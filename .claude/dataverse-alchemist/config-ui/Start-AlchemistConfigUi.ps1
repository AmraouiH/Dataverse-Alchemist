#Requires -Version 7.0
<#
.SYNOPSIS
    Local configuration web page of the Dataverse Alchemist agent:
    permissions, Dataverse connection, tickets (Jira / local), git and DevOps.
.DESCRIPTION
    The shared config is .alchemist/alchemist.config.json (committed).
    Secrets entered in plain text go to .alchemist/alchemist.config.local.json (git-ignored),
    which the agent merges at load time. env:VARIABLE references stay in the shared config.
    If there is no config yet, it is created from the minimal template.
.EXAMPLE
    pwsh .claude/dataverse-alchemist/config-ui/Start-AlchemistConfigUi.ps1   (from the root of the CRM project)
#>
param(
    [int]$Port = 4874,
    # Default: .alchemist/alchemist.config.json of the current CRM project (searched upwards from the current folder)
    [string]$ConfigPath,
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'
$TestScript = Join-Path $PSScriptRoot '..\scripts\Test-AlchemistConfig.ps1'
if (-not $ConfigPath) {
    Import-Module (Join-Path $PSScriptRoot '..\scripts\AlchemistCommon.psm1') -Force
    try { $ConfigPath = Get-AlchemistConfigPath } catch { $ConfigPath = Join-Path (Get-Location).Path '.alchemist\alchemist.config.json' }
}
if (-not (Test-Path -LiteralPath $ConfigPath)) {
    New-Item -ItemType Directory -Force -Path (Split-Path $ConfigPath) | Out-Null
    Copy-Item (Join-Path $PSScriptRoot '..\config\alchemist.config.minimal.json') $ConfigPath
    Write-Host "Config created from the minimal template: $ConfigPath"
}
$ConfigPath = (Resolve-Path $ConfigPath).Path
$LocalPath = $ConfigPath -replace '\.json$', '.local.json'
$htmlPath = Join-Path $PSScriptRoot 'index.html'
$prefix = "http://localhost:$Port/"
$utf8 = [Text.UTF8Encoding]::new($false)

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add($prefix)
$listener.Start()
Write-Host "Alchemist config: $prefix"
Write-Host "  shared: $ConfigPath"
Write-Host "  local:  $LocalPath"
Write-Host "Keep this terminal open; Ctrl+C to stop."
if (-not $NoBrowser) { Start-Process $prefix }

function Send($ctx, [int]$status, [string]$body, [string]$type) {
    $bytes = $utf8.GetBytes($body)
    $ctx.Response.StatusCode = $status
    $ctx.Response.ContentType = "$type; charset=utf-8"
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $ctx.Response.Close()
}

function Write-Json([string]$path, $value) {
    if (Test-Path $path) { Copy-Item $path "$path.bak" -Force }
    [IO.File]::WriteAllText($path, ($value | ConvertTo-Json -Depth 50), $utf8)
}

try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        $req = $ctx.Request
        try {
            switch ("$($req.HttpMethod) $($req.Url.AbsolutePath)") {
                'GET /' { Send $ctx 200 (Get-Content $htmlPath -Raw -Encoding UTF8) 'text/html' }
                'GET /api/config' {
                    $config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
                    $local = if (Test-Path $LocalPath) { Get-Content $LocalPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { [pscustomobject]@{} }
                    Send $ctx 200 (@{ config = $config; local = $local } | ConvertTo-Json -Depth 50) 'application/json'
                }
                'POST /api/config' {
                    $body = [IO.StreamReader]::new($req.InputStream, $utf8).ReadToEnd() | ConvertFrom-Json
                    if (-not $body.config.dataverse -or -not $body.config.project) { throw 'Incomplete config, write refused.' }
                    Write-Json $ConfigPath $body.config
                    $localProps = @($body.local.PSObject.Properties)
                    if ($localProps.Count) { Write-Json $LocalPath $body.local }
                    elseif (Test-Path $LocalPath) { Write-Json $LocalPath ([pscustomobject]@{}) }
                    Send $ctx 200 '{"ok":true}' 'application/json'
                }
                'POST /api/test' {
                    $out = & pwsh -NoProfile -File $TestScript -ConfigPath $ConfigPath 2>&1 | Out-String -Width 200
                    Send $ctx 200 (@{ ok = ($LASTEXITCODE -eq 0); output = $out } | ConvertTo-Json) 'application/json'
                }
                default { Send $ctx 404 'Not found' 'text/plain' }
            }
        } catch {
            Send $ctx 400 (@{ ok = $false; error = $_.Exception.Message } | ConvertTo-Json) 'application/json'
        }
    }
} finally {
    $listener.Stop()
}


