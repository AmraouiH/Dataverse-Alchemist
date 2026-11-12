---
description: Checks the Dataverse Alchemist config and connections (Jira, Dataverse, DevOps, git, tools)
argument-hint: [--env <environment>] [--offline]
---

Run from the repository root:

`pwsh -NoProfile -File ".claude/dataverse-alchemist/scripts/Test-AlchemistConfig.ps1"`

- `--env <name>` in `$ARGUMENTS` becomes `-Environment <name>`;
- `--offline` becomes `-SkipNetwork`.

Present the result as a table. For each `KO` or `WARN`, give the concrete fix: config key to fill in, environment
variable to set, tool to install, permission to request (for example an Application User with a System Customizer role
on the dev environment for `clientSecret` auth).
