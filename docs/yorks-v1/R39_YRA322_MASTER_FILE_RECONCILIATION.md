# YRA-322 Nexus Master File Reconciliation

Status: **production applied and verified on 29 August 2026**

Source: `Project Master File - Nexus 4 Station.xlsx`

SHA-256:
`1038f0b54c1be1473bd5160c9523532fb141988177d6555651fb795d9f061b3c`

Size: `1,961,340` bytes

## Project identity decision

The commercial summary and progress worksheets consistently identify
`YRA-322` and the `N-19957.2` Nexus Phase 1 contract. The copied Project
Details sheet identifies YRA-315 and was quarantined as a conflicting source;
it was not allowed to overwrite YRA-322 project metadata.

The typo `N-1957.2` in `Summery (Option)!D2` was normalized to the dominant
`N-19957.2` reference already held by the project and repeated throughout the
workbook.

## Applied facts

| Fact | Workbook evidence | Applied value |
|---|---|---:|
| Contract baseline | `Summery (Option)!F52` | AED 17,192,000.00 |
| Buildings | DF3W, DF4W, DF6W, DF7W | 25% each |
| Billing stages | `D53:D57` | 10% / 50% / 30% / 5% / 5% |
| DF3W Design | `H9`, `I9`, `W9`, `X9` | 100% of stage / AED 429,800.00 |
| DF4W Design | `H20`, `I20`, `W20`, `X20` | 100% of stage / AED 429,800.00 |
| DF6W Design | `H31`, `I31`, `W31`, `X31` | 100% of stage / AED 429,800.00 |
| DF7W Design | `H42`, `I42`, `W42`, `X42` | 100% of stage / AED 429,800.00 |
| Overall confirmed work | `W58`, `X58` | 10.00% / AED 1,719,200.00 |

Baseline revision 1 already matched the workbook and was verified without
creating a replacement baseline. Four Design progress rows were confirmed
against the immutable source reconciliation. Material Supply, Installation,
Commissioning & Handover and Energizing remained zero.

## Active-baseline reconciliation

A later approved management-review-policy change created baseline revision 2.
Baseline versioning correctly materialized a new 20-row progress grid, so the
source confirmation remained preserved on superseded revision 1 while the
active projection returned zero progress. The two revisions retain identical
source-relevant commercial dimensions: contract value, currency, VAT,
payment/reminder terms, four 25% building allocations, and the 10/50/30/5/5
stage allocations. Only the review policy changed.

The 29 August correction therefore reapplies the four already-approved Design
facts to active revision 2. It links every new confirmation revision to the
same immutable source-import row and appends new audit events. It does not
rewrite revision 1, carry progress automatically between arbitrary baselines,
or infer a new suggestion actor.

## Deliberate exclusions

- `YRA32201` has an amount excluding VAT of zero. No claim or invoice was
  created.
- Approval, due and paid dates are blank/zero. No certification or payment was
  created.
- `45 days PDC` is a note without a PDC instrument, amount, reference or date.
  No PDC was created and the active Accounts policy was not changed.
- Four `YRA3220X` cells are future placeholders, not transactions.
- `Summery (Option)!H5` contains a date inconsistent with the other building
  periods. It was recorded as an anomaly and not used as an historical actor
  timestamp.

These exclusions remain in the immutable source-import row so a later user can
enter a real claim, certification, PDC or payment when actual evidence exists.

## Controls and rollback

Initial migration:
`20260828085441_yorks_r39_accounts_yra322_master_file_import.sql`

Active-baseline correction:
`20260829110327_reconcile_yra322_source_progress_to_current_baseline.sql`

The migration:

- verifies project, actor, baseline, building allocations and stage totals;
- records the source hash, exact extracted facts and all excluded facts;
- refuses to overwrite any existing non-zero confirmation;
- adds append-only progress revisions and audit events;
- is idempotent for the same project and workbook hash;
- denies direct source-import table access to browser clients.

The correction additionally:

- requires the immutable source facts to exist on superseded revision 1;
- requires revision 2 to be the active, dimensionally equivalent baseline;
- refuses to run if any current progress row has been edited or if any
  receivable/payable transaction exists;
- locks the project and complete progress grid before mutation;
- exposes no execution grant to browser or service API roles;
- confirms exactly four Design rows and verifies the resulting weighted total
  is exactly 10.0000% / AED 1,719,200.00;
- is an exact no-op when replayed after a successful reconciliation.

Rollback is corrective, never destructive: create new progress-confirmation
revisions returning the four Design rows to the approved replacement values,
retain the source-import and audit rows, and record the correction reason. Do
not delete the import ledger or its audit history.

## Initial production verification

The protected project Accounts projection returned:

- confirmed progress: `10.00%`;
- confirmed eligible value: `AED 1,719,200.00`;
- four Design rows at `100.0000%`;
- claims, invoices, certifications, PDCs and payments: `0`;
- four progress-import audit events and one source-import audit event.

Before the 29 August correction, a live read confirmed that revision 2 was
current and its fresh grid was still pristine: 20 rows at zero, no revisions,
and no Accounts transaction records. That fail-closed precondition made the
source reapplication safe.

## Active-baseline production verification

After linked migration `20260829110327` was applied, a direct protected
production query returned:

- current baseline: revision `2`, AED `17,192,000.00`;
- progress grid: `20` rows;
- Design: four rows at `100.0000%`, all linked to the immutable source import;
- Material Supply, Installation, Commissioning & Handover and Energizing:
  `16` rows at `0.0000%`;
- weighted confirmed progress: `10.0000%` / AED `1,719,200.00`;
- current-baseline source-linked progress revisions: `4`;
- cumulative import audit events: eight progress events and two source-import
  events (the original application plus the active-baseline correction);
- claims, invoices, certifications, client payments, PDCs, PDC events,
  supplier bills and supplier payments: `0`.

## Release evidence

- Local database reset and the complete pgTAP suite passed: 60 files and
  1,652 assertions. The two YRA-322 files contributed 19 passing assertions,
  including conflict, API-grant and exact-replay coverage.
- `flutter analyze` and the 18 focused Accounts/router tests passed.
- Accounts-enabled Flutter web and ephemeral-signed Android release builds
  passed; the Android artifact was 98.8 MB.
- Production database migration `20260829110327` is aligned in the local and
  remote ledgers. The post-deploy database advisor command completed without
  an error-level finding; its warning-level output is the existing broader
  schema backlog.
- Vercel deployment `dpl_9RnX6xtiLQhocA1F2xGP5Q9uMgNz` reached `READY` and was
  promoted to `https://yorks-r35.vercel.app`. Root, Accounts portfolio,
  billing-progress and the YRA-322 Accounts overview deep route returned HTTP
  200. The deployed index, bootstrap, manifest, service worker and application
  bundle matched the production build byte-for-byte.

The repository-wide Flutter run is not represented as globally green: 831
non-golden tests passed while four pre-existing 1024 px shell/overview tests
reported the same 139 px top-bar overflow; the golden lane also has unrelated
baseline pixel drift. Neither failure intersects this SQL-only reconciliation
or its focused Accounts gates.

## November 2026: billing history from the signed invoices

Owner decisions of 8 November 2026 (`PRODUCT_DECISIONS.md` section 30).

On 20 October 2026 a contract revision set YRA-322's value to AED 1,808,546.80
(it was meant as AED 18,085,468.00). No claim, invoice, certification or
payment had been recorded. The November import brings YRA-322 to its real
billing history from these sources:

| File | SHA-256 |
|---|---|
| `32201 L&T NEXUS -DHAFRA  PAYEMNT INVOICE.xlsx` | `7b6c24c03a789f6e4cf559d4182abc117ef8c4a3c2e7094ffb70c0d79c745320` |
| `Invoice-PC #01-signed.pdf` | `f8fde0ff616add34c78821c0ad372e8242db6fe82ecacf0b9313b4988e978c8e` |
| `INVOICE#02R.1.xlsx` | `9df45305c10485eef7c8b2519cbd1e2db2df4c4daaaa5fe491882fec8bcb436b` |
| `INVOICE#02-R.1-signed.pdf` | `1c9540e87c6f51d9b88870cf1bc479dc0deeddb0bd9861be9cfef40ee2acd896` |

What it records, in one transaction, as Owner:

1. The contract as invoiced: AED 17,192,000, VAT 5%, 45 days, four buildings
   at 25%, stages 10/50/30/5/5 with the invoice labels; Material Supply and
   Progress Installation measured by the workbook's 15 items per building;
   client TRN, work order and contract number; L&T as the billed party.
2. Claim #01: Cooling Load Design 100% in every building, imported from the
   YRA32201 workbook; invoice **YRA32201** dated 19 Jan 2026 (1,719,200.00 +
   85,960.00 = 1,805,160.00); certified in full on 2 Feb 2026; cheque 004517
   received 10 Mar, deposited 20 Apr, cleared 21 Apr 2026, so the invoice is
   paid.
3. Claim #02: Material Supply deliveries per building, imported from the
   YRA32202R.1 workbook (DF3W 1,549,624.36; DF4W 1,549,624.36; DF6W
   1,463,664.36; DF7W 1,420,684.36); invoice **YRA32202R.1** dated
   29 Sep 2026 (5,983,597.45 + 299,179.87 = 6,282,777.33); certified in full on
   20 Oct 2026; cheque 004893 for 6,282,777.33 received 1 Nov 2026, dated
   13 Nov 2026, in hand.
4. The next invoice number YRA32203, then the contract value correction to
   AED 18,085,468.00. Issued invoices keep their amounts.

Each invoice is frozen with the letterhead and bank its signed copy carries.
Progress is linked to two source-import rows (one per workbook), as in August;
no evidence document is inferred. The certifications and cheques are
owner-confirmed facts; the cheques' bank was not given and is left blank. The
original YRA32202, the prototype's draft claim #03 and its sample supplier
bills are not recorded.

The import refuses to run unless YRA-322 is exactly as read on 8 November (the
1,808,546.80 revision, no billing records, all progress at zero) and checks
every invoice figure, the frozen document's columns, the payment and cheque
state, the next invoice number and the final contract value before it can
commit. The signed copies are attached to their invoices afterwards in the app.

Rollback is corrective: revise or cancel the invoices with a reason, reverse
the payment and cheques, and add correcting progress revisions; the
source-import rows and audit events stay.
