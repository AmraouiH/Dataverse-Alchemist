#Requires -Version 7.0
<#
.SYNOPSIS
    Creates a form (main or quick create) from a JSON description of its tabs and sections,
    adds it to the ticket solution and publishes the table with -Publish.
.EXAMPLE
    New-DataverseForm.ps1 -Table account -Name "Compte test" -LayoutFile layout.json -IssueKey CRM-1 -DryRun

    layout.json :
    { "header": ["ownerid"], "readonlyFields": ["accountnumber"], "tabs": [
      { "name": "general", "label": "General", "columns": [
        { "width": "33%", "sections": [ { "name": "main", "label": "Main", "columns": 1, "fields": ["name", "accountnumber"] } ] },
        { "width": "67%", "sections": [ { "name": "timeline", "label": "Timeline", "showLabel": false, "timeline": true } ] } ] } ] }

    A single-column tab can give "sections" directly. To generate the preview: New-DataverseFormMockup.ps1.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Table,
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$LayoutFile,
    [ValidateSet('Main', 'QuickCreate')][string]$FormType = 'Main',
    [string]$Description,
    # Replaces the tabs and header of the form with the same name, keeping its id, events and libraries.
    [switch]$ReplaceExisting,
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
$lcid = [string](Get-DataverseBaseLanguage -Environment $dvEnv)
$typeCode = @{ Main = 2; QuickCreate = 7 }[$FormType]

$definition = Get-Content -Raw -LiteralPath $LayoutFile | ConvertFrom-Json -AsHashtable
if (-not @($definition.tabs).Count) { throw "${LayoutFile}: no tab defined." }

$existing = @((Invoke-DataverseRequest -Environment $dvEnv -Path "systemforms?`$select=formid,formxml&`$filter=objecttypecode eq '$Table' and type eq $typeCode and name eq '$(ConvertTo-ODataString $Name)'").Content.value)
if ($existing.Count -and -not $ReplaceExisting) { throw "A form '$Name' already exists on '$Table' ($($existing[0].formid)). Use -ReplaceExisting or Edit-DataverseFormXml.ps1." }
if ($ReplaceExisting -and -not $existing.Count) { throw "Form '$Name' not found on '$Table'." }

$fieldInfo = Get-DataverseFormFieldInfo -Environment $dvEnv -Table $Table
$layoutFields = Get-DataverseLayoutFields -Definition $definition
$allFields = $layoutFields.all
$base = if ($existing.Count) { $existing[0].formxml } else { $null }
$doc = New-DataverseFormXmlFromLayout -Definition $definition -FieldInfo $fieldInfo -LanguageCode $lcid -Base $base
$form = $doc.DocumentElement

$primaryName = (Invoke-DataverseRequest -Environment $dvEnv -Path "EntityDefinitions(LogicalName='$Table')?`$select=PrimaryNameAttribute").Content.PrimaryNameAttribute
$missingRequired = @($fieldInfo.Keys | Where-Object { $fieldInfo[$_].required -in 'ApplicationRequired', 'SystemRequired' -and $fieldInfo[$_].validForForm -and $_ -notin $allFields -and $_ -notin 'ownerid', 'statecode', 'statuscode', 'createdon', 'modifiedon' })
$warnings = @()
if ($primaryName -notin $allFields) { $warnings += "The primary name '$primaryName' is not on the form." }
if ($missingRequired) { $warnings += "Required columns missing from the form: $($missingRequired -join ', ')." }

$formXml = $form.OuterXml

if ($DryRun) {
    [ordered]@{
        dryRun = $true; environment = "$($dvEnv.name) ($($dvEnv.url))"; solution = $solutionInfo.uniqueName
        table = $Table; form = $Name; type = $FormType; action = $(if ($existing.Count) { 'replace' } else { 'create' }); tabs = @($definition.tabs).Count; fields = $allFields.Count
        warnings = $warnings; formXmlLength = $formXml.Length; publish = [bool]$Publish
    } | ConvertTo-Json
    return
}

$body = @{ name = $Name; objecttypecode = $Table; type = $typeCode; formxml = $formXml }
if ($Description) { $body.description = $Description }
if ($existing.Count) {
    $formId = $existing[0].formid
    Save-AlchemistSnapshot -Config $config -IssueKey $IssueKey -Environment $dvEnv -Type SystemForm -Name "$Table / $Name" -Table $Table -Path "systemforms($formId)" -Fields formxml
    Invoke-DataverseRequest -Environment $dvEnv -Method PATCH -Path "systemforms($formId)" -Body @{ formxml = $formXml } | Out-Null
}
else { $formId = (Invoke-DataverseRequest -Environment $dvEnv -Method POST -Path 'systemforms' -Body $body -SolutionUniqueName $solutionInfo.uniqueName).EntityId }

# Without this setting, a quick create form exists but never opens.
$quickCreateEnabled = $false
if ($FormType -eq 'QuickCreate') {
    $definitionPath = "EntityDefinitions(LogicalName='$Table')"
    if (-not (Invoke-DataverseRequest -Environment $dvEnv -Path "$($definitionPath)?`$select=IsQuickCreateEnabled").Content.IsQuickCreateEnabled) {
        Save-AlchemistSnapshot -Config $config -IssueKey $IssueKey -Type TableSetting -Name $Table -Table $Table -Path $definitionPath -Value $false
        Update-DataverseDefinition -Environment $dvEnv -Path $definitionPath -Changes @{ IsQuickCreateEnabled = $true } -SolutionUniqueName $solutionInfo.uniqueName
        Publish-DataverseXml -Environment $dvEnv -Tables @($Table) | Out-Null
        Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action 'dataverse.table.quickcreate' -Details @{ environment = $dvEnv.name; table = $Table; solution = $solutionInfo.uniqueName }
        $quickCreateEnabled = $true
    }
}

$components = @(Add-DataverseTableToSolution -Environment $dvEnv -Solution $solutionInfo -Table $Table)
$components += New-AlchemistComponent -Type SystemForm -Id $formId -Name "$Table / $Name" -Status (Add-DataverseSolutionComponent -Environment $dvEnv -Solution $solutionInfo -ComponentId $formId -ComponentType SystemForm)
if ($Publish) { Publish-DataverseXml -Environment $dvEnv -Tables @($Table) | Out-Null }

Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action "dataverse.form.$(if ($existing.Count) { 'replace' } else { 'create' })" -Details @{
    environment = $dvEnv.name; table = $Table; form = $Name; formId = $formId; solution = $solutionInfo.uniqueName; components = $components
}
[ordered]@{ created = (-not $existing.Count); replaced = [bool]$existing.Count; quickCreateEnabled = $quickCreateEnabled; formId = $formId; form = $Name; table = $Table; warnings = $warnings; solution = $solutionInfo.uniqueName; components = $components; published = [bool]$Publish } | ConvertTo-Json -Depth 5
