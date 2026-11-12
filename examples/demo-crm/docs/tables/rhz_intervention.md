# Intervention (`rhz_intervention`)

<!-- alchemist:auto:start -->
**Intervention** (`rhz_intervention`) · Web API set `rhz_interventions` · ownership UserOwned · primary name `rhz_name`

Intervention d'un technicien sur un équipement (CRM-413).

## Custom columns

| Column | Label | Type | Required | Detail |
|---|---|---|---|---|
| `rhz_compterendu` | Compte rendu | Memo | No | max 4000 |
| `rhz_dateintervention` | Date d'intervention | DateTime | No | DateOnly, DateOnly |
| `rhz_dureeheures` | Durée (heures) | Decimal | No | 0 to 1000 |
| `rhz_equipementid` | Équipement | Lookup | Yes | to rhz_equipement |
| `rhz_statutintervention` | Statut | Picklist | No | 911240000 Planifiée ; 911240001 Réalisée ; 911240002 Annulée (default 911240000) |
| `rhz_technicienid` | Technicien | Lookup | No | to systemuser |

## Forms

- Information (main)

## Public views

- Active Interventions (default)
- Inactive Interventions

## Business rules

- Compte rendu obligatoire si réalisée — active: CRM-413 : le compte rendu est obligatoire dès que le statut est Réalisée.
- Compte rendu facultatif si non réalisée — active

## Plugins

| Step | Message | Stage | Mode | Filters | State |
|---|---|---|---|---|---|
| Alchemist.Plugins.InterventionCompletionPlugin: Create of rhz_intervention | Create | PreOperation | Sync |  | active |
| Alchemist.Plugins.InterventionCompletionPlugin: Update of rhz_intervention | Update | PreOperation | Sync | rhz_statutintervention,rhz_dureeheures,rhz_dateintervention,rhz_equipementid | active |

_Generated from Dataverse on 2026-11-12._
<!-- alchemist:auto:end -->

## Notes

Rules and practices specific to this table (free text, kept on regeneration).
