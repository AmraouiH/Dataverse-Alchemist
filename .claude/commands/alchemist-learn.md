---
description: Shows what Dataverse Alchemist has learned about you and the project, and lets you forget a lesson
argument-hint: [category] [--forget <id>]
---

Apply the `alchemist-learning` skill.

- No argument: run `pwsh -NoProfile -File ".claude/dataverse-alchemist/scripts/Get-AlchemistKnowledge.ps1"` and present
  the lessons by level and by category, separating confirmed lessons from those only observed.
- With a category in `$ARGUMENTS`: add `-Category <category>`.
- With `--forget <id>` in `$ARGUMENTS`: add `-RemoveId <id>` and confirm what was removed.
