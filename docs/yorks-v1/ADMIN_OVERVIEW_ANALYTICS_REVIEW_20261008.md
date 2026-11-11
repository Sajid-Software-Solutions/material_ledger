# Admin Overview and Analytics: review and improvement plan

Date: 8 October 2026. Status: **approved for implementation and production release by the owner on 8 October 2026**. Implementation and verification are recorded in the accompanying release evidence.

## 1. Conclusion

Yorks has a credible operational-data foundation. Its Admin experience needs a clearer hierarchy: the first screen should help a person identify a problem, its owner and the next useful action. Today, large module summaries and explanatory notices compete with that purpose. Analytics also needs a more distinct role: investigating changes and their causes through source records.

Retain Flutter, Riverpod, the universal shell, existing design tokens, capability checks, protected RPCs and strict response validation. Improve the composition and read paths incrementally. A wholesale rewrite is not justified by this review.

## 2. Evidence and limits

- Read-only production inspection as the authenticated Admin at `https://yorks-r35.vercel.app`, Overview and `/yorks/analytics`.
- Desktop inspection at 1280 x 720 and Analytics at 360 x 800. The temporary viewport override was reset.
- Source reviewed in the combined production worktree, HEAD `eda5c737870dcb2ad4e1a138b3fd639ea33c4f45`. The latest recorded production release source is `bf9babd4c36d32f1a2aa509a2183ba68b7ee55dc`; release documentation and source inspection are distinct from live runtime proof.
- Reviewed models, repositories, providers, UI, RPC migration, existing tests and the approved analytics contract.
- One authenticated Analytics reload produced approximately 3,358 ms request-to-response-header time for the analytics RPC and 2,053 ms for permission resolution. These are individual observations, not p95, database execution time, cold-start measurements or an end-to-end SLA. Requests can overlap; do not add their times together.
- No production SQL profiling, multi-user load test, screen-reader audit, user interviews or task-success study was performed. Security architecture review is not a penetration test.

Governing contracts: [operational analytics](OPERATIONAL_ANALYTICS_AND_FOUNDER_OVERVIEW.md), [architecture/security](ARCHITECTURE_AND_SECURITY_CONTRACT.md), [Accounts](R39_ACCOUNTS_FOUNDATION.md), [product decisions](PRODUCT_DECISIONS.md), [privacy-safe telemetry](../analytics/POSTHOG_ANALYTICS.md).

## 3. Findings

### A. Daily priorities are too far down the page — high priority, live and code confirmed

At the inspected desktop width, five KPI cards occupy three rows before the attention area. Financial totals, empty portfolio statistics and operational work have similar visual weight. The important action is below the initial viewport.

The KPI grid switches directly from two to five columns at 980 px of available content width. Persistent navigation means a normal desktop can still receive the two-column layout. Fixed panel heights also create substantial blank space.

**Change:** put a compact, prioritized attention list near the top; reduce summary-card height; use intermediate responsive layouts and content-driven panel heights. Choose KPI order by the Admin's daily decisions, rather than module order.

### B. Attention totals and visible records are difficult to reconcile — high priority, live and code confirmed

The live attention badge showed 75 while only one request record was visible. The total is a sum across domains; it is not necessarily an incorrect count. However, the Overview request preview explicitly takes only one record whenever `maxVisible` is supplied. It therefore obscures how the total relates to the preview.

**Change:** define the counted unit for each domain; show category subtotals and a bounded preview with an explicit “View all” destination. Avoid a grand total if categories count unlike or overlapping things. Each record should show its project, current state, owner, waiting age and next action where authoritative data supports them. Do not invent deadlines or overdue rules.

### C. Empty portfolios can look like poor performance — high priority, live and code confirmed

Rental occupancy renders 0% for zero occupied out of zero properties. The model explicitly returns zero when the denominator is zero. This is an undefined occupancy ratio, not evidence of failed occupancy.

**Change:** render “No properties yet” and an appropriate source link. Distinguish confirmed zero, no records, no eligible denominator, no access, unavailable data and stale data. Apply the same review to Workforce and Accounts; do not assume every zero means missing setup.

### D. Permanent warning treatment creates noise — high priority, contract and live confirmed

The Analytics coverage warning is prominent even when Inventory and Audit are intentionally source-only under the approved contract. Expected coverage and actual service problems deserve different treatment.

**Change:** put normal coverage details behind a concise information control. Reserve warning emphasis for a real missing result or failure that affects the user's interpretation. Retain explicit source-only and denied states internally and never substitute zeros. Permission-denied responses must remain fail-closed.

### E. Mobile Analytics delays the answer — high priority, live confirmed

At 360 x 800, the first screen is largely title, description, Refresh, project and period controls, update status, section selection and a coverage notice. No substantive result is visible before scrolling.

**Change:** one compact title/status row, one domain control, a short applied-filter summary with a Filters sheet, then the first result. Keep at least 44 x 44 touch targets. Charts need readable summaries and a table alternative; desktop grids must not be squeezed into phone width.

### F. Analytics needs stronger continuity and investigation — medium priority, code confirmed

Project and period filters are local widget state, with 3/6/12-month choices. Domain selection filters presentation without another fetch, which is useful. However, filter context is not represented in the route; source drill-down and Back need explicit restoration behavior. Aggregate action links often open a general workspace rather than the matching filtered queue.

**Change:** preserve allowed filter/domain context in navigation, support meaningful comparison periods, and link each metric to its exact authorized record set. Label current-state snapshots separately from activity during the selected period. Additional comparisons require agreed metric definitions and backend support, not client-side guesses.

### G. Loading work is broader than necessary — medium priority, code and network evidence

Analytics watches the authorized project portfolio to populate its picker. That portfolio loads project scopes, members and parties as well as projects. These requests appeared in the live network observation. Overview also watches several module providers alongside the combined analytics projection. Some support fallbacks and administrative controls, so removing them indiscriminately would regress behavior.

**Change:** inventory dependencies, introduce a lean authorized project picker if measurement justifies it, and load optional lower sections on demand. Profile cold and warm entry, filter changes and return navigation. Use staging `EXPLAIN (ANALYZE, BUFFERS)` with representative data before proposing indexes or materialization. An output row cap does not bound aggregate query cost.

### H. Reliability has a useful foundation but remains coupled — medium priority, code-supported risk

The aggregate RPC combines multiple domains without per-domain exception isolation. A database error in one section can fail the whole projection; permission/source coverage is a different mechanism from runtime fault isolation. The repository has a 20-second timeout. No such domain outage was reproduced during this review.

**Change:** establish measured latency budgets and explicit loading, retry and freshness behavior. Consider a versioned section-result contract or separately bounded reads where fault isolation is valuable. Never catch authorization or malformed-data errors and silently show stale success. Coalesce refreshes; handle rejected refresh futures visibly; test rapid filter changes and responses arriving out of order.

### I. Presentation code is expensive to maintain — medium priority, source confirmed

`company_analytics_screen.dart` is about 3,337 lines and contains both summary and deep-analysis presentation. The executive overview is about 2,282 lines, including fallback composition. Analytics builds its main content inside one large sliver adapter/column. This is a maintenance and potential scaling concern, not proof of current frame jank.

**Change:** extract small domain sections, metric cards, attention rows, filter controls and coverage/status components while preserving tested contracts. Separate Overview composition from Analytics composition. Use lazy sections where profiling shows value. Do not move repository access into widgets.

### J. Accessibility and product measurement need completion evidence

Existing tests cover 360px, 200% text scaling, RTL-related layouts and domain interactions; chart semantics exist. That is a good starting point, not proof of complete keyboard, contrast or screen-reader accessibility. The feature UI has no obvious dedicated filter/drill-down telemetry calls; route-level instrumentation exists elsewhere.

**Change:** verify focus order, focus restoration, keyboard filters, non-colour status cues, chart/table descriptions, contrast and screen-reader output. Instrument through the existing guarded analytics service. Measure task completion, failed loads, useful drill-downs and repeated refreshes. Do not send project names, IDs, monetary amounts, search text or workforce details to PostHog. PostHog remains separate from authoritative operational facts.

## 4. Product references and what to borrow

These are design references, not claims that Yorks has feature or scale parity.

| Reference | Relevant pattern | Yorks application |
|---|---|---|
| [Codex app](https://openai.com/index/introducing-the-codex-app/) | Focused work and review; our visual interpretation is restrained chrome and clear primary actions | Calm typography, compact toolbars, contextual detail, existing global navigation |
| [Procore Project Overview](https://support.procore.com/products/online/user-guide/project-level/project-overview/tutorials/about-the-project-overview) | Relevant open work, project context and direct entry into action | An operational attention list with trustworthy counts, owners and record links |
| [Autodesk Insight](https://help.autodesk.com/cloudhelp/ENG/Docs-Insight/files/getting-started-with-insight/About_Insight.html) | Curated domain dashboards and configurable views | Focused domain analysis and later pinned sections |
| [Autodesk shared dashboards](https://help.autodesk.com/cloudhelp/ENU/Docs-Insight/files/Shared_Dashboards.html) | Shared project dashboard configuration | Later, permission-safe saved views if user research demonstrates need |

Keep familiar Yorks Material Request stages and source workspaces. Do not import enterprise complexity simply because another platform supports it. AI prediction and a general dashboard builder are outside this first improvement.

## 5. Target experience

### Overview: “What needs attention now?”

Desktop composition:

1. Compact Overview title, last updated time and Refresh; one contextual primary action if useful.
2. Attention list: category, record/project, state, owner, age, next action; exact “View all” destinations.
3. Three or four compact company-health summaries with source and period definitions.
4. Projects needing attention, with specific reasons rather than invented health/completeness scores.
5. Recent meaningful changes; optional domain summaries below.

Phone composition: title/status, attention-category control, first actionable card, remaining attention cards, summaries, optional sections. Filters open a bottom sheet. Avoid stacking every desktop filter above the first task. Desktop can place summaries alongside the attention list when width permits; reading order must remain logical.

Illustrative structure (not a pixel specification):

```text
Overview                                  Updated 10:42   Refresh
Needs attention                           Company summary
  Awaiting receipt · owner · age · Open      Active projects
  Pending review   · owner · age · Open      Open requests
  View matching records                      Approved financial metric
Projects needing attention
Recent changes
```

### Analytics: “What changed, where, and why?”

- Reuse the global shell and restrained calculator/MR visual language.
- Compact domain tabs on desktop; accessible domain selector on phone.
- Project and period filters with clear scope, applied-filter summary and reset.
- Two or three decision-relevant visualizations per domain, followed by the source table.
- Show units, currency, denominator, period, update time and metric definition where needed.
- Charts and cards open authorized matching records; Back restores filters and scroll position.
- A selected project must not silently include company-wide Workforce or Rental totals.
- Offer previous-period comparison only where the data and definition support it.

Suggested domain questions:

| Domain | Useful question | Definition constraint |
|---|---|---|
| Material Requests | Which stage is waiting, who owns it, and how long? | Use trusted transition history; `updated_at` is not automatically stage age |
| Projects | Which projects have unresolved operational items? | State reasons and source counts, no weighted completion score |
| Accounts | What requires collection, certification or payment attention? | Preserve approved recognition rules, capabilities and separate currencies |
| Workforce | Which authorized attendance records need completion or approval? | No worker productivity inference, payroll or unauthorized personal data |
| Rentals | Which existing leases/payments need attention? | No occupancy percentage with an empty denominator |

### HCI rules

- Reduce choices at entry: prioritize actual tasks; disclose secondary controls when relevant.
- Prefer recognition: familiar MR stage labels, clear verbs and visible owners.
- Preserve control: reversible filters, meaningful Back, no surprise navigation reset.
- Show system state: distinguish loading, confirmed, stale, unavailable, empty and denied.
- Use readable targets and focus: 44px mobile controls, keyboard paths, text scaling and RTL.
- Reserve colour and warnings for meaningful differences; never encode status by colour alone.
- Use progressive disclosure for metric definitions, data coverage and diagnostics.

## 6. Implementation sequence and acceptance

### Phase 0 — definitions and baseline

Deliver metric dictionary (counted unit, source, scope, permission, period, timezone, denominator, empty/error behavior, drill-down), dependency map and repeatable performance fixture. Confirm reporting timezone; API UTC does not by itself establish the business reporting day.

Baseline tasks: find the next required action; identify its owner; find why a request is waiting; compare a project's selected-period activity; explain a metric from its source records. Test with Admin/management users on desktop and phone.

**Exit:** every retained metric has a definition and an authorized destination; current timings and task observations are recorded without claiming unsupported percentiles.

### Phase 1 — useful first screen

Deliver compact Overview, corrected preview/count relationship, responsive KPI layout, empty-ratio behavior, neutral expected-coverage treatment and simplified mobile Analytics entry. Preserve existing server contracts unless a narrowly specified count contract needs an additive change.

**Exit:** at 1280 x 720 and 360 x 800, the first meaningful task/result is visible without scrolling when data exists; empty/error cases show the appropriate useful alternative. No clipped controls at 200% scale or RTL; no 0/0 percentage; warning state reflects an actionable limitation.

### Phase 2 — focused investigation

Deliver domain-focused Analytics, persistent filters, exact source drill-down and navigation restoration. Add only agreed comparisons supported by authoritative data. Introduce metric definitions without filling the main screen with explanatory prose.

**Exit:** users can reach the matching source record/list within two actions from a metric; period/scope/currency are unambiguous; Back restores context; scoped and unauthorized personas cannot obtain broader values through a route or response.

### Phase 3 — performance and resilience

Measure during Phases 0–2; implement justified optimizations here or earlier when blocking. Deliver lean picker/read dependencies, bounded server queries, coalesced refresh, protected freshness handling and smaller UI components. Consider domain fault isolation only with an explicit versioned contract. Any cache is partitioned by actor, role/capabilities, scope and permission revision, and cleared on lost authority.

**Proposed targets, to confirm against baseline:** warm summary RPC p95 under 1.5 seconds and first useful content under 3 seconds on an agreed connection and representative fixture. Track cold entry separately. These are goals, not measured current results or release claims.

**Exit:** tests cover denied/revoked access, timeout, malformed payload, partial domain failure, offline state, competing refreshes and rapid filter changes. Database changes have positive/negative permission tests and rollback/data-preservation notes. No optional panel blocks the first useful content.

### Phase 4 — user validation and staged release

Pilot with 4–6 actual management users, including a person who reviews on mobile; include separately authorized Accountant/manager personas where relevant. Ask them to perform tasks without coaching. Proposed threshold: at least 4 of 5 participants identify their next action within 10 seconds; treat a small pilot as usability evidence, not a population estimate.

Run the full applicable repository gates, desktop/mobile visual evidence, keyboard/screen-reader checks, source-total reconciliation and permission tests. Deploy staging first, record outcomes, then release under explicit owner authorization with the previous artifact available for rollback. Monitor errors and task outcomes, not just page visits.

## 7. Technical change map

| Area | Current source | Planned responsibility |
|---|---|---|
| Analytics/summary UI | `lib/features/company_overview/presentation/company_analytics_screen.dart` (notably grid ~906, request preview ~1058, badge ~1192) | Split composition; fix hierarchy, preview semantics, responsive filters |
| Overview integration | `lib/features/projects/presentation/screens/yorks_v1_projects_screen.dart`, `yorks_v1_executive_overview.dart` | Preserve shell/fallback, audit eager provider dependencies |
| State/authority | `lib/features/company_overview/application/company_analytics_providers.dart` | Filter continuity, refresh/freshness with authority invalidation |
| Data access | `lib/features/company_overview/data/company_analytics_repository.dart` | Timeouts, typed section outcomes if approved, safe timing instrumentation |
| Definitions | `lib/features/company_overview/domain/company_analytics_models.dart` (~593 occupancy; ~651 attention sum) | Explicit unavailable ratio and well-defined count units |
| Project picker | `lib/shared/providers/yorks_v1_project_portfolio_provider.dart`, `lib/shared/repositories/yorks_v1_project_portfolio_repository.dart` | Preserve shared behavior; consider a separate lean authorized option source |
| Backend | `supabase/migrations/20260905013000_yorks_operational_analytics_company_view.sql` | Profile aggregates; additive follow-up migration only if needed |
| Tests | `test/company_analytics_foundation_test.dart`, `test/company_analytics_route_test.dart`, `test/company_analytics_golden_test.dart`, `test/yorks_v1_executive_overview_golden_test.dart` | Preserve existing protections; add new failure, navigation and responsive witnesses |

## 8. Scope discipline

The first delivery excludes a generic dashboard builder, AI forecasts, weighted project scoring, payroll, company P&L and new automated business actions. Analytics exports are reserved under the current approved contract; a future export requires a separate scoped server/document contract and authorization tests. Existing operational export features are unaffected.

Preserve all records, identifiers, audit history, permissions, source modules and English/secondary-language behavior. This plan does not authorize implementation or deployment by itself.

## 9. Verification for this review

Documentation-only change. The four focused test files listed above passed: **25 tests**, including model/repository, route, interaction and visual cases. Dependency resolution succeeded as part of `flutter test`. Internal Markdown links resolved and `git diff --check` passed. No application build or database reset was run for this prose review; the previous release's reported full baseline (2,556 tests, four skipped, analyzer/web/APK gates) is historical and has not been rerun for this document. No new claim of full-suite, production performance or manual-UAT acceptance is made.
