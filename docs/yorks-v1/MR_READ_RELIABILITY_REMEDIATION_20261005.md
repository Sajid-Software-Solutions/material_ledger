# Material Request read reliability remediation — 5 October 2026

Status: implementation complete on the dedicated remediation branch; production
is unchanged.

## Scope and guardrails

This change addresses the Android/PWA Material Request read timeouts observed
on 5 October 2026. It does not alter workflow authority, RLS, trusted commands,
the 20-second repository timeout, or production data. Production was inspected
only through privacy-safe PostHog aggregates. Database profiling ran only on
the guarded technical staging project and rolled back its transaction.

## Evidence and root cause

The affected Android Chrome session recovered without an auth or permission
change. Around 06:32 UTC, successful reads stretched from hundreds of
milliseconds to 7–12 seconds before three calls reached the existing 20-second
timeout:

| Operation | Android attempts | Successes | Failures | P50 | P95 | Maximum |
|---|---:|---:|---:|---:|---:|---:|
| `material_request_load` | 8 | 6 | 2 | 1.562 s | 20.002 s | 20.002 s |
| `procurement_workspace_load` | 5 | 4 | 1 | 7.010 s | 18.416 s | 20.001 s |

The timeline shows overlapping calls beginning immediately after receipt
review, route changes and Realtime refreshes. A single engineering MR detail
mount also loaded both the role-safe Material Request projection and the much
heavier Procurement arrangement workspace, although engineering users cannot
operate that workspace.

Read-only staging `EXPLAIN (ANALYZE, BUFFERS)` evidence on the largest readable
fixture in the seven-user technical project was:

- `v1_material_request_projection`: 54.675 ms, 1,845 shared-buffer hits.
- `v1_arrangement_projection`: 29.447 ms, 1,272 shared-buffer hits.

Those results do not justify a database migration or index. The supported root
cause is client-side amplification under a temporary network/backend slowdown:
duplicate route reads, broad invalidation after one command, a duplicate
receipt refresh, and uncoalesced Realtime signals allowed protected reads to
overlap.

## Request graph

Before:

```text
MR detail mount
  -> v1_material_request_projection
  -> v1_arrangement_projection (every role)
  -> document/logistics/returns/policy projections

receipt completion
  -> dialog callback invalidates the whole graph
  -> dialog result invalidates the whole graph again
  -> Realtime invalidates every listener again
  -> route remount can start another independent pair
```

After:

```text
MR detail mount
  -> authority-scoped single-flight material-request read
  -> engineering roles reuse the role-safe controlled-document arrangement facts
  -> Procurement/Admin alone load one single-flight arrangement workspace

confirmed command / Realtime / resume
  -> reason-targeted invalidation
  -> a signal burst becomes one revision
  -> an active read receives at most one trailing refresh
  -> a rapid route return may reuse a <=3-second authorized result
```

Riverpod family isolation already keeps each request ID in a separate state
slot. Combined with same-key single-flight and sequential trailing refresh,
an old request response cannot overwrite a newly selected request. The current
PostgREST abstraction does not expose a dependable cross-platform cancellation
handle, so generation safety is enforced at the state boundary rather than by
pretending a dispatched HTTP request was cancelled.

## Implementation

### Protected-read coordinator

`YorksV1ProtectedReadCoordinator` provides:

- one in-flight read per authority scope and record key;
- one trailing refresh when invalidated during an active read;
- a bounded 32-entry cache with a three-second fresh-navigation window;
- last-authorized-result preservation only for offline/backend-unavailable
  failures; and
- no cache reuse for authentication, authorization or other domain failures.
  Such a failure purges that record's prior projection before surfacing the
  error, so a rapid return or later timeout cannot restore pre-denial data.

The coordinator is recreated when the authenticated user, exact role,
activation state, permission revision, or repository changes. Cached data can
therefore never cross an authority boundary.

### Visibility and invalidation

- Realtime signals received while hidden do not start reads.
- Foreground resume emits one authorized refresh.
- A same-turn Realtime burst is coalesced into one revision with only
  low-cardinality reason metadata.
- Detail, work-assignment, change-summary, logistics, movement, return and
  phase-3 projections refresh only for relevant workflow reasons.
- Receipt review now issues one local refresh, not two.
- Receipt completion no longer invalidates the unchanged arrangement editor.

### Role-aware detail startup

Procurement and Admin retain the transactional arrangement workspace. Project
Engineer, Site Engineer, Senior Mechanical Engineer, Project Manager, Workshop
In-Charge and Document Controller render the arrangement summary from the
existing authorized controlled-document projection. Legacy arrangement review
records retain their historical workspace path.

## Files and server functions

Client implementation:

- `lib/shared/sync/yorks_v1_protected_read_coordinator.dart`
- `lib/shared/providers/yorks_v1_material_request_provider.dart`
- `lib/shared/providers/yorks_v1_arrangement_provider.dart`
- `lib/shared/providers/yorks_v1_logistics_provider.dart`
- Material Request, arrangement, logistics and returns presentation screens

Verification:

- `test/yorks_v1_protected_read_coordinator_test.dart`
- `test/yorks_v1_material_request_realtime_test.dart`
- `test/yorks_v1_material_request_read_policy_test.dart`
- existing desktop, responsive, post-approval and mobile MR suites
- `tool/yorks-mr-read-staging-profile.sql`

Profiled, unchanged server functions:

- `public.v1_material_request_projection(uuid)`
- `public.v1_arrangement_projection(uuid)`

There is no migration in this remediation.

## Acceptance matrix

| Required scenario | Evidence |
|---|---|
| Same MR requested twice while in flight | One underlying read in coordinator test |
| Old MR returns after new navigation | Separate keyed state; delayed-old-response test keeps the new selection |
| Realtime while hidden | Three hidden signals produce no refresh revision |
| Resume | One coalesced foreground refresh |
| Timeout | Last authorized projection remains available |
| Timeout vs. permission | Backend unavailable may use cache; unauthorized is surfaced and never translated to denial by timeout logic |
| Rapid Dashboard ↔ MR | Three rapid returns use one read inside the bounded freshness window |
| Auth/permission revision | New authority coordinator cannot reuse old projection |
| Workshop role boundary | Role-policy test confirms no eager Procurement workspace read |
| Responsive regression | Existing desktop and 360 px MR suites pass |

Existing PostHog operation events remain the network-latency measurement
source. Each logical protected read also emits one bounded
`protected read coordinated` event with only `operation`, `workflow`,
`load_trigger`, `outcome`, `coalesced`, `cache_state`,
`request_generation` and `visibility_state`. It records no user, project,
request, material or document identifier. A coalesced consumer does not create
another repository operation event because no backend call occurred; the
coordination event makes that avoided call measurable without logging widget
rebuilds.

## Rollout and rollback

1. Deploy the branch artifact to the dedicated staging web target only.
2. Smoke Dashboard ↔ MR navigation, receipt completion, background/resume and
   Realtime with Workshop-In-Charge-equivalent global engineering and
   Procurement personas.
3. Compare Android Chrome/PWA `material_request_load` and
   `procurement_workspace_load` failure rate, P95 and calls per detail entry for
   at least one operational day. Keep identifiers out of analytics.
4. Production promotion requires an explicit release-owner decision after the
   staging evidence is accepted.

Rollback is client-only: redeploy the preceding verified web artifact. There
is no database rollback because no schema, function, data or policy changed.

## Residual risks

- The staging fixture is small (19 requests and 47 lines), so it proves the
  projections are not intrinsically slow there; it is not a production-scale
  load test.
- Staging has no Workshop In-Charge fixture. Senior Mechanical Engineer covers
  the same organization-wide engineering read boundary; the exact Workshop
  client branch is additionally covered by an automated role test.
- A genuine backend outage can still reach the existing timeout. The user now
  keeps the last authorized projection and the client avoids multiplying the
  outage with overlapping reads.
