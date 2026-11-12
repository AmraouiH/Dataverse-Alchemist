#Requires -Version 7.0
<#
.SYNOPSIS
    Lists the unmanaged solutions of the environment with their publisher (prefix, choice value prefix).
    Used to offer the user the target solution of a ticket.
.EXAMPLE
    Get-DataverseSolutions.ps1
    Get-DataverseSolutions.ps1 -Filter vente -Json
#>
[CmdletBinding()]
param(
    [string]$Filter,
    [string]$Environment,
    [string]$ConfigPath,
    [switch]$Json
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force

$config = Get-AlchemistConfig -ConfigPath $ConfigPath
$dvEnv = Get-DataverseEnvironment -Config $config -Name $Environment
$default = Get-AlchemistSetting $config 'dataverse.solution.default'

$query = "solutions?`$select=uniquename,friendlyname,version,modifiedon" +
    "&`$expand=publisherid(`$select=uniquename,customizationprefix,customizationoptionvalueprefix)" +
    "&`$filter=ismanaged eq false and isvisible eq true&`$orderby=modifiedon desc"
$solutions = @((Invoke-DataverseRequest -Environment $dvEnv -Path $query).Content.value |
    Where-Object { -not $Filter -or $_.uniquename -like "*$Filter*" -or $_.friendlyname -like "*$Filter*" } |
    ForEach-Object {
        $warning = $null
        if ($_.uniquename -eq 'Default' -or $_.publisherid.uniquename -like 'DefaultPublisher*' -or $_.publisherid.customizationprefix -eq 'new') {
            $warning = 'default solution/publisher: avoid'
        }
        [ordered]@{
            uniqueName        = $_.uniquename
            name              = $_.friendlyname
            version           = $_.version
            publisher         = $_.publisherid.uniquename
            prefix            = $_.publisherid.customizationprefix
            optionValuePrefix = $_.publisherid.customizationoptionvalueprefix
            modifiedOn        = $_.modifiedon
            isConfigDefault   = ($_.uniquename -eq $default)
            warning           = $warning
        }
    })

if ($Json) { $solutions | ConvertTo-Json -Depth 4; return }
$solutions | ForEach-Object { [pscustomobject]$_ } |
    Format-Table uniqueName, name, version, publisher, prefix, optionValuePrefix, isConfigDefault, warning -AutoSize | Out-String -Width 250
