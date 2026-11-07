# R39 Accounts Workspace V2 — Import Master File scope

Status: **built on the existing setup-save RPC; provenance table not used.**
Verified 7 November 2026 by sending both real YRA-322 workbooks through the real
codec, parser and `v1_save_project_commercial_setup` in a rolled-back transaction:
DF3W Material Supply 2,149,000.00, AC Units 773,640.00, dampers 171,920.00, 15
items per building and item stage. The live file picker has not been exercised.

**Differences from the plan below.** Parsing, review and saving shipped together
as one flow. The confirm step uses the existing setup-save RPC with the file name
and SHA-256 in the revision note, rather than a new
`v1_apply_accounts_master_import` writing `v1_accounts_source_imports`. That avoids
a migration; a separate provenance row remains a possible follow-up. The invoice
workbook layout is supported as well as the master file.

**Corrections to the original analysis.** The earlier version of §5 described
18,085,468 as a stale total. That was not established; see the corrected table in
§5. Some layout statements had also been written after inspecting only the first
Material block; they are now checked against every block.

Authority: [`AGENTS.md`](../../AGENTS.md),
[`R39_ACCOUNTS_WORKSPACE_V2_INTEGRATION_PLAN.md`](R39_ACCOUNTS_WORKSPACE_V2_INTEGRATION_PLAN.md)
(§8.2, §8.3, §12, Appendix A row "Import Master File"),
[`PRODUCT_DECISIONS.md`](PRODUCT_DECISIONS.md) §32 (D2, D3, D4),
[`R39_ACCOUNTS_FOUNDATION.md`](R39_ACCOUNTS_FOUNDATION.md).

---

## 1. What it is, in one paragraph

From the prototype's own dialog: *"You upload the **Project Master File** (or the
last invoice workbook). The app reads the **Summary** sheet → contract value,
buildings and stage %; the **Material** and **Installation** sheets → item names,
quantities, units and weights; the **Invoice tracker** rows → invoices already
issued. You review a preview, fix anything, and confirm. Nothing is locked
afterwards."* In product terms, Import Master File is a guided way to **populate
the commercial setup** (contract value, building split, stages and items) from an
Excel workbook instead of typing it into the Contract form — ending in the same
place the Contract editor ends: a saved baseline revision via
`v1_save_project_commercial_setup`.

## 2. Scope boundary

**In scope**

- Parse an uploaded `.xlsx` **Project Master File** into a structured, editable
  **preview** of the commercial setup: contract value + currency + VAT, building
  allocations (%), stages (% + measurement mode), and the per-building item
  breakdown for items-mode stages (name, quantity, unit, weight-% of contract).
- Let the actor review and **edit** the preview, see the same setup-check
  validation the Contract editor shows (building Σ = 100%, stage Σ = 100%, item
  weights within tolerance), and **confirm** → a saved baseline revision.
- Record an **immutable provenance row** for the import (file name, sha256,
  extracted snapshot, and an `excluded` snapshot of anything not posted).

**Out of scope (do not pull in)**

- Importing **historical invoices, certifications, PDCs or payments** from the
  "Invoice tracker" sheet. That is the P9 / D12 path and is already handled by the
  one-off, service-role source-import migration
  (`20260828085441_yorks_r39_accounts_yra322_master_file_import.sql`). This slice
  imports **setup only**; the prototype's "Invoice tracker rows" bullet stays a
  later, separate decision.
- Multi-file / batch import, supplier-side imports, and any server-side XLSX
  parsing (parsing stays on the client — see §4).
- Auto-posting a claim. Import ends at a saved baseline; claims still go through
  the claim workbench.

## 3. What already exists to build on

| Need | Already in the repo |
|---|---|
| Confirm/persist a setup as a revision | `v1_save_project_commercial_setup` (§8.3); carry-forward (D2) and all invariants are server-enforced |
| Client-side XLSX read | `YorksV1BoqWorkbookCodec.decode(...)` in `lib/shared/services/yorks_v1_boq_workbook_service.dart` (pure-Dart `archive`/`ZipDecoder`), behind the existing `excel` feature flag |
| Client-side XLSX write (reference pattern) | `YorksAccountsReportService.buildExcel(...)` in `lib/features/accounts/data/accounts_report_service.dart` |
| Setup model + mirror validation | `commercial_setup_models.dart` (`YorksAccountsCommercialSetup`, `toSetupJson`, `validate()`), `commercial_setup_read_models.dart` |
| Items model | `v1_accounts_baseline_stage_items` + items-mode (§8.2); weight = % of contract |
| Immutable import provenance | `v1_accounts_source_imports` table (`source_type = 'excel_project_master'`, sha256 unique per project, `source_snapshot` / `excluded_snapshot` / `application_summary`, append-only guard) and `v1_accounts_billing_progress.confirmed_source_import_id` |
| Contract tab host + editor | `accounts_v2_contract_tab.dart` (`_ContractEditor`, setup-check panel, "How amounts are worked out") |

The important consequence: **the heavy pieces already exist.** The import is
mostly glue — parse → map → preview → reuse the setup save — plus a thin,
auditable server entry point.

## 4. Design

**Parsing stays on the client.** The app already decodes XLSX client-side
(`YorksV1BoqWorkbookCodec`); there is no server-side spreadsheet parser and
AGENTS forbids adding generic/untrusted parsing paths to trusted RPCs. So:

1. **Client parse** — a new `accounts` master-file parser (a small sibling of the
   BOQ codec, reusing its low-level sheet decode) turns the uploaded bytes into a
   `YorksAccountsMasterFileDraft`: contract header, buildings, stages, items, plus
   a list of **unmapped / ambiguous** rows (never silently dropped — AGENTS).
2. **Client preview + edit** — render the draft in the Contract tab with the
   existing setup-check validation and `needs_review` flags; the actor fixes
   anything inline. This is a preview only; nothing is sent yet.
3. **Confirm** — recommended path **(B)**: a thin new RPC
   `v1_apply_accounts_master_import(p_project_id, p_expected_profile_version,
   p_setup jsonb, p_source jsonb, p_idempotency_key)` that, in one transaction,
   (a) records a `v1_accounts_source_imports` row from `p_source` (file name,
   sha256, extracted + excluded snapshots), and (b) runs the **same setup-save
   logic** as `v1_save_project_commercial_setup` so every invariant (Σ building% =
   100, Σ stage% = 100, item-weight tolerance §8.2, carry-forward D2) is
   re-checked server-side and the baseline revision is linked to the import id.

   Rejected alternative **(A)** — confirm straight through
   `v1_save_project_commercial_setup` with no provenance row. Simpler, but loses
   the "where did this come from / what was excluded" audit trail that the
   existing `v1_accounts_source_imports` table is built for. (B) is preferred and
   only marginally larger.

**The server stays authoritative.** The client preview is a convenience mirror;
`v1_apply_accounts_master_import` re-validates everything and is the only thing
that writes. No optimistic success.

## 5. The master-file layout (confirmed from the real workbook)

Confirmed 7 November 2026 against `Project Master File - Nexus 4 Station.xlsx`
(Yorks Ref YRA-322). Sheet names and column positions:

**`Summery (Option)`** — the contract/buildings/stages source. Four per-building
blocks (A/B/C/D = DF3W, DF4W, DF6W, DF7W), then an **ALL PROJECT SUMMARY** block,
then an invoice tracker. All percentages are **fractions** (0.1 = 10%).

- Building block: col `B` = block letter; `C` = building name
  (`"132/22Kv Substation- (DF3W)"`); a `Contract Value` label row; a share row
  `D`=contract% (1), `E`=building% (0.25), `F`=building value; then five stage
  rows `B`=`A.1…A.5`, `C`=stage name, `D`=contract% (0.1/0.5/0.3/0.05/0.05),
  `E`=building×stage fraction, `F`=amount; a `TOTAL` row.
- **ALL PROJECT SUMMARY** (rows ~49–58): `D`=`CONTRACT VALUE`, `F`=total contract
  value; five stage rows with `D`=contract%, `E`=project%, `F`=amount; `TOTAL`.
- Invoice tracker (rows ~60–66): labels in `D`, one column group per invoice
  (`H/K/N/Q/T`): `Invoice Ref. No.`, `Amount W/O VAT`, `Submission/Approved/Due/
  Paid Date`, `Delay (days)`, note `45 days PDC`. (Tracker is out of scope — §2.)
- Stage names → keys: `Cooling Load Design`→design, `Material Supply`→
  material_supply, `Progress Installation`→installation, `Comissioning &
  Handover` (sic)→commissioning_handover, `Energizing Substation`→energizing.

**`Material  `** (trailing spaces) and **`Installation`** — the items source.
Per-building blocks (`DELIVERD MATERIAL SUMMARY (DF3W)` …). Header row (row 5):
`B`=`Item`, `C`=`Description`, `E`=`Total Qty.`, `F`=`WEIGHT`, `G`=`Contract`/
`Amount`. A block total row (`G`=total contract value) and a stage row
(`C`=`Material Supply`/`Installation`, `F`=stage fraction, `G`=amount). Item rows:
`B`=item no (`A.1`), `D`=item name (`AC Units (Package Unit)`), `E`=Total Qty,
`F`=`WEIGHT` = **fraction of total contract** (0.045 = 4.5%), `G`=amount
(= contract × weight). Sub-rows (`A.1.1 System-01`) carry only a qty breakdown
in `E`, no weight.

Further layout facts, verified across all four blocks of both sheets:

- Some weights sit on sub-rows: `A.10 Ducting works` has qty `Lot ` and no weight,
  and `A.10.1…A.10.5` carry the weights. With them, each block sums to the stage
  share (12.5% and 7.5% per building).
- Numeric cells are Excel's raw text, for example `4.4999999999999998E-2`.
- Installation headers read `(A) MATERIAL INSTALLATION SUMMARY  (DF3W)`; the code
  is the last bracket, not the first.
- In the master file's DF4W, DF6W and DF7W Installation blocks one number repeats,
  shifting later numbers by one. The items match DF3W, so blocks are compared by
  content.
- The invoice workbook adds a `Units` column, which moves `WEIGHT` and `Contract`
  one column right, so item columns are found from the header row.

**The contract value differs between sources, and the cause is not known.**

| Date | Source | Total contract value |
|---|---|---|
| 29 Aug 2026 | Master file as reconciled ([record](R39_YRA322_MASTER_FILE_RECONCILIATION.md), `F52`) | 17,192,000 |
| 26 Sep 2026 | Master file, `F52` (`F40` still 17,192,000) | 18,085,468 |
| 29 Sep 2026 | Invoice `YRA32202R.1` | 17,192,000 |
| 23 Oct 2026 | Master file, `F52` (`F40` still 17,192,000) | 18,085,468 |

The 893,468 difference has no explanation in the workbook (no VO or amendment
reference). The owner chose 17,192,000 on 7 November 2026 and reconfirmed it the
same day with this timeline in view (`PRODUCT_DECISIONS.md` section 29). The importer does not hardcode either: it
proposes the project's current value, shows the workbook's beside it, and a person
confirms the figure. Item weights and quantities match between the two workbooks,
so only the top-line value is affected.

## 6. UI

In `accounts_v2_contract_tab.dart`, gated by `configure_project_commercials`
(D1) and `view_project_commercial_values`:

- An **Import Master File** button near the Contract header (prototype placement).
- A dialog/flow: **upload** (`.xlsx`, bytes) → **parsing** → **preview** (contract
  value, buildings %, stages %, item tables) with setup-check badges and
  `needs_review` chips on unmapped/ambiguous rows → inline **fix** → **Confirm**.
- After confirm the Contract tab refreshes to the new revision; **nothing is
  locked** — the existing Contract editor still edits it.
- Strings through `accountsV2Text` in EN + the secondary languages.

## 7. Security, invariants, provenance

- Capability: `configure_project_commercials` (server-checked), commercial-gated.
- Server re-checks every setup invariant; idempotency key; `sha256` unique per
  project (existing constraint) makes a re-upload of the same file a safe no-op /
  conflict rather than a duplicate.
- Append-only provenance; `excluded_snapshot` records anything not posted
  (AGENTS: "never silently discard … quarantine and report").
- No optimistic success; a stale `p_expected_profile_version` returns a conflict.

## 8. What remains

- Exercise the live file picker in a browser with the real workbook.
- Optional: a dedicated provenance row in `v1_accounts_source_imports`, if the note
  on the baseline revision proves insufficient for audit.
- Importing the invoice tracker rows stays out of scope (§2).

## 9. Testing gate (standard, per AGENTS)

`flutter analyze`, `flutter test test/yorks_r39_accounts_v2_*`,
`supabase db reset && supabase test db`, and the R35 web/apk build lanes. UI
evidence at desktop and 360px. Positive + negative role tests for the new RPC.

## 10. Does not touch

The YRA-322 historical source-import migration stays the authoritative historical
path and is not reopened. No change to claims, invoices, supplier bills, the
Accountant office, or any non-Accounts module. The V2 flag stays as-is.
