#Requires -Version 7.0
<#
.SYNOPSIS
    Generates the Playwright test script of a ticket (<testing.ui.specFolder>/<KEY>.ui.spec.mjs, default tests/ui) from its journal and the
    real CRM metadata.

.DESCRIPTION
    Generated tests (generated section, rewritten on each generation):
      - Form   : each form created or changed opens; tabs and sections visible; each field of the
                 ticket (or of the form if the ticket created the table) is shown, with the expected required
                 or locked icon; page script errors are reported.
      - Field  : column created by the ticket but on no main form -> skipped test, with the reason.
      - View   : the view opens, is selected, and shows the columns of its layout in order.
      - App    : the sitemap entry of each added table is visible and opens the table list.
    Custom section (between "alchemist:custom:start" and "alchemist:custom:end"): kept as is. This is
    where the agent writes the behavior scenarios (form script, business rule, plugin as seen from the UI).
    On first generation, it lists the behaviors to cover found in the journal.

.EXAMPLE
    New-AlchemistUiTests.ps1 -IssueKey CRM-412
    New-AlchemistUiTests.ps1 -IssueKey CRM-412 -App rhz_ServiceClient -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$IssueKey,
    # Model-driven app in which to open forms and views (default: the one in the journal, otherwise one whose sitemap has a ticket table)
    [string]$App,
    [string]$Environment,
    [string]$OutputPath,
    [switch]$DryRun,
    [string]$ConfigPath
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force

$config = Get-AlchemistConfig -ConfigPath $ConfigPath
$IssueKey = $IssueKey.ToUpperInvariant()
$runFolder = Get-AlchemistRunFolder -Config $config -IssueKey $IssueKey
$journalPath = Join-Path $runFolder 'journal.jsonl'
if (-not (Test-Path -LiteralPath $journalPath)) { throw "Journal not found: $journalPath" }
$dvEnv = Get-DataverseEnvironment -Config $config -Name $Environment
$repoRoot = $config._meta.repoRoot                                    # CRM project root (parent of .alchemist)
if (-not $OutputPath) { $OutputPath = Join-Path (Join-Path $repoRoot (Get-AlchemistSetting $config 'testing.ui.specFolder' -Default 'tests/ui')) "$IssueKey.ui.spec.mjs" }
# Import path of the library, relative to the spec (the spec lives in the project, the library in the agent)
$libPath = (Resolve-Path (Join-Path $PSScriptRoot '..\playwright\lib\d365.mjs')).Path
$libImport = [IO.Path]::GetRelativePath((Split-Path ([IO.Path]::GetFullPath($OutputPath))), $libPath).Replace('\', '/')
if (-not $libImport.StartsWith('.')) { $libImport = "./$libImport" }

function Get-Dv([string]$Path) {
    $r = Invoke-DataverseRequest -Environment $dvEnv -Path $Path
    $c = $r.Content
    if ($c -is [string]) { $c = $c | ConvertFrom-Json -Depth 30 }
    return $c
}
function Js($Value) { return ($Value | ConvertTo-Json -Depth 10 -Compress) }
function Q([string]$s) { return "'" + ($s -replace '\\', '\\' -replace "'", "\'") + "'" }

# --- 1. Read the journal
$entries = @(Get-Content -LiteralPath $journalPath | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json -AsHashtable })
$rolledBack = @($entries | Where-Object { $_.action -eq 'rollback.finished' }).Count -gt 0
$createdTables = @($entries | Where-Object action -eq 'dataverse.table.create' | ForEach-Object { $_.table })
$columns = [ordered]@{}   # table -> list of ticket columns
foreach ($e in $entries | Where-Object { $_.action -in 'dataverse.column.create', 'dataverse.column.update' }) {
    if (-not $e.table -or -not $e.column) { continue }
    if (-not $columns.Contains($e.table)) { $columns[$e.table] = [System.Collections.Generic.List[string]]::new() }
    if (-not $columns[$e.table].Contains($e.column)) { $columns[$e.table].Add($e.column) }
}
$forms = [ordered]@{}
foreach ($e in $entries | Where-Object { $_.action -like 'dataverse.form.*' -and $_.formId }) { $forms[$e.formId] = @{ table = $e.table; name = $e.form; id = $e.formId } }
$views = [ordered]@{}
foreach ($e in $entries | Where-Object { $_.action -in 'dataverse.view.create', 'dataverse.view.update' -and $_.viewId }) { $views[$e.viewId] = @{ table = $e.table; name = $e.view; id = $e.viewId } }
$appTables = [ordered]@{}
foreach ($e in $entries | Where-Object { $_.action -in 'dataverse.app.addtable', 'dataverse.app.create' -and $_.app }) {
    if (-not $appTables.Contains($e.app)) { $appTables[$e.app] = [System.Collections.Generic.List[string]]::new() }
    foreach ($t in @($e.tables)) { if ($t -and -not $appTables[$e.app].Contains($t)) { $appTables[$e.app].Add($t) } }
}
if (-not $App -and $appTables.Count) { $App = @($appTables.Keys)[0] }
# Otherwise: first app whose sitemap contains a ticket table
if (-not $App) {
    $ticketTables = @(@($columns.Keys) + @($forms.Values | ForEach-Object { $_.table }) + @($views.Values | ForEach-Object { $_.table }) + $createdTables | Where-Object { $_ } | Select-Object -Unique)
    $allMaps = Get-Dv "sitemaps?`$select=sitemapnameunique,sitemapxml&`$filter=sitemapnameunique ne null"
    foreach ($t in $ticketTables) {
        $hit = @($allMaps.value | Where-Object { $_.sitemapxml -match "Entity=`"$t`"" })[0]
        if ($hit) { $App = $hit.sitemapnameunique; break }
    }
}
$webResources = @($entries | Where-Object { $_.action -like 'dataverse.webresource.*' } | ForEach-Object { $_.name } | Select-Object -Unique)
$businessRules = @($entries | Where-Object action -eq 'dataverse.businessrule.create' | ForEach-Object { "$($_.table): $($_.rule ?? $_.name)" } | Select-Object -Unique)
$pluginSteps = @($entries | Where-Object action -eq 'dataverse.pluginstep.created' | ForEach-Object { "$($_.message) $($_.table): $($_.name)" } | Select-Object -Unique)

# Main forms of the tables for which the ticket created columns, if no form is in the journal
foreach ($table in $columns.Keys) {
    if (@($forms.Values | Where-Object table -eq $table).Count) { continue }
    $main = Get-Dv "systemforms?`$select=formid,name&`$filter=objecttypecode eq '$table' and type eq 2 and formactivationstate eq 1"
    foreach ($f in @($main.value)) { $forms[$f.formid] = @{ table = $table; name = $f.name; id = $f.formid; implicit = $true } }
}

# --- 2. Metadata: forms
$attrCache = @{}
function Get-AttributeInfo([string]$Table, [string]$Column) {
    $k = "$Table.$Column"
    if (-not $attrCache.ContainsKey($k)) {
        try {
            $a = Get-Dv "EntityDefinitions(LogicalName='$Table')/Attributes(LogicalName='$Column')?`$select=LogicalName,RequiredLevel,SourceType,IsValidForUpdate,AttributeType"
            $attrCache[$k] = @{ required = ($a.RequiredLevel.Value -in 'ApplicationRequired', 'SystemRequired'); readOnly = ($a.SourceType -in 1, 2, 3) -or (-not $a.IsValidForUpdate); type = $a.AttributeType }
        } catch { $attrCache[$k] = $null }
    }
    return $attrCache[$k]
}

$formSpecs = @()
$placedColumns = @{}
foreach ($f in $forms.Values) {
    $sf = Get-Dv "systemforms($($f.id))?`$select=formxml,name,objecttypecode"
    [xml]$xml = $sf.formxml
    $ticketCols = if ($columns.Contains($f.table)) { @($columns[$f.table]) } else { @() }
    $wholeForm = $createdTables -contains $f.table -or -not $f.implicit
    $tabs = @()
    foreach ($tab in $xml.SelectNodes('//tabs/tab')) {
        if ($tab.visible -eq 'false') { continue }
        $sections = @()
        foreach ($sec in $tab.SelectNodes('.//sections/section')) {
            if ($sec.visible -eq 'false') { continue }
            $fields = @()
            foreach ($cell in $sec.SelectNodes('.//cell')) {
                if ($cell.visible -eq 'false') { continue }
                $ctl = $cell.SelectSingleNode('control[@datafieldname]')
                if (-not $ctl) { continue }
                $name = $ctl.datafieldname
                if (-not $wholeForm -and $ticketCols -notcontains $name) { continue }
                $info = Get-AttributeInfo $f.table $name
                if (-not $info) { continue }
                $placedColumns["$($f.table).$name"] = $true
                $fields += [ordered]@{ name = $name; required = [bool]$info.required; locked = [bool]($info.readOnly -or $ctl.disabled -eq 'true'); ticket = ($ticketCols -contains $name) }
            }
            if ($fields.Count -or $wholeForm) { $sections += [ordered]@{ name = $sec.name; header = ($sec.showlabel -ne 'false'); fields = $fields } }
        }
        if ($sections.Count) { $tabs += [ordered]@{ name = $tab.name; sections = $sections } }
    }
    if ($f.implicit -and -not $wholeForm -and -not $tabs.Count) { continue }   # form without any ticket field
    $formSpecs += [ordered]@{ table = $f.table; name = $sf.name; id = $f.id; tabs = $tabs }
}
$unplaced = @()
foreach ($table in $columns.Keys) { foreach ($c in $columns[$table]) { if (-not $placedColumns["$table.$c"]) { $unplaced += [ordered]@{ table = $table; column = $c } } } }

# --- 3. Views
$viewSpecs = @()
foreach ($v in $views.Values) {
    $sq = Get-Dv "savedqueries($($v.id))?`$select=name,layoutxml,returnedtypecode"
    [xml]$layout = $sq.layoutxml
    $cols = @($layout.SelectNodes('//cell') | ForEach-Object { $_.name } | Where-Object { $_ })
    $viewSpecs += [ordered]@{ table = $v.table; name = $sq.name; id = $v.id; columns = $cols }
}

# --- 4. Apps: sitemap subareas for the added tables
$appSpecs = @()
foreach ($appName in $appTables.Keys) {
    $sm = Get-Dv "sitemaps?`$select=sitemapxml&`$filter=sitemapnameunique eq '$appName'"
    if (-not @($sm.value).Count) { continue }
    [xml]$smXml = $sm.value[0].sitemapxml
    $entriesApp = @()
    foreach ($t in $appTables[$appName]) {
        $sub = $smXml.SelectSingleNode("//SubArea[@Entity='$t']")
        if ($sub) { $entriesApp += [ordered]@{ table = $t; subArea = $sub.Id } } else { $entriesApp += [ordered]@{ table = $t; subArea = $null } }
    }
    $appSpecs += [ordered]@{ app = $appName; entries = $entriesApp }
}

# --- 5. Write the spec
$sb = [System.Text.StringBuilder]::new()
$null = $sb.AppendLine("// Browser tests (Playwright) of ticket $IssueKey - Dataverse Alchemist.")
$null = $sb.AppendLine("// Run: Invoke-AlchemistUiTests.ps1 -IssueKey $IssueKey")
$null = $sb.AppendLine("// The generated section is rewritten by New-AlchemistUiTests.ps1; the custom section is kept.")
$null = $sb.AppendLine("import { test, expect } from '$libImport';")
$null = $sb.AppendLine()
$null = $sb.AppendLine("const APP = $(if ($App) { Q $App } else { 'null' });")
$null = $sb.AppendLine()
$null = $sb.AppendLine('// alchemist:auto:start')
$null = $sb.AppendLine("test.describe('$IssueKey - components', () => {")
foreach ($f in $formSpecs) {
    $null = $sb.AppendLine("    test($(Q "Form $($f.table) / $($f.name): opens and shows its fields"), async ({ d365 }) => {")
    $null = $sb.AppendLine("        const form = $(Js $f);")
    $null = $sb.AppendLine("        await d365.openForm({ app: APP, table: form.table, formId: form.id });")
    $null = $sb.AppendLine("        expect(await d365.currentFormId(), 'form opened').toBe(form.id);")
    $null = $sb.AppendLine("        for (const tab of form.tabs) {")
    $null = $sb.AppendLine("            await expect(d365.tab(tab.name), ``tab `${tab.name}``).toBeVisible();")
    $null = $sb.AppendLine("            await d365.selectTab(tab.name);")
    $null = $sb.AppendLine("            for (const section of tab.sections) {")
    $null = $sb.AppendLine("                if (section.header) { await expect(d365.section(section.name), ``section `${section.name}``).toBeVisible(); }")
    $null = $sb.AppendLine("                for (const field of section.fields) {")
    $null = $sb.AppendLine("                    await expect(d365.field(field.name), ``field `${field.name}``).toBeVisible();")
    $null = $sb.AppendLine("                    if (field.required) { await expect(d365.requiredIcon(field.name), ```${field.name} required``).toBeVisible(); }")
    $null = $sb.AppendLine("                    if (field.locked) { await expect(d365.lockedIcon(field.name), ```${field.name} read-only``).toBeVisible(); }")
    $null = $sb.AppendLine("                }")
    $null = $sb.AppendLine("            }")
    $null = $sb.AppendLine("        }")
    $null = $sb.AppendLine("        await d365.screenshot('form');")
    $null = $sb.AppendLine("        expect(d365.scriptErrors, 'script errors on the page').toEqual([]);")
    $null = $sb.AppendLine("    });")
    $null = $sb.AppendLine()
}
foreach ($u in $unplaced) {
    $null = $sb.AppendLine("    test.skip($(Q "Field $($u.table).$($u.column): on a form"), async () => {")
    $null = $sb.AppendLine("        // Skipped: the column is on no active main form; nothing to check in the UI.")
    $null = $sb.AppendLine("    });")
    $null = $sb.AppendLine()
}
foreach ($v in $viewSpecs) {
    $null = $sb.AppendLine("    test($(Q "View $($v.table) / $($v.name): opens with its columns"), async ({ d365 }) => {")
    $null = $sb.AppendLine("        const view = $(Js $v);")
    $null = $sb.AppendLine("        await d365.openView({ app: APP, table: view.table, viewId: view.id });")
    $null = $sb.AppendLine("        await expect(d365.viewSelector(view.id), 'view selected').toBeVisible();")
    $null = $sb.AppendLine("        expect(await d365.viewColumns(), 'columns shown').toEqual(view.columns);")
    $null = $sb.AppendLine("        await d365.screenshot('view');")
    $null = $sb.AppendLine("    });")
    $null = $sb.AppendLine()
}
foreach ($a in $appSpecs) {
    foreach ($en in $a.entries) {
        if (-not $en.subArea) {
            $null = $sb.AppendLine("    test($(Q "App $($a.app): access to $($en.table)"), async () => {")
            $null = $sb.AppendLine("        throw new Error($(Q "No sitemap subarea of $($a.app) points to $($en.table)"));")
            $null = $sb.AppendLine("    });")
            continue
        }
        $null = $sb.AppendLine("    test($(Q "App $($a.app): access to $($en.table) from the sitemap"), async ({ d365, page }) => {")
        $null = $sb.AppendLine("        await d365.openApp($(Q $a.app));")
        $null = $sb.AppendLine("        const entry = d365.sitemapEntry($(Q $en.subArea));")
        $null = $sb.AppendLine("        await expect(entry, 'sitemap entry').toBeVisible();")
        $null = $sb.AppendLine("        await entry.click();")
        $null = $sb.AppendLine("        await expect(page).toHaveURL(/etn=$($en.table)/);")
        $null = $sb.AppendLine("        await expect(page.locator('[data-id=`"grid-container`"], [data-id=`"GridRoot`"]').first(), 'list shown').toBeVisible();")
        $null = $sb.AppendLine("        await d365.screenshot('navigation');")
        $null = $sb.AppendLine("    });")
        $null = $sb.AppendLine()
    }
}
if (-not ($formSpecs.Count + $unplaced.Count + $viewSpecs.Count + @($appSpecs | ForEach-Object { $_.entries }).Count)) {
    $null = $sb.AppendLine("    test.skip(" + (Q "No UI component in the ticket journal (no form, view or app)") + ", async () => {});")
}
$null = $sb.AppendLine('});')
$null = $sb.AppendLine('// alchemist:auto:end')

# Custom section: kept if the file exists
$custom = $null
if (Test-Path -LiteralPath $OutputPath) {
    $existing = Get-Content -Raw -LiteralPath $OutputPath
    $m = [regex]::Match($existing, '(?s)// alchemist:custom:start.*?// alchemist:custom:end')
    if ($m.Success) { $custom = $m.Value }
}
if (-not $custom) {
    $todo = [System.Text.StringBuilder]::new()
    $null = $todo.AppendLine('// alchemist:custom:start')
    $null = $todo.AppendLine('// Behavior scenarios written by the agent (kept on regeneration). Ticket behaviors to cover:')
    foreach ($w in $webResources) { $null = $todo.AppendLine("//   - form script: $w") }
    foreach ($b in $businessRules) { $null = $todo.AppendLine("//   - business rule: $b") }
    foreach ($p in $pluginSteps) { $null = $todo.AppendLine("//   - plugin (error or result visible after saving): $p") }
    if (-not ($webResources.Count + $businessRules.Count + $pluginSteps.Count)) { $null = $todo.AppendLine('//   (no behavior found in the journal)') }
    $null = $todo.AppendLine("test.describe('$IssueKey - behaviors', () => {")
    $null = $todo.AppendLine('});')
    $null = $todo.Append('// alchemist:custom:end')
    $custom = $todo.ToString()
}
$null = $sb.AppendLine()
$null = $sb.AppendLine($custom)
$content = $sb.ToString()

$summary = [ordered]@{
    spec = $OutputPath; app = $App; forms = $formSpecs.Count; views = $viewSpecs.Count
    navigation = @($appSpecs | ForEach-Object { $_.entries }).Count; skippedColumns = $unplaced.Count
    behaviours = [ordered]@{ webResources = $webResources; businessRules = $businessRules; pluginSteps = $pluginSteps }
    rolledBack = $rolledBack
}
if ($DryRun) { $summary | ConvertTo-Json -Depth 5; $content; return }
New-Item -ItemType Directory -Force -Path (Split-Path $OutputPath) | Out-Null
Set-Content -LiteralPath $OutputPath -Value $content -Encoding utf8
Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action 'tests.ui.generated' -Details @{ spec = $OutputPath; forms = $formSpecs.Count; views = $viewSpecs.Count; navigation = $summary.navigation }
$summary | ConvertTo-Json -Depth 5




