# Authenticated direct navigation / fresh Create evidence

Final staging source: `2546f9207138eee1ee6d77581e8f049f60cb4cd5`.
Deployment: `dpl_48uDaRkz5M3WBzmQn4BYUQEFMiYJ`.

These are native JPEG browser captures, preserved without image editing.
Desktop captures are 1456×787; mobile captures are a fresh 360×900 CSS / DPR 1
session. They show authenticated Local Admin UI, not a synthetic visual fixture.

- [Explicit ownership guard](confirmed-history-ownership-desktop.jpg)
- [Fresh Create after confirmed history](fresh-create-desktop.jpg)
- [Pending files preserved after retirement](pending-files-after-retirement-desktop.jpg)
- [Fresh mobile Create](fresh-create-mobile-360.jpg)
- [Mobile lower fields and sticky actions](fresh-create-mobile-360-bottom.jpg)
- [Before-retirement recovery](pending-files-before-retirement-desktop.jpg),
  captured on the superseded first preview `45367b48` before the live ownership
  trap was corrected. It is preservation comparison evidence, not final release
  acceptance.

Takeover was an explicit local UI action. No final Create/Update, activation,
upload, pending-file removal, team access or backend mutation was used. Exact
core-receipt and pending-file-manifest hashes match before/after retirement.
The original project edit draft and the user's BOQ tab remain preserved.

The mobile session had no captured console warnings/errors. Desktop captured
one bundled-font fallback warning. These fresh sessions do not close the
previously documented accessibility-enabled breakpoint resize issue. Viewport
overrides were reset after inspection.

See the [release report](../../DIRECT_PROJECT_NAVIGATION_2026-10-04.md) and
[machine evidence](../../DIRECT_PROJECT_NAVIGATION_2026-10-04.json) for hashes,
command/test results and unrun acceptance lanes.
