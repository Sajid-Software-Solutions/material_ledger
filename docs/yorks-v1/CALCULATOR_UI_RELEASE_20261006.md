# Calculator interface release — 6 October 2026

Status: **released and verified** at [production Calculators](https://yorks-r35.vercel.app/#/tools/calculators).
The owner's earlier authorization to complete the calculators and update production applies to this refinement.
Implementation: [PR #49](https://github.com/SajidAfridi/material_ledger/pull/49).
Exact deployment and gate evidence: [JSON record](CALCULATOR_UI_RELEASE_20261006.json).

## Interface

The calculator home uses the existing universal Yorks navigation, a compact header,
two neutral launch cards and a recent-calculation list. Search, type, scope and
archive filters remain authorized and paginated. Clear filters recovers empty
search results. The duplicate calculator sidebar has been removed.

Saved records have one compact action header, an accessible editable title,
scope, revision, actor and timestamp. Save is disabled when there are no changes;
an in-flight command shows Saving until the server confirms it. Secondary actions
are grouped; view-only users retain print/export without edit or archive authority.

Duct inputs and results have separate quiet panels. Design basis and ESP system
details collapse without losing values. Desktop ESP keeps the spreadsheet;
360px phones keep the focused row editor. All nine home/Duct/ESP goldens at
1366, 768 and 360px pass, and Arabic RTL editing remains verified.

## Release and verification

| Evidence | Value |
|---|---|
| Merged application source | `58cf37f2062d175a36a201d269c561d01f826e75` |
| Production deployment | `dpl_5N1eU8yvGGi9gGaRX4bBoa3ZW2yr`, READY |
| Immutable artifact | [verified production artifact](https://yorks-r35-3435qbql5-sajid-alis-projects-0ec775a2.vercel.app) |
| Main bundle | 9,863,668 bytes; budget gzip 2,843,319 bytes |
| Main SHA-256 | `f4fa8955da03cf52356d4f6c370b5ad4b791d129eb41bc2c9b7f81224a845669` |
| Static artifact | 60 files; 54,277,398 bytes |
| Analyzer and Flutter | No issues; 2,473 passed, four retained skips |
| Focused calculator suite | 25 passed |
| Clean local database suite | 123 files; 3,597 assertions passed |
| Builds | CI web, ephemeral-signed CI APK and feature-enabled staging/production web passed |
| Artifact checks | 26 candidate, 26 public production and 26 public staging routes/assets passed |

Staging browser acceptance created independent empty Duct and ESP calculations,
edited inputs, saved real server revisions, reopened them, checked totals and
library filtering, and inspected desktop and 360px layouts. Final-build Duct
saving showed Saving and then Saved revision 2. Both synthetic records were
archived recoverably; no temporary access grants were created.

Authenticated production Owner/Admin opened the refreshed home and an empty
creation dialog, then cancelled. Browser error and bounded Vercel error/fatal
checks returned no entries. Static-host logs do not establish backend or all-day
health. Physical devices/printers and all-role interactive logins were not rerun.
A cached older icon font was cleared by a hard refresh; the served font matches
the final artifact byte-for-byte. Temporary browser cache/viewport overrides were
restored afterward.
The retained hosted Flutter workflow/account exception remains distinct from
the passing local gates.

## Preservation and rollback

This release changes calculator UI/copy, tests and documentation. Formulas,
repositories, RPC/RLS, saved data, permissions, imports, exports, routes and
feature defaults are unchanged. No database migration or production business-data
mutation was performed. Existing production feature/configuration flags were
retained, and client assets contain no service-role token, staging backend or CI
placeholder. The source release marker occurs once without a dirty marker.

Roll back by promoting `dpl_9rjHvheK76jH9z5kysbewH36oG8M`, the
[previous verified artifact](https://yorks-r35-ppd0aiybn-sajid-alis-projects-0ec775a2.vercel.app).
Retain calculator data, revisions, grants and audit. Vercel project settings and
unrelated dirty primary-checkout work were not changed.

## Visual evidence

- [Production home, desktop](evidence/calculator-ui-20261006/production-home-desktop.jpg)
- [Duct editor, desktop](evidence/calculator-ui-20261006/staging-duct-desktop.jpg)
- [Duct editor, mobile](evidence/calculator-ui-20261006/staging-duct-mobile.jpg)
- [ESP editor, desktop](evidence/calculator-ui-20261006/staging-esp-desktop.jpg)
- [ESP editor, mobile](evidence/calculator-ui-20261006/staging-esp-mobile.jpg)
