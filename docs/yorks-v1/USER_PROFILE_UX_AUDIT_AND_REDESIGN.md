# Yorks user profile UX audit and proposed My Yorks redesign

Status: **P01–P05 implemented and locally accepted; P06 staging candidate
deployed, named-persona UAT pending**  
Reviewed: 5 September 2026  
Scope: the signed-in account and its profile entry points across all nine Yorks
roles, supported device sizes, orientations, text scaling and LTR/RTL. This
document does not change authorization, HR records or production behavior.

Visual concept: [responsive My Yorks prototype](evidence/user-profile-v01/my-yorks-profile-concept.html)  
Rendered checks: [desktop 1440x900](evidence/user-profile-v01/my-yorks-profile-desktop-1440x900.png),
[phone portrait 390x844](evidence/user-profile-v01/my-yorks-profile-mobile-390x844.png),
[phone landscape 844x390](evidence/user-profile-v01/my-yorks-profile-landscape-844x390.png)

## Executive finding

The current experience is functional but not coherent. Its visual ingredients
mostly fit Yorks, yet three different concepts are presented as if they were
one profile:

1. the authenticated Yorks account and exact server role;
2. the person's employee/HR/leave/attendance record; and
3. an administrator's view of an employee record.

Desktop also has a profile dialog while the shared `/profile` route is a
different settings page. Mobile enters the full page instead. The same person
therefore sees different facts and actions depending on where and how they
open profile. Exact Yorks roles are also reduced to the older four-role
presentation model in parts of the page. This is the primary source of
confusion.

The proposed correction is one canonical **My Yorks** destination, supported
by a small account popover on desktop. It clearly separates **Account &
access**, **Work identity**, **Preferences**, and **Help & security**. Every
summary and quick action is supplied by protected server projections; the UI
never infers authority.

## Current-state score

| Area | Score | Finding |
|---|---:|---|
| Identity clarity | 42/100 | Account, exact role and employment identity are mixed. |
| Role relevance | 38/100 | Several actions and summaries use broad legacy role conditions. |
| Navigation consistency | 45/100 | Desktop dialog, avatar route and mobile More behave differently. |
| Responsive design | 55/100 | Phone portrait is usable; tablet and landscape behavior are not deliberately designed. |
| Accessibility and localization | 52/100 | Tokens and target sizes are generally sound, but profile copy is partly hard-coded and the state matrix lacks RTL/text-scale evidence. |
| Visual consistency | 68/100 | Cards, spacing and color mostly match Yorks; the information model does not. |
| Trust and explainability | 40/100 | Users cannot readily tell why they have access, which scope applies or what to do next. |
| **Overall** | **49/100** | A serviceable settings surface, not yet an industry-level account and workspace experience. |

## Evidence-backed usability issues

| Severity | Issue | User impact | Required correction |
|---|---|---|---|
| Critical | Two competing signed-in profile surfaces | Facts and actions change by entry point and device. | Make `/profile` the only full destination; desktop uses a small launcher popover that links to it. |
| Critical | Exact nine-role identity is sometimes collapsed into four legacy roles | A Workshop In-Charge, Project Manager or Document Controller can appear generically as Engineer. | Use `YorksV1Role` and protected capability projections everywhere in My Yorks. |
| Critical | Account and employee/HR identity are conflated | An unlinked admin account looks broken; attendance and leave can be mistaken for account authority. | Separate Account & access from optional Work identity. Never fabricate an employee link. |
| High | Broad client conditions show irrelevant actions | Procurement or another non-accountant may see engineering tools before route security denies them. | Render quick actions exclusively from the effective capability/route projection. |
| High | Current summaries are engineering-centric | Accountant, Procurement and Admin see meaningless values or labels such as `—` or `BOQ · MR · Docs`. | Provide role-specific, plain-language summaries or omit unavailable metrics with an explanation. |
| High | No plain explanation of access or scope | Users do not know which projects, buildings, teams or organization authority apply. | Add a read-only Access & scope section with source, effective dates and last verification time. |
| High | No deliberate tablet or landscape profile design | Rotating or widening the device can produce a stretched phone list or a desktop-like page. | Define compact, medium and expanded compositions, including short-height landscape. |
| High | Hard-coded English remains in profile surfaces | Secondary language and RTL behavior become incomplete and inconsistent. | Centralize all labels, state messages, semantics and pluralized values. |
| Medium | Connectivity is represented as an unexplained green profile dot | Account status and network status are easy to confuse. | Label account status and workspace sync separately. |
| Medium | Sign out, settings and account facts move between surfaces | Users must relearn where controls live. | Keep stable section order and one sign-out location on every device. |
| Medium | Test evidence represents mainly one Project Engineer on phone portrait | Role-specific and responsive defects can escape. | Add a nine-role by state by viewport contract with focused pairwise coverage. |

## What is already worth preserving

- Yorks colors, typography, spacing, restrained radii and quiet shadows.
- Clear card grouping and familiar list rows in the current phone profile.
- Existing 44px interaction targets and explicit logout confirmation.
- The exact role copy already present in the Yorks shell.
- Server-authoritative routes and capabilities; the redesign must expose them,
  not replace them.
- Honest unlinked-account placeholders instead of invented employee data.
- Visible workspace sync state, moved into its own correctly labelled area.

## Proposed information architecture

### Desktop account popover

The sidebar account stamp opens a compact launcher, not a second profile
(simplified by [`PRODUCT_DECISIONS.md`](PRODUCT_DECISIONS.md) section 55):

- avatar or initials, name, exact role and email;
- an account warning only when the protected profile cannot be read;
- **My Yorks**, Notifications and Sign out.

Workspace sync, About and zoom are not in the menu: sync stays in the
sidebar, top bar and My Yorks; About is in My Yorks > Help and security;
zoom stays on the keyboard shortcuts and pinch.

It contains no unique statistics or business rules. All detailed information
lives in My Yorks.

### Canonical My Yorks page

> Since [`PRODUCT_DECISIONS.md`](PRODUCT_DECISIONS.md) section 55 the page
> is one profile card (identity and the person's own People record) followed
> by the settings; *Your Yorks today* and the section tabs below are retired.

1. **Identity hero**
   - Yorks account name, exact role and workspace;
   - active/disabled state;
   - signed-in email and optional employee-link state;
   - clear distinction between account role and job title.
2. **Your Yorks today**
   - two to four role-relevant, server-confirmed signals;
   - every card states the current owner or next action when applicable;
   - no false zero during loading and no unexplained dash.
3. **Access & scope**
   - plain-language capability groups;
   - organization, project, building/Common, team or internal-location scope;
   - role default, custom grant/denial or delegation source;
   - effective dates and last server verification;
   - **View access details** and **Refresh access**.
4. **Quick actions**
   - only protected actions currently available to the person;
   - task-specific configuration remains in the task, not profile.
5. **Work identity**
   - optional linked employee number, title, department and contact;
   - attendance/leave link only when that system and relationship are valid;
   - a normalized Workforce worker link remains distinct from an Auth account.
6. **Preferences**
   - secondary language and RTL;
   - personal notification delivery and in-app presentation controls;
   - the fixed AED company reporting currency as a read-only policy;
   - respect system text size and reduced motion rather than duplicate them.
7. **Help & security**
   - workspace sync details, current session, version/environment;
   - report a problem, About and Sign out.

## Role contract

The page frame and section order stay identical. Only protected facts and
actions change.

| Exact role | Identity emphasis | Your Yorks today | Typical quick actions |
|---|---|---|---|
| Project Engineer | Assigned project responsibility | Approvals waiting, receipts to confirm, assigned projects | Review arrangement, open project, create MR |
| Site Engineer | Dated project membership | Draft MRs, receipt actions, assigned projects | Continue draft, confirm receipt, create return |
| Senior Mechanical Engineer | Organization-wide engineering role | Portfolio attention, user-access actions, inventory exceptions read-only | Open project portfolio, manage users, browse inventory |
| Project Manager | Organization-wide engineering role | Portfolio reviews, approvals, authorized commercial attention | Review projects, open approval queue, open Accounts when granted |
| Workshop In-Charge | Workshop and team responsibility | Team attendance, timesheet attention, workshop requests when granted | Open team, maintain attendance, open workshop MR |
| Document Controller | Organization-wide project-document responsibility | Document actions and project activity | Open documents, project, requests |
| Procurement | Procurement workspace | Arrangements, dispatches, returns and inventory exceptions | Arrange request, dispatch, confirm return |
| Accountant | Protected Accounts scope | Claims, receipts/PDCs, supplier bills and due actions | Open claim, record receipt, review due schedule |
| Admin | Administration and audited override | Access, configuration, Workforce and audit exceptions | Manage access, open audit, configure Workforce |

These are presentation examples, not grants. If the protected capability
projection omits an action, My Yorks omits it.

## Responsive and orientation contract

| Context | Composition | Important behavior |
|---|---|---|
| Desktop, 1100px+ | 12-column page; identity/access supporting pane and wider today/actions pane | Persistent Yorks shell; account popover launches the same page; keyboard section navigation. |
| Tablet landscape, 721–1099px | Two panes, about 320px supporting pane plus fluid primary pane | No stretched dialog; preserve selected section on resize/rotation. |
| Tablet portrait | Single reading column with two-column metric/action grids | Horizontal section selector may become sticky below the title. |
| Phone portrait, up to 720px | One column; compact hero; stacked access and preference rows | Full-page route, safe-area padding, 44px+ targets, one primary action at most. |
| Phone landscape / short height | Two compact panes where width permits; otherwise one column without oversized hero | Keep identity and section selector visible; avoid a long settings tunnel. |
| RTL | Mirror layout, chevrons and section order; preserve correct direction for email, IDs and numbers | Arabic/Urdu strings are first-class, not subtitles added after layout. |
| 200% text scale | Cards and metric tiles stack; no fixed heights | No clipping, hidden actions or two-dimensional scrolling. |

Minimum acceptance viewports remain 1440x900, 1366x768, 1180x820,
1024x768, 820x1180, 768x1024, 430x932, 390x844 and 360x800. Add at
least 844x390 and 800x360 short-height landscape evidence.

## State contract

Each section needs explicit, useful states:

- loading skeleton, never a false zero;
- active and server-confirmed;
- no assignment or no pending work;
- employee record linked or intentionally not linked;
- access denied, revoked or changed;
- offline with last-confirmed timestamp;
- stale access refreshing;
- session expiring or expired;
- partial feature rollout;
- recoverable error with exact retry or contact action.

Access changes must invalidate the protected projection and refresh My Yorks
without requiring a logout. A denied action must explain the missing effective
capability in plain language without exposing confidential permission data.

## Design-system extension

Use the existing `AppColors`, `AppSpacing`, `AppTypography` and shared Yorks
cards. Add a small, named component family instead of one-off profile widgets:

- `YorksAccountEntry`
- `YorksAccountPopover`
- `YorksIdentityHero`
- `YorksProfileSectionNavigation`
- `YorksRoleMetricCard`
- `YorksAccessSummaryCard`
- `YorksScopeList`
- `YorksQuickActionGrid`
- `YorksPreferenceRow`
- `YorksAccountStateBanner`

Use existing Yorks navy `#0D2F57`, primary blue `#1769D2`, ink `#17263A`,
muted `#68778A`, divider `#DFE6EE`, soft background `#F5F8FC`, success
`#0C8A61`, warning `#B77916` and error `#C53B45`. Motion remains
150–200ms, non-blocking and reduced-motion aware.

## Implementation roadmap

### Slice P01 — canonical contract and projection

- define one protected `v1_get_my_yorks_profile`-style projection or extend an
  existing protected snapshot without leaking restricted data;
- return exact role, account state, workspace copy, effective scopes, safe
  summary facts and allowed route/action identifiers;
- separate optional employee/worker link data from Auth identity;
- add positive and negative role/RLS tests for all nine exact roles.

Done when client code no longer needs legacy `UserRole` to decide My Yorks
content.

Local implementation evidence is recorded in
[`evidence/user-profile-p01/P01_ACCEPTANCE.md`](evidence/user-profile-p01/P01_ACCEPTANCE.md).
P02 now consumes this protected projection in the desktop account launcher.
P01 added no production deployment, route or visible profile change on its own.

### Slice P02 — one entry model

- replace the current desktop statistics dialog with `YorksAccountPopover`;
- route **Open My Yorks** and all mobile/account avatars to `/profile`;
- keep one Sign out command and one confirmation component;
- preserve current navigation and unrelated modules.

Local implementation and verification evidence is recorded in
[`evidence/user-profile-p02/P02_ACCEPTANCE.md`](evidence/user-profile-p02/P02_ACCEPTANCE.md).
P02 replaces the competing desktop statistics dialog with a compact launcher,
routes account entries to the canonical `/profile` destination, and consolidates
profile sign-out behind one localized confirmation. It does not deploy or begin
the P03 page redesign.

### Slice P03 — responsive page foundation

- build compact, medium and expanded compositions from the same section model;
- add tablet portrait/landscape and phone landscape behavior;
- centralize every string and semantic label;
- support RTL, keyboard, screen readers, reduced motion and 200% text.

Local implementation and verification evidence is recorded in
[`evidence/user-profile-p03/P03_ACCEPTANCE.md`](evidence/user-profile-p03/P03_ACCEPTANCE.md).
P03 replaced the legacy settings composition with one adaptive section model,
used only the protected P01 identity, and retained the accepted P02 route and
sign-out behavior. It deliberately left role-aware operational summaries,
effective access, protected quick actions and separate Workforce identity to
the now-completed P04/P05 slices below.

### Slice P04 — role-aware today, access and actions

- add role-specific safe summary cards backed by server projections;
- show effective scope and access source in plain language;
- render only protected quick actions;
- refresh after capability revision without logout.

P04 is implemented and locally accepted. It adds a protected P01-bound
workspace sidecar, server-confirmed Today metrics, aggregate access source and
scope facts, scheduled authority refresh, and quick navigation requiring both
the P01 action contract and the relevant rollout flag. Accounts remains behind
its stricter organization-portfolio server gate.

### Slice P05 — work identity, preferences and security

- connect linked employee facts without making them account authority;
- keep normalized Workforce worker identity distinct;
- consolidate notification, language, company currency, help, session and sync
  information.

P05 is implemented and locally accepted. The normalized Workforce link remains
a separate, read-only self identity and grants no account or attendance
self-service. Only its safe identity fields are projected; employee, HR,
attendance, assignment, team, supervisor, contact and commercial facts remain
outside My Yorks. Verification evidence for both slices is recorded in
[`evidence/user-profile-p04-p05/P04_P05_ACCEPTANCE.md`](evidence/user-profile-p04-p05/P04_P05_ACCEPTANCE.md).

The later P06 product-owner hardening supersedes two P05 presentation choices:
App Lock is removed and any retained enabled device value is cleared; currency
is fixed to AED and is no longer selectable. Notifications now open a dedicated
personal-control page while the existing bell remains the only notification
centre. These corrections do not change the accepted account/work-identity
separation or any business authorization.

### Slice P06 — verification and staging UAT

- focused widget tests for each role and state;
- pairwise role/capability tests plus all-role identity snapshots;
- desktop, tablet portrait/landscape, phone portrait/landscape evidence;
- LTR/RTL, 100%/200% text, keyboard and screen-reader semantics;
- route denial, live permission refresh, offline/recovery and logout tests;
- fixed AED, removed App Lock, server-owned notification preferences, complete
  shell localization and native/root-destination Back behavior;
- deploy only to dedicated staging after local gates, then conduct named-persona
  UAT before production.

The P06 staging candidate is deployed to the dedicated Yorks non-production
backend and an unaliased Vercel Preview. Migration, protected-function,
configuration, route and byte-hash evidence is recorded in
[`evidence/user-profile-p06/P06_STAGING_UAT.md`](evidence/user-profile-p06/P06_STAGING_UAT.md).
P06 is not accepted until the product owner completes the named-persona checks
on that exact candidate; no production release is implied.

## Acceptance scorecard

Implementation is not accepted merely because the screen is visually clean.
It must prove:

1. one canonical profile destination and no conflicting data surface;
2. exact role and job title are both correct and visibly distinct;
3. all actions match the current protected capability projection;
4. account, employee and Workforce worker records never become interchangeable;
5. every supported viewport, orientation, language and text scale retains all
   information and functionality;
6. loading, empty, denied, offline, stale and error states tell the user what
   happened and what to do next;
7. no restricted commercial, HR or permission details leak into profile
   summaries, caches, analytics or screenshots.
