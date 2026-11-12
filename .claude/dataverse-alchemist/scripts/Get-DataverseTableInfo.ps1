#Requires -Version 7.0
<#
.SYNOPSIS
    Summary of a Dataverse table (read-only): metadata, columns, forms, plugin steps.
.EXAMPLE
    pwsh -NoProfile -File Get-DataverseTableInfo.ps1 -Table account -Attributes -Forms -PluginSteps
    pwsh -NoProfile -File Get-DataverseTableInfo.ps1 -Table account -Attributes -AttributeFilter cts_
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Table,
    [switch]$Attributes,
    [string]$AttributeFilter,
    [switch]$CustomOnly,
    [switch]$Forms,
    [switch]$PluginSteps,
    [string]$Environment,
    [string]$ConfigPath,
    [switch]$Json
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force

$config = Get-AlchemistConfig -ConfigPath $ConfigPath
$dvEnv = Get-DataverseEnvironment -Config $config -Name $Environment
$Table = $Table.ToLowerInvariant()
$t = ConvertTo-ODataString $Table

function Get-Label($label) { if ($label -and $label.UserLocalizedLabel) { return $label.UserLocalizedLabel.Label } return $null }

$entity = (Invoke-DataverseRequest -Environment $dvEnv -Path "EntityDefinitions(LogicalName='$t')?`$select=LogicalName,SchemaName,EntitySetName,PrimaryIdAttribute,PrimaryNameAttribute,ObjectTypeCode,DisplayName,IsCustomEntity,MetadataId").Content

$info = [ordered]@{
    logicalName   = $entity.LogicalName
    schemaName    = $entity.SchemaName
    displayName   = Get-Label $entity.DisplayName
    entitySetName = $entity.EntitySetName
    primaryId     = $entity.PrimaryIdAttribute
    primaryName   = $entity.PrimaryNameAttribute
    objectTypeCode = $entity.ObjectTypeCode
    isCustom      = $entity.IsCustomEntity
    metadataId    = $entity.MetadataId
}

if ($Attributes) {
    $attrs = (Invoke-DataverseRequest -Environment $dvEnv -Path "EntityDefinitions(LogicalName='$t')/Attributes?`$select=LogicalName,SchemaName,AttributeType,AttributeTypeName,DisplayName,RequiredLevel,IsCustomAttribute,AttributeOf").Content.value
    $info.attributes = @($attrs |
        Where-Object { -not $_.AttributeOf } |
        Where-Object { -not $CustomOnly -or $_.IsCustomAttribute } |
        Where-Object { -not $AttributeFilter -or $_.LogicalName -like "*$AttributeFilter*" } |
        Sort-Object LogicalName |
        ForEach-Object {
            [ordered]@{
                logicalName = $_.LogicalName
                type        = $_.AttributeTypeName.Value -replace 'Type$', ''
                displayName = Get-Label $_.DisplayName
                required    = $_.RequiredLevel.Value
                custom      = $_.IsCustomAttribute
            }
        })
}

if ($Forms) {
    $formTypes = @{ 2 = 'Main'; 5 = 'Mobile'; 6 = 'QuickView'; 7 = 'QuickCreate'; 11 = 'Card'; 12 = 'MainInteractive' }
    $sysForms = (Invoke-DataverseRequest -Environment $dvEnv -Path "systemforms?`$select=formid,name,type,isdefault,formactivationstate&`$filter=objecttypecode eq '$t'&`$orderby=type,name").Content.value
    $info.forms = @($sysForms | ForEach-Object {
            [ordered]@{ formId = $_.formid; name = $_.name; type = $formTypes[[int]$_.type] ?? $_.type; isDefault = $_.isdefault; active = ($_.formactivationstate -eq 1) }
        })
}

if ($PluginSteps) {
    $stages = @{ 10 = 'PreValidation'; 20 = 'PreOperation'; 40 = 'PostOperation' }
    $steps = (Invoke-DataverseRequest -Environment $dvEnv -Path "sdkmessageprocessingsteps?`$select=name,stage,mode,rank,filteringattributes,statecode&`$expand=sdkmessageid(`$select=name),eventhandler_plugintype(`$select=typename),sdkmessagefilterid(`$select=primaryobjecttypecode)&`$filter=customizationlevel eq 1 and sdkmessagefilterid/primaryobjecttypecode eq '$t'").Content.value
    $info.pluginSteps = @($steps | ForEach-Object {
            [ordered]@{
                name                = $_.name
                message             = $_.sdkmessageid.name
                pluginType          = $_.eventhandler_plugintype.typename
                stage               = $stages[[int]$_.stage] ?? $_.stage
                mode                = if ($_.mode -eq 1) { 'Async' } else { 'Sync' }
                rank                = $_.rank
                filteringAttributes = $_.filteringattributes
                enabled             = ($_.statecode -eq 0)
            }
        })
}

if ($Json) { $info | ConvertTo-Json -Depth 10; return }

"# Table $($info.logicalName) — $($info.displayName)"
"EntitySet: $($info.entitySetName) | PK: $($info.primaryId) | Primary name: $($info.primaryName) | Custom: $($info.isCustom)"
if ($info.Contains('attributes')) {
    "`n## Columns ($($info.attributes.Count))"
    $info.attributes | ForEach-Object { [pscustomobject]$_ } | Format-Table -AutoSize | Out-String -Width 250
}
if ($info.Contains('forms')) {
    "`n## Forms"
    $info.forms | ForEach-Object { [pscustomobject]$_ } | Format-Table -AutoSize | Out-String -Width 250
}
if ($info.Contains('pluginSteps')) {
    "`n## Plugin steps (custom)"
    $info.pluginSteps | ForEach-Object { [pscustomobject]$_ } | Format-Table -AutoSize | Out-String -Width 250
}
