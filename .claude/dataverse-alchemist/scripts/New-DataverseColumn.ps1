#Requires -Version 7.0
<#
.SYNOPSIS
    Creates a Dataverse column (field) in the configured solution. -DryRun shows the request without calling anything.
.EXAMPLE
    New-DataverseColumn.ps1 -Table account -SchemaName cts_CodeClient -DisplayName "Code client" -Type String -MaxLength 50 -DryRun
    New-DataverseColumn.ps1 -Table account -SchemaName cts_Segment -DisplayName "Segment" -Type Choice -Options "PME;ETI;Grand compte"
    New-DataverseColumn.ps1 -Table contact -SchemaName cts_AgenceId -DisplayName "Agence" -Type Lookup -TargetTable cts_agence
    New-DataverseColumn.ps1 -Table contact -SchemaName cts_TestId -DisplayName "test" -DisplayNameTranslations "1033=testo" -Type Lookup -TargetTable account
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Table,
    [Parameter(Mandatory)][string]$SchemaName,
    [Parameter(Mandatory)][string]$DisplayName,
    [Parameter(Mandatory)][ValidateSet('String', 'Memo', 'Integer', 'BigInt', 'Decimal', 'Float', 'Money', 'Boolean', 'DateTime', 'Choice', 'MultiChoice', 'Lookup', 'Customer', 'Image', 'File')][string]$Type,
    # Labels in languages other than the base language: "1036=Client,1031=Kunde"
    [string[]]$DisplayNameTranslations,
    [string]$Description,
    [string[]]$DescriptionTranslations,
    [ValidateSet('None', 'Recommended', 'ApplicationRequired')][string]$RequiredLevel = 'None',
    [int]$MaxLength,
    [ValidateSet('Text', 'Email', 'Url', 'Phone', 'TickerSymbol', 'TextArea', 'RichText')][string]$Format,
    [ValidateSet('None', 'Duration', 'TimeZone', 'Language', 'Locale')][string]$IntegerFormat = 'None',
    # Auto-number text column, e.g. "CASE-{SEQNUM:5}"
    [string]$AutoNumberFormat,
    # Power Fx formula column (read-only, computed on read), e.g. "DateDiff(rhz_startdate, rhz_enddate, TimeUnit.Days)".
    # Types: String, Integer, Decimal, Float, Boolean, DateTime.
    [string]$Formula,
    # Maximum size (KB) of an Image or File column
    [int]$MaxSizeKB,
    [double]$MinValue,
    [double]$MaxValue,
    [int]$Precision = 2,
    [ValidateSet('DateOnly', 'DateAndTime')][string]$DateFormat = 'DateOnly',
    [ValidateSet('UserLocal', 'DateOnly', 'TimeZoneIndependent')][string]$DateBehavior = 'UserLocal',
    # Choice: "A;B;C" (values generated with the publisher option value prefix) or JSON '[{"value":100000000,"label":"A"}]'
    [string]$Options,
    # Choice based on an existing global option set (logical name)
    [string]$GlobalOptionSet,
    [string]$TrueLabel,
    [string]$FalseLabel,
    [switch]$DefaultTrue,
    [string]$TargetTable,
    [string]$RelationshipSchemaName,
    [ValidateSet('Restrict', 'RemoveLink', 'Cascade')][string]$DeleteBehavior = 'RemoveLink',
    # DoNotDisplay avoids an entry in the associated menu of the target table.
    [ValidateSet('UseCollectionName', 'DoNotDisplay')][string]$AssociatedMenuBehavior = 'UseCollectionName',
    [switch]$Publish,
    [string]$Solution,
    [string]$Environment,
    [string]$ConfigPath,
    [string]$IssueKey,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force

$config = Get-AlchemistConfig -ConfigPath $ConfigPath
$dvEnv = Get-DataverseEnvironment -Config $config -Name $Environment
$solutionInfo = Resolve-AlchemistSolution -Config $config -Environment $dvEnv -Solution $Solution -IssueKey $IssueKey
$solutionName = $solutionInfo.uniqueName
# The base language comes from the organization: a wrong config would send labels in a missing language.
$lcid = Get-DataverseBaseLanguage -Environment $dvEnv
$configuredLcid = Get-AlchemistSetting $config 'dataverse.baseLanguageCode'
if ($configuredLcid -and [int]$configuredLcid -ne $lcid) { Write-Warning "dataverse.baseLanguageCode=$configuredLcid ignored: the organization base language is $lcid." }
# Publisher of the target solution: prefix of names and choice values.
$prefix = $solutionInfo.publisher.prefix
$optionPrefix = $solutionInfo.publisher.optionValuePrefix

Assert-PublisherPrefix -Solution $solutionInfo -Name $SchemaName -What 'SchemaName'
$Table = $Table.ToLowerInvariant()
$logicalName = $SchemaName.ToLowerInvariant()

function Label([string]$text, $translations) { New-DataverseLabel -Text $text -LanguageCode $lcid -Translations $translations }

$displayNameLabels = ConvertTo-LabelTranslations $DisplayNameTranslations
$descriptionLabels = ConvertTo-LabelTranslations $DescriptionTranslations
$languages = @(@($lcid) + @($displayNameLabels.Keys) + @($descriptionLabels.Keys) | Select-Object -Unique)

$requiredLevelMetadata = @{ Value = $RequiredLevel; CanBeChanged = $true; ManagedPropertyLogicalName = 'canmodifyrequirementlevelsettings' }

function Get-OptionList {
    if (-not $Options) { throw "-Options is required for a local Choice (or use -GlobalOptionSet)." }
    $items = if ($Options.TrimStart().StartsWith('[')) {
        @($Options | ConvertFrom-Json | ForEach-Object { @{ value = [int]$_.value; label = $_.label } })
    }
    else {
        $i = 0
        @($Options.Split(';') | Where-Object { $_.Trim() } | ForEach-Object { @{ value = $optionPrefix * 10000 + $i; label = $_.Trim() }; $i++ })
    }
    return @($items | ForEach-Object { @{ Value = $_.value; Label = (Label $_.label) } })
}

$common = @{
    SchemaName    = $SchemaName
    DisplayName   = Label $DisplayName $displayNameLabels
    RequiredLevel = $requiredLevelMetadata
}
if ($Description) { $common.Description = Label $Description $descriptionLabels }

$path = "EntityDefinitions(LogicalName='$Table')/Attributes"
$body = $null

switch ($Type) {
    'String' {
        $body = $common + @{
            '@odata.type' = 'Microsoft.Dynamics.CRM.StringAttributeMetadata'
            MaxLength     = if ($MaxLength) { $MaxLength } else { 100 }
            FormatName    = @{ Value = if ($Format -and $Format -notin 'TextArea', 'RichText') { $Format } else { 'Text' } }
        }
        if ($AutoNumberFormat) { $body.AutoNumberFormat = $AutoNumberFormat }
    }
    'Memo' {
        $body = $common + @{
            '@odata.type' = 'Microsoft.Dynamics.CRM.MemoAttributeMetadata'
            MaxLength     = if ($MaxLength) { $MaxLength } else { 2000 }
            Format        = 'TextArea'
            FormatName    = @{ Value = if ($Format -eq 'RichText') { 'RichText' } else { 'Text' } }
        }
    }
    'Integer' {
        $body = $common + @{
            '@odata.type' = 'Microsoft.Dynamics.CRM.IntegerAttributeMetadata'
            Format        = $IntegerFormat
            MinValue      = if ($PSBoundParameters.ContainsKey('MinValue')) { [int]$MinValue } else { -2147483648 }
            MaxValue      = if ($PSBoundParameters.ContainsKey('MaxValue')) { [int]$MaxValue } else { 2147483647 }
        }
    }
    'BigInt' {
        $body = $common + @{ '@odata.type' = 'Microsoft.Dynamics.CRM.BigIntAttributeMetadata' }
    }
    'Float' {
        $body = $common + @{
            '@odata.type' = 'Microsoft.Dynamics.CRM.DoubleAttributeMetadata'
            Precision     = $Precision
            MinValue      = if ($PSBoundParameters.ContainsKey('MinValue')) { $MinValue } else { -100000000000 }
            MaxValue      = if ($PSBoundParameters.ContainsKey('MaxValue')) { $MaxValue } else { 100000000000 }
        }
    }
    'Image' {
        $body = $common + @{
            '@odata.type'     = 'Microsoft.Dynamics.CRM.ImageAttributeMetadata'
            CanStoreFullImage = $true
            MaxSizeInKB      = if ($MaxSizeKB) { $MaxSizeKB } else { 10240 }
        }
    }
    'File' {
        $body = $common + @{
            '@odata.type' = 'Microsoft.Dynamics.CRM.FileAttributeMetadata'
            MaxSizeInKB   = if ($MaxSizeKB) { $MaxSizeKB } else { 32768 }
        }
    }
    'Decimal' {
        $body = $common + @{
            '@odata.type' = 'Microsoft.Dynamics.CRM.DecimalAttributeMetadata'
            Precision     = $Precision
            MinValue      = if ($PSBoundParameters.ContainsKey('MinValue')) { $MinValue } else { -100000000000 }
            MaxValue      = if ($PSBoundParameters.ContainsKey('MaxValue')) { $MaxValue } else { 100000000000 }
        }
    }
    'Money' {
        $body = $common + @{
            '@odata.type'   = 'Microsoft.Dynamics.CRM.MoneyAttributeMetadata'
            Precision       = $Precision
            PrecisionSource = 2
            MinValue        = if ($PSBoundParameters.ContainsKey('MinValue')) { $MinValue } else { -922337203685477 }
            MaxValue        = if ($PSBoundParameters.ContainsKey('MaxValue')) { $MaxValue } else { 922337203685477 }
        }
    }
    'Boolean' {
        $yes = if ($TrueLabel) { $TrueLabel } elseif ($lcid -eq 1036) { 'Oui' } else { 'Yes' }
        $no = if ($FalseLabel) { $FalseLabel } elseif ($lcid -eq 1036) { 'Non' } else { 'No' }
        $body = $common + @{
            '@odata.type' = 'Microsoft.Dynamics.CRM.BooleanAttributeMetadata'
            DefaultValue  = [bool]$DefaultTrue
            OptionSet     = @{
                '@odata.type' = 'Microsoft.Dynamics.CRM.BooleanOptionSetMetadata'
                OptionSetType = 'Boolean'
                TrueOption    = @{ Value = 1; Label = (Label $yes) }
                FalseOption   = @{ Value = 0; Label = (Label $no) }
            }
        }
    }
    'DateTime' {
        $behavior = if ($DateFormat -eq 'DateOnly' -and -not $PSBoundParameters.ContainsKey('DateBehavior')) { 'DateOnly' } else { $DateBehavior }
        $body = $common + @{
            '@odata.type'    = 'Microsoft.Dynamics.CRM.DateTimeAttributeMetadata'
            Format           = $DateFormat
            DateTimeBehavior = @{ Value = $behavior }
        }
    }
    { $_ -in 'Choice', 'MultiChoice' } {
        $odataType = if ($Type -eq 'Choice') { 'Microsoft.Dynamics.CRM.PicklistAttributeMetadata' } else { 'Microsoft.Dynamics.CRM.MultiSelectPicklistAttributeMetadata' }
        $body = $common + @{ '@odata.type' = $odataType }
        if ($GlobalOptionSet) {
            $optionSetId = "<MetadataId of '$GlobalOptionSet'>"
            if (-not $DryRun) {
                $optionSetId = (Invoke-DataverseRequest -Environment $dvEnv -Path "GlobalOptionSetDefinitions(Name='$(ConvertTo-ODataString $GlobalOptionSet)')?`$select=MetadataId").Content.MetadataId
            }
            $body['GlobalOptionSet@odata.bind'] = "/GlobalOptionSetDefinitions($optionSetId)"
        }
        else {
            $body.OptionSet = @{
                '@odata.type' = 'Microsoft.Dynamics.CRM.OptionSetMetadata'
                IsGlobal      = $false
                OptionSetType = 'Picklist'
                Options       = Get-OptionList
            }
        }
    }
    'Lookup' {
        if (-not $TargetTable) { throw "-TargetTable is required for a Lookup column." }
        $TargetTable = $TargetTable.ToLowerInvariant()
        $targetPk = (Invoke-DataverseRequest -Environment $dvEnv -Path "EntityDefinitions(LogicalName='$TargetTable')?`$select=PrimaryIdAttribute").Content.PrimaryIdAttribute
        $shortName = $logicalName.Substring($prefix.Length + 1)
        $unprefixed = { param($name) $name -replace "^$([regex]::Escape($prefix))_", '' }
        $relationship = if ($RelationshipSchemaName) { $RelationshipSchemaName } else { "$($prefix)_$(& $unprefixed $TargetTable)_$(& $unprefixed $Table)_$shortName" }
        Assert-PublisherPrefix -Solution $solutionInfo -Name $relationship -What 'RelationshipSchemaName'
        $path = 'RelationshipDefinitions'
        $lookup = $common + @{ '@odata.type' = 'Microsoft.Dynamics.CRM.LookupAttributeMetadata' }
        $body = @{
            '@odata.type'               = 'Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata'
            SchemaName                  = $relationship
            ReferencedEntity            = $TargetTable
            ReferencedAttribute         = $targetPk
            ReferencingEntity           = $Table
            AssociatedMenuConfiguration = @{ Behavior = $AssociatedMenuBehavior; Group = 'Details'; Order = 10000 }
            CascadeConfiguration        = @{
                Assign = 'NoCascade'; Delete = $DeleteBehavior; Merge = 'Cascade'; Reparent = 'NoCascade'
                Share = 'NoCascade'; Unshare = 'NoCascade'; RollupView = 'NoCascade'
            }
            Lookup                      = $lookup
        }
    }
    'Customer' {
        $shortName = $logicalName.Substring($prefix.Length + 1)
        # CreateCustomerRelationships refuses menu and cascade options: minimal relationships only.
        $customerRelationships = foreach ($target in 'account', 'contact') {
            @{ SchemaName = "$($prefix)_$($target)_$($Table)_$shortName"; ReferencedEntity = $target; ReferencingEntity = $Table }
        }
        $path = 'CreateCustomerRelationships'
        $body = @{
            Lookup                 = $common + @{ '@odata.type' = 'Microsoft.Dynamics.CRM.ComplexLookupAttributeMetadata' }
            OneToManyRelationships = @($customerRelationships)
        }
    }
}

if ($Formula) {
    if ($Type -notin 'String', 'Integer', 'Decimal', 'Float', 'Boolean', 'DateTime') { throw "-Formula is not possible for a $Type column (String, Integer, Decimal, Float, Boolean, DateTime)." }
    if ($AutoNumberFormat -or $RequiredLevel -ne 'None') { throw "A formula column is read-only: no auto-number and no requirement level." }
    # SourceType 3 = Power Fx formula (verified on CRM-408: DateDiff between two dates).
    $body.SourceType = 3
    $body.FormulaDefinition = $Formula
}

# Checks in dry run too: a dry run must not announce a creation bound to fail.
$provisioned = Get-DataverseProvisionedLanguages -Environment $dvEnv
$missing = @($languages | Where-Object { $_ -notin $provisioned })
if ($missing) { throw "Language(s) not installed on the organization: $($missing -join ', ') (installed: $($provisioned -join ', ')). Nothing was created." }
$existing = Invoke-DataverseRequest -Environment $dvEnv -Path "EntityDefinitions(LogicalName='$Table')/Attributes?`$select=LogicalName&`$filter=LogicalName eq '$logicalName'"
if (@($existing.Content.value).Count) { throw "Column '$logicalName' already exists on '$Table'. Nothing was created." }

$plan = [ordered]@{
    environment = "$($dvEnv.name) ($($dvEnv.url))"
    solution    = $solutionName
    publisher   = "$($solutionInfo.publisher.uniqueName) (prefix $prefix, options $optionPrefix)"
    table       = $Table
    column      = $logicalName
    type        = $Type
    languages   = $languages
    request     = "POST /api/data/v9.2/$path"
    body        = $body
}

if ($DryRun) {
    $plan.dryRun = $true
    $plan | ConvertTo-Json -Depth 32
    return
}

$result = Invoke-DataverseRequest -Environment $dvEnv -Method POST -Path $path -Body $body -SolutionUniqueName $solutionName

# The table only enters the solution after a successful creation.
$components = @(Add-DataverseTableToSolution -Environment $dvEnv -Solution $solutionInfo -Table $Table)

if ($Type -eq 'Customer') {
    foreach ($relationshipId in @($result.Content.RelationshipIds)) {
        $components += New-AlchemistComponent -Type EntityRelationship -Id $relationshipId -Name "$logicalName (customer)" -Status (Add-DataverseSolutionComponent -Environment $dvEnv -Solution $solutionInfo -ComponentId $relationshipId -ComponentType EntityRelationship)
    }
    $attributeId = $result.Content.AttributeId
}
elseif ($Type -eq 'Lookup') {
    $components += New-AlchemistComponent -Type EntityRelationship -Id $result.EntityId -Name $relationship -Status (Add-DataverseSolutionComponent -Environment $dvEnv -Solution $solutionInfo -ComponentId $result.EntityId -ComponentType EntityRelationship)
    $attributeId = (Invoke-DataverseRequest -Environment $dvEnv -Path "EntityDefinitions(LogicalName='$Table')/Attributes(LogicalName='$logicalName')?`$select=MetadataId").Content.MetadataId
}
else { $attributeId = $result.EntityId }
$components += New-AlchemistComponent -Type Attribute -Id $attributeId -Name "$Table.$logicalName" -Status (Add-DataverseSolutionComponent -Environment $dvEnv -Solution $solutionInfo -ComponentId $attributeId -ComponentType Attribute)

Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action 'dataverse.column.create' -Details @{
    environment = $dvEnv.name; table = $Table; column = $logicalName; type = $Type; metadataId = $attributeId; solution = $solutionName; components = $components
}

# Dataverse ignores CanStoreFullImage on creation: only an update applies it.
if ($Type -eq 'Image') {
    # Read on the typed path, write (PUT) on the untyped path with @odata.type: form verified on CRM-402.
    $attributePath = "EntityDefinitions(LogicalName='$Table')/Attributes(LogicalName='$logicalName')"
    Update-DataverseDefinition -Environment $dvEnv -Path $attributePath -ReadPath "$attributePath/Microsoft.Dynamics.CRM.ImageAttributeMetadata" -ODataType 'Microsoft.Dynamics.CRM.ImageAttributeMetadata' -Changes @{ CanStoreFullImage = $true } -SolutionUniqueName $solutionName
}

if ($Publish) {
    $tables = @($Table) + $(if ($Type -eq 'Lookup') { @($TargetTable) } else { @() })
    Publish-DataverseXml -Environment $dvEnv -Tables $tables | Out-Null
}

[ordered]@{ created = $true; table = $Table; column = $logicalName; metadataId = $attributeId; solution = $solutionName; components = $components; published = [bool]$Publish } | ConvertTo-Json -Depth 5
