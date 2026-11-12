#Requires -Version 7.0
<#
.SYNOPSIS
    Checks the Dataverse Alchemist config: file, secrets, Jira / Dataverse / DevOps connections, git repository, tools.
#>
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string]$Environment,
    [switch]$SkipNetwork
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force

$results = [System.Collections.Generic.List[object]]::new()
function Add-Result([string]$Status, [string]$Check, [string]$Detail) {
    $results.Add([pscustomobject]@{ Status = $Status; Check = $Check; Detail = $Detail })
}

try {
    $config = Get-AlchemistConfig -ConfigPath $ConfigPath
    Add-Result 'OK' 'Config file' $config._meta.path
}
catch {
    Add-Result 'KO' 'Config file' $_.Exception.Message
    $results | Format-Table -AutoSize -Wrap
    exit 1
}

if (Test-Path -LiteralPath $config._meta.localPath) { Add-Result 'OK' 'Local override' $config._meta.localPath }
if ($config._meta.missingSecrets.Count) {
    Add-Result 'KO' 'Environment variables' "Not set: $($config._meta.missingSecrets -join ', ')"
}
else { Add-Result 'OK' 'Environment variables' 'All env: references are resolved' }

$localTickets = Test-AlchemistLocalTickets -Config $config
$requiredSettings = @('dataverse.defaultEnvironment', 'git.defaultBaseBranch') + $(if ($localTickets) { @() } else { @('jira.baseUrl') })
foreach ($required in $requiredSettings) {
    if (Get-AlchemistSetting $config $required) { Add-Result 'OK' "Setting $required" (Get-AlchemistSetting $config $required) }
    else { Add-Result 'KO' "Setting $required" 'missing' }
}

# Local tools
foreach ($tool in @(
        @{ name = 'git'; required = $true },
        @{ name = 'dotnet'; required = $false; usage = 'plugins' },
        @{ name = 'node'; required = $false; usage = 'web resources' },
        @{ name = 'pac'; required = $false; usage = 'solution unpack' },
        @{ name = 'az'; required = $false; usage = 'azcli auth' })) {
    $present = if ($tool.name -eq 'az') { [bool](Get-AzureCliPath) } elseif ($tool.name -eq 'pac') { [bool](Get-PacCliPath) } else { [bool](Get-Command $tool.name -ErrorAction SilentlyContinue) }
    if ($present) { Add-Result 'OK' "Tool $($tool.name)" 'found' }
    elseif ($tool.required) { Add-Result 'KO' "Tool $($tool.name)" 'not found' }
    else { Add-Result 'WARN' "Tool $($tool.name)" "not found (required for: $($tool.usage))" }
}

# Browser tests (Playwright)
if ((Get-AlchemistSetting $config 'testing.ui.enabled' -Default $true) -and (Get-Command node -ErrorAction SilentlyContinue)) {
    $pwDir = Join-Path $PSScriptRoot '..\playwright'
    if (Test-Path (Join-Path $pwDir 'node_modules\@playwright\test')) { Add-Result 'OK' 'Playwright' 'installed' }
    else { Add-Result 'WARN' 'Playwright' "not installed: npm install in $((Resolve-Path $pwDir).Path) (done automatically on the first test)" }
}

# Allowed capabilities
$caps = Get-AlchemistAllowedCapabilities -Config $config
Add-Result 'OK' 'Allowed capabilities' (($caps.Keys | Where-Object { $caps[$_].allowed }) -join ', ')
$off = @($caps.Keys | Where-Object { -not $caps[$_].allowed })
if ($off) { Add-Result 'WARN' 'Capabilities not allowed' "$($off -join ', '): handled as manual" }

# Git repository
Push-Location $config._meta.repoRoot
try {
    $inside = git rev-parse --is-inside-work-tree 2>$null
    if ($inside -eq 'true') {
        Add-Result 'OK' 'Git repository' $config._meta.repoRoot
        $remote = Get-AlchemistSetting $config 'git.remote' -Default 'origin'
        $base = Get-AlchemistSetting $config 'git.defaultBaseBranch' -Default 'develop'
        $refs = @(git branch -a --format='%(refname:short)' 2>$null)
        if ($refs -contains $base -or $refs -contains "$remote/$base") { Add-Result 'OK' 'Default branch' $base }
        else { Add-Result 'WARN' 'Default branch' "'$base' not found locally (git fetch?)" }
    }
    else { Add-Result 'KO' 'Git repository' "$($config._meta.repoRoot) is not a git repository" }
}
finally { Pop-Location }

# Code and documentation paths
foreach ($pathSetting in 'code.plugins.projectPath', 'code.webresources.rootPath', 'docs.localPath') {
    $value = Get-AlchemistSetting $config $pathSetting
    if (-not $value) { continue }
    if (Test-Path -LiteralPath (Join-Path $config._meta.repoRoot $value)) { Add-Result 'OK' $pathSetting $value }
    else { Add-Result 'WARN' $pathSetting "$value not found in the repository" }
}

if (-not $SkipNetwork) {
    try {
        if ($localTickets) {
            Add-Result 'OK' 'Local tickets' "$(@(Read-AlchemistLocalTickets -Config $config).Count) ticket(s) in $(Get-AlchemistLocalTicketsPath -Config $config)"
        }
        else {
            $me = Invoke-JiraRequest -Config $config -Path 'myself'
            Add-Result 'OK' 'Jira connection' "Connected as $($me.displayName)"
        }
    }
    catch { Add-Result 'KO' $(if ($localTickets) { 'Local tickets' } else { 'Jira connection' }) $_.Exception.Message }

    $envNames = if ($Environment) { @($Environment) } else { @((Get-AlchemistSetting $config 'dataverse.environments' -Default @{}).Keys) }
    foreach ($name in $envNames) {
        try {
            $dvEnv = Get-DataverseEnvironment -Config $config -Name $name
            $who = Invoke-DataverseRequest -Environment $dvEnv -Path 'WhoAmI'
            $mode = if ($dvEnv.allowWrite) { 'write allowed' } else { 'read-only' }
            Add-Result 'OK' "Dataverse '$name'" "$($dvEnv.url) — UserId $($who.Content.UserId) — $mode"
            # Default solution offered (the real solution is chosen for each ticket).
            $solution = Get-AlchemistSetting $config 'dataverse.solution.default'
            if ($solution -and $name -eq (Get-AlchemistSetting $config 'dataverse.defaultEnvironment')) {
                try {
                    $info = Get-DataverseSolutionInfo -Environment $dvEnv -UniqueName $solution
                    $status = if ($info.isManaged) { 'WARN' } else { 'OK' }
                    Add-Result $status "Default solution '$solution'" "v$($info.version) — publisher $($info.publisher.uniqueName) (prefix $($info.publisher.prefix)_)$(if ($info.isManaged) { ' — MANAGED: unusable' })"
                }
                catch { Add-Result 'WARN' "Default solution '$solution'" $_.Exception.Message }
            }
        }
        catch { Add-Result 'KO' "Dataverse '$name'" $_.Exception.Message }
    }

    if ((Get-AlchemistSetting $config 'devops.provider') -eq 'azureDevOps') {
        try {
            $base = Get-DevOpsBaseUri -Config $config
            $repo = Get-AlchemistSetting $config 'devops.repository' -Required
            $r = Invoke-DevOpsRequest -Config $config -Uri "$base/_apis/git/repositories/$([Uri]::EscapeDataString($repo))?api-version=7.1"
            Add-Result 'OK' 'Azure DevOps' "Repo $($r.Content.name)"
        }
        catch { Add-Result 'KO' 'Azure DevOps' $_.Exception.Message }
    }
}

$results | Format-Table -AutoSize -Wrap
exit $(if ($results.Status -contains 'KO') { 1 } else { 0 })


