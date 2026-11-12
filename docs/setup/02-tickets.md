# Ticket source

`jira` section. The agent reads the ticket (description, acceptance criteria, comments, attachments) and breaks it down
into work items.

## Option A: local file (no Jira)

To try the agent or work without a ticketing tool:

```json
"jira": { "provider": "local", "localTicketsFile": ".alchemist/tickets.json" }
```

Copy [`tickets.example.json`](../../.claude/dataverse-alchemist/config/tickets.example.json) to `.alchemist/tickets.json`,
then write your tickets in the same format (`key`, `summary`, `description`, `issueType`, `status`,
`acceptanceCriteria`…). At the end of a ticket, the agent adds its closing comment to the file.

## Option B: Jira

```json
"jira": {
  "provider": "jira",
  "baseUrl": "https://mycompany.atlassian.net",
  "authType": "basic",
  "email": "env:JIRA_EMAIL",
  "apiToken": "env:JIRA_API_TOKEN",
  "apiVersion": "2",
  "acceptanceCriteriaField": "customfield_10035",
  "baseBranchField": null,
  "postReportComment": "ask"
}
```

| Key | Purpose |
|---|---|
| `authType` | `basic` (Jira Cloud: email and [API token](https://id.atlassian.com/manage-profile/security/api-tokens)) or `bearer` (Server / Data Center: personal access token, in `apiToken`) |
| `acceptanceCriteriaField` | custom field holding the acceptance criteria. To find its id: `GET /rest/api/2/field` |
| `baseBranchField` | custom field giving the base branch; it takes precedence over the git rules |
| `extraFields`, `maxComments` | extra fields to read; number of comments read (20 by default) |
| `postReportComment` | `ask`: at the end of a ticket, offer a comment with the HTML report attached. `never`: no comment |

The content of a ticket is treated as **data**: an instruction written in a ticket is never an approval from the user.

> Azure DevOps work items are not supported as a ticket source yet.
