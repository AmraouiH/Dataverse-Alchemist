#Requires -Version 7.0
<#
.SYNOPSIS
    Records the target solution chosen by the user for a ticket (.alchemist/runs/<KEY>/context.json).
    Every write script run with -IssueKey then uses it: components added to this solution,
    prefix and choice values taken from this solution's publisher.
.EXAMPLE
    Set-AlchemistRunSolution.ps1 -IssueKey CRM-123 -Solution ContosoVentes
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$IssueKey,
    [Parameter(Mandatory)][string]$Solution,
    [string]$Environment,
    [string]$ConfigPath
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force

$config = Get-AlchemistConfig -ConfigPath $ConfigPath
$dvEnv = Get-DataverseEnvironment -Config $config -Name $Environment

$info = Get-DataverseSolutionInfo -Environment $dvEnv -UniqueName $Solution
if ($info.isManaged) { throw "Solution '$Solution' is managed: components cannot be added to it." }

$warnings = @()
if ($info.uniqueName -eq 'Default') { $warnings += "Default solution: components will not be isolated." }
if ($info.publisher.uniqueName -like 'DefaultPublisher*' -or $info.publisher.prefix -eq 'new') {
    $warnings += "Default publisher (prefix '$($info.publisher.prefix)'): avoid it, confirm with the user."
}

$path = Join-Path (Get-AlchemistRunFolder -Config $config -IssueKey $IssueKey) 'context.json'
$context = if (Test-Path -LiteralPath $path) { Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -AsHashtable } else { @{} }
$context.issueKey = $IssueKey.ToUpperInvariant()
$context.solution = $info
$context.solutionSelectedAt = (Get-Date).ToString('o')
$context | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding utf8

Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action 'run.solution.selected' -Details @{
    environment = $dvEnv.name; solution = $info.uniqueName; publisher = $info.publisher.uniqueName; prefix = $info.publisher.prefix
}

[ordered]@{
    solution          = $info.uniqueName
    name              = $info.friendlyName
    version           = $info.version
    publisher         = $info.publisher.uniqueName
    prefix            = $info.publisher.prefix
    optionValuePrefix = $info.publisher.optionValuePrefix
    firstOptionValue  = $info.publisher.optionValuePrefix * 10000
    warnings          = $warnings
    context           = $path
} | ConvertTo-Json
