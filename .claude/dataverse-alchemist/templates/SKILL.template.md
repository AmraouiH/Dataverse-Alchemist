---
name: dataverse-<component>
description: "<What the skill does>. Use when <concrete triggers in a ticket: keywords, type of need>."
---

<!--
Template for adding a skill to Dataverse Alchemist:
1. Copy this file to skills/<skill-name>/SKILL.md (folder name = name).
2. Add the write script in scripts/ if needed, following the existing scripts:
   parameters -DryRun, -IssueKey, -Environment, -Solution, -ConfigPath; Resolve-AlchemistSolution (ticket solution and
   publisher); Add-DataverseSolutionComponent for each component created or changed; Write-AlchemistJournal with
   "components" (checked by Test-DataverseSolutionComponents and shown in the report); JSON output.
3. Add a line to the breakdown table of skills/jira-ticket-intake/SKILL.md, and start the skill with a "Prerequisites"
   section (ticket solution, conventions.md, strict scope, approval before writing).
4. Add the skill to the list in commands/alchemist-ticket.md (Technical conventions section).
5. Add it to the capability table (`$AllowSkillMap` in AlchemistCommon.psm1) so it can be allowed or not by the `allow`
   section of .alchemist/alchemist.config.json.
6. If it creates UI components, make sure New-AlchemistUiTests.ps1 can generate a browser test for them.
-->

# <Title>

## 1. Analysis (read-only)
- What to check in the CRM and in the repository before proposing anything.

## 2. Design (included in the plan)
| Item | Decision |
|---|---|

## 3. Run
1. Script with `-DryRun` and `-IssueKey`.
2. Table of exact actions in approval #2.
3. Real execution, then check the result.

## 4. Check / tests
- How to prove it is done and matches the ticket (end-to-end and browser tests).

## 5. Documentation
- What to document, and where.
