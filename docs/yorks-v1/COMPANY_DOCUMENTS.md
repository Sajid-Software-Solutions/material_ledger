# Company documents

Owner request: 13 November 2026 ([`PRODUCT_DECISIONS.md`](PRODUCT_DECISIONS.md)
section 43). The second part of the People section
([`PEOPLE_RECORDS.md`](PEOPLE_RECORDS.md)).

Company documents keeps everything the company itself holds, with the
same expiry status, renewal history, Excel import and export as People:

| Record | What it holds | From the tracker |
| --- | --- | --- |
| Company or branch | Trade licence, establishment card, labour file, PRO cards, other per-company documents | Company Licenses & Permits: the LICENSES row and the rows under it, by column |
| Certificate or permit | Civil Defence, ISO 9001, ICV, CMW, CICPA company registration, land rent and similar | The same sheet, rows with one or two dates |
| Vehicle | Registration, Asateel permit, CICPA vehicle pass | The car registration sections (company, branch and personal cars) and the vehicle lines of the Gate Passes sheet, joined by plate |
| Insurance policy | The policy and its expiry | The insurance lines between the people on Staff Documents, for the company block they sit in, and Workmen's insurance |
| CICPA pass | LOA, with job, people, vehicles and passes applied for | CICPA Contracts, under each company heading |

A row in the licence sheet with only one or two dates is not tied to a
company: its second date is kept as a second document labelled "Value 2"
(the tracker's own column) so PR can say which company it belongs to.
Note rows such as "(COURT) 3 spas" are reported and not imported, and so
is the company's postal address ("P.O. BOX …"): it is an address, not a
document (owner decision, 14 November 2026). The P.O. Box line loaded on
13 November was archived in production with that reason.

The register formerly called "CICPA contracts" is named **CICPA passes**
(owner decision, 14 November 2026). The stored kind stays `contract`, so
records, exports and history are unchanged; an export that says "CICPA
contract" still reads back.

## Who sees what

Admin, PR and Accountant view and manage by default through
`company_documents.view` and `company_documents.manage` (enforced, own
module; Admin and PR delegate). The Accountant and PR capability
boundaries each gain exactly these two keys. No other role sees them
unless granted per person.

## Model

- `v1_company_docs_records`: kind (entity, item, vehicle, policy,
  contract), name, reference (licence number, plate, policy or LOA
  number), owner (the company or branch, or Personal), contract details
  (job and whole-number counts only), notes, active or archived with a
  reason, record version.
- `v1_company_docs_documents`: kind (trade licence, establishment card,
  labour file, PRO card, certificate or permit, registration, Asateel
  permit, CICPA pass, insurance, LOA, other), label, number, issue and
  expiry dates, sites, notes. A document needs a number or an expiry; a
  CICPA pass may name only its sites. A renewal ends the current one as
  *renewed* and keeps it.
- `v1_company_docs_revisions`: append-only history. Records and documents
  are never deleted; a record is archived (a sold vehicle, a finished
  contract) and can be restored.

Status uses the People rule: expired, expiring within 60 days, valid, or no
expiry.

## Commands

All are security-definer and VOLATILE (PostgREST runs STABLE functions
read-only, and each one syncs the caller's profile first; a pgTAP check
keeps it so). Writes take an idempotency key and the record version they
were read at.

| Function | Use |
| --- | --- |
| `v1_company_docs_overview()` | Counts by kind, expired and expiring records, owners, the attention list |
| `v1_company_docs_list(p_query)` | Register: kinds, owner, search, status, archived, sort, paging |
| `v1_company_docs_get(p_record_id)` | One record, documents, previous documents, history |
| `v1_company_docs_save_record` | Add a record or correct one (the kind is fixed once saved) |
| `v1_company_docs_set_archived` | Archive with a reason, or restore |
| `v1_company_docs_save_document` | Add, correct, or renew a document |
| `v1_company_docs_end_document` | End a document with a reason |
| `v1_company_docs_preview_import` / `v1_company_docs_import` | Classify, then apply, the tracker or an export |

Import matches a vehicle or contract by its plate or LOA number, a company
or branch by name and licence number, anything else by name and owner;
documents by kind and label. A blank cell keeps what is stored and an
older expiry never replaces a newer one. Any problem row blocks the whole
import.

Export writes one Company Documents sheet (one row per document, which
imports again) and a Needs Attention sheet.

## Screens

- `/yorks/company-documents`: Needs attention, Licences & permits,
  Vehicles, Insurance, CICPA passes; six tiles; search, company, sort
  and Show archived; Import, Export and Add record; a link to People.
- `/yorks/company-documents/:recordId`: header with Archive, Edit and Add
  document; status banner; documents table with an empty row for each
  expected document not yet held; details (contract counts for an LOA);
  previous documents; history.
- `/yorks/company-documents/new?kind=…` and `…/:recordId/edit`: the
  Material Request composer; a Contract card for an LOA.
- The PR Overview shows company documents that need attention, and People
  links here.

Behind `YORKS_V1_COMPANY_DOCUMENTS` (default off) and
`company_documents.view`; new and edit also need
`company_documents.manage`.

## Release and rollback

1. Apply `20261114140000_company_documents_foundation.sql` (additive,
   repeatable).
2. Load the tracker through `v1_company_docs_import` as an Admin, from a
   reviewed script.
3. Build with `YORKS_V1_COMPANY_DOCUMENTS=true`.

Rollback: build with the flag off, and set the two catalogue rows to
`is_assignable = false` if access must close at once. Keep every row.

## Tests

- `supabase/tests/database/yorks_company_documents.test.sql` (43
  assertions): role matrix, boundaries, closed grants, volatility, record
  and document lifecycle, contract details, archive, stale versions,
  idempotent retries, import matching and re-import.
- `test/yorks_v1_company_documents_test.dart`: reader and export round
  trip; home, record and form goldens; renew, sites-only pass, end, archive,
  new contract, conflict, import and export, refused reader.
