#Requires -Version 7.0
<#
.SYNOPSIS
    Determines the base branch and the name of the new branch for a ticket, according to git.* in the config.
    Requires Get-JiraTicket.ps1 to have run (reads .alchemist/runs/<KEY>/ticket.json).
.OUTPUTS
    JSON: baseBranch, reason, branchName, candidates, existingBranchesForTicket
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$IssueKey,
    [string]$ConfigPath,
    [switch]$NoFetch
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force

$config = Get-AlchemistConfig -ConfigPath $ConfigPath
$IssueKey = $IssueKey.ToUpperInvariant()
$runFolder = Get-AlchemistRunFolder -Config $config -IssueKey $IssueKey
$ticketPath = Join-Path $runFolder 'ticket.json'
if (-not (Test-Path -LiteralPath $ticketPath)) { throw "ticket.json not found. Run Get-JiraTicket.ps1 -IssueKey $IssueKey first." }
$ticket = Get-Content -Raw -LiteralPath $ticketPath | ConvertFrom-Json

$remote = Get-AlchemistSetting $config 'git.remote' -Default 'origin'
$defaultBase = Get-AlchemistSetting $config 'git.defaultBaseBranch' -Default 'develop'
$rules = @(Get-AlchemistSetting $config 'git.baseBranchRules' -Default @())
$pattern = Get-AlchemistSetting $config 'git.branchNamePattern' -Default '{type}/{key}-{slug}'
$typeMapping = Get-AlchemistSetting $config 'git.typeMapping' -Default @{}

Push-Location $config._meta.repoRoot
try {
    if (-not $NoFetch) { git fetch $remote --prune --quiet 2>$null }
    $remoteBranches = @(git branch -r --format='%(refname:short)' 2>$null | ForEach-Object { $_ -replace "^$([regex]::Escape($remote))/", '' })
    $localBranches = @(git branch --format='%(refname:short)' 2>$null)
}
finally { Pop-Location }

function Test-BranchExists([string]$Name) { return ($remoteBranches -contains $Name) -or ($localBranches -contains $Name) }

function Test-Condition($Expected, [string[]]$Actual) {
    $expectedValues = @($Expected)
    if ($expectedValues -contains '*') { return $Actual.Count -gt 0 }
    foreach ($value in $expectedValues) { if ($Actual -contains $value) { return $true } }
    return $false
}

$candidates = [System.Collections.Generic.List[object]]::new()
function Add-Candidate([string]$Branch, [string]$Reason) {
    $candidates.Add([ordered]@{ branch = $Branch; reason = $Reason; exists = (Test-BranchExists $Branch) })
}

if ($ticket.baseBranchHint) { Add-Candidate $ticket.baseBranchHint.Trim() 'Dedicated Jira field (jira.baseBranchField)' }

$index = 0
foreach ($rule in $rules) {
    $index++
    $when = $rule.when ?? @{}
    $matched = $true
    if ($when.issueType -and -not (Test-Condition $when.issueType @($ticket.issueType))) { $matched = $false }
    if ($when.label -and -not (Test-Condition $when.label @($ticket.labels))) { $matched = $false }
    if ($when.component -and -not (Test-Condition $when.component @($ticket.components))) { $matched = $false }
    if ($when.fixVersion -and -not (Test-Condition $when.fixVersion @($ticket.fixVersions))) { $matched = $false }
    if ($when.priority -and -not (Test-Condition $when.priority @($ticket.priority))) { $matched = $false }
    if (-not $matched) { continue }

    $versions = if ($rule.base -match '\{fixVersion\}') { @($ticket.fixVersions) } else { @($null) }
    foreach ($version in $versions) {
        $branch = $rule.base -replace '\{fixVersion\}', $version -replace '\{component\}', (@($ticket.components)[0])
        Add-Candidate $branch "Rule #$index ($($rule.description ?? ($when | ConvertTo-Json -Compress)))"
    }
}
Add-Candidate $defaultBase 'Default branch (git.defaultBaseBranch)'

$chosen = $candidates | Where-Object { $_.exists } | Select-Object -First 1

$type = $typeMapping[$ticket.issueType] ?? 'feature'
$branchName = $pattern -replace '\{type\}', $type -replace '\{key\}', $ticket.key -replace '\{slug\}', (ConvertTo-AlchemistSlug $ticket.summary)

$existingForTicket = @(($remoteBranches + $localBranches) | Where-Object { $_ -match [regex]::Escape($ticket.key) } | Select-Object -Unique)

[ordered]@{
    baseBranch                = $chosen.branch
    reason                    = if ($chosen) { $chosen.reason } else { 'NO candidate branch exists: ask the user' }
    branchName                = $branchName
    existingBranchesForTicket = $existingForTicket
    candidates                = $candidates
} | ConvertTo-Json -Depth 5
