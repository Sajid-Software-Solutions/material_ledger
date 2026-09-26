# Private MR draft deletion

Approved task: 27 September 2026. A recoverable private draft must disappear
only after account deletion and device persistence acknowledge the operation.
This does not change Engineering approvals or normalized MR cancellation.

## Authority and durability

- Recovery input is actor-private. The existing exact-role/project rules for
  creating, saving and submitting a business MR remain authoritative.
- List deletion cannot remove a normalized saved, submitted, approved,
  arranged, dispatched, received or cancelled request. Pending Save/Submit
  receipts must be reconciled before deletion.
- Keep the autoDispose controller alive until the confirmed deletion settles,
  including when its screen closes. Auth-owner changes still stop local writes.
- Block overlapping edits, Save, Submit and duplicate Delete. Drain existing
  autosave and device writes before deletion, then use the latest known sync
  version. A newer/unreviewed account copy produces a conflict, never an
  automatic overwrite or destructive retry.
- Account deletion installs a permanent owner/UUID retirement marker. The same
  transaction lock serializes deletion, private autosave and connected Save,
  including when no row exists. Old/offline editors cannot revive that UUID.
- A retired draft's owner read returns `V1_PRIVATE_DRAFT_DELETED`. A resumed
  stale device copy is then cleaned up and editing is blocked. Offline devices
  retain input until they can verify that server fact.
- A failed device cleanup remains honest and retryable; local failure never
  produces a confirmed-deletion event. Unknown JSON fields, unreadable rows,
  historical duplicates and a corrupt whole blob are preserved. Whole-blob
  corruption prevents overwriting the collection.
- One actor-scoped persistence queue serializes changes from different editors
  and checks SharedPreferences acknowledgment. The existing storage key stays
  unchanged, and local keystrokes still do not trigger account-list reloads.

## Telemetry

After confirmation, record `material request draft delete attempted`, followed
by either `material request draft deleted` or `material request draft delete
failed`. `material_request_draft_delete` records operation duration and bounded
error categories. Never transmit draft IDs/titles, descriptions, project data,
commercial values, raw errors or storage contents. PostHog is diagnostic;
Supabase owns retirement and the append-only deletion audit.

## Migration and rollback

`20260926200859_material_request_draft_deletion_safety.sql` adds a protected
retirement relation and replaces only private sync/read/list/delete and the
existing base Save function. Existing data is not rewritten. The new relation
has RLS and no ordinary client grants; it stores identity, role, version and
time, never draft contents. Existing RPC grants remain unchanged.

Deploy database guards before the application, after backup/readiness checks
and explicit release approval. Old clients fail closed for retired UUIDs.
Rollback retains retirement/audit evidence and the anti-resurrection guards;
deploy corrective function/application code instead of erasing markers.
Restoring a deleted private draft requires an explicit recovery decision and a
new UUID, never silent revival of the retired ID.

## Verification

Controller tests cover offline, stale versions, account changes, pending
workflow commands, duplicate requests, autosave/hydration races, persistence
failure, retired-copy cleanup and matching deletion acknowledgments. Widget
tests cover desktop/360px success, failure, disabled controls and navigation
during deletion. Database tests cover owner isolation, required role positives
and negatives, inactive/anonymous denial, idempotency, audit count, saved-record
preservation and delayed Save/autosave rejection. The local concurrency harness
tests both commit orders against separate PostgreSQL sessions.

The opt-in PostHog ingestion test uses `environment=local` and a synthetic
identity. It verifies controller/privacy-guard/endpoint ingestion. It does not
prove the deployed web SDK, staging UAT or authenticated production behavior.
