# Service contract (`rhz_contratservice`)

<!-- alchemist:auto:start -->
**Service contract** (`rhz_contratservice`) · Web API set `rhz_contratservices` · ownership UserOwned · primary name `rhz_name`

## Custom columns

| Column | Label | Type | Required | Detail |
|---|---|---|---|---|
| `rhz_beneficiaire` | Beneficiary | Customer | No | to account, contact |
| `rhz_coefficientindexation` | Coefficient d'indexation | Decimal | No | 0 to 10 |
| `rhz_compteid` | Account | Lookup | No | to account |
| `rhz_conditionsparticulieres` | Special terms | Memo | No | max 4000 |
| `rhz_contactprincipalid` | Primary contact | Lookup | No | to contact |
| `rhz_contratsigne` | Signed contract | File | No | 32768 Ko |
| `rhz_datedebut` | Start date | DateTime | No | DateOnly, DateOnly |
| `rhz_datefin` | End date | DateTime | No | DateOnly, DateOnly |
| `rhz_dureejours` | Durée (jours) | Decimal (formula) | No | formula `DateDiff(rhz_datedebut, rhz_datefin, TimeUnit.Days)` |
| `rhz_emailfacturation` | E-mail de facturation | String | No | max 100 |
| `rhz_montantannuel` | Annual amount | Money | No | -922337203685477 to 922337203685477 |
| `rhz_numerocontrat` | Numéro de contrat | String | No | max 100, auto-number `CTR-{SEQNUM:5}` |
| `rhz_photodusiteid` |  | Uniqueidentifier | No |  |
| `rhz_referencecomptable` | Référence comptable | Integer | No | -2147483648 to 2147483647 |
| `rhz_scorerisque` | Score de risque | Double | No | 0 to 100 |
| `rhz_siteclient` | Site du client | String | No | max 200 |
| `rhz_statutcontrat` | Contract status | Picklist | No | 911240000 Draft ; 911240001 Active ; 911240002 Expired ; 911240003 Terminated (default 911240000) |
| `rhz_telephonefacturation` | Téléphone de facturation | String | No | max 100 |
| `rhz_typecontrat` | Contract type | Picklist | No | 911240000 Bronze ; 911240001 Silver ; 911240002 Gold |

## Forms

- Information (main)
- Création rapide (quick create)

## Form scripts

| Form | Event | Function | Web resource |
|---|---|---|---|
| Information | onchange `rhz_datedebut` | `Alchemist.ContratService.Information.onDateChange` | `rhz_/js/rhz_contratservice.information.js` |
| Information | onchange `rhz_datefin` | `Alchemist.ContratService.Information.onDateChange` | `rhz_/js/rhz_contratservice.information.js` |
| Information | onload | `Alchemist.ContratService.Information.onLoad` | `rhz_/js/rhz_contratservice.information.js` |
| Information | onsave | `Alchemist.ContratService.Information.onSave` | `rhz_/js/rhz_contratservice.information.js` |

## Public views

- Active contracts
- Active Service contracts (default)
- Contracts expiring within 90 days
- Inactive Service contracts

## Business rules

- Date de fin obligatoire si actif — active: CRM-410 : si le statut est Actif, la date de fin est obligatoire.

_Generated from Dataverse on 2026-11-12._
<!-- alchemist:auto:end -->

## Notes

- **Date consistency (CRM-414)**: on the Information form, an end date before the start date shows an error on the end date and blocks saving; the error disappears as soon as the dates are consistent again. The check is form-side only (an import or the API is not checked).
- **End date required when the contract is active (CRM-410)**: business rule, without automatic return to optional when the status changes.
