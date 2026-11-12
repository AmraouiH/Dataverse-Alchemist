# Équipement (`rhz_equipement`)

<!-- alchemist:auto:start -->
**Équipement** (`rhz_equipement`) · Web API set `rhz_equipements` · ownership UserOwned · primary name `rhz_name`

Équipement installé chez un client et couvert par un contrat de service (CRM-412).

## Custom columns

| Column | Label | Type | Required | Detail |
|---|---|---|---|---|
| `rhz_compteid` | Compte | Lookup | No | to account |
| `rhz_contratserviceid` | Contrat de service | Lookup | No | to rhz_contratservice |
| `rhz_datederniereintervention` | Dernière intervention | DateTime | No | DateOnly, DateOnly |
| `rhz_datefingarantie` | Fin de garantie | DateTime | No | DateOnly, DateOnly |
| `rhz_datemiseenservice` | Date de mise en service | DateTime | No | DateOnly, DateOnly |
| `rhz_numeroserie` | Numéro de série | String | Yes | max 50 |
| `rhz_sousgarantie` | Sous garantie | Boolean (formula) | No | Oui / Non, formule `rhz_datefingarantie >= UTCToday()` |
| `rhz_typeequipement` | Type d'équipement | Picklist | No | 911240000 Climatisation ; 911240001 Chauffage ; 911240002 Électricité ; 911240003 Plomberie |

## Alternate keys

| Key | Label | Columns | Index |
|---|---|---|---|
| `rhz_numeroseriekey` | Numéro de série | rhz_numeroserie | Active |

## Forms

- Information (main)

## Public views

- Active Équipements (default)
- Équipements sous garantie
- Inactive Équipements

_Generated from Dataverse on 2026-11-12._
<!-- alchemist:auto:end -->

## Notes

Rules and practices specific to this table (free text, kept on regeneration).
