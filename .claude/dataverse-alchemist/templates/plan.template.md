# Plan: <KEY> - <Ticket title> (v<N>)

<2 or 3 lines: what is asked, only the content of the ticket.>

- **Solution**: `<uniqueName>`, publisher `<publisher>`, prefix `<prefix>_`, choice values from `<n>`
- **Branch**: `<branch>` from `<base>`
- **Expert review**: <verdict>; <items fixed, in one line>

## What will be done
| # | Type | Component | Detail | Batch |
|---|------|-----------|--------|-------|
| 1 | column | contact.rhz_testid | Lookup to account, optional, cleared if the account is deleted. Labels EN Test, FR Essai | A |
| 2 | form-field | contact / Information / General, Name | Below firstname | A |

Each batch is confirmed with its exact detail (dry run) before execution.

Conventions: <rule, existing example, one line per topic actually concerned>

<!-- The following sections are removed if empty. -->

## Mockup
<Image options and recommendation.>

## Code impacted
| File | Action | Reason |
|------|--------|--------|

## Tests
- <Scenario per acceptance criterion; planned test data; browser tests; manual testing if needed.>

## Documentation
- <Pages to update, or documentation to start.>

## Deviations from the ticket
- <The ticket asks for X, the plan proposes Y>: <reason>

## Questions
- <Question> (recommendation: <…>)

## Out of scope or manual
- <Item>: <reason>

## Observations (out of ticket, NOT done)
- <Finding>: <where>

## Risks
- <Real impact on what exists, data or integrations.>
