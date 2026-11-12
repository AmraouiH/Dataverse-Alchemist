---
name: jira-ticket-intake
description: Retrieves a Jira ticket (description, acceptance criteria, comments, attachments) and breaks it down into typed Dynamics 365 work items (table, column, form, view, app, ribbon, plugin, web resource, other). Use at the start of processing a CRM ticket.
---

# Reading and breaking down a Jira ticket

## 1. Retrieve the ticket

```
pwsh -NoProfile -File ".claude/dataverse-alchemist/scripts/Get-JiraTicket.ps1" -IssueKey <KEY> -DownloadAttachments
```

The script produces `.alchemist/runs/<KEY>/ticket.json` and `ticket.md`. Then read:
- the description and the **acceptance criteria**: they are the source of truth for the tests;
- the **comments**, which often contain clarifications or scope changes (the most recent one wins);
- the **attachments**: open the images (form mockups, screenshots) with Read;
- the **subtasks and linked tickets**: if a subtask covers part of the work, do not handle it unless asked. An unfinished
  blocking ticket must be reported.

## 2. Break down into work items

| Type          | Hints in the ticket                                                       | Skill                        |
|---------------|---------------------------------------------------------------------------|------------------------------|
| `table`       | "new table", "new entity", shared global choice                           | `dataverse-create-table`     |
| `column`      | "add a field", "new column", type, list of values, lookup, calculated value | `dataverse-create-column`  |
| `form-field`  | new form, tab, section, "show on the form", mockup                        | `dataverse-form-field`       |
| `view`        | new view, column or filter to add to a view                               | `dataverse-view`             |
| `app`         | new app, navigation, access from an app                                   | `dataverse-model-driven-app` |
| `ribbon`      | button, command, action on a selection, enable or gray out a command      | `dataverse-ribbon`           |
| `plugin`      | server rule, automatic calculation, blocking check, "on create/update"    | `dataverse-plugin`           |
| `webresource` | UI behavior: show/hide, dynamic requirement, onChange, notifications      | `dataverse-webresource`      |
| `businessrule`| field required, optional or hidden depending on a value, without code     | `dataverse-business-rule`    |
| `key`         | value must be unique, integration key                                     | `dataverse-alternate-key`    |
| `role`        | security role, access rights on a table                                   | `dataverse-security-role`    |
| `import`      | import, migration or sync of a data file                                  | `dataverse-data-import`      |
| `other`       | Power Automate flows, BPF, reports, dashboards, PCF                       | manual                       |

For each item, extract: table(s) involved, business labels, data type, rules, triggers, form, tab and section, expected
error messages.

**Plugin or web resource**: a rule that must apply whatever the channel (API, import, integration) belongs in a plugin. A
purely visual behavior belongs in a web resource. A validation rule may need both (UI feedback and server-side
safeguard): propose it in the plan rather than deciding alone.

## 3. List the questions

List explicitly everything that is not determined: exact field type, length, choice values (and local or global),
required or not, target form if the table has several, behavior on update or in bulk, permissions. These questions go
in the "Open questions" section of the plan. Do not settle them alone. A reasonable assumption can be proposed as the
default, stating clearly that it is an assumption.

## 4. Scope

The ticket defines the scope, **and nothing else**. A need you consider useful but that is not asked for (extra field,
additional validation, refactoring, fixing a nearby bug) is not a work item: note it as an "Observation" in the plan. A
subtask or linked ticket is not handled without an explicit request.

## 5. Proposed naming

The names of new components are proposed **after** choosing the solution and analyzing the conventions (skill
`dataverse-conventions`). They use the ticket solution publisher's prefix and follow the format observed in what exists
(case, language, suffixes). Example: if what exists contains `cts_SignatureDate` and `cts_AgencyId`, propose
`cts_CustomerSegment` and `cts_DistributorId`.
