#Requires -Version 7.0
<#
.SYNOPSIS
    Analyzes (read-only) the conventions already in place in the CRM, so new components stay consistent:
    prefixes actually used, technical name format, lookup suffix, labels and descriptions,
    local or global choices and value style, date behaviors, text lengths, relationship names,
    web resource tree, plugin step names.
    Writes .alchemist/runs/<KEY>/conventions-crm.md (with -IssueKey).
.EXAMPLE
    Get-DataverseConventions.ps1 -IssueKey CRM-123 -Tables account,contact
#>
[CmdletBinding()]
param(
    [string[]]$Tables,
    [string]$Solution,
    [string]$IssueKey,
    [int]$Samples = 12,
    [string]$Environment,
    [string]$ConfigPath
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force

$config = Get-AlchemistConfig -ConfigPath $ConfigPath
$dvEnv = Get-DataverseEnvironment -Config $config -Name $Environment
$solutionInfo = Resolve-AlchemistSolution -Config $config -Environment $dvEnv -Solution $Solution -IssueKey $IssueKey -Optional
$prefix = if ($solutionInfo) { $solutionInfo.publisher.prefix } else { $null }
$Tables = @($Tables | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })

# Without tables given: tables of the solution (10 max).
if (-not $Tables.Count -and $solutionInfo) {
    $ids = @((Invoke-DataverseRequest -Environment $dvEnv -Path "solutioncomponents?`$select=objectid&`$filter=_solutionid_value eq $($solutionInfo.solutionId) and componenttype eq 1&`$top=10").Content.value.objectid)
    $Tables = @($ids | ForEach-Object { (Invoke-DataverseRequest -Environment $dvEnv -Path "EntityDefinitions($_)?`$select=LogicalName").Content.LogicalName })
}
if (-not $Tables.Count) { throw "Specify -Tables (or choose the ticket solution first)." }

function Get-Label($label) { if ($label -and $label.UserLocalizedLabel) { return $label.UserLocalizedLabel.Label } return $null }
function Get-Suffix([string]$schemaName) { $i = $schemaName.IndexOf('_'); if ($i -lt 0) { return $schemaName } return $schemaName.Substring($i + 1) }
function Get-NameStyle([string]$name) {
    if ($name -match '_') { return 'with_underscores' }
    if ($name -cmatch '^[A-Z][A-Za-z0-9]*$') { if ($name -cmatch '[a-z]') { return 'PascalCase' } return 'UPPERCASE' }
    if ($name -cmatch '^[a-z][a-z0-9]*$') { return 'lowercase' }
    if ($name -cmatch '^[a-z][A-Za-z0-9]*$') { return 'camelCase' }
    return 'other'
}
function Format-Distribution($items) {
    $total = @($items).Count
    if (-not $total) { return '_no data_' }
    return (@($items | Group-Object | Sort-Object Count -Descending | ForEach-Object { "$($_.Name): $($_.Count) ($([math]::Round(100 * $_.Count / $total))%)" }) -join ' · ')
}

$attributes = [System.Collections.Generic.List[object]]::new()
$strings = [System.Collections.Generic.List[object]]::new()
$dates = [System.Collections.Generic.List[object]]::new()
$choices = [System.Collections.Generic.List[object]]::new()
$relationships = [System.Collections.Generic.List[object]]::new()

foreach ($table in $Tables) {
    $base = "EntityDefinitions(LogicalName='$table')/Attributes"
    foreach ($a in (Invoke-DataverseRequest -Environment $dvEnv -Path "$($base)?`$select=LogicalName,SchemaName,AttributeType,DisplayName,Description,RequiredLevel,AttributeOf&`$filter=IsCustomAttribute eq true").Content.value) {
        if ($a.AttributeOf) { continue }
        $attributes.Add([pscustomobject]@{
                table = $table; schemaName = $a.SchemaName; type = [string]$a.AttributeType
                displayName = Get-Label $a.DisplayName; hasDescription = [bool](Get-Label $a.Description); required = $a.RequiredLevel.Value
            })
    }
    foreach ($a in (Invoke-DataverseRequest -Environment $dvEnv -Path "$base/Microsoft.Dynamics.CRM.StringAttributeMetadata?`$select=LogicalName,MaxLength,FormatName&`$filter=IsCustomAttribute eq true").Content.value) {
        $strings.Add([pscustomobject]@{ name = $a.LogicalName; maxLength = $a.MaxLength; format = $a.FormatName.Value })
    }
    foreach ($a in (Invoke-DataverseRequest -Environment $dvEnv -Path "$base/Microsoft.Dynamics.CRM.DateTimeAttributeMetadata?`$select=LogicalName,Format,DateTimeBehavior&`$filter=IsCustomAttribute eq true").Content.value) {
        $dates.Add([pscustomobject]@{ name = $a.LogicalName; format = $a.Format; behavior = $a.DateTimeBehavior.Value })
    }
    foreach ($a in (Invoke-DataverseRequest -Environment $dvEnv -Path "$base/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?`$select=LogicalName&`$filter=IsCustomAttribute eq true&`$expand=OptionSet").Content.value) {
        $values = @($a.OptionSet.Options | ForEach-Object { [long]$_.Value })
        $style = if (-not $values.Count) { 'empty' } elseif (($values | Measure-Object -Minimum).Minimum -ge 10000) { 'publisher prefix (>= 10000)' } else { 'small integers' }
        $choices.Add([pscustomobject]@{ name = $a.LogicalName; global = [bool]$a.OptionSet.IsGlobal; optionSet = $a.OptionSet.Name; valueStyle = $style; sample = ($values | Select-Object -First 3) -join ',' })
    }
    foreach ($r in (Invoke-DataverseRequest -Environment $dvEnv -Path "EntityDefinitions(LogicalName='$table')/ManyToOneRelationships?`$select=SchemaName,ReferencedEntity,ReferencingAttribute,IsCustomRelationship&`$filter=IsCustomRelationship eq true").Content.value) {
        $relationships.Add([pscustomobject]@{ schemaName = $r.SchemaName; referencing = "$table.$($r.ReferencingAttribute)"; referenced = $r.ReferencedEntity })
    }
}

$prefixFilter = if ($prefix) { "startswith(name,'$($prefix)_')" } else { "ismanaged eq false" }
$webResources = @((Invoke-DataverseRequest -Environment $dvEnv -Path "webresourceset?`$select=name,webresourcetype&`$filter=$prefixFilter&`$top=300").Content.value)
$steps = @((Invoke-DataverseRequest -Environment $dvEnv -Path "sdkmessageprocessingsteps?`$select=name,stage,mode&`$filter=customizationlevel eq 1&`$orderby=modifiedon desc&`$top=40").Content.value)
$assemblies = @((Invoke-DataverseRequest -Environment $dvEnv -Path "pluginassemblies?`$select=name,version&`$filter=customizationlevel eq 1").Content.value)
# The service does not filter this metadata: sorting happens here. Managed choices come from Microsoft apps.
$globalChoices = @((Invoke-DataverseRequest -Environment $dvEnv -Path 'GlobalOptionSetDefinitions').Content.value | Where-Object { -not $_.IsManaged } | Sort-Object Name)

$lookups = @($attributes | Where-Object { $_.type -in 'Lookup', 'Customer', 'Owner' })
$md = [Text.StringBuilder]::new()
function Line([string]$text = '') { [void]$md.AppendLine($text) }

Line "# Observed CRM conventions"
Line
Line "Environment: $($dvEnv.name) · Tables analyzed: $($Tables -join ', ')"
if ($solutionInfo) { Line "Ticket solution: **$($solutionInfo.uniqueName)** · Publisher: **$($solutionInfo.publisher.uniqueName)** · Prefix: **$($prefix)_** · Choice values from **$($solutionInfo.publisher.optionValuePrefix * 10000)**" }
Line
Line "## Custom columns ($($attributes.Count))"
Line "- Prefixes used: $(Format-Distribution ($attributes | ForEach-Object { $_.schemaName.Split('_')[0].ToLowerInvariant() }))"
if ($prefix -and @($attributes | Where-Object { $_.schemaName.Split('_')[0] -ne $prefix }).Count) {
    Line "- WARNING: some columns use a prefix other than the solution publisher's ($prefix): flag it in the plan."
}
Line "- Technical name format (after the prefix): $(Format-Distribution ($attributes | ForEach-Object { Get-NameStyle (Get-Suffix $_.schemaName) }))"
Line "- Lookups ending with 'Id': $(Format-Distribution ($lookups | ForEach-Object { if ((Get-Suffix $_.schemaName) -match 'id$') { 'yes' } else { 'no' } }))"
Line "- Description filled in: $(Format-Distribution ($attributes | ForEach-Object { if ($_.hasDescription) { 'yes' } else { 'no' } }))"
Line "- Requirement level: $(Format-Distribution ($attributes | ForEach-Object required))"
Line "- Types: $(Format-Distribution ($attributes | ForEach-Object type))"
Line
Line "Examples (technical name -> label):"
$attributes | Select-Object -First $Samples | ForEach-Object { Line "- ``$($_.table).$($_.schemaName)`` ($($_.type)) -> '$($_.displayName)'" }
Line
Line "## Text"
Line "- Max lengths: $(Format-Distribution ($strings | ForEach-Object maxLength))"
Line "- Formats: $(Format-Distribution ($strings | ForEach-Object format))"
Line
Line "## Dates"
Line "- Format: $(Format-Distribution ($dates | ForEach-Object format)) · Behavior: $(Format-Distribution ($dates | ForEach-Object behavior))"
Line
Line "## Choices"
Line "- Local / global: $(Format-Distribution ($choices | ForEach-Object { if ($_.global) { 'global' } else { 'local' } }))"
Line "- Value style: $(Format-Distribution ($choices | ForEach-Object valueStyle))"
$choices | Select-Object -First $Samples | ForEach-Object { Line "- ``$($_.name)``: $(if ($_.global) { "global $($_.optionSet)" } else { 'local' }), values $($_.sample)…" }
Line
Line "## Unmanaged global choices ($($globalChoices.Count))"
$globalChoices | ForEach-Object { Line "- ``$($_.Name)`` '$(Get-Label $_.DisplayName)': $(@($_.Options | ForEach-Object { Get-Label $_.Label }) -join ', ')" }
Line
Line "## Custom N:1 relationships"
$relationships | Select-Object -First $Samples | ForEach-Object { Line "- ``$($_.schemaName)``: $($_.referencing) -> $($_.referenced)" }
Line
Line "## Web resources ($($webResources.Count))"
Line "- Tree: $(Format-Distribution ($webResources | ForEach-Object { $parts = $_.name.Split('/'); if ($parts.Count -gt 1) { ($parts[0..($parts.Count - 2)] -join '/') + '/' } else { '(root)' } }))"
$webResources | Where-Object { $_.webresourcetype -eq 3 } | Select-Object -First $Samples | ForEach-Object { Line "- ``$($_.name)``" }
Line
Line "## Plugins"
Line "- Assemblies: $(@($assemblies | ForEach-Object { "$($_.name) $($_.version)" }) -join ', ')"
Line "- Step name examples:"
$steps | Select-Object -First $Samples | ForEach-Object { Line "  - $($_.name)" }

$text = $md.ToString()
if ($IssueKey) {
    $out = Join-Path (Get-AlchemistRunFolder -Config $config -IssueKey $IssueKey) 'conventions-crm.md'
    $text | Set-Content -LiteralPath $out -Encoding utf8
    $text; "_Saved to: $($out)_"
}
else { $text }
