#Requires -Version 7.0
<#
.SYNOPSIS
    Creates a security role (root business unit) in the ticket solution, or reuses the existing one,
    then adds table privileges to it. Idempotent: a privilege already present is left as is.
.PARAMETER Privileges
    "table:Privilege1,Privilege2:Depth", depth Basic (user), Local (business unit), Deep (business unit and children), Global (organization).
    Privileges: Create, Read, Write, Delete, Append, AppendTo, Assign, Share.
.EXAMPLE
    New-DataverseSecurityRole.ps1 -Name "Contract manager" -Privileges "rhz_servicecontract:Read,Create,Write:Local" -IssueKey CRM-1 -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Name,
    [string]$Description,
    [Parameter(Mandatory)][string[]]$Privileges,
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
$depths = 'Basic', 'Local', 'Deep', 'Global'
$kinds = 'Create', 'Read', 'Write', 'Delete', 'Append', 'AppendTo', 'Assign', 'Share'

# Requested privileges -> ids (metadata of each table).
$wanted = foreach ($spec in $Privileges) {
    $table, $list, $depth = $spec -split ':'
    if (-not $table -or -not $list) { throw "Malformed privilege: '$spec' (expected table:Read,Write:Local)." }
    if (-not $depth) { $depth = 'Basic' }
    if ($depth -notin $depths) { throw "Unknown depth '$depth' (Basic, Local, Deep, Global)." }
    $meta = (Invoke-DataverseRequest -Environment $dvEnv -Path "EntityDefinitions(LogicalName='$($table.Trim().ToLowerInvariant())')?`$select=LogicalName,Privileges").Content
    foreach ($kind in @($list -split ',' | ForEach-Object { $_.Trim() })) {
        if ($kind -notin $kinds) { throw "Unknown privilege '$kind' ($($kinds -join ', '))." }
        $privilege = @($meta.Privileges | Where-Object PrivilegeType -EQ $kind) | Select-Object -First 1
        if (-not $privilege) { throw "Table $($meta.LogicalName) has no $kind privilege." }
        [ordered]@{ table = $meta.LogicalName; kind = $kind; depth = $depth; privilegeId = $privilege.PrivilegeId; name = $privilege.Name }
    }
}

$rootBu = @((Invoke-DataverseRequest -Environment $dvEnv -Path "businessunits?`$select=businessunitid,name&`$filter=_parentbusinessunitid_value eq null").Content.value)[0]
$role = @((Invoke-DataverseRequest -Environment $dvEnv -Path "roles?`$select=roleid,name&`$filter=name eq '$(ConvertTo-ODataString $Name)' and _businessunitid_value eq $($rootBu.businessunitid)").Content.value) | Select-Object -First 1

# Privileges already held by the role (depth included).
$existing = @{}
if ($role) {
    foreach ($rp in @((Invoke-DataverseRequest -Environment $dvEnv -Path "RetrieveRolePrivilegesRole(RoleId=$($role.roleid))").Content.RolePrivileges)) { $existing[[string]$rp.PrivilegeId] = [string]$rp.Depth }
}
$toAdd = @($wanted | Where-Object { $existing[[string]$_.privilegeId] -ne $_.depth })

if ($DryRun) {
    [ordered]@{
        dryRun = $true; environment = "$($dvEnv.name) ($($dvEnv.url))"; solution = $solutionInfo.uniqueName
        role = $Name; exists = [bool]$role; businessUnit = $rootBu.name
        privilegesToAdd = @($toAdd | ForEach-Object { "$($_.name) ($($_.depth))" }); alreadyThere = @($wanted.Count - $toAdd.Count)
    } | ConvertTo-Json -Depth 4
    return
}

$created = $false
if (-not $role) {
    $body = @{ name = $Name; 'businessunitid@odata.bind' = "/businessunits($($rootBu.businessunitid))" }
    if ($Description) { $body.description = $Description }
    $response = Invoke-DataverseRequest -Environment $dvEnv -Method POST -Path 'roles' -Body $body -SolutionUniqueName $solutionInfo.uniqueName
    $role = @{ roleid = $response.EntityId; name = $Name }
    $created = $true
}
if ($toAdd.Count) {
    $body = @{ Privileges = @($toAdd | ForEach-Object { @{ PrivilegeId = $_.privilegeId; Depth = $_.depth; BusinessUnitId = $rootBu.businessunitid } }) }
    Invoke-DataverseRequest -Environment $dvEnv -Method POST -Path "roles($($role.roleid))/Microsoft.Dynamics.CRM.AddPrivilegesRole" -Body $body | Out-Null
}
$status = Add-DataverseSolutionComponent -Environment $dvEnv -Solution $solutionInfo -ComponentId $role.roleid -ComponentType Role

# Check: each requested privilege is present at the right depth.
$after = @{}
foreach ($rp in @((Invoke-DataverseRequest -Environment $dvEnv -Path "RetrieveRolePrivilegesRole(RoleId=$($role.roleid))").Content.RolePrivileges)) { $after[[string]$rp.PrivilegeId] = [string]$rp.Depth }
$missing = @($wanted | Where-Object { $after[[string]$_.privilegeId] -ne $_.depth } | ForEach-Object { "$($_.name) ($($_.depth))" })
if ($missing) { throw "Privileges missing after writing: $($missing -join ', ')." }

$components = @(New-AlchemistComponent -Type Role -Id $role.roleid -Name $Name -Status $status)
$action = if ($created) { 'dataverse.role.create' } else { 'dataverse.role.update' }
Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action $action -Details @{
    environment = $dvEnv.name; role = $Name; roleId = $role.roleid; solution = $solutionInfo.uniqueName
    privilegesAdded = @($toAdd | ForEach-Object { "$($_.name):$($_.depth)" }); components = $components
}
[ordered]@{ created = $created; role = $Name; roleId = $role.roleid; solution = $solutionInfo.uniqueName; privilegesAdded = @($toAdd | ForEach-Object { "$($_.name) ($($_.depth))" }); components = $components } | ConvertTo-Json -Depth 4
