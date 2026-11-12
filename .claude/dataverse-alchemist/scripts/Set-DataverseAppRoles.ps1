#Requires -Version 7.0
<#
.SYNOPSIS
    Links security roles to a model-driven app: without it, only administrators see it.
    A role already linked is skipped; an unknown role stops the script before any write.
.EXAMPLE
    Set-DataverseAppRoles.ps1 -AppUniqueName rhz_Ventes -Roles "Salesperson,Sales Manager" -IssueKey CRM-1 -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AppUniqueName,
    [Parameter(Mandatory)][string[]]$Roles,
    [string]$Environment,
    [string]$ConfigPath,
    [string]$IssueKey,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force

$config = Get-AlchemistConfig -ConfigPath $ConfigPath
$dvEnv = Get-DataverseEnvironment -Config $config -Name $Environment
$roleNames = @($Roles | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

$app = @((Invoke-DataverseRequest -Environment $dvEnv -Path "appmodules?`$select=appmoduleid,name&`$filter=uniquename eq '$(ConvertTo-ODataString $AppUniqueName)'").Content.value) | Select-Object -First 1
if (-not $app) { throw "App '$AppUniqueName' not found (or never published)." }
$current = @((Invoke-DataverseRequest -Environment $dvEnv -Path "appmodules($($app.appmoduleid))?`$select=name&`$expand=appmoduleroles_association(`$select=roleid)").Content.appmoduleroles_association | ForEach-Object roleid)

# A role exists in each business unit: the root business unit one carries the link.
$found = foreach ($roleName in $roleNames) {
    $role = @((Invoke-DataverseRequest -Environment $dvEnv -Path "roles?`$select=roleid,name&`$filter=name eq '$(ConvertTo-ODataString $roleName)' and _parentroleid_value eq null").Content.value) | Select-Object -First 1
    if (-not $role) { throw "Security role not found: $roleName" }
    $role
}
$toAdd = @($found | Where-Object { $_.roleid -notin $current })

if ($DryRun) {
    [ordered]@{ dryRun = $true; environment = "$($dvEnv.name) ($($dvEnv.url))"; app = $AppUniqueName; add = @($toAdd.name); alreadyThere = @($found | Where-Object { $_.roleid -in $current } | ForEach-Object name) } | ConvertTo-Json
    return
}
$base = "$($dvEnv.url.TrimEnd('/'))/api/data/v9.2"
foreach ($role in $toAdd) {
    Invoke-DataverseRequest -Environment $dvEnv -Method POST -Path "appmodules($($app.appmoduleid))/appmoduleroles_association/`$ref" -Body @{ '@odata.id' = "$base/roles($($role.roleid))" } | Out-Null
}
$after = @((Invoke-DataverseRequest -Environment $dvEnv -Path "appmodules($($app.appmoduleid))?`$select=name&`$expand=appmoduleroles_association(`$select=roleid)").Content.appmoduleroles_association | ForEach-Object roleid)
$missing = @($found | Where-Object { $_.roleid -notin $after } | ForEach-Object name)
if ($missing) { throw "Roles not linked after writing: $($missing -join ', ')." }
Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action 'dataverse.app.roles' -Details @{ environment = $dvEnv.name; app = $AppUniqueName; roles = @($found.name); added = @($toAdd.name) }
[ordered]@{ updated = $true; app = $AppUniqueName; added = @($toAdd.name); roles = @($found.name) } | ConvertTo-Json
