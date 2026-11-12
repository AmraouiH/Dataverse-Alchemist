#Requires -Version 7.0
<#
.SYNOPSIS
    Imports a CSV file into a table by upsert on an alternate key: creates missing rows, updates
    existing ones, and leaves identical ones untouched (a second run changes nothing).
.DESCRIPTION
    CSV headers:
        - simple column: logical name (rhz_serialnumber, rhz_equipmenttype…). Values are converted according to the Dataverse
            type: choice (numeric value or label), date (yyyy-mm-dd), number, yes/no (true/false, yes/no, oui/non, 1/0).
        - lookup: <NavigationName>-><entityset>.<business column>, e.g. rhz_AccountId->accounts.rhz_internalcode.
            The target row is found by its business column (exactly one match, otherwise an error).
    Every row is checked before the first write: a data error imports nothing.
    An API error during the write (network, permissions) leaves the previous rows written: rerunning the same
    file, the import being idempotent, completes the job without duplicates.
.EXAMPLE
    Import-DataverseData.ps1 -Table rhz_equipment -CsvPath equipment.csv -KeyColumns rhz_serialnumber -IssueKey CRM-1 -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Table,
    [Parameter(Mandatory)][string]$CsvPath,
    # Columns of the alternate key (in the same order as the key).
    [Parameter(Mandatory)][string[]]$KeyColumns,
    [string]$Delimiter = ';',
    [string]$Environment,
    [string]$ConfigPath,
    [string]$IssueKey,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force

$config = Get-AlchemistConfig -ConfigPath $ConfigPath
$dvEnv = Get-DataverseEnvironment -Config $config -Name $Environment
$Table = $Table.ToLowerInvariant()
$keyList = @($KeyColumns | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
$rows = @(Import-Csv -LiteralPath $CsvPath -Delimiter $Delimiter -Encoding utf8)
if (-not $rows) { throw "Empty file: $CsvPath" }

$meta = (Invoke-DataverseRequest -Environment $dvEnv -Path "EntityDefinitions(LogicalName='$Table')?`$select=EntitySetName,PrimaryIdAttribute&`$expand=Attributes(`$select=LogicalName,AttributeTypeName,IsValidForCreate,IsValidForUpdate),Keys(`$select=KeyAttributes,EntityKeyIndexStatus)").Content
$set = $meta.EntitySetName
$key = @($meta.Keys | Where-Object { -not (Compare-Object @($_.KeyAttributes) $keyList) }) | Select-Object -First 1
if (-not $key) { throw "No alternate key on $Table for ($($keyList -join ', ')). Create the key first (New-DataverseAlternateKey.ps1)." }
if ($key.EntityKeyIndexStatus -ne 'Active') { throw "The key ($($keyList -join ', ')) is not active ($($key.EntityKeyIndexStatus))." }
$types = @{}; foreach ($a in $meta.Attributes) { $types[$a.LogicalName] = $a.AttributeTypeName.Value }

# Choice: label -> value.
$choiceMaps = @{}
function Get-ChoiceMap([string]$column) {
    if (-not $choiceMaps.ContainsKey($column)) {
        $cast = if ($types[$column] -eq 'MultiSelectPicklistType') { 'MultiSelectPicklistAttributeMetadata' } else { 'PicklistAttributeMetadata' }
        $opts = (Invoke-DataverseRequest -Environment $dvEnv -Path "EntityDefinitions(LogicalName='$Table')/Attributes(LogicalName='$column')/Microsoft.Dynamics.CRM.$($cast)?`$select=LogicalName&`$expand=OptionSet(`$select=Options)").Content.OptionSet.Options
        $map = @{}; foreach ($o in $opts) { $map[[string]$o.Value] = [int]$o.Value; $map[$o.Label.UserLocalizedLabel.Label.ToLowerInvariant()] = [int]$o.Value }
        $choiceMaps[$column] = $map
    }
    return $choiceMaps[$column]
}
function ConvertTo-DataverseValue([string]$column, [string]$raw) {
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    $v = $raw.Trim()
    switch ($types[$column]) {
        'PicklistType' { $m = Get-ChoiceMap $column; if (-not $m.ContainsKey($v.ToLowerInvariant())) { throw "Unknown choice value for ${column}: '$v'." }; return $m[$v.ToLowerInvariant()] }
        'BooleanType' { if ($v -match '^(true|oui|1|yes)$') { return $true } elseif ($v -match '^(false|non|0|no)$') { return $false } else { throw "Invalid boolean for ${column}: '$v'." } }
        { $_ -in 'IntegerType', 'BigIntType' } { return [long]$v }
        { $_ -in 'DecimalType', 'DoubleType', 'MoneyType' } { return [decimal]::Parse($v.Replace(',', '.'), [Globalization.CultureInfo]::InvariantCulture) }
        'DateTimeType' { return ([datetime]::ParseExact($v, 'yyyy-MM-dd', $null)).ToString('yyyy-MM-dd') }
        default { return $v }
    }
}

# Lookups: header Nav->entityset.column; resolved by the business column, with a cache.
$lookupCache = @{}
function Resolve-Lookup([string]$targetSet, [string]$businessColumn, [string]$value) {
    $cacheKey = "$targetSet|$businessColumn|$value"
    if (-not $lookupCache.ContainsKey($cacheKey)) {
        $targetMeta = (Invoke-DataverseRequest -Environment $dvEnv -Path "EntityDefinitions?`$select=PrimaryIdAttribute&`$filter=EntitySetName eq '$targetSet'").Content.value[0]
        if (-not $targetMeta) { throw "Unknown entity set '$targetSet'." }
        $found = @((Invoke-DataverseRequest -Environment $dvEnv -Path "$($targetSet)?`$select=$($targetMeta.PrimaryIdAttribute)&`$filter=$businessColumn eq '$(ConvertTo-ODataString $value)'&`$top=2").Content.value)
        if ($found.Count -ne 1) { throw "$targetSet.$businessColumn = '$value': $($found.Count) match(es), 1 expected." }
        $lookupCache[$cacheKey] = $found[0].($targetMeta.PrimaryIdAttribute)
    }
    return $lookupCache[$cacheKey]
}

$headers = @($rows[0].PSObject.Properties.Name)
foreach ($k in $keyList) { if ($k -notin $headers) { throw "Key column '$k' missing from the file." } }

# 1. Prepare and check every row (no write).
$plan = for ($i = 0; $i -lt $rows.Count; $i++) {
    $row = $rows[$i]; $line = $i + 2
    try {
        $body = [ordered]@{}; $compare = [ordered]@{}
        foreach ($h in $headers) {
            $raw = [string]$row.$h
            if ($h -match '^(?<nav>\w+)->(?<set>\w+)\.(?<col>\w+)$') {
                if ([string]::IsNullOrWhiteSpace($raw)) { continue }
                $id = Resolve-Lookup $Matches.set $Matches.col $raw.Trim()
                $body["$($Matches.nav)@odata.bind"] = "/$($Matches.set)($id)"
                $compare["_$($Matches.nav.ToLowerInvariant())_value"] = $id
            }
            else {
                $col = $h.ToLowerInvariant()
                if (-not $types.ContainsKey($col)) { throw "Column '$h' does not exist on $Table." }
                if ($col -in $keyList) { continue }
                $value = ConvertTo-DataverseValue $col $raw
                $body[$col] = $value; $compare[$col] = $value
            }
        }
        $keyPath = ($keyList | ForEach-Object { $kv = ConvertTo-DataverseValue $_ ([string]$row.$_); if ($null -eq $kv) { throw "Empty key ($_)." }; "$_='$(ConvertTo-ODataString ([string]$kv))'" }) -join ','
        [ordered]@{ line = $line; keyPath = $keyPath; body = $body; compare = $compare }
    }
    catch { throw "Row ${line}: $($_.Exception.Message) Nothing was imported." }
}

# 2. Current state of each row: missing, identical or to update.
foreach ($p in $plan) {
    try {
        $select = (@($p.compare.Keys) + $meta.PrimaryIdAttribute) -join ','
        $current = (Invoke-DataverseRequest -Environment $dvEnv -Path "$set($($p.keyPath))?`$select=$select").Content
        $p.id = $current.($meta.PrimaryIdAttribute)
        $diff = [ordered]@{}
        foreach ($c in $p.compare.Keys) {
            $now = $current.$c; $new = $p.compare[$c]
            $same = if ($null -eq $now -or $null -eq $new) { ($null -eq $now) -and ($null -eq $new) }
                elseif ($new -is [decimal]) { [decimal]$now -eq $new }
                elseif ($new -is [bool]) { [bool]$now -eq $new }
                elseif ($types[$c] -eq 'DateTimeType') { ([string]$now).Substring(0, 10) -eq [string]$new }   # day only
                else { [string]$now -eq [string]$new }
            if (-not $same) { $diff[$c] = @{ before = $now; after = $new } }
        }
        $p.action = if ($diff.Count) { 'update' } else { 'unchanged' }; $p.diff = $diff
    }
    catch {
        if ($_.Exception.Message -notmatch 'HTTP 404') { throw }
        $p.action = 'create'
    }
}

$summary = [ordered]@{ create = @($plan | Where-Object action -EQ 'create').Count; update = @($plan | Where-Object action -EQ 'update').Count; unchanged = @($plan | Where-Object action -EQ 'unchanged').Count }
if ($DryRun) {
    [ordered]@{ dryRun = $true; environment = "$($dvEnv.name) ($($dvEnv.url))"; table = $Table; key = $keyList; summary = $summary
        lines = @($plan | ForEach-Object { [ordered]@{ line = $_.line; key = $_.keyPath; action = $_.action; changes = @($_.diff.Keys) } }) } | ConvertTo-Json -Depth 5
    return
}

# 3. Writes: upsert by key (PATCH on the alternate key).
$results = foreach ($p in $plan) {
    if ($p.action -eq 'unchanged') { [ordered]@{ line = $p.line; key = $p.keyPath; action = 'unchanged' }; continue }
    # Plain upsert: If-None-Match / If-Match on an alternate key return 404 (seen on CRM-415).
    # The action was already determined in step 2; the 204 response gives no id, so read back by key.
    Invoke-DataverseRequest -Environment $dvEnv -Method PATCH -Path "$set($($p.keyPath))" -Body $p.body | Out-Null
    $id = if ($p.id) { $p.id } else { (Invoke-DataverseRequest -Environment $dvEnv -Path "$set($($p.keyPath))?`$select=$($meta.PrimaryIdAttribute)").Content.($meta.PrimaryIdAttribute) }
    if ($p.action -eq 'create') {
        # Same shape as Invoke-Dataverse: the rollback plan deletes the rows created.
        Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action 'dataverse.request' -Details @{ environment = $dvEnv.name; method = 'POST'; path = $set; entityId = $id; solution = $null; source = 'import' }
    }
    else {
        Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action 'dataverse.record.update' -Details @{ environment = $dvEnv.name; path = "$set($id)"; changes = $p.diff; source = 'import' }
    }
    [ordered]@{ line = $p.line; key = $p.keyPath; action = $p.action; id = $id }
}
Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action 'dataverse.import' -Details @{ environment = $dvEnv.name; table = $Table; file = (Split-Path $CsvPath -Leaf); summary = $summary }
[ordered]@{ imported = $true; table = $Table; summary = $summary; lines = @($results) } | ConvertTo-Json -Depth 5
