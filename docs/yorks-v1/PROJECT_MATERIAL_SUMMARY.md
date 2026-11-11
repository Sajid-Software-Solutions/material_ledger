# Project Material Summary — 3 November 2026

Status: implemented on `feature/project-material-summary`. Local Flutter gate
passed on 3 November 2026; pgTAP database tests run in CI. Not deployed; the
migration has not been applied to staging or production.

## What it answers

"How much of each material was requested for, and sent to, this project?" —
overall, per calendar month and per Monday–Sunday week, shown together, with
the Material Requests that carried each material as links.

It lives in the project workspace **Material Movement** tab as the default
**Summary** view. The existing chronological dispatch/return list is unchanged
and remains available as **Register**.

## Frozen rules (product owner, 3 November 2026)

| Rule | Behaviour |
|---|---|
| Date basis | The Material Request submission date, in Asia/Dubai |
| Week | Monday to Sunday (weekend included) |
| Requested | Submitted, non-cancelled requests; drafts never count |
| Sent | Every committed dispatch line, including lines dispatched before a later cancellation |
| Returned | Confirmed returns only (good received quantity when recorded) |
| Grouping | Case- and whitespace-insensitive description + unit. Different spellings are **never merged** |
| Search | Substring on description, MR number, brand and item code, plus trigram word similarity ≥ 0.5 so close spellings ("Aluminium Tap") appear next to the correct one |
| Filters | Building/Common scope, date range presets (this week, this month, last 3 months, this year, custom), search |
| Percentages | *Sent of requested* = sent ÷ requested. *Share of item total* = the period's requested quantity ÷ that material's total under the current filters (falls back to sent when nothing was requested). Ratios never mix units |
| Exports | Excel (Overall, Monthly, Weekly sheets with numeric cells), Export PDF and in-app View PDF — always exactly the filtered result |
| Commercial | None. No cost, rate, supplier or valuation field exists in the response or exports |

## Server contract

`public.v1_project_material_summary(p_project_id uuid, p_from date,
p_to date, p_scope_id uuid, p_search text) returns jsonb`

- Security definer, `search_path = ''`, `jit = off`. JIT was measured at
  ~1.4 s of compile time on a ~40 ms query because the grouped CTEs inflate
  planner estimates.
- Access is exactly `v1_project_readable`: assigned Project/Site Engineers,
  Procurement on active/on-hold projects, Admin and organization-wide
  engineering roles. Unassigned actors receive `42501
  V1_PROJECT_MATERIAL_SUMMARY_DENIED`; a foreign scope, inverted range or
  search over 120 characters receive `22023 V1_PROJECT_MATERIAL_SUMMARY_INVALID`.
- Compact response: `requests` and `items` are sent once; `months` and
  `weeks` rows are `[period_start, item_index, requested, sent, returned,
  [request_index…]]`. Quantities are exact decimal strings.
- Measured locally (Postgres 16, 2,000 requests / 12,000 lines / 2 years):
  80–150 ms filtered, ~435 ms unfiltered with a 1.2 MB response.

Migration `20261103130000_project_material_summary.sql` is additive: one
partial index on `v1_material_return_lines (request_line_id)` and the
function. Rollback is forward-only: revoke/drop the function and index in a
corrective migration; no data changes.

## Client

- Model: `lib/shared/models/yorks_v1_project_material_summary.dart`
- Copy (en/ar/ur/hi): `lib/shared/models/yorks_v1_material_summary_strings.dart`
- Repository: optional `YorksV1ProjectMaterialSummaryRepository` in
  `yorks_v1_logistics_repository.dart` (existing test fakes are unaffected)
- Provider: `yorksV1ProjectMaterialSummaryProvider` (refreshes on realtime
  workflow revisions)
- Exports: `lib/shared/services/yorks_v1_material_summary_document_service.dart`
  (uses the shared controlled-document letterhead)
- UI: `lib/features/projects/presentation/widgets/yorks_v1_project_material_summary_panel.dart`

Performance: rows are built in batches of 50 ("Show more"), period rows are
built only when a period is expanded, the previous result stays visible with
a thin progress bar while a new filter loads, and search is debounced 350 ms.

## Verification

- Local Postgres harness against the exact column shapes: grouping, spelling
  separation, Dubai date boundaries, Monday weeks, cancellation, draft
  exclusion, confirmed-only returns, item codes, every filter, LIKE-wildcard
  escaping, denial paths and anon/authenticated grants.
- `supabase/tests/database/yorks_v1_project_material_summary.test.sql`
  (22 pgTAP assertions, PE/SE/Procurement/Admin positive, unassigned/foreign
  scope/anonymous negative) — runs in CI.
- `test/yorks_v1_project_material_summary_test.dart` and
  `test/yorks_v1_project_material_summary_panel_test.dart` — model, calendar,
  labels, Excel package, desktop/360 px/Arabic layouts, filters, links,
  states and export.

Local results (Flutter 3.47.5 / Dart 3.13.4, macOS, 3 November 2026):
`dart format` clean, `flutter analyze` no issues, the 32 new tests pass, and
the full suite reports 2,929 passed / 4 skipped / 1 failed. The single failure
is the pre-existing `yorks_v1_rental_test.dart` R38.4 property-register golden
(0.21% pixel diff), which already had failure artefacts on 22 September 2026
and is unrelated to this change. Desktop, 390 px and Arabic renders plus a
sample Excel/PDF were inspected; the Excel opens with numeric cells, a frozen
header and filters.

Known limitation shared with every existing Excel export in the app: saving
uses `file_selector` save dialogs; PDF export uses the system share sheet.
