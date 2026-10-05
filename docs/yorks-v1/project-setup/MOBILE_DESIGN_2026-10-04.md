# Project setup mobile design — 4 October 2026

## Scope and authority

The product owner supplied six phone compositions for Project details, Parties & access, Buildings with an editor, Attachments, Review & create and Project created. This document measures those images and maps their presentation to the retained [setup specification](specification/Yorks_Project_Creation_Editing_SRS_v1.0.md), [interaction addendum](implementation/UI_Interaction_Addendum.md), [field register](registers/Fields.csv) and [keyboard register](registers/Keyboard_Interactions.csv). The [desktop comparison](DESKTOP_DESIGN_2026-10-04.md) remains the wide-layout evidence. The [mobile implementation guide](../MOBILE_UI_IMPLEMENTATION_GUIDE.md) supplies the inherited touch, responsive, safe-area and authorization safeguards.

The images do not introduce new required fields, identities, access grants, upload formats, upload limits or server-success states. `YORKS_V1_PROJECT_SETUP` remains default off. This is a presentation implementation and verification plan, not production rollout or acceptance of the source's complete manual scenario catalogue.

## Reference identity

All originals are **863 × 1822 raster pixels** and reside in `/var/folders/9c/2xw1g1b90gdg90gsr_n9c9lr0000gp/T/`. All six were opened before measurement.

| Screen | Original file | SHA-256 |
| --- | --- | --- |
| Details | `codex-clipboard-17dda465-32ec-4b1b-b422-eaf5693b847f.png` | `4c2d7ffe26165a6b124046387ae7aae3228a019821f9189b151f8a967f38c3ad` |
| Parties | `codex-clipboard-fc928d9b-d6c0-455f-aef1-bcc52d1c943e.png` | `8e1049b9c2bd2a2442accc2fe2cde1c88fdd89a39e470b4b67c23176d5fe37e2` |
| Buildings | `codex-clipboard-5ea6a99c-a71d-4f3c-ad3b-6082d1e4eedc.png` | `1e8184d67a6367c8d56806eec73429c043a64dccfffdd015fbc5866886a91d3a` |
| Attachments | `codex-clipboard-8d99496b-e4b4-4cfd-ad37-b9a8eadf634c.png` | `03544bd05990ad8536e4af42d86c021e48b66ad007adb6f051f00ecd02c20d87` |
| Review | `codex-clipboard-ce02293d-9b5e-4c24-889a-a7b2ab2f5ba2.png` | `27704b232b06e6179736ff64e183aff5f95884a26d29af482eb1e7a3fd7d0a87` |
| Success | `codex-clipboard-8ffb0f6d-07f4-4d90-be26-dbe36b5dacb8.png` | `2a5a4d9c141d9f61ad3953d8addf7295a4428d298d76f1ba67cd3fd368ba960f` |

## Raster coordinates and app viewport

The artwork contains an OS time/signal/battery row and a bottom home indicator. Neither belongs to the Flutter feature. Do not render a sample 9:41 clock, fabricated signal/battery icons, a home pill or an extra bottom navigation inside project setup. Real safe areas and keyboard insets come from the host.

For measurement only, a **2 raster pixels per logical pixel** interpretation gives a width of 431.5. This is inferred from the artwork, not device metadata. Approximate exclusion bands are raw y0–64 for OS status and the last 32 pixels for the home indicator. Normalized app coordinates use `x = rawX / 2` and `y = (rawY - 64) / 2`; the resulting app-only height is 863. The shell owner confirmed **431 × 863, DPR1** for the six candidate captures. Additional checks use the prescribed 390×844 and 360×800 phone sizes plus 768×1024 and 1024×768 tablet sizes. A 431×844 capture would be 19 logical pixels shorter and must be described as a reflow/crop, not an exact extraction of the source.

Straight card edges are approximate to 1–2 raw pixels. Fonts and gradients cannot be recovered exactly from a raster. Some source controls normalize below 44 logical pixels; accessible target sizes and legibility take precedence over shrinking controls to those pixels. Long values, errors, text scaling and keyboard entry must increase content height naturally and remain scrollable.

## Shared composition

| Surface | Measured source bounds, raw pixels | Implementation binding |
| --- | --- | --- |
| Navy identity chrome | App content roughly y64 to131–143 depending on image | Reuse actual company, drawer/search/notification/avatar actions. At least 44×44 hit areas; no OS chrome. |
| Body | White/pale surface; outer cards x36–829, width 793 | Approximately 18 logical leading/trailing inset at 431 width; directional spacing for RTL. |
| Return link | x40–160 around y168–195 | Guarded Return to Projects; preserve pending local input and explicit leave decision. |
| Heading | x36 around y204–252; Save button x671–829, width158 | Readable title, acknowledged local-save state, full Save draft label. Wrap/stack when width or text scale requires it. |
| Project context | x36, y250–296 except initial Details | Wrap real reference/name. Do not replace form input with a sample reference/name. |
| Five-stage strip | Circle centers x81/257/432/608/783; diameter46–50; line center y321–357 | Manual stage activation, stable stage keys/focus. Numbers/current/completed states remain five; success is a result surface. At 360/200% use a compact accessible selector rather than compressed text. |
| Card shape | Radius ~12–15 raw pixels; subtle pale-blue border | Feature-scoped mobile tokens derived from existing AppColors/AppSpacing/AppTypography, without changing desktop tokens. |
| Sticky actions | Top ~y1680 Details/Buildings/Files, y1724 Parties/Review; bottom before home band | Back/Continue or reviewed final action; full labels and at least 44×44 targets. Stack at narrow/enlarged text instead of ellipsis. Add body bottom/keyboard inset so final rows remain reachable. |

Sample region medians in Details are navy `(22,56,94)`, active blue `(1,105,253)`, primary button `(15,71,132)` and information fill `(239,246,253)`. They vary spatially because the artwork is textured/graded. Bind semantic navy/blue/help/success colors to scoped tokens; do not treat those medians as recovered global theme constants. Retain bundled fonts and record any glyph-metric difference.

### Implemented token bindings

The new `YorksProjectSetupMobileTheme` keeps `AppColors.navy`, blue `#006BFF`, muted `#5D749B`, border `#DCE5EF`, input border `#CAD6E5`, help `#EEF5FD`, selected `#E7F0FC` and success `#008F70` scoped to this feature. It derives bundled-font styles from `AppTypography`: body 14, external field labels 12.5, secondary 11.5 and card title 18. It requires 44px input icon constraints and button targets. Related field columns appear only at viewport ≥400, at least 340px available inner width and text scale ≤1.1; 360px and enlarged text use a single column. Existing wide desktop composition/tokens remain separate.

## Stage measurements and behavior

### 1. Project details

Source information block x36/y440..630; detail card x36/y654..1669. Inner fields x61..804; reference input y816..871, name963..1019, site1207..1262, dates1357..1416, notes1486..1590. Related client/contract and date fields use two columns in the artwork, each about 177 logical pixels wide. Phone layouts must instead use one column where realistic labels, calendar/clear controls or errors cannot fit.

Only reference/name are authoritative required project details. Site/start remain optional; the source's four-item required callout and red stars must not become validation rules. Keep explicit Today, typed date/raw invalid input, optional contacts and hidden contact preservation. Do not copy the image's 1,000-character notes counter into a new limit; use the supported model/service constraint and preserve paragraphs. Local saved status requires acknowledged storage, not a scheduled checkpoint.

### 2. Parties & access

Source party card x37/y432..1027; nested parties y559..1018; team card y1044..1724. Party inputs are about 50 raw pixels tall, chips 36, team search y1134..1185, available/selected columns split near x491. This density is not a 44px touch layout after 2× normalization. Use stacked accessible party controls, selected groups and bounded authorized candidate results on phone; two panes may remain only at a tablet width with enough text space.

Preserve typed but unapplied party input, stable local party identities, explicit Add/remove/undo and opaque member IDs. The source places example chips beneath inconsistent labels; real party kinds must be preserved. Directory output remains safe and eligible, without invented email rows, role labels, external portal access or free-form privilege assignment. The creator's protected membership is automatic and cannot be removed as a cosmetic choice. Filtering must not clear earlier selections or change identity-based actions.

### 3. Buildings

Source list x36/y454..952, search/add y553..618, table header637..694, body rows~59–65 raw pixels. Editor x36/y969..1452, fields name/code1067..1119 and levels/address1202..1253, FRP~y1330, Apply/Cancel1372..1433. Common explanation card x36/y1468..1670. The source lists Common in the physical table and shows a menu beside it; implementation keeps Common separately locked and excluded from physical counts, with no edit/remove menu.

At 431px use the compact physical-building columns shown in the artwork; narrow and enlarged-text layouts reflow to readable physical-building cards. Keep a focused Add/Edit form in both layouts. Apply/Cancel are explicit and preserve `localRowId`, `sourceScopeId`, retained unknown fields, addresses and false FRP. Search/filter actions resolve the original stable row identity. Required name validation stays in the editor; code/levels/address remain optional. No row is applied just because the user leaves a step. An unapplied editor gives a visible reason for disabled Continue and remains recoverable. Common is created by the trusted project command, not a local physical row.

### 4. Attachments

Source main card x37/y476..1624, drop target x60/y637..1015, toolbar y1049..1105 and four-file table y1122..1589. The dense six-column file table cannot become narrow phone form text. Use file cards exposing name, type/size, operational classification, truthful status and a 44px contextual menu; search/filter actions resolve stable file IDs.

Retain the controlled service's supported PDF/PNG/JPG/XLSX/DOCX formats and 20MiB per-file limit. The source's DWG/ZIP/100MB claims are unsupported. Metadata does not prove upload, uploader or timestamp. Restored metadata shows Reselect until original bytes are provided; recovery keeps immutable hashes/keys and rejects changed content. Unreviewed classification must not produce green Ready. Optional attachments never require inventing upload progress or server success.

### 5. Review & create

Source ready banner x37/y428..544; details card559..857, parties870..1092, buildings1104..1321, attachments1333..1522, completion checklist1534..1677 and final actions1730..1790. Summary rows must wrap full values instead of hiding fields to fit these heights. Precise Section Edit controls remain touch accessible and return to the section with proposal/raw-input/focus state intact.

Show every real entered party, contact/detail field, physical scope and file state. No canonical lead/project-manager field or external-access count is invented from the artwork. Ready derives validation, applied editors, eligible prerequisites and classification; it is not weighted completeness. Create remains a single explicit reviewed command. Edit uses real before/after/clear/version conflict semantics and unchanged Save remains a no-op. An uncertain known command renders the original frozen intent and recovery actions, not a mutable replacement request.

### 6. Project created

Source all-complete green strip y278..377; banner x37/y404..544; summary565..938; next-step explanation955..1331; actions1348..1790. Use the existing confirmed-operation model: core Draft/Active state, activation attention, files pending and local cleanup each remain truthful. The result remains until an explicit permitted action; closing a banner or navigating cannot issue another command or erase its journal.

Summary uses confirmed project/scope/member/document facts, with no invented lead engineer or inaccessible Accounts values. Every Open/BOQ/team/documents/Edit action requires actual protected capabilities and structural eligibility. Empty/recovery states remain visible and scrollable. Exact final file reselect/retry/removal uses the original manifest; completion is not optimistic success.

## Preservation and verification matrix

| Boundary | Required check |
| --- | --- |
| Phone/tablet parity | Same providers/controllers/repositories and permitted fields; no mobile business-model fork. Existing desktop branch remains unchanged. |
| Stable row/file/member identities | Filtered Apply/Cancel, same-name file menus and candidate filtering mutate the original identity, never the displayed index. |
| Device draft acknowledgement | Debounced raw text, dates, unapplied editor, false FRP, contacts, section state and stable IDs survive restore; storage failures remain visible. |
| Ownership/session | Owner/backend/project changes fence asynchronous UI work; takeover rechecks atomic ownership and restores the winning proposal. |
| Critical operation | Exact durable intent before dispatch; no auto retry/navigation; known result keeps original command keys and recovery outcomes. |
| Safe areas/keyboard | Actual host insets; focused final input and sticky actions remain reachable. No duplicate workspace bottom navigation or fake OS bars. |
| Touch | Relevant visible buttons, icon controls, menus, clear/calendar actions and selectable targets have nonoverlapping 44×44 minimum hit areas. |
| Keyboard/IME | Enter in fields does not commit; Ctrl/Cmd+S saves local recovery; caret/composition and focus survive checkpoints/reflow; precise validation focus. |
| Enlarged text/RTL | 360px Arabic at 200% and 320px reflow, full action labels, directional layout, no rendering exception or obscured editor. |
| Motion | Short/nonblocking, reduced-motion compatible; no motion-derived state changes. |

The new [mobile interaction suite](../../../test/yorks_v1_project_setup_mobile_interaction_test.dart) has 24 cases: six canonical feature shells, five 360px stage checks, four 768/1024 tablet checks, two Arabic 360px/200% checks, two simulated keyboard/safe-area cases, transient-viewport recovery, stable-ID Building Apply and Cancel, classification/readiness, and same-name filtered file removal. Each canonical viewport capture has a companion bottom capture. The test walks intermediate scroll viewports and checks rendering exceptions and actual visible control bounds before capturing the end. Actual `TextField`, `DropdownButton`, `Checkbox`, `ButtonStyleButton` and `IconButton` bounds are measured; outer field labels and wrappers do not establish a passing input target. Full primary action text is checked for clipping. These checks cover measured rendered bounds, not a complete semantic overlap audit.

The separate [existing setup suite](../../../test/yorks_v1_project_create_flow_test.dart) adds real 390px create/completion/recovery/retirement/edit-route cases. The result golden uses a synthetic confirmed receipt without network requests; it does not establish live server activation or document upload. Candidate goldens are implementation artifacts, not automatic comparison against the supplied rasters or stakeholder approval. Browser platform-view dropzones, real phone keyboard/file picker/reader behavior, production personas, live transactions and the full source acceptance catalogue require separate evidence; unit viewport tests cannot silently pass them. The inherited 320px reflow and full keyboard/IME/motion/manual catalogue remain separate acceptance checks unless recorded elsewhere.

## Candidate captures

All candidate images below are app-only **431 × 863**, DPR 1, with bundled NexusSans/NotoSansArabic and MaterialIcons. They omit OS chrome. Each first view and bottom view comes from the same real feature-shell scroll controller. Building's capture starts at scroll offset zero after the real editor is opened and unfocused; that fixture reset does not change production focus behavior.

| Stage | Initial viewport | Lower viewport |
| --- | --- | --- |
| Details | [Top](../../../test/goldens/project_setup_mobile/projectDetails_431x863.png) | [Bottom](../../../test/goldens/project_setup_mobile/projectDetails_bottom_431x863.png) |
| Parties & access | [Top](../../../test/goldens/project_setup_mobile/partiesAndAccess_431x863.png) | [Bottom](../../../test/goldens/project_setup_mobile/partiesAndAccess_bottom_431x863.png) |
| Buildings | [Top](../../../test/goldens/project_setup_mobile/buildings_431x863.png) | [Bottom](../../../test/goldens/project_setup_mobile/buildings_bottom_431x863.png) |
| Attachments | [Top](../../../test/goldens/project_setup_mobile/attachments_431x863.png) | [Bottom](../../../test/goldens/project_setup_mobile/attachments_bottom_431x863.png) |
| Review & create | [Top](../../../test/goldens/project_setup_mobile/reviewAndCreate_431x863.png) | [Bottom](../../../test/goldens/project_setup_mobile/reviewAndCreate_bottom_431x863.png) |
| Confirmed result | [Top](../../../test/goldens/project_setup_mobile/confirmed_result_431x863.png) | [Bottom](../../../test/goldens/project_setup_mobile/confirmed_result_bottom_431x863.png) |

### Observed presentation differences

The source uses compressed controls and dense tables. The candidate keeps readable body typography and 44px controls, which increases form/card heights and requires scrolling. Details and Building fields retain paired columns only where they fit; 360px and enlarged text stack them. File rows are cards; physical buildings retain compact columns at 431px and reflow to cards at narrow widths or enlarged text. Common remains a separate locked card. The parties view keeps protected creator membership and safe directory rows. Review and completion wrap full facts and expose real local recovery/file states, which the illustrative source omits. These are deliberate accessibility and policy differences, with no approval claimed for a literal pixel match.

All 12 final images were independently opened at original resolution. Details client/contract and start/end input tops align, clear/calendar controls remain visible, and saved status occupies one line in the normal 431px header. Buildings starts at offset zero with an acknowledged draft, while its lower view shows Apply/Cancel, the 48px padded FRP checkbox and the separate locked Common card. Parties exposes protected creator membership, selected engineering roles and safe candidates. Attachments exposes all four supported metadata/reselect cards and classification controls. Review wraps the real facts and preserves reselect status. Completion exposes the full permitted actions and omits obsolete Save draft.

The final raster measurements below use app pixels. Border starts can differ by one antialiased pixel; rounded corners extend approximately seven pixels past a straight-edge segment.

| Candidate landmark | Final measured geometry | Relation to supplied artwork |
| --- | --- | --- |
| Identity chrome | y0–48, full width; actionable icons at least 44px | Source app chrome normalizes to approximately 34–40px; target controls preserve 44px. |
| Outer card edges | x18–413, width 395 | Source x36–829 at inferred DPR2 gives 18–414.5; logical viewport rounds 431.5 to 431. |
| Details callout / details card | y256–362 / top y374 | Source normalizes to approximately y188–283 / top y295; readable text, 44px breadcrumb/save controls and required-content callout increase height. |
| Parties / Buildings / Attachments first card | top y278 | Source approximately y184 / y195 / y206; the accessible shared header/stage selector increases preceding height. |
| Review ready / details card | y278–356 / top y366 | Source approximately y182–240 / top y247.5; full wrapped data continues below. |
| Confirmed banner / summary | approximately y255–344 / y358–654 | Source approximately y170–240 / y250.5–437; confirmed facts and 44px Edit control remain readable. |
| Lower content | Reached through the actual shell scroll controller; sticky footer stays outside the scrolled form | Taller forms are intentional; first and bottom views plus intermediate checkpoints provide evidence of reachability. |

Visible outline height alone does not establish the input target: some input outlines appear about 38px tall, while the actual `TextField` rendered control region measures at least 44px. The automated assertions measure that actual control, not its label or enclosing card.

## Current status

The visual-source run passed **23/23** with refreshed goldens, and a second normal run passed **23/23** against those baselines. After the browser transient-viewport correction, the expanded normal run passes **24/24**, with all 12 golden baselines unchanged:

```bash
flutter test test/yorks_v1_project_setup_mobile_interaction_test.dart --update-goldens
flutter test test/yorks_v1_project_setup_mobile_interaction_test.dart
```

Logs are `/tmp/yorks-setup-mobile-final-update.log`, `/tmp/yorks-setup-mobile-final-verify.log` and `/tmp/yorks-setup-mobile-transient-viewport.log`. The latest 24-case run uses normal golden comparison without `--update-goldens`. All 12 files are 431 × 863. The six original dimensions and SHA-256 values were rechecked, and every local document/artifact link resolves.

Earlier runs exposed two concrete defects: the FRP tile needed a nearest Material ancestor, and its independently clickable checkbox was 40px because of inherited compact density. The mobile source now retains the Material ancestor and explicitly uses standard visual density plus a padded checkbox target. The final assertions include the actual text fields, dropdowns, checkboxes and buttons at initial, intermediate and lower capture viewports. Building's fixture also advances its existing 250ms scroll checkpoint and awaits the controller acknowledgement before capture; the saved state is not fabricated.

### Browser transient-viewport correction

Parent's actual browser navigation later exposed a temporary **1 × 1** surface and a 720px MobileShell column overflow. The normal 431px capture did not reproduce that navigation state. The [mobile shell](../../../lib/features/projects/presentation/screens/yorks_v1_project_setup_mobile_shell.dart) now defers only its chrome inside `Scaffold.body` while available width is below one 44px target or available height is below two targets (88px). The feature and shell controllers remain alive, and the same Scaffold stays registered with ScaffoldMessenger so outcome messages remain available during the temporary surface. The normal composition is restored when the real viewport arrives; normal geometry and visual baselines are unchanged.

The new `transient 1px viewport retains the same draft and unapplied editor` regression uses one `ProviderContainer`, one initial feature mount, and only viewport resizing for **1×1 → 431×863 → 1×1 → 431×863**. It asserts identical feature State at every checkpoint, the same draft ID, exact multiline/whitespace notes and address, stable local row/server scope identity, false FRP, persisted unapplied editor text, unchanged applied building, zero commands, no completion surface and no rendering exception. The 24-case normal run passes and preserves the 12 visual baselines. Actual browser re-verification after rebuilding that guarded source remains root-owned evidence; this widget regression does not convert the earlier browser failure into a claimed live pass.

This is scoped Flutter widget/render evidence. Root-owned full gates, actual browser viewports and build artifacts are recorded separately. No live browser success, physical-device acceptance, production change, complete source scenario pass or literal pixel-perfect match is claimed by this document.

The final full gates and actual browser follow-up are recorded in [mobile validation](MOBILE_VALIDATION_2026-10-04.md).
