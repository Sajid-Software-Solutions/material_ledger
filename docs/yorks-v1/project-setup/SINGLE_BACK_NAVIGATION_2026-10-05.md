# Project setup — single footer Back action

Owner correction received 4 October; staging verification completed 5 October 2026.

## Change

Removed the redundant **Back to projects** link from the desktop PROJECT SETUP
sidebar. The existing footer action is retained: it returns to Projects from
Project details and goes to the previous stage from subsequent stages. Its
save/leave guards and draft preservation are unchanged. Universal workspace
header navigation remains in place.

Only `yorks_v1_project_setup_desktop_shell.dart` changes application behavior.
No model, controller, repository, RPC/RLS, backend, draft schema, localization
contract or rollout default changes. The [direct project navigation correction](DIRECT_PROJECT_NAVIGATION_2026-10-04.md)
continues to govern completion and pending recovery.

## Validation

- `flutter pub get`: passed; lockfile unchanged.
- Changed Dart format gate: two files, zero changes. Full `flutter analyze`:
  no issues. `git diff --check`: passed.
- Full `flutter test --reporter expanded`: **2,331 passed, four retained skips**.
- Desktop/mobile/workspace focused suite: **73 passed**, included in the full
  gate. The new regression checks the sole first-stage footer exit, later
  previous-step navigation, stable draft input/ID and the original header.
  Existing explicit Save draft → Back/resume coverage now requires one exit label.
- Six existing desktop baselines updated: five active stages and one historical
  component fixture. Each differs by exactly **742 pixels**, confined to the
  removed link's original 16px band. No other pixels change. Mobile baselines
  are unchanged. The historical fixture does not reintroduce a result route.
- Candidate CI web build passed: main 10,011,344 bytes, verifier gzip 2,882,622.
- CI APK build passed and Android v2 signature verified with **Yorks CI
  Ephemeral**. This is a CI artifact, not a publishable Android release.

Build commands used the candidate flag explicitly:

```bash
YORKS_V1_PROJECT_SETUP=true R35_ENVIRONMENT=ci \
SUPABASE_URL=https://ci.invalid SUPABASE_ANON_KEY=ci-publishable-key \
./tool/r35.sh build-web

CI=true YORKS_CI_EPHEMERAL_SIGNING=true YORKS_V1_PROJECT_SETUP=true \
R35_ENVIRONMENT=ci SUPABASE_URL=https://ci.invalid \
SUPABASE_ANON_KEY=ci-publishable-key ./tool/r35.sh build-apk
```

## Staging delivery

Clean pushed application source: `6be98178231a9aaf43926715f99a2e0ddef67688`.
The full `lib/main.dart` app was rebuilt after `flutter clean`/`flutter pub get`
using the ignored staging configuration, setup enabled and PostHog disabled.
The Vercel dry run contained only the inspected isolated static artifact:
**59 files / 54,039,586 bytes**. It contains two staging backend markers and no
production/CI/visual-fixture markers. Private-value/service-role JWT scans passed.

- [Stable staging](https://yorks-r35-staging.vercel.app/yorks/projects#/yorks/projects)
- [Immutable preview](https://yorks-r35-oyzv4j9lm-sajid-alis-projects-0ec775a2.vercel.app)
- READY preview: `dpl_7rQK47viZZvLXztcT1srKPdNAYS2`; target is preview/null.
- Staging main: 10,037,683 bytes; verifier gzip 2,890,149.
- Main SHA-256: `cbd3fe21024906a996e59a3da12f7cfec987560918095528a14e56e1062982d9`.
- Index SHA-256: `972a64c127b49a2567a638054c0dc3d4a1373983983ccb019a66558c65668985`.
- Preview and stable alias each passed **23 route/asset hashes plus two
  Create/Edit deep routes**. Only the staging alias was assigned.

Production before/after remains `dpl_Gj1cfA1CbEJnkVwi4bG8eKabkRJy`; its
9,678,001-byte main bundle is byte-identical, SHA-256
`739de306598a9c0d135c5c7721d133a8c800321538b05894bda2627b8471b19f`.
Checked build/protection settings are unchanged. There was no production
promotion, migration, role change or production data mutation.

## Live browser evidence

Authenticated desktop verification at **1456×787 CSS / DPR 1** opened Create
through the existing Projects page. The retained YRA-322 proposal was owned by
another tab, so it remained read-only; no takeover or input edit was performed.
The setup rail has no Back to projects button. The footer Back and universal
header Back remain visible. The later-stage screen has zero Back to projects
buttons and two Back buttons in their distinct header/footer locations.

A fresh **360×900 CSS / DPR 1** session checked the Projects → Create entry,
review cards, lower content and retained sticky footer. Both fresh sessions
had zero captured warning/error messages. Temporary viewport overrides were
reset, verification tabs closed and the user's original tab preserved.

- [Desktop, empty lower setup sidebar and retained footer](visual-evidence/single-back-2026-10-05/desktop-review.jpg)
- [Phone review](visual-evidence/single-back-2026-10-05/mobile-review-360.jpg)
- [Phone lower content and sticky actions](visual-evidence/single-back-2026-10-05/mobile-review-360-bottom.jpg)
- [Capture notes](visual-evidence/single-back-2026-10-05/README.md)
- [Machine evidence](SINGLE_BACK_NAVIGATION_2026-10-05.json)

No live final Create/Update, activation or upload was used. Database gates are
not rerun for this presentation-only change. The previously documented
accessibility-enabled breakpoint resize issue and production/real-device
acceptance remain separate open gates. The candidate flag remains default off
in source and enabled only in this staging build. PR 44 remains a draft.

## Rollback

Reassign staging to the previously verified preview
`yorks-r35-le5zfrcjv-sajid-alis-projects-0ec775a2.vercel.app`
(`dpl_48uDaRkz5M3WBzmQn4BYUQEFMiYJ`) if needed. Source rollback reverts
`6be9817`; there is no schema/data rollback or draft/journal cleanup.
