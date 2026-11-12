#Requires -Version 7.0
<#
.SYNOPSIS
    Reads Dataverse with GET only, no other method possible: this is the read allowed at every step.
    Invoke-Dataverse stays reserved for writes, because a permission rule cannot exclude -Method POST there.
.EXAMPLE
    Get-DataverseData.ps1 -Path 'GlobalOptionSetDefinitions(Name=''rhz_statut'')'
    Get-DataverseData.ps1 -Path 'accounts?$select=name&$top=5' -OutFile .alchemist/runs/CRM-1/accounts.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [string]$OutFile,
    [string]$Environment,
    [string]$ConfigPath
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force

$config = Get-AlchemistConfig -ConfigPath $ConfigPath
$dvEnv = Get-DataverseEnvironment -Config $config -Name $Environment
$json = (Invoke-DataverseRequest -Environment $dvEnv -Path $Path).Content | ConvertTo-Json -Depth 20

if ($OutFile) {
    $json | Set-Content -LiteralPath $OutFile -Encoding utf8
    "Written to: $OutFile"
}
else { $json }
