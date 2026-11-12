# Git, branches and pull requests

## Git (`git` section)

```json
"git": {
  "remote": "origin",
  "defaultBaseBranch": "develop",
  "branchNamePattern": "{type}/{key}-{slug}",
  "typeMapping": { "Story": "feature", "Task": "feature", "Bug": "bugfix", "Hotfix": "hotfix" },
  "baseBranchRules": [
    { "description": "Hotfix from main", "when": { "issueType": ["Hotfix"] }, "base": "main" },
    { "description": "Release of the fix version", "when": { "fixVersion": "*" }, "base": "release/{fixVersion}" }
  ],
  "commitMessagePattern": "{key}: {summary}",
  "pushAfterCompletion": "ask"
}
```

The **base branch** is chosen in this order:
1. the Jira field `jira.baseBranchField`;
2. the first rule in `baseBranchRules` that matches the ticket (type, label or fix version);
3. `defaultBaseBranch`.

The branch name follows `branchNamePattern`, for example `feature/CRM-123-add-segment-field`.

`pushAfterCompletion` is `ask` (offer to push, always after approval) or `never`. Local commits on the ticket branch
are controlled by `workflow.autoCommit`.

## Pull requests (`devops` section)

```json
"devops": {
  "provider": "azureDevOps",
  "organizationUrl": "https://dev.azure.com/myorg",
  "project": "CRM",
  "repository": "crm",
  "pat": "env:AZDO_PAT",
  "createPullRequest": "ask",
  "pullRequestAsDraft": true,
  "defaultReviewerIds": []
}
```

| `provider` | Configuration |
|---|---|
| `none` | no pull request |
| `azureDevOps` | `organizationUrl`, `project`, `repository`, `pat` (Code: read and write) |
| `github` | `repository` as `owner/name`; `pat` optional: without it, the signed-in `gh` CLI is used |

`createPullRequest` is `ask` (offered at the end of the ticket, after approval) or `never`.

The Azure DevOps wiki can also host the documentation: see [06-code-and-docs.md](06-code-and-docs.md).
