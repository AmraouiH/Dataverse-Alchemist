#Requires -Version 7.0
<#
.SYNOPSIS
    Creates a custom table (with its primary name column) in the ticket solution.
.EXAMPLE
    New-DataverseTable.ps1 -SchemaName rhz_Project -DisplayName Project -PluralName Projects -IssueKey CRM-1 -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SchemaName,
    [Parameter(Mandatory)][string]$DisplayName,
    [Parameter(Mandatory)][string]$PluralName,
    [string]$Description,
    [ValidateSet('UserOwned', 'OrganizationOwned')][string]$Ownership = 'UserOwned',
    # Primary name: default schema <prefix>_Name
    [string]$PrimaryNameSchema,
    [string]$PrimaryNameLabel = 'Name',
    [int]$PrimaryNameMaxLength = 100,
    [switch]$HasNotes,
    [switch]$HasActivities,
    [switch]$Publish,
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
$prefix = $solutionInfo.publisher.prefix
$lcid = Get-DataverseBaseLanguage -Environment $dvEnv
Assert-PublisherPrefix -Solution $solutionInfo -Name $SchemaName -What 'SchemaName'
if (-not $PrimaryNameSchema) { $PrimaryNameSchema = "$($prefix)_Name" }
Assert-PublisherPrefix -Solution $solutionInfo -Name $PrimaryNameSchema -What 'PrimaryNameSchema'
$logicalName = $SchemaName.ToLowerInvariant()

$found = @((Invoke-DataverseRequest -Environment $dvEnv -Path "EntityDefinitions?`$select=LogicalName&`$filter=LogicalName eq '$logicalName'").Content.value)
if ($found.Count) { throw "Table '$logicalName' already exists. Nothing was created." }

$body = @{
    '@odata.type'         = 'Microsoft.Dynamics.CRM.EntityMetadata'
    SchemaName            = $SchemaName
    DisplayName           = New-DataverseLabel -Text $DisplayName -LanguageCode $lcid
    DisplayCollectionName = New-DataverseLabel -Text $PluralName -LanguageCode $lcid
    OwnershipType         = $Ownership
    IsActivity            = $false
    HasNotes              = [bool]$HasNotes
    HasActivities         = [bool]$HasActivities
    Attributes            = @(@{
            '@odata.type' = 'Microsoft.Dynamics.CRM.StringAttributeMetadata'
            SchemaName    = $PrimaryNameSchema
            IsPrimaryName = $true
            MaxLength     = $PrimaryNameMaxLength
            FormatName    = @{ Value = 'Text' }
            DisplayName   = New-DataverseLabel -Text $PrimaryNameLabel -LanguageCode $lcid
            RequiredLevel = @{ Value = 'ApplicationRequired'; CanBeChanged = $true; ManagedPropertyLogicalName = 'canmodifyrequirementlevelsettings' }
        })
}
if ($Description) { $body.Description = New-DataverseLabel -Text $Description -LanguageCode $lcid }

if ($DryRun) {
    [ordered]@{
        dryRun = $true; environment = "$($dvEnv.name) ($($dvEnv.url))"; solution = $solutionInfo.uniqueName; table = $logicalName
        displayName = $DisplayName; plural = $PluralName; ownership = $Ownership; primaryName = $PrimaryNameSchema; publish = [bool]$Publish
    } | ConvertTo-Json
    return
}

$tableId = (Invoke-DataverseRequest -Environment $dvEnv -Method POST -Path 'EntityDefinitions' -Body $body -SolutionUniqueName $solutionInfo.uniqueName).EntityId
$status = if (Test-DataverseSolutionComponent -Environment $dvEnv -Solution $solutionInfo -ComponentId $tableId) { 'present' } else { Add-DataverseSolutionComponent -Environment $dvEnv -Solution $solutionInfo -ComponentId $tableId -ComponentType Entity }
$components = @(New-AlchemistComponent -Type Entity -Id $tableId -Name $logicalName -Status $status)
if ($Publish) { Publish-DataverseXml -Environment $dvEnv -Tables @($logicalName) | Out-Null }

Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action 'dataverse.table.create' -Details @{
    environment = $dvEnv.name; table = $logicalName; tableId = $tableId; solution = $solutionInfo.uniqueName; components = $components
}
[ordered]@{ created = $true; table = $logicalName; tableId = $tableId; primaryName = $PrimaryNameSchema.ToLowerInvariant(); solution = $solutionInfo.uniqueName; components = $components; published = [bool]$Publish } | ConvertTo-Json -Depth 5
