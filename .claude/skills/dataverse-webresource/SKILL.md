---
name: dataverse-webresource
description: Develops or changes a Dynamics 365 form JavaScript or TypeScript web resource (Xrm / formContext - visibility, dynamic requirement, onChange, notifications, lookup filters), with its tests, then deploys it, publishes it and wires it on the form. Use for any client-side behavior of a model-driven form.
---

# JS / TS web resources

For ribbon buttons, commands and enable rules, use the `dataverse-ribbon` skill: their JS lives in a web resource separate
from the form script.

## 0. Prerequisites: consistency and scope

- `conventions.md` (skill `dataverse-conventions`) is the reference: namespace or module, function shape (`function` or
  arrow, `async`), variable naming (`formContext`, field name constants), shared helpers to reuse, handler naming, web
  resource naming and path, language of messages and comments, test style. **Model your code on the existing script of
  the same form**, or otherwise the closest one.
- The web resource goes into the ticket's solution, and its name uses that solution publisher's prefix (`-IssueKey`).
- Only the requested behavior: do not rewrite or reformat the existing code of the file.

## 1. Design (included in the plan)

- Target file: existing form script or new file per the repository convention (one script per table or per form,
  namespace `code.webresources.namespace`).
- Web resource name: `code.webresources.namePattern` (e.g. `cts_/js/account.form.js`), with the publisher prefix.
- Handlers: which events (onLoad, onSave, onChange of which fields), which functions, wired on which form.
- If the rule must also be guaranteed server-side, flag it (complementary plugin).

## 2. Implementation

Follow the repository structure (modules, bundler, helpers). Mandatory **Client API** good practices:
- `executionContext.getFormContext()`, never `Xrm.Page` (deprecated).
- Handlers receive `executionContext` (`passExecutionContext="true"` in the FormXml).
- `formContext.getAttribute("x")` and `getControl("x")` can return `null` (field not on the form): guard against it.
- Server calls with `Xrm.WebApi` (`async`/`await`). No synchronous XMLHttpRequest, no jQuery, no DOM manipulation.
- Dynamic requirement: `attribute.setRequiredLevel("required" | "none")`. Visibility: `control.setVisible()`. Messages:
  `formContext.ui.setFormNotification` / `control.setNotification`.
- Blocking onSave: `executionContext.getEventArgs().preventDefault()` with a clear message.
- Call the onChange handlers from onLoad if the initial state depends on them.
- TypeScript: use `@types/xrm` and strict types. No unjustified `any`.

TS example, **only** if the repository has no script to draw from:

```ts
namespace Contoso.Account.Form {
  export function onLoad(executionContext: Xrm.Events.EventContext): void {
    onSegmentChange(executionContext);
  }

  export function onSegmentChange(executionContext: Xrm.Events.EventContext): void {
    const formContext = executionContext.getFormContext();
    const segment = formContext.getAttribute<Xrm.Attributes.OptionSetAttribute>("cts_segment")?.getValue();
    formContext.getControl<Xrm.Controls.StandardControl>("cts_customercode")?.setVisible(segment === 100000002);
  }
}
```

## 3. Build and tests

1. `installCommand` if needed, then `lintCommand` and `buildCommand` (`code.webresources.*`), from `rootPath`.
2. Unit tests (`Invoke-AlchemistUnitTests.ps1 -IssueKey <KEY> -Kind node`, or the repository's jest + xrm-mock setup if
   already in place). Cover each rule (values of the triggering field, field missing from the form). If there is no test
   tooling, propose adding it in the plan and wait for approval.
3. The file to deploy is the **build** (`distPath`), never the `.ts` source.

## 4. Deployment

```
# Changing an existing web resource: start from its real content in the CRM
Get-DataverseWebResource.ps1 -Name <cts_/js/...> -IssueKey <KEY>
Publish-DataverseWebResource.ps1 -FilePath <dist/file.js> -Name <cts_/js/...> -DisplayName "<label>" -Publish -Verify -IssueKey <KEY> -DryRun
```

Approval #2 (name, create or update, size, solution), then run without `-DryRun`. `-Verify` reads back the published
content and compares it with the local file.

New library or new handlers: continue with the `dataverse-form-field` skill (`-Operation AddHandler`) **after** the web
resource is deployed.

## 5. End-to-end tests

- Always: published content identical to the build (`-Verify`), library and handlers present in the published FormXml.
- UI: if `testing.ui.enabled` (default), write the Playwright scenario of each handler in the custom section of the
  ticket's spec (skill `dataverse-testing`), derived from the acceptance criteria. Otherwise, write a short and precise
  **manual test checklist** in the report (steps, expected result).

## 6. Docs

Document the behavior (triggering field, rule, visible effect) in the feature page.
