# Routed browser evidence — 4 October 2026

These captures render the actual feature route using `tool/project_setup_visual_fixture.dart` with synthetic permitted context and no configured remote backend. They are visual checks, not live create/upload acceptance.

## Desktop screens

| Screen | Browser capture |
| --- | --- |
| Project details | [Details](details-browser.jpg) |
| Parties and access | [Parties](parties-browser.jpg) |
| Buildings with unapplied editor | [Buildings](buildings-browser.jpg) |
| Attachments | [Attachments](attachments-browser.jpg) |
| Review and create | [Review](review-browser.jpg) |
| Confirmed result component | [Result](success-browser.jpg) |

Desktop CSS viewport is 1536×1025. The in-app browser's existing zoom reports DPR 0.89; native captures include a dark right/bottom gutter. Exact 1536×1024, DPR 1 snapshots are in [the desktop golden folder](../../../../../test/goldens/project_setup_desktop/). Screenshot pixels and CSS pixels must not be silently treated as interchangeable.

Both primary actions beside footer hints now end at the 26px right inset. The browser-only dropzone wrapper initially let its child shrink to intrinsic width; explicit full width corrects it. The final browser view shows the complete 1222px drop area. The review preserves all entered parties and can grow vertically: the browser fixture's six party rows take 12px more height than the five-row canonical golden. Scroll remains available; values are not discarded to fit a screenshot.

The result view uses a synthetic confirmed operation to inspect the shared result component. Real server-confirmed completion, permission-negative Open, uncertain activation/file recovery, same-container remount and completed-edit shortcuts are exercised by repository/controller-backed widget tests. No browser live transaction is claimed.

## Historical compact and accessibility views

| Case | Browser capture |
| --- | --- |
| Mobile review, 359×800 CSS | [Compact review](mobile-review-359-browser.jpg) |
| Tablet buildings, 1025×800 CSS | [Tablet editor](tablet-buildings-1025-browser.jpg) |
| Arabic details, 359×800 CSS and 200% text | [Arabic enlarged text](arabic-details-359-200pct-browser.jpg) |

These captures predate the supplied mobile references and the subsequent mobile implementation. The browser's integer viewport override and existing zoom gave 359/1025 CSS widths. The historical compact English action was ellipsized; the new mobile shell keeps full action labels and stacks them at narrow widths. Current mobile/tablet/Arabic evidence is recorded in [mobile validation](../../MOBILE_VALIDATION_2026-10-04.md). Retain these earlier captures as desktop-phase history, not the current mobile design.

## Diagnostics and limits

The earlier development tab retained a transient 1×1 startup workspace overflow and disposed EngineFlutterView assertions during debug hot restart. These are recorded separately from the stable views; a fresh tab without hot restart is used for the final six-screen console check. The fresh tab visited all six final desktop states without any hot restart; the final captured console query returned zero errors and zero warnings. All six desktop JPEGs were captured from that clean tab at 1536×1025 CSS. Local widget cases assert no rendering exception and full application analysis/tests pass.

The original image dimensions/hashes, measured geometry and intentional authorization/required-field/file-policy differences are recorded in [the design comparison](../../DESKTOP_DESIGN_2026-10-04.md). Bundled-font glyph metrics differ from the supplied raster references; this evidence does not claim literal pixel equality or stakeholder visual approval.
