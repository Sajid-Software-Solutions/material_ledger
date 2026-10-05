# Single footer Back — authenticated staging captures

Application source: `6be98178231a9aaf43926715f99a2e0ddef67688`.
Staging deployment: `dpl_7rQK47viZZvLXztcT1srKPdNAYS2`.

These are native JPEG captures without image editing. Desktop is 1456×787
CSS / DPR 1; phone is 360×900 CSS / DPR 1.

- [Desktop review](desktop-review.jpg): original universal office chrome,
  setup rail without its former exit link, retained footer Back.
- [Phone review](mobile-review-360.jpg): compact existing header/progress,
  readable cards and retained actions.
- [Phone lower content](mobile-review-360-bottom.jpg): lower review and sticky
  footer remain accessible.

The user's existing draft was owned by another tab and remained read-only.
No takeover, input editing, final Create/Update, activation or file upload was
performed. Fresh-session console inspection returned zero warnings/errors;
this does not close the known breakpoint-resize semantics gate. Verification
tabs were closed, viewport overrides reset and the original user tab retained.

See the [release report](../../SINGLE_BACK_NAVIGATION_2026-10-05.md) and
[machine evidence](../../SINGLE_BACK_NAVIGATION_2026-10-05.json).
