#Requires -Version 7.0
<#
.SYNOPSIS
    Starts or updates the local documentation of the CRM project (markdown in the repository):
    index, data dictionary per table (generated from Dataverse) and feature page per ticket
    (generated from the ticket and the run journal).
.DESCRIPTION
    Generated content is placed between the <!-- alchemist:auto:start --> and <!-- alchemist:auto:end --> markers.
    A new generation only replaces that block: the hand-written text around it is kept.
    Read-only on the Dataverse side; only writes files in the documentation folder.
.EXAMPLE
    New-AlchemistDocumentation.ps1 -Tables account,rhz_contratservice -IssueKey CRM-412 -DryRun
#>
[CmdletBinding()]
param(
    [string[]]$Tables,
    [string]$IssueKey,
    # Documentation folder, relative to the repository. Default: docs.localPath, otherwise "docs".
    [string]$DocsPath,
    [string]$Environment,
    [string]$ConfigPath,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force

$config = Get-AlchemistConfig -ConfigPath $ConfigPath
$dvEnv = Get-DataverseEnvironment -Config $config -Name $Environment
$repoRoot = $config._meta.repoRoot
if (-not $DocsPath) { $DocsPath = Get-AlchemistSetting $config 'docs.localPath' -Default 'docs' }
$root = Join-Path $repoRoot $DocsPath
$tablePattern = Get-AlchemistSetting $config 'docs.tablePagePattern' -Default 'tables/{table}.md'
$featurePattern = Get-AlchemistSetting $config 'docs.featurePagePattern' -Default 'features/{key}.md'
$START = '<!-- alchemist:auto:start -->'; $END = '<!-- alchemist:auto:end -->'
$tableList = @($Tables | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
$written = [Collections.Generic.List[object]]::new()

function Q([string]$path) { (Invoke-DataverseRequest -Environment $dvEnv -Path $path).Content }
function L($label) { if ($label.UserLocalizedLabel) { $label.UserLocalizedLabel.Label } else { '' } }
function Cell($v) { ([string]$v -replace '\|', '\|' -replace "`r?`n", ' ').Trim() }

# Writes the generated block to a file, keeping the manual text around it (or creating the file with a header).
function Write-Doc([string]$relative, [string]$title, [string]$generated, [string]$manualIntro) {
    $file = Join-Path $root $relative
    $block = "$START`n$($generated.Trim())`n$END"
    $status = 'created'
    if (Test-Path -LiteralPath $file) {
        $current = Get-Content -LiteralPath $file -Raw -Encoding utf8
        $pattern = [regex]::Escape($START) + '[\s\S]*?' + [regex]::Escape($END)
        if ($current -match $pattern) { $content = [regex]::Replace($current, $pattern, { param($m) $block }); $status = 'updated' }
        else { $content = $current.TrimEnd() + "`n`n$block`n"; $status = 'appended' }
    }
    else {
        $content = "# $title`n`n$block`n`n## Notes`n`n$manualIntro`n"
    }
    $written.Add([ordered]@{ file = ((Join-Path $DocsPath $relative) -replace '\\', '/'); status = $status })
    if ($DryRun) { return }
    New-Item -ItemType Directory -Force -Path (Split-Path $file -Parent) | Out-Null
    [IO.File]::WriteAllText($file, $content.Replace("`r`n", "`n"), [Text.UTF8Encoding]::new($false))
}

#region Data dictionary
function Get-TableDoc([string]$table) {
    $e = Q "EntityDefinitions(LogicalName='$table')?`$select=LogicalName,DisplayName,DisplayCollectionName,Description,EntitySetName,OwnershipType,PrimaryNameAttribute,IsCustomEntity&`$expand=Attributes(`$select=LogicalName,DisplayName,AttributeTypeName,RequiredLevel,IsCustomAttribute,AttributeOf,SourceType,Description,IsValidForRead),Keys(`$select=LogicalName,DisplayName,KeyAttributes,EntityKeyIndexStatus)"
    $base = "EntityDefinitions(LogicalName='$table')/Attributes"
    $details = @{}
    foreach ($a in @((Q "$base/Microsoft.Dynamics.CRM.StringAttributeMetadata?`$select=LogicalName,MaxLength,AutoNumberFormat,FormulaDefinition").value)) {
        $d = @("max $($a.MaxLength)"); if ($a.AutoNumberFormat) { $d += "auto-number ``$($a.AutoNumberFormat)``" }; if ($a.FormulaDefinition) { $d += "formula ``$($a.FormulaDefinition)``" }; $details[$a.LogicalName] = $d -join ', '
    }
    foreach ($a in @((Q "$base/Microsoft.Dynamics.CRM.MemoAttributeMetadata?`$select=LogicalName,MaxLength").value)) { $details[$a.LogicalName] = "max $($a.MaxLength)" }
    foreach ($cast in 'DecimalAttributeMetadata', 'IntegerAttributeMetadata', 'DoubleAttributeMetadata', 'MoneyAttributeMetadata') {
        foreach ($a in @((Q "$base/Microsoft.Dynamics.CRM.$($cast)?`$select=LogicalName,MinValue,MaxValue,FormulaDefinition").value)) {
            $details[$a.LogicalName] = if ($a.FormulaDefinition) { "formula ``$($a.FormulaDefinition)``" } else { "$($a.MinValue) to $($a.MaxValue)" }
        }
    }
    foreach ($cast in 'PicklistAttributeMetadata', 'MultiSelectPicklistAttributeMetadata') {
        foreach ($a in @((Q "$base/Microsoft.Dynamics.CRM.$($cast)?`$select=LogicalName,DefaultFormValue&`$expand=OptionSet(`$select=Name,IsGlobal,Options)").value)) {
            $opts = @($a.OptionSet.Options | ForEach-Object { "$($_.Value) $(L $_.Label)" }) -join ' ; '
            $global = if ($a.OptionSet.IsGlobal) { "choix global ``$($a.OptionSet.Name)`` : " } else { '' }
            $default = if ($a.DefaultFormValue -ne $null -and $a.DefaultFormValue -ne -1) { " (default $($a.DefaultFormValue))" } else { '' }
            $details[$a.LogicalName] = "$global$opts$default"
        }
    }
    foreach ($a in @((Q "$base/Microsoft.Dynamics.CRM.BooleanAttributeMetadata?`$select=LogicalName,FormulaDefinition,DefaultValue&`$expand=OptionSet(`$select=TrueOption,FalseOption)").value)) {
        $d = "$(L $a.OptionSet.TrueOption.Label) / $(L $a.OptionSet.FalseOption.Label)"; if ($a.FormulaDefinition) { $d += ", formule ``$($a.FormulaDefinition)``" }; $details[$a.LogicalName] = $d
    }
    foreach ($a in @((Q "$base/Microsoft.Dynamics.CRM.DateTimeAttributeMetadata?`$select=LogicalName,Format,DateTimeBehavior,FormulaDefinition").value)) {
        $d = "$($a.Format), $($a.DateTimeBehavior.Value)"; if ($a.FormulaDefinition) { $d += ", formule ``$($a.FormulaDefinition)``" }; $details[$a.LogicalName] = $d
    }
    foreach ($a in @((Q "$base/Microsoft.Dynamics.CRM.LookupAttributeMetadata?`$select=LogicalName,Targets").value)) { $details[$a.LogicalName] = "to $(@($a.Targets) -join ', ')" }
    foreach ($a in @((Q "$base/Microsoft.Dynamics.CRM.ImageAttributeMetadata?`$select=LogicalName,MaxSizeInKB,CanStoreFullImage").value)) { $details[$a.LogicalName] = "$($a.MaxSizeInKB) Ko$(if ($a.CanStoreFullImage) { ', pleine taille' })" }
    foreach ($a in @((Q "$base/Microsoft.Dynamics.CRM.FileAttributeMetadata?`$select=LogicalName,MaxSizeInKB").value)) { $details[$a.LogicalName] = "$($a.MaxSizeInKB) Ko" }

    $req = @{ None = 'No'; Recommended = 'Recommended'; ApplicationRequired = 'Yes'; SystemRequired = 'Yes (system)' }
    $cols = @($e.Attributes | Where-Object { $_.IsCustomAttribute -and -not $_.AttributeOf -and $_.AttributeTypeName.Value -notin 'VirtualType', 'EntityNameType' -and $_.LogicalName -notmatch '_(base|name|yominame|timestamp|url)$' } | Sort-Object LogicalName)
    $lines = @("**$(L $e.DisplayName)** (``$($e.LogicalName)``) · Web API set ``$($e.EntitySetName)`` · ownership $($e.OwnershipType) · primary name ``$($e.PrimaryNameAttribute)``", '')
    if (L $e.Description) { $lines += (L $e.Description), '' }
    $lines += '## Custom columns', '', '| Column | Label | Type | Required | Detail |', '|---|---|---|---|---|'
    foreach ($c in $cols) {
        $type = ($c.AttributeTypeName.Value -replace 'Type$', '')
        if ($c.SourceType -eq 3) { $type += ' (formula)' } elseif ($c.SourceType -eq 1) { $type += ' (calculated)' } elseif ($c.SourceType -eq 2) { $type += ' (rollup)' }
        $lines += "| ``$($c.LogicalName)`` | $(Cell (L $c.DisplayName)) | $type | $($req[$c.RequiredLevel.Value]) | $(Cell $details[$c.LogicalName]) |"
    }
    if (-not $cols) { $lines += '| — | | | | |' }
    if (@($e.Keys).Count) {
        $lines += '', '## Alternate keys', '', '| Key | Label | Columns | Index |', '|---|---|---|---|'
        foreach ($k in $e.Keys) { $lines += "| ``$($k.LogicalName)`` | $(Cell (L $k.DisplayName)) | $(@($k.KeyAttributes) -join ', ') | $($k.EntityKeyIndexStatus) |" }
    }
    $forms = @((Q "systemforms?`$select=name,type,formxml&`$filter=objecttypecode eq '$table' and formactivationstate eq 1 and (type eq 2 or type eq 7)&`$orderby=type,name").value)
    if ($forms) { $lines += '', '## Forms', ''; $lines += @($forms | ForEach-Object { "- $($_.name) ($(if ($_.type -eq 7) { 'quick create' } else { 'main' }))" }) }
    # Form scripts: handlers declared in the FormXml of each form.
    $handlerRows = foreach ($f in $forms) {
        if (-not $f.formxml) { continue }
        $fx = [xml]$f.formxml
        foreach ($ev in @($fx.SelectNodes('//form/events/event'))) {
            foreach ($h in @($ev.SelectNodes('Handlers/Handler'))) {
                $on = if ($ev.GetAttribute('attribute')) { "$($ev.GetAttribute('name')) ``$($ev.GetAttribute('attribute'))``" } else { $ev.GetAttribute('name') }
                "| $($f.name) | $on | ``$($h.GetAttribute('functionName'))`` | ``$($h.GetAttribute('libraryName'))`` |"
            }
        }
    }
    if ($handlerRows) { $lines += '', '## Form scripts', '', '| Form | Event | Function | Web resource |', '|---|---|---|---|'; $lines += @($handlerRows) }
    $views = @((Q "savedqueries?`$select=name,isdefault&`$filter=returnedtypecode eq '$table' and querytype eq 0 and statecode eq 0&`$orderby=name").value)
    if ($views) { $lines += '', '## Public views', ''; $lines += @($views | ForEach-Object { "- $($_.name)$(if ($_.isdefault) { ' (default)' })" }) }
    $rules = @((Q "workflows?`$select=name,statecode,description&`$filter=category eq 2 and type eq 1 and primaryentity eq '$table'").value)
    if ($rules) { $lines += '', '## Business rules', ''; $lines += @($rules | ForEach-Object { "- $($_.name) — $(if ($_.statecode -eq 1) { 'active' } else { 'draft' })$(if ($_.description) { ': ' + (Cell $_.description) })" }) }
    # customizationlevel is not enough: internal 'ObjectModel Implementation' steps pass the filter. Keep those of non-Microsoft assemblies.
    $steps = @((Q "sdkmessageprocessingsteps?`$select=name,stage,mode,filteringattributes,statecode&`$expand=sdkmessageid(`$select=name),plugintypeid(`$select=assemblyname)&`$filter=sdkmessagefilterid/primaryobjecttypecode eq '$table' and ishidden/Value eq false").value | Where-Object { $_.plugintypeid.assemblyname -and $_.plugintypeid.assemblyname -notlike 'Microsoft.*' -and $_.stage -in 10, 20, 40 })
    if ($steps) {
        $stage = @{ 10 = 'PreValidation'; 20 = 'PreOperation'; 40 = 'PostOperation' }
        $lines += '', '## Plugins', '', '| Step | Message | Stage | Mode | Filters | State |', '|---|---|---|---|---|---|'
        foreach ($s in $steps) { $lines += "| $(Cell $s.name) | $($s.sdkmessageid.name) | $($stage[[int]$s.stage]) | $(if ($s.mode -eq 1) { 'Async' } else { 'Sync' }) | $($s.filteringattributes) | $(if ($s.statecode -eq 0) { 'active' } else { '**disabled**' }) |" }
    }
    $lines += '', "_Generated from Dataverse on $(Get-Date -Format 'yyyy-MM-dd')._"
    return @{ title = "$(L $e.DisplayName) (``$table``)"; body = ($lines -join "`n"); label = (L $e.DisplayName) }
}
#endregion

$tableTitles = @{}
foreach ($t in $tableList) {
    $doc = Get-TableDoc $t
    $tableTitles[$t] = $doc.label
    Write-Doc ($tablePattern -replace '\{table\}', $t) $doc.title $doc.body 'Rules and practices specific to this table (free text, kept on regeneration).'
}

#region Feature page
if ($IssueKey) {
    $runFolder = Get-AlchemistRunFolder -Config $config -IssueKey $IssueKey
    $ticket = $null
    $ticketFile = Join-Path $runFolder 'ticket.json'
    if (Test-Path -LiteralPath $ticketFile) { $ticket = Get-Content -LiteralPath $ticketFile -Raw -Encoding utf8 | ConvertFrom-Json }
    elseif (Test-AlchemistLocalTickets -Config $config) { $ticket = @(Read-AlchemistLocalTickets -Config $config | Where-Object key -EQ $IssueKey)[0] }
    if (-not $ticket) { throw "Ticket $IssueKey not found (no ticket.json in the run, no local ticket file)." }

    $journal = Join-Path $runFolder 'journal.jsonl'
    $entries = if (Test-Path -LiteralPath $journal) { @(Get-Content -LiteralPath $journal -Encoding utf8 | Where-Object { $_.Trim() } | ForEach-Object { $_.TrimStart([char]0xFEFF) | ConvertFrom-Json -Depth 20 }) } else { @() }
    $deleted = @($entries | Where-Object action -EQ 'dataverse.component.deleted' | ForEach-Object { [string]$_.id })
    $labels = @{ Entity = 'Table'; Attribute = 'Column'; EntityRelationship = 'Relationship'; OptionSet = 'Global choice'; SavedQuery = 'View'; SystemForm = 'Form'; WebResource = 'Web resource'; PluginAssembly = 'Assembly'; SdkMessageProcessingStep = 'Plugin step'; AppModule = 'App'; SiteMap = 'Navigation'; Role = 'Security role'; EntityKey = 'Alternate key'; Workflow = 'Business rule' }
    $seen = @{}
    $components = foreach ($en in $entries) { foreach ($c in @($en.components)) { if ($c -and $c.id -and -not $seen[$c.id] -and $c.id -notin $deleted) { $seen[$c.id] = $true; $c } } }
    $touched = @($entries | ForEach-Object { $_.table } | Where-Object { $_ } | Select-Object -Unique)
    $report = Join-Path $runFolder 'report.json'
    $summary = if (Test-Path -LiteralPath $report) { $r = Get-Content -LiteralPath $report -Raw -Encoding utf8 | ConvertFrom-Json; if ($r.summary -is [array]) { $r.summary -join "`n" } else { $r.summary } } else { $null }

    $lines = @("> Ticket: $IssueKey · Type: $($ticket.issueType) · Status: $($ticket.status) · Date: $(Get-Date -Format 'yyyy-MM-dd')", '', '## Need', '', ([string]$ticket.description).Trim())
    if ($ticket.acceptanceCriteria) { $lines += '', '## Acceptance criteria', '', ([string]$ticket.acceptanceCriteria).Trim() }
    $lines += '', '## Delivery', '', '| Component | Name | In the solution |', '|---|---|---|'
    foreach ($c in @($components)) { $lines += "| $($labels[$c.type] ?? $c.type) | ``$(Cell $c.name)`` | $(if ($c.status -in 'present', 'added') { 'yes' } else { $c.status }) |" }
    if (-not @($components).Count) { $lines += '| — | No Dataverse component journaled | |' }
    if ($touched) { $lines += '', "Tables involved: $(@($touched | ForEach-Object { "[$_]($((('../' + ($tablePattern -replace '\{table\}', $_)) -replace '\\', '/')))" }) -join ', ')." }
    if ($summary) { $lines += '', '## Summary', '', $summary }
    Write-Doc ($featurePattern -replace '\{key\}', $IssueKey -replace '\{slug\}', (ConvertTo-AlchemistSlug $ticket.summary)) "$IssueKey - $($ticket.summary)" ($lines -join "`n") 'Points of attention, decisions and manual testing (free text, kept on regeneration).'
}
#endregion

#region Index
$solutionName = [string](Get-AlchemistSetting $config 'dataverse.solution.default' -Default '?')
# Strings built separately: in @(a, b + c), the comma binds before + and concatenates arrays.
$indexLines = @("Functional and technical documentation of **$(Get-AlchemistSetting $config 'project.name' -Default 'this CRM project')**.", '', "Reference Dataverse solution: ``$solutionName``.")
$tableDir = Join-Path $root (Split-Path ($tablePattern -replace '\{table\}', 'x') -Parent)
$featureDir = Join-Path $root (Split-Path ($featurePattern -replace '\{key\}', 'x' -replace '\{slug\}', 'x') -Parent)
$tableFiles = @(if (Test-Path $tableDir) { Get-ChildItem $tableDir -Filter *.md | ForEach-Object BaseName }) + @($tableList) | Select-Object -Unique | Sort-Object
$featureFiles = @(if (Test-Path $featureDir) { Get-ChildItem $featureDir -Filter *.md | ForEach-Object BaseName }) + @(if ($IssueKey) { ($featurePattern -replace '\{key\}', $IssueKey -replace '\{slug\}', '') | Split-Path -LeafBase }) | Select-Object -Unique | Sort-Object
$indexLines += '', '## Data dictionary', ''
# Page title: the one computed in this run, otherwise the first line of the existing file.
function Get-PageTitle([string]$relative, [string]$pattern) {
    $first = Get-Content -LiteralPath (Join-Path $root $relative) -TotalCount 1 -ErrorAction SilentlyContinue
    if ($first -match $pattern) { return $Matches[1] }
    return $null
}
if (-not $tableFiles) { $indexLines += '_No table documented._' }
foreach ($t in $tableFiles) {
    $rel = ($tablePattern -replace '\{table\}', $t) -replace '\\', '/'
    $title = if ($tableTitles[$t]) { $tableTitles[$t] } else { Get-PageTitle $rel '^# (.+?) \(' }
    $indexLines += "- [$t]($rel)" + $(if ($title) { " — $title" } else { '' })
}
$indexLines += '', '## Features', ''
if (-not $featureFiles) { $indexLines += '_No feature documented._' }
$featureFolder = (Split-Path ($featurePattern -replace '\{key\}', 'x' -replace '\{slug\}', 'x') -Parent) -replace '\\', '/'
foreach ($f in $featureFiles) {
    $rel = "$featureFolder/$f.md"
    $title = Get-PageTitle $rel '^# (.+)$'
    $indexLines += "- [$(if ($title) { $title } else { $f })]($rel)"
}
Write-Doc 'README.md' 'CRM documentation' ($indexLines -join "`n") 'Conventions, useful links and contacts (free text, kept on regeneration).'
#endregion

if ($IssueKey -and -not $DryRun) { Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action 'docs.generated' -Details @{ docsPath = $DocsPath; files = @($written | ForEach-Object file) } }
[ordered]@{ dryRun = [bool]$DryRun; docsPath = $DocsPath; files = $written } | ConvertTo-Json -Depth 4
