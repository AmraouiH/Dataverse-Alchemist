#Requires -Version 7.0
<#
.SYNOPSIS
    Validates a RibbonDiffXml then applies it to a table through the ticket solution (export, replace, import, publish).

.DESCRIPTION
    The file replaces the WHOLE RibbonDiffXml of the table: start from Get-DataverseRibbon.ps1 -ExportDiff.
    Checks before import: ids prefixed by the publisher and unique, locations present in the real ribbon, commands
    and rules defined, labels defined, existing web resources, each JavaScript function present in its web resource.
    Check after import: buttons and commands present in the published ribbon.
.EXAMPLE
    Import-DataverseRibbon.ps1 -Table account -RibbonDiffXmlPath account.ribbondiff.xml -IssueKey CRM-1 -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Table,
    [Parameter(Mandatory)][string]$RibbonDiffXmlPath,
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
$prefix = $solutionInfo.publisher.prefix

$diff = [xml]::new()
$diff.PreserveWhitespace = $false
$diff.Load((Resolve-Path -LiteralPath $RibbonDiffXmlPath).Path)
if ($diff.DocumentElement.Name -ne 'RibbonDiffXml') { throw "The root must be <RibbonDiffXml>." }

$problems = [System.Collections.Generic.List[string]]::new()

# Ids: publisher prefix and uniqueness.
$idNodes = @($diff.SelectNodes('//CustomAction/@Id | //Button/@Id | //FlyoutAnchor/@Id | //SplitButton/@Id | //Menu/@Id | //MenuSection/@Id | //Controls/@Id | //CommandDefinition/@Id | //RuleDefinitions//EnableRule/@Id | //RuleDefinitions//DisplayRule/@Id | //LocLabel/@Id'))
foreach ($node in $idNodes) {
    if (-not $node.Value.StartsWith("$prefix.", [StringComparison]::OrdinalIgnoreCase)) { $problems.Add("Id without the '$prefix.' prefix: $($node.Value)") }
}
foreach ($group in ($idNodes | Group-Object Value | Where-Object Count -gt 1)) { $problems.Add("Duplicate id: $($group.Name)") }

# Locations: must exist in the real ribbon of the table.
$ribbonText = Get-DataverseEntityRibbon -Environment $dvEnv -Table $Table
$ribbon = [xml]$ribbonText
$controlIds = @{}
foreach ($node in $ribbon.SelectNodes('//Controls/@Id')) { $controlIds[$node.Value] = $true }
foreach ($node in $diff.SelectNodes('//CustomAction/@Location')) {
    $location = $node.Value -replace '\._children$', ''
    if (-not $controlIds.ContainsKey($location)) { $problems.Add("Location missing from the '$Table' ribbon: $($node.Value)") }
    elseif (-not $node.Value.EndsWith('._children')) { $problems.Add("Location without ._children: $($node.Value)") }
}

# Commands and rules.
$commands = @($diff.SelectNodes('//CommandDefinition/@Id') | ForEach-Object Value)
foreach ($node in $diff.SelectNodes('//CommandUIDefinition//@Command')) {
    if ($commands -notcontains $node.Value -and -not $node.Value.StartsWith('Mscrm.')) { $problems.Add("Command not defined: $($node.Value)") }
}
$enableRules = @($diff.SelectNodes('//RuleDefinitions/EnableRules/EnableRule/@Id') | ForEach-Object Value)
$displayRules = @($diff.SelectNodes('//RuleDefinitions/DisplayRules/DisplayRule/@Id') | ForEach-Object Value)
foreach ($node in $diff.SelectNodes('//CommandDefinition/EnableRules/EnableRule/@Id')) {
    if ($enableRules -notcontains $node.Value -and -not $node.Value.StartsWith('Mscrm.')) { $problems.Add("Enable rule not defined: $($node.Value)") }
}
foreach ($node in $diff.SelectNodes('//CommandDefinition/DisplayRules/DisplayRule/@Id')) {
    if ($displayRules -notcontains $node.Value -and -not $node.Value.StartsWith('Mscrm.')) { $problems.Add("Display rule not defined: $($node.Value)") }
}

# Labels.
$labels = @($diff.SelectNodes('//LocLabel/@Id') | ForEach-Object Value)
foreach ($node in $diff.SelectNodes('//@*[starts-with(., "$LocLabels:")]')) {
    $id = $node.Value.Substring('$LocLabels:'.Length)
    if ($labels -notcontains $id) { $problems.Add("Label not defined: $id") }
}

# Web resources and JavaScript functions.
$checkedFunctions = 0
$webResources = @{}
function Get-WebResourceText([string]$WebResourceName) {
    if (-not $webResources.ContainsKey($WebResourceName)) {
        $found = @((Invoke-DataverseRequest -Environment $dvEnv -Path "webresourceset?`$select=content&`$filter=name eq '$(ConvertTo-ODataString $WebResourceName)'").Content.value) | Select-Object -First 1
        $webResources[$WebResourceName] = if ($found) { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($found.content)) } else { $null }
    }
    return $webResources[$WebResourceName]
}
foreach ($node in $diff.SelectNodes('//*[@Library and @FunctionName]')) {
    $library = $node.GetAttribute('Library') -replace '^\$webresource:', ''
    $function = $node.GetAttribute('FunctionName')
    $source = Get-WebResourceText $library
    if ($null -eq $source) { $problems.Add("Web resource not found: $library"); continue }
    $member = $function.Split('.')[-1]
    if ($source -notmatch "\b$([regex]::Escape($member))\b") { $problems.Add("Function '$function' missing from $library") }
    foreach ($segment in $function.Split('.')[0..($function.Split('.').Count - 2)]) {
        if ($function.Contains('.') -and $source -notmatch "\b$([regex]::Escape($segment))\b") { $problems.Add("Namespace '$segment' missing from $library") }
    }
    $checkedFunctions++
}
foreach ($node in $diff.SelectNodes('//@*[starts-with(., "$webresource:")]')) {
    $name = $node.Value.Substring('$webresource:'.Length)
    if ($node.Name -eq 'Library') { continue }
    if (-not @((Invoke-DataverseRequest -Environment $dvEnv -Path "webresourceset?`$select=name&`$filter=name eq '$(ConvertTo-ODataString $name)'").Content.value).Count) { $problems.Add("Web resource not found: $name") }
}

if ($problems.Count) { throw "Invalid RibbonDiffXml:`n - $(@($problems | Select-Object -Unique) -join "`n - ")" }

$buttonIds = @($diff.SelectNodes('//CommandUIDefinition//Button/@Id | //CommandUIDefinition//FlyoutAnchor/@Id | //CommandUIDefinition//SplitButton/@Id') | ForEach-Object Value)

if ($DryRun) {
    [ordered]@{
        dryRun = $true; environment = "$($dvEnv.name) ($($dvEnv.url))"; solution = $solutionInfo.uniqueName; table = $Table
        controls = $buttonIds; commands = $commands.Count; enableRules = $enableRules.Count; functionsChecked = $checkedFunctions
        note = 'The solution will be exported, the table RibbonDiffXml replaced, then the solution re-imported and the table published.'
    } | ConvertTo-Json -Depth 4
    return
}

$components = @(Add-DataverseTableToSolution -Environment $dvEnv -Solution $solutionInfo -Table $Table)
$schemaName = (Invoke-DataverseRequest -Environment $dvEnv -Path "EntityDefinitions(LogicalName='$Table')?`$select=SchemaName").Content.SchemaName

$restoredStates = Update-DataverseSolutionCustomizations -Environment $dvEnv -Solution $solutionInfo -Patch {
    param($document)
    $entity = $document.SelectSingleNode("//Entities/Entity[Name='$schemaName' or Name='$Table']")
    if (-not $entity) { throw "Table '$Table' missing from the exported solution." }
    $imported = $document.ImportNode($diff.DocumentElement, $true)
    $current = $entity.SelectSingleNode('RibbonDiffXml')
    Save-AlchemistSnapshot -Config $config -IssueKey $IssueKey -Type Ribbon -Name $Table -Table $Table -Xml ($current ? $current.OuterXml : '<RibbonDiffXml />')
    if ($current) { [void]$entity.ReplaceChild($imported, $current) } else { [void]$entity.AppendChild($imported) }
}
if ($restoredStates) { Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action 'dataverse.states.restored' -Details @{ environment = $dvEnv.name; restored = $restoredStates } }
Publish-DataverseXml -Environment $dvEnv -Tables @($Table) | Out-Null

$published = Get-DataverseEntityRibbon -Environment $dvEnv -Table $Table
$missing = @(@($buttonIds) + @($commands) | Where-Object { -not $published.Contains("`"$_`"") })
if ($missing) { throw "Missing from the published ribbon: $($missing -join ', ')." }

Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action 'dataverse.ribbon.update' -Details @{
    environment = $dvEnv.name; table = $Table; controls = $buttonIds; solution = $solutionInfo.uniqueName; components = $components
}
[ordered]@{ updated = $true; table = $Table; controls = $buttonIds; commands = $commands.Count; functionsChecked = $checkedFunctions; solution = $solutionInfo.uniqueName } | ConvertTo-Json -Depth 4
