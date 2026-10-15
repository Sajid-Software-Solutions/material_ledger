# Yorks V1 R35 — State, RPC and RLS Matrix

This document is the implementation checklist for Postgres state machines,
trusted commands and access policies. Names are canonical unless a migration
records an explicit replacement.

## 1. State machines

### Project

| From | Command | To | Authority |
|---|---|---|---|
| — | Create project | `draft` | Project Engineer, Site Engineer, Admin |
| `draft` | Activate | `active` | Project Engineer/Admin; at least one active Project Engineer |
| `active` | Put on hold | `on_hold` | Project Engineer/Admin with reason |
| `on_hold` | Resume | `active` | Project Engineer/Admin with reason |
| `active`, `on_hold` | Complete | `completed` | Project Engineer/Admin; no unresolved new-work blocker |
| `completed` | Archive | `archived` | Admin with reason |
| `draft`, `active`, `on_hold`, `completed` | Safe archive | `archived` | Admin-only audited override; only when no operational Material Request remains open |

### Material Request

| From | Command | To | Authority |
|---|---|---|---|
| — | Save draft | `draft` | Assigned Project/Site Engineer |
| `draft` | Submit/resubmit | `awaiting_request_approval` | Draft creator with active project membership |
| `awaiting_request_approval` | Edit Engineering intent | `awaiting_request_approval` | Creator or assigned/global Project Engineer/Admin; versioned and audited |
| `awaiting_request_approval` | Return for changes | `draft` | Assigned/global Project Engineer/Admin; immutable returned decision/reason |
| `awaiting_request_approval` | Approve request | `approved_for_arrangement` | Assigned/global Project Engineer/Admin |
| `approved_for_arrangement` | Begin arrangement | `arranging` | Procurement/Admin |
| `arranging` | Save pre-approved arrangement | `approved`, or remain `arranging` when every line is unavailable | Procurement/Admin |
| Legacy `awaiting_approval` | Return/approve saved legacy arrangement | `arranging` or `approved` | Assigned/global Project Engineer/Admin; compatibility only |
| `approved`, `partially_dispatched`, `partially_received` | Dispatch subset | `partially_dispatched` or `dispatched` | Procurement/Admin |
| `partially_dispatched`, `dispatched`, `partially_received` | Confirm receipt review | `partially_received` or `received` | Assigned Project/Site Engineer/Admin |
| `received` | Close | `closed` | Assigned Project/Site Engineer, global Senior Mechanical Engineer/Project Manager, or Admin when all committed work is resolved |
| Eligible pre-dispatch state | Cancel | `cancelled` | Policy-defined Project Engineer/Admin with reason |
| Cancelled with latest saved all-unavailable arrangement | Create linked replacement Draft | source remains `cancelled`; new request is `draft` | Authorized Engineering MR creator/Admin; never Procurement |

State labels are not manually editable. Aggregate state is calculated by the
trusted command from line facts inside the same transaction.

### Arrangement line

| Decision | Constraint |
|---|---|
| `full` | `arranged_qty = requested_qty` |
| `partial` | `0 < arranged_qty < requested_qty` and reason present |
| `unavailable` | `arranged_qty = 0` and reason present |

### Dispatch and receipt

Dispatch: `created -> dispatched -> receipt_pending -> partially_received -> received`

Receipt review line UI outcome is `received`, `missing` or `damaged`. Good and
exception quantities reconcile to the dispatched quantity as defined in
`PRODUCT_DECISIONS.md`.

### Return

`draft -> awaiting_approval -> approved -> dispatched -> confirmed`

`awaiting_approval -> returned_for_changes -> awaiting_approval`

`awaiting_approval -> rejected`; pre-dispatch active states may be `cancelled`.

Only `confirmed` appends an inventory movement.

### R39 Accounts rollout boundary

The 25 August 2026 Accounts approval does not grant T01 transaction authority.
`YORKS_V1_ACCOUNTS` defaults off; the exact Accountant role and all 15 Accounts
capabilities are added to protected constraints/catalogue in shadow while no
Accounts route or mutation command is reachable. The exact catalogue is in
[`R39_ACCOUNTS_FOUNDATION.md`](R39_ACCOUNTS_FOUNDATION.md).

T01 protects only the default-stage template and its 100% invariant; it freezes
but does not yet instantiate the physical-building allocation policy. T02 adds
the commercial baseline, project physical-building allocation relations,
100%/Common-exclusion constraints and Billing Progress states/commands. T03
adds client claim, invoice, certification, PDC and payment states/commands, and
T04 adds supplier bill/match/payment states/commands. T05–T07 add reachable UI
and shared evidence/release cutover only after the corresponding server tests
pass. Every
later state transition must be added to this matrix with its caller, locks,
expected version, idempotency, atomic effects and rollback before enforcement.
The legacy `/admin/finance` route has no row here because it is not an Accounts
authority (FR-002 and FR-014).

T02 promotes only `view_project_accounts`,
`view_project_commercial_values`, `suggest_billing_progress`,
`confirm_billing_progress`, `configure_project_commercials` and
`review_commercial_progress` for their protected server consumers. The app
flag stays off. T03 claim/invoice capabilities, T06 export capability and all
normalized T05 routes remain shadow/unreachable.

### R39 T02 commercial baseline

`not_initialized -> active revision 1 -> active revision N`

Initialization creates revision 1 once. A later valid revision atomically
becomes active and makes the prior revision historical; no current or
historical baseline is updated in place. Invalid allocation, stage, terms, VAT
or scope input leaves no revision or audit side effect. Revision requires the
current baseline version, a reason, idempotency key and request hash.

An active revision contains an explicit currency, positive fixed-numeric
contract value, payment terms, reminder lead, explicit validated VAT snapshot,
effective date, physical-building allocations and stage allocations. Accounts
has no approved VAT default and never borrows the Rentals 5% rate. Management
review is disabled/null until an authorized baseline explicitly configures a
rule; no implicit threshold, quorum or expiry is allowed.

### R39 T02 Billing Progress

For each active `(project, baseline_revision, physical_building, stage)` there
is exactly one current row and any number of append-only revisions.

| Fact/action | State rule | Authority |
|---|---|---|
| Suggest | 0–100; summary or authorized project evidence required; confirmed/eligible unchanged | Active scoped actor with `suggest_billing_progress` |
| Confirm | 0–100; independent of suggestion; an increase needs an authorized evidence reference | Active scoped actor with `confirm_billing_progress` |
| Review | `not_required`, `pending` or `satisfied` is derived from the explicit baseline policy and review records | Active scoped actor with `review_commercial_progress` |
| Correct | New revision only; expected version, mandatory reason/evidence and applicable capability | Same command authority plus Admin-only exceptional policy; no exception route exists in T02 |

Suggestion, confirmation and review lock the current row, validate the active
baseline and expected version, append one revision/audit event, then update the
current projection atomically. Monetary visibility remains a separate
`view_project_commercial_values` decision; `confirm_billing_progress` does not
implicitly grant it.

### R39 T04 supplier-bill and payment states

`draft -> approved`, with `cancelled` terminal. Payment is a derived state:
`pending`, `approved`, `partially_paid`, `paid`, `blocked` or `cancelled`.

| Fact/action | State rule | Authority |
|---|---|---|
| Maintain bill evidence | Draft only; expected version; no accepted quantity supplied by the caller | Active scoped Procurement/Admin with `manage_supplier_bills` |
| Match | `matched` for PO/LPO + accepted receipt + supplier invoice; `review` for exactly two; `blocked` for fewer than two or explicit mismatch | Server-derived only |
| Approve | Current supplier-invoice document required; normally `matched`; unmatched exception needs a fresh Admin reason | Accountant/Admin with `approve_supplier_bill_payment`; Admin-only exception |
| Pay | Approved, current evidence, positive fixed-numeric amount and net paid not above total incl. VAT; unmatched payment needs a new Admin reason | Accountant/Admin with `approve_supplier_bill_payment`; Admin-only exception |
| Reverse payment | One exact linked original, never a mutation or second reversal | Same payment authority with expected bill version |
| Cancel | No nonzero net payment; approved cancellation requires payment authority and reason | Draft maintainer, or Accountant/Admin for approved bill |

The operational Receipt Review remains authoritative and unchanged. T04 reads
its confirmed good quantity and delivery reference through a narrow trusted
helper; it does not modify MR, Dispatch, Receipt, Inventory or Return state.

## 2. Quantity invariants

| Invariant | Enforcement point |
|---|---|
| `requested_qty >= 0` and committed quantities are positive where required | checks plus submit/command validation |
| `arranged_qty <= requested_qty` | arrangement line check and save RPC |
| `approved_qty <= arranged_qty` | pre-approved arrangement save RPC |
| `good_received_qty + in_transit_qty <= approved_qty` | dispatch and receipt RPCs under locks |
| Warehouse reserved total cannot exceed available stock | arrangement save RPC under inventory locks |
| Warehouse dispatch cannot exceed on-hand/available at commit | dispatch RPC under inventory locks |
| `good + missing_or_damaged = dispatched` for each reviewed line | receipt RPC |
| Missing/damaged does not increment good received | receipt RPC and movement trigger/constraint |
| Confirmed returns do not exceed good received minus earlier confirmed returns | return submit/confirm RPC under source-line locks |
| One committed effect per idempotency key/request hash | idempotency table unique constraint and RPC helper |
| R39 active physical-building allocations total 100.0000 within 0.00005 and exclude Common | baseline initialize/revise RPC plus deferred constraint trigger |
| R39 active stage allocations total 100.0000 within 0.00005 | baseline initialize/revise RPC plus deferred constraint trigger |
| R39 contract value is finite fixed numeric and `> 0`; VAT is an explicit validated snapshot | baseline initialize/revise RPC and checks |
| R39 `0 <= reminder_days <= payment_terms_days` | baseline initialize/revise RPC and checks |
| One current R39 progress row per project/revision/physical building/stage | unique constraint plus progress RPCs |
| R39 suggested/confirmed progress is between 0 and 100; suggestion never mutates confirmation | checks plus suggest/confirm RPC separation |
| R39 Stage Value and Confirmed Eligible are server-derived decimal values | role-safe baseline/progress projections only |

All authoritative quantities are Postgres `numeric`. Flutter may format decimal
input but does not decide the final comparison result.

## 3. Trusted RPC command matrix

Proposed stable function names use a `v1_` prefix during coexistence with legacy
tables/functions.

T01 introduces no normalized Accounts mutation RPC. Any additive T01
projection is diagnostic/shadow-only, returns no Accounts record values and
cannot be treated by Flutter as a command grant. T02–T07 must add their exact
RPC/projection rows here before consumer cutover.

| RPC | Caller | Locks/version | Idempotent | Atomic effects |
|---|---|---|---|---|
| `v1_initialize_project_commercial_baseline` | Active scoped `configure_project_commercials` actor | project/profile, physical scope set, protected default stage template; one baseline per project | yes | validate explicit VAT/terms/positive contract/100% sets/Common exclusion, create profile + immutable revision 1 + allocations + progress current rows, append audit |
| `v1_revise_project_commercial_baseline` | Active scoped `configure_project_commercials` actor | project/profile/current baseline + allocation/progress rows in deterministic order; expected baseline version | yes | validate complete replacement snapshot and reason, create immutable numbered revision, atomically switch current baseline, preserve earlier facts/audit; T03 later marks open claim drafts stale |
| `v1_suggest_billing_progress` | Active scoped `suggest_billing_progress` actor within authorized project/building | active baseline/current progress row; expected progress version | yes | validate 0–100 and evidence summary/reference, append suggestion revision/audit, update suggestion only |
| `v1_confirm_billing_progress` | Active scoped `confirm_billing_progress` actor | active baseline/current progress row and authorized evidence references; expected progress version | yes | validate 0–100 and increase evidence, append confirmation revision/audit, update confirmed percent/review blocker and server eligible facts; no value visibility grant |
| `v1_review_commercial_progress` | Active scoped `review_commercial_progress` actor when explicit policy requires review | active baseline/current progress/review fact; expected progress version | yes | append satisfied review/revision/audit and clear only the matching review blocker |
| `v1_get_project_commercial_baseline` | Active scoped `view_project_accounts`; value fields require `view_project_commercial_values` | project/current baseline | no | role-safe active revision/status/allocations; protected monetary keys omitted rather than zeroed |
| `v1_list_billing_progress` | Active scoped `view_project_accounts`; value fields require `view_project_commercial_values` | active baseline plus stable filter/cursor arguments | no | current Building × Stage rows, invariant totals, blockers and record command flags; filters never change aggregate calculations or hide blockers |
| `v1_list_billing_progress_revisions` | Active scoped `view_project_accounts`; value fields require `view_project_commercial_values` | authorized project/progress row plus stable cursor | no | append-only suggestion/confirmation/review history with only authorized evidence metadata |
| `v1_create_supplier_bill_draft`, `v1_update_supplier_bill_draft` | Active scoped Procurement/Admin with `manage_supplier_bills` | project/bill/version plus controlled-document and confirmed-receipt roots | yes | validate supplier/invoice/value/evidence identity, derive trusted delivery and match state, save draft and audit; no operational mutation |
| `v1_approve_supplier_bill` | Active scoped Accountant/Admin with `approve_supplier_bill_payment` | project/bill/version and current evidence | yes | require supplier-invoice document, enforce matched or fresh Admin exception, snapshot approval/audit |
| `v1_record_supplier_payment` | Active scoped Accountant/Admin with `approve_supplier_bill_payment` | project/bill/version and prior payment/reversal facts | yes | re-check evidence and approval, enforce positive amount/total cap/reference uniqueness, append payment/audit and derive state |
| `v1_reverse_supplier_payment` | Active scoped Accountant/Admin with `approve_supplier_bill_payment` | project/bill/version, exact original payment and reversal uniqueness | yes | append one exact negative linked reversal/audit; never edit original payment |
| `v1_cancel_supplier_bill` | Draft maintainer, or scoped payment approver for approved bill | project/bill/version and net payment total | yes | require reason, reject nonzero net payment, set terminal cancelled state and audit |
| `v1_get_supplier_bill`, `v1_list_supplier_bills` | Active scoped `view_project_accounts`; costs require `view_supplier_costs` | authorized project/bill plus stable filters/cursor | no | protected supplier state, match/payment status and command flags; monetary keys omitted without cost authority; no client-receivable keys |
| `v1_create_project` | Project Engineer, Site Engineer, Admin | reference/template rows | yes | project, Common/buildings, initial memberships, one Workshop Materials BOQ folder per real scope, audit |
| `v1_update_project` | Active assigned Project/Site Engineer or Admin | project/version, retained building scopes | yes | project setup, parties, active/retired building scopes; each new real scope receives one Workshop Materials folder, audit |
| `v1_archive_project` | Admin only | project/version, open MR check | yes | irreversible safe archive state, retained history, audit |
| `v1_set_project_state` | Project Engineer/Admin by transition | project/version | yes | state, owner/action, audit/notification |
| `v1_assign_project_member` | Project Engineer/Admin; creation exception for Site Engineer | project/member/version | yes | close prior membership, add membership, audit/notification |
| `v1_create_boq_group` | Active project actor with `boq.manage_folders` | project/selected real scope/name | yes | one empty custom folder in the selected scope only; no sibling scope or rows copied; projection and audit returned |
| `v1_rename_boq_group` | Active project actor with `boq.manage_folders` | group/scope/expected version/name/reason | yes | update only the selected scope folder's visible name; preserve group/template identity, worksheet title, rows and downstream references; audit old/new name |
| `v1_archive_boq_group` / `v1_restore_boq_group` | Active project actor with `boq.manage_folders` | eligible group/scope/expected version/reason | yes | soft archive or restore only the selected-scope custom, `workshop_materials` or retained `ac_units` folder; preserve worksheet/history and reject duplicate-name restoration; other template identities remain protected |
| `v1_list_boq_folder_management` | Active project actor with `boq.manage_folders` | project/selected real scope/include-archived | no | active/archived folder projections, stable template identity and server-derived action/blocker flags; no cross-scope mutation |
| `v1_assign_legacy_boq_group_scope` | BOQ-authorized Engineer/Admin | group/version | yes | explicit legacy group-to-real-scope reconciliation, audit; submitted/conflicting history rejected |
| `v1_submit_material_request` | Assigned Engineer draft creator | draft/project/counter/version | yes | number, snapshots, state, owner, audit/notification |
| `v1_save_submit_and_approve_material_request` | New-draft creator with exact non-Site-Engineer approval authority, published self-approval policy and effective approval capability | draft/project/current policy/version/idempotency | yes | canonical submitted and approved transitions, one immutable decision/audit/notification set, final approved projection; any failure rolls back the whole command |
| `v1_update_material_request_for_approval` | Creator or assigned/global Project Engineer/Admin | MR/version/line set; no arrangement permitted | yes | replace Engineering snapshot, retain number/submission attribution, audit/notification |
| `v1_decide_material_request` | Assigned/global Project Engineer/Admin | MR/current Engineering version | yes | immutable approval/return decision, state/owner, exact role, audit/notification |
| `v1_begin_arrangement` | Procurement/Admin | approved MR/version | yes | current arrangement work version, `arranging`, audit |
| `v1_update_material_request_procurement_item` | Procurement/Admin with effective arrange capability | MR/version/current unsaved working arrangement/request line | yes | effective description/model, immutable requested snapshot, clarifier metadata and audit |
| `v1_save_arrangement` | Procurement/Admin | MR, arrangement, inventory, reservations | yes | versioned lines, replacement reservations, approved snapshots/state, audit/notification |
| `v1_material_request_phase3_policy_projection` | Authorized request reader | current request access plus published configuration | no | role-safe published self-approval/readiness values and replacement eligibility/link only |
| `v1_create_replacement_material_request` | Authorized Engineering MR creator/Admin | cancelled source/version, latest all-unavailable arrangement, no dispatch, one-source uniqueness | yes | one private linked Draft, cloned line provenance and audit; source remains cancelled |
| `v1_decide_arrangement` | Assigned/global Project Engineer/Admin | legacy MR/current arrangement/version | yes | compatibility-only approval or return decision; retained history |
| `v1_add_material_request_comment` | Authorized request participant | MR/text/mention IDs | yes | append-only comment, validated mentions, notifications and audit |
| `v1_list_material_request_summaries` | Active role within the existing request/project read boundary | server filter/sort/limit/offset | no | lightweight authorized rows plus aggregate metrics; no lines, comments, private drafts or commercial values |
| `v1_list_material_request_comments` | Authorized request participant | request and stable cursor | no | newest/older append-only comment page without duplicate rows |
| `v1_get_material_request_work_assignment` / `v1_list_material_request_assignment_candidates` | Authorized request participant | request and current access | no | coordination marker and eligible non-commercial participant choices only |
| `v1_assign_material_request_work` | Authorized request participant | request/assignment versions and reason on reassignment | yes | claim/reassign marker, audit and assignee notification; no request state/owner/quantity mutation |
| `v1_sync_material_request_private_draft` / `v1_get_material_request_private_draft` / `v1_list_my_material_request_private_drafts` / `v1_delete_material_request_private_draft` | Active draft creator only | owner/draft/version and idempotency on writes | writes only | owner-private recovery snapshot; no submission, visibility or workflow transition |
| `v1_material_request_change_summary` | Authorized request participant | immutable Engineering revision snapshots | no | non-commercial added/removed/quantity/detail/delivery-note difference counts |
| `v1_search_material_request_candidates` | Active project-authorized Engineering/Procurement/Admin actor | project/scope/query | no | non-commercial suggestions ranked selected-scope BOQ, project BOQ, inventory; exact source IDs only for valid same-scope correlation |
| `v1_search_material_request_inventory_items` | Authorized Engineering request participant on an older client | project/query | no | retained compatibility-only inventory suggestions; current clients use ranked candidate search |
| `v1_dispatch_materials` | Procurement/Admin | MR, approved lines, reservations, inventory | yes | dispatch/lines, reservation consumption, stock movements, state, audit/notification |
| `v1_confirm_receipt` | Assigned Project/Site Engineer/Admin | dispatch/MR/receipt version | yes | review/lines, exact good/missing/damaged totals, state, audit/notification; appends receipt-reviewed Delivery Report revision when a DO exists |
| `v1_generate_delivery_order` | Assigned Project/Site Engineer, global Senior Mechanical Engineer/Project Manager, Procurement/Admin after committed dispatch | dispatch/current DO revision; optional later review link | yes | immutable dispatch-quantity revision before review, or immutable receipt-reviewed good-quantity Delivery Report revision after review; document link, audit |
| `admin-users` Edge commands | Active actor with the exact action capability, bounded target hierarchy and exact Admin-only legacy recovery | live Auth/profile, stable app-user target, singular server-owned role/claims, self/target checks and HMAC-bound idempotency | yes for mutations | resumable Auth mutation plus exact actor/action audit; last-active-Admin and reconciliation invariants retained |
| `v1_get/set_user_commercial_capability` | Active exact Admin or Senior Mechanical Engineer | live exact actor, target Auth user; reason and idempotency for writes | writes only | safe capability envelope/override plus audit; no commercial record data returned |
| `v1_get_current_permission_snapshot` | Any active exact Yorks role | live exact actor and monotonically increasing permission revision | no | role-safe effective capability/scope projection for the authenticated actor; no target directory or commercial data |
| `v1_get_user_permission_workspace` | Active permission administrator | live exact actor, stable target identity and delegation ceiling | no | target role baseline, active explicit assignments, effective source/scope/runtime state and revision; no protected domain records |
| `v1_set_user_permission_assignment` | Active permission administrator within delegation ceiling | target/current revision, capability/effect/scope/project set/validity | yes | one current grant/deny assignment, normalized project scopes, incremented target revision, append-only change event and trusted audit |
| `v1_clear_user_permission_assignment` | Active permission administrator within delegation ceiling | target/current revision and assignment | yes | retire the current assignment, increment target revision and append history/audit; seeded role default remains unchanged |
| `v1_apply_user_permission_changes` | Active permission administrator within delegation ceiling | target/current revision and complete typed delta array | yes | validate all set/clear deltas, then atomically apply normalized assignments/scopes, increment target revision once and append one event per delta plus trusted transaction audit; any invalid delta leaves no effect |
| `v1_list_user_permission_history` | Active permission administrator | target plus stable time/ID cursor | no | paged append-only access history without domain data |
| `v1_create_project_material_return` / `v1_save_project_material_return` | Assigned Project/Site Engineer, organization-wide Engineering role or Admin | project/scope/draft version | yes | project-wide draft and replaceable delivered/custom lines; no stock effect |
| `v1_submit_project_material_return` | Draft creator or authorized Engineering/Admin | return/version, project counter, source receipt lines | yes | controlled number, frozen snapshots, eligibility recheck, awaiting approval, audit/notification |
| `v1_decide_project_material_return` | Assigned/global Project Engineer or Admin | return/version and decision | yes | approved, returned-for-changes or rejected state plus immutable reason/actor evidence |
| `v1_dispatch_project_material_return` | Approved-return creator or authorized Engineering/Admin | return/version, driver and delivery-note evidence | yes | dispatched state and physical handover snapshot; no stock effect |
| `v1_confirm_project_material_return` | Procurement/Admin | return/version, every return line, source lines and inventory | yes | reconciled good/damaged/not-received facts, confirmed state, one stock movement per good line, audit/notification |
| `v1_cancel_project_material_return` | Draft creator, assigned/global Engineering or Admin before dispatch | return/version/reason | yes | terminal cancellation with retained lines and audit; no stock effect |
| Legacy `v1_submit_material_return` / `v1_confirm_material_return` / `v1_reject_material_return` | Existing request-scoped clients only | historical request/source contracts | yes | compatibility path retained during rollout; new UI uses project-wide commands |
| `v1_cancel_material_request` | Project Engineer/global Engineering/Admin per policy | MR/version/reservations/current arrangement | yes | terminal cancel, retain unavailable/history, release remainder, lock Procurement editing, audit/notification |
| `v1_close_material_request` | Assigned Project/Site Engineer, global Senior Mechanical Engineer/Project Manager, or Admin | MR and all logistics rows | yes | validated closed state, audit |
| `v1_adjust_inventory` | Procurement/Admin capability | inventory item/version | yes | append-only adjustment movement and derived balance, audit |
| `v1_inventory_category_suggestions` | Procurement/Admin inventory capability | active category/alias library | no | ranked read-only canonical, alias and advisory fuzzy results |
| `v1_create_inventory_category` | Procurement/Admin inventory capability | optional active parent family, canonical name | yes | stable category ID/path plus audit; no quantity effect |
| `v1_create_inventory_item` | Procurement/Admin inventory capability | optional category decision during catalogue reconciliation, metadata, optional opening quantity | yes | categorized or truthfully uncategorized item master, balance, optional opening movement, approved alias when applicable and audit atomically |
| `v1_adjust_inventory_stock` | Procurement/Admin inventory capability | active item/balance version, action, quantity | yes | locked append-only movement, derived balance and audit; reservations remain read-only |
| `v1_import_inventory` | Procurement/Admin inventory capability | reviewed workbook/category decisions/item versions | yes | atomic items/categories/aliases/movements/import result and audit |
| `v1_supplier_directory_projection` / `v1_supplier_folder_projection` | Procurement/Admin inventory capability | exact current role plus paging/filter arguments | no | authorized supplier, receipt, document, destination and audit projections; mixed units stay separated |
| `v1_create_supplier` | Procurement/Admin inventory capability | canonical identity, explicit aliases and idempotency key | yes | one canonical supplier master plus append-only audit; Unknown Supplier is immutable |
| `v1_import_inventory_r38_9` | Procurement/Admin inventory capability | file SHA-256, strict mode, reviewed item/category/supplier decisions, receipt evidence, condition quantities and opening cutoff | yes | one atomic import result, suppliers/aliases, receipt batches/lines, movements, balances and audit; failed rows create nothing |
| `v1_prepare_supplier_document_upload` / `v1_supplier_document_workspace_projection` | Procurement/Admin inventory capability plus document classification | supplier or receipt-batch target and actor-scoped upload intent | yes / no | private verified document version/link and authorized folder projection |
| `v1_create_document_version` | Entity-authorized user | document/link target/version | yes | Storage metadata/version/link/audit after upload finalization |
| `v1_link_document` | Entity-authorized user | document/target/version | yes | classified link and audit |
| `v1_get_configuration_centre` / `v1_get_configuration_validation` | Active exact Admin | current published version plus inert shared draft | no | Admin-safe settings/master/history projection and authoritative validation |
| `v1_list_configuration_units` | Any active exact Yorks role | published active unit register | no | non-commercial unit codes for future MR and Warehouse entry |
| `v1_stage_configuration_setting` | Active exact Admin | draft revision, allowlisted setting and typed value | yes | one inert draft value and incremented draft revision |
| `v1_stage_configuration_master_action` | Active exact Admin | draft revision, normalized category/unit action and archive reason | yes | one inert create/archive action and incremented draft revision |
| `v1_discard_configuration_draft` / `v1_restore_configuration_defaults` | Active exact Admin | draft revision | yes | remove unpublished work or stage typed defaults; published values/history unchanged |
| `v1_publish_configuration` | Active exact Admin | draft revision, validation result and publication reason | yes | atomic setting/master commit, immutable publication snapshot/change rows and trusted audit event |
| `v1_list_chat_conversations` / `v1_search_chat` | Active exact role, active conversation member | current membership and server-side search scope | no | authorized conversation summaries, unread preferences and non-commercial previews only |
| `v1_get_chat_conversation` | Active conversation member with current contextual access | conversation, current project/MR access, cursor and page size | no | participant projection plus newest/older immutable message page |
| `v1_create_chat_conversation` | Any active role for direct/project/MR; Admin, Project Manager or Senior Mechanical Engineer for groups; Admin for announcements | canonical direct/context key and idempotency key | yes | conversation, controlled member set, creator ownership where applicable and system event |
| `v1_update_chat_group` | Group owner or active Admin participant | group row and active member set | yes | title/description/member reconciliation plus system event; direct/context chats rejected |
| `v1_prepare_chat_attachment` / `v1_verify_chat_attachment_upload` | Active member / service role only | actor-scoped short-lived intent, private object metadata, byte count and SHA-256 | yes | upload intent followed by server-verified attachment readiness; no message binding yet |
| `v1_send_chat_message` | Active member; announcements are Admin-send-only | conversation, reply/link/mention/verified attachment ownership and idempotency hash | yes | one append-only message, attachment binding, mentions, hidden participant push-transport rows and audit-safe context; no workflow-bell entry |
| `v1_mark_chat_read` / `v1_mark_chat_unread` | Active member | member preference row | no | authoritative cross-device Chat cursor plus exact hidden Chat transport acknowledgement; workflow notification seen state is untouched |
| `v1_set_chat_preference` | Active member | member preference row | no | pin/mute/archive preference; new unmuted activity can restore archived conversation |
| `v1_toggle_chat_acknowledgement` / `v1_toggle_chat_message_pin` | Active member | message and conversation access | no | caller acknowledgement or per-conversation pinned-message fact |
| `v1_download_chat_attachment` | Active member with current contextual access | attachment/message/conversation access | no | private bucket/path metadata for one authorized download |

Every function derives actor, role and server time. User-supplied actor/role/time
is ignored as authority. The exact role in the JWT must match the current
protected Auth row before it is normalized for workflow use; stale role claims
fail closed.

## 4. RLS capability matrix

Legend: `R` read, `C` create, `U` update, `RPC` mutation only through trusted
command, `—` denied. “Assigned” always means an active relevant project
membership.

The exact ninth `accountant` role is not an “Assigned” technical member. During
T01 it receives only its own protected identity/effective-capability snapshot;
Accounts capabilities are shadow and the feature is unreachable. It is denied
Project/BOQ/MR/Dispatch/Receipt/Inventory/Return/membership mutation through
UI, direct tables and ordinary RPCs. Later Accounts reads/commands use explicit
project/organization capability scope and record-specific command flags, never
technical membership or role-name inference (FR-016–FR-025).

### R39 T02 response and command boundary

| T02 surface | Site Engineer | Project Engineer | Accountant | Procurement | Admin / management reviewer |
|---|---|---|---|---|---|
| Baseline/progress non-monetary projection | Authorized project scope with `view_project_accounts`; percentages/evidence/owner only | Authorized project scope with `view_project_accounts` | Capability-scoped project only | Denied by default | Capability-scoped project |
| Contract/allocation/eligible monetary fields | Omitted unless separately granted `view_project_commercial_values` | Omitted unless separately granted `view_project_commercial_values` | Allowed only where both project scope and value capability are effective | Denied by default | Allowed only where both project scope and value capability are effective |
| Suggest progress | RPC with `suggest_billing_progress` and active project/building scope | Only if explicitly granted same capability | Denied by default | Denied | Only if explicitly granted same capability |
| Confirm progress | Denied | RPC with `confirm_billing_progress`; value capability is not required to confirm | Denied by default | Denied | Only if explicitly granted same capability |
| Configure/revise baseline | Denied | Denied by default | Denied by default | Denied | RPC with `configure_project_commercials` |
| Management review | Denied | Denied unless explicitly granted | Denied unless explicitly granted | Denied | RPC with `review_commercial_progress` and configured review requirement |
| Direct relation insert/update/delete | Denied | Denied | Denied | Denied | Denied; trusted RPC only |

An unassigned actor is denied even if a guessed project/building UUID is
valid. Revocation/inactivation is re-checked against live protected identity on
every read and command. The non-monetary JSON shape contains no contract,
currency, VAT, allocation amount, Stage Value, eligible, cumulative or
available-to-claim key; AT-SEC-001/004/005/008 assert both database response
and captured network payload absence.

| Domain | Project Engineer | Site Engineer | Procurement | Admin |
|---|---|---|---|---|
| Own profile | R/U non-authority fields | R/U non-authority fields | R/U non-authority fields | R/U non-authority fields |
| Other profiles/team picker | R limited active directory | R limited active directory | R limited active directory | R; provision/disable via server |
| Capabilities | R own effective | R own effective | R own effective | R/RPC manage |
| Capability catalogue/templates/assignments/history | own effective snapshot only | own effective snapshot only | own effective snapshot only | protected workspace R/RPC only; no direct table mutation |
| Assigned projects/scopes | R/C/U assigned | R/C/U assigned | R running, no C/U | R/RPC controlled manage |
| Project memberships | R; RPC manage assigned project | R, no manage after create | R, no write | R/RPC |
| Assigned BOQ groups/columns/rows | R/C/U | R/C/U | R only | R/C/U |
| MR drafts | own R/C/U/delete | own R/C/U/delete | — | R/support per policy |
| MR private draft recovery | own R/RPC only | own R/RPC only | — | own R/RPC only; no invisible cross-user access |
| MR work assignment marker | R/RPC when request-authorized | R/RPC when request-authorized | R/RPC after request enters Procurement visibility | R/RPC; cannot bypass workflow commands |
| Submitted MR operational data | R assigned | R assigned | R all running | R |
| MR commercial projection | only with capability | only with capability | R with capability | R with capability |
| Arrangements | R assigned; decision RPC if Project Engineer | R assigned, no decision | R; create/update through RPC | R/RPC |
| Approval decisions | R assigned; RPC if Project Engineer | R assigned | R, no write | R/RPC |
| Inventory catalogue/balances | no general inventory workspace (Senior Mechanical Engineer exception: R only) | no general inventory workspace | R/RPC manage | R/RPC |
| Inventory categories/import batches | — | — | R; create/import via idempotent RPC | R; create/import via idempotent RPC |
| Supplier masters/aliases/receipt batches/provenance | — | — | R/RPC inside Warehouse Inventory only | R/RPC inside Warehouse Inventory only |
| Supplier documents | — | — | R/RPC subject to classification capability | R/RPC subject to classification capability |
| Reservations/movements | related non-commercial summary | related non-commercial summary | R; write only via RPC | R; write only via RPC |
| Dispatches | R assigned | R assigned | R/RPC create | R/RPC |
| Receipt reviews | R/RPC assigned | R/RPC assigned | R, no confirm | R/RPC |
| Delivery Orders | R/RPC generate after an assigned committed dispatch | R/RPC generate after an assigned committed dispatch | R/RPC generate after committed dispatch | R/RPC generate after committed dispatch |
| Returns | R/RPC create assigned | R/RPC create assigned | R/RPC confirm/reject | R/RPC |
| Operational documents | R/C through authorized links | R/C through authorized links | R/C through authorized links | R/C |
| Commercial documents | capability plus link | capability plus link | capability plus link | capability plus link |
| Notifications | own R/U seen state | own R/U seen state | own R/U seen state | own R/U seen state |
| Audit events | related read projection | related read projection | related read projection | R; no client C/U/delete |
| Idempotency/reference counters | — | — | — | no direct client access |
| Configuration settings/draft/publications | — | — | — | R/RPC through exact-Admin projection and commands; no direct table access |
| Direct Team Chat | R/RPC only as one of exactly two participants | R/RPC only as one of exactly two participants | R/RPC only as one of exactly two participants | R/RPC only when explicitly one of two participants; no invisible Admin access |
| Project/MR Team Chat | R/RPC while current project/MR access remains valid | R/RPC while current project/MR access remains valid | R/RPC for authorized running-project context | R/RPC through the same explicit/contextual membership boundary |
| Custom Team Chat groups | R/RPC as member; cannot create unless global role below | R/RPC as member; cannot create | R/RPC as member; cannot create | R/RPC create and manage when owner or active Admin participant |
| Team Chat announcements | R as member; no send | R as member; no send | R as member; no send | R/RPC create/send as active Admin |
| Team Chat attachments | R/RPC authorized private download; verified upload/send as active member | same | same | same; service-only finalization does not grant conversation access |

Senior Mechanical Engineer, Project Manager, Workshop In-Charge and Document
Controller follow the Project Engineer column across all projects without
dated membership. They remain denied Procurement, commercial and Admin-only
cells, except for the separately approved Senior Mechanical Engineer User
Management capability and non-commercial inventory read-only projection.

For Team Chat only, Senior Mechanical Engineer, Project Manager, Workshop
In-Charge and Document Controller may create custom groups. They do not thereby
gain access to Direct conversations, muted or archived conversations,
attachments, or announcements unless the relevant membership/policy
independently permits it. These roles cannot send announcements.

Direct Procurement inserts/updates/deletes on project, scope, membership and BOQ
tables must fail even when a route or stale client attempts them.

Inventory category, alias and import-batch relations also deny ordinary table
access. `v1_create_inventory_category`, `v1_create_inventory_item`,
`v1_adjust_inventory_stock`, the compatibility `v1_adjust_inventory`, and
`v1_import_inventory` are the smart-warehouse write boundaries;
`v1_inventory_category_suggestions` is read-only. The import command validates
the whole workbook and commits or rolls back as one transaction.

The All BOQ overview is read-only. It cannot be represented by a `scope_id`,
used as a mutation target or used as an MR source; BOQ-derived MR lines must
match the request's one persisted Common/building scope at save and submit.

## 5. Storage policy matrix

| Classification | Additional requirement |
|---|---|
| `operational` | Access to every current linked entity |
| `commercial` | Every-linked-entity access plus `view_commercials` |
| `admin_restricted` | Admin |
| Team Chat attachment | Current active conversation membership plus any current project/MR context access; object must be bound to an append-only message after server verification |

Upload recovery uses `v1_resume_document_upload` with the original actor-owned
intent ID and idempotency key. The RPC shares the finalizer's intent row lock,
rechecks the current exact role, active actor, target/classification and document
write authority, and extends only an expired, uncommitted intent. It preserves
the key, path, planned revision and metadata. A finalized intent returns its
existing readable receipt without renewal; an occupied replacement revision
returns a conflict without silently appending a new revision.

Generic workflow status reads use `v1_get_material_workflow_command_outcome` to
return the exact actor/key/command receipt after current entity readability
checks. Optional current screen data is read separately through
`v1_get_material_workflow_command_view`, which repeats those authorization
checks. Neither RPC replays historical commercial response data. Manual status
reads remain available after the automatic budget stops and cannot replay a
mutation or allocate a replacement key.

Upload uses a short-lived authorized path/operation. The final document row and
link are committed by a trusted function after object metadata/hash validation.
Object-path guessing never grants read.

## 6. Server-generated audit events

At minimum, append events for:

- project create/state/member changes;
- BOQ import commit and destructive column/row operations;
- MR submit/cancel/close;
- arrangement begin/save/replace and reservation release;
- approval/return-for-changes;
- inventory adjustment;
- dispatch and movement creation;
- receipt confirmation;
- DO generation/supersession;
- return submit/confirm/reject;
- document version/link change;
- Admin user/capability change and override.
- configuration publication with exact Admin, reason, affected areas and immutable version.
- after the applicable R39 phase cuts over: commercial baseline revision,
  progress suggestion/confirmation/review, claim/invoice/certification,
  PDC/payment, supplier-bill match/approval/payment and Accounts document
  changes with exact actor, role, capability, project, reason and server time.

Audit tables deny client insert, update and delete. Corrections append a new
event referencing the original.

## 7. Required negative proofs

Every relevant migration/test must prove at least:

1. unrelated Engineers cannot read or mutate another project;
2. Site Engineer cannot manage team or approve;
3. Procurement cannot create/edit project or BOQ, raise an Engineering MR, or
   approve its arrangement;
4. an Engineer without commercial capability receives no cost schema/value;
5. direct table writes cannot bypass each critical RPC;
6. stale versions fail without partial effects;
7. competing reservations/dispatches cannot oversubscribe;
8. repeated idempotency keys do not duplicate effects;
9. revoked membership blocks future actions but preserves historical reads and
   attribution;
10. Storage path knowledge does not bypass document/link access;
11. non-Admin exact roles cannot read, stage, restore, discard or publish
    organization configuration, and ordinary clients cannot mutate its tables.
12. non-members, revoked contextual members and an uninvited Admin cannot read
    a conversation, message, member list, search preview or attachment path;
13. unverified, expired, wrong-hash, wrong-size or wrong-content-type chat
    uploads cannot be bound to a message;
14. Procurement, Project Engineer and Site Engineer cannot create custom chat
    groups, while only Admin can create or send an announcement;
15. non-Procurement/non-Admin roles cannot open supplier/import RPCs, tables,
    private objects or exports, including Senior Mechanical Engineer's
    separately allowed non-commercial inventory catalogue read;
16. a missing supplier maps only to immutable Unknown Supplier, similar names
    never merge automatically, duplicate file/cutoff/idempotency identities do
    not duplicate stock, and any failed strict row leaves no partial supplier,
    receipt, movement, balance, document or audit result.
17. a permission administrator cannot mutate their own effective access, grant
    outside their delegation ceiling, remove/expire the last active permission
    administrator, submit an unsupported scope or create conflicting active
    assignments;
18. an expired/revoked/inactive-user assignment is ineffective, stale target
    revisions fail without partial change, and repeated idempotency keys do not
    duplicate assignment/history/audit rows;
19. ordinary authenticated clients cannot insert/update/delete capability,
    template, assignment, project-scope, revision, history or parity data;
20. the seeded shadow resolver reproduces the current role/membership and
    commercial-override decisions with zero unexplained allow/deny differences
    before any protected consumer is cut over.
21. an Accountant cannot mutate BOQ, Material Request or Dispatch by route,
    direct table API or ordinary RPC, and denial creates no partial operational
    or audit side effect (AT-SEC-003);
22. an inactive Accountant presenting a stale token receives no Accounts read
    or command result and any protected client projection is purged
    (AT-SEC-006); and
23. an unknown exact role receives no Accounts capability, route, projection
    or command privilege (AT-SEC-007).
24. a Site Engineer or any actor without
    `view_project_commercial_values` receives percent/evidence/owner facts but
    no monetary JSON field keys, including through direct RPC calls, filters,
    revision history or captured network response (AT-SEC-001/008);
25. an unassigned Project Engineer guessing project/building identifiers is
    denied every T02 projection/command with no existence oracle or partial
    revision/audit side effect (AT-SEC-004);
26. a revoked/inactive T02 actor is denied on the next refetch and command even
    with a stale token; protected client state must be purged by the future T05
    consumer (AT-SEC-005);
27. ordinary authenticated users cannot insert, update or delete a baseline,
    allocation, current progress, progress revision, review or T02 audit row;
28. same idempotency key plus same request hash returns the prior T02 result,
    while the same key plus a different hash conflicts without a second
    revision/audit row (AT-CONC-002/003); and
29. two T02 confirmations with the same expected version yield one success and
    one stale conflict with no lost update or partial effect (AT-PROG-005).

## Submission response reconciliation (17 September 2026)

`v1_get_material_request_submission_result(payload, idempotency_key,
approve_immediately)` is a read-only RPC for the original actor's exact
save-and-submit or save-submit-and-approve intent. It requires current active
identity, engineering project access and submit capability; combined approval
also rechecks decision authority and approve capability. Payload hash, request
identity, project and original creator must match. Another actor gets no result
for a caller-owned key; denied project access fails closed. Responses use the
current role-safe projection. Cached replay branches of both write wrappers now
use the same checks, preventing revoked membership from replaying old responses.

No matching committed key means **unconfirmed**, never proof of rollback.
The client persists the original key/payload/mode in its existing account-owned
recovery draft before sending; freezes editing while unresolved; offers one
bounded read per explicit status check; and permits only an explicit same-intent
retry after an authorized unconfirmed read. Existing transaction locks/hash
checks deduplicate a retry even if the first command commits later. A denied
retry leaves the first attempt unresolved. No server workflow state or stock
transition is added. Reconciliation does not resubmit or issue side effects.

## Company Material Request T02 approval (18 September 2026)

| State | Actor | Trusted command | Server checks | Result |
|---|---|---|---|---|
| `awaiting_company_approval` | snapshotted independent approver | `v1_decide_company_material_request` | active exact identity, non-Procurement role, current explicit category/unit approver authorization, not requester/beneficiary/receiver, expected version, decision/reason shape, idempotency key | one immutable decision and event; state becomes `approved_for_procurement`, `returned_for_changes` or `rejected`; requester notified |

`v1_list_company_material_request_approval_inbox()` returns only pending rows
assigned to the current actor after the same authorization predicate.
Authenticated clients have no table privileges on
`v1_company_material_request_decisions`. The safe projection includes
`can_decide` and immutable decision history; it adds no commercial, project,
BOQ or stock fields. A completed request cannot be decided again. An exact
retry returns the current authorized projection without duplicating evidence.

This is an approval-only candidate behind the existing default-off Company
Material Request flag. No company fulfilment state or stock command is
authorized by T02.
