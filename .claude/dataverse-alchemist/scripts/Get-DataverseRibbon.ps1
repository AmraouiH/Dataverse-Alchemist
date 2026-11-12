#Requires -Version 7.0
<#
.SYNOPSIS
    Read-only view of a table ribbon: available locations, custom JS libraries used, and export of the
    current RibbonDiffXml of the table from the ticket solution.
.EXAMPLE
    Get-DataverseRibbon.ps1 -Table account
    Get-DataverseRibbon.ps1 -Table account -ExportDiff account.ribbondiff.xml -IssueKey CRM-1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Table,
    # Writes the current RibbonDiffXml of the table to this file: starting point of any change.
    [string]$ExportDiff,
    [string]$Solution,
    [string]$Environment,
    [string]$ConfigPath,
    [string]$IssueKey
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force

$config = Get-AlchemistConfig -ConfigPath $ConfigPath
$dvEnv = Get-DataverseEnvironment -Config $config -Name $Environment
$Table = $Table.ToLowerInvariant()

$ribbon = [xml](Get-DataverseEntityRibbon -Environment $dvEnv -Table $Table)
$locations = foreach ($scope in 'Form', 'HomepageGrid', 'SubGrid') {
    foreach ($group in $ribbon.SelectNodes("//Tab[@Id='Mscrm.$scope.$Table.MainTab']//Group")) {
        [ordered]@{ scope = $scope; location = "$($group.SelectSingleNode('Controls').GetAttribute('Id'))._children" }
    }
}
# Unmanaged libraries referenced by the ribbon: they are the project's, reuse them before creating one.
$allLibraries = @($ribbon.SelectNodes('//@Library') | ForEach-Object { $_.Value -replace '^\$webresource:', '' } | Select-Object -Unique)
$libraries = @($allLibraries | Where-Object {
        @((Invoke-DataverseRequest -Environment $dvEnv -Path "webresourceset?`$select=name&`$filter=ismanaged eq false and name eq '$(ConvertTo-ODataString $_)'").Content.value).Count
    })

if ($ExportDiff) {
    $solutionInfo = Resolve-AlchemistSolution -Config $config -Environment $dvEnv -Solution $Solution -IssueKey $IssueKey
    $schemaName = (Invoke-DataverseRequest -Environment $dvEnv -Path "EntityDefinitions(LogicalName='$Table')?`$select=SchemaName").Content.SchemaName
    $document = Get-DataverseSolutionCustomizations -Environment $dvEnv -Solution $solutionInfo
    $node = $document.SelectSingleNode("//Entities/Entity[Name='$schemaName' or Name='$Table']/RibbonDiffXml")
    if (-not $node) { throw "Table '$Table' is not in solution '$($solutionInfo.uniqueName)': add it first." }
    [IO.File]::WriteAllText($ExportDiff, $node.OuterXml, [Text.UTF8Encoding]::new($false))
}

[ordered]@{ table = $Table; customLibraries = $libraries; locations = @($locations); exportedDiff = $ExportDiff } | ConvertTo-Json -Depth 4
