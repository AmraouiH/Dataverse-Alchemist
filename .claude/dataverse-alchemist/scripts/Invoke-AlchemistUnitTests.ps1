#Requires -Version 7.0
<#
.SYNOPSIS
    Runs the unit tests of a ticket and writes .alchemist/runs/<KEY>/unit-tests/unit-tests.json (read by
    New-AlchemistReport.ps1).

.DESCRIPTION
    -Kind dotnet: dotnet test of the plugin test project (code.plugins.testProjectPath, otherwise the first *.Tests.csproj of the project), TRX logger.
    -Kind node  : node --test on the given *.test.js files (default: those of the journal web resources), JUnit.
    -Kind all   : both. Exit code 1 if a test fails.
.EXAMPLE
    Invoke-AlchemistUnitTests.ps1 -IssueKey CRM-413 -Kind dotnet
    Invoke-AlchemistUnitTests.ps1 -IssueKey CRM-414 -Kind node -TestFiles webresources/rhz_/js/rhz_contratservice.information.test.js
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$IssueKey,
    [ValidateSet('dotnet', 'node', 'all')][string]$Kind = 'all',
    [string]$Project,
    [string[]]$TestFiles,
    [string]$ConfigPath
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force
$config = Get-AlchemistConfig -ConfigPath $ConfigPath
$IssueKey = $IssueKey.ToUpperInvariant()
$runFolder = Get-AlchemistRunFolder -Config $config -IssueKey $IssueKey
$repoRoot = $config._meta.repoRoot                                    # CRM project root (parent of .alchemist)
$out = Join-Path $runFolder 'unit-tests'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$suites = @()

if ($Kind -in 'dotnet', 'all') {
    if (-not $Project) {
        $configured = Get-AlchemistSetting $config 'code.plugins.testProjectPath'
        $Project = if ($configured) { Join-Path $repoRoot $configured } else { @(Get-ChildItem $repoRoot -Recurse -Filter '*.Tests.csproj' -ErrorAction SilentlyContinue | Where-Object FullName -notmatch '[\\/](bin|obj|node_modules)[\\/]' | Select-Object -First 1).FullName }
    }
    if ($Project) {
        $trx = Join-Path $out 'dotnet.trx'
        if (Test-Path $trx) { Remove-Item $trx }
        & dotnet test $Project --logger "trx;LogFileName=$trx" --nologo 2>&1 | Out-Host
        $tests = @()
        if (Test-Path $trx) {
            [xml]$x = Get-Content -Raw $trx
            foreach ($r in $x.TestRun.Results.UnitTestResult) {
                $tests += [ordered]@{
                    name = $r.testName; status = ($r.outcome -eq 'Passed' ? 'passed' : ($r.outcome -eq 'Failed' ? 'failed' : 'skipped'))
                    durationMs = [int]([TimeSpan]::Parse($r.duration ?? '0').TotalMilliseconds)
                    error = $r.Output.ErrorInfo.Message
                }
            }
        }
        $suites += [ordered]@{ kind = 'dotnet'; name = [IO.Path]::GetFileNameWithoutExtension($Project); tests = $tests; ran = (Test-Path $trx) }
    }
}

if ($Kind -in 'node', 'all') {
    if (-not $TestFiles) {
        $journal = Join-Path $runFolder 'journal.jsonl'
        $TestFiles = @(Get-Content $journal -ErrorAction SilentlyContinue | ForEach-Object { ($_ | ConvertFrom-Json).file } |
            Where-Object { $_ -and $_ -like '*.js' -and $_ -notlike '*.test.js' } | ForEach-Object { $_ -replace '\.js$', '.test.js' } |
            Where-Object { Test-Path $_ } | Select-Object -Unique)
    }
    if ($TestFiles) {
        $junit = Join-Path $out 'node.xml'
        & node --test --test-reporter=spec --test-reporter-destination=stdout --test-reporter=junit "--test-reporter-destination=$junit" @TestFiles 2>&1 | Out-Host
        $tests = @()
        if (Test-Path $junit) {
            [xml]$x = Get-Content -Raw $junit
            foreach ($c in $x.SelectNodes('//testcase')) {
                $fail = $c.SelectSingleNode('failure')
                $tests += [ordered]@{ name = $c.name; status = ($fail ? 'failed' : ($c.SelectSingleNode('skipped') ? 'skipped' : 'passed')); durationMs = [int]([double]$c.time * 1000); error = $fail.message }
            }
        }
        $suites += [ordered]@{ kind = 'node'; name = ($TestFiles | ForEach-Object { Split-Path $_ -Leaf }) -join ', '; tests = $tests; ran = (Test-Path $junit) }
    }
}

$all = @($suites | ForEach-Object { $_.tests })
$summary = [ordered]@{
    issueKey = $IssueKey; ranAt = (Get-Date).ToString('o')
    total = $all.Count; passed = @($all | Where-Object status -eq 'passed').Count
    failed = @($all | Where-Object status -eq 'failed').Count; skipped = @($all | Where-Object status -eq 'skipped').Count
    suites = $suites
}
$summary | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $out 'unit-tests.json') -Encoding utf8
Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action 'tests.unit.run' -Details @{ total = $summary.total; passed = $summary.passed; failed = $summary.failed }
Write-Host ("Unit tests: {0} passed, {1} failed, {2} skipped out of {3}" -f $summary.passed, $summary.failed, $summary.skipped, $summary.total)
exit ($summary.failed -gt 0 -or -not $suites.Count ? 1 : 0)

