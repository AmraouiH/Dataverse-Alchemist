#Requires -Version 7.0
<#
.SYNOPSIS
    Installs (or updates) the Dataverse Alchemist agent in the repository of a CRM project.

.DESCRIPTION
    Copies into <Target>/.claude/ the files listed in .claude/dataverse-alchemist/installed-files.txt:
    commands, agents, skills, scripts, config templates, Playwright tooling and config page.
    - Never touches the project config if it exists; otherwise creates .alchemist/alchemist.config.json from the
      minimal template (to complete with the config page or SETUP.md).
    - Adds the agent's local data (runs, secrets, browser session) to the project .gitignore.
    - Update: files of a previous version that are no longer part of the agent are deleted, only
        if they were in the old manifest (a file added by the team is never deleted).
    -DryRun shows what would be done.
.EXAMPLE
    ./Install-DataverseAlchemist.ps1 -Target D:\Repos\MonCRM
    ./Install-DataverseAlchemist.ps1 -Target D:\Repos\MonCRM -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Target,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'

$source = Join-Path $PSScriptRoot '.claude'
$manifestPath = Join-Path $source 'dataverse-alchemist/installed-files.txt'
$files = @(Get-Content -LiteralPath $manifestPath | Where-Object { $_.Trim() })
$version = (Get-Content -Raw (Join-Path $source 'dataverse-alchemist/VERSION')).Trim()
if (-not (Test-Path -LiteralPath $Target)) { throw "Target folder not found: $Target" }
$Target = (Resolve-Path -LiteralPath $Target).Path
if ($Target -eq $PSScriptRoot) { throw 'The target is the agent repository itself.' }
$destRoot = Join-Path $Target '.claude'

# Files of a previous version that are no longer part of the agent
$oldManifest = Join-Path $destRoot 'dataverse-alchemist/installed-files.txt'
$obsolete = @()
if (Test-Path -LiteralPath $oldManifest) {
    $obsolete = @(Get-Content -LiteralPath $oldManifest | Where-Object { $_.Trim() -and $_ -notin $files } | Where-Object { Test-Path -LiteralPath (Join-Path $destRoot $_) })
}

$actions = [System.Collections.Generic.List[string]]::new()
foreach ($rel in $files + 'dataverse-alchemist/installed-files.txt') {
    $from = Join-Path $source $rel
    $to = Join-Path $destRoot $rel
    $actions.Add("copy   .claude/$rel")
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force -Path (Split-Path $to) | Out-Null
        Copy-Item -LiteralPath $from -Destination $to -Force
    }
}
foreach ($rel in $obsolete) {
    $actions.Add("remove .claude/$rel (no longer in the agent)")
    if (-not $DryRun) { Remove-Item -LiteralPath (Join-Path $destRoot $rel) -Force }
}

# Project config: created only if missing
$configPath = Join-Path $Target '.alchemist/alchemist.config.json'
if (-not (Test-Path -LiteralPath $configPath)) {
    $actions.Add('create .alchemist/alchemist.config.json (minimal template, to complete)')
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force -Path (Split-Path $configPath) | Out-Null
        Copy-Item (Join-Path $source 'dataverse-alchemist/config/alchemist.config.minimal.json') $configPath
    }
}

# Project .gitignore
$ignore = @('.alchemist/runs/', '.alchemist/*.local.json', '.alchemist/playwright/', '.claude/dataverse-alchemist/playwright/node_modules/')
$gitignore = Join-Path $Target '.gitignore'
$existing = if (Test-Path -LiteralPath $gitignore) { @(Get-Content -LiteralPath $gitignore) } else { @() }
$missing = @($ignore | Where-Object { $_ -notin $existing })
if ($missing) {
    $actions.Add(".gitignore: add $($missing -join ', ')")
    if (-not $DryRun) { Add-Content -LiteralPath $gitignore -Value (@('', '# Dataverse Alchemist') + $missing) -Encoding utf8 }
}

[ordered]@{
    version   = $version
    target    = $Target
    dryRun    = [bool]$DryRun
    copied    = $files.Count
    obsolete  = $obsolete.Count
    nextSteps = @(
        'Open the project in Claude Code',
        '/alchemist-init (or pwsh .claude/dataverse-alchemist/config-ui/Start-AlchemistConfigUi.ps1) to complete the config',
        '/alchemist-check to check the connections',
        '/alchemist-ticket <KEY> to deliver a ticket'
    )
} | ConvertTo-Json
if ($DryRun) { $actions | ForEach-Object { "  $_" } }
