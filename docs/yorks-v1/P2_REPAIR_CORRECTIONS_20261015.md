# P0 release review corrections — 15 October 2026

Status: corrections in progress; no additional production release is claimed.

## Ownership

The existing Codex chat **Check staging-only changes**, thread
`01a0edb7-5ba7-7202-8e11-b1f94814c893`, implemented
`codex/p0-truthful-command-outcomes-20261015`. Its recorded implementation and
release include app source `3cba2e6812fd06db1a56907436c9855717aa359e` and release
evidence commit `b3a80666c82cb901159f3d786db45b30c1fa1fc5`. The owner was verified
against that chat's actual turn history, not inferred from a Git author.

The review identifies three source-confirmed paths requiring correction:

1. Preserve an explicit manual, original-key status lookup after the automatic
   check budget is exhausted, across every generic tracked action.
2. Recover an interrupted upload after intent expiry only when a trusted server
   transaction establishes that the old intent is expired and uncommitted.
3. Return a minimal authorized command receipt before loading optional screen
   data, so a slow projection cannot erase a known commit.

The review is not represented as a fresh production reproduction. The original
release's passing tests do not establish coverage of these additional cases.

## Workspace entry-point containment

The released source still contained a hidden VS Code `folderOpen` task that ran
Node against `public/fonts/fa-solid-600.eot`. That file was 12,727 bytes of ASCII
text rather than an EOT font, with SHA-256
`533e995069ae094d2b8f5acdee575c7f1ecf0364d59d9ab96c7a9524fd231380`.

Before running project tooling for these corrections:

- Removed the task and its hidden automatic launch configuration.
- Disabled automatic repository tasks and removed the nested folder-open task
  from workspace settings.
- Removed the matching disguised asset from the repair worktree and primary
  checkout. Unrelated primary-checkout changes were preserved.
- Retained the original task, settings and payload as non-executable evidence
  outside the repository, under owner-only private backup storage.
- Added regression checks for automatic folder-open tasks and font binary
  signatures. Both tests passed.

No payload was executed for inspection. These steps remove the identified
entry point; they do not establish whether another editor previously ran it or
constitute a host-wide compromise assessment. The production web artifact was
built from `build/web`, not by uploading the source checkout.

## Verification and release

Implementation, regression evidence and any deployment will be recorded here
after completion. Existing production remains the previously documented release.
