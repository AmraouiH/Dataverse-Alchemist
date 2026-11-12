---
name: dataverse-conventions
description: Analyzes what exists (CRM and code) before any Dynamics 365 development and produces the ticket's conventions guide - technical names and labels of fields, publisher and prefix, choices and values, web resource and step naming, JS/TS and C# code style (variables, functions, structure, tests). Mandatory before creating a field, form, plugin or script.
---

# Analysis of existing conventions

Goal: everything produced for the ticket must **look like what already exists**, to the point that a reviewer cannot
tell the agent's work from the team's. No style is invented when a practice exists.

## 1. CRM conventions

Prerequisite: the ticket's solution is chosen (`Set-AlchemistRunSolution.ps1`).

```
pwsh -NoProfile -File ".claude/dataverse-alchemist/scripts/Get-DataverseConventions.ps1" -IssueKey <KEY> -Tables <t1>,<t2>
```

`Get-AlchemistPlanContext.ps1 -Tables` runs this script: do not run it again in the plan step. It writes
`conventions-crm.md` and covers:
- the prefixes actually used;
- the format of the technical name after the prefix (PascalCase, lowercase…);
- the `Id` suffix of lookups;
- whether descriptions are filled in, and requirement levels;
- usual text lengths;
- date behaviors;
- choices: local or global, and value style;
- relationship names;
- the web resource tree;
- step names and assemblies.

Complete this data by reading 2 or 3 columns **close to the need** (same table, same type) for the language and style
of labels: initial capital, abbreviations, language of technical names.

**Publisher**: new components **always** use the prefix and option value prefix of the ticket solution's publisher. If
the tables involved mostly use another prefix, do not choose for the user: flag the gap in the plan.

## 2. Code conventions

Only if the ticket touches code: without code, this section and the consolidation are unnecessary.

Launch the `repo-analyst` sub-agent (see its report, "Style guide" section). It must report, **with a real excerpt from
the repository for each point**:
- naming of variables, constants, parameters, methods and classes (camelCase / PascalCase / `_private`, language,
  abbreviations);
- function shape: JS/TS (`function` or arrow functions, `async`/`await` or promises, namespaces or ES modules), C#
  (base class, private methods, LINQ, `var`);
- file structure: one file per form or per table, folders, regions;
- field access: name constants (`Fields.Account.Segment`), early-bound or hard-coded strings;
- error handling, logging and tracing;
- comments: language, density, XML doc or JSDoc;
- tests: test naming, structure, builders and fixtures.

## 3. Consolidation: `.alchemist/runs/<KEY>/conventions.md`

```markdown
# Conventions applied: <KEY>
Solution: <uniqueName> · Publisher: <publisher> · Prefix: <prefix>_ · Choice values: <n>…

| Topic | Rule chosen | Existing example | Applied to this ticket |
|---|---|---|---|
| Column technical name | <prefix>_PascalCase, in English | cts_SignatureDate | cts_CustomerSegment |
| Lookup | Id suffix | cts_AgencyId | cts_DistributorId |
| Choice | local, publisher prefix values | cts_status (100000000…) | cts_segment |
| Web resource | <prefix>_/js/<table>.form.js | cts_/js/account.form.js | (existing file) |
| JS handler | Namespace.Table.Form.onXxxChange(executionContext) | Contoso.Account.Form.onTypeChange | onSegmentChange |
| JS variable | camelCase, formContext first | const formContext = … | same |
| Plugin | <Table><Message><Stage>, inherits PluginBase | AccountPreUpdate | AccountPreUpdate (existing, method added) |
| Step | "<Assembly>.<Class>: <Message> of <table>" | … | … |
| Tests | Method_Case_Result, AAA, FakeXrmEasy | Execute_SegmentNull_DoesNothing | … |

## Gaps / points to decide
- …
```

This file is **included in the plan** ("Conventions applied" section) and **applied by every development skill**. When
existing conventions contradict each other, take the most recent one, or that of the files closest to the need, and
flag it as a point to decide.
