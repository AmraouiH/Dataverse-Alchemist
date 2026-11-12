---
name: dataverse-testing
description: Runs and writes the tests of a Dynamics 365 development - unit tests (C# plugins, TS/JS web resources), end-to-end tests on the dev environment (metadata, real plugin execution through the Web API, traces) and Playwright browser tests of the components (fields, forms, views, navigation, behaviors) with a report. Use after each implementation, before closing a ticket.
---

# Unit, end-to-end and browser tests

## Unit tests

| Target | Run | Requirement |
|---|---|---|
| Plugins | `Invoke-AlchemistUnitTests.ps1 -IssueKey <KEY> -Kind dotnet` (`dotnet test` of `code.plugins.testProjectPath`) | 100% green; new tests for each rule of the ticket |
| Web resources | `Invoke-AlchemistUnitTests.ps1 -IssueKey <KEY> -Kind node` (`node --test`) | 100% green; tests for each handler added or changed |

The script writes `unit-tests/unit-tests.json`, which the report reads. **Ticket with a plugin: mandatory.** For other
tickets, the Playwright results are mandatory. The report flags the missing result.

If `testing.unit.required` is `true` and no test could be written (no test project, user refusal), flag it as a **risk**
in the summary. Never ignore a failing test and never disable an existing test.

## End-to-end tests (`testing.e2e`, environment `testing.e2e.environment`)

Derive the scenarios from the ticket's **acceptance criteria**: at least one scenario per criterion. Write them in
`.alchemist/runs/<KEY>/e2e/scenarios.md` (Given / When / Then). Scenarios that create or change data are listed in
approval #2.

### By component type

**Columns**: read the metadata (type, length, options, requirement) and compare with the plan.

**Forms**: re-export the published FormXml, then check the controls, their position (tab/section) and the libraries and
handlers.

**Plugins**: real execution through the Web API.
```
# Create a test record (name prefixed with recordPrefix)
Invoke-Dataverse.ps1 -Method POST -Path accounts -Body '{"name":"ALCHEMIST-E2E CRM-123 nominal case","cts_segment":100000002}' -NoSolution -IssueKey CRM-123
# Read the expected result
Invoke-Dataverse.ps1 -Path "accounts(<id>)?`$select=cts_customercode"
# Expected error case: the call must fail with the business message
# Traces when in doubt (if checkPluginTraceLogs)
Invoke-Dataverse.ps1 -Path "plugintracelogs?`$select=messageblock,exceptiondetails,createdon&`$filter=typename eq '<Ns.Class>'&`$orderby=createdon desc&`$top=5"
```
Also check the expected side effects (related records) and the **absence** of effect when an unfiltered field is changed.

**Trace log**: no trace is written if `organizations.plugintracelogsetting` is 0 (Off). Read it before a test that relies
on traces; if it is 0, switching it to 2 (All) on the dev environment is part of the write approval. An **asynchronous**
plugin only traces after its system job runs: poll `plugintracelogs` (every 15 s, for a few minutes) before concluding.
Also check that the **steps are active** (`sdkmessageprocessingsteps`, `statecode = 0`): a disabled step traces nothing
and does nothing.

**Web resources**: `Publish-DataverseWebResource.ps1 ... -Verify` (identical content), handlers present on the form, then
behavior checked in the browser (next section).

## Browser tests (Playwright) - mandatory as soon as a UI component is touched

Fields, forms, views, access in an app, form scripts, business rules, plugin errors as the user sees them. Browser
`testing.ui.browser` (Edge by default), session in `.alchemist/playwright/` (git-ignored).

1. **Generate** the script: `New-AlchemistUiTests.ps1 -IssueKey <KEY>` writes `<testing.ui.specFolder>/<KEY>.ui.spec.mjs`
   (default `tests/ui`, committed). If `testing.ui.enabled` is `false`, replace this section with a manual test
   checklist in the report. Generated section, from the journal and real metadata:
   - each form opens, tabs and sections visible, ticket fields shown, expected required or locked icon, no script error;
   - each view opens with the columns of its layout in order;
   - each table added to an app can be reached from the sitemap;
   - a column on no form gives a skipped test, with the reason. It is a finding to report.
2. **Write the behavior scenarios** in the `alchemist:custom` section (kept on regeneration), at least one per acceptance
   criterion visible on screen. Helpers in `.claude/dataverse-alchemist/playwright/lib/d365.mjs`:
   - form: `openForm`, `setValue`, `setOption`, `selectOption`, `setLookup`, `save()` which returns `{ ok, message, dialog, id }`;
   - control: `errorMessage`, `requiredIcon`, `lockedIcon`, `isRequired`, `displayedValue`;
   - view: `openView`, `gridRow`;
   - data: `createRecord`, `track`, `api` (automatic cleanup at the end of the test), `prefix` for test names.
   - **Business rules and onChange**: use `selectOption` (real drop-down), not `setOption`: a value set by script does
     not run business rules.
   - Respect column max lengths in test data (the prefix counts).
3. **Run**: `Invoke-AlchemistUiTests.ps1 -IssueKey <KEY>` (`-Headed` to watch, `-Login` if the session has expired: the
   user signs in in the browser window). Output: `ui-tests/ui-tests.json`, screenshots, Playwright report
   `ui-tests/html`, trace of failures.
4. **Failure**: read the error and the screenshot. If the test is wrong (selector, data, wait), fix the test. If the
   component is wrong, fix the component. Then rerun the whole suite. Each failure and its fix are recorded in
   `report.json` (a `failed` step, then `done` with the fix). A test is never weakened to make it pass.

### Test data

- Always prefixed with `testing.e2e.recordPrefix` and the ticket key.
- Record each id created in `.alchemist/runs/<KEY>/e2e/records.json`.
- If `cleanup` is `true`: at the end, delete **only** the records listed in that file (`DELETE`), never by a broad query.
  Do not put `[` in `recordPrefix`: in a `startswith`, it acts as a wildcard and matches other records.
- Never run end-to-end tests on an `allowWrite: false` environment.

## Solution check

```
pwsh -NoProfile -File ".claude/dataverse-alchemist/scripts/Test-DataverseSolutionComponents.ps1" -IssueKey <KEY>
```

The script checks that each component created or changed (journal) is in the ticket's solution, and writes
`solution-check.json` (used by the HTML report). If a component is missing, propose `-AddMissing` and wait for the user's
approval.

## Approval and scope

- End-to-end test data (creation, change, deletion) is presented to the user and approved before running.
- Tests cover what the ticket asks. You do not change existing tests, unless the tested behavior changes because of the
  ticket: then present the change.

## Report

`.alchemist/runs/<KEY>/test-report.md`:

```
# Test report <KEY>
## Unit
| Suite | Total | OK | KO | Duration |
## End-to-end
| # | Acceptance criterion | Scenario | Result | Evidence (id, value read, trace) |
## Browser (Playwright)
| Test | Result | Detail |
## Remaining manual testing
- [ ] ...
## Test data
created: n, cleaned up: n
```

On failure: diagnose (code, data, config, permissions), fix if it is code (then rerun the **whole** suite), otherwise
report it. The real result appears in the final summary, even if it is negative.
