#Requires -Version 7.0
<#
.SYNOPSIS
    Exports the (unmanaged) solution through the Web API and, with -Unpack, unpacks it into the repository source folder
    (dataverse.solution.unpackedFolders / unpackedFolderPattern) with "pac solution unpack" (no pac auth needed).
.EXAMPLE
    Export-DataverseSolution.ps1 -Unpack -IssueKey CRM-1
#>
[CmdletBinding()]
param(
    [string]$Solution,
    [string]$OutFile,
    [switch]$Unpack,
    [string]$Environment,
    [string]$ConfigPath,
    [string]$IssueKey
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force

$config = Get-AlchemistConfig -ConfigPath $ConfigPath
$dvEnv = Get-DataverseEnvironment -Config $config -Name $Environment
# Ticket solution (or -Solution); otherwise the default solution of the config.
if (-not $Solution -and -not (Get-AlchemistRunContext -Config $config -IssueKey $IssueKey)) { $Solution = Get-AlchemistSetting $config 'dataverse.solution.default' }
$solutionName = (Resolve-AlchemistSolution -Config $config -Environment $dvEnv -Solution $Solution -IssueKey $IssueKey).uniqueName

if (-not $OutFile) {
    $folder = if ($IssueKey) { Get-AlchemistRunFolder -Config $config -IssueKey $IssueKey } else { [IO.Path]::GetTempPath() }
    $OutFile = Join-Path $folder "$solutionName.zip"
}

$result = Invoke-DataverseRequest -Environment $dvEnv -Method POST -Path 'ExportSolution' -ReadOnlyAction -Body @{ SolutionName = $solutionName; Managed = $false }
[IO.File]::WriteAllBytes($OutFile, [Convert]::FromBase64String($result.Content.ExportSolutionFile))

$unpackedFolder = $null
if ($Unpack) {
    # Source folder: explicit mapping per solution, otherwise the {solution} pattern.
    $folders = Get-AlchemistSetting $config 'dataverse.solution.unpackedFolders' -Default @{}
    $relative = $folders[$solutionName]
    if (-not $relative) {
        $pattern = Get-AlchemistSetting $config 'dataverse.solution.unpackedFolderPattern'
        if (-not $pattern) { throw "No source folder for solution '$solutionName': set dataverse.solution.unpackedFolders or unpackedFolderPattern." }
        $relative = $pattern -replace '\{solution\}', $solutionName
    }
    $unpackedFolder = Join-Path $config._meta.repoRoot $relative
    $custom = Get-AlchemistSetting $config 'dataverse.solution.unpackCommand'
    if ($custom) {
        $command = $custom -replace '\{zip\}', "`"$OutFile`"" -replace '\{folder\}', "`"$unpackedFolder`""
        Invoke-Expression $command
    }
    else {
        $pac = Get-PacCliPath
        if (-not $pac) { throw "pac (Power Platform CLI) not found: install it (dotnet tool install -g Microsoft.PowerApps.CLI.Tool) or set dataverse.solution.unpackCommand." }
        $packageType = Get-AlchemistSetting $config 'dataverse.solution.packageType' -Default 'Unmanaged'
        & $pac solution unpack --zipfile $OutFile --folder $unpackedFolder --packagetype $packageType --allowDelete --allowWrite
    }
    if ($LASTEXITCODE) { throw "Unpack failed (code $LASTEXITCODE)." }
}

Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action 'dataverse.solution.export' -Details @{ environment = $dvEnv.name; solution = $solutionName; zip = $OutFile; unpackedFolder = $unpackedFolder }
[ordered]@{ solution = $solutionName; zip = $OutFile; unpackedFolder = $unpackedFolder } | ConvertTo-Json
