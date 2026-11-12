---
description: Initializes the Dataverse Alchemist config (.alchemist/alchemist.config.json) in the current CRM repository
---

# Dataverse Alchemist initialization

Goal: create `.alchemist/alchemist.config.json` at the root of the current git repository. Start from the **minimal**
template `.claude/dataverse-alchemist/config/alchemist.config.minimal.json` and only add the sections the project needs;
the full example `alchemist.config.example.json` shows every option (schema: `alchemist.config.schema.json`, guide:
`SETUP.md` in the agent repository). A missing option takes its default value: do not copy defaults.

1. Check that you are at the root of a git repository. If `.alchemist/alchemist.config.json` already exists, offer to
   complete it rather than overwrite it.
2. **Detect as much as possible from the repository** before asking questions:
   - branches (`git branch -a`) for `git.defaultBaseBranch` and the rules (`release/*`, `main`, `develop`…);
   - remote (`git remote -v`) for `devops.provider`, the organization, project and repository (Azure DevOps or GitHub);
   - plugin projects (`*.csproj` referencing `Microsoft.CrmSdk.CoreAssemblies` or `Microsoft.PowerPlatform.Dataverse.Client`),
     test projects and framework (FakeXrmEasy, XrmMockup…), target framework, DLL path;
   - web resources (`package.json`, `tsconfig.json`, `@types/xrm`), npm build, test and lint scripts;
   - unpacked solutions (`Other/Solution.xml`, `*.cdsproj`): unique name of each solution and its folder
     (`dataverse.solution.unpackedFolders`);
   - documentation folder (`docs/`, `wiki/`, `*.md`).
3. Then ask, with `AskUserQuestion`, only the remaining questions: Jira URL and auth type, dev environment URL and
   Dataverse auth mode, Jira acceptance criteria field, default solution to offer (only a suggestion: the solution is
   asked for each ticket, and the publisher is always that of the chosen solution), documentation provider and link,
   capabilities to allow (`allow` section: by default everything except `securityRoles` and `dataImport`). The user can
   also set everything with the config page: `pwsh .claude/dataverse-alchemist/config-ui/Start-AlchemistConfigUi.ps1`.
   Without Jira: set `jira.provider` to `local` and copy `.claude/dataverse-alchemist/config/tickets.example.json` to
   `.alchemist/tickets.json`. Tickets are then read from that file.
4. Write the config. **No plain-text secret**: use `env:VARIABLE_NAME` and list the variables to set (e.g.
   `setx JIRA_API_TOKEN "..."` on Windows, or a `.env` file loaded by the profile).
5. Add to the repository `.gitignore`: `.alchemist/runs/`, `.alchemist/*.local.json`, `.alchemist/playwright/` and
   `.claude/dataverse-alchemist/playwright/node_modules/`. Secrets entered in plain text go to
   `.alchemist/alchemist.config.local.json` (merged at load time, never committed).
6. Run `pwsh -NoProfile -File ".claude/dataverse-alchemist/scripts/Test-AlchemistConfig.ps1"` and comment on the result.
