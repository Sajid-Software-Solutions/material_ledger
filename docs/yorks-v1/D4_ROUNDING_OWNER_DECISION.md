# D4 — Cent (fils) rounding

**Status: RESOLVED (2026-11-05) — keep the server's per-cell rounding (Option A).**
Owner to acknowledge the ≤1-fil difference vs the historical Excel PDFs before
go-live. · **Scope:** Accounts V2 invoice totals only ·
**Prepared:** 2026-11-05 · **Verified against primary sources** (Yorks' own Excel
invoice + the approved HTML prototype). **Reference invoice:** YRA-322
`INVOICE#02R.1`

> **Resolution.** We evaluated matching the Excel/prototype exactly (Option B)
> and **declined** it. Exact parity is not a contained change: each building is
> its own claim line stored at `numeric(20,2)`, and the server intentionally
> rounds each building × stage cell to the fil (item values are distributed by
> largest remainder so they sum to the cell exactly). The sub-fil fractions are
> therefore gone before the gross sums the cells, so no "round later" recovers
> the last fil — B would require carrying cell amounts at sub-fil precision
> through the claim/invoice engine (an additive exact-amount column populated at
> claim creation, plus issue/gross/P9 changes). That is disproportionate to a
> **≤1-fil** cosmetic match, and the per-cell model is the stricter one (printed
> lines always total the printed gross). We keep **Option A**; the sections below
> record the full analysis.

---

## The question in one line

When an invoice is built from several building × stage (and item) lines, do we
**round each line to the fil and then add them up** (what the server code does
today), or **keep every line at full precision and round once at the final
total** (what Yorks' Excel and the approved prototype both do)? The two differ by
up to **one fil**.

> **New since the first draft of this memo:** I read Yorks' actual
> `INVOICE#02R.1.xlsx` and the approved `Yorks_Project_Accounts_Prototype.html`.
> **Both use total-only rounding.** The current server is the odd one out. That
> reverses the earlier recommendation — see "Recommendation" below.

---

## Why the two ever differ

An invoice line is **derived**, not typed:
`line = contract × building % × stage %`, and for items-mode stages
`item = item value × delivered qty ÷ total qty`. Those divisions rarely land on a
whole fil (e.g. 20 of 55 fire dampers → `20/55 × 1% × 17,192,000 = 62,516.3636…`),
so each line carries a fraction of a fil.

- **Round-each-line-then-sum** rounds every line to 2 decimals first, then adds.
  The dropped sub-fil fractions never come back.
- **Full precision, round once** carries every line unrounded, adds them, and
  rounds the single final total. The fractions can add up and tip the last fil.

Across a handful of lines this nets to **0 or ±0.01 (one fil)** on the ex-VAT
gross — never more. VAT (5%) and the grand total shift with it.

---

## What each source actually does (verified)

### Yorks' Excel — `INVOICE#02R.1.xlsx` → **full precision, round once**
Every cell is a live formula held at full floating-point precision; nothing is
rounded until the printed cell shows 2 decimals.
- Item amount `Material!N13 = (20/55) × 1% × 17,192,000 = 62,516.3636…` (stored
  unrounded).
- Per-building Material total `Material!N26 = 1,549,624.3636…` (sum of unrounded
  items).
- All-building Material Supply `Summary!J55 = 5,983,597.4545…` (sum of the four
  unrounded buildings).
- Invoice `INVOICE!K37 (GROSS) = 5,983,597.4545…`, `K39 (VAT) = K37×5% =
  299,179.8727…`, `K40 (NET) = 6,282,777.3272…`.
- Printed, these display **5,983,597.45 / 299,179.87 / 6,282,777.33**.

### Approved prototype — `Yorks_Project_Accounts_Prototype.html` → **full precision, round once**
The claim math is all unrounded (`itemVal = contract × weight%`;
`bsAmount = Σ itemVal × qty ÷ totalQty`; `gross += bsAmount` over every
building × stage). Rounding happens only at the invoice total (line 533):
```js
const raw = snap.gross;               // full-precision sum, no per-line rounding
gross = r2(raw);                      // round the total once
vat   = r2(raw * VAT());              // VAT from the UNROUNDED gross
total = r2(raw * (1 + VAT()));        // total from the UNROUNDED gross
```
Byte-identical in method to the Excel, so it reproduces `.45`.

### Current server — `v1_issue_client_invoice` → **round-each-line-then-sum**
```
ex_vat = Σ (claim lines, each stored as numeric(20,2) — already fil-rounded)
vat    = round(ex_vat × vat_rate% / 100, 2)
total  = ex_vat + vat
```
Four Material Supply lines at `1,549,624.36 / 1,549,624.36 / 1,463,664.36 /
1,420,684.36` sum to **5,983,597.44** — one fil below the Excel/prototype. This
is the behavior currently written up as **D4** in `PRODUCT_DECISIONS.md`, and it
is a **deviation from the approved target**, not the target itself.

### The divergence on INVOICE#02R.1

| | Ex-VAT gross | VAT (5%) | Net payable |
|---|---:|---:|---:|
| Excel + approved prototype (round once) | **5,983,597.45** | 299,179.87 | 6,282,777.33 |
| Current server (round each line) | 5,983,597.44 | 299,179.87 | 6,282,777.32 |

**Gap: one fil** on gross, carried into the net.

---

## Options

### Option A — Keep the server's round-each-line-then-sum (current / D4 as written)
- **Pros:** No code change; already implemented and tested (pgTAP ties the claim
  cap to the fil). The printed line amounts always add up exactly to the printed
  gross.
- **Cons:** **Does not match Yorks' real invoices or the approved prototype.**
  Every multi-line invoice can sit a fil below the figure Yorks (and the client)
  expect from the spreadsheet — e.g. `.44` where the signed `INVOICE#02R.1` shows
  `.45`. We would be shipping a number the business has never used.

### Option B — Full precision, round once (match the Excel **and** the prototype) — *recommended*
- **Pros:** Reproduces Yorks' existing invoices and the owner-approved prototype
  to the last fil. It is what the authority sources (effective R35 prototype, and
  the real signed PDFs) actually do, so it needs no owner "tie-breaker" beyond
  confirming the change.
- **Cons:** Requires code + data work: carry the claim/invoice gross at full
  precision (not a sum of `numeric(20,2)` lines) and compute VAT off it in
  `v1_issue_client_invoice` and every reader/report that re-derives gross;
  re-run the DB gate; re-pin the P9 history-import expected totals to the `.45`
  figures; update D4 in `PRODUCT_DECISIONS.md`. The printed line amounts can then
  sit a fil off the printed gross — but **Yorks' own invoices already do this and
  are signed and accepted**, so it is the established, expected behavior, not a
  regression.

---

## Decision (why A, after evaluating B)

Matching the Excel/prototype exactly (Option B) is the faithful-to-the-old-PDFs
choice, and initially we leaned that way. On tracing the engine, B turned out to
require a **sub-fil precision change through the core claim/invoice path**, not a
contained tweak (see the Resolution box at the top). Weighed against a **≤1-fil**
difference that only appears when several buildings are summed, that migration is
disproportionate — and the server's per-cell model is arguably *better*: every
printed line totals the printed gross exactly, with no sub-fil display quirk.

So we **keep Option A** (round each building × stage cell to the fil; gross = Σ
cells; VAT on gross). No code change; the behavior is already implemented and
tested.

## What this needs from the owner

Just an **acknowledgement**, not a build: on a multi-building invoice the system
may show a gross one fil different from the equivalent old Excel sheet (e.g.
`5,983,597.44` where `INVOICE#02R.1` printed `.45`). If any client reconciles to
the fil against the **historical** PDFs, flag it and we will reopen Option B.
Otherwise A stands and D4 is closed. (No V2 invoice has been issued in production
— the flag is off — so nothing needs reissuing either way.)
