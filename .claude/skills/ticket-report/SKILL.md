---
name: ticket-report
description: At the end of a ticket, prepares the HTML report of the steps performed and their status, in the user's CRM interface language, then, with their approval, posts a Jira comment with the report attached and the pull request link. Use when closing each ticket processed by Dataverse Alchemist.
---

# End-of-ticket report

## 1. Language

```
pwsh -NoProfile -File ".claude/dataverse-alchemist/scripts/New-AlchemistReport.ps1" -IssueKey <KEY> -Mode Language
```

The language used is that of the user's CRM interface, found by the email `report.crmUserEmail` or otherwise `jira.email`.
Otherwise it is the signed-in user, and as a last resort the organization base language. It is stored in
`context.json`. **All written text** (`report.json`, Jira comment) is in that language. The report itself supports
English and French; any other language falls back to English.

## 2. `report.json`

Write `.alchemist/runs/<KEY>/report.json`. The format is described at the top of `New-AlchemistReport.ps1`.

- **steps**: every step of the run, in order. One line per significant step:
  - ticket intake;
  - solution choice;
  - conventions analysis;
  - expert review (number of reviews, verdict, items fixed or rejected);
  - plan (approved or modified);
  - branch creation;
  - each work item: one line per column, form, plugin, web resource;
  - deployments;
  - solution sync;
  - tests: each failure as a `failed` step, then the fix as a `done` step;
  - docs;
  - push, PR and comment.
- **status**, one of:

  | Value | Meaning |
  |---|---|
  | `done` | done and verified |
  | `failed` | failed |
  | `skipped` | not done: refused by the user, or not applicable |
  | `manual` | to be done manually |
  | `warning` | done with a reservation |
  | `pending` | waiting, for example the PR not created yet |

  The status must be **faithful**: a step refused by the user is `skipped`, with the reason.
- **details**: concrete and verifiable (technical name, id, number of tests, error message). No filler.
- **tests**: one line per unit suite and per acceptance criterion tested end to end.
- **manualActions**: what remains for a human (items outside the agent's scope, manual testing).
- **summary**: 3 to 5 lines on what was delivered and what remains.
- **branch**, **baseBranch**, **pullRequest** (if any), **docs** (pages created or updated, and `docs.url`).

Out-of-scope observations noted during the run go into `manualActions`, as suggestions. They are never presented as done.

## 3. Rendering

```
pwsh -NoProfile -File ".claude/dataverse-alchemist/scripts/New-AlchemistReport.ps1" -IssueKey <KEY>
```

The script produces `report-<KEY>.html`, a self-contained file with no external resource. It automatically includes:
- the results of `unit-tests/unit-tests.json` (unit tests) and `ui-tests/ui-tests.json` (Playwright: each test, status,
  error, screenshots);
- a red warning when the mandatory result is missing: unit tests for a ticket with a plugin, Playwright otherwise;
- the Dataverse components from the journal and whether they are in the solution (`solution-check.json`).

Show the user the path and the summary.

## 4. Jira comment (only with the user's approval)

Write `.alchemist/runs/<KEY>/jira-comment.txt` **in the user's CRM language**: summary, overall status, PR link,
remaining manual actions. Preview: `Add-JiraComment.ps1 -IssueKey <KEY> -BodyFile <file> -AttachmentPath <report> -DryRun`.

After approval, and once the PR is created if it was requested: regenerate the report so it contains the PR, then run
without `-DryRun`. The report is attached to the ticket and referenced in the comment.

If the user refuses the comment, the report stays available locally and the step is recorded as `skipped`.
