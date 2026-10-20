# Verified authentication before project reads

## Incident and cause

On 20 October 2026 at 17:58:38 PKT, a Windows/Chrome session emitted a
331 ms `project_list_load` permission denial before identification. The same
session authenticated as Project Engineer at 17:58:54 and loaded seven projects
successfully at 17:58:56. This establishes the pre-sign-in failure and subsequent
recovery, but does not establish whether the original session expired or was
otherwise cleared. The incident release was `e1015f5`.

The compatibility session notifier restored a saved local user ID immediately,
before Supabase session/profile verification. Project portfolio and overview
providers also permitted a network read while the presentation session was
absent. The current production baseline `adb3576` retained these paths; its
public bundle SHA-256 was verified against the prior release evidence before
creating this isolated fix.

## Correction

Connected startup no longer treats a persisted compatibility user ID as a
verified session. AuthController must finish the existing Auth and active-profile
checks before opening the signed-in shell. Local demo behavior is preserved.
An already verified in-process session still survives a transient background
verification outage; a cold start cannot open protected screens from the saved
ID alone when verification is unavailable.

Project portfolio and dashboard overview providers check the verified local
session against the current Supabase identity before entering the repository.
A retained listener during sign-out receives local unauthenticated state, without
sending a protected request or recording a failed backend operation. A successful
sign-in automatically recreates the reads. Real server permission denials remain
errors; neither analytics nor authorization rules are weakened.

Logout clears presentation identity synchronously before awaiting device storage.
A generation check prevents a delayed session write from resurrecting that
identity. Materialization checks the generation again after local user persistence
and session persistence, so late verification cannot complete a signed-out session.

## Regression coverage

The HTTP-backed tests exercise real AuthController, Supabase client and project
providers with delayed Auth and profile responses:

- stale device login without a Supabase session sends no project/dashboard reads;
- delayed restored authentication and delayed password sign-in remain blocked
  through both Auth and profile checks, then load normally;
- rejected restored credentials clear stale login and remain blocked;
- sign-out during delayed profile verification cannot reopen protected reads;
- late device persistence cannot resurrect a signed-out identity;
- an authenticated server permission denial remains visible as unauthorized.

The retained temporary-outage test now explicitly starts with an already verified
in-process session, distinguishing background continuity from cold-start trust.

## Release scope

No SQL, RLS, role, permission, schema, business data or production configuration
changes. Deployment is web-only; any CI APK is ephemeral-signed and not an Android
store release. Rollback promotes the previous production deployment
`dpl_B96grAdqY4GbnnG72eJj1c8xBDLv` without a database rollback.

## Validation

- Dependency resolution, changed-file formatting and `git diff --check` passed.
- Full `flutter analyze`: no issues.
- Full `flutter test`: 2,889 passed, four retained skips. This includes seven
  new authentication boundary regressions and existing desktop/mobile/RTL
  layout, routing and golden checks.
- CI web build passed the startup budget: 9,903,404 main-bundle bytes,
  2,852,039 gzip bytes.

The final database, Android build and production release results are recorded
in the accompanying release evidence when complete.
