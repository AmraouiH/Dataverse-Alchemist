#Requires -Version 7.0
<#
.SYNOPSIS
    Creates a pull request (Azure DevOps through REST, GitHub through gh) according to devops.provider.
    Action visible to the team: only run it after explicit user approval.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourceBranch,
    [Parameter(Mandatory)][string]$TargetBranch,
    [Parameter(Mandatory)][string]$Title,
    [Parameter(Mandatory)][string]$DescriptionFile,
    [switch]$Draft,
    [string]$ConfigPath,
    [string]$IssueKey,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force

$config = Get-AlchemistConfig -ConfigPath $ConfigPath
$provider = Get-AlchemistSetting $config 'devops.provider' -Default 'none'
$description = Get-Content -Raw -LiteralPath $DescriptionFile

if ($DryRun) {
    [ordered]@{ dryRun = $true; provider = $provider; source = $SourceBranch; target = $TargetBranch; title = $Title; draft = [bool]$Draft; description = $description } | ConvertTo-Json
    return
}

switch ($provider) {
    'azureDevOps' {
        $repo = Get-AlchemistSetting $config 'devops.repository' -Required
        $uri = "$(Get-DevOpsBaseUri -Config $config)/_apis/git/repositories/$([Uri]::EscapeDataString($repo))/pullrequests?api-version=7.1"
        $body = @{
            sourceRefName = "refs/heads/$SourceBranch"
            targetRefName = "refs/heads/$TargetBranch"
            title         = $Title
            description   = if ($description.Length -gt 4000) { $description.Substring(0, 3990) + "`n…" } else { $description }
            isDraft       = [bool]$Draft
        }
        $reviewers = @(Get-AlchemistSetting $config 'devops.defaultReviewerIds' -Default @())
        if ($reviewers.Count) { $body.reviewers = @($reviewers | ForEach-Object { @{ id = $_ } }) }
        $pr = (Invoke-DevOpsRequest -Config $config -Method POST -Uri $uri -Body $body).Content
        $url = "$(Get-DevOpsBaseUri -Config $config)/_git/$([Uri]::EscapeDataString($repo))/pullrequest/$($pr.pullRequestId)"
        $id = $pr.pullRequestId
    }
    'github' {
        $ghArgs = @('pr', 'create', '--base', $TargetBranch, '--head', $SourceBranch, '--title', $Title, '--body-file', $DescriptionFile)
        if ($Draft) { $ghArgs += '--draft' }
        Push-Location $config._meta.repoRoot
        try { $url = (& gh @ghArgs | Select-Object -Last 1) } finally { Pop-Location }
        if ($LASTEXITCODE) { throw "gh pr create failed." }
        $id = ($url -split '/')[-1]
    }
    default { throw "devops.provider='$provider': PR creation not supported (azureDevOps | github)." }
}

Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action 'pullrequest.create' -Details @{ provider = $provider; id = $id; url = $url }
[ordered]@{ created = $true; provider = $provider; id = $id; url = $url } | ConvertTo-Json
