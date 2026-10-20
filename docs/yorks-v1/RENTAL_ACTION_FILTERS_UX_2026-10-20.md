# Rental action filters and field shortcuts — 20 October 2026

The owner approved the two follow-up recommendations from
[the rental navigation release](RENTAL_NAVIGATION_UX_2026-10-20.md):
filter actions by issue type and open the editor at the relevant fields.

## Delivered behavior

- Action required offers All actions, Rent, Cheques, Leases, Billing setup and
  Missing details, with counts of matching properties. A property may match
  multiple filters. Each row shows and opens the selected kind of issue,
  including a secondary issue that was not its original highest priority.
- The selected filter belongs to the dashboard state, so it survives opening
  a property, returning with Back and switching dashboard sections. Changing
  the filter resets the six-row preview. Empty results explain the selected
  filter and offer Show all actions; the full register stays available.
- Complete details opens the existing editor at the first known missing field.
  The persistent Go to field selector links the other missing fields. Lease
  review starts at Lease End, with Lease Start and Contract No. available.
  Billing setup starts at the explicit first rent date and preserves its
  historical-balance warning.
- Shortcuts expand the relevant group, reveal and highlight the control, and
  move focus away from the previous input without opening a phone keyboard.
  Switching fields keeps unsaved edits. Cancel and the existing explicit
  versioned/idempotent Save path retain their behavior.
- New controls are localized in English, Arabic, Urdu and Hindi. Both office
  and phone layouts use the same labeled selector. The editor materializes its
  bounded form so offscreen field anchors are available without guessing
  scroll offsets.

This is presentation-only. Models, repositories, RPC/RLS, rental financial
rules, source evidence, notification transport and other modules are unchanged.
No records are imported, updated or reclassified by a filter or shortcut.

## Verification

The actual-router journey suite covers overlapping filter counts, the correct
selected-action destination, filter preservation on Back, empty/reset behavior,
collapsed groups, retained draft text, Cancel, billing/lease targets and Arabic
at 1.3 text scale. New visual baselines include desktop and 360px action filters,
contact-field review, phone billing review and Arabic phone review.

## Completed gates and live release

- `flutter pub get`, changed-file formatting, full `flutter analyze` and
  `git diff --check` passed. The final full Flutter suite passed **2,882 tests**
  with four existing skips. The final actual-router suite passed its
  **14 navigation/review scenarios**.
- CI web and APK builds passed. The APK uses ephemeral CI signing and is not
  an Android distribution artifact.
- An isolated database reset and the full pgTAP suite passed **4,876 assertions
  across 143 files**. The audit project was stopped with its backup retained;
  the primary local database was untouched.
- Production was built from clean implementation commit
  `adb3576f3d6a9c19645b5567155dcb982c3b4466`. The main bundle measured
  9,965,866 bytes, with 2,872,753 gzip bytes reported by the startup gate.
  Its SHA-256 is
  `ae10a76f4a66fec627980d1b15beb35a9495ca94b275be4f41dca3a5efca0472`.
  The artifact retained the existing production backend configuration and
  passed the reviewed main-bundle credential and environment checks.
- Staged deployment `dpl_B96grAdqY4GbnnG72eJj1c8xBDLv` passed all **34 route
  and asset hash checks** before promotion. The canonical site passed the
  same checks and resolves to that exact READY production deployment:
  <https://yorks-r35.vercel.app>.
- Live signed-in Chrome verification selected Missing details (52), opened
  `OFFICE-AC1-2`, and confirmed the selected missing-detail reason appeared
  first. Complete details opened the editor at Site location. Go to field
  moved to Contact number, with the field visible, focused and highlighted.
  Cancel closed the editor without saving. The workspace header Back returned
  to the overview with Missing details (52) still selected.
- Desktop, 360px/mobile, Arabic at 1.3 text scale, billing/lease targets,
  collapsed groups, retained draft edits and empty-filter reset are covered
  by the automated journey and visual checks. Physical mobile-device and new
  push-delivery acceptance were outside this presentation change.

The [release record](evidence/rental-action-filters-20261020/release.json),
[artifact measurements](evidence/rental-action-filters-20261020/artifact.json),
[candidate hashes](evidence/rental-action-filters-20261020/verify-candidate.jsonl)
and [canonical hashes](evidence/rental-action-filters-20261020/verify-canonical.jsonl)
retain the release evidence. The primary checkout and rental business records
were not changed.

## Rollback

Promote the prior retained deployment `dpl_JCnBZWcMEKVy633C1gFNyCqXzry6`.
No database rollback or notification replay is needed.
