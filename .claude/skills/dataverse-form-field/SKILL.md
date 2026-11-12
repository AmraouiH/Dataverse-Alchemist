---
name: dataverse-form-field
description: Creates a Dynamics 365 form, or adds tabs, sections and fields to it (FormXml), and registers JS libraries and event handlers (onLoad, onSave, onChange) on a form. Use when a ticket asks to show a field or wire a script on a form.
---

# Form fields and events (FormXml)

## 0. Prerequisites

- The ticket's solution is chosen: `Import-DataverseForm.ps1 -IssueKey` adds the table (root component only) then the
  form to that solution.
- Existing conventions apply (`conventions.md` and the form itself): placement (section close to fields of the same
  nature), labels and languages present, number of columns, label visibility.
- Change **only** what the ticket asks: no moving, renaming or cleaning of other form elements.

## Mockup (required if the ticket gives no order and no mockup)

A ticket can impose the layout (attached mockup, field order, "below field X"): apply it as is. **Otherwise, do not
choose alone** as soon as you need to create a form, or add several fields, a tab or a section:

1. Prepare 2 or 3 `layout-<option>.json` files, one of them recommended. Principles:
   - **header** (4 fields max): status and owner, to see where the record stands without scrolling;
   - **natural reading order**: identification, then related people, then detail, then planning and amounts;
   - **required fields** at the top, **generated fields** read-only (`readonlyFields`);
   - **fields filled at end of life** (resolution, closing) in a separate tab;
   - **timeline** visible if the table has notes or activities;
   - on an existing form, keep its logic: tabs, naming, placement of neighboring fields (`conventions.md`).
2. Generate the **image** of each option. The script also checks the fields and reports those not placed:
   ```
   New-DataverseFormMockup.ps1 -Table <t> -LayoutFile layout-A.json -OutFile mockup-A.png -Title "Option A"
   ```
3. Look at each image to check it is not cut off, then **send the images** to the user (`SendUserFile`). A text diagram
   does not replace the image.
4. Ask which option to apply (`AskUserQuestion`), stating your recommendation and why.
5. Apply **only after approval**, with the file of the chosen option: what was approved is exactly what is applied. For
   a change to the option, regenerate the image and ask for approval again.
6. Then compare the published form to the layout: tabs, widths, order, header, timeline, read-only.

| Need | Script |
|---|---|
| Image mockup | `New-DataverseFormMockup.ps1 -Table <t> -LayoutFile layout.json -OutFile mockup.png` |
| New main or quick create form | `New-DataverseForm.ps1 -Table <t> -Name <name> -LayoutFile layout.json [-FormType QuickCreate] -IssueKey <KEY> -DryRun` |
| Rebuild an existing form (keeps its id, events and libraries) | `New-DataverseForm.ps1 ... -Name <existing name> -ReplaceExisting` |
| Add a tab | `Edit-DataverseFormXml.ps1 -FormXmlPath <f> -Table <t> -Operation AddTab -TabName <n> -TabLabel <l>` |
| Add a section | `Edit-DataverseFormXml.ps1 ... -Operation AddSection -TabName <n> -SectionName <n> -SectionLabel <l> -SectionColumns 2 -Fields a,b` |
| Add fields | `Edit-DataverseFormXml.ps1 ... -Operation AddField -Fields a,b -AfterField x` or `-SectionName <n>` |
| Wire a JS handler | `Edit-DataverseFormXml.ps1 ... -Operation AddHandler -Library <prefix>_/js/<file>.js -FunctionName <Ns.fn> -Event onload\|onsave\|onchange [-Fields a,b]` |

Use these scripts rather than hand editing: they generate the GUIDs, the labels in every language of the column and the
right control, declare a library only once, and refuse duplicates (fields, handlers) and columns not valid on a form.
`Edit-DataverseFormXml.ps1` only works on the exported file: chain it with `Import-DataverseForm.ps1`.

`layout.json`:

```json
{
  "header": ["statuscode", "ownerid"],
  "readonlyFields": ["accountnumber"],
  "tabs": [ { "name": "tab_general", "label": "General", "columns": [
    { "width": "33%", "sections": [ { "name": "sec_main", "label": "Main", "columns": 1, "fields": ["name", "accountnumber"] } ] },
    { "width": "67%", "sections": [ { "name": "sec_timeline", "label": "Timeline", "showLabel": false, "timeline": true } ] }
  ] } ]
}
```

A single-column tab can give `sections` directly. A table always gets an "Information" main form: replace it with
`-ReplaceExisting` rather than adding a second one. The same field can be both in the header and in the body
(`header_<field>` control).

An app does not automatically see a form created after it: add it with `AddAppComponents`
(`Microsoft.Dynamics.CRM.systemform`, `formid`), then publish the app.

## 1. Identify the form

`Export-DataverseForm.ps1 -Table <t>` lists the main forms (`-FormType QuickCreate|QuickView|Card` for the others). If
several active forms are candidates and the ticket does not say which one, ask in the plan.

## 2. Export

```
pwsh -NoProfile -File ".claude/dataverse-alchemist/scripts/Export-DataverseForm.ps1" -Table <t> -FormName "<name>" -IssueKey <KEY>
```

The script produces `<table>.<form>.xml` (indented working copy) and `<table>.<form>.orig.xml` (untouched reference).

## 3. Edit the working copy (only when no script operation fits)

Structure: `form > tabs > tab > columns > column > sections > section > rows > row > cell > control`.

Adding a field to a section (find the tab and section by their `name` or label):

```xml
<row>
  <cell id="{NEW-GUID}" showlabel="true" locklevel="0">
    <labels>
      <label description="Segment" languagecode="1033" />
    </labels>
    <control id="cts_segment" classid="{3EF39988-22BB-4f0b-BBBE-64B5A3748AEE}" datafieldname="cts_segment" disabled="false" />
  </cell>
</row>
```

Rules:
- `cell/@id`: a **new GUID** for each cell, in braces (`[guid]::NewGuid()`).
- `control/@id` = `datafieldname` = logical name of the column. The same field can appear twice, but the second control
  needs a distinct id (e.g. `cts_segment1`).
- `classid`: **copy the one of an existing control of the same type** in this form when there is one. Otherwise:

| Type | classid |
|---|---|
| Text, phone (String) | `{4273EDBD-AC1D-40d3-9FB2-095C621B552D}` |
| Email | `{ADA2203E-B4CD-49be-9DDF-234642B43B52}` |
| URL | `{71716B6C-711E-476c-8AB8-5D11542BFB47}` |
| Long text (Memo) | `{E0DECE4B-6FC8-4a8f-A065-082708572369}` |
| Ticker | `{1E1FC551-F7A8-43AF-AC34-A8DC35C7B6D4}` |
| Whole number | `{C6D124CA-7EDA-4a60-AEA9-7FB8D318B68F}` |
| Duration | `{AA987274-CE4E-4271-A803-66164311A958}` |
| Time zone | `{7C624A0B-F59E-493D-9583-638D34759266}` |
| Decimal | `{C3EFE0C3-0EC6-42be-8349-CBD9079DFD8E}` |
| Currency | `{533B9E00-756B-4312-95A0-DC888637AC78}` |
| Choice | `{3EF39988-22BB-4f0b-BBBE-64B5A3748AEE}` |
| Multi-select choice | `{4AA28AB7-9C13-4F57-A73D-AD894D048B5F}` |
| Boolean | `{67FAC785-CD58-4f9f-ABB3-4B7DDC6ED5ED}` |
| Date | `{5B773807-9FB2-42db-97C3-7A91EFF8ADFF}` |
| Lookup | `{270BD3DB-D9AF-4782-9025-509E298DEC0A}` |

- The cell label must repeat the column label in each language (same translations as the column), unless asked
  otherwise. Add one `<label>` per language present in the form or requested by the ticket.
- **"Below field X"**: the new `row` goes right after the `row` containing the control `datafieldname="x"`, in the same
  section. If X is not on the chosen form, or appears several times (for example in the header and in the body), ask
  which one.
- Respect the section's number of columns (`section/@columns`): a `row` contains as many `cell`s as columns, or one cell
  with `colspan`.
- Touch nothing else. No reformatting of other tabs.

### JS library and event handlers

Prefer `-Operation AddHandler`. By hand, these are direct children of `<form>` (create the nodes if they do not exist,
otherwise add entries to them):

```xml
<formLibraries>
  <Library name="cts_/js/account.form.js" libraryUniqueId="{NEW-GUID}" />
</formLibraries>
<events>
  <event name="onload" application="false" active="false">
    <Handlers>
      <Handler functionName="Contoso.Account.Form.onLoad" libraryName="cts_/js/account.form.js"
               handlerUniqueId="{NEW-GUID}" enabled="true" parameters="" passExecutionContext="true" />
    </Handlers>
  </event>
  <event name="onchange" application="false" active="false" attribute="cts_segment">
    <Handlers>
      <Handler functionName="Contoso.Account.Form.onSegmentChange" libraryName="cts_/js/account.form.js"
               handlerUniqueId="{NEW-GUID}" enabled="true" parameters="" passExecutionContext="true" />
    </Handlers>
  </event>
</events>
```

Possible events: `onload`, `onsave`, and `onchange` with `attribute="<logical name>"`. If the event already exists, add a
`Handler` to its `Handlers` rather than duplicating the `event`. The web resource must exist (deployed before the form
import).

## 4. Show the diff, approve, import

1. `git diff --no-index --stat` then the full diff between `.orig.xml` and `.xml`, to present in approval #2.
2. `Import-DataverseForm.ps1 -FormId <id> -FormXmlPath <file> -Table <t> -IssueKey <KEY> -DryRun`: checks duplicate ids.
   Without `-DryRun`, it also checks that each `datafieldname` exists.
3. After approval: same command without `-DryRun`, with `-Publish`.

## 5. Check

Re-export the form to another folder (`-OutFolder`) and check the control, the handlers and the publishing. Then the
Playwright test generated for the ticket checks the form in the browser (skill `dataverse-testing`). Add the result to
the test report.

## Quick create

`New-DataverseForm.ps1 -FormType QuickCreate` also turns on `IsQuickCreateEnabled` on the table: without this setting,
the form exists but never opens.
