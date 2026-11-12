#Requires -Version 7.0
<#
.SYNOPSIS
    Generic call to the Dataverse Web API (v9.2). For anything without a dedicated script.
.EXAMPLE
    pwsh -NoProfile -File Invoke-Dataverse.ps1 -Path "accounts?`$select=name&`$top=5"
    pwsh -NoProfile -File Invoke-Dataverse.ps1 -Method POST -Path accounts -Body '{"name":"[ALCHEMIST-E2E] test"}' -IssueKey CRM-1
    pwsh -NoProfile -File Invoke-Dataverse.ps1 -Method POST -Path ExportSolution -BodyFile body.json -ReadOnlyAction
#>
[CmdletBinding()]
param(
    [ValidateSet('GET', 'POST', 'PATCH', 'PUT', 'DELETE')][string]$Method = 'GET',
    [Parameter(Mandatory)][string]$Path,
    [string]$Body,
    [string]$BodyFile,
    # Target solution for creations (MSCRM.SolutionUniqueName header). Default: solution chosen for the ticket (-IssueKey).
    [string]$Solution,
    [switch]$NoSolution,
    [switch]$ReadOnlyAction,
    [string]$Environment,
    [string]$ConfigPath,
    [string]$IssueKey,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force

$config = Get-AlchemistConfig -ConfigPath $ConfigPath
$dvEnv = Get-DataverseEnvironment -Config $config -Name $Environment

if ($BodyFile) { $Body = Get-Content -Raw -LiteralPath $BodyFile }
$isWrite = $Method -ne 'GET' -and -not $ReadOnlyAction
$solutionName = if ($isWrite -and -not $NoSolution) { (Resolve-AlchemistSolution -Config $config -Environment $dvEnv -Solution $Solution -IssueKey $IssueKey).uniqueName } else { $null }

if ($DryRun) {
    [ordered]@{
        dryRun      = $true
        environment = "$($dvEnv.name) ($($dvEnv.url))"
        request     = "$Method /api/data/v9.2/$($Path.TrimStart('/'))"
        solution    = $solutionName
        body        = if ($Body) { $Body | ConvertFrom-Json } else { $null }
    } | ConvertTo-Json -Depth 64
    return
}

$result = Invoke-DataverseRequest -Environment $dvEnv -Method $Method -Path $Path -Body $(if ($Body) { $Body } else { $null }) -SolutionUniqueName $solutionName -ReadOnlyAction:$ReadOnlyAction

if ($isWrite) {
    Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action 'dataverse.request' -Details @{
        environment = $dvEnv.name; method = $Method; path = $Path; entityId = $result.EntityId; solution = $solutionName
    }
}

[ordered]@{ statusCode = $result.StatusCode; entityId = $result.EntityId; content = $result.Content } | ConvertTo-Json -Depth 64
