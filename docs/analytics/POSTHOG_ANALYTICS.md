# Yorks privacy-safe product analytics

Status: PostHog Analytics Phase 2, schema version `2`. Capture is opt-in per
environment. Session Replay, exception autocapture, browser autocapture and
production debug logging are disabled.

This contract governs external product telemetry. It is separate from the
protected `YORKS_V1_ANALYTICS` operational workspace and from Supabase's
authoritative workflow, stock and audit records.

## Purpose and boundaries

Yorks analytics should reveal whether important workflows succeed, where
people struggle, which user-visible operations are slow, and which safe error
categories are increasing. Analytics must never block, delay or determine a
business action.

PostHog is not Yorks' audit log, security authority, stock ledger, document
store or commercial reporting source. Role/access changes, approvals,
inventory corrections and other sensitive administrative actions remain
server-authoritative and should ultimately be covered by an immutable
Supabase audit trail.

## Architecture

`route/controller/repository -> AnalyticsService -> privacy guard -> PostHog sink`

- One Riverpod-provided `GuardedAnalyticsService` owns capture, identity,
  common context, timing, friction detection and feature-flag reads.
- `AnalyticsRouteMapper` converts GoRouter paths to fixed, identifier-free
  screens and de-duplicates navigation events.
- Controllers capture meaningful intent; repositories capture only after an
  authoritative RPC/storage result is known.
- The bounded pre-initialization queue and serialized fire-and-forget sink
  preserve identity/reset order. Initialization and transport errors are
  swallowed at the analytics boundary.
- The native and web sinks apply a second event/property allowlist. Direct
  `Posthog().capture()` is confined to the sink.

## Identity, GeoIP and privacy

After a connected Supabase session is verified, `identify()` receives only
the Auth UUID and exact server-controlled `app_metadata.role`. Local demo IDs,
names, email addresses and profile data are never identified. Logout, rejected
restore and remote sign-out reset the SDK identity.

PostHog's normal IP-derived GeoIP enrichment remains enabled. Yorks does not
request GPS permission, send precise coordinates or collect background
location for analytics. GeoIP can support regional reliability investigation,
but it is not sufficient evidence for a security or disciplinary decision.

The event seam accepts booleans, non-negative finite numbers, enums and short
controlled categorical strings. It drops free text. Never send project,
client, consultant, supplier or employee names; record/reference IDs; material
descriptions; query text; comments; reasons; filenames; document contents;
commercial values; tokens; URLs; SQL; raw exceptions; or stack traces.

## Configuration and environments

| Variable | Contract |
|---|---|
| `POSTHOG_ENABLED` | Explicit opt-in; default `false` |
| `POSTHOG_PROJECT_TOKEN` | Environment-specific public project token; never committed |
| `POSTHOG_HOST` | HTTPS ingestion origin; default `https://us.i.posthog.com` |
| `POSTHOG_ENV` | Must match `R35_ENVIRONMENT` |
| `POSTHOG_DEBUG` | Effective only for local debug builds; always false in production |

CI, unsupported platforms, missing/invalid configuration and environment
mismatches are no-ops. Web, Android, iOS and macOS use manual initialization.
Production Session Replay and Canvas Capture remain off.

## Schema version and naming

Every event has `schema_version=2`. Version 2 changes custom event values from
snake_case to lowercase `[object] [verb]` phrases and expands safe workflow,
friction, performance and reliability coverage. Historical version 1 events
remain in PostHog, but Yorks never dual-sends them.

Properties remain snake_case dimensions. Every event automatically receives
`schema_version`, `environment`, `platform`, `app_version`, `app_build`, and,
when available, `screen_name` and `role`. Call sites may add controlled
`source`, `entry_point`, `network_state`, `workflow`, `operation`, counts,
durations and outcome categories.

Normalized error categories are `network`, `timeout`, `validation`,
`permission_denied`, `conflict`, `database`, `storage`, `authentication`,
`offline`, `insufficient_stock`, `feature_disabled`, and `unknown`. No error
message crosses the analytics seam.

## Event catalog

All events below are centrally defined in `analytics_event.dart`.

| Event | Purpose | Trigger | Properties | Authoritative source / sensitive-data rule |
|---|---|---|---|---|
| `authentication attempted` | Login intent | Before sign-in | `source` | Auth controller; no email |
| `authentication succeeded` | Successful login | Verified result | `source`, `outcome` | Auth controller |
| `authentication failed` | Login failure | Normalized result | `source`, `outcome` | Auth controller; no exception |
| `session restored` | Valid returning session | Server revalidation succeeds | common | Auth controller |
| `user signed out` | Explicit logout | Before logout/reset | common | Auth controller |
| `project creation started` | Project funnel start | Create route entry | `entry_point` | Route mapper |
| `project creation attempted` | Project submit intent | Valid input reaches repository | counts | Project repository; no party names |
| `project created` | Project completion | Create RPC succeeds | `building_count`, `attachment_count` | Project repository |
| `project creation failed` | Project failure | Create RPC fails | `error_category` | Project repository |
| `project opened` | Project engagement | Identifier-free detail route | `source` | Route mapper |
| `project access changed` | Access command outcome | Assignment/revocation returns | `action_type`, `success` | Project repository; no user/project ID |
| `project updated` | Update success | Update RPC succeeds | common | Project repository |
| `project update failed` | Update failure | Validation/RPC failure | `error_category` | Project repository |
| `attachment upload started` | Upload intent | Before authorized upload | type/size buckets, `object_type` | Documents repository; no filename |
| `attachment uploaded` | Upload completion | Storage finalize and reload succeed | type/size buckets, duration via operation | Documents repository |
| `attachment upload failed` | Upload failure | Upload/finalize fails | buckets, `error_category` | Documents repository |
| `material request started` | MR funnel start | Draft route entry | `source` | Route mapper |
| `material request item added` | MR composition progress | One or more lines added | `action_type`, `item_count` | Draft controller; no descriptions |
| `material request item removed` | MR composition change | A line is removed | `item_count` | Draft controller |
| `material request draft saved` | Recovery/save outcome | Local recovery or server save succeeds | `source`, `item_count` | Draft controller |
| `material request review reached` | Funnel review step | User enters real review step | `item_count`, `entry_point` | Draft controller |
| `material request submit attempted` | Submit intent | Before connected submit | `source`, `item_count`, `request_timing` | Draft controller |
| `material request submitted` | Submit success | Server returns submitted record | `source`, `item_count` | Draft controller |
| `material request submission failed` | Submit failure | Connected submit fails | `source`, `error_category` | Draft controller |
| `material request opened` | Request engagement | Detail route entry | `source` | Route mapper |
| `material request approved` | Request approval | Decision RPC returns approved | `action_type` | MR repository |
| `material request returned` | Returned for changes | Decision RPC returns returned | `action_type` | MR repository; no reason |
| `material request decision failed` | Decision failure | Decision RPC fails | `action_type`, `error_category` | MR repository |
| `approval started` | Arrangement decision intent | Before decision RPC | `action_type` | Arrangement repository |
| `approval completed` | Arrangement decision result | Decision RPC succeeds/fails | `action_type`, `success`, `error_category` | Arrangement repository |
| `procurement request opened` | Procurement engagement | Arrangement route entry | `source` | Route mapper |
| `procurement started` | Procurement funnel stage | Begin-arrangement RPC succeeds | `workflow` via operation | Arrangement repository |
| `procurement action started` | Arrangement save intent | Before save RPC | `item_count` | Arrangement repository |
| `procurement action completed` | Arrangement save success | Save RPC succeeds | `item_count`, `success` | Arrangement repository |
| `procurement action failed` | Arrangement failure | Begin/save RPC fails | `action_type`, `error_category` | Arrangement repository |
| `dispatch attempted` | Dispatch intent | Before dispatch RPC | `item_count` | Logistics repository |
| `dispatch completed` | Dispatch success | Dispatch RPC succeeds | `item_count`, `success` | Logistics repository |
| `dispatch failed` | Dispatch failure | Dispatch RPC fails | `item_count`, `error_category` | Logistics repository |
| `receipt review completed` | Delivery outcome | Receipt confirmation RPC succeeds | line counts, exception boolean, outcome category | Logistics repository; no line content or quantities |
| `inventory opened` | Inventory engagement | Inventory route entry | `source` | Route mapper |
| `inventory searched` | Search usage | Inventory search RPC completes | result count, query-length bucket, duration | Logistics repository; never query text |
| `inventory search no results` | Search quality | Inventory result count is zero | query-length bucket, duration | Analytics service |
| `material search completed` | MR candidate search | MR candidate RPC completes | result count, query-length bucket, duration | MR repository; never query text |
| `inventory item selected` | Search usefulness | Detail projection succeeds | `source` | Logistics repository; no item ID |
| `inventory item created` | Item-master creation | Create-item RPC succeeds | `inventory_action` | Logistics repository |
| `stock action started` | Stock command intent | Before create/adjust RPC | `inventory_action` | Logistics repository |
| `stock action completed` | Stock command success | Stock RPC succeeds | `inventory_action`, `success` | Logistics repository; no quantity/reference |
| `stock action failed` | Stock command failure | Stock RPC fails | `inventory_action`, `error_category` | Logistics repository |
| `inventory import started` | Import intent | Before import RPC | row count | Logistics repository |
| `inventory import completed` | Import success | Import RPC succeeds | row/result counts | Logistics repository |
| `inventory import failed` | Import failure | Import RPC fails | row count, `error_category` | Logistics repository; no workbook data |
| `form validation failed` | Safe form friction | Reviewed validation boundary | `form_type`, `validation_reason`, count | Controller/repository; categorical reason only |
| `validation loop detected` | Repeated validation friction | Same category three times within two minutes | form/category, attempts, duration | Analytics service |
| `search struggle detected` | Search friction | Threshold reached before selection | context, attempts, zero results, duration | Analytics service |
| `repeated action detected` | Unclear/slow feedback signal | Same meaningful action three times in two seconds | action, taps, duration, loading state | Analytics service |
| `action produced no feedback` | Dead-action signal | Explicit feedback contract expires | action, screen, wait, loading state | Analytics service; critical actions only |
| `operation completed` | Performance/success basis | Timed operation finishes once | operation, duration, success, cached, result count | Analytics operation handle |
| `feature flag evaluated` | Experiment exposure basis | Non-security flag resolves | flag, variant | Analytics service |
| `reliability error occurred` | Reliability rollup | Timed operation fails | operation, category, retryable, duration | Analytics service; no raw exception |

## Legacy event migration

All schema v1 snake_case events map mechanically to the schema v2 phrase with
these deliberate semantic changes:

| Legacy | Schema v2 |
|---|---|
| `project_creation_validation_failed` | `form validation failed` (`form_type=project_creation`) |
| `document_upload_attempted` | `attachment upload started` |
| `document_upload_succeeded` | `attachment uploaded` |
| `document_upload_failed` | `attachment upload failed` |
| `material_request_item_changed` | `material request item added` or `material request item removed` |
| `material_request_review_opened` | `material request review reached` |
| `material_request_validation_failed` | `form validation failed` (`form_type=material_request`) |
| `material_request_submission_attempted` | `material request submit attempted` |
| `material_request_action_completed` | `material request approved`, `material request returned`, or `material request decision failed` |
| `arrangement_started` | `procurement started` |
| `arrangement_save_attempted` | `procurement action started` |
| `arrangement_save_completed` | `procurement action completed` or `procurement action failed` |
| `inventory_action_started` | `stock action started` |
| `inventory_action_completed` | `stock action completed` or `stock action failed` |
| `material_search_struggle_detected` | `search struggle detected` |
| `ui_repeated_action_detected` | `repeated action detected` |
| `ui_action_no_feedback` | `action produced no feedback` |
| `reliability_error` | `reliability error occurred` |
| Every other v1 name | Replace underscores with spaces |

## Friction, performance and reliability

- Repeated action: one signal after three identical important actions within
  two seconds. A double click is not classified as struggle.
- No feedback: only an explicit critical-action handle starts a four-second
  timer. A known loading state counts as feedback and never starts the timer.
- Search struggle: within 30 seconds, three searches including two zero-result
  searches, or 15 seconds without selection, emits once per sequence.
- Validation loop: three failures for the same controlled form/reason within
  two minutes emits once per loop.
- `beginOperation()` measures full repository/controller work, emits once, and
  never awaits PostHog. Failures also emit the category-only reliability rollup.

Form abandonment is intentionally not inferred from route exit. MR drafts are
durable recovery records and leaving the page is often legitimate; labeling
that behavior as abandonment would be untrustworthy. Backtracking and a
cross-workflow friction-free metric require a future privacy-reviewed workflow
run key before they can be calculated exactly.

## Feature flags

`AnalyticsService.isFeatureEnabled(AnalyticsFeatureFlag)` is the only PostHog
flag seam. It returns the safe control experience when analytics is disabled,
not ready, offline, slow beyond two seconds, or throws. A flag may alter
presentation only; it cannot grant routes, roles, commercial data, workflow
authority or stock permissions.

## Session Replay policy

Replay is off on web, Android, iOS and macOS. Web Canvas Capture is also off.
A future staging-only experiment requires synthetic data, text/image/input and
platform-view masking, payload inspection, recording-by-recording review,
documented retention/sampling, and release-owner approval. Production must not
enable `PostHogWidget`, `sessionReplay` or project recordings without that gate.

## Five production dashboard definitions

Use `environment=production` and `schema_version=2` on every insight. Default
range is last 30 days, daily interval; retain an app-version quick filter.

The five pinned production dashboard shells were created in project `600792`
on 9 September 2026: UX Health `2080195`, Material Request Funnel `2080196`,
Performance `2080197`, Inventory Intelligence `2080198`, and Reliability
`2080199`. They intentionally remain without tiles until the production schema
reader observes version 2 events and verifies each event/property combination.

### 1. Yorks UX Health

1. Multi-series line: total counts for `repeated action detected`, `action
   produced no feedback`, `search struggle detected`, `inventory search no
   results`, `form validation failed`, and `validation loop detected`;
   breakdown separately by `screen_name`, `role`, `platform`, `app_version`.
2. Slow critical operations: `operation completed`, `duration_ms > 2000`, bar
   by `operation`; companion count for `duration_ms > 5000`.
3. Important-action failure rate: `operation completed success=false` divided
   by all `operation completed`, formula `A/B*100`, by `operation`.
4. Reliability rate: `reliability error occurred` divided by all `operation
   completed`, `A/B*100`, plus unique affected users.
5. Form abandonment: mark as pending, not zero; no trustworthy event exists.

### 2. Material Request Funnel

Ordered funnel, 30-day conversion window, unique users, show conversion,
drop-off and median conversion time:

`material request started` -> `material request item added` -> `material
request review reached` -> `material request submit attempted` -> `material
request submitted` -> `material request approved` -> `procurement started` ->
`procurement action completed` -> `dispatch completed` -> `receipt review
completed`.

For the final full-delivery view, filter `receipt review completed` by
`receipt_outcome=all_received`; analyze `exceptions_present` separately rather
than pretending missing/damaged lines are fully delivered.

Create separate breakdown views for `role`, `platform`, and `app_version`.
There is no `order recorded` stage: Yorks V1 deliberately has no PO/RFQ suite.

### 3. Performance

1. `operation completed`: median (`p50`) and `p95` of `duration_ms`, breakdown
   `operation`. Covered operations include `dashboard_load`,
   `project_list_load`, `project_create`, `project_update`,
   `material_request_load`, `material_request_submit`, `document_upload`,
   `procurement_workspace_load`, `arrangement_begin`, `arrangement_save`,
   `inventory_load`, `inventory_search`, `inventory_adjust`,
   `inventory_import`, `dispatch_materials`, and `receipt_review`.
2. Failure rate formula as above, breakdown by `operation`.
3. Slow-operation counts at `>2000` and `>5000` ms, breakdown separately by
   `platform`, `app_version`, and `screen_name`.

Interpretive bands: under 500 ms excellent; 500-1000 acceptable; 1-2 seconds
noticeable; 2-5 seconds poor; over 5 seconds serious. These are analysis bands,
not application failure conditions.

### 4. Inventory Intelligence

1. Search count: `inventory searched`.
2. Zero-result rate: `inventory search no results / inventory searched * 100`.
3. Struggle rate: `search struggle detected search_context=inventory /
   inventory searched * 100`.
4. Selection rate: `inventory item selected / inventory searched * 100`.
5. Item creation count: `inventory item created`.
6. Stock success rate: `stock action completed / stock action started * 100`;
   failure rate uses `stock action failed` as numerator.
7. Import outcomes: compare `inventory import completed` and `inventory import
   failed`.

Break down stock insights by `role`, `platform`, and `inventory_action`. Never
add the raw search query as a property or breakdown.

### 5. Reliability

1. `reliability error occurred` totals and unique users, breakdown separately
   by `error_category`, `operation`, `screen_name`, `role`, `platform`, and
   `app_version`.
2. Category tiles filter `timeout`, `network`, `permission_denied`, `storage`,
   and `database`.
3. Upload failure tile: `attachment upload failed`.
4. Critical failures: `operation completed success=false`, by `operation`.
5. Serious latency: `operation completed duration_ms>5000`, by operation and
   app version.

## Product metric foundations

Successful workflow rate is calculated separately per workflow so unmatched
starts cannot distort the result: project `project created / project creation
started`; MR `material request submitted / material request started`; stock
`stock action completed / stock action started`; approval `approval completed
success=true / approval started`; procurement `procurement action completed /
procurement action started`; attachment `attachment uploaded / attachment
upload started`.

Friction-free completion is currently an investigation metric: completed
workflow sessions excluding sessions containing `repeated action detected`,
`validation loop detected`, `action produced no feedback`, or `reliability
error occurred`, with an optional extreme-duration filter. It is not presented
as an exact KPI until a privacy-safe workflow-run correlation key is approved.

## Verification checklist

- Unit-test readable unique event names, common context, identity/reset,
  safe-value rejection, environment/debug gates, failure isolation, repeated
  actions, no-feedback, search struggle, zero results and validation loops.
- Search source for direct `Posthog().capture` and legacy event literals.
- Run `flutter analyze`, `flutter test`, web build and Android build gates.
- Verify a staging capture before production promotion. Confirm new schema v2
  events arrive, common properties exist, query text/content is absent, and no
  duplicate v1 event is emitted.
- Dashboard shells may be created before ingestion. Create their saved insights
  only after the schema reader confirms schema v2 events/properties exist in
  that PostHog project.
