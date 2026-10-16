# Retry marker and restored loader review — 16 October 2026

## Confirmed repository finding

The remote repair branch was force-updated from the verified documentation
commit `cea147240d576371ff1113a147113755a3c863d5` to
`4aefc9c337dbd0d02f011fbca8518e0b2bee68b6`. Both have the same parent and
release-documentation subject. Their only tree differences are workspace
settings, automatic tasks and a newly disguised `public/fonts/fa-solid-700.otf`.
The restored folderOpen task executes that asset using Node with hidden output.
The new payload SHA-256 is
`ca92a5d5286319008106d15de85dbb58d9160c6b8f02375dedbbf9be097427d6`.
It was read as data only and retained privately outside the repository.

The existing local release checkout had not changed to that remote commit.
Containment merge `0e89b3a5ac0141996a33f70dc6aa4f0af09be322` retains both
histories while preserving the verified clean tree, removes the restored task
and asset relative to the remote revision, and restores automatic tasks to off.
It was pushed to the original repair branch as a fast-forward, without rewriting
history. The primary dirty checkout also has automatic tasks off, no nested
task and neither identified payload. No unrelated dirty work was changed.

The font-signature regression now checks OTF as well as TTF, WOFF, WOFF2 and
EOT. The prior test omitted OTF. No payload was executed. These facts do not
establish who changed the remote branch, whether another machine executed a
task, or whether this computer was compromised. Historical malicious revisions
remain evidence and must not be treated as safe executable checkouts.

## Confirmed retry finding and correction

An offline preflight calls markNotSent, which records both known-not-sent and
acknowledged for that key. Sending the same key again previously cleared only
known-not-sent. An uncertain response then left the acknowledged marker hiding
the tracked pending lease and manual recovery controls.

markDispatched now clears both in-memory markers only after the dispatched
state is persisted. The existing failure branch still marks a failed persistence
attempt not sent. The UUID, fingerprint, automatic-check budget and mutation
contract remain unchanged; manual recovery only reads the original receipt.

The new controller regression reproduced the original failure before the fix.
After the fix it verifies offline preflight, same-key retry with a lost response,
both pending predicates, manual original-key receipt lookup and lease retirement.
There is exactly one actual mutation send; status recovery does not resend it.

Verification: 37 focused tests passed; the new regression failed before the
marker correction and passed after it. Full analyzer passed, 2,809 Flutter tests
passed with four retained skips, formatting and diff checks passed. CI web build
passed (startup gzip 2,876,792 / 2,900,000 bytes) and the ephemeral-signed release
APK build passed (113.6 MB, verification artifact only). No schema changes were
made, so no database reset or migration was needed. Existing desktop/mobile
manual-recovery golden checks passed within the focused/full suites; no visual
layout was changed. The offline path was reproduced through the controller
test, not by interrupting a live production user's connection.

## Release boundary

Production main JavaScript still matches the previously recorded release:
`aa4f1a7b017ba190f076b081824e081f3d3d74783449385745a041ff6357aa6f`.
No production deployment or database mutation was performed for this follow-up.
The new retry correction requires a subsequent web release to affect users.

Rollback is the prior clean application source, never the restored loader.
No schema, permissions, business data, persisted key format or UI layout changes.


## Subsequent owner-authorized production release

The owner subsequently authorized production deployment on 16 October 2026.
The earlier review-only boundary above is historical; the retry marker fix is
now live at [Yorks production](https://yorks-r35.vercel.app).

- Clean compiled source: `6d3aa0cc4dd9b86df8fd5cb38c693a966fbea090`.
- Deployment: `dpl_6kHrXZ3yHFrJA41vLhcimN9xFWdZ`, READY.
- [Immutable deployment](https://yorks-r35-jdza2vzvp-sajid-alis-projects-0ec775a2.vercel.app).
- Main JavaScript SHA-256:
  `747f3891d5ccc5dc2502643bda29990a754932b11617e0685dde2088a36c2c6d`.
- Main bytes 10,054,814; startup gzip 2,897,314 / 2,900,000 bytes.
- Production backend and clean source stamp verified; staging/CI references
  and service-role JWT absent. All existing production flags were preserved.
- Empty workspace tasks, automatic tasks off, no disguised OTF payload verified
  before build. Only build/web was copied into the isolated deployment artifact.
- Candidate and canonical production each passed all 28 route/bootstrap/deferred
  asset hash checks. Canonical deployment inspection resolves to the exact READY
  deployment above. Signed-in Admin Material Requests loaded in a fresh browser
  tab. The tab was closed after read-only verification; no business mutation or
  live network-failure injection was performed.
- No database migration was required or applied. Existing full acceptance gates
  from this report apply to unchanged app code; fresh production web build passed.
- Initial upload returned an authentication error. Account/project access were
  rechecked, retry succeeded, and final promotion was verified independently.

Evidence: [candidate](evidence/retry-marker-production-20261016/candidate.jsonl)
and [canonical](evidence/retry-marker-production-20261016/canonical.jsonl).
Runtime client-error trend/soak monitoring was not performed for this release;
route/hash checks do not substitute for production failure injection.

Rollback: promote retained deployment `dpl_8jq9UDFU1QCwgFnwmVbacRzb3Mg9`
([prior immutable release](https://yorks-r35-pwhm71bae-sajid-alis-projects-0ec775a2.vercel.app)).
No data rollback is necessary. Never restore the malicious historical loader.
