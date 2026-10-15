# P0 register read evidence - 15 October 2026

Local isolated synthetic envelope: 30 active projects, 600 Project MRs, 2,400 lines; five exact-role personas (Admin, Project Engineer, Site Engineer, Procurement and Project Manager). Four register reads to one full-detail read. Three rounds per concurrency/version, independent database sessions, each authenticated statement limited to 8 seconds. No Company workload was synthesized in this benchmark; the separate 69-check register suite covers combined Project/Company authorization and paging.

The inline register EXPLAIN (ANALYZE, BUFFERS, WAL, SETTINGS) ran under the function owner with identical explicit actor/parameters, matching the SECURITY DEFINER execution context. Existing authorized helpers were retained. Baseline/candidate register execution: 175.775 / 95.582 ms; shared-buffer hits 39,451 / 18,925; zero physical shared reads. Warm-cache, local-host figures are not production latency promises.

| Version | Concurrent sessions | Register P50 / P95 / P99 ms | Detail P50 / P95 / P99 ms | Errors |
|---|---:|---|---|---:|
| before | 5 | 147.4 / 202.1 / 202.1 | 13.5 / 14.1 / 14.1 | 0 |
| before | 10 | 162.8 / 223.7 / 226.9 | 20.9 / 25.4 / 25.4 | 0 |
| before | 20 | 296.6 / 391.5 / 418.9 | 32.8 / 63.4 / 63.4 | 0 |
| before | 30 | 437.6 / 538.2 / 600.2 | 51.1 / 69.8 / 69.8 | 0 |
| after | 5 | 108.5 / 115.0 / 115.0 | 13.4 / 13.6 / 13.6 | 0 |
| after | 10 | 147.3 / 169.6 / 182.4 | 22.1 / 26.1 / 26.1 | 0 |
| after | 20 | 246.8 / 317.1 / 329.7 | 47.8 / 61.6 / 61.6 | 0 |
| after | 30 | 392.1 / 517.1 / 550.0 | 83.1 / 172.6 / 172.6 | 0 |

All 390 measured RPCs completed; zero statement timeouts / SQLSTATE 57014. The run is a read-load check only: it does not measure mixed critical write commands, lock waits, remote network, DB CPU, gateway/HTTP overhead, browser outcome reconciliation or staging hardware. These remain separate acceptance gates. Detailed per-sample values and full query plans are retained beside this file.

Reproduction: `python3 tool/p0_material_register_local_benchmark.py`. The script refuses a container whose Supabase workdir label does not match this checkout and accepts no remote DSN. It creates/removes only `P0-REGISTER-LOAD-` fixtures. Cleanup uses a transaction/session-local trigger bypass to remove only synthetic immutable snapshots before their test requests; it does not alter global triggers or production. Initial cleanup hit the retained snapshot FK, was corrected, and all synthetic requests/projects were confirmed removed. No migration, role or timeout configuration is changed by the benchmark.

Client checks: 28 coordinator/activity-gate tests passed. 29 register-centre/Realtime tests passed including desktop and 360px goldens, transient refresh auto-recovery and immediate cached-row removal on confirmed denial. Permission map parity: 642 positive/negative comparisons across all nine exact roles, active/archived/unassigned projects, organization scope, enforced/shadow mode, explicit grants/denials, dependency denial and expired legacy assignments; existing combined register 69 checks also passed.

Migration rollback: restore `v1_list_unified_material_request_summaries` from `20260928144343_optimize_unified_material_request_register_setwise.sql` in a corrective migration, then drop the internal map helper. Preserve all business, permission and audit rows. No production or staging migration was applied in this subtask.

Project outcome extension: `20261015091400_p0_project_command_outcome_lookup.sql` adds an actor-owned, read-only completed-command witness. It returns the current authorized project projection, never historical party, membership or attachment data. Missing witnesses remain unknown. The existing reviewed journal and its payload/key are retained. Production providers enable two automatic reconciliation checks, coalesce duplicate clicks and hold the register activity gate through the bounded cycle. Read-only checks remain available after the existing three-mutation cap, preventing a prolonged response outage from permanently freezing recovery. Project recovery plus desktop/mobile interaction: 82 tests passed. The separate 13-check SQL suite verifies owner/missing/cross-actor/inactive/anonymous boundaries and absence of duplicate project/audit/idempotency effects.
