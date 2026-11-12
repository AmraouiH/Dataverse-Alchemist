---
name: dataverse-plugin
description: Develops or changes a Dynamics 365 / Dataverse C# plugin (IPlugin) with its unit tests, then deploys it (assembly, types, steps, images) into the solution. Use for any server-side business rule - calculation, blocking validation, sync between tables on create, update or delete.
---

# Dataverse plugin development

## 0. Prerequisites: consistency and scope

- `conventions.md` (skill `dataverse-conventions`) is the reference: base class, naming of classes, methods, variables
  and constants, field access (early-bound / constants / strings), error handling, tracing, language of messages and
  comments, test structure and naming. **Model your code on the closest existing plugin** (same table or same kind of
  rule).
- New components (assembly, steps) go into the ticket's solution (`-IssueKey`).
- Only the requested rule: do not change neighboring logic and do not "clean up" the surrounding code.

## 1. Design (included in the plan)

For each plugin, decide and write in the plan:

| Item | Decision |
|---|---|
| Class | new or existing (prefer extending the plugin already registered on the same table/message if that is the repository convention) |
| Message | Create / Update / Delete / Assign / SetState / Associate / custom message… |
| Table | logical name |
| Stage | `PreValidation` (check before the transaction), `PreOperation` (change the Target, same transaction), `PostOperation` (actions on other records) |
| Mode | `Sync` by default. `Async` only if the user does not need the result immediately (PostOperation only) |
| Filtering attributes | **mandatory on Update**: only the columns that trigger the rule |
| Images | PreImage / PostImage with the **minimal list** of columns needed |
| Recursion | `context.Depth` guard and/or before/after comparison, especially if the plugin updates its own table |
| Errors | `InvalidPluginExecutionException` with an understandable business message (in the language of the CRM users) |

Golden rules:
- In PreOperation, change `Target` instead of doing an `Update` on the record.
- Never `Retrieve` the current record when an image is enough.
- No state in class fields (plugins are cached and shared across threads).
- No outgoing HTTP call or `Thread.Sleep` in a synchronous plugin. 2-minute limit.
- Use `ITracingService` at key steps (without personal data).
- Use `IOrganizationServiceFactory.CreateOrganizationService(context.UserId)`, unless privilege elevation is explicitly
  needed (to justify in the plan).

## 2. Implementation

Follow `conventions.md` and the conventions reported by `repo-analyst` **exactly**: base class, folders, naming,
early-bound or late-bound, constants, style. Skeleton, **only** if the repository has no plugin to draw from:

```csharp
public class AccountPreUpdateSegment : IPlugin
{
    public void Execute(IServiceProvider serviceProvider)
    {
        var context = (IPluginExecutionContext)serviceProvider.GetService(typeof(IPluginExecutionContext));
        var tracing = (ITracingService)serviceProvider.GetService(typeof(ITracingService));
        var factory = (IOrganizationServiceFactory)serviceProvider.GetService(typeof(IOrganizationServiceFactory));
        var service = factory.CreateOrganizationService(context.UserId);

        if (context.Depth > 1) return;
        if (!(context.InputParameters.TryGetValue("Target", out var t) && t is Entity target)) return;
        var preImage = context.PreEntityImages.TryGetValue("PreImage", out var img) ? img : null;
        // ...
    }
}
```

Isolate the business logic in testable methods or classes, without depending on `IServiceProvider` when the repository
already does so.

Assembly version: increment `build` or `revision` if that is the convention. **Never change `major.minor`** without
approval, as it breaks the update.

## 3. Unit tests (mandatory)

- Use the framework already in place (`testing`/`repo-analyst`): FakeXrmEasy (v1 MIT; v2/v3 licensed, do not change
  version), XrmMockup, Moq…
- If there is no test project: propose one in the plan (framework, location) and wait for approval.
- Cover at least: nominal case, each business branch of the ticket, filters (unrelated field, nothing happens), error
  cases (expected exception and message), recursion guard.
- Run `Invoke-AlchemistUnitTests.ps1 -IssueKey <KEY> -Kind dotnet` (the report reads its result). **Everything must be
  green before deployment.**

## 4. Build and deployment

1. `dotnet build <code.plugins.projectPath> -c <buildConfiguration>`, then check that `code.plugins.outputDll` exists and
   is signed.
2. If `code.plugins.deploymentMode` is `package` (NuGet plugin package): use `pac plugin push` (pac auth required).
   Otherwise:
   ```
   Update-DataversePluginAssembly.ps1 -DllPath <dll> -PluginTypes <Ns.Class1>,<Ns.Class2> -IssueKey <KEY> -DryRun
   Register-DataversePluginStep.ps1 -PluginTypeName <Ns.Class> -Message Update -Table <t> -Stage PreOperation `
       -FilteringAttributes <c1>,<c2> -PreImageAttributes <c1> -IssueKey <KEY> -DryRun
   ```
3. Present the table of actions (assembly and version, types created, steps: message, table, stage, mode, filters,
   images) in **approval #2**, then run without `-DryRun`.
4. `Register-DataversePluginStep.ps1` updates an identical existing step (same type, message, table and stage) instead of
   creating a duplicate.

## 5. End-to-end tests

See the `dataverse-testing` skill: create or update a test record that triggers the step, check the expected result (or
the exception), read `plugintracelogs` on failure, then clean up. If the user sees the plugin's effect on a form (error
on save, calculated value), add a Playwright scenario.

## 6. Docs

For each plugin, document the trigger (message, table, stage, filters), the business rule, the images and the possible
errors (skill `feature-documentation`). If the repository has a step registry (spkl file, README, attributes), update it.

## New plugin project

A plugin requested by the ticket is registered by the agent, with `Update-DataversePluginAssembly.ps1` then
`Register-DataversePluginStep.ps1`, even without a `code.plugins` section in the config: these scripts create the
assembly and the steps. Never propose a manual registration. Before committing: `bin/` and `obj/` in `.gitignore`.

Dataverse requires a signed assembly. Create the key with `New-PluginStrongNameKey.ps1 -Path <project>/<name>.snk`,
without `sn.exe`, then declare it in the `.csproj` (`SignAssembly`, `AssemblyOriginatorKeyFile`). Whether the `.snk` is
committed follows the repository's practice (it is ignored by default in this agent's `.gitignore`).
