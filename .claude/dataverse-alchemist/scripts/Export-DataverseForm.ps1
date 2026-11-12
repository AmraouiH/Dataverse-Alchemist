#Requires -Version 7.0
<#
.SYNOPSIS
    Exports the FormXml of a form to the run folder (<table>.<form>.xml + untouched .orig.xml copy).
    Without -FormName or -FormId: lists the forms of the table.
.EXAMPLE
    Export-DataverseForm.ps1 -Table account -IssueKey CRM-123
    Export-DataverseForm.ps1 -Table account -FormName "Compte" -IssueKey CRM-123
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Table,
    [string]$FormName,
    [string]$FormId,
    [ValidateSet('Main', 'QuickCreate', 'QuickView', 'Card')][string]$FormType = 'Main',
    [string]$IssueKey,
    [string]$OutFolder,
    [string]$Environment,
    [string]$ConfigPath
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force

$config = Get-AlchemistConfig -ConfigPath $ConfigPath
$dvEnv = Get-DataverseEnvironment -Config $config -Name $Environment
$Table = $Table.ToLowerInvariant()
$typeCodes = @{ Main = 2; QuickCreate = 7; QuickView = 6; Card = 11 }

if (-not $FormName -and -not $FormId) {
    $forms = (Invoke-DataverseRequest -Environment $dvEnv -Path "systemforms?`$select=formid,name,isdefault,formactivationstate&`$filter=objecttypecode eq '$Table' and type eq $($typeCodes[$FormType])&`$orderby=name").Content.value
    $forms | ForEach-Object { [pscustomobject]@{ formId = $_.formid; name = $_.name; isDefault = $_.isdefault; active = ($_.formactivationstate -eq 1) } } | Format-Table -AutoSize
    return
}

$filter = if ($FormId) { "formid eq $($FormId.Trim('{}'))" } else { "objecttypecode eq '$Table' and type eq $($typeCodes[$FormType]) and name eq '$(ConvertTo-ODataString $FormName)'" }
$forms = @((Invoke-DataverseRequest -Environment $dvEnv -Path "systemforms?`$select=formid,name,formxml,objecttypecode&`$filter=$filter").Content.value)
if ($forms.Count -eq 0) { throw "Form not found ($filter)." }
if ($forms.Count -gt 1) { throw "Several forms match: $(($forms | ForEach-Object { "$($_.name) [$($_.formid)]" }) -join ', '). Use -FormId." }
$form = $forms[0]

if (-not $OutFolder) {
    $OutFolder = if ($IssueKey) { Join-Path (Get-AlchemistRunFolder -Config $config -IssueKey $IssueKey) 'forms' } else { Join-Path $config._meta.repoRoot '.alchemist/forms' }
}
New-Item -ItemType Directory -Path $OutFolder -Force | Out-Null

$safeName = ConvertTo-AlchemistSlug $form.name
$basePath = Join-Path $OutFolder "$($form.objecttypecode).$safeName"
$workPath = "$basePath.xml"
$origPath = "$basePath.orig.xml"

# Indented to ease editing and diffing.
$doc = [xml]::new()
$doc.PreserveWhitespace = $false
$doc.LoadXml($form.formxml)
$settings = [System.Xml.XmlWriterSettings]::new()
$settings.Indent = $true
$settings.OmitXmlDeclaration = $true
$settings.Encoding = [Text.UTF8Encoding]::new($false)

foreach ($target in @($workPath) + $(if (Test-Path -LiteralPath $origPath) { @() } else { @($origPath) })) {
    $writer = [System.Xml.XmlWriter]::Create($target, $settings)
    try { $doc.Save($writer) } finally { $writer.Dispose() }
}

[ordered]@{
    formId     = $form.formid
    name       = $form.name
    table      = $form.objecttypecode
    formXml    = $workPath
    original   = $origPath
    nextStep   = "Edit $workPath then: Import-DataverseForm.ps1 -FormId $($form.formid) -FormXmlPath `"$workPath`" -Table $Table -Publish"
} | ConvertTo-Json
