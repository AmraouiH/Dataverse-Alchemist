# Demo project

A fictional CRM project (publisher `rohzot`, prefix `rhz_`, solution `Alchemist`), processed by Dataverse Alchemist on
a development environment. It shows what the agent produces in a project. The CRM itself is in French: labels, option
values and the messages shown to users are kept as the CRM displays them, because the tests check them.

| Folder | Contents |
|---|---|
| `.alchemist/alchemist.config.json` | project config; the real environment URL is in the `.local.json`, not committed |
| `.alchemist/tickets.json` | local tickets, with the closing comments left by the agent |
| `plugins/` | `Alchemist.Plugins`: account number normalization and change tracing, intervention completion; xUnit tests for intervention completion |
| `webresources/rhz_/js/` | form scripts (account, service contract) and ribbon script, with their `node:test` tests |
| `docs/` | documentation started by the agent: one page per table and per ticket |
| `tests/ui/` | generated Playwright tests, with the behavior scenarios |

The ticket working folders (`.alchemist/runs/`: plans, journals, HTML reports) stay local. They contain environment
identifiers and are not committed.

## Try it on your environment

1. Replace the URL of `dataverse.environments.dev` (or put it in `.alchemist/alchemist.config.local.json`).
2. From this folder:
   ```powershell
   $s = '../../.claude/dataverse-alchemist/scripts'
   pwsh $s/Test-AlchemistConfig.ps1
   pwsh $s/Invoke-AlchemistUnitTests.ps1 -IssueKey CRM-413 -Kind dotnet
   ```
   The browser tests (`Invoke-AlchemistUiTests.ps1`) assume the ticket components exist in your environment.
