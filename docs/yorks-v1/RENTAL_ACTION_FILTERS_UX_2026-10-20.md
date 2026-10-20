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

Full gate and production results are appended after verification.

## Rollback

Promote the prior retained deployment `dpl_JCnBZWcMEKVy633C1gFNyCqXzry6`.
No database rollback or notification replay is needed.
