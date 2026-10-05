# Mobile project setup validation — 4 October 2026

## Candidate and scope

This follows the desktop candidate at `69da24f43704dd0b83db32bb2bab937e8501e49e` on `codex/project-creation-ux`, in draft [PR 44](https://github.com/SajidAfridi/material_ledger/pull/44). The product owner supplied six mobile references and authorized implementation. The five setup stages and confirmed result now use a responsive feature-owned mobile shell, with consistent tablet reflow and the retained desktop shell. The dedicated route avoids duplicate workspace chrome.

The [mobile design](MOBILE_DESIGN_2026-10-04.md) records original image hashes, measured geometry, twelve exact 431×863 PNG baselines and deliberate accessibility/authority differences. This candidate does not claim literal pixel equality or stakeholder visual approval. Real 44px controls, readable wrapping and existing required-field, document and security rules increase content height compared with the compressed artwork.

No Supabase schema, RLS, RPC, stock, commercial or role contract changed in this mobile follow-up. Widgets continue through the existing controllers/repositories. Existing command identity, immutable intent, fencing, conflict handling and file-reselection recovery remain intact. The success surface requires a confirmed coordinator result in the application; its isolated visual fixture is synthetic.

`YORKS_V1_PROJECT_SETUP` remains **false by default** and browser-only. No production deployment, remote migration, flag promotion or live project/document write occurred. Native setup commands continue to fail closed until a cross-process draft adapter is accepted.

## Final local gates

| Gate | Final result and evidence |
| --- | --- |
| `flutter pub get` | Pass; lockfile unchanged, no new dependencies. |
| Changed Dart formatting | Pass; 11 files checked, zero changes. `/tmp/yorks-mobile-format-final.log` |
| `flutter analyze` | Pass; no issues after the final startup guard. `/tmp/yorks-mobile-final-analyze.log` |
| Complete `flutter test --no-pub --reporter expanded` | **2,251 passed / four retained skips**. `/tmp/yorks-mobile-full-tests-final.log` |
| Mobile interaction/render suite | **24 passed**, normal comparison against all 12 goldens; 360px, 431px, tablets, Arabic 200%, keyboard/safe-area simulations and stable identity actions. `/tmp/yorks-mobile-viewport-final.log` |
| Existing project creation suite | **53 passed**, including 390px create/edit/result/recovery, original key/manifest/hash reselection, negative capabilities and retained scope identity. Included in final full suite. |
| Local Supabase reset | Pass on tracked local project; Postgres 15.19, matching tracked major 15. `/tmp/yorks-mobile-db-reset.log` |
| Local `supabase test db` | **122 files / 3,546 assertions passed**. `/tmp/yorks-mobile-db-tests.log` |
| Candidate-flag CI web build | Pass; startup budget **10,007,726 JS bytes / verifier gzip 2,880,689 bytes**. `/tmp/yorks-mobile-build-web-final.log` |
| Candidate-flag CI APK build | Pass; **110,550,044 bytes**, ephemeral CI signer verified by `apksigner`. `/tmp/yorks-mobile-build-apk-final.log`, `/tmp/yorks-mobile-apk-signature-final.log` |
| Actual Flutter browser inspection | All six normal states and lower controls, narrow phone reflow, enlarged Arabic and tablet review inspected on final rebuilt source. All final state console queries returned zero warnings/errors. [Browser captures and viewport details](visual-evidence/mobile-2026-10-04/README.md) |

The four skips are existing external gates: local PostHog ingestion opt-in absent, two missing R38.9 client review-pack fixture cases, and the attached PERFECT workbook fixture absent. They are not counted as passing acceptance cases. The source acceptance catalogue retains its original Not run statuses.

Build commands used the explicit candidate flag with placeholder backend configuration:

```bash
YORKS_V1_PROJECT_SETUP=true R35_ENVIRONMENT=ci \
SUPABASE_URL=https://ci.invalid SUPABASE_ANON_KEY=ci-publishable-key \
./tool/r35.sh build-web

CI=true YORKS_CI_EPHEMERAL_SIGNING=true YORKS_V1_PROJECT_SETUP=true \
R35_ENVIRONMENT=ci SUPABASE_URL=https://ci.invalid \
SUPABASE_ANON_KEY=ci-publishable-key ./tool/r35.sh build-apk
```

## Final artifact identity

These artifacts were compiled from the final validated candidate working tree before its Git commit. They are local CI-placeholder build evidence, not deployed production artifacts.

- `build/web/main.dart.js`: SHA-256 `398f2afd95969e50cbee3d63f933c5f0a050d5c5ddb7608e2549d24b3cb84fe5`.
- `build/app/outputs/flutter-apk/app-release.apk`: SHA-256 `9402a4ff0eca5d5e2aed3a07a50812c7494f8a7bb07abf5c6e101054c6e1a450`.
- APK certificate: `CN=Yorks CI Ephemeral, OU=CI Only, O=Yorks, C=AE`; certificate SHA-256 `e832c2a71f4f279060766f4268bc63efe89445fa88221325dc83b57c4094f80a`. This is **not production signing** or a publishable release artifact.

## Concrete fixes and preservation

Mobile FRP selection now has its required Material ancestor and a measured 48px checkbox target. Footer actions keep full labels and stack on narrow/enlarged layouts. Raw editor input, false FRP, local row IDs, retained server scope IDs, contacts, unknown fields and command receipts remain preserved.

Actual browser navigation exposed a temporary 1×1 surface that normal viewport snapshots did not reproduce. The shell now defers only its chrome within `Scaffold.body` below usable dimensions; the feature/controllers and ScaffoldMessenger registration remain mounted. A single-mount 1×1 → 431×863 → 1×1 → 431×863 regression preserves the same state, draft ID, unapplied editor, exact raw whitespace and scope identity, with zero dispatched commands. All normal golden images remain unchanged after this fix.

Rollback is the existing default-off feature flag or application revert. Preserve local draft/journal/quarantine/tombstone namespaces and unresolved original command intent. No mobile database rollback is necessary. Retain the previously prepared additive dependency guard and historical records; this presentation follow-up does not authorize removing them.

## Remaining release acceptance

Local widget/database/browser checks do not establish live production create/edit/activation/upload behavior or all source scenarios. Physical phones/tablets, software keyboards/IME/dictation, screen readers, the complete 320px/landscape/high-contrast/reduced-motion matrix, real multi-session faults, representative old-data rollback, production personas, scale/performance and user trials remain separate gates in [candidate acceptance](CANDIDATE_ACCEPTANCE.md). The native cross-process adapter and properly production-signed Android lane remain unresolved release requirements.

The browser fixture has no remote backend and cannot issue a live write. It truthfully renders reselectable attachment metadata; no screenshot establishes a successful upload. Desktop baseline images were left unchanged and pass the full suite. Source/image links and `git diff --check` are checked before the final Git handoff; local checks do not claim remote CI success.
