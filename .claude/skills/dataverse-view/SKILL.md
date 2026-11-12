---
name: dataverse-view
description: Creates or updates a Dynamics 365 / Dataverse public view (columns, widths, sort, filter) in the ticket's solution. Use when a ticket asks for a new view, or to add a column or a filter to a view.
---

# Public views

## Prerequisites

- Ticket solution chosen, conventions gathered: view naming, usual columns, widths.
- Only change the requested view. List the existing views:
  `Invoke-Dataverse.ps1 -Path "savedqueries?$select=name,isdefault&$filter=returnedtypecode eq '<table>' and querytype eq 0"`.

## Run

```
New-DataverseView.ps1 -Table account -Name "Active accounts" -Columns name:300,telephone1,rhz_legalrepid:150 `
    -SortColumn name -FilterXml "<filter type='and'><condition attribute='statecode' operator='eq' value='0' /></filter>" `
    -IssueKey <KEY> -DryRun
```

- With the same name, the existing view is **updated**: this is how a view is changed, but its columns and filter are
  entirely replaced. So include every column to keep.
- The first column, or the primary name if present, carries the link to the record.
- The script checks the displayed, sorted and filtered columns. It refuses **File** and **Image** columns, which the
  platform declares valid although a view cannot show them.
- FetchXml has no `@today`: use relative operators (`today`, `next-x-years`, `last-x-days`…).
- Add `-Publish`.

## App

An app does not automatically see a view created after it. Add it with `AddAppComponents`
(`Microsoft.Dynamics.CRM.savedquery`, `savedqueryid`), then publish the app.

## Check

Read back the view's `fetchxml` and `layoutxml`, and check the solution with `Test-DataverseSolutionComponents.ps1`. The
Playwright test generated for the ticket opens the view and checks its columns.
