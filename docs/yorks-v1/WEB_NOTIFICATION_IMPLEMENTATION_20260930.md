# Web notification reliability candidate — 30 September 2026

Status: **web/PWA released to production; transport remains paused pending the live Owner Chrome delivery gate**.

Branch: `codex/web-notification-reliability`, based on
`b86ff4362cde5c214aaff2906c05b0adac258074`.
The primary checkout and its unrelated work were preserved.

This implements the 30 September notification audit for the website and installed PWA. Staging remains paused, with all 251 notification/outbox rows and 12 token rows retained. Production notification migrations, compatible Edge sender and the verified web artifact were deployed on 2 October 2026. All 4,576 notification/outbox rows and 65 token rows present at deployment were retained. Production transport and cron remain paused pending the designated Owner/Chrome-on-Mac delivery gate. The first explicit check was read before dispatch; the relevance guard rejected it with zero provider attempts. No backlog replay occurred. Do not store account credentials in this document.

## Implemented candidate

- Protected paginated history RPC with stable timestamp/ID cursors, independent
  unread totals, search/filter parameters, and authorized Company, MR/Return, Accounts and Workforce references. Labels and reference search use current read authority independently of whether an old action still needs attention.
  Chat attention records are separate from the workflow inbox and its count.
- Preserved validated internal destinations through sign-in, password changes,
  and router reconstruction; unsafe return locations are rejected.
- Bounded registration waits, capability checks, session/account fencing,
  preference-aware enrollment, and silent initialization. Web enrollment records
  the authenticated session; per-device dispatch rejects a deleted/expired session.
- Notification expiry enforced at claim/submission with remaining FCM/APNs/web
  lifetimes. Preference changes no longer re-enqueue old suppressed notifications.
- Accounts/Workforce and existing workflow event copy generated from versioned catalogues, with four in-app/device languages, CI producer coverage and exact protected record destinations. Per-device language updates require the current owner and active Auth session.
- Search, load-earlier history, stale-data feedback, date grouping, localized
  relative times, unread semantics, delivery-pause messaging, and iOS Home Screen
  guidance. Opening a row waits for protected destination loading and rendering before acknowledgement, with current-page and account fences. Explicit mark-read waits for the server instead of restoring an obsolete list
  after a concurrent refresh.
- Focus/lifecycle foreground guards, bounded alert history, burst grouping,
  and toast dismissal paused during hover/focus. Worker fallback clicks preserve
  unrelated open tabs and validate same-origin destinations.

These are source changes with scoped validation, not a claim of complete audit
closure or real-device delivery.

## Validation

| Check | Result |
|---|---|
| Flutter dependency resolution | Completed |
| Flutter analysis | No issues |
| Focused follow-up suites | Protected acknowledgement, paging, cold startup, worker, language and module navigation checks passed; final lifecycle follow-up passed |
| Full Flutter suite | 2,107 passed, 4 existing skips; no failures |
| Local Supabase reset | Passed |
| Full database suite | 121 files, 3,533 assertions passed after clean reset; digest regression: eight fail against old helper |
| Edge tests | 28 passed |
| Push failure classifier tests | 10 passed |
| Worker / compactor | 26 worker cases and one parse/print contract passed |
| Whitespace check | Passed |
| CI web / APK builds | Final CI web passed: 9,638,669 raw / 2,777,365 gzip bytes; APK passed (108.3 MB), CI-only ephemeral signing. This is not a production store signing artifact. |
| Staging | Forward migration deployed; pause, all 251 notification/outbox rows and 12 token rows retained. Matching final Edge and preview verified; protected context migration deployed; desktop/360px reference search and exact destination checks passed |
| Owner live FCM receipt and tap | First check protected against read-before-dispatch; replacement failed once on missing FCM IAM permission and stayed terminal. After the user granted the exact sending role, provider validation returned HTTP 200 and a new single-device background check was accepted on attempt one. The user confirmed macOS Notification Center receipt and exact-target click; the protected request was independently observed in the installed PWA, and the server recorded the read acknowledgement. General transport resumed after guarded backlog suppression. |

An isolated checkout of unchanged production source `b86ff43` reproduced 271
failures. Regeneration on that unchanged source exposed two non-visual contract
failures: a stale desktop label assertion and missing release-time hashing of
test-account IDs. Both are repaired without importing unrelated primary-checkout
work. 307 baseline PNGs were regenerated; all 21 with >=1% pixel differences
were inspected side-by-side. Most remaining differences were small text-rendering
drift. Sampling Flutter 3.47.1 reproduced the same drift, so SDK version alone
is not established as its cause. Notification dates now use an injected clock.
The strict golden comparator is unchanged: no tolerance, test deletion or new
skip was introduced. CI Flutter is pinned to the validated 3.47.5; Linux visual
parity remains a hosted-CI gate. Review metrics/contact sheets are in local evidence.

Desktop (1366px) and mobile (360px) notification render outputs were inspected:
the content fits and detail actions are visible. These are Flutter test renders,
not production browser or physical-device acceptance.

Local evidence is saved at
`/Users/eapple/Downloads/yorks-notification-implementation-20260930/`:
analysis, full/focused Flutter, database reset/test and Edge logs, plus desktop
and mobile screenshots. Chromium may show its own generic notice when malformed/expired external pushes are discarded; a worker cannot promise global OS silence. The Yorks sender only emits durable events, anchors expiry and never replays the historical backlog. No dummy show-and-close notification is used.

The original audit and 74-state matrix remain at
`/Users/eapple/Downloads/yorks-notification-audit-20260930/`.

## Authorized follow-up and remaining work

The user explicitly authorized repairing the baseline failures after the earlier
stop report. The full suite is now green. Production deployment and guarded transport resumption completed under the user authorization. The original probe read before dispatch and the later permission-failed probe remain preserved. The final fresh Owner/Chrome check passed provider, user-confirmed OS receipt/click, protected PWA rendering and server read acknowledgement without bypassing read-state or duplicate-delivery safeguards.

Completed follow-up: Chat burst destinations; separate bell/history filters;
loaded-history retention; stale-query fencing; onboarding/maintenance intent;
serialized account enrollment and persistent offline token-cleanup retry; worker
click/expiry tests; generated-catalogue CI check; current-entity push checks;
exact Accounts/Workforce target parameters using existing protected loaders.

Audit disposition for the current web/PWA scope:

| Audit | Released behavior / acceptance boundary |
|---|---|
| N01 | Production web/DB/Edge rollout completed. Fresh Owner Chrome-on-Mac delivery passed provider acceptance, user-confirmed OS receipt/click and independently verified installed-PWA target/read. General delivery resumed with old transport backlog suppressed and durable history retained. |
| N02 | Protected attention projection includes real Chat records without mixing Chat into the workflow inbox. |
| N03 | Initial browser location is captured before the startup app renders; auth, password, maintenance and account transitions retain only validated internal intent. Successful protected destination loading and a rendered frame precede acknowledgement for both OS/external taps and bell, inbox and foreground-popup actions. Imperative pushes use the top GoRouter page and retain Back history. |
| N04 | 58 active SQL producer event codes are covered by generated catalogues, safe copy and destination validation. Exact Accounts and Workforce targets use protected loaders. |
| N05 | Stable cursor pagination, independent unread totals, server filters, retained loaded history and competing refresh/read tests. |
| N06 | Silent Darwin initialization is fixed. Native APNs readiness and signed device acceptance remain future native work. |
| N07 | Bounded initialization/enrollment, permission recheck, preview-origin boundary and installed-web-app guidance. Actual browser settings recovery remains a live-device gate. |
| N08 | Serialized account/session installation lifecycle, token deletion, persistent offline cleanup and server session revocation gate. Native installation parity remains future work. |
| N09 | Current entity access and outstanding action rechecked for foreground attention and provider submission. Completed or revoked tasks keep history but lose attention eligibility. |
| N10 | Absolute expiry and remaining transport lifetime; browser worker rejects expired or unidentifiable fallback events. |
| N11 | Sanitized service-pause status is separate from device registration; protected health remains table-based. Provider acceptance is not OS-display proof. |
| N12 | Foreground visibility/focus gate, bounded dedupe, scoped toast dismissal, burst summaries and accessible timing. Physical multi-tab/background acceptance remains pending. |
| N13 | Conservative unknown preferences, preference-aware enrollment, bounded version-fenced refresh/save, no historical preference replay. |
| N14 | Server-confirmed ID-scoped acknowledgement; concurrent refresh is retained. Chat read cursor follows protected thread loading. |
| N15 | Authorized Company, MR/Return, Accounts and Workforce references, real urgency, localized event copy, search/date groups and visible detail actions. New context suite: 104 assertions; completed history stays readable and revoked references are absent from display and search. |
| N16 | Localized timestamps, read/button semantics, contrast and directional layout; desktop/360px tests. Actual screen-reader certification remains unperformed. |
| N17 | Loading, stale/error, filter-empty and refresh feedback without claiming cached work is current. |
| N18 | Web/PWA supported-path focus; native desktop background push is not advertised as implemented. |

The existing full-feature staging size gate now passes after a pinned JavaScript
parse/print step: 9,637,603 raw / 2,779,234 gzip bytes at the preceding build.
The original raw/gzip ceilings are unchanged. No identifier mangling or optimizer
compression is applied, preserving deferred library contracts and licenses.
Producer inventory, device language and broad current-entity tests are complete.
Exact attendance routes and lifecycle race fixes pass their final checks. The browser worker handles visible-unfocused delivery and protects unsaved tabs for both normal FCM and fallback taps; 26 worker cases pass.

Local full checks/builds, forward staging migrations, matching Edge/preview, cold/desktop/360px browser acceptance and the compatible production database/Edge/web rollout are complete. The designated fresh Owner Chrome-on-Mac background probe subsequently passed, with provider acceptance, user-confirmed OS display/click, independently observed exact installed-PWA target and server read acknowledgement recorded separately. The guarded restart preserved history and terminalized old transport work without replay. Broader physical-device/state certification remains outside this single-device acceptance.

Native store packaging, native installation identity and APNs readiness remain
later work per the user's web/PWA priority. No all-OS sign-off is implied.

## Data preservation and rollback

Migrations `20260930140403_web_notification_reliability.sql`,
`20261001180000_notification_attention_and_device_language.sql` and
`20261002010000_notification_record_context.sql` are additive.
The initial migration is preserved exactly as applied in staging; later fixes use
the forward migration. In the initial migration, the new
session column is nullable; historical notifications, tokens, delivery ledgers,
and terminal outbox outcomes are retained. Existing web installations must
re-enroll to supply session binding before becoming eligible under the new gate.

Keep transport paused during rollout. Deploy compatible database, Edge, and web
code together only after the staging gate. If rollback is needed, pause dispatch
first and retain the additive schema and delivery history. Do not restore old
retry functions, broadly replay jobs, remove session checks, or drop the new RPC
while clients depend on it. Use a reviewed forward correction for database
behavior; a web rollback alone is not a transport recovery procedure.

## Staging ledger preservation

The generic staging dry run was refused because staging records the setwise
MR register migration as 20260928160705, while this checkout uses
20260928144343, and staging lacks the unrelated Accounts export migration.
No unrelated ledger entries were repaired or overwritten. Only
20260929150000 and 20260930140403 were applied atomically with their ledger
entries. The sender was deployed to project iqltcyimlqtcwyzlemwx.

## Initial production artifact and live release boundary — 2 October 2026

- App/worker source: `1de7e63c18806fc7a6811ebabd70c114f1b81537`. Protected reference SQL/tests: `dec6613`. Source remains local at the user's request; no release push or GitHub authorization expansion was performed.
- Verified deployment: `dpl_3sz9uGDFBnbuYRo89Dng5mRVPbLT`, `https://yorks-r35-nv5nomdom-sajid-alis-projects-0ec775a2.vercel.app`, promoted to `https://yorks-r35.vercel.app`.
- Production main bundle SHA-256: `64cf2dd5ffff0f4f78a99fad84311b83363f3f784948065dc2435e792393e75a`. Firebase worker SHA-256: `1055f04e9abb387fa59c13837a18b458b89fe54dc0f1e86045d3d0dc95a92cc7`. Preview and canonical routes, shell, worker, manifest and deferred chunks matched the isolated artifact byte-for-byte.
- Production Edge sender: `send-push` version 14. Its webhook remains protected; no JWT verification was disabled beyond its existing secret-authenticated webhook contract.
- Production received only the three reviewed notification migrations and their exact ledger bodies. No generic database push, unrelated migration repair or business workflow mutation occurred.
- Existing Owner Chrome session re-enrolled: exactly one eligible canonical web installation, five retained ineligible legacy token records, no non-web Owner token.
- The first explicit `notification_delivery_check` remained authoritative history and was read before dispatch. The server correctly refused a push for a read notification; attempts, dispatches and device-delivery rows remain zero. This is read-state protection evidence, not FCM/OS delivery acceptance.
- The initial rollout kept transport paused for fresh live acceptance. The final permission repair and guarded cutover, recorded below, retained all history and prior terminal outcomes and enabled only prospective fresh delivery.
- Browser evidence: `staging-inbox-desktop-final.jpg`, `staging-inbox-mobile-final.jpg`, `staging-reference-search-mobile-final.jpg`, `staging-destination-final.jpg`, `staging-destination-mobile-final.jpg` in the local evidence folder. These are live staging browser checks, not physical iOS/Android acceptance.

## In-app acknowledgement follow-up

The bell, full inbox and foreground popup now use one shared open action. Authoritative rows carry their validated notification ID to the protected destination. A loading, denied, failed, unsupported or abandoned destination stays unread. The bridge follows the actual top GoRouter page for imperative pushes rather than the retained address-bar URI; a successful load must render before acknowledgement. Existing in-app Back history is preserved. Invalid IDs cannot propagate stale acknowledgement metadata. Accounts and Workforce keep their existing exact-record protected loaders; Chat keeps its protected read cursor.

Final focused suite: 157 passed, including 48 acknowledgement cases across the three actions, pending/denied/success, logout/account/Back races and unsafe targets. Full Flutter gate after source freeze: 2,107 passed, four existing skips. Analysis and six-file formatting passed. CI web: 9,639,393 raw / 2,777,846 gzip bytes. The production web follow-up artifact was verified and promoted; the designated Mac background receipt/click/read gate subsequently passed, and general delivery resumed after the guarded cutover.

## Verified acknowledgement release and FCM permission repair — 2 October 2026

- App source: `b42108d6df4645db117f19bb8bea677129528dab`. Deployment `dpl_Gj1cfA1CbEJnkVwi4bG8eKabkRJy`, `https://yorks-r35-5ih3bpqik-sajid-alis-projects-0ec775a2.vercel.app`, was verified before promotion to `https://yorks-r35.vercel.app`. Main bundle SHA-256: `739de306598a9c0d135c5c7721d133a8c800321538b05894bda2627b8471b19f`; worker SHA-256 remains `1055f04e9abb387fa59c13837a18b458b89fe54dc0f1e86045d3d0dc95a92cc7`. Canonical routes and all release assets matched the isolated artifact.
- Final production build: 9,678,001 raw / 2,789,393 gzip bytes. CI APK: 108.4 MB, ephemeral CI signing only. Latest staging preview `https://yorks-r35-fdpgkd5kf-sajid-alis-projects-0ec775a2.vercel.app` passed desktop and 360px inbox/reference/destination checks.
- The replacement probe `940bd35b-4d35-443d-b8f0-eed27693a7c9` failed on attempt/dispatch one with `AUTH_CONFIGURATION`, zero accepted devices. A protected validation-only request established Google HTTP 403 / `IAM_PERMISSION_DENIED` for `cloudmessaging.messages.create` on the deployed `yorks-fcm-sender@yorks-48c40.iam.gserviceaccount.com`. The credential project was correctly `yorks-48c40`; the API was not disabled. This probe remains terminal and was not requeued.
- The user granted Firebase Cloud Messaging API Admin to that exact sender. Live IAM shows the binding. The same protected validation-only request then returned Google HTTP 200 with no error, proving the deployed credential can send. The temporary diagnostic endpoint was removed after each validation; no credentials were emitted or rotated.
- Fresh probe `7b07d702-df45-49e2-bf3b-afb24d7ee2f9` was created at 16:31:46.189427 UTC while transport was isolated and cron off. It targets the designated Owner's one eligible canonical Chrome installation and material request `YRA326-MR011`. Provider acceptance completed at 16:31:47.755328 UTC, attempt one, dispatch one, exactly one accepted device, no error. Inbox `seen_at` remained null at the initial outcome check.
- General delivery was repaused after the isolated outcome. The user then confirmed macOS Notification Center receipt and an OS click opening `YRA326-MR011`. The installed PWA independently showed the exact protected request URI with this notification ID and the loaded request; server `seen_at` became `2026-10-02T16:32:53.02108Z`. The remaining badge of one matches the older unread failed check; the successful check is read. This acceptance covers the designated Mac Chrome/installed-PWA path, not every OS or state.
- At `2026-10-02T16:35:04.813405Z`, the guarded cutover resumed transport (`operator_paused=false`, no probe/circuit) and the single canonical every-minute scheduler. It retained all 4,603 notification and outbox rows and all device-delivery rows. The committed active transport cohort was closed without replay: 249 `BUDGET_OR_AGE_EXHAUSTED`, 34 `NOTIFICATION_NO_LONGER_RELEVANT`, and 16 `RELEASE_BACKLOG_SUPPRESSED`. Attempt/dispatch counters, sent-device counts and send-start timestamps were preserved. Earlier terminal outcomes, including the failed permission probe, were untouched. New post-cutover events can deliver prospectively.

Sanitized post-grant validation, isolated dispatch, outcome and repause logs are in the local evidence folder. Source remains local under the user's instruction.

Live acceptance evidence: `production-os-click-destination.png`, post-grant click outcome, guarded resume SQL/result and post-resume health/scheduler checks. OS receipt was confirmed by the user; the agent independently verified the installed-PWA destination and backend acknowledgement. No all-device or all-state certification is implied.

Post-resume verification at 16:36:15 UTC: canonical cron ran successfully at 16:36:00, operator pause was false, circuit and last global error were null, and pending/retry counts were zero. The successful probe remained sent/read with one attempt and one device; the earlier permission failure remained terminal with one attempt. The Owner workflow unread count of one matched both the browser and installed-PWA badge. Historical maximum attempt count 607 was preserved; active maximum was zero. All 65 token records remained; four web installations currently meet the new enrollment/session eligibility gate.
