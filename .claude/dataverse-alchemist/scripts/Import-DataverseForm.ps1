#Requires -Version 7.0
<#
.SYNOPSIS
    Updates the FormXml of a form from a file, after validation, then publishes the table.
    Checks: well-formed XML, <form> root, unique cell/control ids, existing columns (if -Table).
.EXAMPLE
    Import-DataverseForm.ps1 -FormId <guid> -FormXmlPath .alchemist/runs/CRM-1/forms/account.compte.xml -Table account -Publish -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$FormId,
    [Parameter(Mandatory)][string]$FormXmlPath,
    [string]$Table,
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
$solutionName = $solutionInfo.uniqueName
$FormId = $FormId.Trim('{}')

$doc = [xml]::new()
$doc.PreserveWhitespace = $false
$doc.Load((Resolve-Path -LiteralPath $FormXmlPath).Path)
if ($doc.DocumentElement.Name -ne 'form') { throw "The FormXml root must be <form> (found: <$($doc.DocumentElement.Name)>)." }

$errors = [System.Collections.Generic.List[string]]::new()
foreach ($xpath in '//cell/@id', '//control/@id', '//tab/@id', '//section/@id') {
    $duplicates = @($doc.SelectNodes($xpath) | Group-Object { $_.Value.ToLowerInvariant() } | Where-Object Count -gt 1)
    foreach ($dup in $duplicates) { $errors.Add("Duplicate id ($xpath): $($dup.Name)") }
}

$fields = @($doc.SelectNodes('//control/@datafieldname') | ForEach-Object { $_.Value.ToLowerInvariant() } | Select-Object -Unique)
if ($Table -and -not $DryRun) {
    $attrs = (Invoke-DataverseRequest -Environment $dvEnv -Path "EntityDefinitions(LogicalName='$($Table.ToLowerInvariant())')/Attributes?`$select=LogicalName").Content.value.LogicalName
    foreach ($field in $fields) { if ($attrs -notcontains $field) { $errors.Add("Column does not exist on '$Table': $field") } }
}
if ($errors.Count) { throw "Invalid FormXml:`n - $($errors -join "`n - ")" }

$formXml = $doc.DocumentElement.OuterXml

if ($DryRun) {
    [ordered]@{
        dryRun        = $true
        environment   = "$($dvEnv.name) ($($dvEnv.url))"
        request       = "PATCH /api/data/v9.2/systemforms($FormId) { formxml }"
        solution      = $solutionName
        controls      = $fields.Count
        formXmlLength = $formXml.Length
        publish       = [bool]$Publish
        hint          = 'Show the diff: git diff --no-index <form>.orig.xml <form>.xml'
    } | ConvertTo-Json
    return
}

$form = (Invoke-DataverseRequest -Environment $dvEnv -Path "systemforms($FormId)?`$select=name,objecttypecode").Content
Save-AlchemistSnapshot -Config $config -IssueKey $IssueKey -Environment $dvEnv -Type SystemForm -Name "$($form.objecttypecode) / $($form.name)" -Table $form.objecttypecode -Path "systemforms($FormId)" -Fields formxml
Invoke-DataverseRequest -Environment $dvEnv -Method PATCH -Path "systemforms($FormId)" -Body @{ formxml = $formXml } | Out-Null

# Table (root component only) then form in the ticket solution.
$components = @(Add-DataverseTableToSolution -Environment $dvEnv -Solution $solutionInfo -Table $form.objecttypecode)
$components += New-AlchemistComponent -Type SystemForm -Id $FormId -Name "$($form.objecttypecode) / $($form.name)" -Status (Add-DataverseSolutionComponent -Environment $dvEnv -Solution $solutionInfo -ComponentId $FormId -ComponentType SystemForm)
if ($Publish) { Publish-DataverseXml -Environment $dvEnv -Tables @($form.objecttypecode) | Out-Null }

Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action 'dataverse.form.update' -Details @{
    environment = $dvEnv.name; formId = $FormId; form = $form.name; table = $form.objecttypecode; file = $FormXmlPath; solution = $solutionName; components = $components
}

[ordered]@{ updated = $true; formId = $FormId; form = $form.name; table = $form.objecttypecode; published = [bool]$Publish; solution = $solutionName; components = $components } | ConvertTo-Json -Depth 5
