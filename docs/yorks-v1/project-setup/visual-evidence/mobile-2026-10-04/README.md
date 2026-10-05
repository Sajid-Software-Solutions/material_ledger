# Mobile browser evidence — 4 October 2026

Captured from the final source in a fresh hidden Codex browser tab, through the real Flutter web renderer. Synthetic fixture only; no remote backend, live create/edit, upload or production mutation occurred. Stage 5 supplies a synthetic confirmed result. Capture state is not server acceptance evidence.

The browser had existing zoom/DPR **0.8899999857**. Native viewport overrides 384×768, 320×712 and 684×912 produced measured CSS sizes **431×863**, **359×800** and **768×1025**, respectively. DOM scroll width equalled viewport width. Exact 360×800 and 768×1024/1024×768 are separately asserted in widget tests. Enlarged Arabic uses app text scale 2.0.

All six normal top/bottom JPEG pairs and the applied-building capture are app-only 431×863. An initial screenshot clip mismatch was detected in the saved artifacts; those captures were discarded and recaptured at the correct native viewport dimensions. Saved dimensions and distinct top/bottom bytes are checked, and the lower views show their actual lower controls. Narrow captures measure 359×800 CSS but save as 360×800 raster pixels; the tablet measures 768×1025 CSS and saves as 769×1025 pixels. The one-pixel raster rounding comes from the browser's existing fractional DPR. These are browser screenshots, not pixel equality measurements against the source artwork. Exact app-only DPR1 PNG baselines are linked in the mobile design document.

All six normal states and lower controls were inspected. Building Continue was disabled with unapplied editor input; applying the visible editor re-enabled Continue and exposed Undo. The initial semantic browser click could not resolve its shadow-root target, so the action was performed from the fresh visible screenshot; the resulting state was verified. No backend command was dispatched. Files truthfully show metadata/reselection rather than invented completed uploads. Completion omits Save draft and has explicit permitted actions.

Every final state console query returned zero warnings/errors. The final query is retained in [final_browser_console.json](final_browser_console.json); it is a final tab query, not a substitute for backend logs or a complete browser fault-injection run. The previously observed temporary 1×1 overflow was fixed in the shell and covered by a same-mount draft/editor preservation regression. The fresh rebuilt browser navigation did not reproduce that overflow.

The temporary tab was closed, viewport override reset, and local fixture stopped after inspection. Physical phone keyboards, file pickers, screen readers, native critical dispatch and production personas remain separate gates.

| Capture | Saved raster size |
| --- | --- |
| [attachments_bottom_browser.jpg](attachments_bottom_browser.jpg) | 431 × 863 |
| [attachments_top_browser.jpg](attachments_top_browser.jpg) | 431 × 863 |
| [building_applied_browser.jpg](building_applied_browser.jpg) | 431 × 863 |
| [buildings_bottom_browser.jpg](buildings_bottom_browser.jpg) | 431 × 863 |
| [buildings_top_browser.jpg](buildings_top_browser.jpg) | 431 × 863 |
| [confirmed_result_359_browser.jpg](confirmed_result_359_browser.jpg) | 360 × 800 |
| [confirmed_result_bottom_browser.jpg](confirmed_result_bottom_browser.jpg) | 431 × 863 |
| [confirmed_result_top_browser.jpg](confirmed_result_top_browser.jpg) | 431 × 863 |
| [details_359_browser.jpg](details_359_browser.jpg) | 360 × 800 |
| [details_arabic_359_200pct_browser.jpg](details_arabic_359_200pct_browser.jpg) | 360 × 800 |
| [details_arabic_bottom_359_200pct_browser.jpg](details_arabic_bottom_359_200pct_browser.jpg) | 360 × 800 |
| [details_bottom_browser.jpg](details_bottom_browser.jpg) | 431 × 863 |
| [details_top_browser.jpg](details_top_browser.jpg) | 431 × 863 |
| [parties_bottom_browser.jpg](parties_bottom_browser.jpg) | 431 × 863 |
| [parties_top_browser.jpg](parties_top_browser.jpg) | 431 × 863 |
| [review_bottom_browser.jpg](review_bottom_browser.jpg) | 431 × 863 |
| [review_tablet_browser.jpg](review_tablet_browser.jpg) | 769 × 1025 |
| [review_top_browser.jpg](review_top_browser.jpg) | 431 × 863 |
