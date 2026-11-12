#Requires -Version 7.0
<#
.SYNOPSIS
    Adds tables to an existing model-driven app: navigation entry, active forms and views,
    table declaration (through the ticket solution, the only method that works), publishing and check.
.EXAMPLE
    Add-DataverseAppTable.ps1 -AppUniqueName rhz_Ventes -Tables rhz_servicerequest -GroupTitle Service -IssueKey CRM-1 -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AppUniqueName,
    [Parameter(Mandatory)][string[]]$Tables,
    # Navigation group: reused if it exists, created otherwise.
    [Parameter(Mandatory)][string]$GroupTitle,
    # Custom subarea titles: "rhz_servicecontract=Service contracts". Also applies to an existing subarea.
    [string[]]$SubAreaTitles,
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
$tableList = @($Tables | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })

$app = @((Invoke-DataverseRequest -Environment $dvEnv -Path "appmodules?`$select=appmoduleid,clienttype&`$filter=uniquename eq '$AppUniqueName'").Content.value) | Select-Object -First 1
if (-not $app) { throw "App '$AppUniqueName' not found (or never published)." }
$appId = $app.appmoduleid
$current = @((Invoke-DataverseRequest -Environment $dvEnv -Path "RetrieveAppComponents(AppModuleId=$appId)").Content.value)
$siteMapId = @($current | Where-Object componenttype -eq 62)[0].objectid
if (-not $siteMapId) { throw "App without a sitemap." }
$declared = @($current | Where-Object componenttype -eq 1 | ForEach-Object { (Invoke-DataverseRequest -Environment $dvEnv -Path "EntityDefinitions($($_.objectid))?`$select=LogicalName").Content.LogicalName })

$map = [xml]::new()
$map.LoadXml((Invoke-DataverseRequest -Environment $dvEnv -Path "sitemaps($siteMapId)?`$select=sitemapxml").Content.sitemapxml)
$area = $map.SelectSingleNode('//Area')
$groupNode = @($map.SelectNodes('//Group') | Where-Object { $_.GetAttribute('Title') -eq $GroupTitle }) | Select-Object -First 1
$slug = $AppUniqueName.ToLowerInvariant()
if (-not $groupNode) {
    $groupNode = $map.CreateElement('Group')
    $groupNode.SetAttribute('Id', "$($slug)_group_$(($GroupTitle -replace '[^A-Za-z0-9]', '').ToLowerInvariant())")
    $groupNode.SetAttribute('Title', $GroupTitle)
    [void]$area.AppendChild($groupNode)
}

$titles = @{}
foreach ($pair in @($SubAreaTitles | ForEach-Object { $_ -split ',' } | Where-Object { $_ -match '=' })) {
    $k, $v = $pair -split '=', 2; $titles[$k.Trim().ToLowerInvariant()] = $v.Trim()
}
$lcid = Get-AlchemistSetting $config 'dataverse.baseLanguageCode' -Default 1033

# Subarea title: Title attribute and <Titles> element (form written by the app designer).
function Set-SubAreaTitle($node, [string]$title) {
    $node.SetAttribute('Title', $title)
    $titlesNode = $node.SelectSingleNode('Titles')
    if ($titlesNode) { [void]$node.RemoveChild($titlesNode) }
    $titlesNode = $map.CreateElement('Titles')
    $titleNode = $map.CreateElement('Title')
    $titleNode.SetAttribute('LCID', "$lcid")
    $titleNode.SetAttribute('Title', $title)
    [void]$titlesNode.AppendChild($titleNode)
    [void]$node.PrependChild($titlesNode)
}

$forms = @(); $views = @(); $added = @(); $retitled = @()
foreach ($t in $tableList) {
    $meta = (Invoke-DataverseRequest -Environment $dvEnv -Path "EntityDefinitions(LogicalName='$t')?`$select=LogicalName,DisplayCollectionName").Content
    $subArea = $map.SelectSingleNode("//SubArea[@Entity='$t']")
    if (-not $subArea) {
        $subArea = $map.CreateElement('SubArea')
        $subArea.SetAttribute('Id', "$($slug)_sub_$t")
        $subArea.SetAttribute('Entity', $t)
        $subArea.SetAttribute('Title', $meta.DisplayCollectionName.UserLocalizedLabel.Label)
        [void]$groupNode.AppendChild($subArea)
        $added += $t
    }
    if ($titles.ContainsKey($t)) { Set-SubAreaTitle $subArea $titles[$t]; $retitled += $t }
    $forms += @((Invoke-DataverseRequest -Environment $dvEnv -Path "systemforms?`$select=formid&`$filter=objecttypecode eq '$t' and formactivationstate eq 1 and (type eq 2 or type eq 7)").Content.value)
    $views += @((Invoke-DataverseRequest -Environment $dvEnv -Path "savedqueries?`$select=savedqueryid&`$filter=returnedtypecode eq '$t' and querytype eq 0 and statecode eq 0").Content.value)
}
$toDeclare = @($tableList | Where-Object { $_ -notin $declared })

if ($DryRun) {
    [ordered]@{
        dryRun = $true; app = $AppUniqueName; group = $GroupTitle; navigationAdded = $added; retitled = $retitled; tablesToDeclare = $toDeclare
        forms = $forms.Count; views = $views.Count; solution = $solutionInfo.uniqueName
        note = 'The solution will be exported then re-imported to declare the tables.'
    } | ConvertTo-Json
    return
}

Save-AlchemistSnapshot -Config $config -IssueKey $IssueKey -Environment $dvEnv -Type SiteMap -Name $AppUniqueName -Path "sitemaps($siteMapId)" -Fields sitemapxml
Invoke-DataverseRequest -Environment $dvEnv -Method PATCH -Path "sitemaps($siteMapId)" -Body @{ sitemapxml = $map.DocumentElement.OuterXml } | Out-Null
$appComponents = @($forms | ForEach-Object { @{ '@odata.type' = 'Microsoft.Dynamics.CRM.systemform'; formid = $_.formid } })
$appComponents += @($views | ForEach-Object { @{ '@odata.type' = 'Microsoft.Dynamics.CRM.savedquery'; savedqueryid = $_.savedqueryid } })
Invoke-DataverseRequest -Environment $dvEnv -Method POST -Path 'AddAppComponents' -Body @{ AppId = $appId; Components = $appComponents } | Out-Null

$publishXml = "<importexportxml><appmodules><appmodule>{$appId}</appmodule></appmodules><sitemaps><sitemap>{$siteMapId}</sitemap></sitemaps></importexportxml>"
Invoke-DataverseRequest -Environment $dvEnv -Method POST -Path 'PublishXml' -Body @{ ParameterXml = $publishXml } | Out-Null

if ($toDeclare.Count) {
    $restoredStates = Update-DataverseSolutionCustomizations -Environment $dvEnv -Solution $solutionInfo -Patch {
        param($document)
        $appNode = $document.SelectSingleNode("//AppModule[UniqueName='$AppUniqueName']")
        if (-not $appNode) { throw "App '$AppUniqueName' is not in solution '$($solutionInfo.uniqueName)'." }
        $componentsNode = $appNode.SelectSingleNode('AppModuleComponents')
        foreach ($t in $toDeclare) {
            $component = $document.CreateElement('AppModuleComponent')
            $component.SetAttribute('type', '1')
            $component.SetAttribute('schemaName', $t)
            [void]$componentsNode.PrependChild($component)
        }
    }
    if ($restoredStates) { Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action 'dataverse.states.restored' -Details @{ environment = $dvEnv.name; restored = $restoredStates } }
    Invoke-DataverseRequest -Environment $dvEnv -Method POST -Path 'PublishXml' -Body @{ ParameterXml = $publishXml } | Out-Null
}

$final = @((Invoke-DataverseRequest -Environment $dvEnv -Path "RetrieveAppComponents(AppModuleId=$appId)").Content.value)
$finalTables = @($final | Where-Object componenttype -eq 1 | ForEach-Object { (Invoke-DataverseRequest -Environment $dvEnv -Path "EntityDefinitions($($_.objectid))?`$select=LogicalName").Content.LogicalName })
$missing = @($tableList | Where-Object { $_ -notin $finalTables })
if ($missing) { throw "Tables not declared after import: $($missing -join ', ')." }

Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action 'dataverse.app.addtable' -Details @{ environment = $dvEnv.name; app = $AppUniqueName; tables = $tableList; solution = $solutionInfo.uniqueName }
[ordered]@{ updated = $true; app = $AppUniqueName; tables = $finalTables; navigationAdded = $added; retitled = $retitled; formsAdded = $forms.Count; viewsAdded = $views.Count; url = "$($dvEnv.url.TrimEnd('/'))/main.aspx?appid=$appId" } | ConvertTo-Json
