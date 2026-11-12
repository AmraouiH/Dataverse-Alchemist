# Installing and configuring Dataverse Alchemist

Dataverse Alchemist is a Claude Code agent that delivers Dynamics 365 / Dataverse tickets end to end. This guide
installs it in your CRM project repository and configures it in about fifteen minutes.

## 1. Prerequisites

| Tool | Why | Required |
|---|---|---|
| [Claude Code](https://claude.com/claude-code) | runs the agent (`/alchemist-*` commands) | yes |
| PowerShell 7+ (`pwsh`) | all agent scripts | yes |
| git | branches, commits | yes |
| Azure CLI (`az`) | Dataverse sign-in with your own account (simplest mode) | recommended |
| .NET SDK | build and test C# plugins | for plugins |
| Node.js 18+ | web resource tests and Playwright browser tests | for JS scripts or UI tests |
| Power Platform CLI (`pac`) | solution unpacking (`dataverse.solution.sourceControlled`) | optional |
| Microsoft Edge or Chrome | browser tests | for UI tests |

## 2. Install the agent in your project

```bash
cd D:\Repos\MyCRM
npx dataverse-alchemist init --dry-run   # preview
npx dataverse-alchemist init
```

The installer copies the agent into `.claude/` and updates `.gitignore`. If there is no config yet, it creates
`.alchemist/alchemist.config.json` from the minimal template; an existing config is never touched. To update the agent,
run `npx dataverse-alchemist@latest init` again: files removed from the agent are cleaned up, your config and your own
files are kept. `npx dataverse-alchemist version` shows the installed version.

Without npm, from a clone of this repository: `pwsh ./Install-DataverseAlchemist.ps1 -Target D:\Repos\MyCRM`.
## 3. Configure

Your configuration lives in **a single file**, `.alchemist/alchemist.config.json`, committed with the project. Secrets
are never written to it in plain text. They are read in one of two ways:
- from an environment variable, with an `env:VARIABLE_NAME` reference in the config;
- from `.alchemist/alchemist.config.local.json`, a git-ignored file the agent merges at load time.

Three ways to fill in the config, pick one:

1. **Config page** (easiest): `pwsh .claude/dataverse-alchemist/config-ui/Start-AlchemistConfigUi.ps1` opens
   `http://localhost:4874`. It has Permissions, Dataverse, Tickets and Git tabs. The "Test connections" button checks
   the config.
2. **`/alchemist-init`** in Claude Code: the agent detects what it can from the repository (branches, remote, plugin
   projects, web resources, solutions) and only asks the remaining questions.
3. **By hand**, starting from [`alchemist.config.minimal.json`](.claude/dataverse-alchemist/config/alchemist.config.minimal.json).
   Any missing option takes its default value.

The minimal config is enough to get started:

```json
{
  "project": { "name": "My CRM", "language": "en" },
  "dataverse": {
    "defaultEnvironment": "dev",
    "solution": { "default": "MySolution" },
    "environments": {
      "dev": { "url": "https://myorg-dev.crm4.dynamics.com", "allowWrite": true, "auth": { "type": "azcli" } }
    }
  },
  "jira": { "provider": "local", "localTicketsFile": ".alchemist/tickets.json" },
  "git": { "defaultBaseBranch": "main" }
}
```

Everything else is set section by section. Each guide stands on its own:

| Guide | Contents |
|---|---|
| [docs/setup/01-dataverse.md](docs/setup/01-dataverse.md) | environments, authentication (current user, application, token), solution, write access |
| [docs/setup/02-tickets.md](docs/setup/02-tickets.md) | Jira Cloud / Server, or a local ticket file |
| [docs/setup/03-git-devops.md](docs/setup/03-git-devops.md) | branches, commits, push, Azure DevOps or GitHub pull requests |
| [docs/setup/04-permissions.md](docs/setup/04-permissions.md) | what the agent is allowed to do (`allow` section) and the safeguards |
| [docs/setup/05-tests.md](docs/setup/05-tests.md) | unit tests, end-to-end tests, Playwright browser tests |
| [docs/setup/06-code-and-docs.md](docs/setup/06-code-and-docs.md) | plugin and web resource projects, documentation, report |
| [docs/setup/reference.md](docs/setup/reference.md) | every config key with its default value |

## 4. Check

```
/alchemist-check
```

It checks the config, secrets, tools, git repository, Dataverse connection, tickets, Playwright and allowed
capabilities. Everything should be `OK`; a `WARN` points to an optional feature.

## First run in Claude Code

- Open Claude Code **at the root of the CRM project**: the commands and skills are read from `.claude/` there.
- The agent runs its PowerShell scripts through Claude Code. The first time, Claude Code asks permission for each
  command; allow the `.claude/dataverse-alchemist/scripts` commands for the project to avoid repeated prompts. Writes to
  Dataverse still go through the agent's own approval step.
- The installer created `.alchemist/tickets.json` with example tickets. Replace them with yours, or switch to Jira
  ([docs/setup/02-tickets.md](docs/setup/02-tickets.md)).
## 5. Use

| Command | Purpose |
|---|---|
| `/alchemist-ticket CRM-123` | delivers a ticket: analysis, approved plan, branch, development, tests, docs, report |
| `/alchemist-ticket CRM-123 --resume` | resumes an interrupted ticket |
| `/alchemist-rollback CRM-123` | undoes in Dataverse what the ticket did, after you approve the plan |
| `/alchemist-learn` | shows what the agent has learned about you and the project, lets you forget a lesson |
| `/alchemist-check` | checks the config and connections |

The agent never writes to Dataverse, pushes, opens a pull request or posts a Jira comment without your explicit
approval.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `No config found` | the command runs outside the project | open Claude Code at the root of the CRM project, or set `ALCHEMIST_CONFIG` |
| `401` from Dataverse in `azcli` mode | Azure CLI session expired or wrong tenant | `az login --tenant <id>` |
| `Environment variables: not set` | an `env:` reference has no value | set the variable (`setx NAME "value"`) and reopen the terminal |
| Browser tests ask to sign in every time | session expired (8 h by default) | sign in in the window; adjust `testing.ui.sessionHours` |
| `Environment is read-only` | `allowWrite` is `false` | intended for UAT and production; use the dev environment |
