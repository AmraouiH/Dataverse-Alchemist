---
name: git-branch-strategy
description: Determines a ticket's base branch (Jira field, rules by type, label or fix version, default branch), names and creates the working branch, and handles Dataverse Alchemist commits, push and PR.
---

# Branch strategy

## Determine the base branch

```
pwsh -NoProfile -File ".claude/dataverse-alchemist/scripts/Resolve-BaseBranch.ps1" -IssueKey <KEY>
```

Evaluation order (the first **existing** candidate wins):
1. Jira field `jira.baseBranchField` if set;
2. `git.baseBranchRules` in order (conditions `issueType`, `label`, `component`, `fixVersion`, `priority`; `"*"` = "at
   least one value"; placeholders `{fixVersion}` and `{component}` in `base`);
3. `git.defaultBaseBranch`.

The output contains `candidates` (with `exists`): show them in the plan so the user sees **why** this branch was chosen.
If `existingBranchesForTicket` is not empty, propose resuming that branch. If no candidate exists, ask the user.

## Create the branch (after the plan is approved)

```
git fetch <remote> --prune
git switch -c <branchName> <remote>/<baseBranch>
```

Resume: `git switch <branch>` then `git pull --ff-only`.

## Commits

- Only the files related to the ticket: check `git status` and `git diff --cached --stat` before each commit. A file
  changed by a tool (formatting, lockfile) unrelated to the need is restored, not committed.
- Atomic commits per work item, with the `git.commitMessagePattern` message (e.g. `CRM-123: segment calculation plugin`).
- Never add `.alchemist/runs/`, secrets, `bin/`, `obj/`, `node_modules/` or `dist/`, unless `dist/` is committed in this
  repository (check with `git ls-files`).
- No `--no-verify`: if a hook fails, fix the cause.
- Never rewrite the history of the base branch. No force push.

## Push and PR (end of run, only if the user checks them in the closing question)

- `git push -u <remote> <branch>` if `git.pushAfterCompletion` is `ask` and the user accepts.
- PR via `New-PullRequest.ps1 -SourceBranch <branch> -TargetBranch <base> -Title "<KEY>: <summary>" -DescriptionFile <file> [-Draft] -IssueKey <KEY>`,
  first with `-DryRun` to show the content. The description includes the summary, the ticket link, the documentation
  link (`docs.url`), the Dataverse components changed and the test results.
