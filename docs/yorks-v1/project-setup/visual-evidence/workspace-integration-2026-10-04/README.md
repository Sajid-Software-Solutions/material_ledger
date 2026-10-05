# Workspace integration browser evidence — 4 October 2026

The six local JPEGs were captured through the real Flutter web renderer using
`tool/project_setup_visual_fixture.dart`, now wrapped in the shared Yorks
workspace shell. Their context and entered values are synthetic and device-only;
no remote backend, project activation or document upload was invoked. The fixture
has only the setup route. Actual Projects → Create entry/re-entry and draft-safe
exit are covered by the integration widget tests, using the real feature and
Projects screen with a custom GoRouter.

| Capture | Browser inspection |
| --- | --- |
| [Desktop setup](desktop-setup.jpg) | One header and the preserved stage rail/form/footer |
| [Desktop navigation](desktop-navigation.jpg) | Canonical permitted Yorks destinations; existing app branding/account/status |
| [Desktop search](desktop-search.jpg) | Shared workspace search with the same permitted module shortcuts |
| [Mobile setup](mobile-setup.jpg) | Narrow responsive form and one compact header |
| [Mobile navigation](mobile-navigation.jpg) | Shared Yorks destinations from the phone header |
| [Mobile search](mobile-search.jpg) | Shared workspace search from the phone header |
| [Live staging Projects](staging-projects-procurement.jpg) | Real signed-in Procurement portfolio; view-only access is enforced |

The default desktop viewport and saved images measure **1438 × 809** CSS/raster
pixels. The narrow viewport measures **359 × 800 CSS pixels** with scroll width
359, from a native 320 × 712 override at the browser's existing fractional DPR
0.8899999857. The browser capture API saves **403 × 899** raster pixels, including
navy padding to the right/bottom. These unchanged native captures are visual
evidence, not an exact 360px image or a pixel-match assertion. Existing widget
baselines separately cover exact 360px and the supplied desktop dimensions.

The initial macOS Drawer emitted a missing route-label warning. The final
source supplies the translated Quick navigation label and a regression assertion.
Fresh final desktop and phone sessions, including drawer open/dismiss and search,
reported zero captured warnings/errors. A debug-engine semantics-map exception
was observed when resizing a semantics-enabled desktop session across the phone
breakpoint; viewport-before-startup sessions did not reproduce it. General browser
resize/screen-reader behavior remains a separate acceptance boundary.

Temporary browser tabs were closed, viewport override reset and local dev server
stopped. The live staging capture is 1280 × 720 raster pixels and uses the existing
Procurement account. It establishes real read-only Projects access at the stable
alias; no authenticated Engineering/Admin create/edit/upload workflow is
established by these captures.
