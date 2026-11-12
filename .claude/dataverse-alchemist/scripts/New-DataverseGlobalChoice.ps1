#Requires -Version 7.0
<#
.SYNOPSIS
    Creates a global choice in the ticket solution. Values generated with the publisher's option value prefix.
.EXAMPLE
    New-DataverseGlobalChoice.ps1 -Name rhz_priority -DisplayName Priority -Options "Low;Normal;High" -Publish -IssueKey CRM-1 -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$DisplayName,
    # "A;B;C" or JSON '[{"value":100000000,"label":"A"}]'
    [Parameter(Mandatory)][string]$Options,
    [string]$Description,
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
$lcid = Get-DataverseBaseLanguage -Environment $dvEnv
Assert-PublisherPrefix -Solution $solutionInfo -Name $Name -What 'Global choice name'
$Name = $Name.ToLowerInvariant()

$names = @((Invoke-DataverseRequest -Environment $dvEnv -Path 'GlobalOptionSetDefinitions?$select=Name').Content.value.Name)
if ($names -contains $Name) { throw "Global choice '$Name' already exists. Nothing was created." }

$items = if ($Options.TrimStart().StartsWith('[')) {
    @($Options | ConvertFrom-Json | ForEach-Object { @{ value = [int]$_.value; label = $_.label } })
}
else {
    $index = 0
    @($Options.Split(';') | Where-Object { $_.Trim() } | ForEach-Object { @{ value = $solutionInfo.publisher.optionValuePrefix * 10000 + $index; label = $_.Trim() }; $index++ })
}

$body = @{
    '@odata.type' = 'Microsoft.Dynamics.CRM.OptionSetMetadata'
    Name          = $Name
    DisplayName   = New-DataverseLabel -Text $DisplayName -LanguageCode $lcid
    IsGlobal      = $true
    OptionSetType = 'Picklist'
    Options       = @($items | ForEach-Object { @{ Value = $_.value; Label = (New-DataverseLabel -Text $_.label -LanguageCode $lcid) } })
}
if ($Description) { $body.Description = New-DataverseLabel -Text $Description -LanguageCode $lcid }

if ($DryRun) {
    [ordered]@{
        dryRun = $true; environment = "$($dvEnv.name) ($($dvEnv.url))"; solution = $solutionInfo.uniqueName; name = $Name
        options = @($items | ForEach-Object { "$($_.value)=$($_.label)" }); publish = [bool]$Publish
    } | ConvertTo-Json
    return
}

$optionSetId = (Invoke-DataverseRequest -Environment $dvEnv -Method POST -Path 'GlobalOptionSetDefinitions' -Body $body -SolutionUniqueName $solutionInfo.uniqueName).EntityId
$components = @(New-AlchemistComponent -Type OptionSet -Id $optionSetId -Name $Name -Status (Add-DataverseSolutionComponent -Environment $dvEnv -Solution $solutionInfo -ComponentId $optionSetId -ComponentType OptionSet))
if ($Publish) { Publish-DataverseXml -Environment $dvEnv -OptionSets @($Name) | Out-Null }

Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action 'dataverse.globalchoice.create' -Details @{
    environment = $dvEnv.name; name = $Name; optionSetId = $optionSetId; solution = $solutionInfo.uniqueName; components = $components
}
[ordered]@{ created = $true; name = $Name; optionSetId = $optionSetId; solution = $solutionInfo.uniqueName; components = $components; published = [bool]$Publish } | ConvertTo-Json -Depth 5
