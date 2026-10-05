# Project setup desktop design — 4 October 2026

## Scope and authority

The product owner requested convergence of six supplied desktop screens: Project details; Parties & access; Buildings with an open editor; Attachments; Review & create; and the confirmed Project created result. Their source canvas is **1536 × 1024**. This handoff measures the new references and defines the behavior the stage refactor must preserve. It does not approve new business fields, role disclosure, upload limits, production changes or a release flag.

The [setup specification](specification/Yorks_Project_Creation_Editing_SRS_v1.0.md), [interaction addendum](implementation/UI_Interaction_Addendum.md), [field register](registers/Fields.csv), [keyboard register](registers/Keyboard_Interactions.csv) and retained [R35 UI contract](../R35_UI_CONTRACT.md) govern behavior. The image stars, sample names, dates, progress and role values are visual examples only.

## Reference identity and measurement method

All six files reside in `/var/folders/9c/2xw1g1b90gdg90gsr_n9c9lr0000gp/T/`. The full basename and SHA-256 below identify the reviewed originals independently from the earlier five 1586-pixel references.

| Screen | Original file | SHA-256 |
| --- | --- | --- |
| Details | `codex-clipboard-2b62e9ec-53bb-44d9-b4db-3f39125028f1.png` | `c7758c6eedee39454b436930c2b8763af1cc59605c2cbd81de9225d706d90fc4` |
| Parties | `codex-clipboard-a3ebb834-01ab-44ed-b6c1-ab94db84b7f6.png` | `8c92af35e000ae379e8b4c1d26314cd090bc738c2ef9e88d215f49c0cc250936` |
| Buildings | `codex-clipboard-024d29b5-50b6-49a2-b909-164c4c3a0808.png` | `a359553da78c3b226e4221cd1ea4c4036794159b3581c425e5a181a6fb247912` |
| Files | `codex-clipboard-be5f5384-f12c-43d2-b847-b26aa84e7ed2.png` | `71969a2e3bc202b24300c29a5ae4acebe2a4269b59919597aa731218e90df53e` |
| Review | `codex-clipboard-d5d367e6-9905-4a75-91de-09b15d095a82.png` | `754d0cd4d611ca750c02cc67e572a8cb54a2888f07a5bd8101a875570cf3ec6c` |
| Success | `codex-clipboard-9575188e-461d-49c9-b873-bcc63997508d.png` | `84e5850d19125c7dce3cac8942331128467f6911b470d697ee33c452b75c747e` |

Bounds are measured in source pixels with a top-left origin. Straight-line coordinates are reliable to approximately one pixel; rounded corners/antialiased text can shift the visible edge by one or two pixels. Font sizes/weights are inferred from raster geometry, not recovered font metadata. The references contain slight texture and color variation, so regional medians and ranges are reported instead of pretending every background is one exact flat color.

No candidate/reference pixel match is claimed by this document. The final comparison must use actual rendered output at the same viewport/device pixel ratio and the same supported fixture data.

## Shared desktop shell geometry

| Surface | Reference bounds / measurement | Implementation binding |
| --- | --- | --- |
| Canvas | 1536 × 1024; white workspace | Setup-only desktop surface; preserve the current compact/mobile surface. |
| Navy app bar | x0, y0, width 1536, height 56 | Setup-scoped chrome; shared `AppSpacing.topBarHeight` is 64 and must not be globally changed. |
| Menu / identity | menu left 24, center y28; company text left 88, about 20px | Existing navigation capability and company identity. |
| Search | x989, y10, width 371, height 36 | Existing authorized search/jump affordance; no new unprotected search. |
| Bell / avatar | bell center 1420,28; avatar center 1488,28, diameter 36 | Retain real notification/avatar actions and identity. |
| Setup rail | x0..231, y56 to footer; width 232 | Setup-only rail; shared `AppSpacing.sidebarWidth` is 260 and remains unchanged. |
| Rail section label | x26, y87, about 12px bold | Compact eyebrow derived from `AppTypography`; no extra permanent office sidebar inside setup. |
| Rail rows | about 50px apart; text left 69 with numbered circles in the initial Details reference; left 29 in the other five references; selected accent x0..7 | Five stages, focus distinct from selection; completed check at x198. Hide the visual number in later reference states without changing stage identity or keyboard behavior. |
| Rail return link | x30, y900–928 according to stage footer | Route leave guard; no independent unguarded navigation callback. |
| Page heading inset | breadcrumb x262, y78; title x262, y101; context/help x262, y145 | Main starts232; leading inset30. |
| Save state and action | saved text near1254, y123; button x1400, y102, width 114, height 40 | Acknowledged device status only; do not show saved from a scheduled write. |
| Header bottom | y180 Details;182 Parties/Files;183 Buildings/Success;175 Review | References differ by stage. Use stage-specific body positioning when reproducing these canvases. |
| Footer | full viewport width, thin top border; Details/Files y938, Parties959, Buildings932, Review950 | Height86/65/92/74 respectively. Success has no wizard footer. Preserve reachable actions at smaller heights rather than fixing unusable height. |
| Footer actions | Back x26, width~107; primary right 1510; usual height 44–46 | Minimum touch/focus target44; native keyboard order and RTL leading/trailing alignment. |

The sixth screen is a result surface, not a sixth numbered wizard step. Completed rail entries remain five.

## Stage measurements

### 1. Project details

| Element | Source bounds / alignment |
| --- | --- |
| Main form card | x257, y180, width 870, height 724, radius6–8, line1 |
| Form content | x280; section title y211; step text x470; help y249 |
| Two-column fields | leftx281/rightx708; width 398 each; gap29–30 |
| Reference / name | labely295; controls y316–354 (height 38) |
| Client / contract | labely409; controls y431–470 (height 39) |
| Site | labely507; full-width control x281,y529,width 825,height 38 |
| Dates | labely624; controls y648–688 (height 40), calendar leading/clear trailing |
| Notes | labely726; textarea x281,y747,width 825,height 84; helpery843; count right 1101 |
| Help card | x1147,y197,width 368,height 282; padding 23–24; icon34; heading16–18 |

Do not add required stars to optional site/start date merely to match the pixels. Preserve optional contacts via the existing disclosure and any current values; they are not deleted because absent from the reference. Count limits must reflect the actual configured schema instead of importing the image's `1,000` value.

### 2. Parties & access

| Element | Source bounds / alignment |
| --- | --- |
| Section heading | x262,y205; step textx469; helpy239 |
| Project parties card | x261,y270,width 1253,height 254; padding 14–15 |
| Party grid | leftx276/rightx899, columnwidth 600; gutter23 |
| Consultant / contractor controls | y365,height 33; Add rowsy438,height 34; chipsy480,height 27 |
| Team card | x261,y537,width 1253,height 415; titlex275,y552 |
| Candidate pane | x275,y601,width 580,height 335; search x289,y613,width 428; role filterx730,width 112 |
| Candidate table | header y653,height 31; visible rowheight 44; contained vertical scroll |
| Selected pane | x867,y602,width 631,height 338; grouped PE/Site sections with rowheight 44 |
| Access note | x880,y878,width 605,height 57 |

Use real authorized safe directory entries and exact permitted roles. Keep selected IDs stable while filtering; a row label or avatar does not confer privilege. Preserve the Site Engineer one-initial-PE exception and separate edit-mode Manage access command. The screenshot emails, Quantity Surveyor/Design Engineer rows and external users are not permission to expose extra identities or invite external parties.

### 3. Buildings with a focused edit pane

| Element | Source bounds / alignment |
| --- | --- |
| List region | x259,y279,width 794,height 637 |
| Split boundary | x1072, y183..932; editor pane width 464 |
| Toolbar | y292; countx278; searchx665,width 210,height 37; Addx891,width 149,height 37 |
| Table | x260..1053; header y340,height 43; rows y383/433/483/534,height 50–51 |
| Columns | Code119; building name287; levels203; FRP92; row action90 |
| Selected row | blue tint; accent x260..263; code/link and kebab remain keyboard reachable |
| Common note | separatorx278,y610,width 754; iconx285; titlex325,y630; not-editable right 1026 |
| Editor content | x1099,width 415; titley211; code/contexty239 |
| Building name | labely286; inputy306,height 39; visible focus ring2 |
| Code / levels | inputs y394,height 38 andy507,height 37; helpers immediately below |
| Delivery address | x1099,y618,width 415,height 83 |
| FRP | checkboxx1103,y727,size21; labelx1141 |
| Apply area | divider y796; buttons x1099 and1343,y832,height 44 |

Search/filter must select by stable local/source scope identity, not a display index. Apply mutates only the local draft row; Cancel does not apply its pending values. Keep raw editor text/FRP recoverable. Name is required; code/levels/address are optional per the verified contract. Common is shown separately and never counted as a physical building. Persisted-scope retirement remains blocked; new-row remove/undo/reorder keeps IDs and hidden flags.

### 4. Attachments

| Element | Source bounds / alignment |
| --- | --- |
| Section heading/help | x262,y209/y244 |
| Main card | x260,y278,width 1254,height 642 |
| Drop target | x276,y295,width 1223,height 233; fine dashed line; pale fill |
| Drop contents | icon centeredx871,y343; titley383; browse liney409; Addx815,y440,width 114,height 41; policy texty494 |
| List toolbar | countx276,y563; searchx1066,y551,width 242; filterx1319,width 180,height 37 |
| File table | x276,y599,width 1223,height 286; header42; rows57–59 |
| Columns | filename338; category159; actor194; date200; status247; action84 |

The configured current picker limit is 20 MiB; the image's 100 MB is not policy. The current picker accepts PDF, XLSX, DOCX, JPEG and PNG; the image's DWG/ZIP support is not enabled by this design. Do not label pre-create metadata Uploaded or invent uploader/timestamp/progress. Keep filename, actual hash/size/MIME/local ID and classification review. Ready means authorized finalization; restored missing bytes means Reselect. Same-name different-content files remain distinct. Removing local/pending work never deletes a ready controlled document; unknown attempted outcomes require original-intent reconciliation.

### 5. Review & create

| Element | Source bounds / alignment |
| --- | --- |
| Page title | `Review & create`, x262,y103; no redundant second stage hero |
| Main / aside split | leftx261,width 921; aside borderx1197,width 339 |
| Ready strip | x261,y187,width 921,height 65; checkcenter290,215; textx320 |
| Detail card | x261,y265,width 921,height 181; headingx278; edit right 1162 |
| Party/access card | x261,y458,width 921,height 164 |
| Buildings card | x261,y634,width 921,height 162; compact table header28/rows22 |
| Attachment card | x261,y808,width 921,height 142; compact table header25/rows23 |
| Aside | titlex1223,y202; checklist centers1236,306/371/438/505; textx1269 |
| Primary | x1374,y965,width 136,height 43 |

Show actual project fields and real team/scope/file states. The image's project type, description, lead/project manager and external-access summaries are not new canonical fields. Do not show “ready” while unapplied editors, invalid fields or activation/file prerequisites need attention. A no-PE create result is a real Draft, not automatically Active. Uncertain/known original commands retain the frozen original review and their recovery controls. Edit mode keeps before/after/clear and three-way version conflict review; unchanged Save stays a no-op.

### 6. Confirmed result

| Element | Source bounds / alignment |
| --- | --- |
| Success strip | x261,y199,width 1249,height 102; radius6; green iconcenter306,242,diameter 51 |
| Banner text | titlex355,y225,about 28px; bodyy263,about 15px; dismiss center 1478,227 |
| Summary card | x261,y314,width 797,height 332; contentx284; Editx902,y334,width 136,height 42 |
| Summary rows | divider y395; seven rows about 33px; value columnx546 |
| What next card | x261,y659,width 797,height 330; contentx284; numbered circlesdiameter38 |
| Action card | x1072,y315,width 438,height 674; padding 20 |
| Action buttons | x1093,width 396;height 49; y404/463/523/583; Returny686 |
| Information box | x1093,y775,width 396,height 93 |

Render this only after server-confirmed core success. Preserve known Draft/activation pending/files pending distinctions and any durable operation manifest. “Workspace ready” and Accounts/access actions must reflect actual lifecycle/capabilities; parties do not become invited users. No canonical lead-engineer field is invented. Open, BOQ, team and document actions navigate to existing permitted project contexts. A banner close/navigation failure cannot issue a fresh create or erase the receipt/journal.

## Measured palette and implemented scoped tokens

The new [desktop shell](../../../lib/features/projects/presentation/screens/yorks_v1_project_setup_desktop_shell.dart) owns the 56px bar/232px rail geometry and its private chrome colors. Stage controls use [YorksProjectSetupDesktopTheme](../../../lib/features/projects/presentation/screens/yorks_v1_project_setup_desktop_theme.dart), derived from the shared `AppTypography` and `AppColors`. These bindings record actual source values, not a completed visual pass. Screenshot-specific overrides belong only to the new setup desktop surface; changing global values would alter unrelated production screens.

| Role | Measured raster target | Current real token base / required scope |
| --- | --- | --- |
| Navbar | regional medians `#10335B`–`#193758`, center approximately `#153457` | Shell `_navy = #153457`. |
| Heading/body ink | dark glyph medians about `#08244D` (`#052048`–`#0C284E`) | Shell `_ink = #08244D`; stage `navy = AppColors.navy = #0D2F57`. |
| Muted helper text | about `#697A9D` | Shell `_muted = #607AA5`; stage `muted = #5D749B`. Compare rendered glyphs, since texture affects the estimate. |
| Rail | about `#F2F6F9` | Shell `_rail = #F2F6F9`. |
| Work area | near white `#FDFEFE`/`#FEFEFE` | Shell `Scaffold.backgroundColor = Colors.white`. |
| Selected row | Buildings median `#E5EFFC` | Stage `selected = #E7F0FC`. |
| Help | Details median `#EEF5FD`; Files drop `#F7FBFE` | Stage `help = #EEF5FD`; drop surface is separately scoped. |
| Success | Review strip `#E4F3EE`; result strip `#F1F9F6` | Stage `success = #008F70`; success background belongs to its own surface. |
| Control/card border | pale blue-gray; Details sampled `#E4E9F1` | Stage `inputBorder = #CAD6E5`, `border = #DCE5EF`; shell `_line = #DBE5EF`. Actual rendered contrast remains to be reviewed. |
| Table header | near-white gray | Stage `tableHeader = #F4F7FA`. |
| Action blue | saturated blue active rail/focus/Add; primary darker navy | Shell `_blue = #0065FF`; stage `blue = #006BFF`; shell primary `#084477`; stage `navyButton` uses `#0D2F57`. |

| Typography | Raster estimate | Real base |
| --- | --- | --- |
| Page title | 32px,700, about 38px line | Shell `_text(...)` derives from `AppTypography.bodyMedium`; shell owns its page-heading size. |
| Stage heading | 26–28px,700, about 34px line | `YorksProjectSetupDesktopTheme.title`:26px,700,height1.25. |
| Card heading | 20–22px,700 | `YorksProjectSetupDesktopTheme.section`:20px,700,height1.35. |
| Main descriptive sentence | 15–16px,400 | Stage `body`:14px,400,height1.35; descriptive overrides are scoped in the stage. |
| Labels and input text | 14px,400/600, about 20px line | Stage `label`:14px,500; `body`:14px,400. |
| Table bodies / helpers | 12–14px; review tables tighter | Stage `small`:12.5px,400,height1.35; `body`:14px. |
| Button text | 14px,600/700 | Stage `outlineButton`/`blueButton` use `label.copyWith(fontWeight:w600)`; shell uses `_text(14,w600)`. |

The real bundled family is `NexusSans` (Noto Sans) with `NotoSansArabic` fallback. Raster references do not encode a font family. Use deterministic bundled fonts and inspect actual word widths/baselines; do not assert a Segoe/Roboto identity from appearance. Existing `AppSpacing.controlHeight` 38 and `minTapTarget` 44 align with compact visible controls plus adequate interaction targets. The scoped input uses 14px horizontal/10px vertical padding, 5px radius and a 1.5px blue focused border; scoped outline/blue buttons have 38/40px minimum visual height and 5px radius. Preserve compact visual controls without clipping validation or focus. `YorksProjectSetupDesktopTheme.isDesktop` requires width ≥1100 and text scale ≤1.1; larger text deliberately falls back to the compact layout because the fixed desktop header cannot contain its enlarged text. Reference card radii 6–8 differ from global 9/14; local shapes remain scoped.

## Interaction, responsive and recovery preservation

| Boundary | Required invariant | Existing evidence to retain |
| --- | --- | --- |
| Desktop/compact | Desktop registers/split editor; compact cards/focused editor. At360/390px do not shrink desktop columns. Maintain44px actions, software-keyboard inset, translated long labels/RTL and 200%text fallback. | Existing [create-flow tests](../../../test/yorks_v1_project_create_flow_test.dart) and [acceptance map](CANDIDATE_ACCEPTANCE.md). |
| Rail | Arrow/Home/End move focus without changing stage; Enter/Space activates. Native Ctrl+Tab/OS keys remain native; no active input caret interception. | Rail focus test; keyboard register. |
| Inputs | Stable controllers/focus nodes/IME composition and caret. Plain Enter does not Create/Update. Ctrl/Cmd+S acknowledges local save only. | Existing text semantics, typed-date, navigation and throwing-analytics tests. |
| Stage changes | Preserve pending parties/building/date text, stable row ID and visited stages; per-section scroll/focused field survive return. Safe backtracking does not demand unrelated validation. | Raw editor/section context and stage navigation tests. |
| Building edits | Filtered selection/callbacks target stable IDs; explicit Apply/Cancel; FRPfalse overrides historicaltrue; hidden metadata/sourceScopeId survive rename/reorder/undo. | [Draft tests](../../../test/yorks_v1_project_setup_draft_test.dart), reorder/undo tests; [desktop interaction regressions](../../../test/yorks_v1_project_setup_desktop_interaction_test.dart). |
| Team | Safe directory values/exact roles only; selected IDs survive filter/similar names; Site one-PE exception and independent Manage access. | Safe-directory/stale-member/role tests. |
| Files | Real selected versus missing/uploading/unknown/ready; stable hash/key/classification. No fake progress or selected→Uploaded state. | [Recovery tests](../../../test/yorks_v1_project_setup_recovery_test.dart), classification/reselection tests. |
| Persistence | Single owned acknowledged writer, coalescing, backend+owner+mode+project isolation, quarantine and deliberate adoption; legacy fallback unchanged. | Draft tests and actual [Web Locks browser tests](../../../test/yorks_v1_project_setup_browser_storage_test.dart). |
| Ownership/session | Read-only initializing/foreign/recovery; resume verifies writer epoch; all callbacks fenced to original owner/project; takeover reloads winning raw state. | Owner-switch/in-flight/resume regressions. |
| Commit/recovery | Durable exact key/hash/payload before request; frozen original while unknown; max-three explicit jittered retries; confirmed receipt repair before follow-up. | Recovery tests; no widget Supabase/critical outbox. |
| Leave/result | Keep working or acknowledged local draft leave; no guaranteed forced-tab-close async completion. Known success/tombstone/files survive cleanup/navigation failure. | Navigation guard and phase retirement tests. |
| Capability | Optional/required rules, lifecycle, global engineering/Accounts boundaries and deferred retirement/import/cloud policy remain server authoritative. | Retained domain/direct DB tests; feature default off until accepted. |

## Visual verification procedure

1. Render all six canonical states at 1536×1024, DPR1, bundled fonts, English and the same permitted fixture lengths/row counts. Retain the full shell and footer, not only cropped cards.
2. Compare straight edges, insets, split widths, row/control heights, section baselines and icon centers to the bounds above. Report the measured delta; do not hide a large spacing error behind text/content differences.
3. Separate policy-required copy/state differences from geometric mismatches. Safe directory labels,20MiB policy, optional dates/site and truthful selected-file states are intentional contract differences.
4. Compare muted text/heading/primary/rail/success regions using sampled pixel medians and rendered glyph bounds. Slight raster texture and font antialiasing are not proof of an implementation color token; structural deltas remain actionable.
5. Recheck empty, long-name, invalid, loading, ownership, uncertain-command, files-pending and edit-conflict states. A populated mockup alone cannot prove usability or recovery.
6. Rerun existing desktop/compact keyboard/draft/session tests plus new filter/editor/menu identity tests. Native/process and unsupported-browser atomic limitations remain explicit.

### Candidate comparison status

All six candidate canvases have now been rendered and independently inspected at 1536×1024/DPR1 with bundled `NexusSans`, `NotoSansArabic` and Material Icons. The initial test fixture set constraints without changing device metrics, so its MediaQuery reported 800×600 and selected the compact branch; that fixture error was corrected with `tester.view.physicalSize` and `devicePixelRatio`, both reset at teardown. The current snapshots are full desktop surfaces.

| Candidate artifact | Independent comparison after the final density repair |
| --- | --- |
| [Project details](../../../test/goldens/project_setup_desktop/projectDetails_1536x1024.png) | Main card x257/y180/bottom904 is within 1px of the reference. Site y529, dates y648 and notes y747 match despite retained contact disclosure and typed-date helpers. Numbered initial rail is present. Optional site/start and the two-item required checklist are intentional policy differences. |
| [Parties & access](../../../test/goldens/project_setup_desktop/partiesAndAccess_1536x1024.png) | First card y270/bottom524 and Team y537 match. Candidate and selected pane edges are within about 2px. The access note is fully visible; the original clipped note was fixed. Safe directory roles, no email rows, automatic creator copy and fewer authorized candidates are fixture/policy differences. |
| [Buildings](../../../test/goldens/project_setup_desktop/buildings_1536x1024.png) | Table top y279 matches; rows are 50px. Common separator y609 versus610 (-1px), split x1074 versus1072 (+2px). Name/code/levels/address top edges are within about 2px. Apply buttons now start y832, matching the reference after the 16px correction. The former 80px rows/+125px Common displacement were fixed. |
| [Attachments](../../../test/goldens/project_setup_desktop/attachments_1536x1024.png) | Main card x260/y278/bottom920 and table y599 match. The latest full-width dropzone spans the table width at approximately x276/y294, width1222/height233, with pale `#F7FBFE` fill and the scoped blue dashed border. It was independently reopened after the platform-width repair. Operational classification checkboxes, empty authoritative uploader/date cells, Reselect states and the 20MiB format policy are intentional differences. Shortened final rows reflect a permitted PDF fixture rather than the unsupported ZIP/progress example. |
| [Review & create](../../../test/goldens/project_setup_desktop/reviewAndCreate_1536x1024.png) | Details/Parties/Buildings/Attachments card tops are y264/457/633/807 versus265/458/634/808; their main summary density now matches. The first three heights are 181/164/162px. Short localized Type/Size headers remain one line; all three file rows and the card bottom y949 are visible above footer y950. The former clipped last row and byte-unit caption were fixed. |
| [Confirmed result](../../../test/goldens/project_setup_desktop/confirmed_result_1536x1024.png) | Banner/card straight edges are approximately 1px from the reference after refinement; seven truthful summary rows give the reference card height. Close callback is included with its center approximately1479,229 versus1478,227 (1px right/2px down), retaining a 44px hit target and RTL placement. Protected lifecycle text, no invented lead engineer and capability-filtered next actions remain deliberate differences. |

The current [desktop test suite](../../../test/yorks_v1_project_setup_desktop_interaction_test.dart) passed **17 cases** after these repairs (`/tmp/yorks-setup-desktop-ui-tests.log`). This proves stable-ID filtered editing, false FRP/unknown-field retention, Cancel isolation, filtered opaque team identity, same-name file removal, classification readiness, six snapshot generation/bounds, 140% and 200% text readability, protected Open eligibility, and the real confirmed/uncertain feature flows below. The Review golden uses three supported files to match the reference row count; the Attachments golden and behavior fixtures retain four. It does **not** make the images a pixel-perfect approval: goldens were generated from the candidate, not compared automatically against the supplied raster references. Glyph baselines are still approximately 3px different and weights somewhat heavier with the required bundled font.

After the final Review/Apply/close corrections, Root regenerated these images and ran the 17 desktop, 10 completion and 44 existing setup cases together: **71 passed** (`/tmp/yorks-setup-desktop-final-focused.log`). The three affected PNGs were independently reopened and the corrected geometry above was confirmed. The subsequent **17-case run passed** after Root's acknowledged-retirement invalidation fix (`/tmp/yorks-setup-desktop-remount-final.log`). Its confirmed-create case unmounts and remounts in the same provider container without manual invalidation: the historical retirement tombstone and journal remain, while the active form opens at Details with a new draft ID, blank reference/name, no stale completion and no second create or activation command.

A later routed-browser check found a footer defect missed by the earlier geometry review: a `Spacer` followed by a loose `Flexible` hint left unused space after the primary action on Buildings and Review. The table above records body/card geometry, not approval of those footer positions. Root replaced that pair with one `Expanded` containing an end-aligned hint. Both existing stage snapshot tests now explicitly require the appropriate hint and check that the primary action stays inside the footer with its right edge no more than 26px from the viewport edge. Both refreshed images were independently reopened: the visible hints precede actions ending at x1510, preserving the 26px viewport inset. The initial bounds run had 16 passes and one Attachments coordinate assertion failure described below. After the bounded border correction, Root's final run passed **all 17 cases**, including both footer assertions (`/tmp/yorks-setup-desktop-final-bounds-tests.log`), and refreshed all six snapshots. The earlier 17/71 results predate these corrections.

The routed browser also exposed a web-only Attachments difference absent from the nonweb widget snapshots: the dropzone's platform-view `Stack` provided loose width constraints, allowing its contents to shrink to approximately 307px while the file table remained 1222px wide. Root gave the desktop dropzone contents an explicit infinite width while retaining its 233px height, then applied the scoped pale fill and blue border. The Attachments snapshot case checks x276/y294 and width1222 within 2px, with exact height233. The first run measured the key's actual left edge at277: its render-object bounds include a 1px panel-border inset from the visible target edge. The bounded 2px tolerance also permits the two borders' width reduction while still rejecting intrinsic shrinkage. This assertion passed in the final 17-case run and the latest Attachments PNG was independently inspected at full width. The nonweb assertion does not exercise the browser platform-view `Stack`; Root owns that separate browser evidence. The earlier full-width widget snapshot was not proof of full-width web rendering.

Real feature integration checks exercise:

- confirmed create and activation, acknowledged journal cleanup and draft retirement/tombstones, persistent desktop completion, no automatic navigation or duplicate command, and the explicit allowed Open action;
- uncertain activation with a known Draft project and original file manifest, completion-to-files navigation, wrong-content rejection, exact original-content reselect and immutable command/file keys;
- uncertain controlled-document upload, screen unmount plus coordinator reconstruction from its persisted journal, lost process-held bytes, exact reselect and explicit retry with the original upload key, without a second core/activation command.

The protected-capability negative test passed: confirmed creation does not manufacture an Open callback or control when `projects.view` is absent. Browser/native ownership guarantees remain those of the separate storage evidence; the in-process unit adapter used here is explicitly not cross-process proof. Root owns full routed browser/360px/RTL/device and broad-gate evidence; none of those are inferred from this widget test run. Production activation remains separately gated.
