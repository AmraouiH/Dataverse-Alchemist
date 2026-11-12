---
name: dataverse-data-import
description: Imports a CSV file into a Dynamics 365 / Dataverse table by upsert on an alternate key - creates missing rows, updates existing ones, leaves identical ones untouched, resolves lookups by business identifier. Use when a ticket asks for an import, a data migration or a sync without duplicates.
---

# Data import (upsert on an alternate key)

## Prerequisites

- An **active alternate key** on the identifying column(s) (otherwise `dataverse-alternate-key` first).
- The file is provided by the ticket. Real data is only imported into an environment with the write approval; for
  testing, rows prefixed with `recordPrefix`, deleted afterwards.

## CSV format (`;` separator, UTF-8)

- Simple column: logical name (`rhz_serialnumber`). Choice: numeric value or label; date `yyyy-mm-dd`; yes/no:
  `true/false`, `yes/no`, `1/0`; decimal with `.` or `,`. Empty cell = value cleared.
- Lookup: `<NavigationName>-><entityset>.<business column>`, e.g. `rhz_AccountId->accounts.rhz_internalcode`. The target
  must be found **exactly once** by its business column.

## Run

```
Import-DataverseData.ps1 -Table rhz_equipment -CsvPath equipment.csv -KeyColumns rhz_serialnumber -IssueKey <KEY> -DryRun
Import-DataverseData.ps1 -Table rhz_equipment -CsvPath equipment.csv -KeyColumns rhz_serialnumber -IssueKey <KEY>
```

- The dry run gives, row by row, `create`, `update` (with the columns that change) or `unchanged`.
- Every row is checked before writing: a data error imports nothing. An API error during the write leaves the rows
  already processed: rerunning the same file completes it without duplicates.
- Creations are journaled as test data (deleted by the rollback); updates are journaled with the previous values.
- Do not use `If-None-Match` / `If-Match` on an alternate key: Dataverse returns 404 (CRM-415).

## Check

Read the rows back by key, rerun the import (expected: all `unchanged`), test a file with an invalid value (expected:
refused, nothing written).
