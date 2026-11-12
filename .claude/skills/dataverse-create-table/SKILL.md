---
name: dataverse-create-table
description: Creates a custom Dataverse table or global choice in the ticket's solution, with that solution's publisher. Use when a ticket asks for a new table (entity) or a list of values shared between several tables.
---

# Creating tables and global choices

## Prerequisites

- Ticket solution chosen, `conventions.md` up to date (skill `dataverse-conventions`).
- Check that an equivalent table or choice does not already exist (`Get-DataverseTableInfo.ps1`, list of global choices
  in `conventions-crm.md`).
- Create only what the ticket asks for.

## Table

```
New-DataverseTable.ps1 -SchemaName <prefix>_Project -DisplayName Project -PluralName Projects -IssueKey <KEY> -DryRun
```

Options: `-Ownership UserOwned|OrganizationOwned`, `-PrimaryNameSchema`, `-PrimaryNameLabel`, `-PrimaryNameMaxLength`,
`-HasNotes`, `-HasActivities`, `-Description`, `-Publish`.

Choices to approve in the plan, because they are **irreversible** or hard to change: `-Ownership`, the technical name,
`-HasActivities`.

Good to know:
- the platform automatically creates the default views and forms (for example "Active <Tables>"): to adjust them,
  `New-DataverseView.ps1` with the same name updates the existing view;
- a table created in the solution is a full component (`rootcomponentbehavior = 0`): its columns, views and forms are
  part of it without being listed one by one.

## Global choice

```
New-DataverseGlobalChoice.ps1 -Name <prefix>_priority -DisplayName Priority -Options "Low;Normal;High" -Publish -IssueKey <KEY> -DryRun
```

Values start from the publisher's option value prefix. For imposed values, use the JSON format. A column is then bound
to it with `New-DataverseColumn.ps1 -Type Choice -GlobalOptionSet <name>`.

## Check

Read the metadata back, then write and read back a test record with the user's approval. Check the solution with
`Test-DataverseSolutionComponents.ps1`.
