# Project setup — UI and interaction addendum
**Version 1.0 · 2 October 2026 · Proposed implementation target**

This addendum updates the behavior of the five generated visual concepts. It is an interaction specification, not a new rendered UI or a claim that the app has been changed. The numbered SRS and current protected backend rules prevail over the artwork.

## The design direction

Keep Yorks’ navy, blue, white and light-neutral palette, clear icons, confident headings and aligned forms. Give the form—not an illustration or repeated help card—the largest usable area. A good-looking form is not enough: keyboard order, draft acknowledgement, error recovery and final effects must be predictable.

On wide desktop, use a compact five-step rail beside a readable main panel. Show the app sidebar at its existing supported width; do not add a second permanent dense navigation system. Two-column fields are appropriate only when each column has enough width for realistic names and inline errors. An optional help panel appears only at wide widths; otherwise use concise inline help or a disclosure.

Avoid nested cards with repeated “Parties & access” or “Buildings” headings, a long repeated “Good to know” column, duplicate Connected indicators, full-page empty panels and excessive required stars. Alignment must survive real long labels and errors, not only the sample content.

## Specific changes to the existing concepts

| Existing visual implication | Updated UI contract |
|---|---|
| Client, consultant, main contractor, code, floors and delivery address have red stars | These remain optional under the inspected model. Reference/name and at least one named building are required at commit; activation has its own PE prerequisite. |
| “Saved just now” appears beside every step | Use an acknowledged local state: “Saved on this device.” Show a separate server result only after a committed command. |
| Start date is split into DD/MM/YYYY fields | Prefer one accessible typed date control plus calendar. Explain format and preserve null/partial input. Today is an explicit helper. |
| A large grid of staff cards invites selecting anyone | Use an authorized searchable directory with selected people/roles, clear scope and similar-name disambiguation. Preserve exact permissions. |
| Add building copies the last FRP/address values silently | Blank Add starts clean. “Add another like this” is explicit and reversible. |
| Floors field suggests a numerical floor count | Use text labels/chips, e.g. B1, Ground, L1, Roof. Do not reinterpret existing labels. |
| All selected attachments look uploaded | Distinguish selection, missing bytes/reselection, uploading, finalizing, ready and failed. Files upload only through the existing authorized phase. |
| “Ready to create workspace” implies active MR work for everyone | Review states whether the result will be Active or a real Draft awaiting PE/activation, based on fresh server prerequisites. |
| “All information can be edited anytime” | Say “You can update permitted project details later.” Lifecycle, access and downstream-history restrictions still apply. |
| Parties listed imply invited contractors | Company-party names are metadata, not accounts or invitations. Only explicit authorized membership changes grant access. |
| Same create flow reused for edits means identical save behavior | Edit has local unpublished proposals, direct sections, a before/after review and explicit live Save changes. Team changes remain separate protected actions. |

## Shared screen anatomy

**Header:** breadcrumb and mode; short page purpose; current local-save state; secondary Save draft. Keep the full legal project name available without using it as an oversized multi-line hero.

**Main work area:** section title, one concise help sentence, labelled fields, inline validation and one focused sub-editor when needed. Place requiredness and error messages where they belong, not in a remote panel.

**Action area:** Back on the leading edge, Continue or the reviewed final action on the trailing edge. Optional Skip appears only for Attachments and does not silently discard a selected file. Keep sufficient bottom inset for the last field and software keyboard.

**Help:** focus on the decision currently being made. Explain why a PE is needed for activation, how Common scope works, or why file reselection is needed. Avoid general prose that offers no next action.

## Create and edit section behavior

### 1. Project details
Reference and name come first. Then client/contract, location, dates and notes; optional contact details are disclosed on demand. Preserve long text and hidden existing contacts. Show reference normalization/duplicate feedback without changing the caret during typing. Do not reserve the reference through local autosave.

### 2. Parties & access
Show concise party fields and repeatable contractor lists. Keep unfinished Add text recoverable. Below, use searchable selected-person rows with exact roles. Explain the creator’s membership and the Site Engineer’s bounded initial-PE selection. In edit mode, show current team and a separate Manage access action; explicitly state it applies access independently of Save project.

### 3. Buildings
Show the added-building list and a focused Add/Edit panel. Name is required for an applied row; code may be blank where server generation is supported. Levels are label values, address optional, FRP per building. Show FRP in the added row and review, including the unchecked state when relevant. Do not count Common as a building. On desktop, arrow/Tab behavior must not become a competing spreadsheet unless a real grid is deliberately implemented.

### 4. Attachments
Use a modest drop target and keyboard-accessible Add files. Each file has a truthful state and a contextual action. Restored metadata needing bytes shows Reselect; pending/failed upload shows Retry only after a project exists. Present changed-content same-name files for review. Removing a local selection is not deleting a committed document. Do not show a ZIP as previewable like a PDF unless supported.

### 5. Review
Each section has a compact summary and a precise Edit link. Highlight unresolved input and lifecycle implications. No duplicate green ready indicators. Create mode explains what will be created and what may still need activation/files. Edit mode presents real additions, changes, clears and retirements against the base version. A project save must not imply that a separately applied team command is still pending.

## Draft and command status copy

| Situation | Recommended copy | User action |
|---|---|---|
| New untouched form | Not saved yet | Begin entry. |
| Dirty local input | Saving draft on this device… | Continue typing; do not imply a server save. |
| Acknowledged local input | Saved on this device · 15:24 | Save/continue; help explains device limitation. |
| Local persistence failed | Draft cannot be saved on this device. Keep this page open. | Retry storage; review safe commit options. |
| Edit proposal locally saved | Changes saved on this device. Not applied to the project. | Review changes / Save changes. |
| Request sent | Creating project… | Prevent duplicate intent; retain input/journal. |
| Lost response | We are checking whether your project was saved. | Check status / recover original intent. |
| Core created but not active | Project created as draft. Activation needs attention. | Open project / permitted next action. |
| Core saved, upload incomplete | Project saved. 2 files need attention. | Open project / recover files. |
| Existing project changed elsewhere | This project changed while you were editing. | Review differences; preserve proposal. |
| Another local tab owns draft | This draft is being edited in another tab. | View read-only / deliberate takeover. |

## Accessibility and keyboard acceptance

Use the SRS keyboard register. Windows keyboard behavior must feel ordinary: logical Tab order, text selection, copy/paste, local undo and explicit focused buttons. Do not capture browser tab switching for internal tabs. Ctrl/Cmd+S saves local recovery only. Enter in an ordinary field never creates or updates the project.

Keep focus nodes and local row identities stable. Background state updates must not rewrite an active input or cancel IME. Announce validation and outcomes without stealing focus on every autosave. Manual tab activation separates focus from selection. Preserve focus when a popup closes and keep the focused input above the keyboard/footer.

Test at 1366×768 desktop, 1024×768 tablet and 390×844 phone, plus the wider SRS matrix. Test 200% text, 320 CSS-pixel equivalent reflow, Windows display scaling, high contrast, screen readers, RTL where supported, and reduced motion. Primary touch controls should be comfortably 44–48 pixels, with nonoverlapping hit areas.

## Review checklist for the working build

For every create step, edit section and recovery state, check alignment, long labels, local-save meaning, real state, next action, focus order, error placement, permission relevance and data preservation. Capture actual implementation screenshots; do not use the AI mockups as evidence of working controls. A screen can be visually symmetrical and still fail if it loses a field, falsely reports a save or hides the reason a backend command was rejected.
