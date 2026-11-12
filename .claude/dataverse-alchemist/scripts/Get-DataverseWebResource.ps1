#Requires -Version 7.0
<#
.SYNOPSIS
    Downloads the current content of a web resource: every change starts from this file, not from a copy in memory.
    Without -OutFile, the file is written to the run folder, under its web resource name.
.EXAMPLE
    Get-DataverseWebResource.ps1 -Name rhz_/js/account.ribbon.js -IssueKey CRM-1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Name,
    [string]$OutFile,
    [string]$IssueKey,
    [string]$Environment,
    [string]$ConfigPath
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force

$config = Get-AlchemistConfig -ConfigPath $ConfigPath
$dvEnv = Get-DataverseEnvironment -Config $config -Name $Environment
$filter = "name eq '$(ConvertTo-ODataString $Name)'"
$found = @((Invoke-DataverseRequest -Environment $dvEnv -Path "webresourceset?`$select=webresourceid,name,content,webresourcetype,ismanaged&`$filter=$filter").Content.value)
if (-not $found) { throw "Web resource not found: $Name" }
# A normal read returns the published version: after an unpublished update, only this function gives the real content.
$draft = (Invoke-DataverseRequest -Environment $dvEnv -Path "webresourceset($($found[0].webresourceid))/Microsoft.Dynamics.CRM.RetrieveUnpublished()").Content
if ($draft.content) { $found[0].content = $draft.content }

if (-not $OutFile) {
    $folder = if ($IssueKey) { Get-AlchemistRunFolder -Config $config -IssueKey $IssueKey } else { [IO.Path]::GetTempPath() }
    $OutFile = Join-Path $folder ($Name -replace '[/\\]', '.')
}
[IO.File]::WriteAllBytes($OutFile, [Convert]::FromBase64String($found[0].content))
[ordered]@{ name = $found[0].name; type = $found[0].webresourcetype; managed = $found[0].ismanaged; file = $OutFile; bytes = (Get-Item -LiteralPath $OutFile).Length } | ConvertTo-Json
