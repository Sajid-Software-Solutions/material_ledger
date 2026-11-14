# People records

Owner decision: 13 November 2026 ([`PRODUCT_DECISIONS.md`](PRODUCT_DECISIONS.md)
section 42). Source sheet: the Staff Documents & Passes tracker kept by PR.

People is the staff and labour register with every person's identity
documents and site passes, kept for PR, the Accountant and Admin. It
replaces the tracker spreadsheet: the same columns can be imported and
exported, and the app adds history, expiry status and one place to renew a
document.

## Delivery

| Slice | Contents | State |
| --- | --- | --- |
| 1 | People home, Staff and Labour registers, person record, person form, document add/correct/renew/end, Excel import and export, tracker data load | This change |
| 2 | Company documents: trade licences and permits per entity, vehicles and vehicle passes, insurance policies, CICPA contracts | See [`COMPANY_DOCUMENTS.md`](COMPANY_DOCUMENTS.md) |
| 3 | Daily expiry summary to PR and Admin; status-only chips for engineers on their crew (see below) | Done |

Until slice 2, the import reports insurance lines and vehicle passes found
in the tracker and skips them; they are not people.

## Who sees what

| Role | People |
| --- | --- |
| Admin, PR, Accountant | View and manage (`people_records.view`, `people_records.manage` role defaults) |
| Any other role | Nothing, unless granted per person in Access & Roles |
| Engineers (slice 3) | Only an OK / expiring / expired status for their crew members; no numbers or dates of birth |

The two capabilities are new, enforced and in their own module. They do
not reuse the legacy `people.*` shadow keys, which Procurement holds. The
Accountant and PR capability boundaries each gain exactly these two keys.
Every function checks the capability on the server; the tables have no
grants, so identity numbers and dates of birth never leave the server
except through these functions to a holder.

## Model

A person **is** a Workforce worker (`v1_workforce_workers`, number
`WR-######`), so crews, attendance and timesheets use the same record.
Beside it:

- `v1_people_profiles`: Staff or Labour, Arabic name, date of birth,
  unified number, a source note, record version.
- `v1_people_documents`: kind (visa, passport, labour card, ILOE, Emirates
  ID, CICPA pass, CMW pass, other), number, issue and expiry dates, sites
  (passes), notes. Visa, passport, labour card, ILOE and Emirates ID are
  held once: a unique index allows one current document of each, and a
  second one is a renewal. Passes and other documents may be several.
  A document needs a number or an expiry; a pass may instead name only its
  sites (the tracker lists many CMW passes that way).
- `v1_people_revisions`: append-only before/after of every change with
  actor, role, reason and time. Ended documents and revisions cannot be
  updated or deleted (triggers).

Status of a document, from its expiry and today in Asia/Dubai: **expired**,
**expiring** (60 days or fewer), **valid**, or **no expiry**. A person's
attention is their worst current document.

## Commands

All are security-definer functions with an idempotency key and, for
writes to an existing row, the record version it was read at; a stale
version is refused (`40001`) and nothing is shown as saved until the
server confirms.

| Function | Use |
| --- | --- |
| `v1_people_overview()` | Counts, documents by kind, companies, the attention list |
| `v1_people_list(p_query)` | Register page: category, company, search, status, sort, paging |
| `v1_people_get(p_worker_id)` | One person, documents, previous documents, history |
| `v1_people_save_person` | Add a person (creates the worker) or edit details |
| `v1_people_save_document` | Add, correct, or renew (`renew: true` ends the current one as *renewed*) |
| `v1_people_end_document` | End a document with a required reason |
| `v1_people_preview_import` / `v1_people_import` | Classify, then apply, a tracker or export |

## Import and export

The reader finds the staff sheet and the gate pass sheet by their
headings, so the owner's tracker and the app's own export both import.

- Dates: Excel serial numbers, `YYYYMMDD` numbers (pass sheet), and
  `31/01/2027`, `31-Jan-2027`, `2027-01-31` text.
- Long numbers such as Emirates ID stay exact (no scientific notation).
- Staff or Labour comes from a Category column when present, otherwise
  from the profession (engineer, manager, officer, accountant and similar
  office words are Staff; the rest are Labour).
- Gate passes join the person by name, with the company section breaking
  ties. A pass whose name contains a digit is a vehicle (slice 2). A pass
  for a name not on the staff sheet adds that person as Labour, marked
  *Added from the gate pass list*, so PR can check it.
- A person matches an existing one by name and company. For each
  document: new, unchanged, renewed (a later expiry) or updated. An older
  expiry never replaces a newer one, a blank cell keeps what is stored, and
  an existing person's category is not changed by an import.
- The preview shows every row and what it will change. Import is refused
  while any row has a problem, and runs once per key under an advisory
  lock.

Export writes three sheets: **Staff Documents** (the tracker's columns,
plus number and category), **Gate Passes** (one pass per row) and **Needs
Attention**, with real dates, frozen headings, filters and red/amber/green
expiry cells.

## Screens

- `/yorks/people`: header (refresh, Import Excel, Export Excel, Add
  person), Needs attention / Staff / Labour, Workforce and Timesheets
  links, six metric tiles that filter, search, company and sort, the
  register as a table on desktop and cards on a phone.
- `/yorks/people/:workerId`: name, number, category and attention; the
  status banner; the documents table (edit, renew, end; Add on a missing
  kind); personal details with Take attendance for a crew member; previous
  documents; history.
- `/yorks/people/new` and `/yorks/people/:workerId/edit`: the Material
  Request composer layout on desktop, one column with a bottom Save bar on
  a phone.

Routes and the sidebar entry are behind `YORKS_V1_PEOPLE_RECORDS` (default
off) and `people_records.view`; new and edit also need
`people_records.manage`.

## Daily summary

`20261114150000_people_expiry_summary.sql` adds the daily job
`v1_people_send_expiry_summary()`, scheduled as `yorks-people-expiry-summary`
at 04:15 UTC (08:15 in Dubai).

- **What counts:** every current document of an active person or an active
  company record that has expired or expires within 60 days.
- **Who:** every active PR and Admin (`v1_people_expiry_recipients`).
- **When:** one notification per person per day, and only when the set of
  documents and their statuses differs from that person's last summary.
  `v1_people_expiry_digests` keeps each summary (counts and an md5
  fingerprint of the set) and cannot be deleted.
- **What it says:** `people_documents_overdue` (urgent) when anything has
  expired, otherwise `people_documents_due`. The label is the number of
  documents. It opens `/yorks/people`, or `/yorks/company-documents` when
  only company documents need attention; the push sender allows only these
  two links for it.
- **Copy:** `contracts/notifications/module_events.v1.json`, generated into
  the app and the push function by `tool/generate-notification-catalogue.py`.

Rollback: `select cron.unschedule('yorks-people-expiry-summary');` and, if
needed, restore the three notification functions from their
`*_before_people_expiry` versions. Keep every row.

## Engineer status

`20261114160000_crew_document_status.sql` adds
`v1_wf_crew_document_status(p_team_id)`. It requires `view` on the crew
(`v1_wf_crew_access`) and returns, by worker id, only `ok`, `expiring` or
`expired` for the crew's current members and anyone who worked on it in the
last 31 days. A worker with no dated document is left out. Nothing else from
People is returned; the function is the only door engineers have to it.

The app asks for it only when People is on, once per crew
(`yorksCrewDocumentStatusProvider`), and shows `CrewDocumentBadge` beside
the name on Take attendance (phone rows, the desktop grid, the row editor)
and the Crews page. pgTAP `yorks_crew_document_status.test.sql` covers the
statuses, that no kind, number or date leaks, that a worker off the crew is
excluded, that the engineer still cannot open People, and the role matrix.

## Attachments

Owner decision, 14 November 2026 (`PRODUCT_DECISIONS.md` section 47). Every
labourer and staff member has an **Attachments** section on their record:
copies of their passport, visa, Emirates ID, labour card, passes and any
other paper (PDF, Word, Excel, JPG or PNG, up to 20 MB each).

- **Who.** Everyone with `people_records.view` sees and opens them; holders
  of `people_records.manage` (PR, Admin and the Accountant by default) add
  and remove them. Engineers, Procurement and the Senior Mechanical Engineer
  have neither, whatever path they know.
- **Copy of.** A file may name which of the person's documents it copies
  (current or ended). Each document row shows a paperclip with how many
  copies it has and an Attach button that opens the dialog with that
  document chosen. The register shows a paperclip and count beside each
  person with files.
- **Storage.** Private bucket `yorks-people-files`, at
  `people/<worker id>/<attachment id>.<ext>`. Upload is allowed only for a
  real person and only with `people_records.manage`; reading only for a
  recorded, current attachment and only with `people_records.view`
  (`v1_person_file_readable` / `v1_person_file_writable`). A recorded file is
  never replaced. The attachment id comes from the idempotency key, so a
  retry never stores a second copy. Size and type are read from storage.
- **Opening.** A five-minute signed link, opened in a new tab or the
  device's viewer.
- **Removing** needs a reason: the attachment leaves the list and can no
  longer be opened; the file, the row and the history are kept. Rows are
  never deleted.
- **History.** Adding and removing appear in the person's history.
- **Commands.** `v1_people_list_attachments`, `v1_people_attachment_counts`,
  `v1_people_add_attachment`, `v1_people_remove_attachment` (all volatile,
  rechecking the capability). Migration
  `20261114180000_people_attachments.sql`; rollback: drop the two storage
  policies and revoke the four commands, keeping the bucket, table and files.

## Bulk upload

Owner decision, 14 November 2026 (`PRODUCT_DECISIONS.md` section 49). The
People header's **Upload many** (holders of `people_records.manage`) attaches
a folder of scans at once; Company documents has the same button.

- **Matching** (`lib/shared/services/yorks_v1_bulk_attach.dart`, pure Dart,
  tested): from the file name, a document number first (it also picks the
  document), then the worker or unified number, then the name: the person
  with most of their name's words wins, at least two (Muhammad spelt any
  way is one word); a tie is left to choose. Words such as passport, visa,
  Emirates ID, labour card, ILOE, CICPA or CMW pick the document when the
  person holds exactly one current document of that kind. Company records
  use the licence number, plate or LOA and words such as trade licence,
  establishment card, mulkiya, Asateel, insurance or LOA.
- **Check first.** Every file shows its person and document with how it
  was matched ("Matched by number", "Matched by name", "More than one match
  — choose", "Not matched — choose"); both can be changed. Files that are
  not PDF, Word, Excel, JPG or PNG up to 20 MB are listed and left out.
- **Upload** sends files one at a time through `v1_people_add_attachment`
  (or the company command), each under its own idempotency key, so the same
  rights and history apply and a failed file can be tried again without a
  second stored copy. Files are read from disk only when uploaded. No
  database change.
- **The tracker.** The Staff Documents & Passes tracker holds no scans (no
  images, embedded files or links), so nothing was uploaded from it.

## Release and rollback

1. Apply `20261114120000_people_records_foundation.sql` (additive,
   repeatable), then `20261114130000_people_records_read_volatility.sql`.
   The read functions must be volatile: PostgREST runs a STABLE function
   read-only, and every People function first syncs the caller's profile,
   which writes. A pgTAP check keeps every People entry point volatile.
2. Load the tracker through `v1_people_import` as an Admin, from a
   reviewed script. The payload holds personal data and is never committed.
3. Build with `YORKS_V1_PEOPLE_RECORDS=true`.

Rollback: build with the flag off, and set the two catalogue rows to
`is_assignable = false` if access must close at once. Keep every row.

## Tests

- `supabase/tests/database/yorks_people_records.test.sql`: role matrix
  (Admin, PR, Accountant allowed; Project Engineer, Site Engineer,
  Procurement, Senior Mechanical Engineer refused), table grants closed,
  save/renew/end, single-current rule, stale versions, idempotent retry,
  import classification and re-import.
- `test/yorks_v1_people_records_test.dart`: reader and export round trip,
  home, record and form at desktop and 360 px (goldens), renew, add,
  refusal in place, end with reason, new and edit person, import preview
  and commit.
