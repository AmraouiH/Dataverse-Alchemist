#Requires -Version 7.0
<#
.SYNOPSIS
    Deploys (creates or updates) a signed plugin assembly and makes sure the plugin types exist.
    For "plugin packages" (NuGet dependencies), use instead: pac plugin push.
.EXAMPLE
    Update-DataversePluginAssembly.ps1 -DllPath bin/Release/net462/Contoso.Plugins.dll -PluginTypes Contoso.Plugins.AccountPreUpdate -IssueKey CRM-1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DllPath,
    # Full names of the IPlugin classes to register (missing types are created).
    [string[]]$PluginTypes,
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
$PluginTypes = @($PluginTypes | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

$fullPath = (Resolve-Path -LiteralPath $DllPath).Path
$assemblyName = [System.Reflection.AssemblyName]::GetAssemblyName($fullPath)
$token = $assemblyName.GetPublicKeyToken()
if (-not $token -or $token.Length -eq 0) { throw "Assembly $($assemblyName.Name) is not signed (strong name required by Dataverse)." }
$publicKeyToken = ($token | ForEach-Object { $_.ToString('x2') }) -join ''
$version = $assemblyName.Version.ToString()
$culture = if ($assemblyName.CultureName) { $assemblyName.CultureName } else { 'neutral' }

if ($DryRun) {
    [ordered]@{
        dryRun         = $true
        environment    = "$($dvEnv.name) ($($dvEnv.url))"
        assembly       = $assemblyName.Name
        version        = $version
        publicKeyToken = $publicKeyToken
        sizeBytes      = (Get-Item -LiteralPath $fullPath).Length
        action         = 'PATCH pluginassemblies(id) if it exists, otherwise POST pluginassemblies (sandbox)'
        pluginTypes    = $PluginTypes
        solution       = $solutionName
    } | ConvertTo-Json
    return
}

$content = [Convert]::ToBase64String([IO.File]::ReadAllBytes($fullPath))
$existing = @((Invoke-DataverseRequest -Environment $dvEnv -Path "pluginassemblies?`$select=pluginassemblyid,version&`$filter=name eq '$(ConvertTo-ODataString $assemblyName.Name)'").Content.value) | Select-Object -First 1

if ($existing) {
    $assemblyId = $existing.pluginassemblyid
    $previous = [Version]$existing.version
    if ($previous.Major -ne $assemblyName.Version.Major -or $previous.Minor -ne $assemblyName.Version.Minor) {
        Write-Warning "Major/minor version changed ($($existing.version) -> $version): Dataverse may refuse the update. Keep major.minor and increment build/revision."
    }
    Save-AlchemistSnapshot -Config $config -IssueKey $IssueKey -Environment $dvEnv -Type PluginAssembly -Name $assemblyName.Name -Path "pluginassemblies($assemblyId)" -Fields content, version
    Invoke-DataverseRequest -Environment $dvEnv -Method PATCH -Path "pluginassemblies($assemblyId)" -Body @{ content = $content; version = $version } | Out-Null
    $action = 'updated'
}
else {
    $body = @{
        name           = $assemblyName.Name
        content        = $content
        version        = $version
        culture        = $culture
        publickeytoken = $publicKeyToken
        isolationmode  = 2   # Sandbox
        sourcetype     = 0   # Database
    }
    $assemblyId = (Invoke-DataverseRequest -Environment $dvEnv -Method POST -Path 'pluginassemblies' -Body $body -SolutionUniqueName $solutionName).EntityId
    $action = 'created'
}

$types = @()
foreach ($typeName in $PluginTypes) {
    $found = @((Invoke-DataverseRequest -Environment $dvEnv -Path "plugintypes?`$select=plugintypeid&`$filter=typename eq '$(ConvertTo-ODataString $typeName)' and _pluginassemblyid_value eq $assemblyId").Content.value) | Select-Object -First 1
    if ($found) {
        $types += [ordered]@{ typeName = $typeName; pluginTypeId = $found.plugintypeid; action = 'exists' }
        continue
    }
    $typeBody = @{
        typename                    = $typeName
        name                        = $typeName
        friendlyname                = $typeName
        'pluginassemblyid@odata.bind' = "/pluginassemblies($assemblyId)"
    }
    $typeId = (Invoke-DataverseRequest -Environment $dvEnv -Method POST -Path 'plugintypes' -Body $typeBody).EntityId
    $types += [ordered]@{ typeName = $typeName; pluginTypeId = $typeId; action = 'created' }
}

$components = @(New-AlchemistComponent -Type PluginAssembly -Id $assemblyId -Name $assemblyName.Name -Status (Add-DataverseSolutionComponent -Environment $dvEnv -Solution $solutionInfo -ComponentId $assemblyId -ComponentType PluginAssembly))

Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action "dataverse.pluginassembly.$action" -Details @{
    environment = $dvEnv.name; assembly = $assemblyName.Name; version = $version; pluginAssemblyId = $assemblyId; pluginTypes = $types; solution = $solutionName; components = $components
}

[ordered]@{ action = $action; assembly = $assemblyName.Name; version = $version; pluginAssemblyId = $assemblyId; pluginTypes = $types; solution = $solutionName; components = $components } | ConvertTo-Json -Depth 5
