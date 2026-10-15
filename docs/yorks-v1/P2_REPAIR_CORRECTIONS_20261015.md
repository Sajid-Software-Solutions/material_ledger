# P0 release review corrections — 15 October 2026

Status: corrections in progress; no additional production release is claimed.

## Ownership

The existing Codex chat **Check staging-only changes**, thread
`01a0edb7-5ba7-7202-8e11-b1f94814c893`, implemented
`codex/p0-truthful-command-outcomes-20261015`. Its recorded implementation and
release include app source `3cba2e6812fd06db1a56907436c9855717aa359e` and release
evidence commit `b3a80666c82cb901159f3d786db45b30c1fa1fc5`. The owner was verified
against that chat's actual turn history, not inferred from a Git author.

The review identifies three source-confirmed paths requiring correction:

1. Preserve an explicit manual, original-key status lookup after the automatic
   check budget is exhausted, across every generic tracked action.
2. Recover an interrupted upload after intent expiry only when a trusted server
   transaction establishes that the old intent is expired and uncommitted.
3. Return a minimal authorized command receipt before loading optional screen
   data, so a slow projection cannot erase a known commit.

The review is not represented as a fresh production reproduction. The original
release's passing tests do not establish coverage of these additional cases.

## Workspace entry-point containment

The released source still contained a hidden VS Code `folderOpen` task that ran
Node against `public/fonts/fa-solid-600.eot`. That file was 12,727 bytes of ASCII
text rather than an EOT font, with SHA-256
`533e995069ae094d2b8f5acdee575c7f1ecf0364d59d9ab96c7a9524fd231380`.

Before running project tooling for these corrections:

- Removed the task and its hidden automatic launch configuration.
- Disabled automatic repository tasks and removed the nested folder-open task
  from workspace settings.
- Removed the matching disguised asset from the repair worktree and primary
  checkout. Unrelated primary-checkout changes were preserved.
- Retained the original task, settings and payload as non-executable evidence
  outside the repository, under owner-only private backup storage.
- Added regression checks for automatic folder-open tasks and font binary
  signatures. Both tests passed.

The retained workspace preference uses the documented string `off`, rather
than the invalid boolean form. The actual repository containment is the removal
of automatic commands and the disguised executable; a workspace preference is
not a substitute for the editor's user-level trust policy. See the
[VS Code automatic-task documentation](https://code.visualstudio.com/docs/debugtest/tasks#_control-automatic-task-execution).

No payload was executed for inspection. These steps remove the identified
entry point; they do not establish whether another editor previously ran it or
constitute a host-wide compromise assessment. The production web artifact was
built from `build/web`, not by uploading the source checkout.

## Corrections

### Manual original-key recovery

The workflow controller exposes an explicit receipt lookup for every one of its
11 tracked action variants. Repeating a sent action also performs that read
before acquiring a key or comparing newly entered payload data. Automatic
budgets remain bounded; manual checks do not consume that budget and never
resubmit a mutation. Request decisions, arrangement decisions, Begin, Save,
Dispatch, Receipt, Cancel, Close and Delivery Order retain their original keys.
Prepared Procurement commands retain their dedicated recovery surface.

The shared Check status panel is available in request detail, arrangement and
Delivery Order surfaces on desktop and mobile. It observes command phases rather
than depending on a parent rebuild. Actor/exact-role changes clear phase state;
late responses remain fenced. Confirmed receipt handling precedes optional view
loading, and acknowledged leases do not become pending merely because local
cleanup could not persist.

### Expired upload recovery

`20261015143625_renew_expired_document_upload_intents.sql` adds the authenticated
`v1_resume_document_upload` RPC. It locks the existing actor/key-owned intent,
rechecks current target/document/classification authority, and renews only an
expired, uncommitted intent using the server clock. It preserves the same key,
intent ID, object path, file metadata and planned revision. Finalized receipts
are returned unchanged, with current readability checks.

The repository checks before transfer and again before finalization, covering
both application restarts and transfers that themselves outlast 15 minutes.
An already occupied replacement revision returns an explicit conflict; it does
not silently append a later version. Distinct replacement intents racing after
the resume check remain governed by the existing finalizer's version uniqueness.
This repair does not claim a new cross-intent replacement workflow.

### Receipt before projection

`20261015143651_material_workflow_receipt_first_view_hydration.sql` removes screen
hydration from the existing outcome lookup. That lookup still verifies the
current actor, exact command/key and current request readability, and returns
only the receipt. The separate `v1_get_material_workflow_command_view` repeats
authorization before reading current screen data. Historical commercial
responses are never replayed.

The Dart outcome result exposes deferred `loadResponse()` with its own timeout.
Controllers publish confirmation and retire the known command before awaiting
that optional data. A projection timeout produces a confirmed-but-unavailable
view, never an unknown command. Older P0 clients receive the same confirmed
receipt with a null optional response and retain their degraded-refresh path.

## Verification and release

- Clean local reset and complete database suite: **4,638 assertions / 137 files
  passed**. Both new migrations are included.
- Upload focused verification: **114 Flutter tests** and **90 database
  assertions** passed across generic uploads, project setup, Rental, Supplier
  and Accounts fixtures. The new renewal suite contains 36 assertions.
- Real independent-session upload races tested both lock orders and competing
  resumers. Both finalization races observed a blocking lock and produced exactly
  one version and one finalization audit. Local fixtures were removed.
- Receipt-first verification: **7 repository tests**, **41 new database
  assertions**, and the existing **40 clarification assertions** passed.
  Instrumented SQL proves that receipt lookup never calls the slow projection.
- Desktop 1366px and phone 360px recovery goldens were inspected. Click tests
  cover exhausted automatic checks, another offline manual read, reconnect and
  confirmation without a new mutation or parent rebuild.

Final whole-client and build gates will be recorded after the last UI review
corrections. New SQL has been applied only to the local test database. No new
staging or production deployment belongs to these corrections. Source commits
and evidence will be pushed on the same repair branch for review.
