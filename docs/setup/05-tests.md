# Tests

`testing` section. At the end of a ticket, the HTML report must contain:
- **the unit test results** if the ticket has a plugin;
- **otherwise, the Playwright results**.

If the required result is missing, the report flags it in red.

```json
"testing": {
  "unit": { "required": true },
  "e2e":  { "enabled": true, "environment": "dev", "recordPrefix": "ALCHEMIST-E2E", "cleanup": true, "checkPluginTraceLogs": true },
  "ui":   { "enabled": true, "specFolder": "tests/ui", "browser": "msedge", "sessionHours": 8 }
}
```

## Unit tests

- **C# plugins**: `dotnet test` of the `code.plugins.testProjectPath` project. Without that option, the first
  `*.Tests.csproj` in the project is used. TRX output.
- **Web resources**: `node --test` on the `*.test.js` files of the ticket's scripts.
- Normalized run: `Invoke-AlchemistUnitTests.ps1 -IssueKey <KEY> -Kind dotnet|node|all`, which writes
  `unit-tests/unit-tests.json`. The report reads this file.
- `unit.required: true`: a code ticket without tests is flagged as a risk.

## End-to-end tests (`e2e`)

Scenarios come from the acceptance criteria. The agent creates test records through the Web API, checks the outcome
(real plugin execution, trace log), then deletes the records.

- `recordPrefix`: prefix of test record names. Avoid `[` and `_`, which are wildcards in a `startswith` filter.
- `cleanup`: deletion at the end, only of the records created, by id.
- `checkPluginTraceLogs`: reads the plugin trace log. If it is off in the organization, the agent offers to turn it on in dev.
- Never run on an `allowWrite: false` environment.

## Playwright browser tests (`ui`)

They run as soon as a ticket touches a field, form, view, app, script or business rule.

1. **Generation**: `New-AlchemistUiTests.ps1 -IssueKey <KEY>` writes `<specFolder>/<KEY>.ui.spec.mjs`, to be committed.
   - The **generated part** comes from the ticket journal and real metadata. It checks that each form opens with its
     tabs, sections and fields, that the "required" and "locked" icons are shown, and that there are no script errors.
     It also checks that each view shows its columns in order, and that each table can be reached from the sitemap.
   - A **custom part**, kept on every regeneration, holds the behavior scenarios: error message, field becoming
     required, save rejected by a plugin, calculation.
2. **Run**: `Invoke-AlchemistUiTests.ps1 -IssueKey <KEY>` (`-Headed` to watch the browser, `-Login` to force sign-in).
   Results go to `.alchemist/runs/<KEY>/ui-tests/`: summary, screenshots, Playwright report, and a trace for each
   failure.

**First run**: `npm install` runs automatically in `.claude/dataverse-alchemist/playwright`. A browser window then opens
for you to sign in to the CRM. The session is kept in `.alchemist/playwright/` (git-ignored) for `sessionHours`. If it is
still valid, the window closes by itself.

| Key | Default | Purpose |
|---|---|---|
| `enabled` | `true` | `false`: a manual test checklist replaces the browser tests |
| `specFolder` | `tests/ui` | folder of generated specs, relative to the project |
| `browser` | `msedge` | `msedge` or `chrome` (installed browser), `chromium` (browser downloaded by Playwright) |
| `sessionHours` | `8` | how long the CRM session is reused |
