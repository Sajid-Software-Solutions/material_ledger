# Yorks P0 push delivery correction — release candidate

Status: local implementation and mock verification. No production change or
real FCM delivery test. Read the earlier
[investigation](PUSH_P0_INVESTIGATION_20260929.md) for live read-only evidence.

## Immediate production containment

**Recommendation: apply containment promptly after explicit production
approval.** The owner's later read-only count saw 1,409 failed jobs retried in
one hour and 366 in 15 minutes. The prepared
[operator SQL](evidence/push-p0-20260929/containment-operator-only.sql)
was reviewed and not executed.

The transaction checks for one Vault URL secret, one named cron job and the
existing sender grant. `vault.update_secret` renames only the encrypted URL
entry so the insert trigger and cron dispatcher cannot find a destination;
the secret value and stable Vault ID remain. `cron.alter_job(..., active :=
false)` stops periodic dispatch. Revoking the old service-role claim grant
prevents already queued HTTP invocations that have not claimed from reaching
FCM. A final privilege assertion checks for inherited claim access; the three
changes commit together or fail together. They do not touch
`v1_notifications`, tokens, outbox rows, workflow RPCs or in-app reads. An
already claimed in-flight send may finish; allow that lease to drain and
inspect it after containment.

These settings are reversible, but **do not simply reverse them against the
old code**. The old cron would replay stale jobs. Restore the URL and cron
only after the migration has terminalized historical work, the fenced Edge
sender is deployed, and the operator has verified the control row remains
paused. Keep cron stopped for the first recovery test. Set an expired circuit cooldown,
clear its probe slot, and unpause the operator control; call
`v1_dispatch_push_notification` for exactly one approved fresh notification.
The dispatcher reserves that notification as the sole probe. A successful
accepted delivery clears the circuit. Verify its browser alert before resuming
cron. A failed probe leaves the circuit open. Verify the exact pending set
before each restoration step.

## Implemented state and concurrency rules

Migration
[`20260929150000_bound_push_delivery_and_health.sql`](../../supabase/migrations/20260929150000_bound_push_delivery_and_health.sql)
adds claim identity, send-start evidence, terminal fields, a six-attempt
budget, a 24-hour age ceiling, dispatcher leases and a protected circuit row.
The migration defaults transport to paused. It terminalizes **all preexisting
failed or sending jobs**, including recently failed jobs, rather than
automatically replaying the 1,425 poison jobs. It also terminalizes pending
jobs older than 24 hours or already at the attempt budget. Every notification,
outbox row and historical attempt count is retained. A later one-off resend
would require a separate reviewed operator decision and is not part of this
candidate.

The outbox PK still provides one job per notification. Dispatcher reservation
limits duplicate HTTP invocations; the atomic claim increments the attempt
count once and returns a UUID claim ID. Finish requires that exact UUID and
the active `sending` state. The Edge sender records `send_started_at` before
the first FCM request. An expired lease that has **not** started an FCM send
may be recovered by a new claim; the old claim cannot start sending or finish.
If an FCM send may have started, the expired lease becomes terminal
`DELIVERY_OUTCOME_UNKNOWN` rather than risking another visible alert. External
FCM acceptance and Postgres commit cannot be one atomic transaction; this
uncertainty is deliberate and visible. The in-app notification remains intact.

A protected per-notification/device SHA-256 ledger records accepted sends.
A retry skips accepted devices and attempts only confirmed temporary rejections.
The server rechecks current token ownership before each send and before pruning.
Transport timeouts are ambiguous and terminal, not permission to resend.
A crash after possible FCM acceptance remains visible as an unknown outcome.

The old four-argument finish RPC loses its service-role grant. Migration and
Edge deployment must happen with transport paused so an old sender cannot
send using the new claim and then fail to record its result.

Retryable failures use 1, 2, 4, 8, 16 and 32-minute exponential delays after
the corresponding attempts (the sixth failure terminates), plus a stable
0–29-second jitter. FCM `Retry-After` can lengthen a retry and is honored by SQL rather than
merely returned as an Edge header. A delay of 24 hours or more terminalizes
the job instead of retrying sooner than requested; the job age limit also
prevents stale delivery.
The user-facing response remains a failure on rejected transport.

## Safe FCM classification and token handling

[`fcm_failure.mjs`](../../supabase/functions/send-push/fcm_failure.mjs)
reads Firebase's structured HTTP v1 error details. Its mockable transport
adapter and [tests](../../supabase/functions/send-push/fcm_failure.test.mjs)
cover accepted sends, rate limits, network failures and the documented error
classes. Only explicit `UNREGISTERED` deletes a device token, through a fenced RPC
that rechecks its current owner. `INVALID_ARGUMENT` is permanent but does not
prove token revocation; it never deletes a token. A `BadRequest` is treated
as malformed payload.
Sender mismatch is terminal for that target; three distinct affected jobs in
five minutes open the circuit for a likely project-wide mismatch. Third-party
web-push auth and OAuth/configuration failures open it immediately. Quota,
unavailable, internal and unknown failures receive finite retries. The
database accepts only an allowlist of normalized codes. No raw Firebase
response, token, OAuth credential or protected message copy is persisted or
logged by the new classifier.

The production token inventory had 64 web tokens for 11 users, only five
registered/seen within 24 hours. `last_seen_at` means registration recency;
it does not prove live browser use. The follow-up now persists one installation UUID per browser origin and stores
its approved web origin, enrollment time and retirement state on the token.
Rotation retires only the same owner's previous token for that installation;
no historical token is deleted by age or count. Legacy unclassified web tokens
remain stored but are ineligible for external delivery until explicitly
re-enrolled from the approved site. Registration never requeues old no-device
jobs. A newly enrolled browser is also excluded from still-pending events
created before its enrollment time. In-app notification history is unchanged.


## Circuit and health

A confirmed global configuration failure opens the transport circuit for 15
minutes. While open, the dispatcher sends no bulk work. It permits one
designated recovery probe after the interval. Another global failure delays
the next probe; a real FCM accepted send closes the circuit. A no-device or
unclaimed probe cannot count as recovery. The separate operator pause always
overrides the circuit. New `v1_notifications` continue to be written and read
while push is paused or degraded.

Protected `v1_push_backend_health()` reads indexed operational tables only:
notification creation, attempts, sent/no-device/terminal outcomes over one
and 24 hours, retry count, oldest retry, historical max attempts, last FCM
acceptance, allowlisted error categories, registered token/user counts and
circuit/operator status. `activeTokens` in the JSON means *registered* tokens,
not confirmed live installations. No raw Supabase logs are scanned; routine
monitoring must use this projection. `service_role` alone can execute it.
The new event table records claim and outcome times, which the prior outbox
could not reconstruct. The 24-hour count uses time indexes; do not poll it at
high frequency.

## Verification and remaining gates

Local `supabase db reset` applied the additive migration. Focused pgTAP tests
exercise pause/in-app persistence, role grants, one claim per lease, a stalled
pre-send claim followed by successful replacement, stale finish rejection,
post-send ambiguity, six-attempt exhaustion, Retry-After, no devices,
permanent failure, circuit suppression and recovery. The Edge payload tests
and Node mock FCM tests run without credentials. The exact command/results
are recorded in the final handoff once all gates finish.

Real FCM delivery remains pending. Dedicated staging
`iqltcyimlqtcwyzlemwx` currently lacks `FCM_SERVICE_ACCOUNT_JSON`; its
existing pending outbox must be quarantined by this migration before enabling
transport. An operator should create a minimal Firebase sender service
account for the intended Yorks Firebase project, store its JSON in a private
local file with mode `0600` and a single `FCM_SERVICE_ACCOUNT_JSON=<JSON>`
entry, then run `npx supabase secrets set --env-file <private-file>
--project-ref iqltcyimlqtcwyzlemwx` from a trusted terminal. Do not put the
JSON in a CLI argument, repository, chat, Vercel variable or browser asset.
After a staging web build uses the matching public VAPID key, sign in to one
non-production browser profile and explicitly enable device alerts. Verify
its owner-bound token row, one new in-app notification, one FCM acceptance,
one browser alert and deep link, then test multi-device and failure cases.

Production release requires separate explicit approval, a reviewed migration
ledger, an isolated candidate, complete local gates, real staging FCM proof,
and baseline/post-release hourly comparisons of Edge invocations, 503s,
Postgres/Edge/function log rows and payload, notifications, push attempts,
sent/retry/terminal events, and egress. Historical billing-cycle totals will
not fall. The prior draft `40001` conflict fix is unchanged; normal-use and
legitimate conflict checks remain release gates.

## Rollback

Pause operator transport and cron first; keep `v1_notifications` and every
outbox/event row. Roll back the Edge sender only to a version compatible with
claim IDs and the fenced finish RPC. Do **not** restore the unbounded SQL
worker or automatically reopen terminal rows. The additive columns and
protected event/health tables may remain inert for a later forward fix.

## Secure staging credential provisioning (operator only)

These steps have not been executed. Confirm the Firebase project ID matches
the staging client's sender/project configuration. In Google Cloud IAM,
create a dedicated sender service account and grant Firebase Cloud Messaging
API Admin on that project; enable the Firebase Cloud Messaging API. Create
a JSON key and save it outside the repository in an owner-only directory.
The supported service-account/OAuth flow is documented by
[Firebase](https://firebase.google.com/docs/cloud-messaging/send/v1-api).

In a trusted terminal, convert that private JSON file to a temporary dotenv
file without printing its contents or putting the key in process arguments:

```bash
umask 077
python3 - /absolute/private/firebase-sender.json /absolute/private/staging-push.env <<'PY'
import json, os, sys
source, destination = sys.argv[1:]
with open(source) as f:
    account = json.load(f)
assert all(isinstance(account.get(k), str) and account[k] for k in
           ('project_id', 'client_email', 'private_key'))
with open(destination, 'x') as f:
    os.chmod(destination, 0o600)
    f.write('FCM_SERVICE_ACCOUNT_JSON=' + json.dumps(account, separators=(',', ':')) + '\n')
PY
npx supabase secrets set --env-file /absolute/private/staging-push.env \
  --project-ref iqltcyimlqtcwyzlemwx
```

The env-file interface is supported by
[Supabase secrets](https://supabase.com/docs/guides/functions/secrets).
Verify only the secret name in the Dashboard. Remove the temporary env file
through the operator's normal secure-file process; retain the original key
only in approved credential storage. Never paste either file into chat.

Apply the reviewed migration to dedicated staging while dispatch is paused,
then deploy `send-push` from this candidate with JWT verification disabled
(the handler validates the dedicated Vault webhook secret). Keep production
ref `czykuksmlwswjsgotrpo` out of these staging commands. Configure the existing
Vault Edge URL/webhook secret pair using the private operator workflow; do
not print decrypted values. Register one opted-in staging browser token from
the matching HTTPS staging build. Use the single-probe procedure above,
verify one in-app row plus one browser alert/deep link, then multi-device
retry and background/foreground behavior. FCM acceptance alone is not proof
of browser display. Only after these gates may an approved production rollout
repeat the same paused migration/deployment/probe sequence.


## Completed local gates

- `flutter pub get` and `flutter analyze`: passed, no analyzer issues.
- Full `supabase db reset` and database suite: passed, 113 files / 3,282 assertions.
- Final focused database suite after health/dispatch refinements: 92 assertions passed.
- Independent two-session race: one claim, replacement success, stale finish rejected.
- Transactional migration replay twice: passed; 605-attempt poison fixture preserved and terminalized.
- Deno sender type check, 12 payload tests and 5 handler mock tests: passed.
- Node Firebase classifier/transport tests: 10 passed.
- CI web build and startup budget: passed.
- CI APK build with ephemeral signing: passed; not a production-signed artifact.
- `git diff --check` and shell syntax checks: passed. No Dart source changed.
- Full Flutter suite: blocked by unrelated mobile project-review/overview golden
  differences on unchanged Flutter code. Stopped after observing these failures;
  did not regenerate goldens or change UI. It is not reported as a passed gate.

The complete database suite preceded the final additive retry-health fields
and dispatch-exception circuit change; the final focused suite and repeated
migration test cover the final SQL. The original checkout remains untouched.
Compact output is in [local validation evidence](evidence/push-p0-20260929/local-validation.txt).
No remote migration, Edge deployment, containment or credential write occurred.


## Browser flood and staging notification follow-up

The user's exact staging deployment was inspected read-only:
`https://yorks-r35-4s7k6maqd-sajid-alis-projects-0ec775a2.vercel.app/`.
Its compiled bundle references dedicated staging, but has neither
`company_material_request_approval_requested` nor its English label.
The current Flutter source contains both the specific labels and Company
Request detail routing. Staging has 69 Company Request notification rows and
69 existing target records. This confirms an older deployed presentation;
it does not authorize changing that immutable deployment or production.

The candidate additionally implements:

- A visible View details cue and tested Company Request navigation at desktop
  and 360px. Unknown targets explain the unavailable link instead of opening
  the notification list again. No commercial details are added to alerts.
- Fourteen Company Request event descriptions and Company detail deep links
  in the Edge payload, matching the current in-app descriptions.
- Foreground FCM as an authorized refresh signal only. Console/test payload
  text cannot produce an orphan toast; initial feed hydration does not replay
  old entries after login/reload.
- Permission copy that reports registration without claiming the OS will show
  alerts. macOS may independently block Chrome notifications.
- Approved-origin web enrollment and server send eligibility. Production
  defaults to `https://yorks-r35.vercel.app`. Dedicated staging must configure
  **one approved stable staging origin** consistently in the Flutter build
  (`YORKS_WEB_PUSH_ORIGIN`), Edge (`YORKS_WEB_ORIGIN`), and database
  (`v1_push_transport_control.allowed_web_origins`, operator-only).
  Do not add every Vercel preview origin. The shared Firebase project alone
  must not imply that every preview receives production pushes.

Apply the candidate migration before deploying the matching client/Edge code,
with transport paused throughout. Legacy web tokens are preserved but skipped;
users re-enroll from the canonical origin and receive new events only. These
changes are in the existing unpublished P0 migration, not an already-applied
remote migration. An environment that already applied an earlier candidate
must use a reviewed delta rather than editing its migration history.

Old preview permissions and OS notification-centre entries are browser-owned.
A page on the canonical origin cannot revoke other origins' subscriptions.
The operator/user should remove notification permission for obsolete preview
URLs in Chrome site settings, preserving the canonical site's permission.
Chrome-generated background notices and external test messages are not Yorks
workflow history; do not fabricate in-app rows to mirror them. Firebase console
messages bypass this app's sender and cannot be prevented by its retry policy.

Local evidence: all 3,303 database assertions passed, followed by 11 expanded
installation assertions. 24 focused Flutter tests and desktop/mobile navigation
checks passed. Edge type checking, 19 payload/handler tests, concurrency and
migration replay passed. Analyzer, CI web and ephemeral-signed APK builds
passed. The previously observed unrelated full-suite golden failures remain
an overall release limitation. Real browser/FCM delivery remains pending.

Visual evidence: [desktop](../../test/goldens/push_p0/notification_center_desktop.png)
and [360px mobile](../../test/goldens/push_p0/notification_center_mobile.png).
The UI tests verify that clicking the Company approval notification opens the
exact Company request route. No staging or production deployment was performed.
