#Requires -Version 7.0
<#
.SYNOPSIS
    Creates an alternate key (uniqueness on one or more columns) in the ticket solution,
    after checking that no duplicate prevents the index from being created, then waits for the index to be active.
.EXAMPLE
    New-DataverseAlternateKey.ps1 -Table account -SchemaName rhz_CodeInterneKey -DisplayName "Code interne" -Columns rhz_codeinterne -IssueKey CRM-1 -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Table,
    [Parameter(Mandatory)][string]$SchemaName,
    [Parameter(Mandatory)][string]$DisplayName,
    [Parameter(Mandatory)][string[]]$Columns,
    [int]$TimeoutSeconds = 300,
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
$columnList = @($Columns | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
$logicalName = $SchemaName.ToLowerInvariant()
Assert-PublisherPrefix -Name $SchemaName -Solution $solutionInfo -What 'Key'

$meta = (Invoke-DataverseRequest -Environment $dvEnv -Path "EntityDefinitions(LogicalName='$Table')?`$select=EntitySetName,PrimaryIdAttribute&`$expand=Keys(`$select=LogicalName,KeyAttributes,EntityKeyIndexStatus)").Content
$same = @($meta.Keys | Where-Object { -not (Compare-Object @($_.KeyAttributes) $columnList) })
if ($same) { throw "A key already exists on these columns: $($same[0].LogicalName) ($($same[0].EntityKeyIndexStatus))." }
if (@($meta.Keys | Where-Object LogicalName -EQ $logicalName)) { throw "Key $logicalName already exists on $Table." }

# Existing duplicates: the index would fail (Failed status). FetchXml aggregate on non-empty values.
$groupBy = ($columnList | ForEach-Object { "<attribute name='$_' alias='$_' groupby='true'/>" }) -join ''
$notNull = ($columnList | ForEach-Object { "<condition attribute='$_' operator='not-null'/>" }) -join ''
$fetch = "<fetch aggregate='true'><entity name='$Table'>$groupBy<attribute name='$($meta.PrimaryIdAttribute)' alias='n' aggregate='count'/><filter>$notNull</filter></entity></fetch>"
$groups = @((Invoke-DataverseRequest -Environment $dvEnv -Path "$($meta.EntitySetName)?fetchXml=$([uri]::EscapeDataString($fetch))").Content.value)
$duplicates = @($groups | Where-Object { $_.n -gt 1 } | ForEach-Object { $g = $_; (($columnList | ForEach-Object { $g.$_ }) -join ' / ') + " ($($g.n))" })

if ($DryRun) {
    [ordered]@{ dryRun = $true; environment = "$($dvEnv.name) ($($dvEnv.url))"; solution = $solutionInfo.uniqueName; table = $Table; key = $logicalName; columns = $columnList; duplicates = $duplicates } | ConvertTo-Json
    return
}
if ($duplicates) { throw "Existing duplicates, the index could not be created: $($duplicates -join ', ')." }

$lcid = Get-DataverseBaseLanguage -Environment $dvEnv
$body = @{
    '@odata.type' = 'Microsoft.Dynamics.CRM.EntityKeyMetadata'
    SchemaName    = $SchemaName
    DisplayName   = New-DataverseLabel -Text $DisplayName -LanguageCode $lcid
    KeyAttributes = $columnList
}
Invoke-DataverseRequest -Environment $dvEnv -Method POST -Path "EntityDefinitions(LogicalName='$Table')/Keys" -Body $body -SolutionUniqueName $solutionInfo.uniqueName | Out-Null

# The index is built by a system job: Pending -> InProgress -> Active (or Failed).
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
do {
    Start-Sleep -Seconds 5
    $key = (Invoke-DataverseRequest -Environment $dvEnv -Path "EntityDefinitions(LogicalName='$Table')/Keys(LogicalName='$logicalName')?`$select=MetadataId,EntityKeyIndexStatus").Content
} while ($key.EntityKeyIndexStatus -in 'Pending', 'InProgress' -and (Get-Date) -lt $deadline)

$status = Add-DataverseSolutionComponent -Environment $dvEnv -Solution $solutionInfo -ComponentId $key.MetadataId -ComponentType EntityKey
$components = @(New-AlchemistComponent -Type EntityKey -Id $key.MetadataId -Name "$Table.$logicalName" -Status $status)
Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action 'dataverse.key.create' -Details @{
    environment = $dvEnv.name; table = $Table; key = $logicalName; columns = $columnList; indexStatus = $key.EntityKeyIndexStatus; solution = $solutionInfo.uniqueName; components = $components
}
if ($key.EntityKeyIndexStatus -ne 'Active') { throw "Key created but index '$($key.EntityKeyIndexStatus)' after $TimeoutSeconds s (Failed: run ReactivateEntityKey again after fixing the duplicates)." }
[ordered]@{ created = $true; table = $Table; key = $logicalName; columns = $columnList; indexStatus = $key.EntityKeyIndexStatus; components = $components } | ConvertTo-Json -Depth 4
