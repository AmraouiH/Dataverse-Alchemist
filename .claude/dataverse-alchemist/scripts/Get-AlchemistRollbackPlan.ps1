#Requires -Version 7.0
<#
.SYNOPSIS
    Computes the rollback of a ticket, read-only, from its journal and its backups.
.DESCRIPTION
    Created by the ticket: to delete, unless it holds data. Changed: to restore, if a backup exists.
    Anything uncertain is kept and explained. The plan is written to rollback-plan.json:
    Invoke-AlchemistRollback.ps1 only runs that file, never a recomputed list.
    Run by the /alchemist-rollback command, after explicit user approval.
.EXAMPLE
    Get-AlchemistRollbackPlan.ps1 -IssueKey CRM-123
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$IssueKey,
    [string]$Environment,
    [string]$ConfigPath
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force

$config = Get-AlchemistConfig -ConfigPath $ConfigPath
$dvEnv = Get-DataverseEnvironment -Config $config -Name $Environment
$runFolder = Get-AlchemistRunFolder -Config $config -IssueKey $IssueKey
$journalFile = Join-Path $runFolder 'journal.jsonl'
$entries = if (Test-Path -LiteralPath $journalFile) { @(Get-Content -LiteralPath $journalFile -Encoding utf8 | Where-Object { $_.Trim() } | ForEach-Object { $_.TrimStart([char]0xFEFF) | ConvertFrom-Json -Depth 20 }) } else { @() }

$CREATED_TYPES = @{
    'dataverse.table.create' = 'Entity'; 'dataverse.column.create' = 'Attribute'; 'dataverse.globalchoice.create' = 'OptionSet'
    'dataverse.view.create' = 'SavedQuery'; 'dataverse.form.create' = 'SystemForm'; 'dataverse.webresource.created' = 'WebResource'
    'dataverse.pluginassembly.created' = 'PluginAssembly'; 'dataverse.pluginstep.created' = 'SdkMessageProcessingStep'; 'dataverse.app.create' = 'AppModule'
    'dataverse.role.create' = 'Role'; 'dataverse.key.create' = 'EntityKey'; 'dataverse.businessrule.create' = 'Workflow'
}
$MODIFIED_TYPES = @{
    'dataverse.view.update' = 'SavedQuery'; 'dataverse.form.update' = 'SystemForm'; 'dataverse.form.replace' = 'SystemForm'
    'dataverse.webresource.updated' = 'WebResource'; 'dataverse.pluginassembly.updated' = 'PluginAssembly'; 'dataverse.pluginstep.updated' = 'SdkMessageProcessingStep'
}
$NAMES = @{ Entity = 'Table'; Attribute = 'Column'; EntityRelationship = 'Relationship'; OptionSet = 'Global choice'; SavedQuery = 'View'; SystemForm = 'Form'; WebResource = 'Web resource'; PluginAssembly = 'Plugin'; SdkMessageProcessingStep = 'Step'; AppModule = 'App'; AppSiteMap = 'Navigation'; Ribbon = 'Ribbon'; SiteMap = 'Navigation'; ColumnDefault = 'Default value'; TableSetting = 'Quick create'; Record = 'Test data'; Role = 'Security role'; EntityKey = 'Alternate key'; Workflow = 'Business rule'; RolePrivilege = 'Role privilege' }
$ORDER = @{ Record = 0; Workflow = 1; RolePrivilege = 1.2; Role = 1.5; EntityKey = 7.5; AppModule = 2; AppSiteMap = 2.5; SdkMessageProcessingStep = 3; PluginAssembly = 4; SavedQuery = 5; SystemForm = 6; WebResource = 7; EntityRelationship = 8; Attribute = 8; Entity = 9; OptionSet = 10 }

$created = [ordered]@{}
$modified = [ordered]@{}
$records = [ordered]@{}
$rolePrivileges = [ordered]@{}
$undone = @{}
foreach ($entry in $entries) {
    $type = $CREATED_TYPES[$entry.action]
    if ($entry.action -eq 'dataverse.table.create') {
        $created["Entity:$($entry.table)"] = @{ type = 'Entity'; name = [string]$entry.table; id = $null; relationship = $null }
    }
    elseif ($type) {
        foreach ($component in @($entry.components | Where-Object type -EQ $type)) {
            $created["$($type):$($component.name)"] = @{ type = $type; name = [string]$component.name; id = [string]$component.id; relationship = $null }
        }
        $relationship = @($entry.components | Where-Object type -EQ 'EntityRelationship') | Select-Object -First 1
        if ($type -eq 'Attribute' -and $relationship) { $created[@($created.Keys)[-1]].relationship = [string]$relationship.id }
        # An app takes its navigation with it: it is deleted right after.
        if ($type -eq 'AppModule') {
            foreach ($map in @($entry.components | Where-Object type -EQ 'SiteMap')) { $created["AppSiteMap:$($map.name)"] = @{ type = 'AppSiteMap'; name = [string]$map.name; id = [string]$map.id; relationship = $null } }
        }
    }
    if ($MODIFIED_TYPES[$entry.action]) {
        foreach ($component in @($entry.components | Where-Object type -EQ $MODIFIED_TYPES[$entry.action])) { $modified["$($component.type):$($component.name)"] = @{ type = [string]$component.type; name = [string]$component.name } }
    }
    if ($entry.action -eq 'dataverse.column.update') { $modified["ColumnDefault:$($entry.table).$($entry.column)"] = @{ type = 'ColumnDefault'; name = "$($entry.table).$($entry.column)" } }
    if ($entry.action -eq 'dataverse.table.quickcreate') { $modified["TableSetting:$($entry.table)"] = @{ type = 'TableSetting'; name = [string]$entry.table } }
    if ($entry.action -eq 'dataverse.ribbon.update') { $modified["Ribbon:$($entry.table)"] = @{ type = 'Ribbon'; name = [string]$entry.table } }
    if ($entry.action -eq 'dataverse.app.addtable') { $modified["SiteMap:$($entry.app)"] = @{ type = 'SiteMap'; name = [string]$entry.app } }
    if ($entry.action -eq 'dataverse.request' -and $entry.entityId -and $entry.method -eq 'POST') { $records["$($entry.path)($($entry.entityId))"] = @{ set = [string]$entry.path; id = [string]$entry.entityId } }
    if ($entry.action -eq 'dataverse.request' -and $entry.method -eq 'DELETE') { $records.Remove([string]$entry.path) }
    # Privileges added to an existing role: to remove (the role itself is not deleted).
    if ($entry.action -eq 'dataverse.role.update') {
        foreach ($priv in @($entry.privilegesAdded)) { $privName = ([string]$priv -split ':')[0]; $rolePrivileges["$($entry.roleId)|$privName"] = @{ roleId = [string]$entry.roleId; role = [string]$entry.role; privilege = $privName } }
    }    if ($entry.action -eq 'rollback.component') { $undone["$($entry.type):$($entry.name)"] = $true }
}
foreach ($key in @($undone.Keys)) { $created.Remove($key); $modified.Remove($key) }

$tablesCreated = @($created.Values | Where-Object type -EQ 'Entity' | ForEach-Object name)
$items = [Collections.Generic.List[object]]::new()
function Add-Item($operation, $type, $name, $reason, $path, $extra = @{}) {
    $item = [ordered]@{ op = $operation; type = $type; label = $NAMES[$type] ?? $type; name = $name; reason = $reason; path = $path; order = $ORDER[$type] ?? 1 }
    foreach ($key in $extra.Keys) { $item[$key] = $extra[$key] }
    $items.Add($item)
}
function Test-Absent([string]$path) {
    try { Invoke-DataverseRequest -Environment $dvEnv -Path $path | Out-Null; return $false }
    catch { if ($_.Exception.Message -match 'HTTP 404') { return $true } else { throw } }
}
$tableInfo = @{}
function Get-TableInfo([string]$table) {
    if (-not $tableInfo.ContainsKey($table)) { $tableInfo[$table] = (Invoke-DataverseRequest -Environment $dvEnv -Path "EntityDefinitions(LogicalName='$table')?`$select=EntitySetName,PrimaryIdAttribute").Content }
    return $tableInfo[$table]
}
# The ticket test data will be deleted: it does not count as data to protect.
function Test-HasData([string]$table, [string]$filter) {
    $info = Get-TableInfo $table
    $query = "$($info.EntitySetName)?`$select=$($info.PrimaryIdAttribute)&`$top=100$(if ($filter) { "&`$filter=$filter" })"
    $rows = @((Invoke-DataverseRequest -Environment $dvEnv -Path $query).Content.value)
    $own = @($records.Values | Where-Object set -EQ $info.EntitySetName | ForEach-Object id)
    return [bool]@($rows | Where-Object { $_.($info.PrimaryIdAttribute) -notin $own }).Count
}

foreach ($rp in $rolePrivileges.Values) {
    if ($undone.ContainsKey("RolePrivilege:$($rp.role) / $($rp.privilege)")) { continue }
    # Privilege of a table created by the ticket: deleted with the table.
    if (@($tablesCreated | Where-Object { $rp.privilege.ToLowerInvariant().EndsWith($_.ToLowerInvariant()) }).Count) { continue }
    $privilege = @((Invoke-DataverseRequest -Environment $dvEnv -Path "privileges?`$select=privilegeid&`$filter=name eq '$($rp.privilege)'").Content.value)[0]
    if (-not $privilege) { Add-Item 'absent' 'RolePrivilege' "$($rp.role) / $($rp.privilege)" 'Privilege not found.' $null; continue }
    Add-Item 'delete' 'RolePrivilege' "$($rp.role) / $($rp.privilege)" 'Added to the role by the ticket.' "roles($($rp.roleId))|$($privilege.privilegeid)"
}
foreach ($record in $records.Values) { Add-Item 'delete' 'Record' "$($record.set) $($record.id)" 'Created by the ticket tests.' "$($record.set)($($record.id))" }

# A missing backup cannot be guessed: the component stays as is, and the plan says so.
$backupFolder = Join-Path $runFolder 'backup'
foreach ($change in $modified.Values) {
    if ($created.Contains("$($change.type):$($change.name)")) { continue }
    # A column or table created by the ticket goes with its deletion: its setting is not to be restored.
    if ($change.type -eq 'ColumnDefault' -and $created.Contains("Attribute:$($change.name)")) { continue }
    if ($change.type -eq 'TableSetting' -and $created.Contains("Entity:$($change.name)")) { continue }
    $file = Get-AlchemistSnapshotPath -RunFolder $runFolder -Type $change.type -Name $change.name
    if (Test-Path -LiteralPath $file) { Add-Item 'restore' $change.type $change.name 'Goes back to its state before the ticket.' $file }
    else { Add-Item 'keep' $change.type $change.name 'Changed without a backup: review by hand.' $null }
}

$kept = @{}
# Global choices come last: they depend on the columns kept.
foreach ($item in @($created.Values | Sort-Object { $_.type -eq 'OptionSet' })) {
    $type = $item.type; $name = $item.name; $id = $item.id
    $path = switch ($type) {
        'SavedQuery' { "savedqueries($id)" } 'SystemForm' { "systemforms($id)" } 'WebResource' { "webresourceset($id)" }
        'PluginAssembly' { "pluginassemblies($id)" } 'SdkMessageProcessingStep' { "sdkmessageprocessingsteps($id)" } 'AppModule' { "appmodules($id)" }
        'AppSiteMap' { "sitemaps($id)" } 'Role' { "roles($id)" } 'Workflow' { "workflows($id)" } 'OptionSet' { "GlobalOptionSetDefinitions($id)" } 'Entity' { "EntityDefinitions(LogicalName='$name')" }
    }
    if ($type -eq 'EntityKey') {
        $keyTable, $keyName = $name -split '\.', 2
        $path = "EntityDefinitions(LogicalName='$keyTable')/Keys(LogicalName='$keyName')"
    }
    if ($type -eq 'Attribute') {
        $table, $column = $name -split '\.', 2
        $path = "EntityDefinitions(LogicalName='$table')/Attributes(LogicalName='$column')"
    }
    # Deleting a table takes its columns, forms and views with it.
    $owner = if ($type -in 'SavedQuery', 'SystemForm', 'Workflow') { ($name -split ' / ')[0] } elseif ($type -eq 'Attribute') { $table } else { $null }
    if ($owner -in $tablesCreated) { continue }

    $probe = if ($type -eq 'OptionSet') { "GlobalOptionSetDefinitions($id)?`$select=Name" } else { $path }
    if (Test-Absent $probe) { Add-Item 'absent' $type $name 'Already absent from the CRM.' $null; continue }

    if ($type -eq 'Entity' -and (Test-HasData $name $null)) { Add-Item 'keep' $type $name 'Holds records: decide by hand.' $null; $kept[$type] = $true; continue }
    if ($type -eq 'Attribute') {
        try {
            $field = if ($item.relationship) { "_$($column)_value" } else { $column }
            if (Test-HasData $table "$field ne null") { Add-Item 'keep' $type $name 'Holds values: decide by hand.' $null; $kept[$type] = $true; continue }
        }
        catch { Add-Item 'keep' $type $name 'Data could not be checked: decide by hand.' $null; $kept[$type] = $true; continue }
        # A relationship deletes itself, and its column with it.
        if ($item.relationship) { $path = "RelationshipDefinitions($($item.relationship))" }
    }
    if ($type -eq 'OptionSet' -and $kept['Attribute']) { Add-Item 'keep' $type $name 'May be used by a column that is kept.' $null; continue }
    $covers = @()
    if ($type -eq 'Entity') { $covers = @($created.Values | Where-Object { ($_.type -eq 'Attribute' -and $_.name -like "$name.*") -or ($_.type -in 'SavedQuery', 'SystemForm' -and $_.name -like "$name / *") } | ForEach-Object { @{ type = $_.type; name = $_.name } }) }
    Add-Item 'delete' $type $name 'Created by the ticket.' $path @{ covers = $covers }
}

$plan = [ordered]@{
    id = [guid]::NewGuid().ToString(); issueKey = $IssueKey; environment = $dvEnv.name; url = $dvEnv.url; createdAt = (Get-Date).ToString('o')
    items = @($items | Sort-Object { $_.order }, { $_.name })
}
$json = $plan | ConvertTo-Json -Depth 8
$json | Set-Content -LiteralPath (Join-Path $runFolder 'rollback-plan.json') -Encoding utf8
$json

