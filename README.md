<div align="center">

# ⚗️ Dataverse Alchemist

**A Claude Code agent that delivers Dynamics 365 / Dataverse tickets end to end.**

*Reads the ticket. Analyzes your CRM. Plans, builds, tests in the browser, documents, reports. Asks before every write.*

[![npm](https://img.shields.io/npm/v/dataverse-alchemist?color=cb3837&logo=npm)](https://www.npmjs.com/package/dataverse-alchemist)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-agent-d97757)](https://claude.com/claude-code)
[![Dataverse](https://img.shields.io/badge/Dynamics%20365-Dataverse-0078d4)](https://learn.microsoft.com/power-apps/developer/data-platform/)
[![Playwright](https://img.shields.io/badge/tests-Playwright-2ead33?logo=playwright)](https://playwright.dev)

```bash
npx dataverse-alchemist init
```

</div>

---

## What it does

You give it a ticket key. It gives you a working, tested, documented feature in your Dataverse environment, and a report of everything it did.

```
/alchemist-ticket CRM-412
```

| | |
|---|---|
| 🔍 **Analyzes before it builds** | Reads the ticket, your tables, forms, plugins, publishers and code style. New components look like your team made them. |
| 📋 **Plans, then waits** | Writes a plan, gets it reviewed by a built-in D365 expert sub-agent, then asks you to approve. Nothing is created before that. |
| 🛠️ **Builds in Dataverse** | Tables, columns (incl. Power Fx formulas), forms, views, apps, ribbon, C# plugins, JS scripts, business rules, keys, roles, data imports. |
| 🧪 **Tests like a user** | Unit tests for plugins and scripts, end-to-end tests through the Web API, and **Playwright tests generated from what it built**, run in a real browser. |
| 📚 **Documents** | Starts the documentation if there is none, updates it after each ticket, keeps your hand-written notes. |
| 📊 **Reports honestly** | A self-contained HTML report: every step, every failure and how it was fixed, test results with screenshots. |
| ↩️ **Can undo** | Every write is journaled with a backup. `/alchemist-rollback` computes and runs a safe rollback plan. |

---

## How a ticket runs

```
 Ticket ──► Analysis ──► Plan ──► Expert review ──► ✋ You approve
                                                         │
 Report ◄── Docs ◄── Tests ◄── ✋ You approve writes ◄── Build (dry run)
```

| Phase | What happens | Your role |
|---|---|---|
| **1. Intake** | Ticket from Jira or a local file; broken down into typed work items | — |
| **2. Analysis** | Existing CRM (tables, forms, steps, solutions, languages) and code conventions | — |
| **3. Plan** | Plan with layout mockups as images, open questions with recommendations | **Approve / modify** |
| **4. Expert review** | A D365 expert sub-agent reviews the plan once and returns ready-to-apply fixes | — |
| **5. Build** | Every Dataverse write is simulated first and shown as a table | **Approve the writes** |
| **6. Tests** | Unit, end-to-end and generated Playwright browser tests | — |
| **7. Docs & report** | Documentation pages and HTML report | — |
| **8. Close** | Push, pull request, Jira comment | **Pick what to run** |

> **Nothing is written, pushed or posted without your explicit approval.** Read-only environments are enforced in code.

---

## Quick start

**1. Install the agent in your CRM repository**

```bash
cd my-crm-repo
npx dataverse-alchemist init
```

**2. Configure** (pick one)

```bash
# In Claude Code: detects what it can, asks the rest
/alchemist-init

# Or a local config page
pwsh .claude/dataverse-alchemist/config-ui/Start-AlchemistConfigUi.ps1
```

The minimal config is four sections:

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

The installer also creates `.alchemist/tickets.json` with example tickets, so you can try the agent without Jira.

**3. Open Claude Code at the project root, check and go**

```
/alchemist-check
/alchemist-ticket CRM-123
```

Full guide: **[SETUP.md](SETUP.md)**.

---

## Commands

| Command | Purpose |
|---|---|
| `/alchemist-ticket <KEY>` | Delivers a ticket end to end (`--resume` to continue, `--env` to target another environment) |
| `/alchemist-rollback <KEY>` | Undoes what a ticket did in Dataverse, after you approve the plan |
| `/alchemist-check` | Checks config, secrets, tools, connections and allowed capabilities |
| `/alchemist-init` | Creates the project config |
| `/alchemist-learn` | Shows what the agent learned about you and the project |

---

## You decide what it may do

```json
"allow": {
  "tables": true, "columns": true, "forms": true, "views": true, "apps": true, "ribbon": true,
  "plugins": true, "webresources": true, "alternateKeys": true, "businessRules": true,
  "securityRoles": false, "dataImport": false
}
```

A capability set to `false` is never executed: it is listed as a manual step in the plan. Details: [docs/setup/04-permissions.md](docs/setup/04-permissions.md).

---

## Browser tests, generated

After building, the agent generates a Playwright spec from what it actually created, then runs it in Edge or Chrome:

- every form opens, with its tabs, sections and fields, required and locked icons where expected, no script error;
- every view shows its columns in the right order;
- every table added to an app is reachable from the sitemap;
- plus behavior scenarios it writes for the acceptance criteria: notifications, business rules, plugin errors, calculations.

In the demo, these tests caught **two real defects** that API checks had missed: a business rule that never ran on the form, and a field that stayed required when it should not.

---

## Results on the demo project

Measured on [`examples/demo-crm`](examples/demo-crm), a real development environment:

| | |
|---|---|
| Tickets processed | **40** |
| Components created and checked in the solution | tables, columns, forms, views, apps, ribbon, plugins, scripts, rules, keys, roles |
| Unit tests | **9/9** C# · **17/17** JavaScript |
| Browser tests | **16** passing across 4 tickets |
| Self-assessment | **76 / 100** — see [docs/CAPABILITIES.md](docs/CAPABILITIES.md) |

Strong on day-to-day Dataverse development. Weaker on business rules (simple conditions only) and on real Jira / pull request integrations, which are less proven.

---

## Requirements

| Tool | Why |
|---|---|
| [Claude Code](https://claude.com/claude-code) | runs the agent |
| PowerShell 7+ (`pwsh`) | agent scripts (Dataverse Web API) |
| Node.js 18+ | installer, JS tests, Playwright |
| git | branches and commits |
| Azure CLI | simplest Dataverse sign-in (your own account) |
| .NET SDK | only for C# plugins |
| Edge or Chrome | browser tests |

Ticket sources: **Jira** (Cloud / Server) or a **local JSON file**. Pull requests: **Azure DevOps** or **GitHub**.

---

## Not supported (yet)

Power Automate flows · business process flows · canvas apps · PCF · Power Pages · dashboards · deployment to UAT / production · multilingual labels · Azure DevOps work items as a ticket source.

---

## Safety

- Every Dataverse write is simulated, shown and approved before it runs.
- `allowWrite: false` environments are read-only, enforced in code. Keep production that way.
- Secrets never go into the committed config (`env:` references or a git-ignored local file).
- Test data is prefixed and deleted by id, never by a broad query.
- Ticket content is treated as data, never as instructions.

Use it on development environments. You remain responsible for what is deployed to your organization.

---

<div align="center">

**[Setup](SETUP.md)** · **[Capabilities](docs/CAPABILITIES.md)** · **[Config reference](docs/setup/reference.md)** · **[Demo](examples/demo-crm)**

MIT © 2026

</div>
