---
name: feature-documentation
description: Looks up the existing documentation of a Dynamics 365 feature (repository docs folder, Azure DevOps wiki, docs.url link, references) before development, starts it when there is none, then updates it afterwards (feature page per ticket, data dictionary per table, plugins, scripts). Use during analysis and when closing each ticket.
---

# Feature documentation

Settings: `docs.enabled`, `docs.provider` (`local` | `azureDevOpsWiki` | `none`), `docs.url` (main documentation link,
cited in the plan, the PR and the summary), `docs.localPath`, `docs.featurePagePattern`, `docs.tablePagePattern`,
`docs.wiki.*`, `docs.references`.

## Read phase (analysis, before the plan)

1. Look for the documentation related to the ticket:
   - `local`: Grep in `docs.localPath` for the names of tables, columns, plugins, the ticket key, linked tickets and
     business keywords. Read the pages found.
   - `azureDevOpsWiki`: `Invoke-DevOpsWiki.ps1 -Action List`, then `-Action Get -PagePath <page>` for the pages whose path
     matches.
   - `docs.url` and `docs.references`: read the useful pages (WebFetch if they are public). If a page requires
     authentication, mention it without trying to bypass it.
2. Summarize in the plan what the documentation says about what exists, and the **contradictions** between the
   documentation, the ticket and the code or the real CRM. These contradictions become open questions.

## No documentation found: start it

If `docs.enabled` is false, if `docs.provider` is `none`, or if the search finds nothing (no docs folder, no wiki, no
`docs.url`), **propose in the plan to start the documentation**. It is the user's decision (plan question): the
documentation is committed on the branch and read by the team.

After approval:

1. Config: `docs.enabled = true`, `docs.provider = "local"`, `docs.localPath = "docs"` (unless chosen otherwise), default
   patterns `tables/{table}.md` and `features/{key}.md`.
2. Generate the base from the real CRM (read-only on the Dataverse side):
   ```
   New-AlchemistDocumentation.ps1 -Tables <ticket tables> -IssueKey <KEY> -DryRun
   New-AlchemistDocumentation.ps1 -Tables <ticket tables> -IssueKey <KEY>
   ```
   It creates `docs/README.md` (index), one data dictionary page per table (custom columns with type, requirement,
   details, choices, formulas; keys; forms; views; business rules; plugin steps and their state) and the feature page
   (need, criteria, components from the journal, report summary).
3. Only document the ticket's tables: the documentation grows ticket after ticket, without retro-documenting the whole
   CRM.
4. Complete the **Notes** section of each page by hand (rules, decisions, remaining manual testing). The block between
   `<!-- alchemist:auto:start -->` and `<!-- alchemist:auto:end -->` is regenerated on each run; the rest is kept.

## Update phase (after the tests)

### Feature page (`featurePagePattern`, e.g. `features/CRM-123.md`)

```markdown
# <KEY> - <Title>
> Ticket: <Jira url> · Branch: <branch> · Date: <date>

## Need
<functional summary in 3-5 lines>

## Delivery
### Data model
| Table | Column | Type | Label | Required | Detail |
### Forms
| Table | Form | Tab / Section | Fields |
### Plugins
| Class | Message | Table | Stage | Mode | Filters | Images | Rule |
### Form scripts
| Web resource | Event | Handler | Behavior |

## Business rules
- ...

## Tests
<link to unit tests, end-to-end and browser test summary, remaining manual testing>

## Points of attention
```

Only include the useful sections.

### Existing pages

- **Data dictionary** (`tablePagePattern`, e.g. `tables/account.md`): if the page was generated (`alchemist:auto`
  markers), rerun `New-AlchemistDocumentation.ps1 -Tables <t> -IssueKey <KEY>`. Otherwise add the new columns to the
  existing table, in the same format. A missing page is created with the script.
- Existing functional or technical pages affected by the change: update the relevant passage, without rewriting the rest.
- Index or table of contents (`README.md`, wiki `.order`): add the link to the new page.

### Publishing

- `local`: files are committed on the ticket branch (`<KEY>: documentation`).
- `azureDevOpsWiki`: write the content in `.alchemist/runs/<KEY>/docs/`, then `Invoke-DevOpsWiki.ps1 -Action Set ...
  -Comment "<KEY>" -DryRun`. Show the content to the user and publish **only after confirmation**, because the wiki is
  shared and the change is immediate.

## Rules

- Document **only** what was delivered for the ticket. You do not rewrite or restructure existing pages, and you do not
  fix other sections (report the errors spotted as observations instead).
- Follow the format and tone of existing pages (consistency).
- Every page creation or change is shown to the user. The shared wiki is only published after their approval.
- Never delete existing content without saying so.
- Write in `project.language`, in the style of existing pages.
- No secret, no sensitive environment URL, no personal data from tests.
