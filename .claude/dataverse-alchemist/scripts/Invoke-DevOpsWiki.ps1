#Requires -Version 7.0
<#
.SYNOPSIS
    Reads / lists / updates pages of the configured Azure DevOps wiki (docs.wiki.*).
.EXAMPLE
    Invoke-DevOpsWiki.ps1 -Action List
    Invoke-DevOpsWiki.ps1 -Action Get -PagePath "/CRM/Tables/Compte"
    Invoke-DevOpsWiki.ps1 -Action Set -PagePath "/CRM/Features/CRM-123" -ContentFile page.md -Comment "CRM-123" -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('List', 'Get', 'Set')][string]$Action,
    [string]$PagePath,
    [string]$ContentFile,
    [string]$Comment,
    [string]$ConfigPath,
    [string]$IssueKey,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force

$config = Get-AlchemistConfig -ConfigPath $ConfigPath
$wiki = Get-AlchemistSetting $config 'docs.wiki.name' -Required
$root = Get-AlchemistSetting $config 'docs.wiki.rootPath' -Default '/'
$pagesUri = "$(Get-DevOpsBaseUri -Config $config)/_apis/wiki/wikis/$([Uri]::EscapeDataString($wiki))/pages"

switch ($Action) {
    'List' {
        $path = if ($PagePath) { $PagePath } else { $root }
        $page = (Invoke-DevOpsRequest -Config $config -Uri "$($pagesUri)?path=$([Uri]::EscapeDataString($path))&recursionLevel=full&api-version=7.1").Content
        $paths = [System.Collections.Generic.List[string]]::new()
        function Walk($node) { $paths.Add($node.path); foreach ($child in @($node.subPages)) { if ($child) { Walk $child } } }
        Walk $page
        $paths
    }
    'Get' {
        if (-not $PagePath) { throw '-PagePath is required.' }
        $result = Invoke-DevOpsRequest -Config $config -AllowNotFound -Uri "$($pagesUri)?path=$([Uri]::EscapeDataString($PagePath))&includeContent=true&api-version=7.1"
        if (-not $result) { "Page not found: $PagePath"; return }
        $result.Content.content
    }
    'Set' {
        if (-not $PagePath -or -not $ContentFile) { throw '-PagePath and -ContentFile are required.' }
        $content = Get-Content -Raw -LiteralPath $ContentFile
        $current = Invoke-DevOpsRequest -Config $config -AllowNotFound -Uri "$($pagesUri)?path=$([Uri]::EscapeDataString($PagePath))&api-version=7.1"
        $mode = if ($current) { 'update' } else { 'create' }
        if ($DryRun) { [ordered]@{ dryRun = $true; mode = $mode; page = $PagePath; length = $content.Length } | ConvertTo-Json; return }

        $headers = if ($current) { @{ 'If-Match' = $current.ETag } } else { @{} }
        $uri = "$($pagesUri)?path=$([Uri]::EscapeDataString($PagePath))&api-version=7.1"
        if ($Comment) { $uri += "&comment=$([Uri]::EscapeDataString($Comment))" }
        Invoke-DevOpsRequest -Config $config -Method PUT -Uri $uri -Body @{ content = $content } -Headers $headers | Out-Null
        Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action "wiki.page.$mode" -Details @{ page = $PagePath }
        [ordered]@{ mode = $mode; page = $PagePath } | ConvertTo-Json
    }
}
