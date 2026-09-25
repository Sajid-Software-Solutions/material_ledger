# Material Request Save edit release — 25 September 2026

An existing Project Material Request now offers **Save** to authorized editors.
For an approved request with an explicit, still-open edit grant, Save commits the
new version without sending it for another approval. Before Procurement starts,
the request remains `approved_for_arrangement`. During its first unsaved working
arrangement, Save retains `arranging` and synchronizes that arrangement's line
placeholders in the same transaction. Procurement must refresh an already open
arrangement editor after a concurrent request edit.
New requests still require initial submission and approval. An edit to a
request awaiting its first approval remains in that queue. A legacy amendment
already pending reapproval is not silently promoted.

The trusted edit command checks the exact actor, membership/capability, grant,
state, arrangement cutoff and expected version under a request row lock. One
idempotency key returns one saved result. The initial Engineering decision is
retained with its original version; a post-approval edit creates a separate,
immutable revision snapshot and audit event with the editing actor and role.
Stable line IDs and protected commercial relations remain attached. An
incomplete or disconnected existing edit cannot report a local-only success.
The window closes when the arrangement is saved or holds a populated decision,
reservation or downstream activity; a historical arrangement version also
closes it.

The desktop, tablet and phone composers show Save alone for an existing
submitted request, with an editing title and a server-confirmed return to the
detail page. A new request keeps Submit for Approval. Request History labels
the saved edit; the approved status continues to describe the prior decision.

Migration `20260925031723_material_request_save_edits_without_reapproval.sql`
and the later `20260925120351_material_request_working_arrangement_edits.sql`
are forward-only and do not update existing requests or decisions. The latter
extends the grant through the first unsaved working arrangement, preserving
existing arrangement-line IDs and adding/removing only unsaved placeholders in
the same transaction as the request Save. Rollback is to revoke edit grants
through the audited command and deploy a corrective function migration; retain
already committed snapshots and audit history.
Production database, deployment and data require separate explicit approval.

## Verification

Record local database, Flutter, build, staging migration and preview evidence
in the automation evidence package before a release decision. A staging preview
is not proof of production behavior. Test Project Engineer, Site Engineer,
Procurement, Admin, an ungranted user, revoked grants, version conflicts,
idempotent retries, simultaneous writers where available, and the transition
into arrangement. Confirm desktop and 360 px phone actions visually.
