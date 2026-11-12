---
name: dataverse-business-rule
description: Creates and activates a simple Dynamics 365 business rule (all forms scope) in the ticket's solution - when a field equals (or does not equal) a value, fields become required, optional or hidden. Use when a ticket asks to make a field required or hide it depending on a value, without code.
---

# Business rules

## What the script can do

One condition `field = value` or `field <> value` (`-ConditionOperator Equal|NotEqual`; choice, text, boolean, whole
number) and, when it is true: make fields required (`-RequireFields`), optional (`-OptionalFields`) or hidden
(`-HideFields`).

**No ELSE branch**: the server refuses the generated Else branch (HTTP 500 "waitStep", CRM-410). An action is not undone
automatically when the condition becomes false again. When the ticket needs the reverse (field optional again), create
a **second rule** with the opposite condition: for example "required if status = Done" plus "optional if status <> Done"
(`-ConditionOperator NotEqual -OptionalFields`). Several conditions, default values, error messages: rule designer or
web resource (`dataverse-webresource`).

## Run

```
New-DataverseBusinessRule.ps1 -Table rhz_servicecontract -Name "End date required when active" `
    -ConditionField rhz_contractstatus -ConditionType OptionSetValue -ConditionValue 911240001 `
    -RequireFields rhz_enddate -IssueKey <KEY> -DryRun
```

- For a choice, `-ConditionValue` is the numeric value (read it from the choice metadata).
- The script builds the XAML, activates the rule and adds it to the solution. The server generates the client code.
- Step `DisplayName`s follow the `<Type>Step<n>` format: the server reads them back to build the rule; another format
  gives "Workflow contains unexpected step". Do not change this format.

## Triggers

A rule only runs on the form if activation generated its `processtriggers` (`load` and `change <field>`). This requires
`processtriggerscope = 1` (the script sets it and checks the triggers; it returns `active-without-trigger` otherwise). An
active rule without triggers does nothing: only a Playwright test shows it (CRM-413).

## Check

Read the rule back: `statecode = 1`, `clientdata` contains the tested value and `setRequiredLevel(...)` or
`setVisible(false)`, `triggers` lists `change <field>`. The effect on the form is checked with Playwright: use
`selectOption` (real drop-down), because a value set by script does not run business rules. The rollback deactivates
then deletes the rule.
