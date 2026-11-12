#Requires -Version 7.0
# Dataverse Alchemist shared module: config, Jira, Dataverse Web API, Azure DevOps, journal.

$script:DataverseApiVersion = 'v9.2'
$script:ConfigFileName = 'alchemist.config.json'

#region Config

function Get-AlchemistConfigPath {
    [CmdletBinding()]
    param([string]$ConfigPath)

    if ($ConfigPath) {
        if (Test-Path -LiteralPath $ConfigPath) { return (Resolve-Path -LiteralPath $ConfigPath).Path }
        throw "Config file not found: $ConfigPath"
    }
    if ($env:ALCHEMIST_CONFIG -and (Test-Path -LiteralPath $env:ALCHEMIST_CONFIG)) {
        return (Resolve-Path -LiteralPath $env:ALCHEMIST_CONFIG).Path
    }
    $dir = (Get-Location).Path
    while ($dir) {
        $candidate = Join-Path $dir ".alchemist/$script:ConfigFileName"
        if (Test-Path -LiteralPath $candidate) { return $candidate }
        $parent = Split-Path $dir -Parent
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    $userConfig = Join-Path $HOME ".dataverse-alchemist/$script:ConfigFileName"
    if (Test-Path -LiteralPath $userConfig) { return $userConfig }
    throw "No config found. Run /alchemist-init or create .alchemist/$script:ConfigFileName at the repository root (or set ALCHEMIST_CONFIG)."
}

function Merge-AlchemistHashtable {
    param([hashtable]$Base, [hashtable]$Override)
    foreach ($key in $Override.Keys) {
        if ($Base.ContainsKey($key) -and $Base[$key] -is [hashtable] -and $Override[$key] -is [hashtable]) {
            Merge-AlchemistHashtable -Base $Base[$key] -Override $Override[$key]
        }
        else {
            $Base[$key] = $Override[$key]
        }
    }
}

# Replaces "env:VARIABLE_NAME" values with the content of the environment variable.
function Resolve-AlchemistSecrets {
    param($Value, [System.Collections.Generic.List[string]]$Missing)
    if ($Value -is [hashtable]) {
        foreach ($key in @($Value.Keys)) { $Value[$key] = Resolve-AlchemistSecrets -Value $Value[$key] -Missing $Missing }
        return $Value
    }
    if ($Value -is [System.Collections.IList]) {
        for ($i = 0; $i -lt $Value.Count; $i++) { $Value[$i] = Resolve-AlchemistSecrets -Value $Value[$i] -Missing $Missing }
        return , $Value
    }
    if ($Value -is [string] -and $Value.StartsWith('env:')) {
        $name = $Value.Substring(4)
        $resolved = [Environment]::GetEnvironmentVariable($name)
        if ([string]::IsNullOrEmpty($resolved)) { $Missing.Add($name) | Out-Null; return $null }
        return $resolved
    }
    return $Value
}

function Get-AlchemistConfig {
    [CmdletBinding()]
    param([string]$ConfigPath)

    $path = Get-AlchemistConfigPath -ConfigPath $ConfigPath
    $config = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -AsHashtable

    # Local override, not committed (personal preferences, default environment, secrets, etc.)
    $localPath = $path -replace '\.json$', '.local.json'
    if (Test-Path -LiteralPath $localPath) {
        $local = Get-Content -Raw -LiteralPath $localPath | ConvertFrom-Json -AsHashtable
        Merge-AlchemistHashtable -Base $config -Override $local
    }

    $missing = [System.Collections.Generic.List[string]]::new()
    $config = Resolve-AlchemistSecrets -Value $config -Missing $missing

    $configDir = Split-Path $path -Parent
    $repoRoot = if ((Split-Path $configDir -Leaf) -eq '.alchemist') { Split-Path $configDir -Parent } else { (Get-Location).Path }

    $config['_meta'] = @{
        path           = $path
        localPath      = $localPath
        repoRoot       = $repoRoot
        missingSecrets = @($missing | Select-Object -Unique)
    }
    return $config
}

# Reads a value by dotted path: Get-AlchemistSetting $config 'jira.baseUrl'
function Get-AlchemistSetting {
    param([hashtable]$Config, [string]$Path, $Default = $null, [switch]$Required)
    $current = $Config
    foreach ($segment in $Path.Split('.')) {
        if ($current -is [hashtable] -and $current.ContainsKey($segment)) { $current = $current[$segment] }
        else { $current = $null; break }
    }
    if ($null -eq $current -or ($current -is [string] -and $current -eq '')) {
        if ($Required) { throw "Missing config setting: '$Path' (file $($Config._meta.path))" }
        return $Default
    }
    return $current
}

function Get-AlchemistRunFolder {
    param([hashtable]$Config, [Parameter(Mandatory)][string]$IssueKey)
    $runs = Get-AlchemistSetting $Config 'workflow.runsFolder' -Default '.alchemist/runs'
    $folder = Join-Path $Config._meta.repoRoot (Join-Path $runs $IssueKey.ToUpperInvariant())
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    return $folder
}

# JSONL journal of write actions (traceability / rollback).
function Write-AlchemistJournal {
    param([hashtable]$Config, [string]$IssueKey, [string]$Action, [hashtable]$Details)
    if (-not $IssueKey) { return }
    $folder = Get-AlchemistRunFolder -Config $Config -IssueKey $IssueKey
    $entry = [ordered]@{ timestamp = (Get-Date).ToString('o'); action = $Action }
    if ($Details) { foreach ($key in $Details.Keys) { $entry[$key] = $Details[$key] } }
    ($entry | ConvertTo-Json -Depth 10 -Compress) | Add-Content -LiteralPath (Join-Path $folder 'journal.jsonl') -Encoding utf8
}

function Get-AlchemistSnapshotPath {
    param([string]$RunFolder, [string]$Type, [string]$Name)
    return Join-Path $RunFolder (Join-Path 'backup' "$Type-$($Name -replace '[^\w.-]+', '_').json")
}
# Keeps the state of a component right before the ticket changes it. The first copy stays: it is the state before the ticket.
function Save-AlchemistSnapshot {
    param(
        [hashtable]$Config, [string]$IssueKey, [hashtable]$Environment, [Parameter(Mandatory)][string]$Type, [Parameter(Mandatory)][string]$Name,
        [string]$Path, [string[]]$Fields, [string]$ReadPath, [string]$Table, [string]$Xml, $Value
    )
    if (-not $IssueKey) { return }
    $folder = Get-AlchemistRunFolder -Config $Config -IssueKey $IssueKey
    $file = Get-AlchemistSnapshotPath -RunFolder $folder -Type $Type -Name $Name
    if (Test-Path -LiteralPath $file) { return }
    $snapshot = [ordered]@{ kind = $Type; name = $Name; table = $Table; path = $Path; savedAt = (Get-Date).ToString('o') }
    if ($Xml) { $snapshot.xml = $Xml }
    elseif ($PSBoundParameters.ContainsKey('Value')) { $snapshot.value = $Value }
    else {
        $select = "$($Path)?`$select=$($Fields -join ',')"
        $record = (Invoke-DataverseRequest -Environment $Environment -Path ($ReadPath ? $ReadPath : $select)).Content
        # A version never changed has no draft: the normal read takes over.
        if ($ReadPath -and $null -eq $record.($Fields[0])) { $record = (Invoke-DataverseRequest -Environment $Environment -Path $select).Content }
        $values = [ordered]@{}
        foreach ($field in $Fields) { $values[$field] = $record.$field }
        $snapshot.fields = $values
    }
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($file))
    $snapshot | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $file -Encoding utf8
}
# Definitions do not accept PATCH: read everything, change the property, send everything back. MergeLabels protects the other languages.
function Update-DataverseDefinition {
    param([hashtable]$Environment, [Parameter(Mandatory)][string]$Path, [string]$ReadPath, [string]$ODataType, [Parameter(Mandatory)][hashtable]$Changes, [string]$SolutionUniqueName)
    $definition = (Invoke-DataverseRequest -Environment $Environment -Path ($ReadPath ? $ReadPath : $Path)).Content
    foreach ($name in $Changes.Keys) { $definition | Add-Member -NotePropertyName $name -NotePropertyValue $Changes[$name] -Force }
    if ($ODataType) { $definition | Add-Member -NotePropertyName '@odata.type' -NotePropertyValue $ODataType -Force }
    Invoke-DataverseRequest -Environment $Environment -Method PUT -Path $Path -Body $definition -SolutionUniqueName $SolutionUniqueName -Headers @{ 'MSCRM.MergeLabels' = 'true' } | Out-Null
}
function Update-DataverseColumnDefault {
    param([hashtable]$Environment, [string]$Table, [string]$Column, $Value, [string]$SolutionUniqueName)
    $path = "EntityDefinitions(LogicalName='$Table')/Attributes(LogicalName='$Column')"
    Update-DataverseDefinition -Environment $Environment -Path $path -ReadPath "$path/Microsoft.Dynamics.CRM.PicklistAttributeMetadata" -ODataType 'Microsoft.Dynamics.CRM.PicklistAttributeMetadata' -Changes @{ DefaultFormValue = $Value } -SolutionUniqueName $SolutionUniqueName
}
function ConvertTo-AlchemistSlug {
    param([string]$Text, [int]$MaxLength = 40)
    $normalized = $Text.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', ''
    $slug = ($normalized.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ($slug.Length -gt $MaxLength) { $slug = $slug.Substring(0, $MaxLength).Trim('-') }
    return $slug
}

# Identifier of the current user for the personal knowledge base.
function Get-AlchemistUserId {
    param([hashtable]$Config)
    $candidates = @()
    if ($Config) { $candidates += (Get-AlchemistSetting $Config 'report.crmUserEmail'), (Get-AlchemistSetting $Config 'jira.email') }
    $candidates += (& git config user.email 2>$null), $env:USERNAME, $env:USER
    return ($candidates | Where-Object { $_ } | Select-Object -First 1)
}

function Get-AlchemistKnowledgePath {
    param([ValidateSet('User', 'Project')][string]$Scope = 'User', [string]$UserId, [string]$ConfigPath)
    $config = $null
    try { $config = Get-AlchemistConfig -ConfigPath $ConfigPath } catch { if ($Scope -eq 'Project') { throw } }
    if ($Scope -eq 'Project') { return (Join-Path $config._meta.repoRoot '.alchemist/knowledge/project.json') }
    if (-not $UserId) { $UserId = Get-AlchemistUserId -Config $config }
    if (-not $UserId) { throw "User not identified: set report.crmUserEmail or git config user.email." }
    return (Join-Path $HOME ".dataverse-alchemist/knowledge/$(ConvertTo-AlchemistSlug $UserId -MaxLength 60).json")
}

function Read-AlchemistKnowledge {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $raw = Get-Content -Raw -LiteralPath $Path
    if (-not $raw.Trim()) { return @() }
    return @($raw | ConvertFrom-Json -AsHashtable)
}

function Save-AlchemistKnowledge {
    param([Parameter(Mandatory)][string]$Path, [AllowEmptyCollection()][object[]]$Entries)
    New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force | Out-Null
    $json = ConvertTo-Json -InputObject @($Entries) -Depth 8
    [IO.File]::WriteAllText($Path, $json, [Text.UTF8Encoding]::new($false))
}

#endregion

#region Dataverse

function Get-DataverseEnvironment {
    param([hashtable]$Config, [string]$Name)
    if (-not $Name) { $Name = Get-AlchemistSetting $Config 'dataverse.defaultEnvironment' -Required }
    $environments = Get-AlchemistSetting $Config 'dataverse.environments' -Required
    if (-not $environments.ContainsKey($Name)) {
        throw "Dataverse environment '$Name' is not in the config (available: $($environments.Keys -join ', '))."
    }
    $environment = $environments[$Name].Clone()
    $environment['name'] = $Name
    if (-not $environment.url) { throw "dataverse.environments.$Name.url is missing." }
    return $environment
}

# Azure CLI installed while an editor is open: its terminals keep the old PATH. So the Windows one is read again.
function Get-AzureCliPath {
    $found = Get-Command az -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.Source }
    $folders = @([Environment]::GetEnvironmentVariable('Path', 'Machine'), [Environment]::GetEnvironmentVariable('Path', 'User')) -join ';' -split ';'
    $folders += @("$env:ProgramFiles\Microsoft SDKs\Azure\CLI2\wbin", "${env:ProgramFiles(x86)}\Microsoft SDKs\Azure\CLI2\wbin")
    foreach ($folder in ($folders | Where-Object { $_ })) {
        $candidate = Join-Path $folder 'az.cmd'
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return $null
}

# pac is often only installed by the Power Platform VS Code extension (outside PATH) or as a dotnet tool.
function Get-PacCliPath {
    $found = Get-Command pac -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.Source }
    $candidates = @(
        "$env:USERPROFILE\.dotnet\tools\pac.exe",
        "$env:LOCALAPPDATA\Microsoft\PowerAppsCLI\pac.cmd",
        "$env:APPDATA\Code\User\globalStorage\microsoft-isvexptools.powerplatform-vscode\pac\tools\pac.exe",
        "$env:APPDATA\Code - Insiders\User\globalStorage\microsoft-isvexptools.powerplatform-vscode\pac\tools\pac.exe"
    )
    foreach ($candidate in $candidates) { if (Test-Path -LiteralPath $candidate) { return $candidate } }
    return $null
}

function Get-DataverseAccessToken {
    param([hashtable]$Environment)
    $resource = $Environment.url.TrimEnd('/')
    $auth = if ($Environment.auth) { $Environment.auth } else { @{ type = 'azcli' } }

    switch ($auth.type) {
        'clientSecret' {
            foreach ($key in 'tenantId', 'clientId', 'clientSecret') {
                if (-not $auth[$key]) { throw "dataverse.environments.$($Environment.name).auth.$key is empty (environment variable not set?)." }
            }
            $body = @{
                grant_type    = 'client_credentials'
                client_id     = $auth.clientId
                client_secret = $auth.clientSecret
                scope         = "$resource/.default"
            }
            $response = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$($auth.tenantId)/oauth2/v2.0/token" -Body $body -ContentType 'application/x-www-form-urlencoded'
            return $response.access_token
        }
        'azcli' {
            $azure = Get-AzureCliPath
            if (-not $azure) { throw "Azure CLI not found. Install it: winget install -e --id Microsoft.AzureCLI" }
            $output = & $azure account get-access-token --resource $resource --output json 2>$null
            if ($LASTEXITCODE -ne 0) { throw "'az account get-access-token' failed for $resource. Run 'az login --allow-no-subscriptions --use-device-code' (with an account that has access to the environment)." }
            return ($output | ConvertFrom-Json).accessToken
        }
        'accessToken' {
            if (-not $auth.token) { throw "dataverse.environments.$($Environment.name).auth.token is empty." }
            return $auth.token
        }
        default { throw "Unknown Dataverse authentication type: '$($auth.type)' (clientSecret | azcli | accessToken)." }
    }
}

function Get-ResponseHeader {
    param($Response, [string]$Name)
    foreach ($key in $Response.Headers.Keys) {
        if ($key -ieq $Name) { return @($Response.Headers[$key])[0] }
    }
    return $null
}

function Invoke-DataverseRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Environment,
        [ValidateSet('GET', 'POST', 'PATCH', 'PUT', 'DELETE')][string]$Method = 'GET',
        [Parameter(Mandatory)][string]$Path,
        $Body,
        [string]$SolutionUniqueName,
        [hashtable]$Headers,
        # POST that changes nothing (ExportSolution, RetrieveXxx…): allowed even if allowWrite=false.
        [switch]$ReadOnlyAction
    )

    $isWrite = $Method -ne 'GET' -and -not $ReadOnlyAction
    if ($isWrite -and -not $Environment.allowWrite) {
        throw "Write refused: environment '$($Environment.name)' does not have 'allowWrite: true' in the config."
    }

    $token = Get-DataverseAccessToken -Environment $Environment
    $uri = if ($Path -match '^https?://') { $Path } else { "$($Environment.url.TrimEnd('/'))/api/data/$script:DataverseApiVersion/$($Path.TrimStart('/'))" }

    $requestHeaders = @{
        Authorization      = "Bearer $token"
        'OData-MaxVersion' = '4.0'
        'OData-Version'    = '4.0'
        Accept             = 'application/json'
        Prefer             = 'odata.include-annotations="*"'
    }
    if ($SolutionUniqueName) { $requestHeaders['MSCRM.SolutionUniqueName'] = $SolutionUniqueName }
    if ($Headers) { foreach ($key in $Headers.Keys) { $requestHeaders[$key] = $Headers[$key] } }

    $params = @{ Uri = $uri; Method = $Method; Headers = $requestHeaders; SkipHttpErrorCheck = $true }
    if ($null -ne $Body) {
        $json = if ($Body -is [string]) { $Body } else { ConvertTo-Json -InputObject $Body -Depth 64 }
        $params.Body = [Text.Encoding]::UTF8.GetBytes($json)
        $params.ContentType = 'application/json; charset=utf-8'
    }

    $response = Invoke-WebRequest @params
    $text = if ($response.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($response.Content) } else { [string]$response.Content }

    if ($response.StatusCode -ge 400) {
        $message = $text
        try { $message = ($text | ConvertFrom-Json).error.message } catch { }
        throw "Dataverse $Method $uri -> HTTP $($response.StatusCode): $message"
    }

    $entityId = $null
    $entityHeader = Get-ResponseHeader -Response $response -Name 'OData-EntityId'
    if ($entityHeader -and $entityHeader -match '\(([0-9a-fA-F-]{36})\)') { $entityId = $Matches[1] }

    $content = $null
    if ($text -and $text.Trim()) { $content = $text | ConvertFrom-Json -Depth 100 }

    return [pscustomobject]@{ StatusCode = [int]$response.StatusCode; EntityId = $entityId; Content = $content }
}

function ConvertTo-ODataString {
    param([string]$Value)
    return $Value.Replace("'", "''")
}

# Label in the base language, plus optional translations (LCID -> text).
function New-DataverseLabel {
    param([string]$Text, [int]$LanguageCode, [System.Collections.IDictionary]$Translations)
    if ([string]::IsNullOrEmpty($Text)) { return $null }
    $labels = @(@{ '@odata.type' = 'Microsoft.Dynamics.CRM.LocalizedLabel'; Label = $Text; LanguageCode = $LanguageCode })
    if ($Translations) {
        foreach ($lcid in $Translations.Keys) {
            if ([int]$lcid -eq $LanguageCode) { continue }
            $labels += @{ '@odata.type' = 'Microsoft.Dynamics.CRM.LocalizedLabel'; Label = $Translations[$lcid]; LanguageCode = [int]$lcid }
        }
    }
    return @{ '@odata.type' = 'Microsoft.Dynamics.CRM.Label'; LocalizedLabels = $labels }
}

# Translations as "1033=Text,1031=Text" -> dictionary LCID -> text.
function ConvertTo-LabelTranslations {
    param([string[]]$Values)
    $map = [System.Collections.Generic.Dictionary[int, string]]::new()
    foreach ($item in @($Values | ForEach-Object { $_ -split ',' } | Where-Object { $_.Trim() })) {
        if ($item -notmatch '^\s*(\d{4,5})\s*=\s*(.+?)\s*$') { throw "Invalid translation '$item': expected format LCID=Label (e.g. 1033=Customer)." }
        $map[[int]$Matches[1]] = $Matches[2]
    }
    return , $map
}

# Organization base language (LCID).
function Get-DataverseBaseLanguage {
    param([hashtable]$Environment)
    return [int](@((Invoke-DataverseRequest -Environment $Environment -Path "organizations?`$select=languagecode").Content.value)[0].languagecode)
}

# Languages installed on the organization (LCID).
function Get-DataverseProvisionedLanguages {
    param([hashtable]$Environment)
    return @((Invoke-DataverseRequest -Environment $Environment -Path 'RetrieveProvisionedLanguages()').Content.RetrieveProvisionedLanguages)
}

# Most common solution component types.
$script:SolutionComponentTypes = @{
    Entity                    = 1
    Attribute                 = 2
    OptionSet                 = 9
    SavedQuery                = 26
    EntityRelationship        = 10
    SystemForm                = 60
    SiteMap                   = 62
    WebResource               = 61
    AppModule                 = 80
    PluginAssembly            = 91
    SdkMessageProcessingStep  = 92
    Role                      = 20
    EntityKey                 = 14
    Workflow                  = 29
}

function Test-DataverseSolutionComponent {
    param([hashtable]$Environment, [Parameter(Mandatory)][hashtable]$Solution, [Parameter(Mandatory)][string]$ComponentId)
    $id = $ComponentId.Trim('{}')
    $found = Invoke-DataverseRequest -Environment $Environment -Path "solutioncomponents?`$select=solutioncomponentid&`$filter=_solutionid_value eq $($Solution.solutionId) and objectid eq $id&`$top=1"
    return [bool]@($found.Content.value).Count
}

# Adds a component to the ticket solution if it is not already there (never its subcomponents:
# adding a table does not embed all its columns and forms).
function Add-DataverseSolutionComponent {
    param(
        [hashtable]$Environment,
        [Parameter(Mandatory)][hashtable]$Solution,
        [Parameter(Mandatory)][string]$ComponentId,
        [Parameter(Mandatory)][ValidateSet('Entity', 'Attribute', 'OptionSet', 'SavedQuery', 'EntityRelationship', 'SystemForm', 'SiteMap', 'WebResource', 'AppModule', 'PluginAssembly', 'SdkMessageProcessingStep', 'Role', 'EntityKey', 'Workflow')][string]$ComponentType
    )
    $id = $ComponentId.Trim('{}')
    if (Test-DataverseSolutionComponent -Environment $Environment -Solution $Solution -ComponentId $id) { return 'present' }
    $body = @{
        ComponentId               = $id
        ComponentType             = $script:SolutionComponentTypes[$ComponentType]
        SolutionUniqueName        = $Solution.uniqueName
        AddRequiredComponents     = $false
        DoNotIncludeSubcomponents = $true
    }
    try { Invoke-DataverseRequest -Environment $Environment -Method POST -Path 'AddSolutionComponent' -Body $body | Out-Null }
    catch { throw "Component $ComponentType $id created/changed but NOT added to solution '$($Solution.uniqueName)': $($_.Exception.Message)" }
    return 'added'
}

# Makes sure the table is in the solution (root component only) before adding a column or a form to it.
function Add-DataverseTableToSolution {
    param([hashtable]$Environment, [Parameter(Mandatory)][hashtable]$Solution, [Parameter(Mandatory)][string]$Table)
    $metadataId = (Invoke-DataverseRequest -Environment $Environment -Path "EntityDefinitions(LogicalName='$($Table.ToLowerInvariant())')?`$select=MetadataId").Content.MetadataId
    $status = Add-DataverseSolutionComponent -Environment $Environment -Solution $Solution -ComponentId $metadataId -ComponentType Entity
    return [ordered]@{ type = 'Entity'; id = $metadataId; name = $Table; status = $status }
}

function Publish-DataverseXml {
    param([hashtable]$Environment, [string[]]$Tables, [string[]]$WebResourceIds, [string[]]$OptionSets)
    $xml = '<importexportxml>'
    if ($Tables) { $xml += '<entities>' + (($Tables | ForEach-Object { "<entity>$_</entity>" }) -join '') + '</entities>' }
    if ($WebResourceIds) { $xml += '<webresources>' + (($WebResourceIds | ForEach-Object { "<webresource>{$($_.Trim('{}'))}</webresource>" }) -join '') + '</webresources>' }
    if ($OptionSets) { $xml += '<optionsets>' + (($OptionSets | ForEach-Object { "<optionset>$_</optionset>" }) -join '') + '</optionsets>' }
    $xml += '</importexportxml>'
    Invoke-DataverseRequest -Environment $Environment -Method POST -Path 'PublishXml' -Body @{ ParameterXml = $xml } | Out-Null
    return $xml
}

function Get-DataverseSolutionInfo {
    param([hashtable]$Environment, [Parameter(Mandatory)][string]$UniqueName)
    $query = "solutions?`$select=solutionid,uniquename,friendlyname,version,ismanaged" +
        "&`$expand=publisherid(`$select=uniquename,friendlyname,customizationprefix,customizationoptionvalueprefix)" +
        "&`$filter=uniquename eq '$(ConvertTo-ODataString $UniqueName)'"
    $found = @((Invoke-DataverseRequest -Environment $Environment -Path $query).Content.value)
    if (-not $found.Count) { throw "Solution '$UniqueName' not found on environment '$($Environment.name)'." }
    $s = $found[0]
    return @{
        uniqueName   = $s.uniquename
        solutionId   = $s.solutionid
        friendlyName = $s.friendlyname
        version      = $s.version
        isManaged    = [bool]$s.ismanaged
        environment  = $Environment.name
        publisher    = @{
            uniqueName        = $s.publisherid.uniquename
            friendlyName      = $s.publisherid.friendlyname
            prefix            = $s.publisherid.customizationprefix
            optionValuePrefix = [int]$s.publisherid.customizationoptionvalueprefix
        }
    }
}

function Get-AlchemistRunContext {
    param([hashtable]$Config, [string]$IssueKey)
    if (-not $IssueKey) { return $null }
    $path = Join-Path (Get-AlchemistRunFolder -Config $Config -IssueKey $IssueKey) 'context.json'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -AsHashtable
}

# Target solution: explicit -Solution, otherwise the solution chosen for the ticket (Set-AlchemistRunSolution.ps1).
# The publisher (prefix, choice value prefix) is ALWAYS that of this solution.
function Resolve-AlchemistSolution {
    param([hashtable]$Config, [hashtable]$Environment, [string]$Solution, [string]$IssueKey, [switch]$Optional)
    $context = Get-AlchemistRunContext -Config $Config -IssueKey $IssueKey
    $selected = if ($context) { $context.solution } else { $null }

    if (-not $Solution -and $selected) { $Solution = $selected.uniqueName }
    if (-not $Solution) {
        if ($Optional) { return $null }
        throw "No target solution. Choose the ticket solution: Set-AlchemistRunSolution.ps1 -IssueKey <KEY> -Solution <unique name> (or pass -Solution)."
    }
    if ($selected -and $selected.uniqueName -eq $Solution -and $selected.environment -eq $Environment.name) { return $selected }

    $info = Get-DataverseSolutionInfo -Environment $Environment -UniqueName $Solution
    if ($info.isManaged) { throw "Solution '$Solution' is managed: components cannot be added to it." }
    return $info
}

function Assert-PublisherPrefix {
    param([hashtable]$Solution, [string]$Name, [string]$What = 'Name')
    $prefix = $Solution.publisher.prefix
    if (-not $Name.StartsWith("$($prefix)_", [StringComparison]::OrdinalIgnoreCase)) {
        throw "$What '$Name' does not start with '$($prefix)_', prefix of publisher '$($Solution.publisher.uniqueName)' of solution '$($Solution.uniqueName)'."
    }
}

$script:LanguageCodes = @{
    1025 = 'ar'; 1028 = 'zh-TW'; 1029 = 'cs'; 1030 = 'da'; 1031 = 'de'; 1033 = 'en'; 1035 = 'fi'; 1036 = 'fr'; 1040 = 'it'
    1041 = 'ja'; 1042 = 'ko'; 1043 = 'nl'; 1044 = 'nb'; 1045 = 'pl'; 1046 = 'pt-BR'; 1049 = 'ru'; 1053 = 'sv'; 1055 = 'tr'
    2052 = 'zh-CN'; 2070 = 'pt'; 3082 = 'es'
}

# CRM interface language of the user: user found by email (report.crmUserEmail, otherwise jira.email),
# otherwise the signed-in user (WhoAmI); organization base language if the user has not chosen one.
function Get-DataverseUserLanguage {
    param([hashtable]$Config, [hashtable]$Environment, [string]$UserEmail)
    if (-not $UserEmail) { $UserEmail = (Get-AlchemistSetting $Config 'report.crmUserEmail') ?? (Get-AlchemistSetting $Config 'jira.email') }
    $userId = $null; $source = $null
    if ($UserEmail) {
        $e = ConvertTo-ODataString $UserEmail
        $user = @((Invoke-DataverseRequest -Environment $Environment -Path "systemusers?`$select=systemuserid,fullname&`$filter=internalemailaddress eq '$e' or domainname eq '$e'&`$top=1").Content.value) | Select-Object -First 1
        if ($user) { $userId = $user.systemuserid; $source = "CRM user $($user.fullname) ($UserEmail)" }
    }
    if (-not $userId) {
        $userId = (Invoke-DataverseRequest -Environment $Environment -Path 'WhoAmI').Content.UserId
        $source = 'signed-in user (WhoAmI)'
    }
    $lcid = [int]((Invoke-DataverseRequest -Environment $Environment -Path "usersettingscollection($userId)?`$select=uilanguageid").Content.uilanguageid)
    if (-not $lcid) {
        $lcid = [int](@((Invoke-DataverseRequest -Environment $Environment -Path "organizations?`$select=languagecode").Content.value)[0].languagecode)
        $source += ', organization base language'
    }
    return @{ lcid = $lcid; code = $script:LanguageCodes[$lcid] ?? 'en'; userId = $userId; source = $source }
}

# Full ribbon of a table (XML), as published.
function Get-DataverseEntityRibbon {
    param([hashtable]$Environment, [Parameter(Mandatory)][string]$Table)
    Add-Type -AssemblyName System.IO.Compression
    $response = Invoke-DataverseRequest -Environment $Environment -Path "RetrieveEntityRibbon(EntityName='$($Table.ToLowerInvariant())',RibbonLocationFilter=Microsoft.Dynamics.CRM.RibbonLocationFilters'All')"
    $stream = [IO.MemoryStream]::new([Convert]::FromBase64String($response.Content.CompressedEntityXml))
    $zip = [IO.Compression.ZipArchive]::new($stream)
    try {
        $reader = [IO.StreamReader]::new($zip.Entries[0].Open(), [Text.Encoding]::UTF8)
        try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    }
    finally { $zip.Dispose() }
}

function Get-DataverseSolutionZip {
    param([hashtable]$Environment, [Parameter(Mandatory)][hashtable]$Solution)
    $export = Invoke-DataverseRequest -Environment $Environment -Method POST -Path 'ExportSolution' -ReadOnlyAction -Body @{ SolutionName = $Solution.uniqueName; Managed = $false }
    return , [Convert]::FromBase64String($export.Content.ExportSolutionFile)
}

function Read-DataverseZipEntry {
    param([Parameter(Mandatory)][IO.Compression.ZipArchive]$Zip, [Parameter(Mandatory)][string]$Name)
    $reader = [IO.StreamReader]::new($Zip.GetEntry($Name).Open(), [Text.Encoding]::UTF8)
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}

# customizations.xml of the solution (read-only).
function Get-DataverseSolutionCustomizations {
    param([hashtable]$Environment, [Parameter(Mandatory)][hashtable]$Solution)
    Add-Type -AssemblyName System.IO.Compression
    # The import disables the solution's plugin steps (seen on CRM-331 and CRM-412, PublishWorkflows = false).
    # So the state of steps and processes is captured before the import, and restored as is afterwards.
    $states = Get-DataverseSolutionProcessStates -Environment $Environment -Solution $Solution
    $bytes = Get-DataverseSolutionZip -Environment $Environment -Solution $Solution
    $zip = [IO.Compression.ZipArchive]::new([IO.MemoryStream]::new($bytes))
    try {
        $document = [xml]::new()
        $document.PreserveWhitespace = $true
        $document.LoadXml((Read-DataverseZipEntry -Zip $zip -Name 'customizations.xml'))
        return , $document
    }
    finally { $zip.Dispose() }
}

# Exports the solution, applies $Patch to customizations.xml ($Patch receives the XmlDocument), then re-imports.
# The import requires a licensed user, not in Administrative access mode.
function Update-DataverseSolutionCustomizations {
    param([hashtable]$Environment, [Parameter(Mandatory)][hashtable]$Solution, [Parameter(Mandatory)][scriptblock]$Patch)
    Add-Type -AssemblyName System.IO.Compression
    # The import disables the solution's plugin steps (seen on CRM-331 and CRM-412, PublishWorkflows = false).
    # So the state of steps and processes is captured before the import, and restored as is afterwards.
    $states = Get-DataverseSolutionProcessStates -Environment $Environment -Solution $Solution
    $bytes = Get-DataverseSolutionZip -Environment $Environment -Solution $Solution
    $stream = [IO.MemoryStream]::new()
    $stream.Write($bytes, 0, $bytes.Length)
    $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Update, $true)
    try {
        $document = [xml]::new()
        $document.PreserveWhitespace = $true
        $document.LoadXml((Read-DataverseZipEntry -Zip $zip -Name 'customizations.xml'))
        & $Patch $document
        $zip.GetEntry('customizations.xml').Delete()
        $writer = [IO.StreamWriter]::new($zip.CreateEntry('customizations.xml').Open(), [Text.UTF8Encoding]::new($true))
        try { $writer.Write($document.OuterXml) } finally { $writer.Dispose() }
    }
    finally { $zip.Dispose() }
    Invoke-DataverseRequest -Environment $Environment -Method POST -Path 'ImportSolution' -Body @{
        OverwriteUnmanagedCustomizations = $true
        PublishWorkflows                 = $false
        CustomizationFile                = [Convert]::ToBase64String($stream.ToArray())
        ImportJobId                      = [guid]::NewGuid().ToString()
    } | Out-Null
    return @(Restore-DataverseSolutionProcessStates -Environment $Environment -States $states)
}

# State (statecode/statuscode) of the plugin steps and processes (business rules, workflows) of a solution.
function Get-DataverseSolutionProcessStates {
    param([hashtable]$Environment, [Parameter(Mandatory)][hashtable]$Solution)
    $sets = @{ 92 = 'sdkmessageprocessingsteps'; 29 = 'workflows' }
    $states = foreach ($type in $sets.Keys) {
        $ids = @((Invoke-DataverseRequest -Environment $Environment -Path "solutioncomponents?`$select=objectid&`$filter=_solutionid_value eq $($Solution.solutionId) and componenttype eq $type").Content.value | ForEach-Object objectid)
        foreach ($id in $ids) {
            try {
                $row = (Invoke-DataverseRequest -Environment $Environment -Path "$($sets[$type])($id)?`$select=statecode,statuscode,name").Content
                [ordered]@{ set = $sets[$type]; id = $id; name = $row.name; statecode = [int]$row.statecode; statuscode = [int]$row.statuscode }
            }
            catch { }
        }
    }
    return @($states)
}

# Restores the states captured before an import; returns what was restored.
function Restore-DataverseSolutionProcessStates {
    param([hashtable]$Environment, [object[]]$States)
    foreach ($s in @($States | Where-Object { $_ })) {
        $now = (Invoke-DataverseRequest -Environment $Environment -Path "$($s.set)($($s.id))?`$select=statecode,statuscode").Content
        if ([int]$now.statecode -eq $s.statecode -and [int]$now.statuscode -eq $s.statuscode) { continue }
        Invoke-DataverseRequest -Environment $Environment -Method PATCH -Path "$($s.set)($($s.id))" -Body @{ statecode = $s.statecode; statuscode = $s.statuscode } | Out-Null
        [ordered]@{ name = $s.name; set = $s.set; from = [int]$now.statecode; to = $s.statecode }
    }
}

# Control classid per column type, taken from real forms (or documented for Double, multi-select, language).
$script:FormControlClassIds = @{
    'StringType'              = '{4273EDBD-AC1D-40D3-9FB2-095C621B552D}'
    'StringType/Email'        = '{ADA2203E-B4CD-49BE-9DDF-234642B43B52}'
    'StringType/Url'          = '{71716B6C-711E-476C-8AB8-5D11542BFB47}'
    'StringType/TickerSymbol' = '{1E1FC551-F7A8-43AF-AC34-A8DC35C7B6D4}'
    'StringType/TextArea'     = '{E0DECE4B-6FC8-4A8F-A065-082708572369}'
    'MemoType'                = '{E0DECE4B-6FC8-4A8F-A065-082708572369}'
    'IntegerType'             = '{C6D124CA-7EDA-4A60-AEA9-7FB8D318B68F}'
    'IntegerType/Duration'    = '{AA987274-CE4E-4271-A803-66164311A958}'
    'IntegerType/TimeZone'    = '{7C624A0B-F59E-493D-9583-638D34759266}'
    'IntegerType/Language'    = '{671A9387-CA5A-4D1E-8AB7-06E39DDCF6B5}'
    'BigIntType'              = '{C6D124CA-7EDA-4A60-AEA9-7FB8D318B68F}'
    'DecimalType'             = '{C3EFE0C3-0EC6-42BE-8349-CBD9079DFD8E}'
    'DoubleType'              = '{0D2C745A-E5A8-4C8F-BA63-C6D3BB604660}'
    'MoneyType'               = '{533B9E00-756B-4312-95A0-DC888637AC78}'
    'BooleanType'             = '{67FAC785-CD58-4F9F-ABB3-4B7DDC6ED5ED}'
    'DateTimeType'            = '{5B773807-9FB2-42DB-97C3-7A91EFF8ADFF}'
    'PicklistType'            = '{3EF39988-22BB-4F0B-BBBE-64B5A3748AEE}'
    'StateType'               = '{3EF39988-22BB-4F0B-BBBE-64B5A3748AEE}'
    'StatusType'              = '{5D68B988-0661-4DB2-BC3E-17598AD3BE6C}'
    'MultiSelectPicklistType' = '{4AA28AB7-9C13-4F57-A73D-AD894D048B5F}'
    'LookupType'              = '{270BD3DB-D9AF-4782-9025-509E298DEC0A}'
    'CustomerType'            = '{270BD3DB-D9AF-4782-9025-509E298DEC0A}'
    'OwnerType'               = '{270BD3DB-D9AF-4782-9025-509E298DEC0A}'
}

# Columns of a table usable on a form: type, format, labels per language, classid.
function Get-DataverseFormFieldInfo {
    param([hashtable]$Environment, [Parameter(Mandatory)][string]$Table)
    $t = $Table.ToLowerInvariant()
    $base = "EntityDefinitions(LogicalName='$t')/Attributes"
    $formats = @{}
    foreach ($a in (Invoke-DataverseRequest -Environment $Environment -Path "$base/Microsoft.Dynamics.CRM.StringAttributeMetadata?`$select=LogicalName,FormatName").Content.value) { $formats[$a.LogicalName] = $a.FormatName.Value }
    foreach ($a in (Invoke-DataverseRequest -Environment $Environment -Path "$base/Microsoft.Dynamics.CRM.IntegerAttributeMetadata?`$select=LogicalName,Format").Content.value) { $formats[$a.LogicalName] = $a.Format }
    $info = @{}
    foreach ($a in (Invoke-DataverseRequest -Environment $Environment -Path "$($base)?`$select=LogicalName,AttributeTypeName,DisplayName,RequiredLevel,AttributeOf,IsValidForForm").Content.value) {
        if ($a.AttributeOf) { continue }
        $type = $a.AttributeTypeName.Value
        $format = $formats[$a.LogicalName]
        $classId = $script:FormControlClassIds["$type/$format"] ?? $script:FormControlClassIds[$type]
        $labels = @{}
        foreach ($l in @($a.DisplayName.LocalizedLabels)) { if ($l) { $labels[[string]$l.LanguageCode] = $l.Label } }
        $info[$a.LogicalName] = @{ type = $type; format = $format; classId = $classId; labels = $labels; required = $a.RequiredLevel.Value; validForForm = [bool]$a.IsValidForForm }
    }
    return $info
}

function New-DataverseFormLabels {
    param([Parameter(Mandatory)][xml]$Document, [Parameter(Mandatory)][hashtable]$Labels)
    $node = $Document.CreateElement('labels')
    foreach ($lcid in $Labels.Keys) {
        $label = $Document.CreateElement('label')
        $label.SetAttribute('description', $Labels[$lcid])
        $label.SetAttribute('languagecode', [string]$lcid)
        [void]$node.AppendChild($label)
    }
    return $node
}

# Full cell of a field. Refuses columns without a known control or not valid on a form.
function New-DataverseFormCell {
    param([Parameter(Mandatory)][xml]$Document, [Parameter(Mandatory)][string]$Field, [Parameter(Mandatory)][hashtable]$FieldInfo)
    $name = $Field.ToLowerInvariant()
    $meta = $FieldInfo[$name]
    if (-not $meta) { throw "Column '$name' not found on the table." }
    if (-not $meta.validForForm) { throw "Column '$name' cannot be used on a form." }
    if (-not $meta.classId) { throw "No known control for '$name' (type $($meta.type)): copy the control from the designer." }
    $cell = $Document.CreateElement('cell')
    $cell.SetAttribute('id', "{$([guid]::NewGuid())}")
    $cell.SetAttribute('showlabel', 'true')
    $cell.SetAttribute('locklevel', '0')
    [void]$cell.AppendChild((New-DataverseFormLabels -Document $Document -Labels $meta.labels))
    $control = $Document.CreateElement('control')
    $control.SetAttribute('id', $name)
    $control.SetAttribute('classid', $meta.classId)
    $control.SetAttribute('datafieldname', $name)
    $control.SetAttribute('disabled', 'false')
    [void]$cell.AppendChild($control)
    return $cell
}

# Rows of a section: as many cells per row as columns in the section.
function Add-DataverseFormRows {
    param([Parameter(Mandatory)][xml]$Document, [Parameter(Mandatory)][System.Xml.XmlElement]$Rows, [string[]]$Fields, [hashtable]$FieldInfo, [int]$Columns = 1)
    for ($i = 0; $i -lt $Fields.Count; $i += $Columns) {
        $row = $Document.CreateElement('row')
        foreach ($field in @($Fields[$i..([math]::Min($i + $Columns, $Fields.Count) - 1)])) {
            [void]$row.AppendChild((New-DataverseFormCell -Document $Document -Field $field -FieldInfo $FieldInfo))
        }
        [void]$Rows.AppendChild($row)
    }
}

function New-DataverseFormSection {
    param([Parameter(Mandatory)][xml]$Document, [Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][hashtable]$Labels, [int]$Columns = 1, [string[]]$Fields, [hashtable]$FieldInfo)
    $section = $Document.CreateElement('section')
    $section.SetAttribute('name', $Name)
    $section.SetAttribute('id', "{$([guid]::NewGuid())}")
    $section.SetAttribute('showlabel', 'true')
    $section.SetAttribute('showbar', 'false')
    $section.SetAttribute('IsUserDefined', '1')
    $section.SetAttribute('columns', [string]$Columns)
    [void]$section.AppendChild((New-DataverseFormLabels -Document $Document -Labels $Labels))
    $rows = $Document.CreateElement('rows')
    [void]$section.AppendChild($rows)
    if ($Fields) { Add-DataverseFormRows -Document $Document -Rows $rows -Fields $Fields -FieldInfo $FieldInfo -Columns $Columns }
    return $section
}

function New-DataverseFormTab {
    param([Parameter(Mandatory)][xml]$Document, [Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][hashtable]$Labels)
    $tab = $Document.CreateElement('tab')
    $tab.SetAttribute('name', $Name)
    $tab.SetAttribute('id', "{$([guid]::NewGuid())}")
    $tab.SetAttribute('IsUserDefined', '1')
    $tab.SetAttribute('verticallayout', 'true')
    $tab.SetAttribute('expanded', 'true')
    $tab.SetAttribute('showlabel', 'true')
    [void]$tab.AppendChild((New-DataverseFormLabels -Document $Document -Labels $Labels))
    $columns = $Document.CreateElement('columns')
    $column = $Document.CreateElement('column')
    $column.SetAttribute('width', '100%')
    [void]$column.AppendChild($Document.CreateElement('sections'))
    [void]$columns.AppendChild($column)
    [void]$tab.AppendChild($columns)
    return $tab
}

# Columns of a layout tab: "columns" with widths, or "sections" for a single column.
function Get-DataverseLayoutColumns {
    param([Parameter(Mandatory)][hashtable]$Tab)
    if ($Tab.columns) { return , @($Tab.columns) }
    return , @(@{ width = '100%'; sections = @($Tab.sections) })
}

# Every field of a layout (header included); a field can be in the header AND in the body.
function Get-DataverseLayoutFields {
    param([Parameter(Mandatory)][hashtable]$Definition)
    $body = [System.Collections.Generic.List[string]]::new()
    foreach ($tab in @($Definition.tabs)) {
        foreach ($column in (Get-DataverseLayoutColumns -Tab $tab)) {
            foreach ($section in @($column.sections)) {
                foreach ($field in @($section.fields)) { if ($field) { $body.Add($field.ToLowerInvariant()) } }
            }
        }
    }
    $duplicates = @($body | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name)
    if ($duplicates) { throw "Fields present twice in the layout body: $($duplicates -join ', ')." }
    $header = @($Definition.header | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })
    return [pscustomobject]@{ body = @($body); header = $header; all = @(@($body) + $header | Select-Object -Unique) }
}

# Builds the FormXml of a layout. $Base (optional): existing FormXml whose content is kept except <tabs> and <header>.
function New-DataverseFormXmlFromLayout {
    param([Parameter(Mandatory)][hashtable]$Definition, [Parameter(Mandatory)][hashtable]$FieldInfo, [Parameter(Mandatory)][string]$LanguageCode, [string]$Base)
    $doc = [xml]::new()
    if ($Base) {
        $doc.LoadXml($Base)
        foreach ($name in 'tabs', 'header') {
            $old = $doc.SelectSingleNode("/form/$name")
            if ($old) { [void]$doc.DocumentElement.RemoveChild($old) }
        }
    }
    else { [void]$doc.AppendChild($doc.CreateElement('form')) }

    $tabsNode = $doc.CreateElement('tabs')
    foreach ($tabDefinition in @($Definition.tabs)) {
        $tab = New-DataverseFormTab -Document $doc -Name $tabDefinition.name -Labels @{ $LanguageCode = ($tabDefinition.label ?? $tabDefinition.name) }
        $columnsNode = $tab.SelectSingleNode('columns')
        [void]$columnsNode.RemoveChild($columnsNode.FirstChild)
        foreach ($columnDefinition in (Get-DataverseLayoutColumns -Tab $tabDefinition)) {
            $column = $doc.CreateElement('column')
            $column.SetAttribute('width', ($columnDefinition.width ?? '100%'))
            $sectionsNode = $doc.CreateElement('sections')
            foreach ($sectionDefinition in @($columnDefinition.sections)) {
                $labels = @{ $LanguageCode = ($sectionDefinition.label ?? $sectionDefinition.name) }
                $fieldList = @($sectionDefinition.fields | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })
                $section = New-DataverseFormSection -Document $doc -Name $sectionDefinition.name -Labels $labels -Columns ([int]($sectionDefinition.columns ?? 1)) -Fields $fieldList -FieldInfo $FieldInfo
                if ($sectionDefinition.showLabel -eq $false) { $section.SetAttribute('showlabel', 'false') }
                if ($sectionDefinition.timeline) {
                    # Timeline: tall cell without label, followed by empty rows it occupies.
                    $rows = $section.SelectSingleNode('rows')
                    $row = $doc.CreateElement('row')
                    $cell = $doc.CreateElement('cell')
                    $cell.SetAttribute('id', "{$([guid]::NewGuid())}")
                    $cell.SetAttribute('showlabel', 'false')
                    $cell.SetAttribute('rowspan', '15')
                    $cell.SetAttribute('auto', 'false')
                    [void]$cell.AppendChild((New-DataverseFormLabels -Document $doc -Labels @{ $LanguageCode = 'Timeline' }))
                    $control = $doc.CreateElement('control')
                    $control.SetAttribute('id', 'notescontrol')
                    $control.SetAttribute('classid', '{06375649-c143-495e-a496-c962e5b4488e}')
                    [void]$cell.AppendChild($control)
                    [void]$row.AppendChild($cell)
                    [void]$rows.AppendChild($row)
                    for ($i = 1; $i -lt 15; $i++) { [void]$rows.AppendChild($doc.CreateElement('row')) }
                }
                [void]$sectionsNode.AppendChild($section)
            }
            [void]$column.AppendChild($sectionsNode)
            [void]$columnsNode.AppendChild($column)
        }
        [void]$tabsNode.AppendChild($tab)
    }
    [void]$doc.DocumentElement.PrependChild($tabsNode)

    $headerFields = @($Definition.header | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })
    if ($headerFields.Count) {
        if ($headerFields.Count -gt 4) { throw "The header accepts 4 fields at most ($($headerFields.Count) requested)." }
        $header = $doc.CreateElement('header')
        $header.SetAttribute('id', "{$([guid]::NewGuid())}")
        $header.SetAttribute('columns', ('1' * $headerFields.Count))
        $header.SetAttribute('celllabelposition', 'Top')
        $header.SetAttribute('labelwidth', '115')
        $rows = $doc.CreateElement('rows')
        $row = $doc.CreateElement('row')
        foreach ($field in $headerFields) {
            $cell = New-DataverseFormCell -Document $doc -Field $field -FieldInfo $FieldInfo
            $cell.SelectSingleNode('control').SetAttribute('id', "header_$field")
            [void]$row.AppendChild($cell)
        }
        [void]$rows.AppendChild($row)
        [void]$header.AppendChild($rows)
        [void]$doc.DocumentElement.InsertAfter($header, $tabsNode)
    }

    foreach ($field in @($Definition.readonlyFields | Where-Object { $_ })) {
        $controls = @($doc.SelectNodes("//control[@datafieldname='$($field.ToLowerInvariant())']"))
        if (-not $controls.Count) { throw "Read-only field missing from the layout: $field." }
        foreach ($c in $controls) { $c.SetAttribute('disabled', 'true') }
    }
    return , $doc
}

# Summary of the components to journal ({type; id; name}) for the final solution check.
function New-AlchemistComponent {
    param([string]$Type, [string]$Id, [string]$Name, [string]$Status)
    return [ordered]@{ type = $Type; id = $Id.Trim('{}'); name = $Name; status = $Status }
}

#endregion

#region Jira

# Ticket source: Jira, or a local file to work without Jira (jira.provider = "local").
function Test-AlchemistLocalTickets {
    param([hashtable]$Config)
    return (Get-AlchemistSetting $Config 'jira.provider' -Default 'jira') -eq 'local'
}

function Get-AlchemistLocalTicketsPath {
    param([hashtable]$Config)
    $relative = Get-AlchemistSetting $Config 'jira.localTicketsFile' -Default '.alchemist/tickets.json'
    return (Join-Path $Config._meta.repoRoot $relative)
}

function Read-AlchemistLocalTickets {
    param([hashtable]$Config)
    $path = Get-AlchemistLocalTicketsPath -Config $Config
    if (-not (Test-Path -LiteralPath $path)) { throw "Local ticket file not found: $path (template: config/tickets.example.json)." }
    return @(Get-Content -Raw -Encoding utf8 -LiteralPath $path | ConvertFrom-Json -AsHashtable)
}

function Save-AlchemistLocalTickets {
    param([hashtable]$Config, [Parameter(Mandatory)][object[]]$Tickets)
    $json = ConvertTo-Json -InputObject @($Tickets) -Depth 10
    [IO.File]::WriteAllText((Get-AlchemistLocalTicketsPath -Config $Config), $json, [Text.UTF8Encoding]::new($false))
}

function Get-JiraAuthHeaders {
    param([hashtable]$Config)
    $jira = Get-AlchemistSetting $Config 'jira' -Required
    $headers = @{ Accept = 'application/json' }
    switch ($jira.authType ?? 'basic') {
        'basic' {
            if (-not $jira.email -or -not $jira.apiToken) { throw "jira.email / jira.apiToken are missing (environment variables?)." }
            $pair = "$($jira.email):$($jira.apiToken)"
            $headers.Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))
        }
        'bearer' {
            if (-not $jira.apiToken) { throw "jira.apiToken is missing (environment variable?)." }
            $headers.Authorization = "Bearer $($jira.apiToken)"
        }
        default { throw "Unknown jira.authType: '$($jira.authType)' (basic | bearer)." }
    }
    return $headers
}

function Invoke-JiraRequest {
    param([hashtable]$Config, [string]$Method = 'GET', [Parameter(Mandatory)][string]$Path, $Body)
    $baseUrl = (Get-AlchemistSetting $Config 'jira.baseUrl' -Required).TrimEnd('/')
    $apiVersion = Get-AlchemistSetting $Config 'jira.apiVersion' -Default '2'
    $uri = if ($Path -match '^https?://') { $Path } else { "$baseUrl/rest/api/$apiVersion/$($Path.TrimStart('/'))" }
    $params = @{ Uri = $uri; Method = $Method; Headers = (Get-JiraAuthHeaders -Config $Config) }
    if ($null -ne $Body) {
        $params.Body = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Body -Depth 32))
        $params.ContentType = 'application/json; charset=utf-8'
    }
    return Invoke-RestMethod @params
}

#endregion

#region Azure DevOps

function Invoke-DevOpsRequest {
    param([hashtable]$Config, [string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, $Body, [hashtable]$Headers, [switch]$AllowNotFound)
    $pat = Get-AlchemistSetting $Config 'devops.pat' -Required
    $requestHeaders = @{
        Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat"))
        Accept        = 'application/json'
    }
    if ($Headers) { foreach ($key in $Headers.Keys) { $requestHeaders[$key] = $Headers[$key] } }
    $params = @{ Uri = $Uri; Method = $Method; Headers = $requestHeaders; SkipHttpErrorCheck = $true }
    if ($null -ne $Body) {
        $params.Body = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Body -Depth 32))
        $params.ContentType = 'application/json; charset=utf-8'
    }
    $response = Invoke-WebRequest @params
    if ($AllowNotFound -and $response.StatusCode -eq 404) { return $null }
    if ($response.StatusCode -ge 400) { throw "Azure DevOps $Method $Uri -> HTTP $($response.StatusCode): $($response.Content)" }
    $content = if ($response.Content) { $response.Content | ConvertFrom-Json -Depth 64 } else { $null }
    return [pscustomobject]@{ Content = $content; ETag = (Get-ResponseHeader -Response $response -Name 'ETag') }
}

function Get-DevOpsBaseUri {
    param([hashtable]$Config)
    $organizationUrl = (Get-AlchemistSetting $Config 'devops.organizationUrl' -Required).TrimEnd('/')
    $project = Get-AlchemistSetting $Config 'devops.project' -Required
    return "$organizationUrl/$([Uri]::EscapeDataString($project))"
}

#endregion

# Allowed capabilities ("allow" section of the config). Each capability maps to a skill. Without an "allow" section,
# everything is allowed except security roles and data import. The old skills.enabled list is still understood.
$script:AllowSkillMap = [ordered]@{
    tables = 'dataverse-create-table'; columns = 'dataverse-create-column'; forms = 'dataverse-form-field'; views = 'dataverse-view'
    apps = 'dataverse-model-driven-app'; ribbon = 'dataverse-ribbon'; plugins = 'dataverse-plugin'; webresources = 'dataverse-webresource'
    securityRoles = 'dataverse-security-role'; alternateKeys = 'dataverse-alternate-key'; businessRules = 'dataverse-business-rule'
    dataImport = 'dataverse-data-import'
}
function Get-AlchemistAllowedCapabilities {
    param([Parameter(Mandatory)][hashtable]$Config)
    $result = [ordered]@{}
    $legacy = $Config.skills.enabled
    foreach ($cap in $script:AllowSkillMap.Keys) {
        $skill = $script:AllowSkillMap[$cap]
        $value = if ($Config.allow -and $Config.allow.Contains($cap)) { [bool]$Config.allow[$cap] }
        elseif ($legacy) { $legacy -contains $skill }
        else { $cap -notin 'securityRoles', 'dataImport' }
        $result[$cap] = [ordered]@{ allowed = $value; skill = $skill }
    }
    return $result
}
Export-ModuleMember -Function * -Variable SolutionComponentTypes

