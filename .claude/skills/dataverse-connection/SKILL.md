---
name: dataverse-connection
description: Connects to Dynamics 365 / Dataverse through the Web API with the Dataverse Alchemist config, and runs read queries (table, column, form, step, web resource, global choice metadata). Use to analyze the existing CRM or make a Web API call without a dedicated script.
---

# Dataverse connection and reads

The whole connection goes through the config (`dataverse.environments.<env>`). Auth modes:
- `clientSecret`: Application User (Entra ID app registration) with a customization role on the environment;
- `azcli`: the `az login` account;
- `accessToken`: token provided (troubleshooting).

`allowWrite: false` makes the environment **read-only**: the scripts refuse any write. Never bypass this safeguard.

## Read scripts

```
# Table summary: columns (filterable), forms, custom plugin steps
pwsh -NoProfile -File ".claude/dataverse-alchemist/scripts/Get-DataverseTableInfo.ps1" -Table account -Attributes -CustomOnly -Forms -PluginSteps
pwsh -NoProfile -File ".claude/dataverse-alchemist/scripts/Get-DataverseTableInfo.ps1" -Table account -Attributes -AttributeFilter segment -Json

# Generic call (GET by default). Escape the $ of OData parameters: `$select
pwsh -NoProfile -File ".claude/dataverse-alchemist/scripts/Invoke-Dataverse.ps1" -Path "<path relative to /api/data/v9.2/>"
```

In Bash, wrap the path in single quotes so `$select` is not interpreted: `-Path 'accounts?$select=name&$top=3'`.

## Useful queries (`-Path`)

| Need | Path |
|---|---|
| Specific column | `EntityDefinitions(LogicalName='account')/Attributes(LogicalName='cts_segment')` |
| Options of a local choice | `EntityDefinitions(LogicalName='account')/Attributes(LogicalName='cts_segment')/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?$expand=OptionSet` |
| Unmanaged global choices | already listed in `conventions-crm.md`; otherwise `Get-DataverseData.ps1 -Path 'GlobalOptionSetDefinitions'` |
| N:1 relationships of a table | `EntityDefinitions(LogicalName='contact')/ManyToOneRelationships?$select=SchemaName,ReferencedEntity,ReferencingAttribute` |
| Web resources of the prefix | `webresourceset?$select=name,webresourcetype,modifiedon&$filter=startswith(name,'cts_')` |
| Web resource content | `Get-DataverseWebResource.ps1 -Name <name>` (or `webresourceset(<id>)?$select=content`, base64) |
| Plugin assemblies | `pluginassemblies?$select=name,version,isolationmode&$filter=customizationlevel eq 1` |
| Types of an assembly | `plugintypes?$select=typename&$filter=_pluginassemblyid_value eq <id>` |
| Solution components | `solutioncomponents?$select=objectid,componenttype&$filter=_solutionid_value eq <id>` |
| Solutions and publishers | `Get-DataverseSolutions.ps1` (then `Set-AlchemistRunSolution.ps1` to set the ticket's solution) |
| Plugin traces | `plugintracelogs?$select=typename,messagename,exceptiondetails,messageblock,createdon&$filter=typename eq '<type>'&$orderby=createdon desc&$top=10` |

## Writes

Use a dedicated script first (`New-DataverseColumn`, `Import-DataverseForm`, `Publish-DataverseWebResource`,
`Update-DataversePluginAssembly`, `Register-DataversePluginStep`, `Publish-DataverseCustomizations`). Only as a last
resort, `Invoke-Dataverse.ps1 -Method POST|PATCH|DELETE`: always `-DryRun` first, always `-IssueKey`, and user approval
before the real call. Creations automatically get the `MSCRM.SolutionUniqueName` header (ticket solution, with
`-IssueKey`), except with `-NoSolution` (end-to-end test data).

## Troubleshooting

- `HTTP 401`: expired secret, wrong tenant, or Application User missing from the environment.
- `HTTP 403` / `0x80040220`: insufficient security role.
- `0x80044363`: a component with that name already exists.
- Timeout or `PublishXml` error: another publish is in progress, retry once later.
