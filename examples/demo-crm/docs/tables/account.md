# Account (`account`)

<!-- alchemist:auto:start -->
**Account** (`account`) · Web API set `accounts` · ownership UserOwned · primary name `name`

Business that represents a customer or potential customer. The company that is billed in business transactions.

## Custom columns

| Column | Label | Type | Required | Detail |
|---|---|---|---|---|
| `adx_createdbyipaddress` | Created By (IP Address) | String | No | max 100 |
| `adx_createdbyusername` | Created By (User Name) | String | No | max 100 |
| `adx_modifiedbyipaddress` | Modified By (IP Address) | String | No | max 100 |
| `adx_modifiedbyusername` | Modified By (User Name) | String | No | max 100 |
| `msa_managingpartnerid` | Managing Partner | Lookup | No | to account |
| `rhz_codeinterne` | Code interne | String | No | max 20 |
| `rhz_legalrepid` | Legal Rep | Lookup | No | to contact |
| `rhz_segmentclient` | Segment client | Picklist | No | 911240000 PME ; 911240001 ETI ; 911240002 Grand compte |
| `rhz_tstautonum` | Tst AutoNumber | String | No | max 100, auto-number `TST-{SEQNUM:5}` |
| `rhz_tstbigint` | Tst BigInt | BigInt | No |  |
| `rhz_tstbool` | Tst Boolean | Boolean | No | Yes / No |
| `rhz_tstchoice` | Tst Choice | Picklist | No | 911240000 Low ; 911240001 Medium ; 911240002 High ; 911240003 Tst Ajout |
| `rhz_tstchoicejson` | Tst Choice Json | Picklist | No | 911240100 One ; 911240101 Two |
| `rhz_tstcustomer2id` | Tst Customer 2 | Customer | No | to account, contact |
| `rhz_tstcustomerid` | Tst Customer | Customer | No | to account, contact |
| `rhz_tstdateonly` | Tst Date Only | DateTime | No | DateOnly, DateOnly |
| `rhz_tstdatetime` | Tst Date Time | DateTime | No | DateAndTime, UserLocal |
| `rhz_tstdatetz` | Tst Date Tz | DateTime | No | DateAndTime, TimeZoneIndependent |
| `rhz_tstdecimal` | Tst Decimal | Decimal | No | -100000000000 to 100000000000 |
| `rhz_tstduration` | Tst Duration | Integer | No | 0 to 100000 |
| `rhz_tstemail` | Tst Email | String | No | max 100 |
| `rhz_tstfile` | Tst File | File | No | 32768 Ko |
| `rhz_tstfloat` | Tst Float | Double | No | -100000000000 to 100000000000 |
| `rhz_tstglobal` | Tst Global Choice | Picklist | No | choix global `powerpagelanguages` : 1025 Arabic ; 1069 Basque - Basque ; 1026 Bulgarian - Bulgaria ; 1027 Catalan - Catalan ; 2052 Chinese - China ; 3076 Chinese - Hong Kong SAR ; 1028 Chinese - Traditional ; 1050 Croatian - Croatia ; 1029 Czech - Czech Republic ; 1030 Danish - Denmark ; 1043 Dutch - Netherlands ; 1033 English ; 1061 Estonian - Estonia ; 1035 Finnish - Finland ; 1036 French - France ; 1110 Galician - Spain ; 1031 German - Germany ; 1032 Greek - Greece ; 1037 Hebrew ; 1081 Hindi - India ; 1038 Hungarian - Hungary ; 1057 Indonesian - Indonesia ; 1040 Italian - Italy ; 1041 Japanese - Japan ; 1087 Kazakh - Kazakhstan ; 1042 Korean - Korea ; 1062 Latvian - Latvia ; 1063 Lithuanian - Lithuania ; 1086 Malay - Malaysia ; 1044 Norwegian (Bokmål) - Norway ; 1045 Polish - Poland ; 1046 Portuguese - Brazil ; 2070 Portuguese - Portugal ; 1048 Romanian - Romania ; 1049 Russian - Russia ; 3098 Serbian (Cyrillic) - Serbia ; 2074 Serbian (Latin) - Serbia ; 1051 Slovak - Slovakia ; 1060 Slovenian - Slovenia ; 3082 Spanish (Traditional Sort) - Spain ; 1053 Swedish - Sweden ; 1054 Thai - Thailand ; 1055 Turkish - Türkiye ; 1058 Ukrainian - Ukraine ; 1066 Vietnamese - Vietnam |
| `rhz_tstimageid` |  | Uniqueidentifier | No |  |
| `rhz_tstint` | Tst Integer | Integer | No | 0 to 1000 |
| `rhz_tstlanguage` | Tst Language | Integer | No | 0 to 2147483647 |
| `rhz_tstlookupid` | Tst Lookup | Lookup | No | to contact |
| `rhz_tstmemo` | Tst Memo | Memo | No | max 4000 |
| `rhz_tstmoney` | Tst Money | Money | No | -922337203685477 to 922337203685477 |
| `rhz_tstmulti` | Tst MultiChoice | MultiSelectPicklist | No | 911240000 Red ; 911240001 Green ; 911240002 Blue |
| `rhz_tstphone` | Tst Phone | String | No | max 100 |
| `rhz_tstrichtext` | Tst RichText | Memo | No | max 2000 |
| `rhz_tstselfid` | Tst Self Lookup | Lookup | No | to account |
| `rhz_tsttext` | Tst Text Modifié | String | Recommended | max 250 |
| `rhz_tstticker` | Tst Ticker | String | No | max 100 |
| `rhz_tsttimezone` | Tst TimeZone | Integer | No | -1500 to 1500 |
| `rhz_tsturl` | Tst Url | String | No | max 100 |

## Alternate keys

| Key | Label | Columns | Index |
|---|---|---|---|
| `rhz_codeinternekey` | Code interne | rhz_codeinterne | Active |

## Forms

- Account (main)
- Account for Interactive experience (main)
- Alchemist Test Form (main)
- Information (main)
- Account Quick Create (quick create)
- Alchemist Test Quick Create (quick create)

## Form scripts

| Form | Event | Function | Web resource |
|---|---|---|---|
| Information | onload | `Alchemist.Account.Information.onLoad` | `rhz_/js/account.information.js` |
| Information | onchange `creditlimit` | `Alchemist.Account.Information.onCreditLimitChange` | `rhz_/js/account.information.js` |

## Public views

- Accounts: Influenced Deals That We Won
- Accounts: No Campaign Activities in Last 3 Months
- Accounts: No Orders in Last 6 Months
- Accounts: Responded to Campaigns in Last 6 Months
- Active Accounts
- Alchemist Test View
- All Accounts
- Inactive Accounts
- My Active Accounts (default)
- My Connections

## Plugins

| Step | Message | Stage | Mode | Filters | State |
|---|---|---|---|---|---|
| Alchemist.Plugins.AccountNumberNormalizationPlugin: Create of account | Create | PreOperation | Sync |  | active |
| Alchemist.Plugins.AccountNumberNormalizationPlugin: Update of account | Update | PreOperation | Sync | accountnumber | active |
| Alchemist.Plugins.AccountNumberChangeTracePlugin: Update of account | Update | PostOperation | Async | accountnumber | active |

_Generated from Dataverse on 2026-11-12._
<!-- alchemist:auto:end -->

## Notes

Rules and practices specific to this table (free text, kept on regeneration).
