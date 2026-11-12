# Configuration redesign — analysis and plan

Status: approved by the owner, 12 November 2026 (PRODUCT_DECISIONS.md
section 39).

Owner decisions:
1. Admin edits every section; PR edits Workforce and Rentals. No one else
   has access.
2. Accounts defaults (payment policy, billing stages) are editable for new
   baselines only; stages total 100%.
3. Admin manages the default BOQ folders new scopes receive (new scopes
   only).
4. Settings that did nothing are removed from view (rows kept).

## 1. What is there today (production, 12 Nov 2026)

`/yorks/configuration` is one 6,089-line Admin-only screen over 45 settings in
`v1_configuration_settings`, plus inventory units, edited through a shared
draft → validate → publish workflow.

| Kind | Count | What it really does |
|---|---|---|
| Operational | 6 | Changes app behaviour: MR default timing, urgent MRs, creator self-approval, procurement external-source readiness, push on/off, support WhatsApp |
| Protected | 16 | Read-only. Company names, currency, numbering patterns, document formats/size, audit logging |
| Planned | 23 | **Nothing.** Regional formats, security (password, session, MFA), email, retention, accounts terms/stages, company contact and bank |

Problems found:

1. **Most controls do nothing.** 23 of 45 settings are "planned" and have no
   effect, yet they look like real switches and fields. Nine of the 12 areas
   contain no working control at all.
2. **Settings that do matter are mislabelled.** Invoices print the company
   address, phone, TRN and bank block from `company.*`, and workforce reports
   print the company names. Configuration calls them "planned, not in use".
   The bank name, account name and IBAN are **empty in production**, so
   invoices carry no bank details.
3. **Duplicates that disagree with the real source.** `accounts.*` (payment
   terms, PDC days, stage weights) duplicate `v1_accounts_foundation_settings`
   and `v1_accounts_billing_stage_templates`, which Accounts actually uses.
   Editing the Configuration copy changes nothing.
4. **The real setup data has no home.** These are used every day but have no
   page, or a page somewhere else:
   - default BOQ folders for new buildings (`v1_boq_group_templates`, 30 rows):
     no page
   - inventory categories (29) and aliases (41): only via inventory import
   - Company MR categories (6) and units: no page
   - Accounts default payment policy and billing stages: no page
   - Workforce shift, internal locations, trades: Workforce Administration;
     public holidays: Workforce › Crews
   - rental reminders and push transport switches: database only
5. **The page explains itself instead of the business.** The top third is
   safety cards, draft chips, coverage metrics and control modes. An Admin who
   wants to fix the bank details on invoices cannot find them.
6. **Incomplete languages.** About 600 English strings; Arabic, Urdu and
   Hindi cover a fraction (Hindi about 30).

## 2. Goals

- One place to set up the company and every module, in the order people
  think: company and documents, projects, requests, stock, accounts,
  workforce, rentals, notifications, access.
- **Every control works.** If a setting does nothing, it is removed, or shown
  as a plain fact with where it is managed (for example, password rules
  belong to the sign-in service).
- Changes are safe: future records only, a reason, a review of exactly what
  changes, history, conflict on stale edits, server-checked. Existing records
  are never rewritten.
- Keep everything that works: the 6 operational policies, publication
  history, units, the existing RPCs and enforcement, Workforce
  Administration, User Access.

## 3. New structure

The same route, `/yorks/configuration`, with a left list on desktop and a list
of sections on phones (one section per page, 44px targets).

| # | Section | Contents | Source (existing unless marked new) |
|---|---|---|---|
| 0 | **Setup checklist** | What still needs attention, each with a Fix link: bank details missing, no public holidays this year, push off, no PR user, an unused unit… | computed |
| 1 | **Company & documents** | Legal / short / Arabic names; address, phone, fax, email, TRN; **bank block for invoices**; support WhatsApp; a **live letterhead preview** (invoice and Delivery Order header). Fixed facts: currency AED, time zone Asia/Dubai, file types and size. | `company.*`, `support.*` (made operational), facts from protected settings |
| 2 | **Projects & BOQ** | Default folders a new building or Common scope receives (add, rename, turn on/off, order); the 29 standard group names, read-only | `v1_boq_group_templates` + **new** RPC |
| 3 | **Material requests** | Default timing, urgent requests, self-approval (today's 3 policies); Company MR categories and units | existing policies; categories **new** RPC |
| 4 | **Inventory & procurement** | Categories with aliases (add, rename, archive); units (today's register); external-source readiness; warehouse-first rule (fact) | `v1_inventory_categories`, units master actions, existing policy |
| 5 | **Accounts** | Default payment policy and billing stages for **new** project baselines (total must be 100%); existing projects untouched | `v1_accounts_foundation_settings`, `v1_accounts_billing_stage_templates` + **new** RPC; the `accounts.*` duplicates retired |
| 6 | **Workforce** | Default crew shift, internal locations, trades, public holidays (one list, the one attendance uses) | existing workforce RPCs, embedded |
| 7 | **Rentals** | Rental reminders on/off and push on/off | `v1_rental_notification_control` + **new** RPC |
| 8 | **Notifications** | Push on/off; delivery health (existing); the daily reminders listed with their times (read-only) | existing |
| 9 | **Access & security** | Links to User Access and role templates; sign-in rules shown as facts managed by the sign-in service | links only |
| 10 | **Numbering** | Each document number pattern with a live example; read-only | protected settings |
| 11 | **History** | Every published change: who, role, when, reason, before → after | existing publications |

Removed from view (rows kept in the database, never deleted): regional date
format, financial year, primary/secondary language (the app has its own
language setting), email notifications, security password/session/MFA,
document and audit retention. None of them did anything.

## 4. How editing works

- Each section edits in place. **Save changes** opens a review: every change,
  before → after, plus a required reason. It is stored as one publication
  (reusing `v1_stage_configuration_setting` + `v1_publish_configuration`, or
  the module's own RPC for list data), so history and audit stay complete.
- A stale edit (someone published meanwhile) is refused with "Reload to see
  their change", and nothing is overwritten.
- Lists (folders, categories, units, MR categories, locations, trades,
  holidays) use add / rename / archive / restore. Nothing used by a record is
  deleted.
- Changes apply to future records only: invoices, Delivery Orders and reports
  already issued keep their frozen header.
- No shared global draft, and no draft/validate/publish toolbar.

## 5. Security and data

- Server-enforced on every call: the configuration capability keys (Admin by
  default) or the module's own key (for example `workforce.configuration.manage`,
  `inventory.categories.manage`). UI hiding is never the control.
- Additive migration: new list RPCs, the `company.*` and `support.*` rows
  reclassified to operational, the `accounts.*` duplicates marked retired. No
  row is rewritten or deleted.
- pgTAP: positive and negative tests for Admin, Project Engineer, Site
  Engineer, Procurement, Accountant and PR on every new command; the 100%
  stage total; idempotency; stale version; and future-only effect (an issued
  invoice keeps its old bank block).

## 6. Delivery (one PR each)

1. Database: list RPCs (BOQ default folders, inventory categories, Company MR
   categories, rental control, accounts defaults), reclassification, pgTAP.
2. New Configuration shell: sections, setup checklist, review-and-save sheet,
   history; Company & documents with the letterhead preview; Numbering.
3. Requests, Inventory & procurement, Accounts.
4. Projects & BOQ, Workforce, Rentals, Notifications, Access.
5. Retire the old screen code; AR/UR/HI copy complete; desktop and 360px
   goldens; staging check; production on approval.
