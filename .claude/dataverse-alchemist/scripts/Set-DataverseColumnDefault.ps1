#Requires -Version 7.0
<#
.SYNOPSIS
    Sets the default value of an existing choice column (DefaultFormValue), by label or value.
    Definitions are updated with a full PUT, and publishing is required. A multi-select choice has no default
    value: the platform does not allow it.
.EXAMPLE
    Set-DataverseColumnDefault.ps1 -Table rhz_contratservice -Column rhz_statutcontrat -Value Brouillon -IssueKey CRM-1 -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Table,
    [Parameter(Mandatory)][string]$Column,
    [Parameter(Mandatory)][string]$Value,
    [string]$Solution,
    [string]$Environment,
    [string]$ConfigPath,
    [string]$IssueKey,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force

$config = Get-AlchemistConfig -ConfigPath $ConfigPath
$dvEnv = Get-DataverseEnvironment -Config $config -Name $Environment
$solutionInfo = Resolve-AlchemistSolution -Config $config -Environment $dvEnv -Solution $Solution -IssueKey $IssueKey
$Table = $Table.ToLowerInvariant()
$Column = $Column.ToLowerInvariant()

$path = "EntityDefinitions(LogicalName='$Table')/Attributes(LogicalName='$Column')"
$cast = "$path/Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
try { $detail = (Invoke-DataverseRequest -Environment $dvEnv -Path "$($cast)?`$select=DefaultFormValue&`$expand=OptionSet,GlobalOptionSet").Content }
catch { throw "'$Table.$Column' is not a single choice: only a single choice has a default value. $($_.Exception.Message)" }

$options = @(($detail.GlobalOptionSet ?? $detail.OptionSet).Options)
$option = $options | Where-Object { "$($_.Value)" -eq $Value -or $_.Label.UserLocalizedLabel.Label -eq $Value -or $_.Label.LocalizedLabels.Label -contains $Value } | Select-Object -First 1
if (-not $option) { throw "Option '$Value' not found. Options: $(@($options | ForEach-Object { "$($_.Value) = $($_.Label.UserLocalizedLabel.Label)" }) -join ' ; ')." }

if ($DryRun) {
    [ordered]@{ dryRun = $true; environment = "$($dvEnv.name) ($($dvEnv.url))"; column = "$Table.$Column"; previous = $detail.DefaultFormValue; value = $option.Value; label = $option.Label.UserLocalizedLabel.Label; solution = $solutionInfo.uniqueName } | ConvertTo-Json
    return
}

Save-AlchemistSnapshot -Config $config -IssueKey $IssueKey -Type ColumnDefault -Name "$Table.$Column" -Table $Table -Path $path -Value $detail.DefaultFormValue
Update-DataverseColumnDefault -Environment $dvEnv -Table $Table -Column $Column -Value $option.Value -SolutionUniqueName $solutionInfo.uniqueName
Publish-DataverseXml -Environment $dvEnv -Tables @($Table) | Out-Null

$saved = (Invoke-DataverseRequest -Environment $dvEnv -Path "$($cast)?`$select=DefaultFormValue,MetadataId").Content
if ($saved.DefaultFormValue -ne $option.Value) { throw "Default value read back: $($saved.DefaultFormValue), expected: $($option.Value)." }
$components = @(New-AlchemistComponent -Type Attribute -Id $saved.MetadataId -Name "$Table.$Column" -Status 'present')
Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action 'dataverse.column.update' -Details @{ environment = $dvEnv.name; table = $Table; column = $Column; defaultValue = $option.Value; solution = $solutionInfo.uniqueName; components = $components }
[ordered]@{ updated = $true; column = "$Table.$Column"; defaultValue = $option.Value; label = $option.Label.UserLocalizedLabel.Label; published = $true } | ConvertTo-Json
