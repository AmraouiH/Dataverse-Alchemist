# Config reference

File: `.alchemist/alchemist.config.json`. Secrets go in `env:NAME` references, or in
`.alchemist/alchemist.config.local.json` (same structure, merged at load time, git-ignored).
JSON schema: [`alchemist.config.schema.json`](../../.claude/dataverse-alchemist/config/alchemist.config.schema.json).
Examples: [minimal](../../.claude/dataverse-alchemist/config/alchemist.config.minimal.json) and
[full](../../.claude/dataverse-alchemist/config/alchemist.config.example.json).

Only the `dataverse` section is required. In the table, "—" means "no default value": the option is optional, or only
required when the related feature is used.

| Key | Default | Purpose |
|---|---|---|
| `project.name` | — | display name |
| `project.language` | `en` | language of conversations, plans and docs |
| **`dataverse.defaultEnvironment`** | — (required) | development environment |
| **`dataverse.environments.<name>.url`** | — (required) | organization URL |
| `dataverse.environments.<name>.allowWrite` | `false` | `true` for dev only |
| `dataverse.environments.<name>.auth.type` | — | `azcli`, `clientSecret` (`tenantId`, `clientId`, `clientSecret`) or `accessToken` (`token`) |
| `dataverse.baseLanguageCode` | organization language | LCID of labels |
| `dataverse.solution.default` | — | solution offered first |
| `dataverse.solution.sourceControlled` | `false` | unpack the solution into the repository after changes |
| `dataverse.solution.unpackedFolders` / `unpackedFolderPattern` | — | source folder of each solution (`{solution}`) |
| `dataverse.solution.packageType` | `Unmanaged` | `Unmanaged`, `Managed` or `Both` |
| `jira.provider` | `jira` | `jira` or `local` |
| `jira.localTicketsFile` | `.alchemist/tickets.json` | local ticket file |
| `jira.baseUrl`, `authType`, `email`, `apiToken`, `apiVersion` | `apiVersion`: `2` | Jira connection |
| `jira.acceptanceCriteriaField`, `baseBranchField`, `extraFields`, `maxComments` | `maxComments`: 20 | fields read |
| `jira.postReportComment` | `ask` | end-of-ticket comment: `ask` or `never` |
| `git.remote` | `origin` | remote |
| `git.defaultBaseBranch` | `develop` | default base branch |
| `git.branchNamePattern` | `{type}/{key}-{slug}` | branch names |
| `git.typeMapping` | — | ticket type → branch prefix |
| `git.baseBranchRules` | `[]` | base branch rules (type, label, fix version) |
| `git.commitMessagePattern` | `{key}: {summary}` | commit message |
| `git.pushAfterCompletion` | `ask` | `ask` or `never` |
| `devops.provider` | `none` | `azureDevOps`, `github` or `none` |
| `devops.organizationUrl`, `project`, `repository`, `pat` | — | remote repository and token |
| `devops.createPullRequest`, `pullRequestAsDraft`, `defaultReviewerIds` | `ask`, `true`, `[]` | pull requests |
| `allow.<capability>` | `true`, except `securityRoles` and `dataImport` | see [04-permissions.md](04-permissions.md) |
| `code.plugins.*` | — | `solutionPath`, `projectPath`, `testProjectPath`, `buildConfiguration`, `outputDll`, `deploymentMode` (`assembly` or `package`), `testFramework` |
| `code.webresources.*` | — | `rootPath`, `language`, `installCommand`, `buildCommand`, `lintCommand`, `distPath`, `namePattern`, `namespace` |
| `testing.unit.required` | `false` | a code ticket without tests is flagged as a risk |
| `testing.e2e.enabled`, `environment` | `true`, `defaultEnvironment` | end-to-end tests through the Web API |
| `testing.e2e.recordPrefix` | `ALCHEMIST-E2E` | test data prefix |
| `testing.e2e.cleanup`, `checkPluginTraceLogs` | `true`, `true` | cleanup, trace log |
| `testing.ui.enabled` | `true` | Playwright browser tests |
| `testing.ui.specFolder` | `tests/ui` | folder of generated specs |
| `testing.ui.browser` | `msedge` | `msedge`, `chrome` or `chromium` |
| `testing.ui.sessionHours` | `8` | CRM session reuse |
| `docs.enabled`, `provider` | `false`, `local` | `local`, `azureDevOpsWiki` or `none` |
| `docs.localPath`, `featurePagePattern`, `tablePagePattern` | `docs`, `features/{key}.md`, `tables/{table}.md` | generated pages |
| `docs.url`, `wiki.name`, `wiki.rootPath`, `references` | — | links and wiki |
| `report.crmUserEmail` | `jira.email`, otherwise the signed-in user | report language and personal knowledge base |
| `workflow.runsFolder` | `.alchemist/runs` | ticket working folder |
| `workflow.autoCommit` | `true` | local commits on the ticket branch |

Useful environment variable: `ALCHEMIST_CONFIG`, to use a config stored somewhere other than `.alchemist/` at the
project root.
