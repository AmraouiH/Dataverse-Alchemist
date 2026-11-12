---
name: dataverse-ribbon
description: Adds or changes ribbon (command bar) buttons of a Dynamics 365 table - form, view or subgrid button, flyout - with commands and enable rules in JavaScript in a dedicated web resource. Use when a ticket asks for a button, an action on a selection, or to enable or hide a command.
---

# Ribbon buttons

## Prerequisites

- Ticket solution chosen, conventions gathered. Id prefix is the publisher's (`rhz.account...`).
- Signed-in user licensed, not in Administrative access mode: the change goes through a solution import (plugin steps
  and business rules are restored to their previous state afterwards).
- Only the buttons the ticket asks for.

## 1. Analyze

```
Get-DataverseRibbon.ps1 -Table <t> -ExportDiff <t>.ribbondiff.xml -IssueKey <KEY>
```

The script returns the table's real locations, the unmanaged JS libraries already used by its ribbon, and writes the
current `RibbonDiffXml`. **Always start from this file**: the import replaces the table's entire `RibbonDiffXml`, and
starting from an empty file would delete the existing buttons.

## 2. JavaScript

**Every action and every enable rule is in JavaScript**, in the table's ribbon web resource:
- if `customLibraries` lists one for this table, extend it;
- otherwise create `<prefix>_/js/<table>.ribbon.js`, separate from the form script, with a namespace and the functions
  exposed by `return { ... }`.

`CrmParameter` values:

| Value | Context | Received by the function |
|---|---|---|
| `PrimaryControl` | form | the `formContext` |
| `SelectedControl` | view, subgrid | the grid control |
| `SelectedControlSelectedItemIds` | view, subgrid | array of ids, with braces |
| `SelectedControlSelectedItemCount` | view, subgrid | number of selected rows |

Rules:
- an enable rule returns a boolean or a `Promise` of boolean; `Default="false"` keeps the button disabled if the JS
  fails;
- the ribbon does not re-evaluate its rules when a field changes: call `formContext.ui.refreshRibbon()` from
  `addOnChange`, once per field;
- an asynchronous rule must catch its errors and return `false`;
- handle a field missing from the form (`getAttribute` can return `null`), a create (`getFormType() === 1`), and strip
  the braces from ids for `Xrm.WebApi`.

Deployment, **before** the ribbon, because the check verifies the functions exist:

```
Publish-DataverseWebResource.ps1 -FilePath <t>.ribbon.js -Name <prefix>_/js/<t>.ribbon.js -Publish -Verify -IssueKey <KEY>
```

Test the logic with a mocked `Xrm` (nominal and negative cases) when the repository has no test tooling.

## 3. Define the buttons

| Type | Element | Location |
|---|---|---|
| Form | `Button` | `Mscrm.Form.<t>.MainTab.Actions.Controls._children` |
| View | `Button` | `Mscrm.HomepageGrid.<t>.MainTab.Actions.Controls._children` |
| Subgrid | `Button` | `Mscrm.SubGrid.<t>.MainTab.Actions.Controls._children` |
| Flyout | `FlyoutAnchor` > `Menu` > `MenuSection` > `Controls` > `Button` | same |

For each button: a `CustomAction`, a `CommandDefinition`, its `EnableRule`s, and `LocLabel`s in each installed language.
A `FlyoutAnchor` needs a command, even without an action. Icon: `ModernImage="$webresource:..."`.

Id convention: `<prefix>.<table>.<Form|Home|SubGrid>.<Name>.<CustomAction|Button|Command>`,
`<prefix>.<table>.EnableRule.<Name>`.

## 4. Apply

```
Import-DataverseRibbon.ps1 -Table <t> -RibbonDiffXmlPath <t>.ribbondiff.xml -IssueKey <KEY> -DryRun
```

The script refuses the file if an id lacks the prefix or is duplicated, if a location does not exist, if a command,
rule, label or web resource is missing, or if a function is missing from the JS. Without `-DryRun`, it exports the
solution, replaces the `RibbonDiffXml`, re-imports, publishes and checks the buttons in the published ribbon.

## 5. Check

- On an existing record and on create: enabled or disabled state of each button, and after changing a field tracked by
  a rule.
- In the view: no selection, one row, several rows.
- The subgrid only shows the button on a form that contains a subgrid of this table.
- The API proves the buttons exist, not how they render: add a Playwright scenario for the button's state.
- The browser cache can keep the old ribbon: reload the page (Ctrl+F5).
