#Requires -Version 7.0
<#
.SYNOPSIS
    Creates or updates a web resource from a local file, adds it to the solution and publishes it.
.EXAMPLE
    Publish-DataverseWebResource.ps1 -FilePath dist/account.form.js -Name cts_/js/account.form.js -Publish -Verify -IssueKey CRM-1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$FilePath,
    [Parameter(Mandatory)][string]$Name,
    [string]$DisplayName,
    [string]$Description,
    [switch]$Publish,
    # Reads the published content back and compares it with the local file.
    [switch]$Verify,
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
Assert-PublisherPrefix -Solution $solutionInfo -Name $Name -What 'Web resource name'

$types = @{ '.htm' = 1; '.html' = 1; '.css' = 2; '.js' = 3; '.xml' = 4; '.png' = 5; '.jpg' = 6; '.jpeg' = 6; '.gif' = 7; '.xsl' = 9; '.xslt' = 9; '.ico' = 10; '.svg' = 11; '.resx' = 12 }
$extension = [IO.Path]::GetExtension($FilePath).ToLowerInvariant()
if (-not $types.ContainsKey($extension)) { throw "Unsupported extension for a web resource: $extension" }

$fullPath = (Resolve-Path -LiteralPath $FilePath).Path
$content = [Convert]::ToBase64String([IO.File]::ReadAllBytes($fullPath))
$n = ConvertTo-ODataString $Name

$existing = $null
if (-not $DryRun) {
    $existing = @((Invoke-DataverseRequest -Environment $dvEnv -Path "webresourceset?`$select=webresourceid,name&`$filter=name eq '$n'").Content.value) | Select-Object -First 1
}

if ($DryRun) {
    [ordered]@{
        dryRun      = $true
        environment = "$($dvEnv.name) ($($dvEnv.url))"
        action      = 'POST webresourceset (create) or PATCH webresourceset(id) (update) depending on existence'
        name        = $Name
        type        = $types[$extension]
        file        = $fullPath
        sizeBytes   = (Get-Item -LiteralPath $fullPath).Length
        solution    = $solutionName
        publish     = [bool]$Publish
    } | ConvertTo-Json
    return
}

if ($existing) {
    $id = $existing.webresourceid
    $patch = @{ content = $content }
    if ($DisplayName) { $patch.displayname = $DisplayName }
    if ($Description) { $patch.description = $Description }
    Save-AlchemistSnapshot -Config $config -IssueKey $IssueKey -Environment $dvEnv -Type WebResource -Name $existing.name -Path "webresourceset($id)" -Fields content -ReadPath "webresourceset($id)/Microsoft.Dynamics.CRM.RetrieveUnpublished()"
    Invoke-DataverseRequest -Environment $dvEnv -Method PATCH -Path "webresourceset($id)" -Body $patch | Out-Null
    $action = 'updated'
}
else {
    $body = @{
        name            = $Name
        displayname     = if ($DisplayName) { $DisplayName } else { $Name }
        webresourcetype = $types[$extension]
        content         = $content
    }
    if ($Description) { $body.description = $Description }
    $id = (Invoke-DataverseRequest -Environment $dvEnv -Method POST -Path 'webresourceset' -Body $body -SolutionUniqueName $solutionName).EntityId
    $action = 'created'
}

$components = @(New-AlchemistComponent -Type WebResource -Id $id -Name $Name -Status (Add-DataverseSolutionComponent -Environment $dvEnv -Solution $solutionInfo -ComponentId $id -ComponentType WebResource))
if ($Publish) { Publish-DataverseXml -Environment $dvEnv -WebResourceIds @($id) | Out-Null }

$verified = $null
if ($Verify) {
    $remote = (Invoke-DataverseRequest -Environment $dvEnv -Path "webresourceset($id)?`$select=content").Content.content
    $verified = ($remote -eq $content)
    if (-not $verified) { Write-Warning "The remote content differs from the local file after deployment." }
}

Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action "dataverse.webresource.$action" -Details @{
    environment = $dvEnv.name; name = $Name; webResourceId = $id; file = $fullPath; solution = $solutionName; components = $components
}

[ordered]@{ action = $action; name = $Name; webResourceId = $id; published = [bool]$Publish; verified = $verified; solution = $solutionName; components = $components } | ConvertTo-Json -Depth 5
