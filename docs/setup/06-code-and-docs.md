# Code, documentation and report

## Code (`code` section)

These paths help the agent find and build your code. `/alchemist-init` detects them.

```json
"code": {
  "plugins": {
    "solutionPath": "src/Plugins/Contoso.Plugins.sln",
    "projectPath": "src/Plugins/Contoso.Plugins/Contoso.Plugins.csproj",
    "testProjectPath": "src/Plugins/Contoso.Plugins.Tests/Contoso.Plugins.Tests.csproj",
    "buildConfiguration": "Release",
    "outputDll": "src/Plugins/Contoso.Plugins/bin/Release/net462/Contoso.Plugins.dll",
    "deploymentMode": "assembly"
  },
  "webresources": {
    "rootPath": "src/WebResources",
    "language": "typescript",
    "buildCommand": "npm run build",
    "distPath": "src/WebResources/dist",
    "namePattern": "{prefix}_/js/{table}.form.js",
    "namespace": "Contoso"
  }
}
```

Before writing code, the agent always analyzes what exists: naming, style, structure, test framework. It then writes
in that style. Without a plugin project, it creates one (.NET Framework 4.6.2, signed assembly) for the first plugin.

## Documentation (`docs` section)

```json
"docs": {
  "enabled": true,
  "provider": "local",
  "localPath": "docs",
  "featurePagePattern": "features/{key}.md",
  "tablePagePattern": "tables/{table}.md",
  "url": null,
  "wiki": { "name": "CRM.wiki", "rootPath": "/CRM" }
}
```

- At the start of a ticket, the agent looks for the existing documentation of the feature.
- **If there is no documentation**, it offers to start it. It then generates, from the real CRM, one page per table
  (columns, keys, forms, views, business rules, scripts, plugins), one page per ticket and an index.
- At the end of a ticket, it updates the affected pages. Hand-written text is kept: only the parts marked
  `alchemist:auto` are regenerated.
- `provider`: `local` (markdown files in the repository) or `azureDevOpsWiki` (wiki of the Azure DevOps project from the
  `devops` section).

## Report (`report` section)

At the end of a ticket, the agent produces `.alchemist/runs/<KEY>/report-<KEY>.html`. It is a self-contained file you
can attach to a ticket. It contains:
- every step, successful or failed, with the fix applied to each failure;
- the Dataverse components and whether they are in the solution;
- the unit tests, then the browser tests, with screenshots;
- the remaining manual actions.

The report is written in the language of your CRM user interface. The user is found by `report.crmUserEmail`,
otherwise by `jira.email`, otherwise it is the signed-in user.

## Working folder (`workflow` section)

`runsFolder` (default `.alchemist/runs`) holds one folder per ticket: plan, journal, backups, test results, report.
This folder is git-ignored.
