# Material Return overhaul — plan (4 November 2026)

Status: proposed on `feature/material-return-overhaul`. Not implemented.

## Problems found (production data, 3 November 2026)

| Problem | Evidence |
|---|---|
| Deployed material cannot be returned | Only receipt-confirmed lines are eligible: 476 of 1,143 dispatched lines (42%). YRA-313: 107 of 230. |
| One row per delivery, not per material | Returning 10 pipes delivered in 3 dispatches needs 3 rows, identified only by MR/dispatch numbers. |
| Strict building filter | Candidates only for the selected scope; material moved on site cannot be returned. |
| Missing fields | 1,547 of 1,891 request lines (82%) carry a size; return candidates, lines, Excel and PDF carry no size, model or equipment tag. |
| No search or autocomplete | Flat table of up to 230 rows; custom rows are plain text fields. |
| Slow screen | Server candidate query is 8–39 ms on production; the editor builds every candidate row with its own TextField in a Material `DataTable` inside one eager `ListView`, and rebuilds it on every scope change or custom row. |
| Depth vs Material Requests | No guided composer, MR grid, mobile focused editor, draft recovery, discussion, history or next-action guidance. |

## Product decisions

1. **Dispatched-but-unconfirmed material is returnable** (product owner, 3 November 2026).
   - Returnable from a dispatch line = basis − quantity on active returns
     (awaiting approval, approved, dispatched, confirmed).
   - Basis = confirmed good received quantity when a confirmed receipt review exists,
     otherwise the dispatched quantity.
   - Each return line records which basis applied (`received` or `dispatched_unconfirmed`).
   - Invariant protection: a later receipt review of a dispatch line cannot record a
     good quantity below what is already on active returns from that line; the
     reviewer is told to reduce or cancel the return first.
   - Warehouse confirmation is unchanged: stock only increases when Procurement
     records good returned quantity.
2. **Consistency with Material Requests**: the return composer reuses the MR line
   editor (`YorksV1MaterialItemsEditor`, `YorksV1MaterialDescriptionField`) exactly as
   the Company Material Request screen already does.

## Design

### Server (additive migration + tests)
- `v1_material_return_item_candidates(project, scope?, search?, return?)`: delivered
  material **grouped per material** (normalized description + size + unit), with item
  code, brand, model, equipment tag, total returnable, and the underlying dispatch
  lines; trigram search like the Material Summary; all buildings by default.
- Save draft accepts either per-dispatch-line quantities or a material key + quantity,
  which the server allocates across that material's dispatch lines (most recent
  delivery first) under row locks.
- Return lines gain `size`, `model`, `equipment_tag`, `basis_kind`; delivered lines
  anchor on `dispatch_line_id`, with `receipt_review_line_id` optional.
- Submit/confirm re-check the new eligibility rule under the same locks and
  idempotency keys; a trigger on `v1_receipt_review_lines` enforces the receipt guard.
- Detail/list projections, Excel and PDF include size, model and equipment tag.

### Screens (mirror the Material Request draft screen)
- Same page header, project/scope context card, stepper and sticky actions as the MR draft.
- Step 1 **Material**: search-first picker over delivered material with autocomplete,
  grouped rows (description · size · code · returnable), virtualized list; MR-style
  "add custom item" with the MR autocomplete.
- Line grid: the MR editor with an additive per-field lock (description/size/unit locked
  on delivered lines) and an "available" hint; mobile uses the MR focused one-row editor.
- Step 2 **Logistics & purpose**, Step 3 **Review**: same review layout as MR.
- Detail screen: MR-style summary, status, next action, history and line table with size/model.

### Performance targets
- Composer interactive < 1 s on YRA-313 after data arrives; typing and filtering
  without dropped frames; candidate list lazily built.

## Verification
pgTAP for eligibility (received vs unconfirmed), allocation, receipt guard, idempotency,
competing writers and role access; Flutter tests for the composer, grid locks, picker,
mobile editor and exports; desktop/360 px/Arabic visual evidence.
