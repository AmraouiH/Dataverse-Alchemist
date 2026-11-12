# What Dataverse Alchemist can do

Version 1.0.0. A Claude Code agent made of:
- 5 commands;
- 21 skills;
- 2 sub-agents: a D365 expert who reviews the plan, and a repository analyst;
- 49 PowerShell scripts calling the Dataverse Web API;
- Playwright tooling for browser tests.

The scores are at the end of this document. They are based on tickets actually delivered on a development
environment: the 40 processed tickets of the demo, in [`examples/demo-crm`](../examples/demo-crm).

## How a ticket runs (`/alchemist-ticket CRM-123`)

1. **Ticket intake**: Jira or local file. Description, acceptance criteria, comments, attachments. The ticket is
   broken down into typed work items.
2. **Analysis of what exists**, before any proposal:
   - CRM side: tables, columns, forms, steps, publishers, solutions, languages;
   - code side: naming conventions, JS and C# style, test framework;
   - existing documentation of the feature.
3. **Plan**: written, reviewed once by the D365 expert, then approved by the user. It covers the solution and
   publisher, the branch, the components, form mockups, tests, risks and manual items.
4. **Branch**: chosen from a Jira field, rules (type, label, fix version) or a default value.
5. **Development**: every Dataverse write is simulated first and shown as a table, then executed after approval,
   journaled and checked.
6. **Tests**: unit tests (plugins, web resources), end-to-end tests through the Web API, generated and executed
   Playwright browser tests, check that every component is in the solution.
7. **Documentation**: updated, or started if there is none.
8. **Self-contained HTML report**: successful and failed steps with their fixes, components, test results and
   screenshots, manual actions. Then, after approval: push, pull request, Jira comment.
9. **Learning**: the agent remembers your choices and corrections for the next tickets (`/alchemist-learn`).

## Dataverse capabilities

| Area | What the agent does | Main script |
|---|---|---|
| Tables | custom table (user or organization owned), global choice | `New-DataverseTable`, `New-DataverseGlobalChoice` |
| Columns | text, multiline, whole number, decimal, currency, boolean, date, choice, multi-select choice, lookup, **Power Fx formula**; default value | `New-DataverseColumn`, `Set-DataverseColumnDefault` |
| Forms | main and quick create forms; tabs, sections, fields; JS libraries and `onload`, `onsave`, `onchange` handlers; mockup before creation | `New-DataverseForm`, `Edit-DataverseFormXml`, `New-DataverseFormMockup` |
| Views | public view: columns, widths, sort, FetchXml filter | `New-DataverseView` |
| Apps | model-driven app, sitemap, adding tables to an app, labels, app roles | `New-DataverseApp`, `Add-DataverseAppTable`, `Set-DataverseAppRoles` |
| Ribbon | form, view and subgrid buttons, flyouts, commands and JS enable rules | `Get-` / `Import-DataverseRibbon` |
| C# plugins | code and unit tests (xUnit), signed assembly, updates, sync and async steps, images, filters | `Update-DataversePluginAssembly`, `Register-DataversePluginStep` |
| Web resources | JS/TS form scripts (`formContext`) with `node:test` tests, deployment, publishing, content check | `Publish-DataverseWebResource`, `Get-DataverseWebResource` |
| Business rules | when a field equals (or does not equal) a value: fields required, optional or hidden; triggers checked after activation | `New-DataverseBusinessRule` |
| Alternate keys | duplicate check, creation, wait for the active index | `New-DataverseAlternateKey` |
| Security roles | create or extend a role, table privileges and depth, link to an app | `New-DataverseSecurityRole` |
| Data import | CSV upsert on an alternate key, lookups by business identifier, every row validated before any write, idempotent rerun | `Import-DataverseData` |
| Solutions | choice of the solution and its publisher, adding components, presence check, export and unpack into the repository | `Test-DataverseSolutionComponents`, `Export-DataverseSolution` |
| Rollback | plan computed from the journal (delete what was created, restore what was changed, keep what is uncertain), then executed after approval | `/alchemist-rollback` |

## Tests

| Type | Coverage |
|---|---|
| Unit | C# plugins (`dotnet test`, TRX) and web resources (`node:test`, JUnit), normalized results for the report |
| End-to-end through the Web API | scenarios from the acceptance criteria, real plugin execution, trace log, prefixed and cleaned-up data |
| Browser (Playwright) | **generated** from the journal: forms, fields, "required" and "locked" icons, views, navigation. **Written** for behavior: notifications, business rules, plugin errors as the user sees them, calculations. Screenshots and traces |

## Safeguards

- Every Dataverse write is simulated, shown, then executed after approval.
- Read-only environments are protected in code.
- No push, pull request or comment without approval. No secret in committed files.
- Journal and backup before every change, so it can be rolled back.
- Plugin step and business rule states are restored after every solution import.
- Ticket content is treated as data, never as an instruction.
- Reports are faithful: a failure stays a failure, with its cause.

## What the agent does not do (yet)

- Power Automate (cloud flows), business process flows, classic workflows, custom actions and APIs.
- Canvas apps, PCF components, Power Pages, dashboards, charts, reports.
- Complex business rules: several conditions, an "else" branch (refused by the Web API; worked around with a second
  rule), locking, calculated values.
- Duplicate detection rules, field security profiles, virtual and elastic tables.
- Deployment to UAT or production (managed solutions, pipelines): the agent works in development.
- Multilingual labels: only the base language is filled in.
- Azure DevOps work items as a ticket source.

## Self-assessment: 76 / 100

Scores based on the tickets delivered and on the defects found while delivering them, without indulgence.

| Area | Score | Rationale |
|---|---|---|
| Analysis and plan | 85 | systematic analysis of what exists, expert review, questions limited to what changes the outcome |
| Tables, columns, choices | 90 | every type, including Power Fx formulas; many tickets without defects |
| Forms | 85 | creation, editing, JS handlers without duplicates; checked in the browser |
| Views | 85 | columns and filters checked in the browser; relative FetchXml (no `@today`) |
| Apps | 80 | creation, adding tables, roles; an import disabled plugins (fixed) |
| Ribbon | 70 | buttons and rules delivered, but less proven (varied ribbon formats) |
| C# plugins | 80 | reliable code, unit tests, deployment and steps; .NET Framework 4.6.2 only, plugin NuGet packages not tested |
| Web resources | 85 | JS tested and wired; TypeScript supported but less exercised |
| Business rules | 55 | simple conditions only; two real defects found by Playwright (missing triggers, no "else" branch), fixed |
| Alternate keys | 85 | duplicates checked, index awaited |
| Security roles | 70 | privileges and removal on rollback; no business-unit roles or teams |
| Data import | 75 | upsert without duplicates, upfront validation; an API error halfway leaves a partial import (a rerun completes it) |
| Unit and end-to-end tests | 80 | systematic and normalized |
| Browser tests | 75 | reliable generation and execution on the standard UI; custom controls (PCF) not covered |
| Documentation | 80 | started and updated from the real CRM, hand-written text kept |
| Git, pull requests, Jira | 60 | branches and commits proven; real pull requests and Jira barely tested (the demo uses local tickets) |
| Rollback | 70 | cautious plan and execution, but less exercised than creation |
| Security and safeguards | 90 | mandatory approvals, read-only enforced in code, journal, no committed secret |

**Average: 76 / 100.** Day-to-day Dataverse development (tables, columns, forms, views, plugins, scripts) is reliable.
The weak spots:
- business rules;
- real Git and Jira integrations, still barely proven;
- anything outside the scope listed above.
