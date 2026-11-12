# What the agent is allowed to do

## Capabilities (`allow` section)

Each capability is `true` or `false`. A capability set to `false` is never executed: the item is listed as "manual" in
the plan and in the report.

```json
"allow": {
  "tables": true,
  "columns": true,
  "forms": true,
  "views": true,
  "apps": true,
  "ribbon": true,
  "plugins": true,
  "webresources": true,
  "alternateKeys": true,
  "businessRules": true,
  "securityRoles": false,
  "dataImport": false
}
```

| Capability | What the agent does |
|---|---|
| `tables` | custom tables and global choices |
| `columns` | columns of every type (text, number, date, choice, multi-select choice, lookup, Power Fx formula), default value |
| `forms` | main and quick create forms, tabs, sections, fields, JS libraries and event handlers |
| `views` | public views: columns, widths, sort, filter |
| `apps` | model-driven apps, sitemap, adding tables, app roles |
| `ribbon` | command bar buttons (form, view, subgrid), commands and enable rules |
| `plugins` | C# plugins with unit tests, assembly deployment, steps and images |
| `webresources` | JS/TS form scripts with tests, deployment and publishing |
| `alternateKeys` | alternate keys (uniqueness), after checking existing duplicates |
| `businessRules` | simple business rules: when a field equals (or does not equal) a value, make fields required, optional or hidden |
| `securityRoles` | security roles and table privileges |
| `dataImport` | CSV import by upsert on an alternate key |

Without an `allow` section, everything is allowed **except** `securityRoles` and `dataImport`, which touch permissions
and data. The old `skills.enabled` key is still understood, but `allow` replaces it.

## Safeguards (not configurable)

- **Dataverse writes**: a simulation (`-DryRun`) is shown as a table, then executed only after your approval.
- **`allowWrite: false` environments**: refused in code, whatever is asked.
- **Push, pull request, Jira comment**: offered, never done without approval (`ask`). With `never`, they are not even offered.
- **Secrets**: never written to the committed file.
- **Journal**: every write is recorded in `.alchemist/runs/<KEY>/journal.jsonl`, with a copy of the previous state.
  `/alchemist-rollback` relies on this journal.
- **Solution imports**: plugin steps and business rules are restored to their previous state (Dataverse would disable
  them otherwise).
- **Test data**: names prefixed with `testing.e2e.recordPrefix`, deleted by id only, never by a broad query.
