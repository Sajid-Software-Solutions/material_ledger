# D4 — Cent (fils) rounding: decision needed from the owner

**Status:** awaiting owner sign-off · **Scope:** Accounts V2 invoice totals only ·
**Blocks:** turning on `YORKS_V1_ACCOUNTS_WORKSPACE_V2` in production
**Prepared:** 2026-11-05 · **Reference invoice:** YRA-322 `INVOICE#02R.1`

---

## The question in one line

When an invoice's amount is built from several building × stage (and item)
lines, do we **round each line to the fil and then add them up** (what the
system does today), or **add the lines at full precision and round once at the
end** (what Yorks' Excel sheet does)? The two can disagree by **one fil**.

This is a policy choice, not a bug. Both are defensible; they must simply match
what Yorks treats as the official figure on the printed tax invoice.

---

## Why the two ever differ

An invoice line is **derived**, not typed: a line amount is
`contract value × building % × stage %`, and for items-mode stages
`item value × claimed qty ÷ total qty`. Those divisions rarely land exactly on a
whole fil, so each line carries a fraction of a fil.

- **Round-then-sum** rounds every line to 2 decimals first, then adds. The
  dropped sub-fil fractions never come back.
- **Sum-then-round** keeps every line at full precision, adds them, and rounds
  the single total. The fractions can add up to tip the last fil.

Across a handful of lines this nets to **0 or ±0.01 (one fil)** on the ex-VAT
gross — never more. VAT (5%) is then applied to whichever gross is chosen, so
the VAT and grand total can shift by a fil too.

---

## What the system does today

The issue command computes (invoice-issue migration, `v1_issue_client_invoice`):

```
ex_vat  = Σ (each claim line, already stored rounded to the fil)
vat     = round(ex_vat × vat_rate% / 100, 2)
total   = ex_vat + vat
```

So today = **round-each-line-then-sum**, with VAT applied once to the summed
gross. This is the behavior recorded as **D4** in `PRODUCT_DECISIONS.md`.

## What Yorks' Excel does

On `INVOICE#02R.1` the Excel sheet prints the ex-VAT gross ending in **.45**,
i.e. it keeps the lines at full precision and rounds the **total** once
(sum-then-round).

## The concrete divergence (YRA-322, Claim #02)

| Line | Amount (round-then-sum, today) |
|------|-------------------------------:|
| DF3W | 1,549,624.36 |
| DF4W | 1,549,624.36 |
| DF6W | 1,463,664.36 |
| DF7W | 1,420,684.36 |
| **Ex-VAT gross — system (D4)** | **5,983,597.44** |
| **Ex-VAT gross — Excel (total-only)** | **5,983,597.45** |

**Difference: 0.01 (one fil)** on the ex-VAT gross, which also moves VAT/total by
up to a fil. Cumulative ex-VAT after Claim #02 is **7,702,797.44** under the
current method.

---

## Options

### Option A — Keep round-then-sum (current, D4 as written) — *recommended*

- **Pros:** Every printed line adds up **exactly** to the gross on the page — no
  "the lines don't sum to the total" question from a client or auditor. It is the
  method already implemented, tested (pgTAP ties the claim cap to the fil), and
  frozen into each issued invoice's snapshot. No code change.
- **Cons:** On a minority of invoices the gross is one fil below Yorks' old Excel
  figure (e.g. `.44` vs `.45`), so historical Excel invoices won't always match
  to the last fil.

### Option B — Switch to sum-then-round (match Excel)

- **Pros:** Reproduces Yorks' existing Excel invoices to the last fil, including
  `INVOICE#02R.1` → `.45`.
- **Cons:** The displayed lines can then **not** add up to the printed gross by a
  fil, which invites questions; requires changing the gross computation in
  `v1_issue_client_invoice` (and every reader/report that re-derives gross),
  re-running the DB gate, and re-recording D4. The P9 history import's expected
  totals must be re-pinned to the sum-then-round figures.

> A third variant — round-then-sum for the lines **but** carry the exact gross
> onto the invoice — is **not recommended**: it is the worst of both (lines that
> visibly don't total, and a number that matches neither method cleanly).

---

## Recommendation

**Keep Option A (round-then-sum, D4 as written).** The invoice is a document a
client and an auditor read line by line; lines that sum exactly to the printed
total matter more than matching a one-fil quirk of the old spreadsheet. The
one-fil gaps against historical Excel invoices are explainable and bounded.

If the owner instead wants **byte-for-byte parity with the Excel invoices**
(e.g. because clients reconcile against the old PDFs), choose **Option B** and we
will change the gross computation, re-pin the P9 import totals, re-run the gates,
and update D4.

---

## What we need from the owner

1. **A or B?** (If no reply, we proceed on **A** — current behavior.)
2. If **B**: confirm it applies to **new** invoices only, or whether any
   already-issued V2 invoice snapshots must be reissued (none exist yet, since
   the flag is off in production).

Either answer is recorded back into `PRODUCT_DECISIONS.md` (D4) before the
feature flag is turned on.
