#Requires -Version 7.0
<#
.SYNOPSIS
    Checks that each component created or changed during the ticket (journal.jsonl) is in the ticket solution.
    Result written to .alchemist/runs/<KEY>/solution-check.json (used by the HTML report).
    -AddMissing adds the missing components (write: after user approval).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$IssueKey,
    [switch]$AddMissing,
    [string]$Environment,
    [string]$ConfigPath
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force

$config = Get-AlchemistConfig -ConfigPath $ConfigPath
$dvEnv = Get-DataverseEnvironment -Config $config -Name $Environment
$solutionInfo = Resolve-AlchemistSolution -Config $config -Environment $dvEnv -IssueKey $IssueKey
$runFolder = Get-AlchemistRunFolder -Config $config -IssueKey $IssueKey
$journalPath = Join-Path $runFolder 'journal.jsonl'
if (-not (Test-Path -LiteralPath $journalPath)) { throw "No journal for $IssueKey." }

$components = [ordered]@{}
foreach ($line in Get-Content -LiteralPath $journalPath) {
    if (-not $line.Trim()) { continue }
    $entry = $line | ConvertFrom-Json -AsHashtable
    # Component deleted during the ticket (trial, cleanup): it must no longer be checked.
    if ($entry.action -eq 'dataverse.component.deleted' -and $entry.id) { $components.Remove(([string]$entry.id).ToLowerInvariant()); continue }
    foreach ($component in @($entry.components)) {
        if ($component -and $component.id) {
            $component.table = $entry.table
            $components[$component.id.ToLowerInvariant()] = $component
        }
    }
}

# A table as a full root component (rootcomponentbehavior 0) includes its columns, views, forms and relationships,
# which are then not listed individually in solutioncomponents.
$fullTables = @{}
$tableRows = (Invoke-DataverseRequest -Environment $dvEnv -Path "solutioncomponents?`$select=objectid&`$filter=_solutionid_value eq $($solutionInfo.solutionId) and componenttype eq 1 and rootcomponentbehavior eq 0").Content.value
foreach ($row in @($tableRows)) {
    if ($row) { $fullTables[(Invoke-DataverseRequest -Environment $dvEnv -Path "EntityDefinitions($($row.objectid))?`$select=LogicalName").Content.LogicalName] = $true }
}

$results = foreach ($component in $components.Values) {
    $inSolution = Test-DataverseSolutionComponent -Environment $dvEnv -Solution $solutionInfo -ComponentId $component.id
    # Only the subcomponents embedded by the table count (not a role, rule or key deleted since).
    if (-not $inSolution -and $component.type -in 'Attribute', 'SavedQuery', 'SystemForm', 'EntityRelationship', 'EntityKey' -and $component.table -and $fullTables.ContainsKey($component.table)) { $inSolution = $true }
    if (-not $inSolution -and $AddMissing) {
        Add-DataverseSolutionComponent -Environment $dvEnv -Solution $solutionInfo -ComponentId $component.id -ComponentType $component.type | Out-Null
        $inSolution = $true
    }
    [ordered]@{ type = $component.type; name = $component.name; id = $component.id; inSolution = $inSolution }
}
$results = @($results)

$check = [ordered]@{
    solution  = $solutionInfo.uniqueName
    checkedAt = (Get-Date).ToString('o')
    total     = $results.Count
    missing   = @($results | Where-Object { -not $_.inSolution }).Count
    components = $results
}
$check | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runFolder 'solution-check.json') -Encoding utf8

$results | ForEach-Object { [pscustomobject]$_ } | Format-Table type, name, inSolution, id -AutoSize | Out-String -Width 250
"Solution '$($solutionInfo.uniqueName)': $($check.total - $check.missing)/$($check.total) components present."
if ($check.missing) { exit 1 }
