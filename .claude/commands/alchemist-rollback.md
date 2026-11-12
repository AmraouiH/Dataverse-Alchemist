---
description: Undoes what a ticket did in Dataverse (created components deleted, changed components restored), after the plan is approved
argument-hint: <JIRA-KEY> [--env <environment>]
---

# Rolling back a ticket

Ticket: `$ARGUMENTS`. The ticket journal (`.alchemist/runs/<KEY>/journal.jsonl`) records what was created or changed.

1. **Plan, read-only**:
   ```
   pwsh -NoProfile -File ".claude/dataverse-alchemist/scripts/Get-AlchemistRollbackPlan.ps1" -IssueKey <KEY>
   ```
   It writes `rollback-plan.json`: to delete (created by the ticket and holding no data), to restore (backup
   available), kept (with the reason: holds data, no backup, used elsewhere).
2. **Present the plan** as a table (component, action, reason), including what is kept, then ask with
   `AskUserQuestion`: "Run this rollback" / "Cancel". Nothing runs without this approval.
3. **Execution**, of the approved plan only (its `id`):
   ```
   pwsh -NoProfile -File ".claude/dataverse-alchemist/scripts/Invoke-AlchemistRollback.ps1" -IssueKey <KEY> -PlanId <id>
   ```
   An error on one component does not stop the next ones. Report faithfully what was done, failed or kept.
4. Plugin steps and business rules are restored to their previous state (the script does it after each import).
   The code (git branch) is not touched: offer to delete the branch only if the user asks.
