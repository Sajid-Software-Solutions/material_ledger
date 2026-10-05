# Project setup control corrections

Owner-requested corrections implemented and deployed to staging on 5 October 2026.

## Controls

- New building rows use **Add building**. Existing rows use **Save building** and retain their stable identity. The pending-editor footer says **Finish or cancel**. Continue still waits for unfinished building input.
- Attachments have an optional category picker, default **General**, with Drawing, Calculation, Schedule, Approval, Material list and Other. Search and the **All categories** filter use organization labels; they do not represent access permissions.
- Removed **Requires review**, its checkbox and its creation-readiness blockers. **Preview** opens exact currently selected PDF/image bytes. XLSX/DOCX show a truthful unsupported-preview explanation and optional local **Save file**. Missing local bytes require **Reselect file**.
- Removed the Project details information panel on desktop and its mobile card. The form uses the recovered space; required-field and date validation remain inline.

Original universal workspace navigation, explicit local-save acknowledgement,
saved-setup discovery, single footer Back action and direct confirmed-project
navigation remain in place. Copy is supplied in English, Arabic, Urdu and Hindi.

## Data and access boundaries

Categories are local organization metadata in the setup draft/recovery manifest.
They are separate from protected operational/commercial/restricted document
classification and do not add a field to the existing core RPC or upload payload.
Older omitted categories display General without inserting a field into historical
JSON. Unknown category values and unknown metadata remain retained. Reselection
preserves local identity, hash and category; pending operation keys, original
classification, core payload/hash and upload workflow remain unchanged.

Preview rechecks the writer fence, current owner, backend and trusted capability,
then matches local ID/name/MIME/size/hash to currently resident bytes. Permission
or owner revocation removes the viewer and prevents a stale Save callback. It
does not fetch a remote URL, upload a file or change classification. Widgets use
the existing controllers/providers/local file service. No SQL, RLS, RPC,
repository contract, role or backend deployment changed; database gates were not
rerun for this local presentation/metadata slice.

## Verification

- `flutter pub get`: passed; lockfile unchanged.
- `dart format --output=none --set-exit-if-changed`: **13 Dart files, zero changes**.
- Full `flutter analyze`: **no issues**.
- Full `flutter test --reporter expanded`: **2,383 passed, four retained skips**.
- Focused model/desktop/mobile/flow/recovery checks: **161 passed**. Two affected building snapshot cases passed normally again after the final footer copy correction.
- **14 deliberate PNG baselines** changed, limited to Details, Buildings, Attachments and Review. Independent visual review found no remaining overflow or missing controls. Parties and unrelated snapshots remain untouched.
- Exact same-name image bytes/hashes, General/change/restore, unknown/absent metadata, missing-byte reselection, Office local-save fallback, revoked access and original pending recovery are covered.
- Candidate CI web: **10,028,618 bytes**, gzip **2,887,523**; startup gate passed.
- Candidate CI APK: **110.7 MB**, verified Android v2 **Yorks CI Ephemeral** signature. This is not a publishable Android artifact.
- `git diff --check`: passed.

The required web/Android commands explicitly enabled `YORKS_V1_PROJECT_SETUP`
and used `R35_ENVIRONMENT=ci`, `SUPABASE_URL=https://ci.invalid`,
`SUPABASE_ANON_KEY=ci-publishable-key`; Android also used `CI=true` and
`YORKS_CI_EPHEMERAL_SIGNING=true`.

## Browser evidence and limits

The existing isolated fixture used the real presentation, universal workspace
shell and local storage, with synthetic identity and **no remote backend**.
A public repository PNG was selected locally, rendered in Preview, and closed
through its visible toolbar. Native desktop evidence is **1438×809 CSS**; the
emulated Details captures measured **1636×884** and **359×900 CSS** because of
that origin's browser zoom. Exact **1536px**, **390px**, **360px Arabic/200%**,
and tablet layout boundaries are additionally covered by the widget/golden suite.

- [Desktop Details without information panel](visual-evidence/setup-polish-2026-10-05/local-details-desktop.jpg)
- [Desktop Add building editor](visual-evidence/setup-polish-2026-10-05/local-buildings-desktop.jpg)
- [Compact Details without information card](visual-evidence/setup-polish-2026-10-05/local-details-mobile.jpg)
- [Desktop General/category/Preview controls](visual-evidence/setup-polish-2026-10-05/local-attachments-desktop-native.jpg)
- [Actual selected image and visible close toolbar](visual-evidence/setup-polish-2026-10-05/local-image-preview-desktop-native.jpg)
- [Published staging saved attachment](visual-evidence/setup-polish-2026-10-05/staging-attachments.jpg)

A fresh authenticated staging session at **1280×720 CSS / DPR 2** resumed the
owner's existing **YRA-322 / test** at Attachments. It displayed **General** and
optional category copy with no review checkbox. The file correctly remained
**Reselect file** because a fresh session had no selected bytes. The draft was
owned by another tab: verification did not take over, edit it, issue final
Create/Update, upload a file or change server data. The original user tab was
preserved.

Automation DOM clicks can scroll Flutter's hidden overflow ancestor and move
the Preview toolbar outside the viewport. Native pointer/wheel interaction
verified the toolbar at positive coordinates with ancestor scrollTop zero and
working Close. Local debug hot restart also logged an existing bootstrap
`removeChild` warning; it was not a file-preview error. These checks do not claim
full screen-reader certification or a new real-device PDF/Office acceptance run.
No SDK/accessibility workaround was added.

## Staging release

Clean pushed application source: `96329a0c92b93e3e662c1c46720072e059921dd2`. The full `lib/main.dart`
application was rebuilt after `flutter clean`/dependency resolution using the
ignored staging configuration, setup enabled and PostHog disabled. Isolated
upload/dry-run: **59 files / 54,056,855 bytes**; staging markers two,
production/CI/visual-fixture markers zero. Private credential/service-role scans
passed.

- [Stable staging](https://yorks-r35-staging.vercel.app/yorks/projects#/yorks/projects)
- [Immutable preview](https://yorks-r35-iijoaabzn-sajid-alis-projects-0ec775a2.vercel.app)
- READY preview `dpl_8ZUjQirCCg8EDBrNA9X1fZzjrrXW`, target preview/null.
- Main **10,054,968 bytes**, gzip **2,895,008**.
- Main SHA-256 `6586f786d6a849c57e4461197fdc021a485f1e8d8238455e03b353a14b275218`.
- Index SHA-256 `972a64c127b49a2567a638054c0dc3d4a1373983983ccb019a66558c65668985`.
- Preview and stable each passed **23 route/asset hashes + two Create/Edit routes**.

Only the staging alias changed. Production remains
`dpl_Gj1cfA1CbEJnkVwi4bG8eKabkRJy` with its **9,678,001-byte**
main bundle byte-identical before/after, SHA-256
`739de306598a9c0d135c5c7721d133a8c800321538b05894bda2627b8471b19f`. Checked Vercel build/protection settings are
unchanged. PR #44 remains draft; no merge or production promotion occurred.

Rollback is the previous READY staging preview
`dpl_GFVECJdEtqmhV2jHnXMgHxCQt9Da`
([previous artifact](https://yorks-r35-nmhujwm0r-sajid-alis-projects-0ec775a2.vercel.app)).
Repoint only the staging alias after verifying that artifact; do not clear local
drafts/journals. No backend rollback is required. Older code ignores the new
optional category metadata, so retain its local record before editing with an
older build if those labels need to be preserved.

[Machine-readable release evidence](SETUP_CONTROL_POLISH_2026-10-05.json)
