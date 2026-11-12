# Dataverse connection

`dataverse` section of `.alchemist/alchemist.config.json`.

```json
"dataverse": {
  "defaultEnvironment": "dev",
  "baseLanguageCode": 1033,
  "solution": { "default": "MySolution", "sourceControlled": false },
  "environments": {
    "dev": { "url": "https://myorg-dev.crm4.dynamics.com", "allowWrite": true,  "auth": { "type": "azcli" } },
    "uat": { "url": "https://myorg-uat.crm4.dynamics.com", "allowWrite": false, "auth": { "type": "azcli" } }
  }
}
```

## Environments

Each environment has a free-form name (`dev`, `uat`…). `defaultEnvironment` is where the agent develops. To use
another one for a single ticket: `/alchemist-ticket CRM-123 --env uat`.

**`allowWrite`**: when `false`, the environment is read-only. The agent can analyze what exists but never creates or
changes anything there, and never runs end-to-end tests there. Keep it `false` for UAT and production: the check is
enforced in code, before every call.

## Authentication (`auth.type`)

| Type | When to use it | Configuration |
|---|---|---|
| `azcli` | developer workstation; the agent acts with **your** account and permissions | `az login` (add `--tenant <id>` if you have several tenants) |
| `clientSecret` | service account, continuous integration | `tenantId`, `clientId`, `clientSecret`: an Entra ID app registered as an application user in the environment, with a role (System Customizer at least) |
| `accessToken` | token obtained by another tool | `token` |

```json
"auth": {
  "type": "clientSecret",
  "tenantId": "env:DATAVERSE_TENANT_ID",
  "clientId": "env:DATAVERSE_CLIENT_ID",
  "clientSecret": "env:DATAVERSE_CLIENT_SECRET"
}
```

Never put a secret in plain text in the committed file. You have two options:
- an `env:NAME` reference, with the value set by `setx NAME "value"` on Windows;
- the value in `.alchemist/alchemist.config.local.json`, which the config page fills in automatically.

## Solution and publisher

- `solution.default` is only a suggestion. For each ticket the agent asks which solution to use. The publisher and
  prefix (for example `rhz_`) always come from the chosen solution: the agent never makes them up.
- `solution.sourceControlled: true`: after making changes, the agent exports the solution and unpacks it into the
  repository with `pac solution unpack`, into `unpackedFolders.<solution>` or `unpackedFolderPattern`.
- `baseLanguageCode` is the language of labels (1033 for English, 1036 for French). Without it, the organization base
  language is read.

## Check

`/alchemist-check` should show `OK  Dataverse <env>  Connected as …`.
