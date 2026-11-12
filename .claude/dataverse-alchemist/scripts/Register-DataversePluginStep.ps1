#Requires -Version 7.0
<#
.SYNOPSIS
    Creates or updates a plugin step (and its pre/post images), then adds it to the solution.
.EXAMPLE
    Register-DataversePluginStep.ps1 -PluginTypeName Contoso.Plugins.AccountPreUpdate -Message Update -Table account `
        -Stage PreOperation -FilteringAttributes cts_segment,name -PreImageAttributes cts_segment -IssueKey CRM-1 -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PluginTypeName,
    [Parameter(Mandatory)][string]$Message,
    [string]$Table,
    [ValidateSet('PreValidation', 'PreOperation', 'PostOperation')][string]$Stage = 'PostOperation',
    [ValidateSet('Sync', 'Async')][string]$Mode = 'Sync',
    [int]$Rank = 1,
    [string[]]$FilteringAttributes,
    [string]$Name,
    [string]$UnsecureConfiguration,
    # "*" for all columns, otherwise a list
    [string[]]$PreImageAttributes,
    [string[]]$PostImageAttributes,
    [string]$PreImageName = 'PreImage',
    [string]$PostImageName = 'PostImage',
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

function Join-List([string[]]$Values) { (@($Values | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ }) -join ',') }

$stageCode = @{ PreValidation = 10; PreOperation = 20; PostOperation = 40 }[$Stage]
$modeCode = if ($Mode -eq 'Async') { 1 } else { 0 }
$filtering = Join-List $FilteringAttributes
$preAttrs = Join-List $PreImageAttributes
$postAttrs = Join-List $PostImageAttributes
if ($Mode -eq 'Async' -and $Stage -ne 'PostOperation') { throw "An asynchronous step must be PostOperation." }
if ($postAttrs -and $Stage -ne 'PostOperation') { throw "A post-image is only available in PostOperation." }
if ($preAttrs -and $Message -eq 'Create') { throw "No pre-image on the Create message." }
if ($filtering -and $Message -ne 'Update') { Write-Warning "Filtering attributes only apply to the Update message." }
if (-not $Name) { $Name = "$PluginTypeName`: $Message of $(if ($Table) { $Table } else { 'any entity' })" }

$stepBody = @{
    name                = $Name
    stage               = $stageCode
    mode                = $modeCode
    rank                = $Rank
    supporteddeployment = 0
    asyncautodelete     = ($Mode -eq 'Async')
    filteringattributes = if ($filtering) { $filtering } else { $null }
    configuration       = $UnsecureConfiguration
}
$messagePropertyName = if ($Message -eq 'Create') { 'Id' } else { 'Target' }
$images = @()
if ($preAttrs) { $images += @{ name = $PreImageName; entityalias = $PreImageName; imagetype = 0; attributes = if ($preAttrs -eq '*') { $null } else { $preAttrs } } }
if ($postAttrs) { $images += @{ name = $PostImageName; entityalias = $PostImageName; imagetype = 1; attributes = if ($postAttrs -eq '*') { $null } else { $postAttrs } } }

if ($DryRun) {
    [ordered]@{
        dryRun      = $true
        environment = "$($dvEnv.name) ($($dvEnv.url))"
        pluginType  = $PluginTypeName
        message     = $Message
        table       = $Table
        step        = $stepBody
        images      = $images
        solution    = $solutionName
        action      = 'PATCH if an identical step (type + message + table + stage) exists, otherwise POST'
    } | ConvertTo-Json -Depth 6
    return
}

$typeId = @((Invoke-DataverseRequest -Environment $dvEnv -Path "plugintypes?`$select=plugintypeid&`$filter=typename eq '$(ConvertTo-ODataString $PluginTypeName)'").Content.value)[0].plugintypeid
if (-not $typeId) { throw "Plugin type '$PluginTypeName' not found. Deploy the assembly first (Update-DataversePluginAssembly.ps1 -PluginTypes ...)." }
$messageId = @((Invoke-DataverseRequest -Environment $dvEnv -Path "sdkmessages?`$select=sdkmessageid&`$filter=name eq '$(ConvertTo-ODataString $Message)'").Content.value)[0].sdkmessageid
if (-not $messageId) { throw "Message '$Message' not found." }

$filterId = $null
if ($Table) {
    $filterId = @((Invoke-DataverseRequest -Environment $dvEnv -Path "sdkmessagefilters?`$select=sdkmessagefilterid&`$filter=_sdkmessageid_value eq $messageId and primaryobjecttypecode eq '$($Table.ToLowerInvariant())'").Content.value)[0].sdkmessagefilterid
    if (-not $filterId) { throw "Message '$Message' is not available for table '$Table'." }
}

$stepBody['eventhandler_plugintype@odata.bind'] = "/plugintypes($typeId)"
$stepBody['sdkmessageid@odata.bind'] = "/sdkmessages($messageId)"
if ($filterId) { $stepBody['sdkmessagefilterid@odata.bind'] = "/sdkmessagefilters($filterId)" }

$filter = "_eventhandler_value eq $typeId and _sdkmessageid_value eq $messageId and stage eq $stageCode"
$filter += if ($filterId) { " and _sdkmessagefilterid_value eq $filterId" } else { ' and _sdkmessagefilterid_value eq null' }
$existing = @((Invoke-DataverseRequest -Environment $dvEnv -Path "sdkmessageprocessingsteps?`$select=sdkmessageprocessingstepid&`$filter=$filter").Content.value) | Select-Object -First 1

if ($existing) {
    $stepId = $existing.sdkmessageprocessingstepid
    Save-AlchemistSnapshot -Config $config -IssueKey $IssueKey -Environment $dvEnv -Type SdkMessageProcessingStep -Name $Name -Path "sdkmessageprocessingsteps($stepId)" -Fields filteringattributes, mode, rank, stage
    Invoke-DataverseRequest -Environment $dvEnv -Method PATCH -Path "sdkmessageprocessingsteps($stepId)" -Body $stepBody | Out-Null
    $action = 'updated'
}
else {
    $stepId = (Invoke-DataverseRequest -Environment $dvEnv -Method POST -Path 'sdkmessageprocessingsteps' -Body $stepBody -SolutionUniqueName $solutionName).EntityId
    $action = 'created'
}

$imageResults = @()
$existingImages = @((Invoke-DataverseRequest -Environment $dvEnv -Path "sdkmessageprocessingstepimages?`$select=sdkmessageprocessingstepimageid,entityalias&`$filter=_sdkmessageprocessingstepid_value eq $stepId").Content.value)
foreach ($image in $images) {
    $imageBody = $image + @{ messagepropertyname = $messagePropertyName; 'sdkmessageprocessingstepid@odata.bind' = "/sdkmessageprocessingsteps($stepId)" }
    $match = $existingImages | Where-Object { $_.entityalias -eq $image.entityalias } | Select-Object -First 1
    if ($match) {
        Invoke-DataverseRequest -Environment $dvEnv -Method PATCH -Path "sdkmessageprocessingstepimages($($match.sdkmessageprocessingstepimageid))" -Body $imageBody | Out-Null
        $imageResults += [ordered]@{ alias = $image.entityalias; action = 'updated' }
    }
    else {
        $imageId = (Invoke-DataverseRequest -Environment $dvEnv -Method POST -Path 'sdkmessageprocessingstepimages' -Body $imageBody).EntityId
        $imageResults += [ordered]@{ alias = $image.entityalias; action = 'created'; id = $imageId }
    }
}

$components = @(New-AlchemistComponent -Type SdkMessageProcessingStep -Id $stepId -Name $Name -Status (Add-DataverseSolutionComponent -Environment $dvEnv -Solution $solutionInfo -ComponentId $stepId -ComponentType SdkMessageProcessingStep))

Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action "dataverse.pluginstep.$action" -Details @{
    environment = $dvEnv.name; stepId = $stepId; name = $Name; message = $Message; table = $Table; stage = $Stage; mode = $Mode; images = $imageResults; solution = $solutionName; components = $components
}

[ordered]@{ action = $action; stepId = $stepId; name = $Name; images = $imageResults; solution = $solutionName; components = $components } | ConvertTo-Json -Depth 5
