---
name: dataverse-security-role
description: Creates a Dynamics 365 / Dataverse security role in the ticket's solution, or extends an existing role, with table privileges (Create, Read, Write, Delete, Append, AppendTo, Assign, Share) and a depth (user, business unit, child business units, organization), then links it to an app if needed. Use when a ticket asks for a role or access rights on a table.
---

# Security roles

## Prerequisites

- Ticket solution chosen. Privileges and depth come from the ticket; if they are missing, it is a plan question.
- List the existing roles (root business unit) before creating one:
  `Invoke-Dataverse.ps1 -Path "roles?$select=name&$filter=_parentroleid_value eq null"`.

## Run

```
New-DataverseSecurityRole.ps1 -Name "Contract manager" -Description "..." `
    -Privileges "rhz_servicecontract:Read,Create,Write:Local","account:Read:Global" -IssueKey <KEY> -DryRun
```

- Depth: `Basic` (user), `Local` (business unit), `Deep` (business unit and children), `Global` (organization).
- The role is created in the root business unit. If it already exists, only the missing privileges, or those at another
  depth, are added (`AddPrivilegesRole`): nothing is removed.
- The script checks each privilege after writing (`RetrieveRolePrivilegesRole`) and adds the role to the solution.
- To open an app, the role must also be linked to it:
  `Set-DataverseAppRoles.ps1 -AppUniqueName <app> -Roles "<role name>" -IssueKey <KEY>` (idempotent).
- A role without read access on the base system tables (user, business unit…) is not enough to sign in: it complements a
  base role, it does not replace it. Say so in the plan.

## Check

Read the privileges back (`RetrieveRolePrivilegesRole(RoleId=...)`), check the solution with
`Test-DataverseSolutionComponents.ps1`. The rollback deletes the role created by the ticket, and removes the privileges
added to an existing role.
