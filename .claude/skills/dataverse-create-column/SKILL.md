---
name: dataverse-create-column
description: Creates Dataverse / Dynamics 365 columns (fields) in the ticket's solution, with that solution's publisher and the existing conventions - text, multiline text, whole number, decimal, currency, boolean, date, choice, multi-select choice, lookup, Power Fx formula. Use when a ticket asks for a new field on a table.
---

# Creating Dataverse columns

## Prerequisites

- The ticket's solution is chosen (`Set-AlchemistRunSolution.ps1`): prefix and choice values come from **that
  solution's publisher**, and scripts run with `-IssueKey` apply them automatically.
- `conventions.md` exists (skill `dataverse-conventions`). Each column follows the observed conventions:
  - technical name format (case, language, `Id` suffix for lookups);
  - label style and whether descriptions are filled in;
  - usual text length and date behavior;
  - local or global choice, and value style.
- Create **only** the columns the ticket asks for.

## Analysis

1. Check the column does not already exist, including under a similar name:
   `Get-DataverseTableInfo.ps1 -Table <t> -Attributes -AttributeFilter <keyword>`.
   If an equivalent column exists, propose reusing it instead of creating one.
2. For a choice, check whether a reusable **global choice** exists (list in `conventions-crm.md`). Its default value is
   then set with `Set-DataverseColumnDefault.ps1 -Table <t> -Column <c> -Value <label> -IssueKey <KEY>`. A multi-select
   choice has none. If the same values are used on several tables, propose a global choice.
3. For a lookup, check the target table and existing relationships.

## Need to parameters

| Business need | `-Type` | Useful parameters |
|---|---|---|
| Short text | `String` | `-MaxLength` (default 100), `-Format Text\|Email\|Url\|Phone\|TickerSymbol`, `-AutoNumberFormat "TST-{SEQNUM:5}"` |
| Long text | `Memo` | `-MaxLength` (default 2000), `-Format RichText` |
| Whole number | `Integer` | `-MinValue -MaxValue`, `-IntegerFormat None\|Duration\|TimeZone\|Language` |
| Big integer | `BigInt` | |
| Decimal number | `Decimal` | `-Precision -MinValue -MaxValue` |
| Floating point number | `Float` | `-Precision -MinValue -MaxValue` |
| Amount | `Money` | `-Precision` |
| Yes/No | `Boolean` | `-TrueLabel -FalseLabel -DefaultTrue` |
| Date | `DateTime` | `-DateFormat DateOnly\|DateAndTime`, `-DateBehavior UserLocal\|DateOnly\|TimeZoneIndependent` |
| List of values | `Choice` | `-Options "A;B;C"` or JSON `[{"value":..,"label":..}]`, or `-GlobalOptionSet <name>` |
| Multi-value list | `MultiChoice` | same |
| Reference to another table | `Lookup` | `-TargetTable`, `-RelationshipSchemaName`, `-DeleteBehavior RemoveLink\|Restrict\|Cascade`, `-AssociatedMenuBehavior DoNotDisplay` |
| Customer (account or contact) | `Customer` | creates 2 relationships, navigation names `<SchemaName>_account` / `_contact` |
| Image | `Image` | `-MaxSizeKB` |
| File | `File` | `-MaxSizeKB` |
| Calculated value (read-only) | `Decimal`, `Integer`, `Float`, `String`, `Boolean`, `DateTime` | `-Formula "DateDiff(rhz_startdate, rhz_enddate, TimeUnit.Days)"` (Power Fx formula, computed on read; no `-RequiredLevel` and no auto-number) |

Common: `-SchemaName <prefix>_<Name>` (format per `conventions.md`; the script refuses a prefix other than that of the
solution's publisher), `-DisplayName`, `-Description`, `-RequiredLevel None|Recommended|ApplicationRequired`.

Points of attention:
- **Date behavior**: `DateOnly` for a date without time (birthday, due date). This choice is hard to reverse, to be
  approved in the plan.
- **Choice values**: generated from the solution publisher's option value prefix (e.g. 10000 → 100000000, 100000001…).
  If what exists uses another style, or if the ticket or an external system imposes values, use the JSON format with
  explicit values, and flag it in the plan.
- **Required**: `ApplicationRequired` impacts existing imports and integrations. Flag it in the plan.
- **Labels**: `-DisplayName` is in the base language (`dataverse.baseLanguageCode`). Other languages requested by the
  ticket go through `-DisplayNameTranslations "1036=Client,1031=Kunde"` (same for `-DescriptionTranslations`). During
  analysis, check these languages are installed: `Invoke-Dataverse.ps1 -Path "RetrieveProvisionedLanguages()"`. The
  script refuses a language that is not installed rather than losing the translation. If the ticket does not give the
  translation for an installed language, do not invent one: ask.

Known platform limits, to state in the plan:
- `BigInt` cannot be used on a form;
- `File` and `Image` cannot be used in a view;
- `Image`: the script keeps the full image (`CanStoreFullImage`), on top of the 144 px thumbnail. The first image column
  of a table becomes its primary image: this cannot be refused;
- the `Json` format is reserved for non-relational tables: not offered;
- `Merge` is always `Cascade` on a relationship, whatever value is requested;
- creating a lookup also adds the **target table** to the solution (root component only): this is platform behavior,
  to state in the plan;
- `Customer` accepts no menu or cascade option.

The base language comes from the organization, not from the config: a mismatch shows a warning. The dry run also checks
whether the column exists and which languages are installed.

## Run

1. For each column: `New-DataverseColumn.ps1 ... -IssueKey <KEY> -DryRun`. Collect the payloads.
2. Present the table (table, logical name, label, type, details, required, solution, publisher, environment) in
   **approval #2**. Group all the ticket's columns in a single batch.
3. After approval: same command without `-DryRun`. Add `-Publish` on the **last** column of each table, or publish at
   the end with `Publish-DataverseCustomizations.ps1 -Tables <t1>,<t2>`.
4. The script adds the table (root component only, without its other columns) then the column to the ticket's
   solution, and returns `components` with an `added` or `present` status. Check this output.
5. The script refuses to recreate an existing column. On error, do not try a random variant: analyze the message and
   propose a fix.

## Check

`Invoke-Dataverse.ps1 -Path "EntityDefinitions(LogicalName='<t>')/Attributes(LogicalName='<col>')"`: check the type,
length, options and requirement level. The result goes into the test report (end-to-end section, "metadata").

## Code and docs

- If the repository uses early-bound classes or field name constants, update them (regenerate with the repository's
  tool, or add manually following the existing format) and commit.
- Docs: add the column to the table's data dictionary (skill `feature-documentation`).
