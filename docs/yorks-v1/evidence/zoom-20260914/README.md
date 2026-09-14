# Yorks workspace zoom evidence — 14 September 2026

Status: **implemented, locally verified and deployed to dedicated staging;
physical-device/platform matrix remains outstanding.** No production release
was performed.

## Result

- Browser builds use Yorks' fixed-layout workspace transform for familiar
  keyboard, modified-wheel and trackpad/touch pinch input. Magnification does
  not change Flutter constraints, breakpoints or shell geometry.
- Native builds use focal-point inspection zoom from 100% through 400% with
  touch pinch, trackpad pinch/pan, Ctrl/Command-wheel, keyboard shortcuts,
  middle-button pan and Space plus primary-button pan.
- The former bottom-right control is absent. Accessible native Zoom in, Zoom
  out and Reset zoom actions live in the existing account menu/drawer.
- A bounded in-memory route history restores an inspected native page during
  the same authenticated session and is discarded when identity changes.
- Embedded PDF previews own their gestures and cannot also zoom the workspace.
- System text scaling, business state, drafts, exports and server authority are
  unchanged.

## Automated evidence

- `flutter analyze`: passed, no issues.
- `flutter test`: passed, 1,715 tests.
- `flutter test test/yorks_workspace_zoom_test.dart
  test/yorks_v1_workspace_shell_test.dart`: passed, 31 tests.
- Chrome-platform zoom ownership widget test: passed, 1 test.
- `node --test tool/yorks_browser_zoom_test.mjs`: passed, 2 tests.
- CI-configured `./tool/r35.sh build-web`: passed; startup budget passed.
- CI-configured `./tool/r35.sh build-apk`: passed; release APK generated with
  ephemeral CI signing, not a production-signed artifact.
- CI-configured `./tool/r35.sh build-macos`: passed; local release app generated
  for build verification. Distribution signing was not verified.

Focused coverage includes two-finger touch pinch/pan, trackpad pinch/pan,
pointer-centred modified-wheel zoom, keyboard and reduced-motion handling,
ordinary/Shift-wheel behavior, single-finger scrolling while magnified, mouse
panning, bounds, reset, focus visibility, form/dropdown preservation, route
restoration, identity isolation, PDF-viewer isolation and menu access at 1366px
and 360px.

## Browser witness

Chrome 152 on macOS loaded the corrected staging build without a reported
browser error. At an emulated 360 by 800 mobile viewport, the Flutter layout
remained 360 by 800 while the workspace content was composited at 200% and
then reset to 100%.

| State | Browser scale | Layout width | Flutter view | Workspace scale |
|---|---:|---:|---:|---:|
| Initial | 1.0 | 360 | 360 by 800 | 100% |
| Magnified | 1.0 | 360 | 360 by 800 | 200% |
| Reset | 1.0 | 360 | 360 by 800 | 100% |

This proves magnification without browser page scaling or a responsive-layout
switch. Browser defaults are prevented only for zoom shortcuts and modified
wheel input; those events continue to Flutter's workspace handler, while
ordinary keyboard and wheel input remains untouched.

## Dedicated staging release

- Source commit: `0ea4f689e2a175a520b66420f7e29070bd6b5ab7`.
- Vercel deployment: `dpl_A6PJocysCWtxXLYtxvST9vwQ7fmh`.
- Immutable preview:
  `https://yorks-r35-i964xnknw-sajid-alis-projects-0ec775a2.vercel.app`.
- The staging database preflight reported no pending migrations. No database or
  Edge Function mutation was required for this UI-only slice.
- The compiled bundle contains the dedicated staging project reference once,
  and contains the production project reference and CI placeholders zero times.
- Seventeen root, deep-route, PWA and JavaScript checks byte-matched the local
  artifact. `main.dart.js` SHA-256 is
  `d919ecca9f82f3f7150a83fea14ee2dce62090b9f856676127a21161ddcc7b2d`.
- A fresh browser smoke check rendered the Flutter view with the scalable
  viewport and `pinch-zoom` touch policy, with no overlay or reported browser
  error.
- Production remained on deployment `dpl_EFMtEEvZrhMcjttQbSFQZCXjzV6y`;
  its alias response retained the pre-release ETag and byte length.

### Corrected fixed-layout browser preview

- Source commit: `78493fdc10e81901290bcfd23d606d58940abceb`.
- Vercel deployment: `dpl_txqbxTN7HF5HES7X4wDiCRYPXvca`.
- Immutable preview:
  `https://yorks-r35-8ceupuu5n-sajid-alis-projects-0ec775a2.vercel.app`.
- Seventeen root, deep-route, PWA and JavaScript checks byte-matched the local
  artifact. Corrected `main.dart.js` SHA-256 is
  `2a7f56bd1655d35ec99e8d5afa073a1410131a2dfdd1795d54c41dc762c2d475`.
- Live Ctrl-plus browser verification retained browser scale `1.0`, window and
  Flutter-view dimensions `1280 by 633`, and showed no error overlay. The
  Chrome-platform widget test separately proved that the workspace content
  transformed while retaining its original layout constraints.
- The production deployment and alias remained unchanged.

The eight changed 1366px goldens differ only in the former control footprint:

- `test/goldens/r35/engineer_overview_desktop.png`
- `test/goldens/r35/procurement_overview_desktop.png`
- `test/goldens/r35/admin_overview_desktop.png`
- `test/goldens/r35/audit_workspace_desktop.png`
- `test/goldens/r35/senior_mechanical_overview_desktop.png`
- `test/goldens/r35/material_request_approval_header_1366x768.png`
- `test/goldens/r35/senior_user_management_nav_desktop.png`
- `test/goldens/mobile_touchups/user_management_1366x768.png`

Existing 360px visual baselines remained unchanged because the floating control
was already hidden at phone width.

## Data preservation and rollback

There is no migration, backend, authorization, record, cache or export change.
Rollback is the code-and-golden revert of this slice. No data operation is
required.

## Remaining release evidence

- Real trackpad/mouse checks in Chrome and Edge on Windows and macOS.
- Physical iOS and Android pinch, system magnifier and screen-reader checks.
- Native Windows and signed macOS release checks where applicable.
- The local Supabase reset/database suite was unavailable because Docker and
  local Postgres were not running. This slice contains no database change.
