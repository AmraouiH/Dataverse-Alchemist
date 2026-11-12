#Requires -Version 7.0
<#
.SYNOPSIS
    Creates a model-driven app (Unified Interface) in the ticket solution.

.DESCRIPTION
    Constraints imposed by the API (seen on a real environment):
    - clienttype must be forced to 4: without it, the app is created as 2 and does not open;
    - AddAppComponents cannot attach a table (it references the system table "entity");
        so the tables are declared in the solution customizations.xml, then re-imported;
    - the import requires a licensed user, not in Administrative access mode.

    Navigation (JSON) :
    { "groups": [ { "title": "Customers", "tables": ["account", "contact"] } ] }
.EXAMPLE
    New-DataverseApp.ps1 -Name "Ventes" -UniqueName rhz_Ventes -NavigationFile nav.json -IssueKey CRM-1 -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$UniqueName,
    [Parameter(Mandatory)][string]$NavigationFile,
    [string]$Description,
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
Assert-PublisherPrefix -Solution $solutionInfo -Name $UniqueName -What 'UniqueName'

# An app never published only appears in RetrieveUnpublishedMultiple.
$published = @((Invoke-DataverseRequest -Environment $dvEnv -Path "appmodules?`$select=appmoduleid,uniquename&`$filter=uniquename eq '$UniqueName'").Content.value)
$unpublished = @((Invoke-DataverseRequest -Environment $dvEnv -Path 'appmodules/Microsoft.Dynamics.CRM.RetrieveUnpublishedMultiple()?$select=appmoduleid,uniquename').Content.value | Where-Object uniquename -eq $UniqueName)
$existing = @($published + $unpublished | Where-Object { $_ })
if ($existing.Count) { throw "App '$UniqueName' already exists ($($existing[0].appmoduleid))." }

$navigation = Get-Content -Raw -LiteralPath $NavigationFile | ConvertFrom-Json -AsHashtable
$navTables = @($navigation.groups | ForEach-Object { $_.tables } | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)
if (-not $navTables.Count) { throw "${NavigationFile}: no table." }
# Activities open in their real table: they must be part of the app.
$appTables = @($navTables)
if ($navTables -contains 'activitypointer') { $appTables = @($appTables + 'appointment', 'email', 'phonecall', 'task' | Select-Object -Unique) }

$labels = @{}
foreach ($t in $appTables) {
    $meta = (Invoke-DataverseRequest -Environment $dvEnv -Path "EntityDefinitions(LogicalName='$t')?`$select=LogicalName,DisplayCollectionName").Content
    $labels[$t] = $meta.DisplayCollectionName.UserLocalizedLabel.Label
}

$slug = $UniqueName.ToLowerInvariant()
$groupIndex = 0
$groupsXml = ($navigation.groups | ForEach-Object {
        $groupIndex++
        $title = [System.Security.SecurityElement]::Escape($_.title)
        $subs = ($_.tables | ForEach-Object { $tableName = $_.ToLowerInvariant(); "<SubArea Id=`"$($slug)_sub_$tableName`" Entity=`"$tableName`" Title=`"$([System.Security.SecurityElement]::Escape($labels[$tableName]))`" />" }) -join ''
        "<Group Id=`"$($slug)_group_$groupIndex`" Title=`"$title`">$subs</Group>"
    }) -join ''
$siteMapXml = "<SiteMap><Area Id=`"$($slug)_area`" Title=`"$([System.Security.SecurityElement]::Escape($Name))`" ShowGroups=`"true`">$groupsXml</Area></SiteMap>"

$forms = @(); $views = @()
foreach ($t in $appTables) {
    $forms += @((Invoke-DataverseRequest -Environment $dvEnv -Path "systemforms?`$select=formid&`$filter=objecttypecode eq '$t' and formactivationstate eq 1 and (type eq 2 or type eq 7)").Content.value)
    $views += @((Invoke-DataverseRequest -Environment $dvEnv -Path "savedqueries?`$select=savedqueryid&`$filter=returnedtypecode eq '$t' and querytype eq 0 and statecode eq 0").Content.value)
}

if ($DryRun) {
    [ordered]@{
        dryRun = $true; environment = "$($dvEnv.name) ($($dvEnv.url))"; solution = $solutionInfo.uniqueName; app = $Name; uniqueName = $UniqueName
        tables = $appTables; forms = $forms.Count; views = $views.Count; siteMap = $siteMapXml
        note = 'The solution will be exported then re-imported to declare the tables: it must not contain unpublished work.'
    } | ConvertTo-Json
    return
}

$userId = (Invoke-DataverseRequest -Environment $dvEnv -Path 'WhoAmI').Content.UserId
$user = (Invoke-DataverseRequest -Environment $dvEnv -Path "systemusers($userId)?`$select=accessmode,islicensed").Content
if ($user.accessmode -eq 1 -or -not $user.islicensed) { throw "The signed-in user is in Administrative mode or unlicensed: the solution import will be refused. Nothing was created." }

$appId = (Invoke-DataverseRequest -Environment $dvEnv -Method POST -Path 'appmodules' -SolutionUniqueName $solutionInfo.uniqueName -Body @{
        name          = $Name
        uniquename    = $UniqueName
        description   = $Description
        clienttype    = 4
        webresourceid = '953b9fac-1e5e-e611-80d6-00155ded156f'
    }).EntityId
$siteMapId = (Invoke-DataverseRequest -Environment $dvEnv -Method POST -Path 'sitemaps' -SolutionUniqueName $solutionInfo.uniqueName -Body @{
        sitemapname = $Name; sitemapnameunique = $UniqueName; sitemapxml = $siteMapXml; isappaware = $true
    }).EntityId

$appComponents = @(@{ '@odata.type' = 'Microsoft.Dynamics.CRM.sitemap'; sitemapid = $siteMapId })
$appComponents += @($forms | ForEach-Object { @{ '@odata.type' = 'Microsoft.Dynamics.CRM.systemform'; formid = $_.formid } })
$appComponents += @($views | ForEach-Object { @{ '@odata.type' = 'Microsoft.Dynamics.CRM.savedquery'; savedqueryid = $_.savedqueryid } })
Invoke-DataverseRequest -Environment $dvEnv -Method POST -Path 'AddAppComponents' -Body @{ AppId = $appId; Components = $appComponents } | Out-Null

# An app never published is not exported: publish before exporting.
$publishXml = "<importexportxml><appmodules><appmodule>{$appId}</appmodule></appmodules><sitemaps><sitemap>{$siteMapId}</sitemap></sitemaps></importexportxml>"
Invoke-DataverseRequest -Environment $dvEnv -Method POST -Path 'PublishXml' -Body @{ ParameterXml = $publishXml } | Out-Null

# Table declaration through the solution.
$restoredStates = Update-DataverseSolutionCustomizations -Environment $dvEnv -Solution $solutionInfo -Patch {
    param($document)
    $appNode = $document.SelectSingleNode("//AppModule[UniqueName='$UniqueName']")
    if (-not $appNode) { throw "App '$UniqueName' missing from the exported solution (appId $appId, sitemap $siteMapId created: remove or complete them)." }
    $componentsNode = $appNode.SelectSingleNode('AppModuleComponents')
    foreach ($t in $appTables) {
        $component = $document.CreateElement('AppModuleComponent')
        $component.SetAttribute('type', '1')
        $component.SetAttribute('schemaName', $t)
        [void]$componentsNode.PrependChild($component)
    }
}
if ($restoredStates) { Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action 'dataverse.states.restored' -Details @{ environment = $dvEnv.name; restored = $restoredStates } }

Invoke-DataverseRequest -Environment $dvEnv -Method POST -Path 'PublishXml' -Body @{ ParameterXml = $publishXml } | Out-Null

# Real check: ValidateApp alone does not detect a missing table.
$state = (Invoke-DataverseRequest -Environment $dvEnv -Path "appmodules($appId)?`$select=clienttype").Content
$finalComponents = @((Invoke-DataverseRequest -Environment $dvEnv -Path "RetrieveAppComponents(AppModuleId=$appId)").Content.value)
$declared = @($finalComponents | Where-Object componenttype -eq 1 | ForEach-Object { (Invoke-DataverseRequest -Environment $dvEnv -Path "EntityDefinitions($($_.objectid))?`$select=LogicalName").Content.LogicalName })
$missingTables = @($appTables | Where-Object { $_ -notin $declared })
if ($state.clienttype -ne 4) { throw "clienttype=$($state.clienttype) instead of 4 after creation." }
if ($missingTables) { throw "Tables not declared in the app: $($missingTables -join ', ')." }
$validation = (Invoke-DataverseRequest -Environment $dvEnv -Path "ValidateApp(AppModuleId=$appId)").Content.AppValidationResponse
$issues = @(@($validation.ValidationIssueList) | Where-Object { $_ -and $_.Message } | ForEach-Object { "[$($_.ErrorType)] $($_.Message)" })

$components = @(
    New-AlchemistComponent -Type AppModule -Id $appId -Name $UniqueName -Status (Add-DataverseSolutionComponent -Environment $dvEnv -Solution $solutionInfo -ComponentId $appId -ComponentType AppModule)
    New-AlchemistComponent -Type SiteMap -Id $siteMapId -Name $UniqueName -Status (Add-DataverseSolutionComponent -Environment $dvEnv -Solution $solutionInfo -ComponentId $siteMapId -ComponentType SiteMap)
)
Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action 'dataverse.app.create' -Details @{
    environment = $dvEnv.name; app = $UniqueName; appId = $appId; solution = $solutionInfo.uniqueName; components = $components
}
[ordered]@{
    created = $true; app = $Name; uniqueName = $UniqueName; appId = $appId; clientType = $state.clienttype; tables = $declared
    forms = $forms.Count; views = $views.Count; validationSuccess = $validation.ValidationSuccess; validationIssues = $issues
    url = "$($dvEnv.url.TrimEnd('/'))/main.aspx?appid=$appId"; solution = $solutionInfo.uniqueName; components = $components
} | ConvertTo-Json -Depth 5
