#Requires -Version 7.0
<#
.SYNOPSIS
    Runs the Playwright browser tests of a ticket (<testing.ui.specFolder>/<KEY>.ui.spec.mjs) on the test environment and
    writes the result to .alchemist/runs/<KEY>/ui-tests/.

.DESCRIPTION
    1. Session: .alchemist/playwright/auth-<env>.json of the project (git-ignored). Missing, older than
       testing.ui.sessionHours (8 h), or -Login: .claude/dataverse-alchemist/playwright/login.mjs opens the browser
       (testing.ui.browser, Edge by default) on a dedicated profile; if the profile session is still valid, the window
       closes by itself, otherwise the user signs in (5 min max).
    2. npx playwright test (.claude/dataverse-alchemist/playwright/playwright.config.mjs), one worker, screenshots always,
       trace on failure.
    3. ui-tests/results.json (raw), ui-tests/html (Playwright report), ui-tests/ui-tests.json (summary read by
       New-AlchemistReport.ps1); journal 'tests.ui.run'.
    Exit code: 0 if no test failed, 1 otherwise. A spec that does not load counts as a failure.
.EXAMPLE
    Invoke-AlchemistUiTests.ps1 -IssueKey CRM-412
    Invoke-AlchemistUiTests.ps1 -IssueKey CRM-412 -Headed -Grep "View"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$IssueKey,
    [string]$Environment,
    [switch]$Login,
    [switch]$Headed,
    [string]$Grep,
    [string]$ConfigPath
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AlchemistCommon.psm1') -Force

$config = Get-AlchemistConfig -ConfigPath $ConfigPath
$IssueKey = $IssueKey.ToUpperInvariant()
$runFolder = Get-AlchemistRunFolder -Config $config -IssueKey $IssueKey
$repoRoot = $config._meta.repoRoot                                    # CRM project root (parent of .alchemist)
$toolDir = (Resolve-Path (Join-Path $PSScriptRoot '..\playwright')).Path
$specFolder = Join-Path $repoRoot (Get-AlchemistSetting $config 'testing.ui.specFolder' -Default 'tests/ui')
$spec = Join-Path $specFolder "$IssueKey.ui.spec.mjs"
if (-not (Test-Path -LiteralPath $spec)) { throw "Spec not found: $spec. Run New-AlchemistUiTests.ps1 -IssueKey $IssueKey first." }

$envName = if ($Environment) { $Environment } elseif ($config.testing.e2e.environment) { $config.testing.e2e.environment } else { $config.dataverse.defaultEnvironment }
$dvEnv = Get-DataverseEnvironment -Config $config -Name $envName
if ($dvEnv.allowWrite -ne $true) { throw "Environment '$envName' is read-only (allowWrite=false): no browser tests." }
$crmUrl = $dvEnv.url.TrimEnd('/')

if (-not (Test-Path (Join-Path $toolDir 'node_modules\@playwright\test'))) {
    Push-Location $toolDir; try { npm install --silent | Out-Null } finally { Pop-Location }
}

# 1. Session
$authDir = Join-Path $repoRoot '.alchemist\playwright'
$statePath = Join-Path $authDir "auth-$envName.json"
$browser = Get-AlchemistSetting $config 'testing.ui.browser' -Default 'msedge'
$sessionHours = [double](Get-AlchemistSetting $config 'testing.ui.sessionHours' -Default 8)
$stale = -not (Test-Path -LiteralPath $statePath) -or ((Get-Date) - (Get-Item -LiteralPath $statePath).LastWriteTime).TotalHours -gt $sessionHours
if ($Login -or $stale) {
    Write-Host "Signing in to $crmUrl (browser window)…"
    & node (Join-Path $toolDir 'login.mjs') --url $crmUrl --env $envName --dir $authDir --channel $browser --timeout 300
    if ($LASTEXITCODE -ne 0) { throw "CRM sign-in not obtained: run again with -Login and sign in in the window." }
}

# 2. Run
$results = Join-Path $runFolder 'ui-tests'
if (Test-Path -LiteralPath $results) { Remove-Item -LiteralPath $results -Recurse -Force }
New-Item -ItemType Directory -Force -Path $results | Out-Null
$env:ALCHEMIST_CRM_URL = $crmUrl
$env:ALCHEMIST_ENV = $envName
$env:ALCHEMIST_ISSUE_KEY = $IssueKey
$env:ALCHEMIST_RECORD_PREFIX = if ($config.testing.e2e.recordPrefix) { $config.testing.e2e.recordPrefix } else { 'ALCHEMIST-E2E' }
$env:ALCHEMIST_PROJECT_ROOT = $repoRoot
$env:ALCHEMIST_UI_TESTDIR = $specFolder
$env:ALCHEMIST_AUTH_STATE = $statePath
$env:ALCHEMIST_BROWSER_CHANNEL = $browser
$env:ALCHEMIST_UI_SPEC = "**/$IssueKey.ui.spec.mjs"
$env:ALCHEMIST_UI_RESULTS = $results
$env:ALCHEMIST_HEADED = if ($Headed) { '1' } else { '0' }
$pwArgs = @('playwright', 'test', '--config', (Join-Path $toolDir 'playwright.config.mjs'))
if ($Grep) { $pwArgs += @('--grep', $Grep) }
$started = Get-Date
Push-Location $toolDir
try { & npx @pwArgs; $exit = $LASTEXITCODE } finally { Pop-Location }

# 3. Summary
$rawPath = Join-Path $results 'results.json'
if (-not (Test-Path -LiteralPath $rawPath)) { throw "Playwright produced no result (code $exit)." }
$raw = Get-Content -Raw -LiteralPath $rawPath | ConvertFrom-Json -Depth 50
$tests = [System.Collections.Generic.List[object]]::new()
function Read-Suite($Suite, [string[]]$Path) {
    $here = if ($Suite.title -and $Suite.title -notlike '*.mjs') { $Path + $Suite.title } else { $Path }
    foreach ($s in @($Suite.specs)) {
        foreach ($t in @($s.tests)) {
            $last = @($t.results)[-1]
            $status = switch ($t.status) { 'expected' { 'passed' } 'unexpected' { 'failed' } 'flaky' { 'flaky' } default { 'skipped' } }
            $error = if ($last.error) { ($last.error.message -replace '\x1b\[[0-9;]*m', '').Trim() } else { $null }
            $shots = @($last.attachments | Where-Object { $_.contentType -eq 'image/png' -and $_.path } | ForEach-Object { [IO.Path]::GetRelativePath($runFolder, $_.path) })
            $tests.Add([ordered]@{
                    suite = ($here -join ' > '); title = $s.title; status = $status; durationMs = [int]$last.duration
                    error = $error; screenshots = $shots
                })
        }
    }
    foreach ($child in @($Suite.suites)) { if ($child) { Read-Suite $child $here } }
}
foreach ($s in @($raw.suites)) { Read-Suite $s @() }
# Errors outside tests (spec that does not load, syntax error): counted as failures, never as "0 tests"
foreach ($e in @($raw.errors)) {
    if (-not $e) { continue }
    $tests.Add([ordered]@{ suite = 'loading'; title = 'Spec loading'; status = 'failed'; durationMs = 0; error = (($e.message ?? $e.value ?? ($e | ConvertTo-Json -Compress)) -replace '\x1b\[[0-9;]*m', '').Trim(); screenshots = @() })
}
if (-not $tests.Count -and $exit -ne 0) { $tests.Add([ordered]@{ suite = 'loading'; title = 'Playwright run'; status = 'failed'; durationMs = 0; error = "Playwright ended with an error (code $exit) without any test result."; screenshots = @() }) }
$summary = [ordered]@{
    issueKey = $IssueKey; environment = $envName; spec = [IO.Path]::GetRelativePath($repoRoot, $spec)
    startedAt = $started.ToString('o'); durationMs = [int]((Get-Date) - $started).TotalMilliseconds
    total = $tests.Count
    passed = @($tests | Where-Object status -eq 'passed').Count
    failed = @($tests | Where-Object status -eq 'failed').Count
    flaky = @($tests | Where-Object status -eq 'flaky').Count
    skipped = @($tests | Where-Object status -eq 'skipped').Count
    htmlReport = 'ui-tests/html/index.html'
    tests = $tests
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $results 'ui-tests.json') -Encoding utf8
Write-AlchemistJournal -Config $config -IssueKey $IssueKey -Action 'tests.ui.run' -Details @{ total = $summary.total; passed = $summary.passed; failed = $summary.failed; skipped = $summary.skipped; environment = $envName }
Write-Host ("Playwright: {0} passed, {1} failed, {2} skipped out of {3}" -f $summary.passed, $summary.failed, $summary.skipped, $summary.total)
exit ($summary.failed -gt 0 ? 1 : 0)


