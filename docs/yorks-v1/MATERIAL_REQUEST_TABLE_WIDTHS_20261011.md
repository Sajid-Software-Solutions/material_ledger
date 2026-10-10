# Material Request table readability — 11 October 2026

## Correction

Material Items previously assigned only 58 logical pixels to Unit. Quantity
history assigned 54–86 pixels to each quantity/unit column while giving all spare
width to Item. This split words such as Cylinder despite available desktop space.

- Material Items quantity and unit columns now grow to their intrinsic content
  width, with minimum widths retained.
- Quantity history measures each quantity/unit column, keeps at least 200 pixels
  for Item, and gives Item the remaining space.
- Arrangement summary requested/arranged quantities use the same content-based
  sizing rather than fixed 90/94 pixel caps.
- Existing horizontal scrolling handles constrained desktop views. Mobile cards,
  editing, quantities, workflow and controlled document exports are unchanged.

## Verification

The operational route fixture now uses Cylinder and checks rendered text boxes
for single-line quantity/unit values in both affected desktop tables. Desktop
1366px and mobile 360px snapshots accompany the existing responsive checks.
No backend, permission, migration or production deployment is part of this slice.

Final gates: full analyzer clean, all 2,690 Flutter tests passed (four retained
skips), focused operational layout checks passed (12), formatting and diff checks
passed. CI web and ephemeral-signed APK builds passed; the APK is a compatibility
artifact, not a signed production distribution. Updated affected desktop/tablet
screenshot baselines; visually inspected the Cylinder fixture, partial dispatch
and 360px mobile layout. Database gates are not applicable to this UI-only change.
