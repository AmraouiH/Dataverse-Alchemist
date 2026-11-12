---
name: dataverse-model-driven-app
description: Creates a Dynamics 365 model-driven app (Unified Interface) with its sitemap, tables, forms and views, in the ticket's solution. Use when a ticket asks for a new app, to add a table to an app, or to check why an app does not open.
---

# Model-driven app

## Prerequisites

- Ticket solution chosen. The solution will be **exported then re-imported**: state it in the plan. Plugin steps and
  business rules are restored to their previous state after the import (Dataverse disables them otherwise).
- Signed-in user **licensed**, not in Administrative access mode: otherwise the import is refused. The script checks it
  before creating anything.
- Check that the requested tables really exist. Dynamics 365 Sales or Customer Service may be missing: `lead`,
  `opportunity`, `incident`, etc. then do not exist, and those apps cannot be installed on an environment created
  without Dynamics 365 apps.

## Run

`nav.json`:

```json
{ "groups": [
  { "title": "Customers", "tables": ["account", "contact"] },
  { "title": "My Work", "tables": ["activitypointer"] }
] }
```

```
New-DataverseApp.ps1 -Name "Sales" -UniqueName <prefix>_Sales -NavigationFile nav.json -IssueKey <KEY> -DryRun
```

The script creates the app and its sitemap, adds **all** forms (main, quick create) and all public views of the tables:
this is the standard behavior, and the plan states it that way instead of picking some. It declares the tables,
publishes, then **checks the real result**. With `activitypointer`, it also includes appointment, email, phonecall and
task, otherwise activities do not open.

Adding tables to an existing app:

```
Add-DataverseAppTable.ps1 -AppUniqueName <prefix>_Sales -Tables <t> -GroupTitle Service -IssueKey <KEY> -DryRun
```

Navigation entry title different from the table's plural name: `-SubAreaTitles "<t>=Service contracts"`. Also works on
an entry already present (rename only). The title is written in the organization base language.

Giving access to the app:

```
Set-DataverseAppRoles.ps1 -AppUniqueName <prefix>_Sales -Roles "Salesperson,Sales Manager" -IssueKey <KEY> -DryRun
```

## Known pitfalls (do not work around them by hand)

| Pitfall | Consequence | Good practice |
|---|---|---|
| `clienttype` not set | the app is created as 2 and does not open | always 4 |
| `AddAppComponents` with a table | references the system table `entity`, without error | declare the tables in `customizations.xml` and re-import |
| `ValidateApp` | returns success even with wrong tables | read `RetrieveAppComponents` back and resolve each table |
| App not published | missing from the export and from `appmodules` | publish before exporting, `RetrieveUnpublishedMultiple` to find it |
| `appmodulecomponents` | direct creation not supported | go through `AddAppComponents` or the solution |

## Access

System Administrator and System Customizer are associated automatically. For other users, a role must be associated
with the app (`Set-DataverseAppRoles.ps1`), to be specified in the plan.

**Error "You don't have permissions to these records or something may be wrong with the site map"**: check, in this
order, `clienttype`, declared tables, then the user's access mode and license (`systemusers`: `accessmode`,
`islicensed`).

## Check

The Playwright test generated for the ticket opens the app and checks that each added table can be reached from the
sitemap (skill `dataverse-testing`).
