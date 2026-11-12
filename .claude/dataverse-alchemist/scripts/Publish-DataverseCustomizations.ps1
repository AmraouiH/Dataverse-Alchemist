#Requires -Version 7.0
<#
.SYNOPSIS
    Publishes customizations: targeted tables and/or web resources, or everything (-All).
.EXAMPLE
    Publish-DataverseCustomizations.ps1 -Tables account,contact
#>
[CmdletBinding()]
param(
    [string[]]$Tables,
    [string[]]$WebResourceIds,
    [string[]]$OptionSets,
    [switch]$All,
    [string]$Environment,
    [string]$ConfigPath,
    [string]$IssueKey
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force

$config = Get-AlchemistConfig -ConfigPath $ConfigPath
$dvEnv = Get-DataverseEnvironment -Config $config -Name $Environment
$split = { param($values) @($values | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }

if ($All) {
    Invoke-DataverseRequest -Environment $dvEnv -Method POST -Path 'PublishAllXml' | Out-Null
    $published = 'PublishAllXml'
}
else {
    if (-not ($Tables -or $WebResourceIds -or $OptionSets)) { throw "Nothing to publish: specify -Tables, -WebResourceIds, -OptionSets or -All." }
    $published = Publish-DataverseXml -Environment $dvEnv -Tables (& $split $Tables) -WebResourceIds (& $split $WebResourceIds) -OptionSets (& $split $OptionSets)
}
Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action 'dataverse.publish' -Details @{ environment = $dvEnv.name; parameterXml = $published }
[ordered]@{ published = $published } | ConvertTo-Json
