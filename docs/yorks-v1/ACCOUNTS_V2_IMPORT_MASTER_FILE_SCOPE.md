# R39 Accounts Workspace V2 — Import Master File scope

Status: **scoped, not started.** This is the one remaining prototype feature in
the per-project Accounts workspace that is not yet built. Unlike the claim
workbench and invoice-revise slices (which were UI-only on top of existing
RPCs), Import Master File needs new work on both sides and one owner decision,
so it is written up here before implementation.

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

**Owner decision / stop condition — the contract value conflicts across the two
source documents.** The parser's acceptance target cannot be fixed until this is
resolved by the owner:

| Source | Total contract value | AC Units (4.5%) | DF3W Material Supply |
|---|---|---|---|
| **This master file** (Summery `F52`, Material `G7`) | **18,085,468** | 813,846.06 | 2,260,683.50 |
| **Signed invoice** `INVOICE#02R.1` / plan §12 | **17,192,000** | 773,640.00 | 2,149,000.00 |

The two differ by 893,468. The master file is self-inconsistent too: every block
uses 18,085,468 **except** the DF7W block header (`F40` = 17,192,000) — the only
place 17,192,000 appears in it. So the plan §12 fixtures (17,192,000-based) were
taken from the **invoice** workbook, not this master file, and will **not**
reproduce from it.

Decisions needed before S1:
1. **Which contract value is authoritative** for the baseline the importer sets —
   18,085,468 (master-file summary) or 17,192,000 (signed invoice / §12)?
2. The importer must **flag** internal inconsistencies like the DF7W stray as
   `needs_review` rather than silently pick one (AGENTS: never reinterpret or
   silently omit). Confirm that behaviour is wanted.

The column map above is settled; these value questions are the remaining S0 gate.

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

## 8. Phasing (sub-slices, one vertical slice per PR)

| Slice | Scope | Gate |
|---|---|---|
| **S0** | Layout confirmed (§5). Owner resolves the contract-value conflict (18,085,468 vs 17,192,000) and confirms needs_review flagging | authoritative value chosen |
| **S1** | Client master-file parser + `YorksAccountsMasterFileDraft` model | unit tests reproduce the chosen-base numbers from the real sample; the DF7W stray and any unmapped rows surface as needs_review, none dropped |
| **S2** | Preview UI in Contract tab (read + editable), behind the existing V2 flag | widget tests desktop + 360px; setup-check + needs_review render |
| **S3** | `v1_apply_accounts_master_import` RPC (provenance + setup save) | pgTAP: invariants, idempotency/replay, sha256 uniqueness, role negatives (PE/SE/Procurement denied; Admin/PM/SME allowed) |
| **S4** | Wire Confirm → apply; end-to-end; owner sign-off | §12 totals reproduced through the real save; nothing locked afterwards |

Estimate ≈ **4–6 engineer-days** after S0, the import-dialog subset of plan P2.

## 9. Testing gate (standard, per AGENTS)

`flutter analyze`, `flutter test test/yorks_r39_accounts_v2_*`,
`supabase db reset && supabase test db`, and the R35 web/apk build lanes. UI
evidence at desktop and 360px. Positive + negative role tests for the new RPC.

## 10. Does not touch

The YRA-322 historical source-import migration stays the authoritative historical
path and is not reopened. No change to claims, invoices, supplier bills, the
Accountant office, or any non-Accounts module. The V2 flag stays as-is.
