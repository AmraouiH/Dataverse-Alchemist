---
name: dataverse-solution-sync
description: Exports the unmanaged Dataverse solution from the dev environment and unpacks it into the repository source folder (pac solution unpack) to commit the created components (columns, forms, web resources, steps) on the branch. Use after Dataverse changes when the solution is under source control.
---

# Syncing the solution into the repository

This skill applies when `dataverse.solution.sourceControlled` is `true`. The synced solution is **the ticket's**. Its
source folder is set by `dataverse.solution.unpackedFolders.<solution>`, or otherwise by
`dataverse.solution.unpackedFolderPattern` (`{solution}`). The export changes nothing in the CRM, but the write to the
repository is presented before committing.

## Steps

1. Check that all customizations are published (`Publish-DataverseCustomizations.ps1 -Tables ...`).
2. Export and unpack:
   ```
   pwsh -NoProfile -File ".claude/dataverse-alchemist/scripts/Export-DataverseSolution.ps1" -Unpack -IssueKey <KEY>
   ```
   The export goes through the Web API (read-only). The unpack uses `pac solution unpack`, which needs no
   authentication, or `dataverse.solution.unpackCommand` if the repository has its own command (placeholders `{zip}` and
   `{folder}`).
3. Analyze `git status` / `git diff --stat` on the ticket solution's source folder:
   - **expected**: the ticket's components (attributes in `Entities/<table>/Entity.xml`, `FormXml`, `WebResources/`,
     `PluginAssemblies/`, `SdkMessageProcessingSteps/`, `Other/Solution.xml`);
   - **unexpected**: changes to other components, made by other developers on the shared environment.
4. Present both lists. **Commit only what belongs to the ticket**, with `git add -p` or file by file. For foreign
   changes, ask the user (ignore with `git checkout -- <file>`, or include).
5. Binaries (plugin DLL, compiled web resources) are often mapped to build outputs in the repository (mapping file,
   `.cdsproj`): follow the existing convention and do not commit binaries if the repository does not.
6. Commit: `<KEY>: sync solution <uniqueName>`.

## Caution

- The version number in `Solution.xml` may change: keep the repository convention (increment per ticket or per release).
- On a future merge conflict on `Solution.xml` or `Customizations.xml`, resolve component by component. Never take a
  whole file as "ours" or "theirs".
