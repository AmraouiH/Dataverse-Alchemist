---
name: dataverse-alternate-key
description: Creates a Dynamics 365 / Dataverse alternate key (uniqueness on one or more columns) in the ticket's solution, after checking existing duplicates, and waits for the index to be active. Use when a ticket asks for a value to be unique, or for an integration key (upsert).
---

# Alternate keys

## Prerequisites

- Ticket solution chosen. Columns of type text, whole number, decimal, date, lookup or choice (no multiline text, image
  or file). One key per column combination.

## Run

```
New-DataverseAlternateKey.ps1 -Table account -SchemaName rhz_InternalCodeKey -DisplayName "Internal code" `
    -Columns rhz_internalcode -IssueKey <KEY> -DryRun
```

- The dry run lists **existing duplicates** (non-empty values): if there are any, the index would fail. Fixing them is a
  business decision, to raise in the plan; the script refuses to create the key while duplicates remain.
- The index is built by a system job: the script waits for the `Active` status (5 min by default, `-TimeoutSeconds`).
  On `Failed`, fix the duplicates then `ReactivateEntityKey`.
- Empty values do not count as duplicates.

## Check

End-to-end test: create two records with the same value; the second must be refused (HTTP 412,
"Entity Key ... violated"). Delete the test record. The rollback deletes the key.
