# Yorks AC. & Ref. — Project Creation & Editing SRS

**Version 1.0 · 2 October 2026 · For product and engineering review**

**130 numbered requirements · 68 acceptance scenarios · 11 screen specifications**

## 1. Document control and scope

This Software Requirements Specification defines the shared Project Creation and Project Editing experience in Yorks AC. & Ref. It preserves the approved five-step setup, introduces precise usability and recovery requirements, and supplies an executable acceptance contract for the implementation team. It is a review baseline—not a claim that the proposed behavior already works in production.

| Control | Value |
| --- | --- |
| Document ID | YORKS-SRS-PROJECT-SETUP-001 |
| Version / issue | 1.0 / 2 October 2026 |
| Owner / audience | Sajid Ali; Yorks product, engineering, operations, implementation and QA teams |
| Status | For product and engineering review. No production changes authorized. |
| Repository reviewed | SajidAfridi/material_ledger / main at b86ff4362cde5c214aaff2906c05b0adac258074 |
| Platform | Existing Flutter / Dart, Riverpod, GoRouter and Supabase architecture |
| Scope | Create, resume, review, edit, save, recover, manage project setup context and observe outcomes |
| Companion | Detailed Sol prompt; UI interaction addendum; requirements, tests, fields, telemetry, audit and error registers |

### 1.1 Authority and requirement classes

The repository authority hierarchy remains binding: approved Yorks V1 Rev 2.0 behavior, effective non-conflicting R35 interaction target, execution pack, approved product decisions and then implementation evidence. The supplied Project Accounts SRS is a cross-module boundary reference, not authority for project setup. This specification does not broaden Accounts, Procurement or team-management privileges. [R01–R04, A01]

| Class | Meaning | Delivery rule |
| --- | --- | --- |
| R | Retained approved product or integration rule | Preserve behavior and historical data. Resolve code/contract disagreement explicitly. |
| T | Proposed target in this specification | Implement in the approved project-setup slice, with evidence. Do not describe it as current functionality. |
| G | Approval-gated extension | Keep unavailable until its decision, data model, authorization and tests are approved. |

“Shall” is normative. All numbered requirements are Must for their applicable release. A G requirement mandates a guard, not immediate implementation of the feature. Tables defining field rules, states, keyboard behavior, error handling and acceptance criteria form part of the associated requirements. Performance values are proposed targets, not measured service guarantees.

### 1.2 Evidence boundary

This review read the pinned repository authority documents, the creation/edit screen, draft model/provider/controller, project models/controller/repository, the base project-update SQL migration and the analytics contract. It also examined the supplied screenshots and the relevant Accounts SRS boundaries. It did not execute the application, query production, run browser/DB tests or exhaustively trace every later SQL override. Static findings below are implementation risks to reproduce, not claimed production incidents. The implementer must inspect the complete current migration chain before altering an RPC. [R01–R13, U01–U02, A01]

### 1.3 Included and excluded

| Included | Excluded or separately controlled |
| --- | --- |
| Five setup steps, local recovery, edit proposals, validation and responsive input | No new statutory accounting, commercial baseline activation, VAT or payment configuration in project creation |
| Reliable create/update orchestration and attachment follow-up | No autonomous offline project activation, team granting or general snapshot upserts |
| Scoped initial membership and existing manage-access entry point | No new external contractor accounts or invitations inferred from company names |
| Audited upload/import boundaries and privacy-safe PostHog events | No unrestricted workbook-to-live-project import or cross-device draft sync without approval |
| Testable UI/HCI and migration safeguards | No redesign of MR, BOQ tables, warehouse, Workforce, Rentals or unrelated modules |

### PRJ-SCP-001 — Preserve the five-step contract
**Class:** R · **Priority:** Must for applicable release · **Sources:** R01, R03, R04, A01 · **Acceptance:** PC-AT-01,PC-AT-02

The system shall retain Project details; Parties & access; Buildings; Attachments; Review & create. Materials and BOQ rows shall not be prerequisites for creating a project. Editing shall reuse the same field components and domain rules rather than create a competing project editor.

### PRJ-SCP-002 — Stable identity and bounded authority
**Class:** R · **Priority:** Must for applicable release · **Sources:** R01, R03, R04, A01 · **Acceptance:** PC-AT-03,PC-AT-04

Every committed command and relation shall use immutable project, scope and Auth identities. Human names and references shall be display/search fields, not foreign keys or authorization evidence. Accounts and Procurement shall not gain technical mutation rights through this redesign.

### PRJ-SCP-003 — One scope-local initialization rule
**Class:** R · **Priority:** Must for applicable release · **Sources:** R01, R03, R04, A01 · **Acceptance:** PC-AT-05,PC-AT-06

A successful create transaction shall create one immutable Common scope, the submitted physical buildings, initial membership history and one independent Workshop Materials folder per real scope using current protected configuration. It shall not seed AC Units, 29 folders or other scopes’ custom folders.

### PRJ-SCP-004 — Separate operational and financial setup
**Class:** R · **Priority:** Must for applicable release · **Sources:** R01, R03, R04, A01 · **Acceptance:** PC-AT-06,PC-AT-07

Creating or editing a project shall not create a commercial baseline, allocate contract value, confirm billing progress, reserve claims, create invoices or change money. Existing Accounts records and historical document snapshots shall remain unchanged.

### PRJ-SCP-005 — No prototype data as business policy
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R03, R04, A01 · **Acceptance:** PC-AT-08

Generated screen values, stars, names, dates and status copy shall not define validation, permissions, committed state or seed data. The implementation shall use this field contract and verified server policy; samples remain isolated test fixtures.

## 2. Source findings and required UI corrections

The original screenshots establish the current layout and five steps. The later generated screens are visual direction only. Preserve their clearer hierarchy, restrained navy/blue palette and purposeful icons, but correct the following before implementation. [U01, U02]

| Finding | Evidence / risk | Target correction |
| --- | --- | --- |
| F01 · Local draft presented as generic “Saved” | Creation recovery is per Auth user and device; there is no cloud-save proof. [R05–R07] | Show “Saved on this device” only after storage acknowledgement; show committed project status separately. |
| F02 · Edit input is not durably recovered | The inspected edit path uses _editDraft in widget state; local-save branches return without writing the draft store. [R08] | Add a separate, versioned edit recovery record without changing live data. |
| F03 · Partially completed subforms can be omitted | Unadded building values, FRP checkbox and uncommitted multi-party text live in local widget/controllers. [R08] | Persist the unfinished sub-editor; warn before committing a project that excludes it. |
| F04 · Success spans multiple operations | Create returns a server draft; activation is a later command; file uploads run afterwards. [R08–R10] | Persist a phase journal; retain confirmed project identity through activation, upload or cleanup failures. |
| F05 · Fields over-required in mockups | The typed model requires reference/name and at least one named building. Other shown fields are optional or conditional. [R09] | Remove unsupported required stars. Floors/levels are labels, not an integer floor count. |
| F06 · Back-only step selection | The inspected selector rejects every forward step click, even when revisiting a previously reached step. [R08] | Allow revisiting visited steps; edit uses directly selectable sections. Preserve unfinished input. |
| F07 · Automatic duplicate-building assumptions | The add handler carries name, levels, address and FRP into the next building form. [R08] | Make reuse explicit with “Add another like this”; do not silently copy FRP. |
| F08 · Edit serializer hazards | Creation draft serialization omits sourceScopeId; false FRP can coexist with a retained true flag in the merged flags map. [R09] | Test and preserve scope IDs; encode explicit true/false. These are static round-trip risks to verify. |
| F09 · Generic failure and directory presentation | Edit projection errors may appear as no permission; command state has no explicit uncertain outcome. [R08, R10] | Separate read failure, denial, validation, conflict and post-send uncertainty. |
| F10 · File metadata versus bytes | Selection metadata persists, but selected bytes are in memory; resume requires reselection. [R08] | Show Selected / Reselect required / Uploading / Finalizing / Ready. Retain pending upload manifest after project success. |
| F11 · Large repeated help and nested cards | The visual references consume substantial width on repeated “Good to know” panels. [U01–U02] | Use concise inline guidance; collapse support at narrower widths; keep a readable primary form. |
| F12 · Analytics must retain its privacy contract | Schema v2 forbids free text and project/record IDs; production replay/autocapture are off. [R13] | Extend existing event/property allowlists; never introduce a second SDK or send draft payloads. |

These findings do not authorize destructive fixes. In particular, adding edit persistence must preserve sourceScopeId, hidden contact fields and all allowed flags; it must not persist a creation-shaped copy that later recreates buildings or clears existing metadata.

## 3. Actors, permissions and activation readiness

| Actor | Setup responsibility | Boundary |
| --- | --- | --- |
| Project Engineer | Create; edit authorized draft/active projects; manage permitted team membership | Current membership/capability checks still apply. |
| Site Engineer | Create; edit authorized project details/BOQ context | Creation-time exception permits at most one initial Project Engineer selection; not unrestricted team administration. |
| Global engineering roles | Senior Mechanical Engineer, Project Manager, Workshop In-Charge, Document Controller | Retain exact title and approved global-engineering authority; do not insert synthetic memberships merely to grant access. |
| Admin | Authorized administration and audited corrections | No bypass of versioning, history or invalid inputs. |
| Procurement / Accountant | Only their authorized read or module-specific context | No project create/edit or technical-membership grant from this flow. |

Role descriptions are not a grant matrix. Current server-controlled exact identity, capability, membership, project lifecycle and record command availability remain authoritative. The screenshots’ checked cards do not prove that every displayed person is eligible for every project role. [R01, R03, R04]

### PRJ-AUT-001 — Authorize every read and mutation
**Class:** R · **Priority:** Must for applicable release · **Sources:** R01, R03, R04, R09–R12 · **Acceptance:** PC-AT-03,PC-AT-04,PC-AT-09

The server shall verify active identity, exact role, effective scoped capability, membership and record state for every project read, create, update, membership and lifecycle command. Missing or stale authorization shall fail closed; UI visibility shall not provide authority.

### PRJ-AUT-002 — Separate initial access from later team changes
**Class:** R · **Priority:** Must for applicable release · **Sources:** R01, R03, R04, R09–R12 · **Acceptance:** PC-AT-09,PC-AT-10

Initial member assignment shall use the retained creation transaction and its exact Site Engineer exception. Later assignments/revocations shall use protected membership commands with reason and expected version, never an initial_members field smuggled into a project update.

### PRJ-AUT-003 — Activation needs an eligible Project Engineer
**Class:** R · **Priority:** Must for applicable release · **Sources:** R01, R03, R04, R09–R12 · **Acceptance:** PC-AT-10,PC-AT-11

The system shall activate only when the server’s active Project Engineer prerequisite is met. A valid created project without that prerequisite shall remain an explicitly described server draft. Saving local input is always distinct from activation.

### PRJ-AUT-004 — Explain membership consequences before commit
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R03, R04, R09–R12 · **Acceptance:** PC-AT-10,PC-AT-12

The review shall show the creator’s automatic membership where applicable, selected members’ exact roles and which access will take effect. Selecting a company as Client, Consultant or Contractor shall not invite that company or create an external account.

### PRJ-AUT-005 — Searchable safe team picker
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R03, R04, R09–R12 · **Acceptance:** PC-AT-09,PC-AT-12

The team selector shall use the existing authorized active-user directory, show role and a permitted disambiguator for similar names, and retain selected IDs across search/filter changes. It shall not infer duplicates by name or change a person’s role from an avatar card.

### PRJ-AUT-006 — Revocation and session changes
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R03, R04, R09–R12 · **Acceptance:** PC-AT-13,PC-AT-14

When sign-out, user change or revocation is detected, the client shall fence pending saves to their original owner/context, clear protected active views and reauthorize new requests. It shall never restore one user’s local proposal to another or expose unauthorized directory/cache data.

### PRJ-AUT-007 — Lifecycle-dependent editability
**Class:** R · **Priority:** Must for applicable release · **Sources:** R01, R03, R04, R09–R12 · **Acceptance:** PC-AT-15

Normal metadata edits shall respect the retained Draft/Active state rules. On Hold, Completed and Archived shall not be made editable by reusing the Create form. An unavailable action shall state the safe reason and link to an authorized next step.

### PRJ-AUT-008 — Prevent removal of necessary access
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R03, R04, R09–R12 · **Acceptance:** PC-AT-10,PC-AT-15

Team removal or replacement shall preview affected responsibility and be validated by its trusted command. The UI shall not invent a Site Engineer promotion or remove an activation/approval prerequisite merely to make the setup appear complete.

## 4. Field contract and error-preventing entry

The field inventory below is grounded in the inspected typed model and base command. R refers to retained field semantics; additions to presentation are targets. Limits not present in inspected evidence shall be obtained from the current schema/configuration before release, rather than invented or enforced by silent truncation. [R08–R12]

| Field / label | Requirement | Handling |
| --- | --- | --- |
| project_ref / York Reference / Ref. No. | Required at commit; incomplete allowed in local draft | Text; trim/case normalization per server; preserve leading zeroes. Do not reserve by local save. |
| name / Project name | Required at commit | Preserve full name; use wrapping or disclosure in headings. No forced all-caps input. |
| client / Client / end user | Optional | Existing readable party input; search enhancement only if authorized master is available. No implicit contact/account creation. |
| job_contract_reference / Contract / Job No. | Optional | Text, not a money field; preserve punctuation and leading zeroes. |
| project_site / Site location | Optional | Readable address/location text. Do not require GPS or geocoding. |
| start_date / Start date | Optional; Today is an explicit helper | ISO date at boundary. Do not silently stamp today into restored or edited empty data. |
| target_completion_date / Expected end date | Optional | If both dates exist, end >= start; preserve absent versus entered. |
| notes / Project notes | Optional | Multiline plain text; preserve paragraphs. No financial or security commands hidden in notes. |
| client contacts / Contact name / phone / email / address | Optional; progressive disclosure | Preserve existing hidden values on edit. Validate only entered values and current supported constraints. |
| consultant / Consultant | Optional | One party of this kind; clearing is a deliberate edit. |
| main_contractor / Main contractor | Optional | One party of this kind; show typed pending value before list/step change. |
| subcontractors / Subcontractors | Optional repeatable list | Stable local row identity; explicit add/remove with recoverable input. Duplicate warning does not merge history. |
| other_contractors / Other contractors | Optional repeatable list | Never reinterpret legacy authorityRef. Names do not grant access. |
| initial_members / Project team | Conditional for activation | Eligible directory records only; activation needs active PE. Site Engineer creation exception remains bounded. |
| buildings / Physical buildings | At least one named building at commit | Common is system-created and excluded from physical count. No default building inferred from title. |
| building.code / Building code | Optional; blank permits server generation | Current base SQL canonical format: 1–64 ASCII letters/digits/_/- starting alphanumeric, normalized case. Verify later overrides. |
| building.name / Building name | Required for each added building | Not required until row is being applied/committed; reject whitespace-only. |
| building.floors_levels / Floors / levels | Optional list of text labels | Examples B1, Ground, L1, Roof. “3” is a label unless an explicit separate count feature is approved. |
| building.delivery_address / Delivery address | Optional | Offer explicit Copy site location, not an invisible changing link. |
| building.has_frp_room / Has FRP room | Boolean per building; retained default false | True/false must round-trip exactly. No FRP capacity field; no inheritance from another building unless explicitly copied. |
| building.sourceScopeId / Existing building identity | Mandatory internal identity for retained edit rows | Hidden immutable reference. Preserve through draft reload and update; never recreate it from the code/name. |
| attachments / Project documents | Optional selection | Metadata is not uploaded evidence; bytes may require reselection. File policy from controlled document service. |

### PRJ-FLD-001 — Only authoritative required fields
**Class:** R · **Priority:** Must for applicable release · **Sources:** R08, R09, R12; E01, E04, E05 · **Acceptance:** PC-AT-08,PC-AT-16

The form shall require project reference, project name and at least one valid named building at commit, plus action-specific authorization prerequisites. Optional client, consultant, main-contractor, date, code, level and address inputs shall not acquire required stars from a mockup.

### PRJ-FLD-002 — Reference validation without destructive normalization
**Class:** T · **Priority:** Must for applicable release · **Sources:** R08, R09, R12; E01, E04, E05 · **Acceptance:** PC-AT-16,PC-AT-17

Reference availability checks shall be advisory, debounced and server-scoped; a unique constraint remains authoritative at commit. Display proposed normalization without moving the caret or losing leading zeroes. Duplicate errors shall not disclose another unauthorized project’s identity.

### PRJ-FLD-003 — Long text and hidden-field preservation
**Class:** T · **Priority:** Must for applicable release · **Sources:** R08, R09, R12; E01, E04, E05 · **Acceptance:** PC-AT-18

Long official names and permitted multiline text shall remain editable and recoverable. A layout abbreviation shall not truncate stored data. Editing a visible subset shall preserve existing supported contact fields, flags and metadata unless the user explicitly changes them.

### PRJ-FLD-004 — One keyboard-friendly date control
**Class:** T · **Priority:** Must for applicable release · **Sources:** R08, R09, R12; E01, E04, E05 · **Acceptance:** PC-AT-19,PC-AT-20

Each date shall accept unambiguous typed input and an accessible calendar button. Use one field per date rather than three obligatory tab stops. The displayed format shall be explained; the boundary shall preserve a calendar date, not shift it through UTC.

### PRJ-FLD-005 — Date rules and blank semantics
**Class:** R · **Priority:** Must for applicable release · **Sources:** R08, R09, R12; E01, E04, E05 · **Acceptance:** PC-AT-19

Optional blank dates shall remain null. Entered dates shall be real calendar dates within the retained supported window, with end not before start when both exist. Invalid partial date text shall remain in the local editor until corrected, not normalize into another valid day.

### PRJ-FLD-006 — Progressive validation
**Class:** T · **Priority:** Must for applicable release · **Sources:** R08, R09, R12; E01, E04, E05 · **Acceptance:** PC-AT-16,PC-AT-19,PC-AT-21

Validate a field after meaningful interaction or attempted continuation; validate the complete payload before commit. Keep input, show a specific inline remedy and a linked summary for multiple errors. Required-but-untouched fields shall not all appear red on first load.

### PRJ-FLD-007 — No implicit master-data creation
**Class:** T · **Priority:** Must for applicable release · **Sources:** R08, R09, R12; E01, E04, E05 · **Acceptance:** PC-AT-12,PC-AT-22

Autocomplete shall show authorized existing choices and, only where already supported, an explicit use-as-text choice. Entering a new party name shall not create a supplier account, contact record, user or permission grant in the background.

### PRJ-FLD-008 — Preserve unfinished entries
**Class:** T · **Priority:** Must for applicable release · **Sources:** R08, R09, R12; E01, E04, E05 · **Acceptance:** PC-AT-23

Pending contractor chips and partially entered building rows shall be part of recoverable form state. On final review, require an explicit Add/apply or discard decision for meaningful unadded values rather than silently dropping them.

### PRJ-FLD-009 — Readable errors before busy states
**Class:** T · **Priority:** Must for applicable release · **Sources:** R08, R09, R12; E01, E04, E05 · **Acceptance:** PC-AT-21,PC-AT-24

Local validation shall complete before a network spinner. A disabled commit control shall have a visible reason when it cannot be invoked; ordinary Continue may remain actionable to expose field errors. Do not replace actionable validation with a generic toast.

## 5. Screen and navigation specification

Use one shared ProjectSetupForm domain/controller composition with create and edit modes. This is not a mandate for one enormous widget. Reuse small existing form, shell, focus, document, permission and error components. Retain Yorks typography, spacing and colors; use a stronger visual hierarchy without adding charts to a data-entry task.

| Screen | Purpose | Required content |
| --- | --- | --- |
| PC-UI-01 | Draft entry / resume | Show recoverable local work, save location and last acknowledged time. Resume restores step and unfinished sub-editor. Start new requires a deliberate discard/retain choice under the supported draft policy. |
| PC-UI-02 | Project details | Reference and project name first; client/contract; location; dates; notes. Contacts in optional details. One heading, aligned labels, concise help, visible local-save state. |
| PC-UI-03 | Parties & access | Compact party fields and repeatable lists, then searchable eligible team assignment. Use selected rows/chips with exact roles, not a wall of large avatar cards. Show activation readiness separately from optional parties. |
| PC-UI-04 | Buildings | Compact added-building list plus focused Add/Edit editor. Code optional, name required; levels as text labels; optional address; FRP boolean. Add, Add another like this, and Cancel edit are explicit. |
| PC-UI-05 | Attachments | Small drop area plus Add files. Per-file status, size/type, remove-from-selection and reselect/retry actions. Explain selected files upload after the project exists; optionality remains visible. |
| PC-UI-06 | Review & create | Identity, parties, exact team effect, buildings/FRP, dates and file readiness, each with Edit link. Distinguish Ready to activate from Will remain draft. Show what the next command will do. |
| PC-UI-07 | Creation outcome / recovery | Show known created project reference, activation status and per-file follow-up. Open project after confirmed creation even if later phases need attention. Do not offer a second create to repair an upload. |
| PC-UI-08 | Edit project | Same four input sections plus Review changes. Direct section selection, dirty markers, saved server version and local-proposal state. Save changes is explicit; no autosave into live project records. |
| PC-UI-09 | Conflict / compare changes | Show Your proposal versus Latest permitted values and version. Retain proposal; require review of conflicts. Do not expose protected old values after revocation. |
| PC-UI-10 | Manage access from edit | Protected existing membership workflow in a clearly separate dialog/page. Explicit Apply access change and reason; say it acts immediately and is not part of later Save project. |
| PC-UI-11 | Import/paste review (gated) | Allowed mappings, row errors, counts, duplicate detection, proposed draft changes and provenance. Applying a preview to local input is not committing an import into a live project. |

### PRJ-NAV-001 — Clear create versus edit mode
**Class:** R · **Priority:** Must for applicable release · **Sources:** R03, R08; E02, E03 · **Acceptance:** PC-AT-01,PC-AT-02

The page shall identify Create project or Edit project with the existing immutable project context. The final action shall be Create project or Save changes respectively; edit shall never call createProject as a substitute for updating a record.

### PRJ-NAV-002 — Revisit completed setup steps
**Class:** T · **Priority:** Must for applicable release · **Sources:** R03, R08; E02, E03 · **Acceptance:** PC-AT-25

Creation shall support Back, Continue and direct return to any previously visited step without losing input. Invalid incomplete work may be saved locally. Only progression past the current validation boundary and final commit require the relevant checks; returning to an earlier step is not blocked by an unrelated optional field.

### PRJ-NAV-003 — Direct edit section navigation
**Class:** T · **Priority:** Must for applicable release · **Sources:** R03, R08; E02, E03 · **Acceptance:** PC-AT-02,PC-AT-25

Edit mode shall expose the same section order with freely selectable Details, Parties & access, Buildings, Attachments and Review changes. Switching a section shall not save live changes, reset the proposal or require traversing every earlier step.

### PRJ-NAV-004 — Tab selection and panel focus
**Class:** T · **Priority:** Must for applicable release · **Sources:** R03, R08; E02, E03 · **Acceptance:** PC-AT-25,PC-AT-26

In-page tabs shall distinguish focused from selected state. Use manual Enter/Space activation for panels that may load; arrow and Home/End navigation shall apply only inside the tablist. Stepper links may instead use semantic navigation with equivalent keyboard reachability.

### PRJ-NAV-005 — Preserve context through navigation
**Class:** T · **Priority:** Must for applicable release · **Sources:** R03, R08; E02, E03 · **Acceptance:** PC-AT-23,PC-AT-25,PC-AT-27

Step changes, browser Back/Forward and record-inspector visits shall preserve draft identity, unfinished editor values and stable scroll/focus restoration. URLs/history shall identify allowed context without embedding personal form data or generating a new create intent.

### PRJ-NAV-006 — Honest browser-tab behavior
**Class:** T · **Priority:** Must for applicable release · **Sources:** R03, R08; E02, E03 · **Acceptance:** PC-AT-27,PC-AT-28

Browser Ctrl+Tab and OS app switching shall retain their native function. Returning to the app shall reconcile local draft ownership and any pending command before re-enabling edits, without treating page visibility or route exit as abandonment.

### PRJ-NAV-007 — Review links and outcome labels
**Class:** T · **Priority:** Must for applicable release · **Sources:** R03, R08; E02, E03 · **Acceptance:** PC-AT-11,PC-AT-21,PC-AT-29

Review Edit links shall take the user to the exact section/field and provide a return path to review. Final copy shall describe active versus server-draft outcome, automatic Common/default folders, selected team effect and outstanding files. No unconditional green ready banner is allowed when a prerequisite is unresolved.

### PRJ-NAV-008 — Guard leaving and discarding
**Class:** T · **Priority:** Must for applicable release · **Sources:** R03, R08; E02, E03 · **Acceptance:** PC-AT-14,PC-AT-27,PC-AT-30

Leaving unpublished edits shall offer Keep working or Leave with locally saved draft when storage confirms safety, otherwise explain loss risk. Discard requires explicit confirmation for meaningful content. An unresolved post-send command cannot be forgotten by discarding form input.

## 6. Keyboard, Office familiarity and input methods

Office familiarity means stable labels, predictable field order, visible selection, ordinary clipboard behavior and recoverable edits—not a fake spreadsheet wrapped around every form. The keyboard model is part of release acceptance, including combined touch, mouse, stylus and external keyboard use. APG patterns guide semantics; Flutter implementation must be tested on the actual rendered build. [E01–E06]

| Input | Context | Behavior |
| --- | --- | --- |
| Tab / Shift+Tab | All forms | Move in visible reading order. Label/help text does not add needless stops; no trap in a panel. |
| Enter | Ordinary text field | Do not submit/create the project. Accept an explicit active suggestion or activate a focused button only. |
| Enter / Space | Focused step/tab/button | Activate that control. Manual tabs do not activate on mere focus. |
| Space | Checkbox / FRP toggle | Toggle once; status and accessible value update together. |
| Arrow keys | Open listbox or tablist | Navigate choices without moving the whole form or editing another field. Closed text input retains caret navigation. |
| Home / End | Focused tablist | Focus first/last section; activation remains explicit. In text input retain ordinary text behavior. |
| Escape | Popup / local sub-editor | Close topmost noncommitting popup and return focus. Discard a dirty editor only after confirmation; never reverse a server command. |
| Ctrl+S / Cmd+S | Focused setup route, where intercept is supported | Flush local draft/proposal only and announce location. Never create, activate or apply live edits. Outside this task preserve browser/system behavior. |
| Ctrl+Z / Cmd+Z | Editable text / explicit local list operation | Undo local text or supported draft operation. Do not silently reverse committed membership, project or audit facts. |
| Ctrl+C / X / V / A | Text selection | Standard selection/clipboard. Do not capture paste globally or transform reference text into numbers. |
| Excel/TSV paste | Explicit building paste/import surface only | Show mapping and validation preview. Applying creates draft rows with stable temporary IDs; no implicit live import. |
| Ctrl+Tab / Ctrl+Shift+Tab | Browser tabs | Never override to switch setup steps. Returning triggers non-destructive reconciliation. |
| Ctrl+L / T / W / R / F; Alt+Tab | Browser / OS | Preserve native navigation, refresh, find and app switching. Do not promise async save completes on forced tab close. |
| Tab + Enter | Calendar control | Reach and open calendar without mouse; arrow navigation, month/year selection and Escape work; selected date returns to source field. |
| IME / dictation / mobile Next | Text fields | Preserve composition, caret and selection across rebuild/save; Next moves to the logical next input, Done does not commit the project. |

### PRJ-KEY-001 — Complete keyboard path
**Class:** T · **Priority:** Must for applicable release · **Sources:** E01–E06, R01, R08 · **Acceptance:** PC-AT-26,PC-AT-31

A keyboard-only user shall create, resume and edit a project including parties, eligible team, building FRP, attachment selection and final review without a mouse. Every focusable control shall show a visible focus state and a meaningful accessible name.

### PRJ-KEY-002 — Stable focus objects and caret
**Class:** T · **Priority:** Must for applicable release · **Sources:** E01–E06, R01, R08 · **Acceptance:** PC-AT-31,PC-AT-32

Focus nodes/controllers shall be long-lived and correctly disposed. Draft persistence, validation, directory refresh and responsive rebuilds shall not move the caret to the end, reverse typing, interrupt IME composition or refocus an unrelated field.

### PRJ-KEY-003 — Reading-order traversal
**Class:** T · **Priority:** Must for applicable release · **Sources:** E01–E06, R01, R08 · **Acceptance:** PC-AT-26,PC-AT-33

Tab order shall match visible row-major field order on desktop and the same semantic order when stacked on smaller screens. Each interactive component shall have one documented keyboard model; it shall not require tabbing through hidden columns or offscreen duplicate controls.

### PRJ-KEY-004 — No accidental submission
**Class:** T · **Priority:** Must for applicable release · **Sources:** E01–E06, R01, R08 · **Acceptance:** PC-AT-31,PC-AT-34

Enter in a normal text or multiline field shall not activate Create project or Save changes. There shall be no globally intercepted Ctrl+Enter commit. A final mutation requires an explicit focused action after review.

### PRJ-KEY-005 — Scope keyboard shortcuts
**Class:** T · **Priority:** Must for applicable release · **Sources:** E01–E06, R01, R08 · **Acceptance:** PC-AT-26,PC-AT-34

Implement the keyboard table with route/component-scoped shortcuts only. Preserve browser, OS and assistive-technology shortcuts; user-configurable extra shortcuts shall be disableable. Ctrl/Cmd+S shall save local input, never live project data.

### PRJ-KEY-006 — Accessible pickers and dates
**Class:** T · **Priority:** Must for applicable release · **Sources:** E01–E06, R01, R08 · **Acceptance:** PC-AT-19,PC-AT-31,PC-AT-35

Searchable team/party pickers and date dialogs shall support arrows, Enter, Escape and focus return; expose selected and disabled states and announce loading/no results. A failed lookup shall not clear selections or masquerade as an empty directory.

### PRJ-KEY-007 — Clipboard with explicit mapping
**Class:** T · **Priority:** Must for applicable release · **Sources:** E01–E06, R01, R08 · **Acceptance:** PC-AT-36

Ordinary text paste shall remain literal. Bulk building paste shall be offered only in an approved dedicated preview; preserve leading zeroes, label lists and source row positions. Ignore no invalid row silently, execute no formulas and do not import permissions from pasted names.

### PRJ-KEY-008 — Recoverable local list actions
**Class:** T · **Priority:** Must for applicable release · **Sources:** E01–E06, R01, R08 · **Acceptance:** PC-AT-23,PC-AT-37

Adding, editing, duplicating, removing or reordering local parties/buildings shall use stable IDs and support explicit undo before final commit. Undo shall restore the prior row including FRP and identity; it shall never become an unauthorized server reversal.

### PRJ-KEY-009 — Screen-reader and mixed-input checks
**Class:** T · **Priority:** Must for applicable release · **Sources:** E01–E06, R01, R08 · **Acceptance:** PC-AT-31,PC-AT-33,PC-AT-35

The acceptance matrix shall test Windows keyboard/screen readers, mobile screen readers and tablet external keyboards. Changing input method mid-task shall preserve focus, values and permission semantics.

## 7. Responsive layout and visual quality contract

Recommended composition: compact app shell, one page heading, a five-step rail on wide desktop, a main form, optional concise contextual help and a persistent action area. Do not repeat the page/step title inside multiple nested cards. Symmetry comes from aligned fields, spacing and consistent control sizes, not equal-height empty panels. [U01–U02; target design judgment]

| Viewport / input | Layout contract | Acceptance condition |
| --- | --- | --- |
| Wide desktop ≥1280 CSS px | Two-column fields when each stays readable; step rail; optional help only when adequate width remains | Primary form remains dominant. At 1366×768 the active section and first useful fields appear without scrolling. |
| Compact desktop / tablet 768–1279 | Collapse app navigation/help; adapt steps to a compact selector; one or two field columns based on available width | No three-column squeeze, clipped labels, overlapping footer or nested-page scroll trap. |
| Phone <768 | Single column; compact Step n of 5 with accessible jump list; focused Add/Edit building screen | 44×44 minimum product touch targets, aim 48; keyboard inset and safe-area support; no horizontal form scroll. |
| Zoom and orientation | Reflow at 320 CSS-pixel equivalent; 200% text; 400% zoom test where applicable | Desktop can become phone composition. Genuine 2D preview tables may scroll in a labelled region only. |
| Desktop scaling | Windows 100%, 125%, 150% and 200% display scaling / browser zoom combinations | No illegible text, lost focus ring or pointer hitbox mismatch. |

### PRJ-UX-001 — Consistent visual system
**Class:** T · **Priority:** Must for applicable release · **Sources:** E01, E04–E06; U01, U02 · **Acceptance:** PC-AT-33,PC-AT-38

Reuse AppColors, AppSpacing, AppTypography and shared Yorks controls. Proposed form tokens shall be mapped to them, not introduced as a parallel theme. Use navy identity, blue primary actions, subtle neutral surfaces and semantic color only with text/icons.

### PRJ-UX-002 — Readable symmetric forms
**Class:** T · **Priority:** Must for applicable release · **Sources:** E01, E04–E06; U01, U02 · **Acceptance:** PC-AT-33,PC-AT-38

Related field labels and inputs shall align on a consistent grid, with stable vertical rhythm and room for wrapped labels/errors. Avoid narrow controls created by decorative help panels, forced empty space, duplicate headings or ambiguous icon-only actions.

### PRJ-UX-003 — One primary action per task
**Class:** T · **Priority:** Must for applicable release · **Sources:** E01, E04–E06; U01, U02 · **Acceptance:** PC-AT-29,PC-AT-38

Continue or the reviewed final action shall be visually primary. Save draft, Back, optional Skip and file actions shall be secondary. Destructive actions shall not sit at equal prominence beside a routine continuation.

### PRJ-UX-004 — Guidance at the point of need
**Class:** T · **Priority:** Must for applicable release · **Sources:** E01, E04–E06; U01, U02 · **Acceptance:** PC-AT-21,PC-AT-29,PC-AT-38

Each step shall explain its purpose and important consequence in brief plain language. Optional details may use progressive disclosure. Contextual help shall not repeat long generic instructions or hide mandatory meaning in a tooltip.

### PRJ-UX-005 — Responsive parity
**Class:** T · **Priority:** Must for applicable release · **Sources:** E01, E04–E06; U01, U02 · **Acceptance:** PC-AT-33,PC-AT-39

Desktop, tablet and phone shall expose the same permitted fields and commands, with purpose-built layouts. A smaller device shall not lose project creation, edit, dates, team, FRP, attachments, review or recovery capability.

### PRJ-UX-006 — No obstruction or scroll traps
**Class:** T · **Priority:** Must for applicable release · **Sources:** E01, E04–E06; U01, U02 · **Acceptance:** PC-AT-33,PC-AT-39

The main form shall have one understandable vertical scrolling region. Sticky footers/headers shall reserve space, respect safe areas and the software keyboard, and never obscure the focused field, error or final action. Child lists may be bounded without trapping wheel/touch scrolling.

### PRJ-UX-007 — Accessibility target is testable
**Class:** T · **Priority:** Must for applicable release · **Sources:** E01, E04–E06; U01, U02 · **Acceptance:** PC-AT-31,PC-AT-33,PC-AT-35

The actual Flutter web experience shall target WCAG 2.2 AA. Test contrast, focus visibility, focus not obscured, meaningful order, status announcements, input assistance and reflow; component-library use alone is not evidence of conformance.

### PRJ-UX-008 — No color-only or hover-only meaning
**Class:** T · **Priority:** Must for applicable release · **Sources:** E01, E04–E06; U01, U02 · **Acceptance:** PC-AT-21,PC-AT-33,PC-AT-38

Errors, step completion, selection, offline and saved state shall have textual meaning and accessible state, not color alone. Every essential hover action shall also be available to touch and keyboard users.

### PRJ-UX-009 — Locale and reduced motion
**Class:** T · **Priority:** Must for applicable release · **Sources:** E01, E04–E06; U01, U02 · **Acceptance:** PC-AT-19,PC-AT-32,PC-AT-40

Preserve the application’s configured supported languages, including RTL behavior where supported, translated validation and accessible names. Dates/references shall remain unambiguous. Motion shall be short, nonblocking and disabled/reduced for the user preference.

## 8. Draft persistence and recovery specification

> Four distinct things must never share a misleading “Saved” state: local creation input; a server-created Draft project; a local unpublished edit proposal; and a submitted command whose server outcome is not yet known.

| Record | Meaning | Authority / persistence |
| --- | --- | --- |
| Local creation draft | Recoverable uncommitted input, including incomplete values | Private user/device storage; does not create a project or reserve its reference. |
| Server project in Draft state | A real committed project awaiting activation | Supabase project/scopes/membership records; may have audit and attachments. |
| Local edit proposal | Unapplied changes against a known project/version | Private recovery storage separate from live server data and from a create draft. |
| Operation journal | Original reviewed intent plus phase outcomes | Durable client recovery metadata; the server remains authority for every committed effect. |

Retain local-first behavior. Cross-device/cloud draft sync is not established by the inspected implementation and remains gated. A browser’s origin/storage profile defines the practical device boundary; local data may be lost through explicit clearing, private-mode restrictions, eviction or device loss. Do not promise server backup, device encryption or guaranteed last-keystroke survival on a forced browser/process termination. [R05–R08]

### PRJ-DRF-001 — Local draft has no business side effects
**Class:** R · **Priority:** Must for applicable release · **Sources:** R03, R05–R09; U01 · **Acceptance:** PC-AT-41

Local autosave shall persist recoverable input only. It shall not create project rows, memberships, folders, activation, notifications to team members, commercial records or queued critical commands.

### PRJ-DRF-002 — Separate create and edit storage
**Class:** T · **Priority:** Must for applicable release · **Sources:** R03, R05–R09; U01 · **Acceptance:** PC-AT-02,PC-AT-42

Create and edit drafts shall use distinct versioned records. Edit recovery shall retain immutable project ID, base project version, original editable snapshot and complete unpublished proposal, including sourceScopeId. A restored edit shall never be replayed as a new project.

### PRJ-DRF-003 — Owner and environment isolation
**Class:** T · **Priority:** Must for applicable release · **Sources:** R03, R05–R09; U01 · **Acceptance:** PC-AT-13,PC-AT-14,PC-AT-43

Keys shall isolate verified Auth user, backend/environment, record kind, draft ID and project ID for edit mode. Existing owner-only draft keys shall migrate non-destructively with provenance; staging work must not restore into production or another user’s session.

### PRJ-DRF-004 — Persist all meaningful input
**Class:** T · **Priority:** Must for applicable release · **Sources:** R03, R05–R09; U01 · **Acceptance:** PC-AT-23,PC-AT-32,PC-AT-42

Snapshots shall include completed fields, raw partial date input, unfinished party/building sub-editor, stable temporary row IDs, selected members, per-building FRP, attachments metadata, current/visited step and safe recovery position. Nonserializable file bytes/handles shall not be falsely recorded as durable uploads.

### PRJ-DRF-005 — Acknowledge storage before saved
**Class:** T · **Priority:** Must for applicable release · **Sources:** R03, R05–R09; U01 · **Acceptance:** PC-AT-24,PC-AT-41,PC-AT-44

Track dirty_revision, persisted_revision and storage health separately. Show “Saved on this device” only when the adapter acknowledges that revision; an older completed write shall not mark newer input saved. A storage failure shall retain dirty input and a persistent corrective message.

### PRJ-DRF-006 — Serialize and coalesce local writes
**Class:** T · **Priority:** Must for applicable release · **Sources:** R03, R05–R09; U01 · **Acceptance:** PC-AT-41,PC-AT-44,PC-AT-45

Use one serialized writer per owned draft; coalesce newer snapshots without reordering them. Keep the existing short autosave cadence unless measured changes justify it. After editing settles, target acknowledged recovery within one second on the test device; storage failure is an explicit state.

### PRJ-DRF-007 — Flush deliberate transitions
**Class:** T · **Priority:** Must for applicable release · **Sources:** R03, R05–R09; U01 · **Acceptance:** PC-AT-25,PC-AT-27,PC-AT-41

Continue, Back, step selection, Save draft and supported route exits shall flush and await relevant local writes where possible. Lifecycle/unload hooks are best-effort only; periodic persistence and a pending-intent journal provide recovery. Do not promise an awaited network save on tab close.

### PRJ-DRF-008 — Do not block safe typing on local failures
**Class:** T · **Priority:** Must for applicable release · **Sources:** R03, R05–R09; U01 · **Acceptance:** PC-AT-24,PC-AT-44

When storage is unavailable/quota-limited, show “Draft cannot be saved on this device. Keep this page open.” Keep the in-memory proposal usable and allow explicit connected commit if its required intent journal can be durably established; otherwise block that unsafe submission and explain why.

### PRJ-DRF-009 — Browser single-writer protection
**Class:** T · **Priority:** Must for applicable release · **Sources:** R03, R05–R09; U01 · **Acceptance:** PC-AT-28,PC-AT-45,PC-AT-46

Two tabs opening the same local draft shall not overwrite each other. Use a proven atomic revision/ownership mechanism, such as transactional browser storage with a fencing epoch; broadcasts are hints only. A secondary tab shall open read-only with a deliberate takeover/reload choice.

### PRJ-DRF-010 — Lease takeover and suspended tabs
**Class:** T · **Priority:** Must for applicable release · **Sources:** R03, R05–R09; U01 · **Acceptance:** PC-AT-28,PC-AT-46

Ownership transfer shall atomically increment a fencing generation and re-read the latest persisted revision. A sleeping/resumed former owner shall be unable to overwrite after takeover. All irreversible commands remain server-idempotent even if client coordination fails.

### PRJ-DRF-011 — Preserve corrupt and future-version drafts
**Class:** T · **Priority:** Must for applicable release · **Sources:** R03, R05–R09; U01 · **Acceptance:** PC-AT-43,PC-AT-47

A decode error, unsupported schema or multiple inconsistent legacy records shall show a recovery problem and preserve quarantined data under access controls. It shall not silently start blank, map unknown party types to Other Contractor or discard unknown supported fields.

### PRJ-DRF-012 — Retire drafts after known outcomes
**Class:** T · **Priority:** Must for applicable release · **Sources:** R03, R05–R09; U01 · **Acceptance:** PC-AT-30,PC-AT-48

A confirmed created/updated result shall retire the matching draft with its result identity before cleanup. Tombstones/generations shall prevent stale writers resurrecting it. Cleanup failure shall not turn confirmed success into creation failure or issue another business command.

### PRJ-DRF-013 — Recover incomplete uploads separately
**Class:** T · **Priority:** Must for applicable release · **Sources:** R03, R05–R09; U01 · **Acceptance:** PC-AT-48,PC-AT-49

After a project exists, retain a per-file follow-up manifest until uploads are finalized or the user explicitly removes them from pending work. Retiring creation input shall not erase unresolved upload obligations or imply all files reached the server.

### PRJ-DRF-014 — No implied cloud or multi-draft capability
**Class:** G · **Priority:** Must for applicable release · **Sources:** R03, R05–R09; U01 · **Acceptance:** PC-AT-50

Cross-device cloud draft sync, collaborative draft editing and a general multiple-draft catalogue shall remain disabled until privacy, conflict, retention, ownership and migration policies are approved. The core shall correctly recover the supported local draft rather than claim unsupported availability.

## 9. Connected commands, precision and partial success

The existing create transaction and the later activation/document work are different boundaries. Preserve that architecture unless a separately reviewed backend change deliberately replaces it. The target adds a durable coordinator, not a pretend transaction spanning PostgreSQL and file storage. The current code generates fresh activation/upload keys inside its UI sequence; the target journals stable keys and the exact payload for each attempted phase. [R08, R10, R11]

| Phase | Commit effect | Recovery behavior |
| --- | --- | --- |
| 1. Prepare | Validate proposal and save reviewed canonical payload + intent key locally | No server effect. Block dispatch if the necessary recovery journal cannot be persisted. |
| 2. Create | v1_create_project commits project, scopes, initial membership, default folder initialization and required audit | Persist returned project ID/version. A dropped response is uncertain; replay/query original intent. |
| 3. Activate, when applicable | v1_set_project_state validates active PE and lifecycle independently | Use its own persisted key/version. Failure leaves a known real Draft project, not a failed create. |
| 4. Upload and finalize | Controlled document service creates/finalizes authorized files and links | Per-file stable intent/status. Retry only the affected file/phase; classification rules still apply. |
| 5. Open / retire | Refresh authorized workspace and retire local creation record | Navigation or cleanup error cannot erase a successful project; expose Open existing project. |

### PRJ-CMD-001 — Trusted connected commit only
**Class:** R · **Priority:** Must for applicable release · **Sources:** R01, R03, R08, R10–R12; A01 · **Acceptance:** PC-AT-03,PC-AT-04,PC-AT-51

Project creation, activation, update and access changes shall require connectivity and the authorized RPC path. Generic collection sync, widget-level Supabase writes and automatic offline critical-command replay shall not substitute for a trusted transaction.

### PRJ-CMD-002 — Atomic core creation
**Class:** R · **Priority:** Must for applicable release · **Sources:** R01, R03, R08, R10–R12; A01 · **Acceptance:** PC-AT-05,PC-AT-51,PC-AT-52

The core create command shall commit all required project, Common, building, initial membership, default folder and audit effects together or none. Failure injection shall prove no partial core project or orphan member/folder survives a rollback.

### PRJ-CMD-003 — One durable reviewed intent
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R03, R08, R10–R12; A01 · **Acceptance:** PC-AT-30,PC-AT-45,PC-AT-53

Before a critical request can leave the client, persist its operation kind, stable idempotency key, exact canonical payload/hash and expected versions. While its outcome is uncertain, editing the visible form shall not change the submitted intent; a new payload requires reconciliation and a new explicit intent.

### PRJ-CMD-004 — Server idempotency and concurrency
**Class:** R · **Priority:** Must for applicable release · **Sources:** R01, R03, R08, R10–R12; A01 · **Acceptance:** PC-AT-17,PC-AT-45,PC-AT-52,PC-AT-53

The server shall return the original result for same-key/same-payload replay, reject same-key/different-payload reuse and enforce relevant uniqueness/versions under transaction locks. Double clicks, tab races or network retries shall not duplicate project, activation, membership or audit effects.

### PRJ-CMD-005 — Phase-aware result journal
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R03, R08, R10–R12; A01 · **Acceptance:** PC-AT-11,PC-AT-48,PC-AT-49,PC-AT-54

The coordinator shall persist known create/update result IDs and separate activation/upload outcomes. It shall resume from the earliest unresolved phase rather than rerun successful phases with fresh keys. Confirmed success remains success even if a subsequent phase fails.

### PRJ-CMD-006 — Explicit uncertain-outcome state
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R03, R08, R10–R12; A01 · **Acceptance:** PC-AT-53,PC-AT-54

A timeout or dropped connection after dispatch shall show “We are checking whether your project was saved,” not definitive Not saved. Retain the original key/payload; reconcile through the supported idempotent command/read. Distinguish this from a known pre-send offline failure.

### PRJ-CMD-007 — Reliable activation bridge
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R03, R08, R10–R12; A01 · **Acceptance:** PC-AT-10,PC-AT-11,PC-AT-54

Activation shall use the existing authorized lifecycle command with a persisted phase key and expected version. If it fails or a PE is unavailable, show the created Draft project with a specific next action; do not recreate it or silently promote a member.

### PRJ-CMD-008 — Independent file completion
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R03, R08, R10–R12; A01 · **Acceptance:** PC-AT-49,PC-AT-54

An attachment failure after creation/update shall report “Project saved; some files need attention,” with per-file recovery. It shall neither roll back an already committed project nor label the whole operation failed. Selected file metadata alone is not a finalized document.

### PRJ-CMD-009 — Bounded retry and escalation
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R03, R08, R10–R12; A01 · **Acceptance:** PC-AT-24,PC-AT-53,PC-AT-55

Retry transient reads and reconcilable commands with bounded backoff and jitter, honoring server retry guidance. Do not retry denied/invalid/conflicting writes blindly. Persistent uncertainty shall retain the journal and show a safe support reference; retry limits shall not delete pending intent.

### PRJ-CMD-010 — Fresh read generations and invalidation
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R03, R08, R10–R12; A01 · **Acceptance:** PC-AT-25,PC-AT-56

Late search, directory and portfolio responses shall not replace newer context. After confirmed mutation, invalidate affected authorized project/portfolio, scope, team and document views. A refreshed summary shall not overwrite unpublished field edits.

### PRJ-CMD-011 — Success only from authority
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R03, R08, R10–R12; A01 · **Acceptance:** PC-AT-29,PC-AT-48,PC-AT-54

The UI shall present committed reference, lifecycle and result version only from a confirmed response or reconciliation. A green connection icon, local save time, elapsed spinner or PostHog event shall not be proof of server success.

### PRJ-CMD-012 — Do not reset after post-commit housekeeping errors
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R03, R08, R10–R12; A01 · **Acceptance:** PC-AT-48,PC-AT-54

If refreshing, routing, analytics or local cleanup fails after commit, preserve the confirmed result and provide retry/open-existing controls. Never clear that result, issue another create or ask the user to re-enter the project because housekeeping failed.

## 10. Editing, identity preservation and change review

The same visual form is appropriate for create and edit, but the commit semantics differ. Live updates are explicit versioned commands; local autosave protects a proposal only. Membership management and document upload remain separately acknowledged operations even when their launch points sit inside the same section. [R08–R12]

### PRJ-EDT-001 — Durable unpublished edit proposal
**Class:** T · **Priority:** Must for applicable release · **Sources:** R03, R08–R12; A01 · **Acceptance:** PC-AT-02,PC-AT-42,PC-AT-57

An edit shall load the authorized complete setup snapshot, preserve its base version and save only local proposal changes until the user explicitly applies Save changes. Reopening shall compare latest server state before applying or refreshing the proposal.

### PRJ-EDT-002 — Review an actual diff
**Class:** T · **Priority:** Must for applicable release · **Sources:** R03, R08–R12; A01 · **Acceptance:** PC-AT-18,PC-AT-57

Review changes shall show added, changed and retired fields/rows with readable before/after values, including cleared values and team/file side effects already applied separately. An unchanged save shall be a no-op rather than producing meaningless project_updated events.

### PRJ-EDT-003 — Retain building identities
**Class:** R · **Priority:** Must for applicable release · **Sources:** R03, R08–R12; A01 · **Acceptance:** PC-AT-06,PC-AT-42,PC-AT-58

Editing or reordering existing buildings shall retain their immutable source scope IDs and downstream links. Names/codes shall not be used to recreate or merge scopes; a renamed building remains the same scope in BOQ, MR, documents and Accounts.

### PRJ-EDT-004 — Preserve complete known metadata
**Class:** T · **Priority:** Must for applicable release · **Sources:** R03, R08–R12; A01 · **Acceptance:** PC-AT-18,PC-AT-42,PC-AT-58

Edit serialization shall preserve allowed contact fields, scope flags and supported hidden values when unrelated fields change. The draft envelope shall retain sourceScopeId, and explicit FRP false shall override an earlier true value rather than vanish from a merged flags map.

### PRJ-EDT-005 — Conflict-aware save
**Class:** T · **Priority:** Must for applicable release · **Sources:** R03, R08–R12; A01 · **Acceptance:** PC-AT-46,PC-AT-57,PC-AT-59

Updates shall use fresh expected-version checks. On conflict, preserve the proposal and offer a reviewable three-way comparison of base, latest and proposed authorized values. Never use silent last-write-wins or automatically merge conflicting building/team sets.

### PRJ-EDT-006 — Retire rather than delete linked buildings
**Class:** R · **Priority:** Must for applicable release · **Sources:** R03, R08–R12; A01 · **Acceptance:** PC-AT-06,PC-AT-58,PC-AT-60

Removing a persisted building shall retain its historical scope and downstream records through the supported retirement/deactivation path. Common shall remain immutable. No generic row delete or creation import may hard-delete used scopes.

### PRJ-EDT-007 — Dependency-aware retirement preview
**Class:** T · **Priority:** Must for applicable release · **Sources:** R03, R08–R12; A01 · **Acceptance:** PC-AT-07,PC-AT-60

Before a persisted building is retired, present authorized operational and commercial dependencies. Block unsupported retirement that would strand active work or an active commercial allocation; require the existing controlled reconciliation path. Do not silently rewrite Accounts baselines, claims or historical documents.

### PRJ-EDT-008 — Membership changes are visibly separate
**Class:** T · **Priority:** Must for applicable release · **Sources:** R03, R08–R12; A01 · **Acceptance:** PC-AT-09,PC-AT-10,PC-AT-57

In edit mode, Parties & access shall show current authorized membership and a Manage access entry point only when allowed. Its apply action shall state that access changes take effect independently; the project Save action shall not pretend it atomically includes those separate commands.

### PRJ-EDT-009 — Preserve unknown and legacy semantics
**Class:** T · **Priority:** Must for applicable release · **Sources:** R03, R08–R12; A01 · **Acceptance:** PC-AT-18,PC-AT-43,PC-AT-58

Unknown/legacy fields shall be retained or quarantined for explicit reconciliation according to the approved migration contract. Do not translate authorityRef into Other Contractor, promote legacy engineer roles, or erase information because the new form lacks a field.

### PRJ-EDT-010 — Post-edit return context
**Class:** T · **Priority:** Must for applicable release · **Sources:** R03, R08–R12; A01 · **Acceptance:** PC-AT-27,PC-AT-56,PC-AT-57

After confirmed save, return to the same project and relevant section, refresh the permitted current version and preserve list navigation context. A local edit draft for that result shall retire; unresolved attachment follow-up shall remain recoverable.

## 11. Buildings, parties and guided repetitive work

### PRJ-BLD-001 — Physical building and Common distinction
**Class:** R · **Priority:** Must for applicable release · **Sources:** R03, R08, R09, R12 · **Acceptance:** PC-AT-05,PC-AT-06

The form shall collect only physical buildings. It shall explain that Common / All Buildings is created automatically and is not a fifth building, a billing allocation or an editable duplicate scope.

### PRJ-BLD-002 — Stable local row model
**Class:** T · **Priority:** Must for applicable release · **Sources:** R03, R08, R09, R12 · **Acceptance:** PC-AT-23,PC-AT-37,PC-AT-58

Each uncommitted building and repeatable party shall receive a stable local row ID independent of visual order. Row edit, undo, draft restore and mapped server results shall preserve identity and values without relying on array index alone.

### PRJ-BLD-003 — No hidden carry-forward
**Class:** T · **Priority:** Must for applicable release · **Sources:** R03, R08, R09, R12 · **Acceptance:** PC-AT-08,PC-AT-37,PC-AT-61

After Add building, the next blank editor shall not silently inherit FRP, floors or address. An explicit Add another like this action may prefill a reviewed copy with a visibly suggested unused code; it shall never add an unintended building without confirmation.

### PRJ-BLD-004 — Labels, not inferred floor counts
**Class:** R · **Priority:** Must for applicable release · **Sources:** R03, R08, R09, R12 · **Acceptance:** PC-AT-08,PC-AT-16,PC-AT-61

Floors/levels shall retain the approved list-of-labels meaning and optionality. No numeric control shall convert “3” into three floors or flatten B1/G/Roof into a count. FRP shall remain a per-building boolean without a capacity field.

### PRJ-BLD-005 — Immediate duplicate and invalid-code feedback
**Class:** T · **Priority:** Must for applicable release · **Sources:** R03, R08, R09, R12 · **Acceptance:** PC-AT-17,PC-AT-21,PC-AT-61

Validate an entered building code before applying its row and at final commit, using current server normalization and constraints. Blank code is allowed where server generation is supported; duplicates shall point to the local row without silently appending a suffix to the committed code.

### PRJ-BLD-006 — Helpful address reuse
**Class:** T · **Priority:** Must for applicable release · **Sources:** R03, R08, R09, R12 · **Acceptance:** PC-AT-22,PC-AT-61

Copy site location shall be an explicit reversible action. Later changing site location shall not silently rewrite individual delivery addresses; offer a reviewable bulk update only if approved and authorized.

### PRJ-BLD-007 — Incomplete editor exit control
**Class:** T · **Priority:** Must for applicable release · **Sources:** R03, R08, R09, R12 · **Acceptance:** PC-AT-23,PC-AT-25,PC-AT-37

Moving from a dirty building/party editor shall retain it or offer Apply to draft / Keep unfinished / Discard. Final review shall clearly distinguish added rows from unfinished inputs, so an apparently filled row cannot be omitted unnoticed.

## 12. Documents, file recovery and controlled imports

“Add files” attaches documents. “Import project data” interprets document contents and can alter records. These are different actions and must never be conflated. The current creation path records file metadata and uploads selected bytes after project creation; the target preserves that sequence while making its limitations and failures clear. [R08, A01]

### PRJ-DOC-001 — Reuse controlled document services
**Class:** R · **Priority:** Must for applicable release · **Sources:** R01, R08, A01 · **Acceptance:** PC-AT-49,PC-AT-62

Attachments shall use the existing protected document/version/link service, storage authorization and finalization. No parallel public bucket, arbitrary object-path field or direct widget upload shall bypass classification and entity access.

### PRJ-DOC-002 — Truthful file lifecycle
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R08, A01 · **Acceptance:** PC-AT-49,PC-AT-62

Every selected file shall show Selected on this device, Reselect required, Uploading, Finalizing, Ready, Failed or Removed from pending work as applicable. Only successful server finalization/linking shall be labelled Uploaded/Ready.

### PRJ-DOC-003 — Rerequest bytes safely
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R08, A01 · **Acceptance:** PC-AT-42,PC-AT-49,PC-AT-62

After reload, keep selected file metadata and explain when bytes must be reselected. Filename alone shall not prove the same file; compare supported size/hash metadata and require confirmation for changed content. Do not promise persistent browser file permission or byte recovery that is not implemented.

### PRJ-DOC-004 — Per-file durable retry intent
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R08, A01 · **Acceptance:** PC-AT-49,PC-AT-53,PC-AT-62

Upload attempts shall use stable file-intent IDs and supported idempotent finalize/link commands. A retry after unknown outcome shall check the existing intent/document before uploading another copy. Partial progress shall remain visible after navigation and project success.

### PRJ-DOC-005 — Configured validation and classification
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R08, A01 · **Acceptance:** PC-AT-13,PC-AT-62,PC-AT-63

Enforce existing extension, size, MIME/content and quarantine policy on both supported boundaries. Show configured limits. Commercially sensitive files shall use permitted classification/access; do not treat all files as unrestricted operational evidence or claim malware scanning without deployed support.

### PRJ-DOC-006 — Optional uploads do not hold core creation hostage
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R08, A01 · **Acceptance:** PC-AT-29,PC-AT-49

Users shall be able to proceed without optional documents. Meaningful selected files missing bytes or failing validation require an explicit reselect/remove/defer choice. A committed project remains accessible while permitted uploads are recovered.

### PRJ-DOC-007 — Do not destroy used evidence
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R08, A01 · **Acceptance:** PC-AT-06,PC-AT-62,PC-AT-63

Remove from local selection shall not delete an existing document. Existing file deletion/version replacement shall follow the controlled document policy and retain used evidence. Preview must be appropriate to file type; a ZIP shall not promise a native document preview unless supported.

### PRJ-IMP-001 — Gate general project imports
**Class:** G · **Priority:** Must for applicable release · **Sources:** R01, R03, R13, A01 · **Acceptance:** PC-AT-36,PC-AT-50,PC-AT-64

A general Excel/CSV project-import feature shall remain unavailable until mappings, authorization, validation, conflict/duplicate behavior and rollback are approved. A file-upload control shall never silently parse and apply project or membership data.

### PRJ-IMP-002 — Preview draft-only bulk input
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R03, R13, A01 · **Acceptance:** PC-AT-36,PC-AT-64

An approved building paste/import preview shall show source columns, mapped fields, included/excluded rows and field-specific errors. Apply to draft shall modify only local proposal rows; final project creation/update still requires the normal review and trusted command.

### PRJ-IMP-003 — Preserve provenance and identity
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R03, R13, A01 · **Acceptance:** PC-AT-64,PC-AT-65

For approved imports, retain content fingerprint, source schema/mapping version, source row/sheet references, normalized changes, exclusions and importer attribution. Same filename is not identity; a renamed duplicate shall not become a second committed import.

### PRJ-IMP-004 — No hidden security or financial import
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R03, R13, A01 · **Acceptance:** PC-AT-03,PC-AT-07,PC-AT-64

Import mappings shall not create external accounts, grant roles, assign unauthorized members, reinterpret legacy identities, seed financial baselines or change existing money. Unknown fields and contradictory project references shall be shown for reconciliation, not guessed.

### PRJ-IMP-005 — Idempotent audited apply
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R03, R13, A01 · **Acceptance:** PC-AT-52,PC-AT-64,PC-AT-65

A committed import shall use a protected versioned command or approved orchestrated commands with an explicit partial-result contract. Replaying the same approved intent shall not duplicate records or audit effects. A changed mapping shall be a new reviewed decision, not an invisible bypass.

### PRJ-IMP-006 — Treat workbook content as untrusted
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R03, R13, A01 · **Acceptance:** PC-AT-36,PC-AT-63,PC-AT-64

Import parsing shall not execute macros, formulas, external links or embedded scripts. Preserve textual references and leading zeroes; flag unsupported/ambiguous dates and types. Exports of user text shall neutralize spreadsheet formula injection under the existing export policy.

## 13. User-visible failure and recovery contract

Messages must tell the user what is known, what remains safely available, and the next permitted action. A failure code is not a diagnosis of the underlying infrastructure. Use the protected server’s precise machine code when available; map it to localized copy and an allowed recovery action. New semantic categories below are target adapter contracts, not claims that these exact wire codes already exist.

| Category | Example message | Recovery |
| --- | --- | --- |
| validation | Review highlighted fields | Keep all input; focus the first invalid field; provide links to others. Correct input; do not retry unchanged. |
| duplicate_reference | This project reference is already in use | Preserve proposed reference; reveal other record only when authorized. Choose another reference or open permitted existing record. |
| invalid_building_code | Use letters, numbers, hyphens or underscores | Identify the row and configured limit; no silent rename. Correct or leave blank for supported server generation. |
| directory_unavailable | Team list could not be loaded | Keep selected IDs and show unverified availability, not zero members. Retry lookup; server rechecks at commit. |
| activation_prerequisite | Project created as draft; a Project Engineer is needed | Show known project reference and lifecycle. Assign through permitted workflow, then activate. |
| local_storage_failed | Draft cannot be saved on this device | Retain in-memory input; show last acknowledged revision. Retry storage; keep page open; do not claim cloud backup. |
| offline_before_send | You are offline; the project has not been submitted | Local draft remains private; no server request dispatched. Reconnect and explicitly submit after review. |
| command_outcome_uncertain | We are checking whether your changes were saved | A request was dispatched; do not assert failure or permit changed replay. Check/replay original intent; escalate safely if unresolved. |
| version_conflict | This project changed while you were editing | Keep proposal and show latest authorized version. Review differences; then submit a new validated intent. |
| permission_denied | You no longer have permission for this action | Stop writes and clear unauthorized data; no raw SQL/identity leakage. Request access or return to authorized workspace. |
| session_expired | Sign in again to continue | Keep only policy-permitted recovery, fenced to original owner. Reauthenticate, reauthorize, reconcile pending command first. |
| backend_unavailable | The service is unavailable | Differentiate known no-send from possibly committed write. Bounded read/reconciliation retry; keep input. |
| project_saved_files_pending | Project saved; some files need attention | Show committed project and failed/pending file count. Open project; retry/reselect only those files. |
| dependency_blocked | This building is linked to active work | Show permitted dependency categories without leaking commercial values. Resolve through existing owner/workflow; do not delete. |
| cleanup_failed_after_success | Project saved; local cleanup needs attention | Keep confirmed result and mark original draft retired. Retry cleanup; never create a duplicate. |
| import_rejected | Import has not been applied | Show source rows/fields and whether preview or commit failed. Correct mapping/data; preserve raw provenance. |

### PRJ-ERR-001 — Safe localized error taxonomy
**Class:** T · **Priority:** Must for applicable release · **Sources:** R08, R10, R11; E01, E04 · **Acceptance:** PC-AT-21,PC-AT-24,PC-AT-53

The controller shall expose distinct validation, duplicate, denied, expired-session, conflict, dependency, storage, pre-send offline, service and post-send uncertain states. The UI shall use durable localized messages with next actions and no raw SQL, tokens, stack traces or unrelated record details.

### PRJ-ERR-002 — Known outcome outranks later errors
**Class:** T · **Priority:** Must for applicable release · **Sources:** R08, R10, R11; E01, E04 · **Acceptance:** PC-AT-48,PC-AT-49,PC-AT-54

A committed create/update result shall remain visible even if activation, uploads, refresh or cleanup later fails. Error summaries shall identify the failed phase and successful phases. No generic “Project creation failed” message may replace a confirmed project ID.

### PRJ-ERR-003 — Per-field server errors
**Class:** T · **Priority:** Must for applicable release · **Sources:** R08, R10, R11; E01, E04 · **Acceptance:** PC-AT-17,PC-AT-21,PC-AT-61

Where the server returns safe structured field/row errors, map them to the originating control with stable row identity and preserve user text. A generic invalid-input response shall not invent a more specific cause; provide a review action and safe diagnostic reference.

### PRJ-ERR-004 — Support without sensitive telemetry
**Class:** T · **Priority:** Must for applicable release · **Sources:** R08, R10, R11; E01, E04 · **Acceptance:** PC-AT-24,PC-AT-55,PC-AT-63

A copyable support reference may link an authorized diagnostic record or operation, but PostHog shall receive only allowed categorical errors/counts. Never expose a privileged request payload, personal notes or access-restricted response in a support popup.

## 14. Audit, imports and accountability

The authoritative audit trail and PostHog answer different questions. Audit proves which committed record changed, by whom, with what approved before/after context. PostHog measures usability and reliability without record contents. Neither a client click nor an analytics success event substitutes for transactional audit. [R01, R12, R13]

| Event / status | When | Evidence |
| --- | --- | --- |
| project_created (Existing event family; confirm exact current name) | Core create transaction | Project identity, scopes and initial membership/default-folder result; trusted actor/role/time; intent key. |
| project_updated (Verified base event name) | Successful versioned update | Before/after setup snapshots, affected scope IDs, base/result version and changed field categories. |
| project state transition (Reuse existing event registry) | Activation or permitted lifecycle change | Prior/new lifecycle, prerequisite decision, actor, reason where required and phase intent. |
| project membership assigned/revoked (Reuse existing protected command events) | Actual membership commit | Affected Auth identity, exact/project role, effective period, acting authority and reason; preserve history. |
| document finalized / linked / superseded (Reuse document audit registry) | Document service commit | Project/entity link, classification, immutable version/hash, action and actor. Never only file-selection intent. |
| project import applied (Target event; map approved registry name) | Approved import commit | Source content hash, mapping version, affected records, source row references, exclusions and importing actor. |
| import validation/rejection (Target operational/security evidence) | Rejected preview/apply with no mutation | Outcome, counts and safe reason; distinguish from a successful business audit event. |
| local draft checkpoint (Not a live project business event) | Local adapter acknowledgement | Private recovery revision/time only; do not flood project audit on every keystroke. |

### PRJ-AUD-001 — Transactional server audit
**Class:** R · **Priority:** Must for applicable release · **Sources:** R01, R03, R12, R13; A01 · **Acceptance:** PC-AT-05,PC-AT-52,PC-AT-65

Each committed critical project, scope, membership and lifecycle change shall append required server-owned audit in the same transaction. Failure of required audit shall fail that mutation; client-side analytics success is insufficient.

### PRJ-AUD-002 — Complete import and update provenance
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R03, R12, R13; A01 · **Acceptance:** PC-AT-58,PC-AT-64,PC-AT-65

Audit shall retain the meaningful permitted before/after or immutable revision references, exact actor/role, trusted timestamp, versions, reason and import/source mapping where applicable. Source business dates shall not impersonate the time or author of a historical action.

### PRJ-AUD-003 — Append-only accountability
**Class:** R · **Priority:** Must for applicable release · **Sources:** R01, R03, R12, R13; A01 · **Acceptance:** PC-AT-06,PC-AT-65

Normal application users shall not rewrite committed audit or historical membership/document facts. Corrections and retirement shall append new linked events. Existing actor identities and source import lineage shall survive UI changes.

### PRJ-AUD-004 — Readable audit presentation
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R03, R12, R13; A01 · **Acceptance:** PC-AT-38,PC-AT-65

Activity shall use plain-language action names, changed field summaries and authorized record links. Private local saves and failed previews shall not appear as completed project imports or live updates. Sensitive snapshots remain capability-controlled.

## 15. PostHog measurement plan

The inspected contract uses schema_version=2, lowercase space-separated event names and snake_case property keys. It routes through AnalyticsService → privacy guard → PostHog sink; production replay, Canvas Capture, browser/exception autocapture and debug logging remain disabled. Identity is verified Auth UUID plus exact role only. Project/record/reference IDs, names, filenames, contents, query text and raw errors are prohibited. [R13]

Retain the meaning of “project created”: the create RPC succeeded, not necessarily activation and file completion. Add a separate setup-outcome measurement rather than redefining historical data. Exact per-attempt funnels and cross-step abandonment are not supported by inventing a workflow-run ID: a new correlation identifier needs the existing privacy review. Route exit is not abandonment.

| Event | Status / trigger | Allowed additional context |
| --- | --- | --- |
| project creation started | Existing · Route entry | entry_point · Route mapper; deduplicate rerenders. |
| project creation attempted | Existing · Valid intent reaches repository | building_count, attachment_count · No project name, reference or idempotency key. |
| project created | Existing · Confirmed create RPC result | building_count, attachment_count · Not a proxy for activated or all-files-ready. |
| project creation failed | Existing · Known create failure | error_category · Do not classify unknown outcome as definitive failed commit. |
| project updated | Existing · Confirmed update RPC result | common context · One success emission owner. |
| project update failed | Existing · Known validation/RPC failure | error_category · Unknown outcome separately measured. |
| project access changed | Existing · Protected membership result | action_type, success · No target user or project ID in event properties. |
| attachment upload started / attachment uploaded / attachment upload failed | Existing family · Respective upload/finalize outcome | object_type, type/size buckets; safe durations · Names/content excluded; success after finalization. |
| form validation failed | Existing · Meaningful reviewed validation boundary | form_type, validation_reason, result_count · Categories only; never typed values. |
| operation completed / reliability error occurred | Existing family · Timed operation outcome | operation, duration, success, error_category · Transport failure and commit uncertainty stay distinguishable. |
| project setup step viewed | Proposed · User selects actual setup section | mode, step, entry_point · Not every build; step enum has five allowed values. |
| project draft saved | Proposed · Acknowledged local revision | mode, storage_scope, save_trigger · Coalesce/sample routine checkpoints; no draft ID or timestamp fingerprint. |
| project draft restored | Proposed · Successful owner-scoped restore | mode, step, source · Do not claim cross-device unless approved. |
| project draft save failed | Proposed · Local persistence error | mode, error_category · No serialized draft or file path. |
| project setup conflict detected | Proposed · Ownership or server-version conflict shown | mode, conflict_type · Enums: local_owner, server_version, stale_prerequisite. |
| project command outcome uncertain | Proposed · Post-send result cannot be established | operation, phase, error_category · No command ID; not a confirmed business failure. |
| project command reconciled | Proposed · Original intent’s authoritative outcome known | operation, outcome, phase · Enums and elapsed bucket; deduplicated result. |
| project setup completed | Proposed · Coordinator reaches a known user-facing outcome | mode, outcome · Outcomes active, draft_pending_activation, saved_files_pending, updated. |
| project import previewed / applied / failed | Proposed, feature gated · Approved preview or authoritative import outcome | source_type, row_count, error_category · No source hash, filename, cell content or record IDs. |
| repeated action detected / validation loop detected / action produced no feedback | Existing family · Existing validated friction detector rules | Allowed counts, categories, loading state · No per-keystroke tracking; do not revive retired search-struggle detector. |

### PRJ-ANA-001 — Reuse schema-v2 analytics boundary
**Class:** R · **Priority:** Must for applicable release · **Sources:** R11, R13 · **Acceptance:** PC-AT-66

Instrumentation shall use the existing guarded AnalyticsService and central event/property allowlists in all sinks. No feature widget shall initialize a second SDK, call Posthog().capture directly or dual-send historical schema-v1 events.

### PRJ-ANA-002 — Privacy-safe context only
**Class:** R · **Priority:** Must for applicable release · **Sources:** R11, R13 · **Acceptance:** PC-AT-63,PC-AT-66

Capture only approved common context, enumerations, booleans, bounded counts/durations and categorical error codes. Never send project/draft/record/reference IDs, names, inputs, file names/content, hashes, bank/financial data, URLs, SQL, raw exceptions or tokens.

### PRJ-ANA-003 — Measure phases without redefining success
**Class:** T · **Priority:** Must for applicable release · **Sources:** R11, R13 · **Acceptance:** PC-AT-53,PC-AT-54,PC-AT-66

Preserve existing project-created/update event semantics and distinguish local save, server create, activation and upload outcomes. Add proposed events only with central schema/test updates. Unknown outcomes shall not inflate definitive failure or success counts.

### PRJ-ANA-004 — Nonblocking bounded telemetry
**Class:** T · **Priority:** Must for applicable release · **Sources:** R11, R13 · **Acceptance:** PC-AT-55,PC-AT-66

Analytics initialization, capture, queuing, identity reset and transport failure shall not delay or block draft writes or business commands. Honor environment opt-in and bounded queues; native Windows telemetry remains a no-op where the chosen SDK is unsupported.

### PRJ-ANA-005 — Friction is not user blame
**Class:** T · **Priority:** Must for applicable release · **Sources:** R11, R13 · **Acceptance:** PC-AT-27,PC-AT-66,PC-AT-67

Use existing repeated-action, no-feedback and validation-loop contracts with controlled categories; normal keyboard navigation or route exit is not failure. Do not infer abandonment, frustration or an exact cross-session funnel without an approved measurement design.

### PRJ-ANA-006 — Dashboard and release comparison
**Class:** T · **Priority:** Must for applicable release · **Sources:** R11, R13 · **Acceptance:** PC-AT-66,PC-AT-67

Provide aggregate dashboards for create/update confirmed outcomes, uncertain/reconciled outcomes, per-phase latency, local-save failure, activation blockers and upload finalization. Compare releases/platforms/roles with denominators and sample sizes; missing analytics is not proof of zero errors.

### PRJ-ANA-007 — Do not enable invasive capture
**Class:** R · **Priority:** Must for applicable release · **Sources:** R11, R13 · **Acceptance:** PC-AT-63,PC-AT-66

Production Session Replay, Canvas Capture and automatic browser/exception capture shall remain off under the existing contract. Adding a workflow-run ID, broader identity, or replay requires a separate approved privacy decision and verified masking.

## 16. Data and integration contracts

The following is a conceptual target envelope, not a new live table or API name. Implement it through current repositories/storage adapters and narrowly scoped migrations. Keep raw editable text distinct from validated command payloads. Persistent UI hints must never become server authority. [R01, R05–R12]

| Logical record | Minimum fields | Important constraint |
| --- | --- | --- |
| Draft envelope | schema_version, environment/backend identity, owner Auth ID, draft ID, mode, project ID for edits, base version, revision, acknowledged revision, writer epoch, payload | Internal identifiers remain local/protected; never send them to PostHog. |
| Draft payload | Complete editable proposal, unfinished sub-editors, stable local row IDs, current/visited sections, permitted metadata | Incomplete values are recoverable; command adapter validates before dispatch. |
| Operation journal | operation/phase, immutable reviewed payload and hash, key, expected versions, dispatch status, authoritative result IDs, terminal state | Same pending intent survives reload. New key only for a new confirmed-safe reviewed intent. |
| Attachment manifest | local file ID, metadata/hash where available, byte availability, project/document mapping, upload/finalize intent and status | Metadata-only record is not Ready. Preserve file association through partial success. |
| Conflict state | base snapshot, latest authorized snapshot/version, local proposal, changed-field map | No automatic merge of conflicting identity, access, building retirement or pending command. |
| Local retirement record | draft ID, generation, known outcome/project ID, retirement time, retained file follow-up link | Stops an old writer or failed cleanup from resurrecting a completed creation. |

### PRJ-INT-001 — Keep architectural seams
**Class:** R · **Priority:** Must for applicable release · **Sources:** R01, R03, R05–R12 · **Acceptance:** PC-AT-04,PC-AT-51,PC-AT-68

Widgets shall call Riverpod controllers, which use typed repositories and existing protected RPC/storage services. Realtime shall trigger authorized refresh only. Do not bypass domain commands with generic JSON upserts or move backend logic into a form widget.

### PRJ-INT-002 — Explicit adapter contracts
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R03, R05–R12 · **Acceptance:** PC-AT-43,PC-AT-47,PC-AT-68

Define versioned typed adapters for draft storage, pending intents, files, field errors and project payloads. Map target semantics to real current commands, limits and schema. Preserve old JSON decoding or quarantine incompatible records without loss.

### PRJ-INT-003 — Complete schema and round-trip tests
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R03, R05–R12 · **Acceptance:** PC-AT-18,PC-AT-42,PC-AT-58,PC-AT-68

Tests shall verify null versus blank, raw partial dates, false FRP, hidden contacts/flags, scope IDs, local row IDs, order and edited collections through save, reload, mapping and server response. A “looks right” screenshot is not round-trip evidence.

### PRJ-INT-004 — Environment and secret safety
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R03, R05–R12 · **Acceptance:** PC-AT-03,PC-AT-13,PC-AT-63,PC-AT-68

Build/runtime configuration shall select explicit intended backend and fail closed if missing. No service-role credential, signed private URL, draft payload or privileged diagnostic shall enter browser assets or analytics. Read-only research does not authorize production writes.

## 17. Quality targets, acceptance and release gates

These targets define a test plan, not a promise about current infrastructure. All timings must state device/browser, network, release, data size and load. Improving speed must not weaken audit, version checks or authorization. Use the supported current/previous browser versions verified at release, rather than hardcoded future version numbers.

| Quality area | Proposed target / test envelope |
| --- | --- |
| Input responsiveness | Visible input/click feedback within 100 ms on agreed office laptop and reference phone; no avoidable >200 ms UI-thread stall in ordinary typing. |
| Local draft persistence | Within 1 second after typing settles on the reference device; deliberate Save waits for acknowledgement. Quota/unavailable cases explicitly fail. |
| Connected reads / writes | At documented 100 ms network RTT, p95 meaningful authorized read ≤2 s and normal core create/update response ≤3 s under agreed load; uploads measured separately. |
| Representative scale | 100 physical buildings; 500 proposed building rows for parser stress; 5,000 directory candidates with bounded search; 50 selected members; 50 file metadata entries; 20 concurrent setup sessions including same-reference races. All sizes are targets subject to configuration limits. |
| Browser/device matrix | Windows Chrome/Edge; macOS Safari/Chrome; iPadOS Safari with touch and external keyboard; Android Chrome; iPhone Safari. Include Firefox where supported; native builds use their actual supported matrix. |
| Layout matrix | 1366×768, 1440×900, 1920×1080; 1024×768 and 768×1024; 390×844 and 360×800; 320 CSS-pixel reflow; landscape and keyboard open. |
| Representative user trial | At least five office users and three site/tablet users; ready data; 90% unassisted core-task completion across trials, no critical accidental commits/data loss, median ease score ≥5/7. Report small-sample limitations and observed issues. |
| Reliability | Fault injection before/after each commit/ack, delayed/reordered local writes, multiple tabs, auth change, quota failure, backend down, duplicate click and reload during uncertainty. |
| Release blocker | Any reproducible critical data loss, unauthorized mutation/disclosure, duplicated project/effect, unacknowledged false save, broken core keyboard/mobile flow or missing required audit. |

### PRJ-NFR-001 — Measured interaction performance
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R13; E01–E06 · **Acceptance:** PC-AT-33,PC-AT-39,PC-AT-67

Validate the stated reference-device input, save and request targets using recorded traces and declared workload. Use bounded directory search, debouncing and request generations rather than fetching complete unrestricted lists. Missing infrastructure measurements shall be reported, not assumed from a hosting plan.

### PRJ-NFR-002 — Fault-injection recovery gate
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R13; E01–E06 · **Acceptance:** PC-AT-44,PC-AT-45,PC-AT-48,PC-AT-52,PC-AT-53,PC-AT-54

Before release, exercise failure at every core/phase boundary and prove no duplicate effect, unauthorized overwrite, lost acknowledged draft or false committed status. Coverage shall include actual storage-adapter behavior, not only mocked widgets.

### PRJ-NFR-003 — Visual evidence from working screens
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R13; E01–E06 · **Acceptance:** PC-AT-31,PC-AT-33,PC-AT-38,PC-AT-39

Capture real build screenshots for all five create steps, edit/review, validation, draft resume, offline, conflict and partial success on desktop/tablet/phone. Compare alignment, legibility, focus and footer behavior, not only resemblance to AI images.

### PRJ-NFR-004 — User acceptance is required
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R13; E01–E06 · **Acceptance:** PC-AT-29,PC-AT-31,PC-AT-67

Office and site users shall perform create, resume, edit, error recovery and file retry tasks with keyboard and touch. Record completion, errors and ease scores. Resolve critical usability failures before describing the experience as accepted.

### PRJ-NFR-005 — Additive isolated delivery
**Class:** R · **Priority:** Must for applicable release · **Sources:** R01, R13; E01–E06 · **Acceptance:** PC-AT-06,PC-AT-43,PC-AT-68

Changes shall preserve existing authentication, MR/BOQ workflow, Accounts, scope/membership/document history and unrelated modules. Migrations shall be reviewed, repeatable and non-destructive, with old/new-client compatibility and rollback evidence where applicable.

### PRJ-NFR-006 — Feature and rollout discipline
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R13; E01–E06 · **Acceptance:** PC-AT-50,PC-AT-68

New unaccepted behavior shall remain guarded according to repository release policy. Rollback shall restore consumers without deleting projects, pending outcome journals, evidence or audit. Deployments, production migrations and flag changes require separate authorization.

### PRJ-NFR-007 — Document actual test results
**Class:** T · **Priority:** Must for applicable release · **Sources:** R01, R13; E01–E06 · **Acceptance:** PC-AT-68

The implementation handoff shall record branch/commit, files, migrations, commands, tests, screenshots, unresolved issues and executed versus unexecuted gates. A plan, source inspection or AI assertion shall never be marked as a passed production test.

## 18. Acceptance scenarios and traceability

The following scenarios are minimum release cases. Each includes positive/negative variants where stated. Status is Not run for the application in this documentation task. The CSV register maps every requirement to at least one scenario; implementation teams add executable test names and actual evidence.

### PC-AT-01 — Five-step creation and no materials prerequisite
**Given:** An authorized actor begins a new project with no material rows.

**When:** Complete the five defined steps with valid required setup data.

**Then:** The review and create path works without BOQ/material entry; all five sections use the prescribed names and order.

**Requirements:** PRJ-SCP-001,PRJ-NAV-001

**Status:** Not run — specification only

### PC-AT-02 — Shared edit UI and durable proposal
**Given:** An authorized Draft/Active project exists and edit mode is opened.

**When:** Change two sections, switch directly between them, save locally, close and reopen.

**Then:** The same field components and rules are used; unpublished edits restore against the original project/version; no new project or live update occurred.

**Requirements:** PRJ-SCP-001,PRJ-NAV-001,PRJ-NAV-003,PRJ-DRF-002,PRJ-EDT-001

**Status:** Not run — specification only

### PC-AT-03 — Direct authorization attacks
**Given:** Personas include missing/stale role, Procurement, Accountant and a user scoped to project A only.

**When:** Attempt UI/deep-link and direct RPC operations for project B, substituted IDs and unauthorized initial membership.

**Then:** Each protected boundary denies unauthorized action/data; no cache, draft, import or local role label adds authority.

**Requirements:** PRJ-SCP-002,PRJ-AUT-001,PRJ-CMD-001,PRJ-IMP-004,PRJ-INT-004

**Status:** Not run — specification only

### PC-AT-04 — Architecture and connected authority
**Given:** Spies observe widget, controller, repository, RPC and local-store boundaries.

**When:** Exercise create/update with feature configuration valid, absent and offline.

**Then:** Business writes go through the existing typed trusted path only; no widget Supabase write or generic offline collection replay occurs.

**Requirements:** PRJ-SCP-002,PRJ-AUT-001,PRJ-CMD-001,PRJ-INT-001

**Status:** Not run — specification only

### PC-AT-05 — Atomic initialization and defaults
**Given:** A create payload contains two named physical buildings.

**When:** Commit normally, replay once and inject a failure before required audit.

**Then:** Normal success creates one project, one Common and two physical scopes with one Workshop Materials folder each; replay adds nothing; injected transaction failure leaves no partial core records.

**Requirements:** PRJ-SCP-003,PRJ-CMD-002,PRJ-BLD-001,PRJ-AUD-001

**Status:** Not run — specification only

### PC-AT-06 — Downstream preservation
**Given:** An existing project has scopes, BOQ rows, MRs, documents, memberships and Accounts history.

**When:** Perform permitted setup edits and rehearse application rollback.

**Then:** Stable IDs and unrelated counts/hashes remain intact; no AC Units/29-folder reseeding, cross-scope copies, hard-deletion or financial reset occurs.

**Requirements:** PRJ-SCP-003,PRJ-SCP-004,PRJ-EDT-003,PRJ-EDT-006,PRJ-BLD-001,PRJ-DOC-007,PRJ-AUD-003,PRJ-NFR-005

**Status:** Not run — specification only

### PC-AT-07 — Financial isolation and dependencies
**Given:** A building participates in an active commercial baseline and open operational work.

**When:** Edit noncommercial metadata, then request building retirement or import a monetary allocation.

**Then:** Metadata edits do not change money; unsupported retirement/import is blocked with authorized dependency guidance and no hidden commercial disclosure.

**Requirements:** PRJ-SCP-004,PRJ-EDT-007,PRJ-IMP-004

**Status:** Not run — specification only

### PC-AT-08 — Mockup-versus-field contract
**Given:** The visual examples show stars on client, consultant, code, floors and delivery address.

**When:** Leave all those optional fields blank and provide required reference/name and a named building.

**Then:** Local/model/server validation follows the actual approved contract; optional data is not required by the image; FRP and floor-label semantics remain correct.

**Requirements:** PRJ-SCP-005,PRJ-FLD-001,PRJ-BLD-003,PRJ-BLD-004

**Status:** Not run — specification only

### PC-AT-09 — Initial-team authority matrix
**Given:** Eligible PE/Site members and ineligible/deactivated identities exist.

**When:** Exercise Admin/PE/global-role creation and the Site Engineer one-PE exception; attempt broad assignments and update-payload initial_members.

**Then:** Only allowed initial assignments succeed. Later access changes require separate protected commands; similar names do not override stable identity or exact role.

**Requirements:** PRJ-AUT-001,PRJ-AUT-002,PRJ-AUT-005,PRJ-EDT-008

**Status:** Not run — specification only

### PC-AT-10 — Activation and access safeguards
**Given:** A valid creation has no eligible PE, and another has one.

**When:** Create each; attempt unauthorized promotion/revocation and then valid assignment/activation.

**Then:** The first remains an explicitly described server Draft; the second can activate through the guarded phase. No client-inferred role elevation or prerequisite bypass occurs.

**Requirements:** PRJ-AUT-002,PRJ-AUT-003,PRJ-AUT-004,PRJ-AUT-008,PRJ-CMD-007,PRJ-EDT-008

**Status:** Not run — specification only

### PC-AT-11 — Partial creation: activation blocked
**Given:** Core creation committed but activation is rejected or its response is lost.

**When:** Reload and resume the coordinator.

**Then:** The real project ID remains known; UI says created/activation pending or uncertain. Recovery uses the same phase intent and does not create a second project.

**Requirements:** PRJ-AUT-003,PRJ-NAV-007,PRJ-CMD-005,PRJ-CMD-007

**Status:** Not run — specification only

### PC-AT-12 — Party versus access meaning
**Given:** A party company is typed and two directory entries have similar display names.

**When:** Select parties and authorized team members, filter results and inspect final review.

**Then:** Parties create no external account/invitation. Selected team IDs/roles remain visible and stable; review explains actual access consequences.

**Requirements:** PRJ-AUT-004,PRJ-AUT-005,PRJ-FLD-007

**Status:** Not run — specification only

### PC-AT-13 — Revocation, logout and owner isolation
**Given:** User A has an open proposal and pending reads; authority is revoked or user B signs in.

**When:** Resolve delayed callbacks and reopen setup.

**Then:** New protected reads/writes reauthorize; views clear appropriately. User A’s delayed local save cannot write under user B or reveal A’s proposal.

**Requirements:** PRJ-AUT-006,PRJ-DRF-003,PRJ-DOC-005,PRJ-INT-004

**Status:** Not run — specification only

### PC-AT-14 — Exit while saving or changing session
**Given:** A dirty local draft or uncertain command exists.

**When:** Sign out, switch account or attempt discard/close through supported UI.

**Then:** The user receives honest recovery/loss guidance; pending callbacks are owner-fenced; unresolved intent is retained under policy and never silently replayed for another user.

**Requirements:** PRJ-AUT-006,PRJ-NAV-008,PRJ-DRF-003

**Status:** Not run — specification only

### PC-AT-15 — Lifecycle restrictions
**Given:** Fixtures cover Draft, Active, On Hold, Completed and Archived projects.

**When:** Attempt metadata edits, team changes, activation and archive through UI/API.

**Then:** Only the retained current-state commands are available; unavailable actions explain the safe boundary. No general edit form bypasses lifecycle or historical safeguards.

**Requirements:** PRJ-AUT-007,PRJ-AUT-008

**Status:** Not run — specification only

### PC-AT-16 — Minimum fields and blank semantics
**Given:** A new local draft contains blank/partial required fields and optional empty values.

**When:** Autosave, Continue, then commit variants missing reference, name or buildings.

**Then:** Incomplete local input is recoverable; commit rejects the specific missing prerequisite. Optional blanks remain null/empty as defined, not invented values.

**Requirements:** PRJ-FLD-001,PRJ-FLD-002,PRJ-FLD-006,PRJ-BLD-004

**Status:** Not run — specification only

### PC-AT-17 — Reference and code uniqueness races
**Given:** Two sessions prepare the same normalized project reference or duplicate building codes.

**When:** Run advisory checks, change input while checks are pending and commit concurrently.

**Then:** Late advisory results are discarded; authoritative uniqueness allows no duplicate effect. Leading zeroes and safe record-disclosure limits are preserved.

**Requirements:** PRJ-FLD-002,PRJ-CMD-004,PRJ-BLD-005,PRJ-ERR-003

**Status:** Not run — specification only

### PC-AT-18 — Hidden fields and long-text round trip
**Given:** An existing setup has long names, contacts not expanded in the UI, allowed flags and legacy metadata.

**When:** Edit an unrelated visible field, save/reload the proposal and apply the update.

**Then:** All unchanged supported values remain exact; names are not stored truncated; intentionally cleared values are distinguished from untouched fields.

**Requirements:** PRJ-FLD-003,PRJ-EDT-002,PRJ-EDT-004,PRJ-EDT-009,PRJ-INT-003

**Status:** Not run — specification only

### PC-AT-19 — Dates across locales and boundaries
**Given:** Inputs include leap day, impossible dates, ambiguous two-digit dates, end before start and optional nulls.

**When:** Type/paste/select dates, change timezone/locale and reload draft.

**Then:** Valid calendar dates keep the same day; invalid or ambiguous input is retained with an error; blanks stay absent; no UTC day shift or rollover correction occurs.

**Requirements:** PRJ-FLD-004,PRJ-FLD-005,PRJ-FLD-006,PRJ-KEY-006,PRJ-UX-009

**Status:** Not run — specification only

### PC-AT-20 — Keyboard calendar and null clearing
**Given:** Start/end dates are empty or previously set.

**When:** Use Tab and Enter to open the picker, navigate and choose; Escape another picker; explicitly clear a date.

**Then:** Focus returns to the field; cancellation changes nothing; clearing remains null and does not reinsert Today; review displays an unambiguous year.

**Requirements:** PRJ-FLD-004

**Status:** Not run — specification only

### PC-AT-21 — Progressive, actionable validation
**Given:** A form has untouched required fields, one invalid date and an invalid building code.

**When:** Type, blur, Continue and use the error summary links.

**Then:** No initial wall of errors appears; validation retains input, identifies the specific correction, focuses the correct stable row/field and never falsely enters a network success state.

**Requirements:** PRJ-FLD-006,PRJ-FLD-009,PRJ-NAV-007,PRJ-UX-004,PRJ-UX-008,PRJ-BLD-005,PRJ-ERR-001,PRJ-ERR-003

**Status:** Not run — specification only

### PC-AT-22 — Autocomplete and explicit reuse
**Given:** Party search is available or unavailable; a building has an explicit delivery address.

**When:** Type a novel party, choose Use text where supported, copy site location and later edit site location.

**Then:** No background master/user creation occurs; optional search failure does not erase text; copied delivery address stays unchanged until a deliberate new action.

**Requirements:** PRJ-FLD-007,PRJ-BLD-006

**Status:** Not run — specification only

### PC-AT-23 — Unfinished sub-editor recovery
**Given:** Type a subcontractor without Add and half a building with FRP selected.

**When:** Switch steps, save locally, reload, then review for final commit.

**Then:** Unfinished input restores with its local identity. Review requires an explicit apply/discard/defer decision; nothing appears added merely because its editor was filled.

**Requirements:** PRJ-FLD-008,PRJ-NAV-005,PRJ-KEY-008,PRJ-DRF-004,PRJ-BLD-002,PRJ-BLD-007

**Status:** Not run — specification only

### PC-AT-24 — Local-storage and service error honesty
**Given:** Storage quota/failure, directory read failure and backend unavailable fixtures exist.

**When:** Attempt save and continuation on each fixture.

**Then:** Distinct durable messages describe known state and next action; dirty input remains; no false Saved or No permission is inferred from generic service failure.

**Requirements:** PRJ-FLD-009,PRJ-DRF-005,PRJ-DRF-008,PRJ-CMD-009,PRJ-ERR-001,PRJ-ERR-004

**Status:** Not run — specification only

### PC-AT-25 — Visited steps and direct edit tabs
**Given:** A user reached Review then returned to Details; an edit proposal has changes in Buildings.

**When:** Use step links, keyboard tabs, Back and Continue, including an invalid field.

**Then:** Visited steps remain reachable; edit sections can switch directly; local input persists. Required validation controls progression/commit, not safe backtracking.

**Requirements:** PRJ-NAV-002,PRJ-NAV-003,PRJ-NAV-004,PRJ-NAV-005,PRJ-DRF-007,PRJ-CMD-010,PRJ-BLD-007

**Status:** Not run — specification only

### PC-AT-26 — Tablist and scoped shortcuts
**Given:** Setup tabs, text fields and calendar/picker dialogs are focusable.

**When:** Use Tab/Shift+Tab, arrows, Home/End, Enter/Space, Ctrl/Cmd+S and native browser keys.

**Then:** Control-scoped keyboard behavior matches the guide; focused and selected tabs differ. Save shortcut saves local input only; browser Ctrl+Tab and OS shortcuts are not hijacked.

**Requirements:** PRJ-NAV-004,PRJ-KEY-001,PRJ-KEY-003,PRJ-KEY-005

**Status:** Not run — specification only

### PC-AT-27 — Browser history and visibility changes
**Given:** A dirty draft, focused field and selected section exist.

**When:** Use in-app navigation, browser Back/Forward, switch browser tabs and return.

**Then:** Context is restored without recreating intent or discarding input; access/ownership is rechecked as needed. Route exit is not logged as abandonment.

**Requirements:** PRJ-NAV-005,PRJ-NAV-006,PRJ-NAV-008,PRJ-DRF-007,PRJ-EDT-010,PRJ-ANA-005

**Status:** Not run — specification only

### PC-AT-28 — Two-tab takeover and sleep
**Given:** Two tabs open the same draft and one tab later sleeps.

**When:** Edit concurrently, explicitly take over, then resume the former owner.

**Then:** Only the current fenced writer may persist. Former-owner writes fail safely; latest persisted proposal survives. Broadcast delivery alone is not relied on for correctness.

**Requirements:** PRJ-NAV-006,PRJ-DRF-009,PRJ-DRF-010

**Status:** Not run — specification only

### PC-AT-29 — Review and outcome comprehension
**Given:** Fixtures include active-ready, no-PE, unfinished editor and pending-file setups.

**When:** Review and activate the final allowed action; use Edit links.

**Then:** Users see the actual expected result, exact team/building/FRP content and file status; no invalid setup is called Ready. Review links return to the precise correction.

**Requirements:** PRJ-NAV-007,PRJ-UX-003,PRJ-UX-004,PRJ-CMD-011,PRJ-DOC-006,PRJ-NFR-004

**Status:** Not run — specification only

### PC-AT-30 — Intent survives discard and refresh
**Given:** A create/update request was dispatched with a persisted reviewed payload.

**When:** Drop its response; attempt to edit, discard, refresh and retry.

**Then:** Original key/hash/payload remain immutable until reconciliation; no changed replay or new create is allowed to compensate for uncertainty.

**Requirements:** PRJ-NAV-008,PRJ-DRF-012,PRJ-CMD-003

**Status:** Not run — specification only

### PC-AT-31 — End-to-end keyboard and screen readers
**Given:** An office user uses Windows keyboard with NVDA or Narrator, plus a macOS VoiceOver variant.

**When:** Complete create, edit, team selection, buildings, attachments, review and failure recovery.

**Then:** Every required action is usable and announced, focus remains visible and logical, and there is no keyboard trap or accidental commit.

**Requirements:** PRJ-KEY-001,PRJ-KEY-002,PRJ-KEY-004,PRJ-KEY-006,PRJ-KEY-009,PRJ-UX-007,PRJ-NFR-003,PRJ-NFR-004

**Status:** Not run — specification only

### PC-AT-32 — Caret, IME and asynchronous rebuilds
**Given:** An input contains a mid-string caret/selection or active IME composition.

**When:** Type while debounce saves, directory refreshes, validation and width changes occur.

**Then:** Characters remain in order, caret/composition are preserved and the view does not replace active text with an older draft snapshot.

**Requirements:** PRJ-KEY-002,PRJ-UX-009,PRJ-DRF-004

**Status:** Not run — specification only

### PC-AT-33 — Reflow, contrast and scaling
**Given:** Use the prescribed desktop/tablet/phone, text-size, Windows scaling and 320px reflow matrix.

**When:** Navigate each step and error state, including long translated labels.

**Then:** No control or focused field is clipped/obscured, labels and errors are readable and core forms need no horizontal page scroll; measured contrast/accessibility issues are recorded.

**Requirements:** PRJ-KEY-003,PRJ-KEY-009,PRJ-UX-001,PRJ-UX-002,PRJ-UX-005,PRJ-UX-006,PRJ-UX-007,PRJ-UX-008,PRJ-NFR-001,PRJ-NFR-003

**Status:** Not run — specification only

### PC-AT-34 — Enter and shortcut safety
**Given:** A user is entering notes, dates, a chip and a selected suggestion.

**When:** Press Enter, Ctrl+Enter, Ctrl/Cmd+S and Escape in each context.

**Then:** No ordinary text key submits the project or applies live edits. Suggestion selection and local save work only in their defined context; native shortcuts remain usable.

**Requirements:** PRJ-KEY-004,PRJ-KEY-005

**Status:** Not run — specification only

### PC-AT-35 — Picker accessibility and outages
**Given:** A team/party picker has many items, empty results or an RPC outage.

**When:** Operate via keyboard and mobile reader; select/filter/cancel/retry.

**Then:** Selection remains stable; loading, no results and failed lookup differ. Focus returns correctly and an outage does not claim there are no eligible people.

**Requirements:** PRJ-KEY-006,PRJ-KEY-009,PRJ-UX-007

**Status:** Not run — specification only

### PC-AT-36 — Excel paste preview
**Given:** An approved building-paste surface receives TSV with codes 001, floor labels, invalid rows and formula-like cells.

**When:** Preview mapping, apply to local draft, undo and finally commit valid rows.

**Then:** Codes/labels preserve meaning; invalid rows require resolution; no formula executes and no implicit live import or role grant occurs.

**Requirements:** PRJ-KEY-007,PRJ-IMP-001,PRJ-IMP-002,PRJ-IMP-006

**Status:** Not run — specification only

### PC-AT-37 — Local row undo and duplication
**Given:** Several parties/buildings are added with different FRP/address values.

**When:** Edit, reorder, remove/undo and choose explicit Add another like this.

**Then:** Stable local IDs and all values are restored correctly; duplication is visible and reversible; no operation reverses a committed server fact.

**Requirements:** PRJ-KEY-008,PRJ-BLD-002,PRJ-BLD-003,PRJ-BLD-007

**Status:** Not run — specification only

### PC-AT-38 — Visual and content consistency
**Given:** Working screens are rendered for create, edit, error and recovery states.

**When:** Review shared tokens, label alignment, action emphasis, help density and text wrapping.

**Then:** One coherent Yorks design system is used; forms dominate, no redundant banners/cards displace work, and statuses/actions retain consistent meaning.

**Requirements:** PRJ-UX-001,PRJ-UX-002,PRJ-UX-003,PRJ-UX-004,PRJ-UX-008,PRJ-AUD-004,PRJ-NFR-003

**Status:** Not run — specification only

### PC-AT-39 — Touch, software keyboard and rotation
**Given:** Phone/tablet users have a form or building editor open.

**When:** Focus lower fields, open keyboard, rotate, use split screen and then attach an external keyboard.

**Then:** Focus, draft and selection remain; footer does not obscure input; all commands remain available without shrinking desktop UI into unreadable controls.

**Requirements:** PRJ-UX-005,PRJ-UX-006,PRJ-NFR-001,PRJ-NFR-003

**Status:** Not run — specification only

### PC-AT-40 — Localization and motion
**Given:** Supported languages include long translations and RTL where configured; reduced motion is enabled.

**When:** Change language and complete the setup/recovery workflow.

**Then:** Meaning, dates/references and stored data remain stable; alignment and directional icons adapt; errors/accessibility labels are translated and no critical meaning relies on animation.

**Requirements:** PRJ-UX-009

**Status:** Not run — specification only

### PC-AT-41 — Local acknowledgement and autosave
**Given:** Rapid edits create revisions 1, 2 and 3 while writes are delayed.

**When:** Complete writes and invoke Save draft/Continue.

**Then:** Saved state advances only to actually acknowledged revisions; latest input remains dirty until persisted; no live business record is created by autosave.

**Requirements:** PRJ-DRF-001,PRJ-DRF-005,PRJ-DRF-006,PRJ-DRF-007

**Status:** Not run — specification only

### PC-AT-42 — Create/edit recovery round trip
**Given:** Separate create and edit proposals include pending sub-editors, dates, contact fields, scope IDs and selected file metadata.

**When:** Save locally, restart the app and restore each.

**Then:** Each restores in the correct mode/environment/owner, retaining source IDs and base versions; file metadata correctly requests bytes when necessary.

**Requirements:** PRJ-DRF-002,PRJ-DRF-004,PRJ-EDT-001,PRJ-EDT-003,PRJ-EDT-004,PRJ-DOC-003,PRJ-INT-003

**Status:** Not run — specification only

### PC-AT-43 — Migration and environment isolation
**Given:** Legacy owner-key drafts, unknown fields, and staging/production stores exist.

**When:** Upgrade storage schema and switch authenticated/environment contexts.

**Then:** Existing data is migrated with provenance or quarantined, never silently overwritten/cross-restored. Unknown future data is not guessed into valid business fields.

**Requirements:** PRJ-DRF-003,PRJ-DRF-011,PRJ-EDT-009,PRJ-INT-002,PRJ-NFR-005

**Status:** Not run — specification only

### PC-AT-44 — Storage failures and out-of-order completion
**Given:** A storage adapter delays, rejects or exhausts quota for a snapshot.

**When:** Continue typing, retry save and finish an older pending write.

**Then:** Dirty proposal remains intact; a failed/newer revision is not labelled saved. Serialized/coalesced writes prevent old data replacing the latest acknowledged record.

**Requirements:** PRJ-DRF-005,PRJ-DRF-006,PRJ-DRF-008,PRJ-NFR-002

**Status:** Not run — specification only

### PC-AT-45 — Concurrent writers and duplicate intent
**Given:** Multiple tab/process writers and repeated final clicks target one draft/reference.

**When:** Race local writes and server commands with delayed responses.

**Then:** Local ownership/revisions and server idempotency provide independent protection; exactly one intended core effect survives; no dropped latest acknowledged draft.

**Requirements:** PRJ-DRF-006,PRJ-DRF-009,PRJ-CMD-003,PRJ-CMD-004,PRJ-NFR-002

**Status:** Not run — specification only

### PC-AT-46 — Stale owner and stale server version
**Given:** One tab owns draft generation 1; another takes generation 2 or another actor updates the project.

**When:** Resume old tab and attempt save/apply.

**Then:** Old writer is fenced; stale server update conflicts. Proposal is preserved for explicit reconciliation, not blindly reapplied.

**Requirements:** PRJ-DRF-009,PRJ-DRF-010,PRJ-EDT-005

**Status:** Not run — specification only

### PC-AT-47 — Corrupt/unsupported local state
**Given:** Storage contains invalid JSON, future schema, duplicate legacy records or an unknown party type.

**When:** Open setup and attempt recovery.

**Then:** A recoverable diagnostic appears; raw data remains quarantined under policy. App does not silently return an empty draft or coerce unknown identity/type.

**Requirements:** PRJ-DRF-011,PRJ-INT-002

**Status:** Not run — specification only

### PC-AT-48 — Retirement and housekeeping failure
**Given:** Create/update succeeded but local cleanup or navigation fails; a stale tab still holds the old draft.

**When:** Retry cleanup, reopen setup and resume the stale tab.

**Then:** Confirmed project/result is retained; retired generation cannot resurrect as a fresh creation. User can open existing project and recover pending files.

**Requirements:** PRJ-DRF-012,PRJ-DRF-013,PRJ-CMD-005,PRJ-CMD-011,PRJ-CMD-012,PRJ-ERR-002,PRJ-NFR-002

**Status:** Not run — specification only

### PC-AT-49 — Files after core success
**Given:** Two selected files succeed, one upload fails and another loses bytes on reload.

**When:** Complete project creation, reload and retry pending work.

**Then:** Project remains successful. Per-file manifest/status survives; only failed/missing work is retried/reselected with stable intent; selected metadata is not labelled Uploaded.

**Requirements:** PRJ-DRF-013,PRJ-CMD-005,PRJ-CMD-008,PRJ-DOC-001,PRJ-DOC-002,PRJ-DOC-003,PRJ-DOC-004,PRJ-DOC-006,PRJ-ERR-002

**Status:** Not run — specification only

### PC-AT-50 — Gated features stay gated
**Given:** Cloud draft sync, generalized imports and multi-draft catalogue have no approved implementation.

**When:** Inspect routes/buttons, toggle client state or call unsupported endpoints.

**Then:** No feature pretends to be available or bypasses core guards; the existing local recovery path still functions.

**Requirements:** PRJ-DRF-014,PRJ-IMP-001,PRJ-NFR-006

**Status:** Not run — specification only

### PC-AT-51 — Offline versus connected command
**Given:** One attempt is offline before dispatch; another disconnects after sending.

**When:** Create/update/activate from both states.

**Then:** First is known not submitted and remains local; second becomes uncertain. No critical offline outbox silently activates or changes membership later.

**Requirements:** PRJ-CMD-001,PRJ-CMD-002,PRJ-INT-001

**Status:** Not run — specification only

### PC-AT-52 — Transaction and audit failure injection
**Given:** A valid core create/update/import path has locks and required audit.

**When:** Inject failures after each internal write and audit stage; race two competing requests.

**Then:** Either all required business/audit effects commit or none. Version/uniqueness boundaries and downstream references remain intact.

**Requirements:** PRJ-CMD-002,PRJ-CMD-004,PRJ-IMP-005,PRJ-AUD-001,PRJ-NFR-002

**Status:** Not run — specification only

### PC-AT-53 — Dropped response and idempotent recovery
**Given:** A create, update, activation or file-finalize effect commits but response is dropped.

**When:** Reload/retry the original key, then try the same key with changed payload.

**Then:** Original result is returned without duplication; changed intent conflicts. UI never states failed merely because response was lost.

**Requirements:** PRJ-CMD-003,PRJ-CMD-004,PRJ-CMD-006,PRJ-CMD-009,PRJ-DOC-004,PRJ-ERR-001,PRJ-ANA-003,PRJ-NFR-002

**Status:** Not run — specification only

### PC-AT-54 — Orchestration phase recovery
**Given:** Fixtures fail after create, activation, file finalize, portfolio refresh and navigation.

**When:** Resume after each failure and inspect user message/events.

**Then:** Known success phases remain recorded; only unresolved phases recover. User sees created Draft/Active/files-pending accurately; no duplicate creation or incorrect all-files-complete status.

**Requirements:** PRJ-CMD-005,PRJ-CMD-006,PRJ-CMD-007,PRJ-CMD-008,PRJ-CMD-011,PRJ-CMD-012,PRJ-ERR-002,PRJ-ANA-003,PRJ-NFR-002

**Status:** Not run — specification only

### PC-AT-55 — Retry/analytics outage resilience
**Given:** Transient failures, repeated service outages, rate limits and PostHog transport failure are simulated.

**When:** Run safe bounded retries and exceed the retry budget.

**Then:** Backoff honors supported guidance, UI stays responsive, state remains recoverable and analytics never blocks/changes business behavior. Persistent failures expose safe escalation.

**Requirements:** PRJ-CMD-009,PRJ-ERR-004,PRJ-ANA-004

**Status:** Not run — specification only

### PC-AT-56 — Stale asynchronous reads
**Given:** Search/filter/directory/project refresh requests return out of order.

**When:** Switch contexts and edit a field before earlier reads complete.

**Then:** Old responses are ignored; selections/edits remain. Successful writes refresh relevant authorized projections without erasing pending proposal data.

**Requirements:** PRJ-CMD-010,PRJ-EDT-010

**Status:** Not run — specification only

### PC-AT-57 — Edit review and conflict
**Given:** An edit changes one field while a second actor changes another or the same field; an access change was applied separately.

**When:** Review diff, save, resolve conflict and test unchanged Save.

**Then:** Explicit review shows actual changes/clears and independent access effect. No-op does not create meaningless update audit; conflicting changes require review.

**Requirements:** PRJ-EDT-001,PRJ-EDT-002,PRJ-EDT-005,PRJ-EDT-008,PRJ-EDT-010

**Status:** Not run — specification only

### PC-AT-58 — Scope identity and FRP false
**Given:** An existing building has sourceScopeId and flags.has_frp_room=true with hidden metadata.

**When:** Uncheck FRP, reorder/rename building, persist edit draft, restore and update.

**Then:** The same scope ID remains and FRP is false on server/readback; no new scope or unrelated flag/contact loss occurs.

**Requirements:** PRJ-EDT-003,PRJ-EDT-004,PRJ-EDT-006,PRJ-EDT-009,PRJ-BLD-002,PRJ-AUD-002,PRJ-INT-003

**Status:** Not run — specification only

### PC-AT-59 — Three-way conflict resolution
**Given:** Base, latest and proposed snapshots differ in building lists and reference values.

**When:** Invoke conflict review and choose supported resolutions.

**Then:** User can inspect permitted differences; unsafe identity/access/list changes do not auto-merge. New request uses a reviewed new payload/key and current expected version.

**Requirements:** PRJ-EDT-005

**Status:** Not run — specification only

### PC-AT-60 — Building retirement with open dependencies
**Given:** A persisted building has historical and active downstream records; Common also exists.

**When:** Request removal with and without dependency clearance.

**Then:** No hard-delete or Common removal occurs. Unsupported active dependencies block with a clear next action; permitted retirement preserves historic attribution and commercial snapshots.

**Requirements:** PRJ-EDT-006,PRJ-EDT-007

**Status:** Not run — specification only

### PC-AT-61 — Building defaults and repetitive entry
**Given:** First building has FRP=true, address and labels B1/G/Roof.

**When:** Add it, start the next blank row, use explicit duplicate, and test blank/invalid/duplicate codes.

**Then:** Blank entry does not inherit hidden values; duplicate is visibly proposed. Optional code generation and label list semantics match server; no accidental count conversion occurs.

**Requirements:** PRJ-BLD-003,PRJ-BLD-004,PRJ-BLD-005,PRJ-BLD-006,PRJ-ERR-003

**Status:** Not run — specification only

### PC-AT-62 — File selection, validation and finalization
**Given:** Files include valid, unsupported, changed-content same-name, oversized and unfinalized examples.

**When:** Select, reload/reselect, upload/retry, preview and finalize.

**Then:** Configured policy applies; reselection does not silently substitute different content; only finalized authorized links are Ready. Appropriate preview is offered per type.

**Requirements:** PRJ-DOC-001,PRJ-DOC-002,PRJ-DOC-003,PRJ-DOC-004,PRJ-DOC-005,PRJ-DOC-007

**Status:** Not run — specification only

### PC-AT-63 — Sensitive data and document security
**Given:** Drafts contain names, phones, notes, file content and commercial documents.

**When:** Inspect network telemetry, direct file links, exported errors and identity resets.

**Then:** No prohibited payload reaches PostHog or public storage; file classification/authorization holds; no invented scanning/encryption guarantee is displayed.

**Requirements:** PRJ-DOC-005,PRJ-DOC-007,PRJ-IMP-006,PRJ-ERR-004,PRJ-ANA-002,PRJ-ANA-007,PRJ-INT-004

**Status:** Not run — specification only

### PC-AT-64 — Controlled import and source conflicts
**Given:** An approved import/paste preview receives mismatched project IDs, unknown columns, roles and monetary fields.

**When:** Map and validate, then apply approved draft-only or committed path.

**Then:** Unknown/security/financial mappings do not silently apply; exclusions and errors are visible; import remains distinct from attachment upload and core review is retained.

**Requirements:** PRJ-IMP-001,PRJ-IMP-002,PRJ-IMP-003,PRJ-IMP-004,PRJ-IMP-005,PRJ-IMP-006,PRJ-AUD-002

**Status:** Not run — specification only

### PC-AT-65 — Audit and provenance
**Given:** Project, scope, membership, document and approved import changes are available.

**When:** Commit, replay, reject and correct operations; inspect protected history.

**Then:** Required commits have trusted append-only attribution/version/source evidence; replay does not duplicate effects; failed previews/local keystrokes are not false project updates.

**Requirements:** PRJ-IMP-003,PRJ-IMP-005,PRJ-AUD-001,PRJ-AUD-002,PRJ-AUD-003,PRJ-AUD-004

**Status:** Not run — specification only

### PC-AT-66 — PostHog schema and event correctness
**Given:** Analytics is enabled in a test environment and disabled/unavailable in another.

**When:** Exercise create/update, draft, phase failure/recovery, files and import routes.

**Then:** Events go through existing schema-v2 allowlists, contain only safe properties and preserve semantic success boundaries; no duplicate SDK/replay or sensitive/run IDs are introduced.

**Requirements:** PRJ-ANA-001,PRJ-ANA-002,PRJ-ANA-003,PRJ-ANA-004,PRJ-ANA-005,PRJ-ANA-006,PRJ-ANA-007

**Status:** Not run — specification only

### PC-AT-67 — Usability and measurement trial
**Given:** Representative office/site users use agreed devices with ready task data.

**When:** Run create, resume, edit and failure recovery tasks; compare release/platform samples.

**Then:** Report task completion, observed errors, latency and ease score against targets with sample sizes. Exit is not abandonment; telemetry absence is not zero failures; critical usability issues block release.

**Requirements:** PRJ-ANA-005,PRJ-ANA-006,PRJ-NFR-001,PRJ-NFR-004

**Status:** Not run — specification only

### PC-AT-68 — Integration, regression and release evidence
**Given:** A candidate branch contains the scoped implementation, migration plan and feature guards.

**When:** Run applicable repository gates, direct permission/DB tests, old-data migration and visual checks.

**Then:** Document executed commands/results and limitations, preserve unrelated modules and source records, and provide non-destructive rollback. No unrun test or production action is claimed as completed.

**Requirements:** PRJ-INT-001,PRJ-INT-002,PRJ-INT-003,PRJ-INT-004,PRJ-NFR-005,PRJ-NFR-006,PRJ-NFR-007

**Status:** Not run — specification only

## 19. Delivery sequence and completion criteria

| Slice | Scope | Acceptance evidence |
| --- | --- | --- |
| P0 · Reconcile | Pin current branch; read authority and complete current migration chain; map fields and commands; reproduce static risks | Source map, authority conflicts, baseline tests and preservation checks before edits. |
| P1 · Recovery core | Create/edit storage separation, complete serializers, acknowledgement, ownership and pending-intent journal | Adapter/reload/quota/corruption/multi-tab/owner-switch tests before visual polish. |
| P2 · Shared form | Five steps, direct edit sections, keyboard/pickers, meaningful validation and responsive layout | Working desktop/tablet/phone plus keyboard/IME/zoom evidence. |
| P3 · Connected lifecycle | Versioned create/update; separate activation/upload phase recovery; dependencies and cleanup retirement | Fault injection and race tests proving no duplicate/partial core effects. |
| P4 · Audit and analytics | Retain transactional audit and privacy-safe schema-v2 outcomes; add approved event extensions | Payload inspection, deduplication and telemetry-outage tests. |
| P5 · Acceptance / release | User trials, full applicable gates, migration rehearsal, source/fixture reconciliation and rollback | Signed-off evidence on candidate commit. Staging and production authorization separately recorded. |

Do not perform a broad codebase rewrite. Deliver coherent vertical slices under the repository’s current branch/PR discipline. A new RPC or storage schema requires an additive compatibility plan; a UI-only workaround shall not weaken a server rule. If a safety invariant cannot be established, keep that operation unavailable while completing independent safe work.

Completion requires all applicable Must requirements traced to code and passed tests; zero unresolved critical security/data-loss/duplicate-effect defects; representative-device visuals and manual interaction evidence; explicit known limitations; and product/engineering sign-off. Gated extensions may remain deferred with guards intact. This package itself only verifies the documentation and traceability—not those application gates.

## 20. Decisions, safe defaults and approval boundaries

| Decision / owner | Question | Safe default |
| --- | --- | --- |
| D01 · Product / security | Local draft retention, shared-device clearing and export/recovery policy | Retain current user-isolated local behavior; no automatic purge or new plaintext draft export. Resolve before advertising retention guarantees. |
| D02 · Product / engineering | Party-master search and permitted disambiguators | Use existing plain party input/directory projections; no new master/account creation or extra personal disclosure. |
| D03 · Product / security | Cloud drafts, collaboration and multiple active drafts | Deferred. No claim of cross-device recovery; no workflow-run identity added to analytics. |
| D04 · Product / data owner | General project Excel import and building paste format | General import deferred. Add dedicated local paste preview only after mapping/limit approval; no auto-apply. |
| D05 · Engineering / Accounts | Retiring a scope with operational/commercial dependencies | Block unsupported unsafe retirement; preserve existing IDs and Accounts history; define explicit migration/reconciliation before allowing it. |
| D06 · Technical / QA | Storage adapter capable of atomic writer fencing and recovery journal | Release blocker for promised multi-tab persistence safety. Broadcast-only protection is not sufficient. |
| D07 · Product / UX | Optional Start date Today helper versus visible new-draft default | Core preserves optionality and offers explicit Today; never reset restored/edit dates. Any automatic default must be visibly reviewable and newly approved. |
| D08 · Release / UX | Performance envelope, supported native platforms and user-trial targets | Use Section 17 as proposed acceptance baseline; report environment limits. No unmeasured uptime/recovery promise. |
| D09 · Privacy / analytics | New event/property enums and exact run-level correlation | Extend central allowed categorical properties; keep replay off and identifiers out. Exact cross-attempt tracking needs separate approval. |
| D10 · Product / engineering | Exceptions to baseline field lengths/date/code format | Use actual current schema/configuration; inventory all limits before release, with no truncation or destructive normalization. |

## Appendix A. Source register and implementation anchors

Repository sources were read at the pinned commit unless stated otherwise. URLs below point to that snapshot. Line ranges record inspected portions where relevant; implementations must check later overrides. Web references were consulted on 2 October 2026. Their patterns inform the proposed UX; they do not redefine Yorks permissions or prove that a Flutter implementation is accessible.

### R01 · AGENTS.md

Approved architecture, authority, exact roles and five-step workflow. Inspected: Full document.

https://github.com/SajidAfridi/material_ledger/blob/b86ff4362cde5c214aaff2906c05b0adac258074/AGENTS.md

### R02 · README.md

Repo-local contract index; historical delivery statements are not current tests. Inspected: Relevant authority and integration sections.

https://github.com/SajidAfridi/material_ledger/blob/b86ff4362cde5c214aaff2906c05b0adac258074/docs/yorks-v1/README.md

### R03 · PRODUCT_DECISIONS.md

Approved roles, lifecycle, initial membership, local draft and scope-local initialization. Inspected: Lines 1–278.

https://github.com/SajidAfridi/material_ledger/blob/b86ff4362cde5c214aaff2906c05b0adac258074/docs/yorks-v1/PRODUCT_DECISIONS.md

### R04 · SOURCE_OF_TRUTH.md

Precedence and later Workshop Materials-only/default scope decisions. Inspected: Lines 1–170.

https://github.com/SajidAfridi/material_ledger/blob/b86ff4362cde5c214aaff2906c05b0adac258074/docs/yorks-v1/SOURCE_OF_TRUTH.md

### R05 · yorks_v1_project_creation_draft.dart

Local recovery fields, date-only persistence and creation input adapter. Inspected: Full document.

https://github.com/SajidAfridi/material_ledger/blob/b86ff4362cde5c214aaff2906c05b0adac258074/lib/shared/models/yorks_v1_project_creation_draft.dart

### R06 · yorks_v1_project_creation_draft_provider.dart

Current owner-UUID/device storage key; not cloud persistence. Inspected: Full document.

https://github.com/SajidAfridi/material_ledger/blob/b86ff4362cde5c214aaff2906c05b0adac258074/lib/shared/providers/yorks_v1_project_creation_draft_provider.dart

### R07 · yorks_v1_project_creation_draft_controller.dart

State-before-storage acknowledgement, restore and discard behavior. Inspected: Full document.

https://github.com/SajidAfridi/material_ledger/blob/b86ff4362cde5c214aaff2906c05b0adac258074/lib/shared/controllers/yorks_v1_project_creation_draft_controller.dart

### R08 · yorks_v1_project_create_flow_screen.dart

Shared create/edit form, local versus memory edit state, navigation, sub-editors, activation and upload sequence. Inspected: Lines 1–350 and 455–1440.

https://github.com/SajidAfridi/material_ledger/blob/b86ff4362cde5c214aaff2906c05b0adac258074/lib/features/projects/presentation/screens/yorks_v1_project_create_flow_screen.dart

### R09 · yorks_v1_project.dart

Lifecycle, membership, field validation, building flags and scope serialization. Inspected: Lines 1–380 and 450–830.

https://github.com/SajidAfridi/material_ledger/blob/b86ff4362cde5c214aaff2906c05b0adac258074/lib/shared/models/yorks_v1_project.dart

### R10 · yorks_v1_project_controller.dart

Current command state and guarded controller operations. Inspected: Lines 1–260.

https://github.com/SajidAfridi/material_ledger/blob/b86ff4362cde5c214aaff2906c05b0adac258074/lib/shared/controllers/yorks_v1_project_controller.dart

### R11 · yorks_v1_project_repository.dart

Trusted create call, analytics timing and error mapping. Inspected: Lines 1–280.

https://github.com/SajidAfridi/material_ledger/blob/b86ff4362cde5c214aaff2906c05b0adac258074/lib/shared/repositories/yorks_v1_project_repository.dart

### R12 · 20260805101932_yorks_v1_project_edit_and_safe_archive.sql

Versioned project update, retained scopes, party snapshots and transactional audit. Inspected: Lines 1–290; base migration, not exhaustive final SQL.

https://github.com/SajidAfridi/material_ledger/blob/b86ff4362cde5c214aaff2906c05b0adac258074/supabase/migrations/20260805101932_yorks_v1_project_edit_and_safe_archive.sql

### R13 · POSTHOG_ANALYTICS.md

Schema v2, event meaning, privacy allowlist, disabled replay and measurement limits. Inspected: Lines 1–220.

https://github.com/SajidAfridi/material_ledger/blob/b86ff4362cde5c214aaff2906c05b0adac258074/docs/analytics/POSTHOG_ANALYTICS.md

### A01 · Yorks_Project_Accounts_SRS_v1.0(1).md / .pdf / .docx

Supplied Accounts review baseline, 19 September 2026; scope boundaries, physical-building ownership, controlled evidence, audit and uncertainty. Not the creation authority.

### U01 · Seven supplied current creation screenshots

Project details, Parties & access, team, Buildings/editor/list, Attachments, Review & create. Visual evidence only; test data is not a live business fixture.

### U02 · Five generated creation design images

Visual exploration: yorks_ac_project_setup_dashboard.png; modern_project_setup_wizard.png; create_project_buildings_setup.png; project_attachments_setup_dashboard.png; create_project_review_dashboard.png. Some required stars/roles/example dates/copy conflict with the model and are superseded by this specification.

### E01 · W3C · WCAG 2.2

Testable accessibility target: keyboard, focus, contrast, reflow and error assistance.

https://www.w3.org/TR/WCAG22/

### E02 · W3C APG · Tabs and manual activation

Focus/selection separation and component-scoped keyboard behavior.

https://www.w3.org/WAI/ARIA/apg/patterns/tabs/

### E03 · W3C APG · Combobox and datepicker examples

Picker semantics; examples need actual assistive-technology testing.

https://www.w3.org/WAI/ARIA/apg/patterns/combobox/

### E03b · W3C APG · Datepicker dialog

Keyboard date selection and focus-return reference.

https://www.w3.org/WAI/ARIA/apg/patterns/dialog-modal/examples/datepicker-dialog/

### E04 · Microsoft Fluent 2 · Field usage

Labels, help and validation as familiar office-form patterns.

https://fluent2.microsoft.design/components/web/react/core/field/usage/

### E05 · Flutter · Keyboard focus system

Long-lived focus nodes, traversal groups and focus management.

https://docs.flutter.dev/ui/interactivity/focus

### E06 · Flutter · Adaptive input

Pointer, keyboard and touch support as an adaptive input concern.

https://docs.flutter.dev/ui/adaptive-responsive/input

### E07 · Procore · Create a new project

Construction-project setup context; not permission to copy another product’s required fields.

https://support.procore.com/products/online/user-guide/company-level/portfolio/tutorials/create-a-new-project

### E08 · Adobe Spectrum · Text field

Visual component reference; not a separate construction-accounting authority.

https://spectrum.adobe.com/page/text-field/

## Appendix B. Definitions and documentation verification

| Term | Meaning |
| --- | --- |
| Draft input | Private uncommitted local form state. Not a server project or cloud save. |
| Server Draft project | A successfully committed project whose lifecycle remains draft. |
| Edit proposal | Local changes against a known project/version, unapplied until explicit Save changes. |
| Idempotency | Same reviewed intent can be retried without duplicating its business effect. |
| Expected version | The version against which a proposed mutation was prepared; stale versions conflict. |
| Fencing epoch | A monotonically changing ownership generation that prevents a former writer overwriting a new owner. |
| Uncertain outcome | A request was sent and may have committed, but its result is not yet known. |
| Partial success | One or more phases are confirmed; another phase, such as activation or a file, still needs attention. |
| Audit | Protected record of committed business changes and their attribution. Not analytics. |
| PostHog | Privacy-limited product telemetry; not the operational/audit authority. |
| Import | Interpreting source data into proposed or committed records. Uploading a file alone is not an import. |
| FRP | Retained Yorks room flag terminology; a boolean per building, not a capacity or inferred floor count. |

This package’s validation checks requirement IDs, requirement-to-test links, source identifiers, event naming, file integrity, and document rendering. It does not execute application tests, measure service performance, inspect live PostHog data, change production or certify accessibility. All application acceptance scenarios remain Not run until the implementation team supplies evidence.
