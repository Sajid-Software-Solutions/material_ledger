# Rental workbook audit — 20 October 2026

This records the supplied workbook evidence and the subsequently approved
non-destructive intake rules. It contains no tenant names or contact details.
The original files were inspected read-only and were not overwritten.

## Source evidence

| File | SHA-256 |
|---|---|
| `Yorks Properties.xlsx` | `d5d48550e1b8d3f0cfc7e0d99c7a3d60136c6dad9ba14787c14cf45241aa5116` |
| Supplied `Yorks_Rental_Properties_Import_Template.xlsx` | `64f31e3c00a15068a50340e43b7a586a5bec72d6d1839e0840dd7f1c63cdae8e` |

The source has one worksheet, `Sheet1`. Its title is in row 1, headers in
`A3:K3`, and 52 property records in `A4:K55`. Formatting extends to `Z999`;
those additional cells contain no records. There are no formulas, cell errors,
hidden rows or columns, external workbook links, or native Excel tables.

The exact eleven source headers are:

1. Unit No
2. Unit Type
3. Tenant / Company
4. Contract Start
5. Contract End
6. Annual Rent (AED)
7. Status
8. Security Cheque (AED)
9. Contact
10. Days to Expiry
11. Expiry Flag

| Control | Result |
|---|---:|
| Property rows | 52 |
| Shop / Store / Office (Store) / Office / missing type | 7 / 6 / 1 / 37 / 1 |
| Active / Empty / missing status | 46 / 4 / 2 |
| Rows with both contract dates | 40 |
| Rows missing contract dates | 12 |
| Numeric annual rent amounts | 39 |
| Sum of annual rent amounts | AED 710,238 |
| Missing annual rent amounts | 13 |
| Numeric security-cheque amounts | 23 |
| Sum of numeric security-cheque amounts | AED 52,000 |

The security-cheque total is source information. It does not establish cash
deposits, cleared cheques, receipts or an opening balance. Four additional
security-cheque cells contain text: `4 YEARS` in rows 21 and 29, `6 Months` in
row 30, and `NO` in row 55. These values must remain intact.

Unit numbers 1–6 are each used once for a Shop and once for a Store. Row 17
has no unit number. Row 36 has no property type. Rows 37 and 45 have no
tenant/company value, and rows 37 and 44 have no status. Every row lacks an
explicit location and contract number. The workbook supplies no payment
history or bank/number/date/status evidence for actual cheque transactions.

As of 20 October 2026, three dated leases have passed their end dates while
their source Status remains Active. Nineteen unexpired leases end within 90
days, including Store 4 on 24 October. The Days to Expiry and Expiry Flag
cells are static values, not formulas. Row 50 says OK despite an end date of
7 December 2026. Preserve the original labels as evidence and calculate live
expiry attention from the stored contract end date.

## Original import failure

The earlier codec required `Rental Properties`, `Payment History`, and
`Cheque Register` worksheets with the detailed template headers in row 1.
It therefore returned one missing-sheet error for each of those three names
and zero rows for the supplied tracker. The preview rendered only row-level
issues, so the actual three workbook-level errors were hidden.

The corrected preview displays workbook-level missing-sheet/header messages
even when no record rows can be parsed. The dialog footer wraps at mobile
width instead of overflowing.

## Approved incomplete intake

The user subsequently authorized importing all 52 records while leaving
missing details editable, preserving annual amounts as annual, retaining a
monthly option, and showing completion warnings.

- Recognize the exact eleven-column tracker at row 3 in `Sheet1` or
  `Rental Properties`. Retain compatibility with the earlier detailed
  27-column format.
- Derive unique codes from source type and unit number. Missing unit row 17
  receives `SOURCE-17`. Keep the original type and unit number in protected
  source metadata. Preserve Store and Office (Store) as distinct supported
  types rather than asserting they are warehouses.
- Preserve Active as occupied and Empty as vacant. Missing or unrecognized
  source status remains unknown, rather than asserting vacancy.
- Keep Annual Rent in `annual_rent`. Do not divide it by twelve. Missing
  rent remains null, rather than asserting a zero-rent contract.
- Keep the original security-cheque value as source metadata and lease
  notes. Do not create deposits, receipts or cheque-register transactions.
- Preserve all original header values and original row numbers in protected
  `source_metadata`. Keep source values separate from corrected live fields.
- Send an explicit null `billing_start` for this source. Do not create
  historical arrears or assume any rent was paid. The first tracked rent date
  and opening balance require later completion.
- Treat missing location, contract, dates, tenant, rent, source identity and
  billing setup as visible completion warnings. Malformed supplied numbers,
  dates, duplicate identities and conflicting annual/monthly inputs remain
  blocking errors.

The revised downloadable format keeps the same eleven source columns and
adds optional Rent Frequency, Monthly Rent (AED), Location, Contract No.,
Unit Code, Billing Start, Monthly Due Day and Import Action columns. Its other sheets retain
Instructions, Payment History, Cheque Register and Lists. Monthly rent requires
an explicit Monthly choice and a value in Monthly Rent; the unselected amount
must be blank. The original files are not changed.

A tracker-derived code that already exists is blocked unless the workbook
explicitly says Update in Import Action. A deliberate update preserves
completed optional values when the corresponding input is missing, keeps the
existing source metadata, and blocks changes to the original eleven source
values. Reimport therefore does not silently clear a confirmed location,
contract number, tenant, billing start or original evidence.

## Local reconciliation evidence

The exact supplied source was decoded through the application codec, producing
52 unique create rows, 133 non-blocking warnings, zero errors, zero payments
and zero cheque transactions. Annual amounts sum to AED 710,238. Every
monthly amount and billing start remains null. Preview itself makes no
repository or database mutation.

Independent comparison of all 572 source cells (52 rows × 11 original
columns) with the application's generated source metadata found no mismatch,
including dates, blank values, numeric amounts and security-cheque text.

The final focused Flutter suite passed 43 tests, including malformed legacy
input rejection, exact source-format recognition, original metadata
preservation, annual/monthly selection without conversion, nullable editing,
unknown occupancy, deliberate reimport, duplicate identity rejection,
same-key retry after an uncertain payment result, competing-tap prevention
and desktop/360px portfolio, full property register, detail and workbook-error
evidence. Before billing starts, current-period and balance displays say Not
confirmed and never claim Paid or a confirmed zero balance. The full release and database
gates are recorded separately by the coordinating release task; this local
evidence does not establish deployment, live import or real-device push
delivery.

A new template was exported through the application codec to
`Yorks_Rental_Properties_Import_Template_2026-10-20.xlsx` in Downloads. Its
five-sheet structure, nineteen tracker/optional headers in row 3 and ZIP
integrity passed verification. Its SHA-256 is
`e590233411acce42a26007eea6dbe402a921bb204818f10dbb4cb7bc98c704af`.
Neither supplied workbook was overwritten.

The coordinating release subsequently imported the exact application-codec
payload through the production import RPC under the authorized Owner actor.
Live reconciliation matched all 52 records and 572 source cells, annual rent
AED 710,238 and zero generated periods, receipts or actual cheques. Same-key
replay retained one import audit and 52 records. The Mac was locked, so the
production browser file-picker path was not exercised. See the [release
record](RENTAL_TRUST_AUDIT_2026-10-20.md) for deployed identities and remaining
physical-browser/OS acceptance limits.

No downstream record, receipt, cheque, document, reservation or audit history
is deleted by the intake. Rollback must retain imported records and source
metadata and use the existing controlled archive/correction paths.
