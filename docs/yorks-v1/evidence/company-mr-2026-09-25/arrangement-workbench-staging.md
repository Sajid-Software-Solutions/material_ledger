# Company MR arrangement workbench — staging evidence

25 September 2026. Scope: Company Material Request Procurement arrangement presentation and interaction. The protected Company supply-plan command, reservation/dispatch rules, and other fulfilment commands were not changed in this slice.

The old Company action opened a review dialog and then a separate dialog per material line. The current action opens one responsive workbench with Project-style counts, decision/source/quantity editing, inline exception details, stock search, a focused phone list and line editor, and an explicit review before saving. Unsaved changes require a deliberate discard. A failed command leaves the editor open for a same-key retry. Server confirmation remains the only success signal.

- Source PR: [#26](https://github.com/SajidAfridi/material_ledger/pull/26), draft; Company workbench commits `7652c62` and `83e460c`.
- Staging integration source: `a4815ad` on `codex/yorks-staging-company-arrangement-20260925`. It includes draft [#27](https://github.com/SajidAfridi/material_ledger/pull/27), whose migration `20260925031723` was already on the shared staging backend.
- [Verified preview](https://yorks-r35-r7p6ylv3m-sajid-alis-projects-0ec775a2.vercel.app): Vercel deployment `dpl_E49eAoRd9pjVjivceMjkpaKbvy8A`. No production promotion was performed.
- Final `main.dart.js`: 10,292,847 bytes, SHA-256 `059e8806d723fe41ec25a5f18dd737b5e4143378446a35bb81047f94873cdafa`; local staging artifact and served file matched. The build contained exactly one staging backend reference and no CI placeholder. The 21 checked routes/assets, including `/yorks/material-requests`, matched the local artifact.
- Staging migration dry run: up to date, no migration pushed by this slice.
- Analyzer: clean on both the source and combined staging checkouts. Project/Company focused suite passed; combined checkout: 141 tests before the phone heading polish, plus 8 final workbench tests afterward. Responsive workbench tests covered 360, 390, 600, 768, 1024, 1366 and 1920 px, a searchable stock choice, dirty exit, and failed-save retry.
- CI-configured web and ephemeral-signing APK builds passed on the source branch. The repository-wide Flutter test run still had 264 existing golden failures; it was not a clean full-suite gate.
- The production alias `main.dart.js` SHA-256 was `97b62b561e80d907239fe60786195bd760c148fcca6df45b569908bdadfcc4eb` before this staging update and must be checked unchanged at handoff.

Local visual captures using the app typography and icon font: [360 px phone list](arrangement-mobile-360.png) and [1366 px desktop table](arrangement-desktop-1366.png). They use synthetic request data. They prove the rendered layouts, not a signed-in role workflow.

Still for staging acceptance: a named Procurement user should arrange Full, Partial and Cannot Provide Now lines, re-open a saved plan, exercise an external supplier and the same-stock race, and confirm the history and dispatch handoff. No authenticated persona test or live PostHog receipt was available in this turn. Production schema, data and deployment remain untouched pending explicit approval.
