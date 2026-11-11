# Clarification approval response correction — 9 October 2026

Owner authorized the fix and production update. Source commit: `5aae6ed`.

## Cause and change

The clarification branch of `v1_decide_material_request` committed successfully
but returned an arrangement projection. Flutter's unchanged `decideRequest`
requires a Material Request projection, so parsing failed and telemetry classified
`unexpectedResponse` as Database. Two attempts on YRA313-MR035 showed this issue.

The additive RPC adapter preserves the complete existing authority/locking/
version/idempotency/decision/notification/audit implementation, then normalizes
clarification results through the existing authorized Material Request projection.
It persists the corrected response under the same actor/command/key. Older stored
responses are repaired on retry without repeating the decision. Original command
completion timestamps remain intact. No stock or business-history migration occurs.
The underlying implementation is private; authenticated callers retain only the
existing public RPC. No UI, Dart, role grants or RLS policies changed.

## Verification

- Clean local database reset passed; all 3,860 checks across 132 files passed.
- Clarification regression file: 35 checks, including approval and return response
  shape, protected commercial fields, old-response replay and one audit event.
- Reapplying the migration locally and rerunning the focused checks passed.
- Flutter pub get, full analyze and 2,690 Flutter tests passed (four retained skips).
- CI web and ephemeral-signed APK builds passed. APK is validation only, not a
  production Android distribution. No changed Dart formatting or UI visual target.
- Staging replayed two historical clarification approvals in a rolled-back
  transaction: valid responses, unchanged request versions and audit counts.
- Production replayed the incident command in the same rolled-back verification:
  valid response, unchanged request version and audit count.
- Local, staging and production adapter definition hash:
  `17759dc49329360506ef8372c6616cb4`. Preserved original definition, with its original
  name restored for comparison: `a554a1075352ae18ad7256c8db495679`.
- Production migration ledger: `20261009063816`, `approval_response_contract`.
- Live grants: public RPC authenticated=true, anon=false; private helper
  authenticated=false. Security adviser scan returned no ERROR findings.
  Existing unrelated notices were not changed; see the
  [Supabase adviser guide](https://supabase.com/docs/guides/database/database-linter).

## Release and rollback

This is a server-only release, effective immediately for the existing production
web/native clients. The Vercel artifact from the preceding
[Procurement release](PROCUREMENT_PRODUCTION_RELEASE_20261009.md) remains current.
No cache clear or client update is necessary. No fresh business approval was
submitted for testing; actual end-user browser completion remains to be observed.
Historical telemetry failures are preserved and will remain in old reporting ranges.

Rollback can restore the public function body from the preserved private function,
retaining all records, audit and stored command responses. Do not undo an approval
or delete idempotency records to roll back a response-format correction.
