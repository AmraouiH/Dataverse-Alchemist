---
name: alchemist-learning
description: Dataverse Alchemist knowledge base - learns from what satisfies each user and from their corrections, then applies it to the next tickets. Use at the start of each ticket to load what is known, as soon as the user expresses satisfaction, makes a choice or corrects the agent, and when closing the ticket.
---

# Learning how each person works

## Two levels of knowledge

| Level | File | Content | Sharing |
|---|---|---|---|
| Person (`-Scope User`) | `~/.dataverse-alchemist/knowledge/<user>.json` | this person's preferences: format, layout, way of approving | their workstation only |
| Project (`-Scope Project`) | `<repo>/.alchemist/knowledge/project.json` | practices shared by the project | can be committed, with the team's agreement |

The user is identified by `report.crmUserEmail`, then `jira.email`, then `git config user.email`. What applies to one
person does not apply to another.

## Load (start of each ticket)

```
pwsh -NoProfile -File ".claude/dataverse-alchemist/scripts/Get-AlchemistKnowledge.ps1"
```

- **Confirmed** lesson (3 signals or more): apply by default, without asking again.
- **Observed** lesson (1 or 2 signals): a hint, to propose as a recommendation.
- In the plan, cite the lessons used ("learned: ...") so the user can correct them.

**Priority order**: golden rules > ticket > user request > `conventions.md` > knowledge base. A lesson never replaces an
approval, never widens the scope of a ticket and never replaces reading what exists.

## Learn

Record a lesson when there is an **explicit signal**, at the moment it happens:

| Signal | Example | `-Signal` |
|---|---|---|
| Satisfaction expressed | "great", "perfect", "it works, thanks" about a specific result | `satisfied` |
| Choice between options | mockup picked, recommendation accepted | `chosen` |
| Correction | "the mockup must be an image", reasoned refusal | `corrected` |

These are **not** signals: silence, absence of remarks, a purely procedural approval ("Run these actions"). When in
doubt, record nothing.

**A good lesson** describes a reusable behavior, not a fact of the ticket:
- yes: "Prefers PNG image mockups over text diagrams";
- no: "Picked option A for Service Request"; record it as `-Note` instead, as evidence.

If the satisfaction does not clearly say what was liked, ask in one short question rather than guess.

```
pwsh -NoProfile -File ".claude/dataverse-alchemist/scripts/Add-AlchemistKnowledge.ps1" -Scope User -Category <category> -Signal <signal> -Lesson "<behavior>" -IssueKey <KEY> -Note "<what happened>"
```

Categories: `communication`, `form-layout`, `naming`, `code-style`, `testing`, `delivery`, `workflow`, `data-model`.

An identical lesson is reinforced (counter +1), not duplicated: so reuse **the same wording** as the existing lesson. If
a new correction contradicts a lesson, remove the old one with `-RemoveId`, then record the new one.

**Never in the base**: secrets, email addresses, customer data, record content. The script refuses what it detects, but
it is up to you not to put it there.

**Level**: `-Scope User` by default. Only use `-Scope Project` for a practice valid for the whole team, and with the
user's agreement. The project file never goes into a ticket branch: it is a separate commit, on request.

## When closing the ticket

1. Review the run's signals and record what is not recorded yet.
2. Announce in one or two lines what was learned, so the user can correct it.

`/alchemist-learn` shows what is known, and lets you forget a lesson.
