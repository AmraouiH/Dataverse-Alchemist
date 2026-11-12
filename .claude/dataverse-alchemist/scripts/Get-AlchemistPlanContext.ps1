#Requires -Version 7.0
<#
.SYNOPSIS
    Gathers in one call everything the plan step needs to read: a model turn costs far more than a script.
.DESCRIPTION
    Without -Tables: git tree, config, lessons, ticket, solutions, default solution applied to the run, branch.
    With -Tables: languages, allowed capabilities, CRM conventions and table summary (custom columns, form layouts, steps).
    The full detail of each table is written to the run folder. Nothing is written elsewhere.
.EXAMPLE
    pwsh -NoProfile -File Get-AlchemistPlanContext.ps1 -IssueKey CRM-123
    pwsh -NoProfile -File Get-AlchemistPlanContext.ps1 -IssueKey CRM-123 -Tables contact,account
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$IssueKey,
    [string[]]$Tables,
    [string]$Environment,
    [string]$ConfigPath
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force

$config = Get-AlchemistConfig -ConfigPath $ConfigPath
$runFolder = Get-AlchemistRunFolder -Config $config -IssueKey $IssueKey
$withConfig = @{}
if ($ConfigPath) { $withConfig.ConfigPath = $ConfigPath }
$withEnv = $withConfig.Clone()
if ($Environment) { $withEnv.Environment = $Environment }

# A failing section is reported without depriving the agent of the others.
function Write-Section($title, [scriptblock]$body) {
    "`n## $title"
    try { & $body | Out-String -Width 250 | ForEach-Object { $_.TrimEnd() } }
    catch { "FAILED: $($_.Exception.Message)" }
}

function Get-FormLayout($formXml) {
    $doc = [xml]$formXml
    foreach ($tab in $doc.SelectNodes('/form/tabs/tab')) {
        $tabLabel = $tab.SelectSingleNode('labels/label')?.GetAttribute('description') ?? $tab.GetAttribute('name')
        foreach ($section in $tab.SelectNodes('.//section')) {
            $sectionLabel = $section.SelectSingleNode('labels/label')?.GetAttribute('description') ?? $section.GetAttribute('name')
            $rows = foreach ($row in $section.SelectNodes('rows/row')) {
                $cells = foreach ($cell in $row.SelectNodes('cell')) {
                    $field = $cell.SelectSingleNode('control')?.GetAttribute('datafieldname')
                    if ($field) { $field } else { '-' }
                }
                # Empty rows only give subgrids their height.
                if ($cells | Where-Object { $_ -ne '-' }) { $cells -join ' + ' }
            }
            "    $tabLabel > ${sectionLabel}: $(if ($rows) { $rows -join ' ; ' } else { '(no field)' })"
        }
    }
}

"# Context of $IssueKey"

if (-not $Tables) {
    Write-Section 'Working tree' {
        # The local ticket file receives the closing comments: it does not block the next ticket.
        $localTickets = Get-AlchemistSetting $config 'jira.localTicketsFile'
        $dirty = @(git status --porcelain | Where-Object { -not $localTickets -or $_ -notlike "*$localTickets" })
        if ($dirty) { 'NOT CLEAN, to be decided by the user:'; $dirty } else { 'Clean.' }
    }
    Write-Section 'Configuration' {
        # In a separate process: that script ends with exit.
        $check = pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Test-AlchemistConfig.ps1') @withEnv 2>&1
        $failures = @($check | Where-Object { "$_" -match '^KO\s' })
        if ($failures) { $failures } else { 'OK.' }
    }
    Write-Section 'Lessons learned' { & (Join-Path $PSScriptRoot 'Get-AlchemistKnowledge.ps1') @withConfig }
    Write-Section 'Ticket' { & (Join-Path $PSScriptRoot 'Get-JiraTicket.ps1') -IssueKey $IssueKey -DownloadAttachments @withConfig }
    Write-Section 'Unmanaged solutions' { & (Join-Path $PSScriptRoot 'Get-DataverseSolutions.ps1') @withEnv }
    Write-Section 'Run solution' {
        $defaultSolution = Get-AlchemistSetting $config 'dataverse.solution.default'
        if (Test-Path -LiteralPath (Join-Path $runFolder 'context.json')) { Get-Content -Raw -LiteralPath (Join-Path $runFolder 'context.json') }
        elseif ($defaultSolution) { & (Join-Path $PSScriptRoot 'Set-AlchemistRunSolution.ps1') -IssueKey $IssueKey -Solution $defaultSolution @withEnv }
        else { 'NO default solution: ask the user before going further.' }
    }
    Write-Section 'Branch' { & (Join-Path $PSScriptRoot 'Resolve-BaseBranch.ps1') -IssueKey $IssueKey @withConfig }
    return
}

$tableNames = @($Tables | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
$dvEnv = Get-DataverseEnvironment -Config $config -Name $Environment

Write-Section 'Languages' {
    "Base language (LCID): $(Get-DataverseBaseLanguage -Environment $dvEnv)"
    "Installed languages: $((Get-DataverseProvisionedLanguages -Environment $dvEnv) -join ', ')"
}
Write-Section 'Allowed capabilities (allow)' {
    $caps = Get-AlchemistAllowedCapabilities -Config $config
    "Allowed: $(($caps.Keys | Where-Object { $caps[$_].allowed }) -join ', ')"
    "Not allowed (items classified as manual in the plan): $($off = @($caps.Keys | Where-Object { -not $caps[$_].allowed }); if ($off) { $off -join ', ' } else { 'none' })"
}
Write-Section 'CRM conventions' { & (Join-Path $PSScriptRoot 'Get-DataverseConventions.ps1') -IssueKey $IssueKey -Tables $tableNames @withEnv }

$summary = foreach ($tableName in $tableNames) {
    Write-Section "Table $tableName" {
        try { $info = & (Join-Path $PSScriptRoot 'Get-DataverseTableInfo.ps1') -Table $tableName -Attributes -Forms -PluginSteps -Json @withEnv | ConvertFrom-Json -Depth 10 }
        catch { "Not found in this environment ($($_.Exception.Message)): to create if the ticket asks for it."; return }

        $detail = Join-Path $runFolder "existing-$tableName.json"
        $info | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $detail -Encoding utf8

        "$($info.displayName) | set: $($info.entitySetName) | primary name: $($info.primaryName)"
        "$(@($info.attributes).Count) columns (all in ${detail}: look there for a possible duplicate)"
        # Those of other publishers (Power Pages...) stay in the detail: they would drown the ones that matter.
        $prefix = (Get-Content -Raw -LiteralPath (Join-Path $runFolder 'context.json') | ConvertFrom-Json).solution.publisher.prefix
        $custom = @($info.attributes | Where-Object { $_.custom -and $_.logicalName -like "$($prefix)_*" })
        "Publisher columns ($($prefix)_): $(if ($custom) { ($custom | ForEach-Object { "$($_.logicalName) [$($_.type)] '$($_.displayName)'" }) -join ', ' } else { 'none' })"

        $others = @($info.forms | Where-Object { $_.type -ne 'Main' } | ForEach-Object { "$($_.name) ($($_.type))" })
        if ($others) { "Other forms: $($others -join ', ')" }

        $t = ConvertTo-ODataString $tableName
        $forms2 = (Invoke-DataverseRequest -Environment $dvEnv -Path "systemforms?`$select=formid,name,formxml,isdefault&`$filter=objecttypecode eq '$t' and type eq 2 and formactivationstate eq 1&`$orderby=name").Content.value
        'Active main forms:'
        foreach ($form in $forms2) {
            "  $($form.name)$(if ($form.isdefault) { ' (default)' }) [$($form.formid)]"
            Get-FormLayout $form.formxml
        }

        $steps = @($info.pluginSteps | Where-Object { $_.enabled -and $_.pluginType -notlike 'Microsoft.*' })
        "Team steps: $(if ($steps) { ($steps | ForEach-Object { "$($_.message) $($_.stage) $($_.pluginType)" } | Select-Object -Unique) -join ', ' } else { 'none' })"
    }
}
$summary
# The expert reviews this summary rather than the table detail.
$summary | Set-Content -LiteralPath (Join-Path $runFolder 'existing-summary.md') -Encoding utf8

