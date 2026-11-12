#Requires -Version 7.0
<#
.SYNOPSIS
    Edits an exported FormXml (local file, nothing is sent to the CRM): adds a tab, section, fields,
    or a JavaScript event handler (library declared once, no duplicate).
    Chain with Import-DataverseForm.ps1 to apply.
.EXAMPLE
    Edit-DataverseFormXml.ps1 -FormXmlPath account.account.xml -Table account -Operation AddTab -TabName tab_finance -TabLabel Finance
    Edit-DataverseFormXml.ps1 -FormXmlPath account.account.xml -Table account -Operation AddSection -TabName tab_finance -SectionName sec_main -SectionLabel Main -SectionColumns 2 -Fields revenue,rhz_tstmoney
    Edit-DataverseFormXml.ps1 -FormXmlPath account.account.xml -Table account -Operation AddField -Fields rhz_legalrepid -AfterField tickersymbol
    Edit-DataverseFormXml.ps1 -FormXmlPath account.account.xml -Table account -Operation AddField -Fields rhz_tsttext -SectionName sec_main
    Edit-DataverseFormXml.ps1 -FormXmlPath f.xml -Table account -Operation AddHandler -Library rhz_/js/account.form.js -FunctionName Alchemist.Account.Form.onChange -Event onchange -Fields creditlimit
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$FormXmlPath,
    [Parameter(Mandatory)][string]$Table,
    [Parameter(Mandatory)][ValidateSet('AddTab', 'AddSection', 'AddField', 'AddHandler')][string]$Operation,
    [string]$TabName,
    [string]$TabLabel,
    [string]$SectionName,
    [string]$SectionLabel,
    [int]$SectionColumns = 1,
    [string[]]$Fields,
    # AddField: inserts a row right below this field, in the same section.
    [string]$AfterField,
    # AddHandler: library (web resource), function, event onload | onsave | onchange (with -Fields for onchange).
    [string]$Library,
    [string]$FunctionName,
    [ValidateSet('onload', 'onsave', 'onchange')][string]$Event,
    [string]$Environment,
    [string]$ConfigPath
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force

$config = Get-AlchemistConfig -ConfigPath $ConfigPath
$dvEnv = Get-DataverseEnvironment -Config $config -Name $Environment
$lcid = [string](Get-DataverseBaseLanguage -Environment $dvEnv)
$fieldList = @($Fields | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })

$path = (Resolve-Path -LiteralPath $FormXmlPath).Path
$doc = [xml]::new()
$doc.PreserveWhitespace = $false
$doc.Load($path)

function Assert-FieldsAbsent([string[]]$Names) {
    foreach ($n in $Names) {
        if ($doc.SelectSingleNode("//control[@datafieldname='$n']")) { throw "Field '$n' is already on the form." }
    }
}

switch ($Operation) {
    'AddTab' {
        if (-not $TabName) { throw '-TabName is required.' }
        if ($doc.SelectSingleNode("//tab[@name='$TabName']")) { throw "Tab '$TabName' already exists." }
        $tabs = $doc.SelectSingleNode('/form/tabs')
        [void]$tabs.AppendChild((New-DataverseFormTab -Document $doc -Name $TabName -Labels @{ $lcid = ($TabLabel ? $TabLabel : $TabName) }))
        $summary = "onglet $TabName"
    }
    'AddSection' {
        if (-not $TabName -or -not $SectionName) { throw '-TabName and -SectionName are required.' }
        $tab = $doc.SelectSingleNode("//tab[@name='$TabName']")
        if (-not $tab) { throw "Tab '$TabName' not found." }
        if ($doc.SelectSingleNode("//section[@name='$SectionName']")) { throw "Section '$SectionName' already exists." }
        Assert-FieldsAbsent $fieldList
        $info = if ($fieldList) { Get-DataverseFormFieldInfo -Environment $dvEnv -Table $Table } else { @{} }
        # Last column of the tab.
        $sections = @($tab.SelectNodes('columns/column/sections'))[-1]
        [void]$sections.AppendChild((New-DataverseFormSection -Document $doc -Name $SectionName -Labels @{ $lcid = ($SectionLabel ? $SectionLabel : $SectionName) } -Columns $SectionColumns -Fields $fieldList -FieldInfo $info))
        $summary = "section $SectionName, $($fieldList.Count) field(s)"
    }
    'AddField' {
        if (-not $fieldList) { throw '-Fields is required.' }
        Assert-FieldsAbsent $fieldList
        $info = Get-DataverseFormFieldInfo -Environment $dvEnv -Table $Table
        if ($AfterField) {
            $target = $AfterField.ToLowerInvariant()
            $anchors = @($doc.SelectNodes("//control[@datafieldname='$target']"))
            if ($anchors.Count -eq 0) { throw "Field '$target' is not on this form." }
            if ($anchors.Count -gt 1) { throw "Field '$target' appears $($anchors.Count) times: specify -SectionName." }
            if ($anchors[0].SelectSingleNode('ancestor::header') -or $anchors[0].SelectSingleNode('ancestor::footer')) { throw "Field '$target' is in the header or footer." }
            $anchorRow = $anchors[0].SelectSingleNode('ancestor::row')
            foreach ($field in ($fieldList | Sort-Object { [array]::IndexOf($fieldList, $_) } -Descending)) {
                $row = $doc.CreateElement('row')
                [void]$row.AppendChild((New-DataverseFormCell -Document $doc -Field $field -FieldInfo $info))
                [void]$anchorRow.ParentNode.InsertAfter($row, $anchorRow)
            }
            $summary = "$($fieldList.Count) field(s) below $target"
        }
        else {
            if (-not $SectionName) { throw '-AfterField or -SectionName is required.' }
            $section = $doc.SelectSingleNode("//section[@name='$SectionName']")
            if (-not $section) { throw "Section '$SectionName' not found." }
            $columnCount = [int]($section.GetAttribute('columns') ? $section.GetAttribute('columns') : 1)
            Add-DataverseFormRows -Document $doc -Rows $section.SelectSingleNode('rows') -Fields $fieldList -FieldInfo $info -Columns $columnCount
            $summary = "$($fieldList.Count) field(s) in $SectionName"
        }
    }
    'AddHandler' {
        if (-not $Library -or -not $FunctionName -or -not $Event) { throw '-Library, -FunctionName and -Event are required.' }
        # Empty string = form event (onload, onsave). Not @($null): an if-expression flattens it to $null, and foreach does not run.
        if ($Event -eq 'onchange' -and -not $fieldList) { throw 'onchange: -Fields is required.' }
        [string[]]$targets = if ($Event -eq 'onchange') { $fieldList } else { ,'' }
        foreach ($t in @($targets | Where-Object { $_ })) {
            if (-not $doc.SelectSingleNode("//control[@datafieldname='$t']")) { throw "onchange: field '$t' is not on this form." }
        }
        $form = $doc.SelectSingleNode('/form')
        # Library declared only once.
        $libraries = $form.SelectSingleNode('formLibraries')
        if (-not $libraries) { $libraries = $doc.CreateElement('formLibraries'); [void]$form.AppendChild($libraries) }
        if (-not $libraries.SelectSingleNode("Library[@name='$Library']")) {
            $lib = $doc.CreateElement('Library'); $lib.SetAttribute('name', $Library); $lib.SetAttribute('libraryUniqueId', "{$([guid]::NewGuid())}")
            [void]$libraries.AppendChild($lib)
        }
        $events = $form.SelectSingleNode('events')
        if (-not $events) { $events = $doc.CreateElement('events'); [void]$form.AppendChild($events) }
        $added = 0
        foreach ($t in $targets) {
            $xpath = if ($t) { "event[@name='onchange' and @attribute='$t']" } else { "event[@name='$Event' and not(@attribute)]" }
            $eventNode = $events.SelectSingleNode($xpath)
            if (-not $eventNode) {
                $eventNode = $doc.CreateElement('event'); $eventNode.SetAttribute('name', $Event); $eventNode.SetAttribute('application', 'false'); $eventNode.SetAttribute('active', 'false')
                if ($t) { $eventNode.SetAttribute('attribute', $t) }
                [void]$events.AppendChild($eventNode)
            }
            $handlers = $eventNode.SelectSingleNode('Handlers')
            if (-not $handlers) { $handlers = $doc.CreateElement('Handlers'); [void]$eventNode.AppendChild($handlers) }
            # No duplicate: same function of the same library on the same event.
            if ($handlers.SelectSingleNode("Handler[@functionName='$FunctionName' and @libraryName='$Library']")) { continue }
            $h = $doc.CreateElement('Handler')
            foreach ($pair in @(@('functionName', $FunctionName), @('libraryName', $Library), @('handlerUniqueId', "{$([guid]::NewGuid())}"), @('enabled', 'true'), @('parameters', ''), @('passExecutionContext', 'true'))) { $h.SetAttribute($pair[0], $pair[1]) }
            [void]$handlers.AppendChild($h); $added++
        }
        $summary = "$FunctionName on $Event$(if ($fieldList -and $Event -eq 'onchange') { ' (' + ($fieldList -join ', ') + ')' }): $added handler(s) added"
    }
}

$settings = [System.Xml.XmlWriterSettings]::new()
$settings.Indent = $true
$settings.OmitXmlDeclaration = $true
$settings.Encoding = [Text.UTF8Encoding]::new($false)
$writer = [System.Xml.XmlWriter]::Create($path, $settings)
try { $doc.Save($writer) } finally { $writer.Dispose() }

[ordered]@{ edited = $true; operation = $Operation; detail = $summary; file = $path } | ConvertTo-Json
