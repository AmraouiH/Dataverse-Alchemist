#Requires -Version 7.0
<#
.SYNOPSIS
    Generates an IMAGE mockup (PNG) of a form, with its HTML source, from the JSON layout then used by
    New-DataverseForm.ps1: what is approved is exactly what will be applied. Nothing is written to the CRM.
    The image needs Edge or Chrome; without a browser, the script fails rather than deliver a mockup without an image.
    Checks that the fields exist and are usable, and lists the custom columns not placed.
.EXAMPLE
    New-DataverseFormMockup.ps1 -Table rhz_servicerequest -LayoutFile layout.json -OutFile maquette.png -Title "Option A"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Table,
    [Parameter(Mandatory)][string]$LayoutFile,
    [Parameter(Mandatory)][string]$OutFile,
    [string]$Title,
    [string]$Environment,
    [string]$ConfigPath
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force

$config = Get-AlchemistConfig -ConfigPath $ConfigPath
$dvEnv = Get-DataverseEnvironment -Config $config -Name $Environment
$Table = $Table.ToLowerInvariant()
$lcid = [string](Get-DataverseBaseLanguage -Environment $dvEnv)
$definition = Get-Content -Raw -LiteralPath $LayoutFile | ConvertFrom-Json -AsHashtable
$fieldInfo = Get-DataverseFormFieldInfo -Environment $dvEnv -Table $Table
$entity = (Invoke-DataverseRequest -Environment $dvEnv -Path "EntityDefinitions(LogicalName='$Table')?`$select=DisplayName,PrimaryNameAttribute").Content
$entityLabel = $entity.DisplayName.UserLocalizedLabel.Label

# Building the FormXml also validates the layout: an invalid field fails here, before the user approves.
$null = New-DataverseFormXmlFromLayout -Definition $definition -FieldInfo $fieldInfo -LanguageCode $lcid
$layoutFields = Get-DataverseLayoutFields -Definition $definition
$readonly = @($definition.readonlyFields | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })

function E([object]$value) { [System.Net.WebUtility]::HtmlEncode([string]$value) }
function Get-FieldLabel([string]$Field) { $labels = $fieldInfo[$Field].labels; return $labels[$lcid] ?? @($labels.Values)[0] ?? $Field }
function Get-TypeLabel([string]$Field) {
    $meta = $fieldInfo[$Field]
    $names = @{ StringType = 'Text'; MemoType = 'Multiline'; PicklistType = 'Choice'; LookupType = 'Lookup'; CustomerType = 'Customer'; OwnerType = 'Owner'; MoneyType = 'Currency'; DateTimeType = 'Date'; BooleanType = 'Yes/No'; IntegerType = 'Number'; DecimalType = 'Decimal'; DoubleType = 'Float'; MultiSelectPicklistType = 'Choices' }
    if ($meta.format -eq 'Duration') { return 'Duration' }
    return $names[$meta.type] ?? ($meta.type -replace 'Type$', '')
}
function Get-Marker([string]$Field) {
    $required = $fieldInfo[$Field].required -in 'ApplicationRequired', 'SystemRequired'
    $parts = @()
    if ($required) { $parts += '<span class="req" title="Required">*</span>' }
    if ($readonly -contains $Field) { $parts += '<span class="lock" title="Read-only">🔒</span>' }
    return ($parts -join '')
}
function Get-FieldHtml([string]$Field) {
    $tall = $fieldInfo[$Field].type -eq 'MemoType'
    "<div class=`"field$(if ($tall) { ' tall' })`"><label>$(E (Get-FieldLabel $Field))$(Get-Marker $Field)</label><div class=`"input$(if ($readonly -contains $Field) { ' ro' })`">$(E (Get-TypeLabel $Field))</div></div>"
}

$html = [Text.StringBuilder]::new()
[void]$html.Append(@'
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><title>Form mockup</title><style>
*{box-sizing:border-box}body{margin:0;font:13px/1.4 "Segoe UI",system-ui,sans-serif;color:#242424;background:#f3f2f1}
.bar{background:#0f2a4a;color:#fff;padding:8px 16px;font-weight:600}.page{max-width:1240px;margin:12px auto;padding:0 12px}
.head{background:#fff;border:1px solid #e1dfdd;border-radius:6px;padding:12px 16px;display:flex;justify-content:space-between;gap:24px;flex-wrap:wrap}
.head h1{font-size:19px;margin:0}.head small{color:#616161}.hf{display:flex;gap:28px}.hf div{min-width:96px}.hf b{display:block;font-size:13px}.hf span{color:#616161;font-size:12px}
.tabname{display:inline-block;padding:10px 14px 7px;font-weight:600;border-bottom:3px solid #0f6cbd;margin:10px 0 6px}
.cols{display:flex;gap:12px;align-items:flex-start}.col{display:flex;flex-direction:column;gap:12px;min-width:0}
.sec{background:#fff;border:1px solid #e1dfdd;border-radius:6px;padding:12px}.sec h2{font-size:13px;margin:0 0 8px;text-transform:uppercase;letter-spacing:.03em;color:#424242}
.grid{display:grid;gap:8px 14px}.field label{display:block;font-size:12px;color:#616161;margin-bottom:2px}.input{background:#f5f5f5;border:1px solid #e0e0e0;border-radius:4px;padding:5px 8px;color:#8a8886;font-size:12px}
.input.ro{background:#ebebeb}.field.tall .input{min-height:70px}.req{color:#c50f1f;margin-left:3px}.lock{margin-left:3px;font-size:10px}
.timeline{min-height:230px;border:1px dashed #c8c6c4;border-radius:4px;display:flex;align-items:center;justify-content:center;color:#8a8886}
</style></head><body>
'@)
[void]$html.Append("<div class=`"bar`">$(E ($Title ? $Title : "Form mockup"))</div><div class=`"page`"><div class=`"head`"><div><h1>New $(E $entityLabel)</h1><small>$(E $entityLabel)</small></div><div class=`"hf`">")
foreach ($field in $layoutFields.header) { [void]$html.Append("<div><b>$(E (Get-TypeLabel $field))</b><span>$(E (Get-FieldLabel $field))$(Get-Marker $field)</span></div>") }
[void]$html.Append('</div></div>')

foreach ($tab in @($definition.tabs)) {
    [void]$html.Append("<div class=`"tabname`">$(E ($tab.label ?? $tab.name))</div><div class=`"cols`">")
    foreach ($column in (Get-DataverseLayoutColumns -Tab $tab)) {
        $width = [int](($column.width ?? '100%') -replace '%', '')
        [void]$html.Append("<div class=`"col`" style=`"flex:$width 1 0`">")
        foreach ($section in @($column.sections)) {
            [void]$html.Append('<div class="sec">')
            if ($section.showLabel -ne $false) { [void]$html.Append("<h2>$(E ($section.label ?? $section.name))</h2>") }
            $count = [int]($section.columns ?? 1)
            [void]$html.Append("<div class=`"grid`" style=`"grid-template-columns:repeat($count,minmax(0,1fr))`">")
            foreach ($field in @($section.fields | Where-Object { $_ })) { [void]$html.Append((Get-FieldHtml $field.ToLowerInvariant())) }
            [void]$html.Append('</div>')
            if ($section.timeline) { [void]$html.Append('<div class="timeline">Timeline (notes, activities)</div>') }
            [void]$html.Append('</div>')
        }
        [void]$html.Append('</div>')
    }
    [void]$html.Append('</div>')
}
[void]$html.Append('</div></body></html>')
$pngPath = [IO.Path]::GetFullPath([IO.Path]::ChangeExtension($OutFile, '.png'))
$htmlPath = [IO.Path]::ChangeExtension($pngPath, '.html')
[IO.File]::WriteAllText($htmlPath, $html.ToString(), [Text.UTF8Encoding]::new($false))

# PNG rendering: height estimated from the longest content of each tab.
$browser = @(
    (Get-Command msedge, chrome -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source),
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if (-not $browser) { throw "Edge or Chrome not found: cannot produce the mockup image ($htmlPath)." }
$height = 150
foreach ($tab in @($definition.tabs)) {
    $tallest = 0
    foreach ($column in (Get-DataverseLayoutColumns -Tab $tab)) {
        $h = 0
        foreach ($section in @($column.sections)) {
            $perRow = [math]::Max(1, [int]($section.columns ?? 1))
            $sectionFields = @($section.fields | Where-Object { $_ })
            $tallFields = @($sectionFields | Where-Object { $fieldInfo[$_.ToLowerInvariant()].type -eq 'MemoType' }).Count
            $h += 62 + 58 * [math]::Ceiling($sectionFields.Count / $perRow) + 45 * $tallFields + $(if ($section.timeline) { 250 } else { 0 })
        }
        $tallest = [math]::Max($tallest, $h)
    }
    $height += 60 + $tallest
}
$pngTmp = "$pngPath.tmp.png"
$browserArgs = @('--headless=new', '--disable-gpu', '--hide-scrollbars', "--window-size=1280,$height", "--screenshot=$pngTmp", ([Uri]$htmlPath).AbsoluteUri)
Start-Process -FilePath $browser -ArgumentList $browserArgs -Wait -WindowStyle Hidden
for ($i = 0; $i -lt 20 -and -not (Test-Path -LiteralPath $pngTmp); $i++) { Start-Sleep -Milliseconds 500 }
if (-not (Test-Path -LiteralPath $pngTmp)) { throw "The browser did not produce the mockup image." }
Move-Item -LiteralPath $pngTmp -Destination $pngPath -Force

$custom = @($fieldInfo.Keys | Where-Object { $_ -like '*_*' -and $fieldInfo[$_].validForForm -and $fieldInfo[$_].type -notin 'VirtualType', 'UniqueidentifierType' -and $_ -notin $layoutFields.all -and $_ -notmatch '_base$|^(transactioncurrencyid|exchangerate|importsequencenumber|overriddencreatedon|timezoneruleversionnumber|utcconversiontimezonecode)$' })
$required = @($fieldInfo.Keys | Where-Object { $fieldInfo[$_].required -in 'ApplicationRequired', 'SystemRequired' -and $fieldInfo[$_].validForForm -and $_ -notin $layoutFields.all -and $_ -notin 'ownerid', 'statecode', 'statuscode', 'createdon', 'modifiedon' })
[ordered]@{ image = $pngPath; html = $htmlPath; tabs = @($definition.tabs).Count; fields = $layoutFields.all.Count; notPlaced = $custom; requiredNotPlaced = $required } | ConvertTo-Json
