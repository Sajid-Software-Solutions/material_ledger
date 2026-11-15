# Contract materials — the invoice's lines in the BOQ and under Accounts

Status: **approved 15 November 2026** (owner, "Approve as recommended");
decision record [`PRODUCT_DECISIONS.md`](PRODUCT_DECISIONS.md) section 61.
Built behind the default-off flag `YORKS_V1_CONTRACT_MATERIALS`.

## What it answers

"For each building, which materials does the contract (and the invoice) list,
what is each worth, and how far is each one delivered, installed and
invoiced?" — in the BOQ for the engineers who request the material, and under
Project › Accounts for the people who bill it.

## Source

The signed tax invoice YRA32202R.1 (29 September 2026), attached to YRA-322,
prints a "Delivered material summary" per building (DF3W, DF4W, DF6W, DF7W):
the same 15 lines in each, numbered A.1 … A.11 with Ducting works A.10.1 …
A.10.5 by floor, each with total quantity, unit, weight (% of contract) and
contract amount. Those lines were already in Accounts as the items of the
Material Supply and Installation stages (Workspace V2 D3, imported from the
invoice workbook on 8 November 2026). Nothing in this feature re-enters a
quantity or a price: the BOQ sheet is built from the Accounts lines.

## The model

| Piece | What it is |
|---|---|
| Contract line | A building's item of an item-measured stage, keyed by building and `item_key` (stable across contract revisions). The same key in Material Supply and Installation is one line in two stages. |
| Contract Materials sheet | One BOQ folder per physical building: Ref, Description, Qty, Unit, one row per line, in invoice order and numbering. Non-commercial. |
| Tie (`v1_accounts_material_boq_row_links`) | "This BOQ row is that contract line." One row per line and building, one line per row. Configuration only. |
| Folder link (`v1_accounts_material_boq_links`, 20261107160000) | "This whole folder stands for that line's Material Supply." Kept for detailed folders such as DF3W's VCD sheet. A folder holding a tied row cannot also be linked as a whole. |

### States

| Stage | From confirmed quantity |
|---|---|
| Material Supply | Not delivered → Part delivered → Delivered |
| Installation | Not started → Installing → Installed |

Billing, per stage, for those who may see values: **Ready to invoice** (more
confirmed than invoiced), **Invoiced** (with the invoice reference and its
own status: submitted, certified, paid …), or **Invoiced above confirmed** when
a confirmation was lowered after billing. "Invoiced" quantity is the quantity
as it stood when the latest invoiced claim was checked — the invoice's own
"to date".

"On site" is a guide: good quantity on confirmed receipt reviews of Material
Requests raised from the tied row or a linked folder, less confirmed returns
(the same reading as the claim workbench's site deliveries). Earlier
deliveries made with typed rows are not traced back; they are already in the
confirmed quantities.

What moves a line: the Project Engineer (or Admin, Senior Mechanical
Engineer, Project Manager, Workshop In-Charge, Document Controller) confirms
delivered or installed quantity on Progress & claims with evidence; a Site
Engineer suggests. Claims, invoices, certification and payment are unchanged.

### Prices

A line's amount is its share of today's contract (`v1_accounts_stage_item_value`,
largest remainder to the fil), its rate the amount divided by the quantity,
rounded to the fil for display. A part quantity is worth amount × part ÷
quantity, as the invoice computes it (20 of 55 dampers). Work billed before a
contract correction keeps its billed amounts; the next claim carries the
difference as a contract value correction (section 35), shown on the tab as
"Not yet invoiced · Contract value correction".

## Who sees what

| Role | Accounts › Materials | BOQ › Contract Materials |
|---|---|---|
| Admin, Project Engineer on the project, SME, PM, WIC, DC | Lines, prices, states | Lines, rate and amount, requested, received, delivered, installed |
| Accountant | Lines, prices, states | No BOQ (as before) |
| HR/PRO | Lines, prices, states, read-only (section 37 Accounts reading) | As the Accountant column of Accounts, read-only |
| Site Engineer on the project | Lines, quantities, states; no prices | Requested, received, delivered, installed; no prices |
| Procurement | No project Accounts (as before) | Requested and received only |

The server decides, never the screen: money, weight and invoice fields are
absent from the JSON for a caller without `view_project_commercial_values`,
and Accounts quantities are absent without `view_project_accounts`.

## Server contract

Migration `20261115120000_accounts_contract_materials.sql`:

- `v1_accounts_material_boq_row_links` — the ties; RLS on, no client grants.
- `v1_accounts_material_delivered(project)` — internal; the site-delivery
  reading of 20261107160000 with tied rows added (Material Supply only).
- `v1_accounts_contract_line_facts(project)` — internal; every line with value,
  confirmed and invoiced quantity and last invoice.
- `v1_get_accounts_material_register(project)` — the Accounts tab's read.
- `v1_get_boq_contract_status(group)` — the BOQ sheet's status read.
- `v1_save_accounts_material_row_links(project, ties, reason, key)` — replaces
  a project's ties; `configure_project_commercials`, idempotent, audited.
- `v1_get_accounts_material_sources` now also counts tied rows, stops offering
  a folder that holds one, and lists the ties; `v1_save_accounts_material_boq_links`
  refuses such a folder.

pgTAP: `yorks_accounts_contract_materials.test.sql` (positive and negative per
role, money-key absence, double-count guard, replay, audit, revision, grants)
and `yorks_r39_accounts_v2_material_links.test.sql` (its return fixture now
carries `basis_kind`, which the constraint requires).

## Client

- Model: `lib/features/accounts/domain/v2/material_register_models.dart`
  (also the invoice-style numbering, `yorksAccountsSheetRows`).
- Repository / controller: `getMaterialRegister`,
  `yorksAccountsMaterialRegisterControllerProvider`.
- Tab: `lib/features/accounts/presentation/v2/accounts_v2_materials_tab.dart`,
  route `/yorks/projects/:projectId/accounts/materials`; tab hidden and the
  link falls back to Summary while the flag is off.

## Rollout

1. Read-only preflight `supabase/preflight/contract_materials_preflight.sql`.
2. Bundle `supabase/release/contract_materials_bundle.sql` (staging, then
   production, each with the owner's OK). Rollback
   `supabase/release/contract_materials_rollback.sql` restores the two
   replaced functions exactly and drops the new ones; the ties stay.
3. Web built with `YORKS_V1_CONTRACT_MATERIALS=true` beside the other
   production flags.
4. YRA-322 data: see the data script section (added with that PR).
