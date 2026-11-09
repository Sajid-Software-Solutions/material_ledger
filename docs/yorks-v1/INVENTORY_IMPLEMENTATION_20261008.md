# Inventory reliability and usability — implementation candidate

8 October 2026. First coherent implementation slice from [the audit](INVENTORY_AUDIT_20261008.md). This is a local candidate, not a production release or completion of every audit phase.

## Implemented

- Project and Company reservations appear in the authorized inventory projection. Company destinations use unit/category labels, with no additional commercial or personal fields.
- Stock creation and adjustment retain the exact payload, expected version and idempotency key after an uncertain response. Concurrent submission is blocked; definitive rejection permits correction. Navigation and editor changes are blocked until an uncertain command is resolved in the current session.
- Import navigation is blocked while committing or awaiting confirmation. The provider retains pending state, prevents edits/reset during uncertain outcomes, and refreshes stock, history and supplier reads after confirmed success.
- Negative corrections use the server's signed, nonzero delta semantics; labels follow the selected action. Existing server stock-floor, role, version and transaction checks remain unchanged.
- Inventory reads refresh on coalesced workflow signals, foreground return and a foreground 60-second interval. Providers watch the current user and role.
- Global and item movement history use authorized server search/type filters and timestamp/ID cursor pages. Item summaries no longer load all history. Old RPCs remain for older clients.
- Movement Excel exports retrieve all matching pages rather than exporting the stock register or silently stopping at 100. Stock exports follow the current stock filters. Export retrieval stops if the current user or role changes.
- Stock is the default view. Mobile has visible search, collapsed secondary filters and a section dropdown. Repeated actions were consolidated. Supplier navigation retains the parent page, and shell breadcrumbs recognize inventory subroutes. Items without a configured minimum say so explicitly.
- SQL materializes item projections once and uses grouped movement statistics instead of repeated correlated count/latest queries. Search input is debounced. This is not a measured production performance claim.

## Change boundaries

Models: reservation source kind and history query/page types. Repositories: movement-page RPC and bounded item-summary RPC. Controllers/providers: stock retry lifecycle, import retention and read invalidation. UI/routes: Inventory, import, supplier navigation and exit guards. Export service: movement workbook. Migration and database tests are additive. No unrelated feature, stock command, table RLS policy or production data was changed.

## Data preservation and rollout

Migration: [20261008062343_inventory_reliability.sql](../../supabase/migrations/20261008062343_inventory_reliability.sql).

It replaces the read projection, adds read RPCs and an index, and preserves existing rows, IDs, balances, reservations, movements and audit history. New RPCs revoke public/anonymous execution, grant authenticated execution and enforce the existing inventory read guard internally. Authorized read access does not grant stock mutation.

Apply the migration before deploying this client; the client requires the new history and item-summary RPCs. Older clients continue to use their existing RPCs. Roll back the client first if necessary; leaving the additive RPCs/index in place is safe. Any database rollback should restore the previous projection definition explicitly and must not delete inventory data or reverse committed stock movements.

## Verification

- `flutter pub get`: passed.
- `flutter analyze`: no issues.
- Full `flutter test`: 2,571 passed, four existing skips. After the final export-authority check and history invalidation, the focused Inventory suites were rerun: 71 passed.
- CI web build and startup-size budget: passed. CI APK build with ephemeral signing: passed.
- Local `supabase db reset --local`: passed, including the new migration.
- Full local `supabase test db`: 3,692 tests across 127 files passed. New coverage includes mixed Company demand, bounded/older history, stable same-timestamp paging, positive read permissions and negative stock/read permission cases.
- Desktop, tablet and 360px widget goldens updated and inspected. These are controlled widget renders, not production browser or physical-device evidence.
- Retry tests cover a lost response, replay of the exact command, offline retry, definitive rejection and concurrent clicks; widget tests also cover create/adjust retry and a negative correction.
- Export tests inspect signed movement facts and workbook cell encoding.

## Remaining audit phases and release limitations

- Pending command recovery currently survives in-app navigation guards/provider retention, **not a full browser reload or process termination**. Durable, authority-scoped recovery and reopen/reconciliation need a separate tested slice before calling reload recovery complete.
- The stock workspace still retrieves all stock; server stock/reservation paging, separate summary reads, measured large-data/import performance and privacy-safe search timing remain open.
- Movement date-range controls, a print view matching export, sticky desktop item identity, further supplier-folder simplification and explicit last-updated/stale UI remain open.
- Two-person browser refresh/reconnect tests, secondary-language/RTL visual inspection and warehouse-staff task testing remain release gates. Current local checks do not certify every flow bug-free.
- No hosted migration, staging deployment, production promotion or live stock mutation was performed. CI builds use an invalid placeholder backend; the APK uses ephemeral CI signing and is not a production distribution artifact.

## Follow-up implementation — 8 October 2026

This section and the final verification below supersede the historical remaining-scope statements above for the new local candidate.

### Implemented in this follow-up

- Stock commands persist the complete submitted input and original idempotency key before invoking the repository. A reloaded Inventory page presents a retry action instead of accepting a replacement command. Successful confirmation removes recovery; a definitive rejection allows a new reviewed command and shows rejection feedback. Storage failure prevents the write. Unrecognized recovery fields remain preserved and block replay rather than being silently discarded.
- Import commands persist both the original key and exact receipt/adjustment payload. Recovery is available from Inventory and a freshly opened Import route. Replaying requires an explicit click and the usual server checks; this is not automatic offline stock submission. A pending import cannot be overwritten by a different command.
- Both recovery namespaces include the authenticated user and exact role. Inactive provider instances cannot start new writes. Restoring another account does not expose or execute the saved operation. Browser storage must remain available; clearing site data removes local recovery. This does not implement cross-tab ownership leases.
- Movement history accepts an inclusive start/exclusive end timestamp range. Local selected calendar days are converted to UTC boundaries. Filters survive cursor changes and are also used for Excel and print. The additive `v1_inventory_movement_page_v2` RPC keeps the original RPC available to older clients.
- Printing uses the same canonical headings and row values as Excel, with bundled Unicode fonts, repeated table headings and page numbering. PDF generation checks authority again before opening print. It does not access commercial values.
- The desktop stock identity column stays fixed when horizontally scrolling quantities and actions. Existing vertical lazy rows remain. A regression checks that horizontal offset changes while the item's screen position stays fixed.
- Successful stock reads show their check time and in-progress refresh is labeled. Debounced paged stock searches report result count, length bucket and repository query duration through the existing privacy-filtered analytics service. The legacy adapter fallback measures local filtering instead. Neither sends search text, item descriptions or stock contents.

### Performance evidence

A rollback-only local Postgres probe inserted 2,500 items and 10,000 movements. `EXPLAIN (ANALYZE, BUFFERS)` measured approximately 92.5 ms for the full workspace function and 32.0 ms for a 50-row searched history page. The workspace JSON was 1,655,332 bytes. All probe fixtures were rolled back. These are single local samples, not production percentiles or mobile/network benchmarks. They establish that stock payload size still merits paged queries despite the relatively quick local database call.

### Additional verification

- Full local database suite: 3,695 checks across 127 files passed after a clean reset.
- Full Flutter regression: 2,577 passed, four existing skips before final recovery-edge tests; final gate results recorded below.
- Focused tests cover restored command replay, unchanged payload/key on import retry, storage failure before submission, authority changes, owner isolation, preserved unknown fields, PDF generation, history dates and pinned identity scrolling.
- Desktop and 360px history goldens were updated and inspected. Automated UI recovery checks restore a saved command, reject a lost response, replay its original key, clear it only after confirmation, and keep it invisible to another owner.

### Paging and mobile refinements

- Stock and reservations now use authorized, filtered server pages, defaulting to 50 rows. Search/filter changes reset pagination; stock exports retrieve every matching page and stop on authority changes or non-progress. Search text and focus survive loading. History uses a minimal stock page for its surrounding context.
- The additive [register-page migration](../../supabase/migrations/20261008080029_inventory_register_pages.sql) preserves the existing safe quantity/category/summary projection internally. This bounds routine response size, not total SQL work. Overview and explicit full-catalogue validation/picker operations still use the full projection.
- The same rollback-only 2,500-item probe measured 41,780 bytes for a 50-item page versus 1,655,351 bytes for the full response: approximately 97.5% less transport data. The paged call took 103.1 ms locally. These are single local samples, not production latency guarantees.
- Supplier-folder mobile metrics are collapsed under Overview. Identity, document actions and Unknown Supplier guidance remain visible.
- Arabic/RTL 360px and desktop goldens cover the stock register. Horizontal identity pinning is tested in both directions.
- Import recovery is gzip-compressed before storage, with compatibility for earlier plain JSON. A 20,000-row recovery test checks exact round-trip preservation and a stored size below 1 MB for its fixture. Storage failure still prevents submission.

### Final verification

- Full Flutter regression: 2,583 passed, four existing skips. After adding compressed recovery, the final three focused suites passed 72 tests, including the new large recovery fixture.
- Final analyzer: no issues. Web build/startup budget and Android CI build passed. APK signing is ephemeral CI signing, not a production distribution signature.
- Clean local database reset and full suite: 3,710 tests across 128 files passed. The Company-reservation test was subsequently switched to the actual paged RPC and rerun: 17 passed.
- Existing 20,000-row workbook validation benchmark passed in the full Flutter suite. Physical mobile/browser main-thread profiling remains unverified.
- Desktop/mobile and Arabic/RTL widget evidence is under `test/goldens/r38_3/`; supplier evidence is under `test/goldens/r38_9/`. Widget renders and controller recreation tests do not establish real browser crash/reconnect or warehouse-staff acceptance.

### Release order and remaining validation

Apply all three Inventory read migrations before this client: `20261008062343_inventory_reliability.sql`, [20261008072819_inventory_history_date_range.sql](../../supabase/migrations/20261008072819_inventory_history_date_range.sql), and `20261008080029_inventory_register_pages.sql`. Existing RPCs remain compatible. Roll back the client first and retain additive read functions; do not reverse stock movements or delete historical data.

Remaining validation is multi-person browser reconnect testing, constrained-device import profiling and warehouse-staff task testing. Further separation of summary computation from the full internal projection should follow measured production scale needs. No hosted migration, staging deployment, production promotion or real stock mutation was performed.

## Authorized production release — 8 October 2026

The owner explicitly requested “deploy to production please”. Clean source
`baa4f118e0ae5b5b493f3a153dbd8c343522ce0b` was built with the existing production
configuration, preserving previously enabled modules. Production backend binding,
source stamp and absence of staging/CI placeholders were checked in the artifact.

The three tracked SQL files were applied unchanged through the hosted migration
API, first to staging and then production. Hosted ledger IDs differ from local
filenames, as in earlier releases:

| Migration | Staging ledger | Production ledger |
| --- | --- | --- |
| inventory_reliability | 20261008110049 | 20261008110234 |
| inventory_history_date_range | 20261008110053 | 20261008110237 |
| inventory_register_pages | 20261008110056 | 20261008110242 |

- Read-only database smoke checks passed for stock, reservations and history.
  Anonymous execution is denied for the new page RPCs. An initial production
  probe using a nonexistent fixture identity was correctly denied; the read-only
  probe then passed using an existing Admin identity without changing that user.
- Deployment: `dpl_BzugN8M8Wawfa2rUU2zhdWLN9EC1`.
- Immutable URL: https://yorks-r35-lcw7nigzf-sajid-alis-projects-0ec775a2.vercel.app
- Public URL: https://yorks-r35.vercel.app
- Candidate and public alias each passed 26 asset/route SHA-256 checks, plus
  Inventory and Import deep-route checks. The authenticated CLI verification
  timed out; direct public verification succeeded without changing protection.
- Production build and startup budget passed (main JavaScript 10,000,402 bytes;
  gzip 2,883,635 bytes). Flutter clean stalled resolving unrelated Xcode packages;
  the generated web directory was cleared explicitly before the successful build.
- Authenticated live browser checks confirmed stock cards with freshness status
  on mobile and movement history with date/print/export controls on desktop.
  The bounded browser console error check returned no errors. No real stock,
  import, reservation or business record was written during verification.
- Local artifact: `/tmp/yorks-inventory-production-20261008`; browser screenshots:
  `/tmp/yorks-inventory-evidence-20261008/production-mobile.png` and
  `/tmp/yorks-inventory-evidence-20261008/production-history-desktop.png`.
- Rollback deployment: `dpl_ATbb2j7yzeGgc3ggwMPEhFa2woc3`, immutable URL
  https://yorks-r35-ovnt890ju-sajid-alis-projects-0ec775a2.vercel.app.
  Restore that client if needed and retain the backward-compatible read migrations.

This supersedes the earlier undeployed status. Physical-device staff acceptance,
real multi-user reconnect exercises and long-running monitoring remain unverified.
