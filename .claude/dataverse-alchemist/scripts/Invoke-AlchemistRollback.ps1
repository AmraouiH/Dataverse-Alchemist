#Requires -Version 7.0
<#
.SYNOPSIS
    Runs the approved rollback plan: only rollback-plan.json, and only if its id is the approved one.
    An error on one component does not stop the next ones: the result says exactly what was done.
    Run by the /alchemist-rollback command, after explicit user approval of the plan.
.EXAMPLE
    Invoke-AlchemistRollback.ps1 -IssueKey CRM-123 -PlanId 0f8fad5b-d9cb-469f-a165-70867728950e
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$IssueKey,
    [Parameter(Mandatory)][string]$PlanId,
    [string]$Environment,
    [string]$ConfigPath
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force

$config = Get-AlchemistConfig -ConfigPath $ConfigPath
$dvEnv = Get-DataverseEnvironment -Config $config -Name $Environment
$runFolder = Get-AlchemistRunFolder -Config $config -IssueKey $IssueKey
$plan = Get-Content -Raw -LiteralPath (Join-Path $runFolder 'rollback-plan.json') -Encoding utf8 | ConvertFrom-Json -Depth 10
if ($plan.id -ne $PlanId) { throw 'This plan is no longer the approved one: run the analysis again.' }

$tables = [Collections.Generic.HashSet[string]]::new()
$webResources = [Collections.Generic.List[string]]::new()

function Restore-Snapshot($file) {
    $saved = Get-Content -Raw -LiteralPath $file -Encoding utf8 | ConvertFrom-Json -Depth 10 -AsHashtable
    if ($saved.kind -eq 'Ribbon') {
        $table = $saved.name
        $solutionInfo = Resolve-AlchemistSolution -Config $config -Environment $dvEnv -IssueKey $IssueKey
        $schemaName = (Invoke-DataverseRequest -Environment $dvEnv -Path "EntityDefinitions(LogicalName='$table')?`$select=SchemaName").Content.SchemaName
        $restoredStates = Update-DataverseSolutionCustomizations -Environment $dvEnv -Solution $solutionInfo -Patch {
            param($document)
            $entity = $document.SelectSingleNode("//Entities/Entity[Name='$schemaName' or Name='$table']")
            if (-not $entity) { throw "Table '$table' missing from the exported solution." }
            $fragment = [xml]::new()
            $fragment.LoadXml($saved.xml)
            $imported = $document.ImportNode($fragment.DocumentElement, $true)
            $current = $entity.SelectSingleNode('RibbonDiffXml')
            if ($current) { [void]$entity.ReplaceChild($imported, $current) } else { [void]$entity.AppendChild($imported) }
        }
        if ($restoredStates) { Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action 'dataverse.states.restored' -Details @{ environment = $dvEnv.name; restored = $restoredStates } }
        [void]$tables.Add($table)
        return
    }
    if ($saved.kind -eq 'ColumnDefault') {
        $table, $column = $saved.name -split '\.', 2
        Update-DataverseColumnDefault -Environment $dvEnv -Table $table -Column $column -Value $saved.value
        [void]$tables.Add($table)
        return
    }
    if ($saved.kind -eq 'TableSetting') {
        Update-DataverseDefinition -Environment $dvEnv -Path $saved.path -Changes @{ IsQuickCreateEnabled = $saved.value }
        [void]$tables.Add($saved.name)
        return
    }
    Invoke-DataverseRequest -Environment $dvEnv -Method PATCH -Path $saved.path -Body $saved.fields | Out-Null
    if ($saved.table) { [void]$tables.Add($saved.table) }
    if ($saved.kind -eq 'WebResource' -and $saved.path -match '\(([0-9a-fA-F-]{36})\)') { $webResources.Add($Matches[1]) }
}

$results = [Collections.Generic.List[object]]::new()
foreach ($item in @($plan.items | Where-Object { $_.op -in 'delete', 'restore' })) {
    $result = [ordered]@{ op = $item.op; type = $item.type; label = $item.label; name = $item.name; ok = $true; error = $null }
    try {
        if ($item.op -eq 'restore') { Restore-Snapshot $item.path }
        elseif ($item.type -eq 'RolePrivilege') {
            # Privilege added to an existing role: path "roles(<id>)|<privilegeid>", removed by RemovePrivilegeRole.
            $rolePath, $privilegeId = $item.path -split '\|'
            Invoke-DataverseRequest -Environment $dvEnv -Method POST -Path "$rolePath/Microsoft.Dynamics.CRM.RemovePrivilegeRole" -Body @{ PrivilegeId = $privilegeId } | Out-Null
        }
        else {
            # An active business rule cannot be deleted: deactivate it first.
            if ($item.type -eq 'Workflow') { Invoke-DataverseRequest -Environment $dvEnv -Method PATCH -Path $item.path -Body @{ statecode = 0; statuscode = 1 } | Out-Null }
            Invoke-DataverseRequest -Environment $dvEnv -Method DELETE -Path $item.path | Out-Null
        }
        Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action 'rollback.component' -Details @{ op = $item.op; type = $item.type; name = $item.name }
        foreach ($covered in @($item.covers)) { if ($covered) { Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action 'rollback.component' -Details @{ op = 'delete'; type = $covered.type; name = $covered.name } } }
    }
    catch {
        $result.ok = $false
        $result.error = $_.Exception.Message
    }
    $results.Add($result)
}

# A restore is only visible once published.
$publishError = $null
if ($tables.Count -or $webResources.Count) {
    try { Publish-DataverseXml -Environment $dvEnv -Tables @($tables) -WebResourceIds @($webResources) | Out-Null }
    catch { $publishError = $_.Exception.Message }
}
$failed = @($results | Where-Object { -not $_.ok })
$summary = [ordered]@{
    planId = $PlanId; ok = (-not $failed.Count -and -not $publishError); done = $results.Count - $failed.Count; failed = $failed.Count
    publishError = $publishError; results = @($results); finishedAt = (Get-Date).ToString('o')
}
$json = $summary | ConvertTo-Json -Depth 6
$json | Set-Content -LiteralPath (Join-Path $runFolder 'rollback-result.json') -Encoding utf8
Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action 'rollback.finished' -Details @{ done = $summary.done; failed = $summary.failed }
$json

