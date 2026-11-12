#Requires -Version 7.0
<#
.SYNOPSIS
    Creates or updates a public view (savedquery) in the ticket solution, then publishes the table with -Publish.
.EXAMPLE
    New-DataverseView.ps1 -Table account -Name "Comptes actifs" -Columns name:300,telephone1,rhz_legalrepid:150 `
        -SortColumn name -FilterXml "<filter type='and'><condition attribute='statecode' operator='eq' value='0'/></filter>" -IssueKey CRM-1 -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Table,
    [Parameter(Mandatory)][string]$Name,
    # Columns "name:width" (width 150 by default). The first column carries the link to the record.
    [Parameter(Mandatory)][string[]]$Columns,
    [string]$SortColumn,
    [switch]$SortDescending,
    # Filtre FetchXml complet : <filter>...</filter>
    [string]$FilterXml,
    [string]$Description,
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
$Table = $Table.ToLowerInvariant()

$entity = (Invoke-DataverseRequest -Environment $dvEnv -Path "EntityDefinitions(LogicalName='$Table')?`$select=PrimaryIdAttribute,PrimaryNameAttribute,ObjectTypeCode").Content
$attributes = @{}
foreach ($a in (Invoke-DataverseRequest -Environment $dvEnv -Path "EntityDefinitions(LogicalName='$Table')/Attributes?`$select=LogicalName,AttributeTypeName,IsValidForGrid").Content.value) {
    $attributes[$a.LogicalName] = @{ type = $a.AttributeTypeName.Value; valid = [bool]$a.IsValidForGrid }
}

$viewColumns = @($Columns | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object {
        $parts = $_.Split(':')
        [pscustomobject]@{ name = $parts[0].ToLowerInvariant(); width = if ($parts.Count -gt 1) { [int]$parts[1] } else { 150 } }
    })
foreach ($column in $viewColumns) {
    if (-not $attributes.ContainsKey($column.name)) { throw "Column '$($column.name)' not found on '$Table'." }
    # IsValidForGrid is true for File and Image, but a view cannot show them.
    if (-not $attributes[$column.name].valid -or $attributes[$column.name].type -in 'FileType', 'ImageType') {
        throw "Column '$($column.name)' ($($attributes[$column.name].type)) cannot be used in a view."
    }
}
if ($SortColumn) {
    $SortColumn = $SortColumn.ToLowerInvariant()
    if (-not $attributes.ContainsKey($SortColumn)) { throw "Sort column '$SortColumn' not found on '$Table'." }
}
if ($FilterXml) {
    $filterDoc = [xml]::new()
    $filterDoc.LoadXml($FilterXml)
    if ($filterDoc.DocumentElement.Name -ne 'filter') { throw '-FilterXml must have <filter> as its root.' }
    foreach ($node in $filterDoc.SelectNodes('//condition/@attribute')) {
        if (-not $attributes.ContainsKey($node.Value)) { throw "Filter column '$($node.Value)' not found on '$Table'." }
    }
}

$pk = $entity.PrimaryIdAttribute
$fetchColumns = @($viewColumns.name) + @($pk) | Select-Object -Unique
$fetch = "<fetch version=`"1.0`" output-format=`"xml-platform`" mapping=`"logical`"><entity name=`"$Table`">"
$fetch += ($fetchColumns | ForEach-Object { "<attribute name=`"$_`" />" }) -join ''
if ($SortColumn) { $fetch += "<order attribute=`"$SortColumn`" descending=`"$(([bool]$SortDescending).ToString().ToLowerInvariant())`" />" }
if ($FilterXml) { $fetch += $FilterXml }
$fetch += '</entity></fetch>'

$jump = if ($viewColumns.name -contains $entity.PrimaryNameAttribute) { $entity.PrimaryNameAttribute } else { $viewColumns[0].name }
$layout = "<grid name=`"resultset`" object=`"$($entity.ObjectTypeCode)`" jump=`"$jump`" select=`"1`" icon=`"1`" preview=`"1`"><row name=`"result`" id=`"$pk`">"
$layout += ($viewColumns | ForEach-Object { "<cell name=`"$($_.name)`" width=`"$($_.width)`" />" }) -join ''
$layout += '</row></grid>'

$existing = @((Invoke-DataverseRequest -Environment $dvEnv -Path "savedqueries?`$select=savedqueryid&`$filter=returnedtypecode eq '$Table' and querytype eq 0 and name eq '$(ConvertTo-ODataString $Name)'").Content.value) | Select-Object -First 1
$action = if ($existing) { 'update' } else { 'create' }

if ($DryRun) {
    [ordered]@{
        dryRun = $true; action = $action; environment = "$($dvEnv.name) ($($dvEnv.url))"; solution = $solutionInfo.uniqueName
        table = $Table; view = $Name; fetchxml = $fetch; layoutxml = $layout; publish = [bool]$Publish
    } | ConvertTo-Json
    return
}

$body = @{ name = $Name; fetchxml = $fetch; layoutxml = $layout }
if ($Description) { $body.description = $Description }
if ($existing) {
    $viewId = $existing.savedqueryid
    Save-AlchemistSnapshot -Config $config -IssueKey $IssueKey -Environment $dvEnv -Type SavedQuery -Name "$Table / $Name" -Table $Table -Path "savedqueries($viewId)" -Fields fetchxml, layoutxml
    Invoke-DataverseRequest -Environment $dvEnv -Method PATCH -Path "savedqueries($viewId)" -Body $body | Out-Null
}
else {
    $body.returnedtypecode = $Table
    $body.querytype = 0
    $viewId = (Invoke-DataverseRequest -Environment $dvEnv -Method POST -Path 'savedqueries' -Body $body -SolutionUniqueName $solutionInfo.uniqueName).EntityId
}

$components = @(Add-DataverseTableToSolution -Environment $dvEnv -Solution $solutionInfo -Table $Table)
$components += New-AlchemistComponent -Type SavedQuery -Id $viewId -Name "$Table / $Name" -Status (Add-DataverseSolutionComponent -Environment $dvEnv -Solution $solutionInfo -ComponentId $viewId -ComponentType SavedQuery)
if ($Publish) { Publish-DataverseXml -Environment $dvEnv -Tables @($Table) | Out-Null }

Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action "dataverse.view.$action" -Details @{
    environment = $dvEnv.name; table = $Table; view = $Name; viewId = $viewId; solution = $solutionInfo.uniqueName; components = $components
}
[ordered]@{ action = $action; viewId = $viewId; view = $Name; table = $Table; solution = $solutionInfo.uniqueName; components = $components; published = [bool]$Publish } | ConvertTo-Json -Depth 5
