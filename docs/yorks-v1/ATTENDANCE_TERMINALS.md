# Attendance terminals: the receiver and the punch log

Status: **built; rehearsed end to end on staging (18 November 2026); not in
production yet (waiting for the owner's OK); not yet proven against a real
terminal.**

Decision: [`PRODUCT_DECISIONS.md`](PRODUCT_DECISIONS.md) section 64 (owner
request, 17 November 2026). Attendance itself is described in
[`WORKFORCE_ATTENDANCE_TIMESHEETS.md`](WORKFORCE_ATTENDANCE_TIMESHEETS.md);
nothing in it changes here.

## What this is

A biometric attendance terminal (ZKTeco, attendance push) is given one web
address. From then on it calls Yorks by itself: it says who it is, sends each
check-in and check-out, and asks now and then whether there are instructions.
Yorks answers in the terminal's own format and keeps every punch in a log.

| It does | It does not |
|---|---|
| Answer terminals registered by serial number, while the receiver is on | Answer any other caller |
| Keep every punch once, exactly as the terminal reported it | Change, merge or delete a punch |
| Keep an attendance line it cannot read, as it arrived | Tell a terminal "OK" for a line it did not keep |
| Count what else a terminal sends, by kind | Store a face, fingerprint, photo or name |
| Note when each terminal was last heard from | Touch an attendance day, line, month, hours or screen |

The last row is the point of this slice: the app is unchanged. No route,
screen, flag or Dart file is added, and taking attendance works exactly as
before. Putting a checked-in labourer on a place's day is a later slice with
its own decision.

## The path

```text
terminal --HTTPS--> terminals' address --> attendance-terminal --> Postgres
            /iclock/...   (Vercel rewrite)     (Edge Function)     (v1_wf_terminal_*)
```

1. **The terminal** is set once: Menu, COMM., Cloud Server Setting. Server
   mode ADMS, Enable Domain Name on, Server Address = the terminals' address,
   Server Port 443, HTTPS on. It always calls `/iclock/...` at the root of
   that address; it cannot be given a longer path.
2. **The terminals' address** is a tiny static Vercel project of its own
   (`deploy/attendance-terminals/`), separate from the Yorks web app. Its one
   rule passes `/iclock/*` to the Edge Function. The app's `web/vercel.json`
   is not touched, and the terminals' address can stay the same if the app's
   address ever changes.
3. **`attendance-terminal`** (`supabase/functions/attendance-terminal/`,
   `verify_jwt = false` because a terminal cannot sign in) reads the call,
   splits attendance lines and calls Postgres with the service role.
4. **Postgres** decides everything: whether the receiver is on, whether the
   serial number is registered and active, what is stored, what is a
   duplicate and what is kept as unreadable.

## What a terminal sends and what it is told

| Call | Meaning | Answer |
|---|---|---|
| `GET /iclock/cdata?SN=..&options=all` | Handshake | `GET OPTION FROM: <SN>` and the option lines below |
| `POST /iclock/cdata?SN=..&table=ATTLOG&Stamp=..` | Check-ins and check-outs, one tab-separated line each: user ID, time, state, verify mode, work code | `OK: <lines>` once every line is stored, already held or kept as unreadable |
| `POST /iclock/cdata?SN=..&table=<other>` | Users, fingerprints, faces, photos, the terminal's own options | `OK`; the body is counted by kind and dropped |
| `GET /iclock/getrequest?SN=..` | "Any instructions?" | `OK` (Yorks sends none) |
| `POST /iclock/devicecmd?SN=..` | The result of an instruction | `OK` |
| `GET /iclock/ping?SN=..` | "Are you there?" | `OK` |
| anything else under `/iclock/` | Not spoken (for example `/iclock/registry`, the access-control dialect) | 404, and it is logged |

Refusals are `ERROR` with a status: 400 no usable serial number, 403 not
registered or switched off, 503 receiver off, 413 body over 4 MB, 500 the
database did not answer. A terminal treats anything but `OK` as "not
delivered", keeps its punches and tries again.

The handshake a terminal gets by default:

```text
GET OPTION FROM: <SN>
ATTLOGStamp=<newest stamp it reported | None | 0>
OPERLOGStamp=9999
ATTPHOTOStamp=None
ErrorDelay=60
Delay=60
TransTimes=00:00;14:05
TransInterval=1
TransFlag=100000000000
TimeZone=4
Realtime=1
Encrypt=None
```

`TransFlag=100000000000` asks for attendance only (the first of twelve
positions). `Delay` is how often the terminal asks for instructions: at 60
seconds one terminal makes about 43,200 calls a month. `TimeZone=4` is Abu
Dhabi.

## Rules that always hold

- **OK only after storing.** The function answers `OK` to an attendance
  upload only after `v1_wf_terminal_punches` has returned. Any error, timeout
  or odd answer becomes an error status, so the terminal sends the lines
  again.
- **Stored once.** A punch is unique by terminal, user ID and the terminal's
  time. A resend, or a full "send everything again", stores nothing new.
- **Nothing readable is dropped.** A line whose user ID or time cannot be
  read goes to `v1_workforce_terminal_rejects` with the reason. A punch dated
  ahead of now or before 2020 is stored and marked `clock_suspect`.
- **Attendance only.** Bodies of any other table never leave the function's
  memory: not to the database, not to the logs. The diagnostic log takes a
  fixed list of short facts (`v1_wf_terminal_details`), so a body cannot
  reach it even by mistake.
- **Off by default.** The migration leaves the receiver off and registers no
  terminal.

## Data

| Table | Holds |
|---|---|
| `v1_workforce_terminal_settings` | One row: the receiver's switch and the handshake values (`poll_seconds`, `error_delay_seconds`, `realtime`, `trans_times`, `trans_interval_minutes`, `trans_flag`, `extra_option_lines`) |
| `v1_workforce_terminals` | Registered terminals: serial number, name, the place served (`team_id`, an attendance place), active or not, clock offset (240 minutes), the newest stamp, model, firmware and when it was last heard from. Never deleted |
| `v1_workforce_terminal_punches` | The punch log: terminal, the place at the time, terminal user ID, the terminal's time, the same moment in UTC, the day, state, verify mode, `clock_suspect`, the raw line. Append-only |
| `v1_workforce_terminal_rejects` | Attendance lines that could not be read, as they arrived, with the reason. Append-only |
| `v1_workforce_terminal_requests` | A diagnostic log: handshakes, uploads, other data and refusals, with counts. Asking for instructions is not logged. Refusals are capped at 200 a day; rows are cleared after 30 days (`pg_cron` job `yorks-workforce-terminal-request-retention`, 22:25 UTC) |

All five have row level security on and no grant to `anon` or
`authenticated`. No function is executable by them either, so no role reads
or writes any of this from the app. The Edge Function calls
`v1_wf_terminal_handshake`, `v1_wf_terminal_punches` and
`v1_wf_terminal_seen`; an operator calls `v1_wf_terminal_receiver`,
`v1_wf_register_terminal`, `v1_wf_set_terminal_active` and
`v1_wf_terminal_resend_all` from the SQL editor. Registering through the app,
with audit events, belongs to the next slice; until then the terminal table's
`record_version` and timestamps are the only trace of who changed what.

A terminal's user ID is stored as sent. It is not yet matched to a labourer
anywhere. The intended match is the digits of the worker number (`WR-000418`
is 418); the query in "Check" below shows it as a guide only.

## Runbook

Every step that changes staging or production needs the owner's OK. Before
deploying anything, check the checkout as the project notes say (no
`.vscode/eslint`, no `android/service`, no `GIT_ALL_IN_ONE`).

### 1. Deploy

```bash
npx supabase@latest db query --remote=<ref> --yes -f supabase/release/attendance_terminals_bundle.sql
```

```bash
npx supabase@latest functions deploy attendance-terminal --remote=<ref> --yes
```

```bash
SUPABASE_URL=https://<ref>.supabase.co ./tool/attendance_terminal_gateway.sh
```

```bash
cd build/attendance-terminal-gateway && npx vercel@latest link --yes --project yorks-terminals && npx vercel@latest deploy --prod --yes && rm -f .env.local
```

The last command creates (the first time) a Vercel project for the terminals'
address and removes the token file `link` leaves behind. The address is then
`https://yorks-terminals.vercel.app`. Before a second terminal is installed,
give it a domain the company owns: a terminal keeps whatever address is typed
into it.

Nothing answers yet: the receiver is off.

Staging has all of this already: project `yorks-r35-staging`, address
`https://yorks-terminals-staging.vercel.app`, receiver on, one simulator
terminal `SIM-0001` with no place. Use it to rehearse anything.

### 2. Prove the path without a terminal

In the SQL editor:

```sql
select public.v1_wf_register_terminal('SIM-0001', 'Simulator');
select public.v1_wf_terminal_receiver(true);
```

The simulator has no place, so nothing it sends can ever count as attendance.
Then:

```bash
./tool/attendance_terminal_simulator.sh --base-url https://<terminals address> --serial SIM-0001
```

Fourteen checks should pass. Its punches stay in the log for good, under the
simulator terminal.

### 3. Terminal day

Once steps 1 and 2 are done in production, a new terminal takes three steps
and a few minutes.

**a. Set the terminal.** Set its date and time. Then Menu, COMM., Cloud
Server Setting: Server mode **ADMS**; Enable Domain Name **on**; Server
Address **the terminals' address** (no `https://`, no path); Server Port
**443**; HTTPS **on**; Enable Proxy Server **off**.

**b. Register it.** It is refused until it is registered, and each refusal
is logged with its serial number, so the number need not be typed. See who
is waiting:

```sql
select serial_number, count(*) as calls, max(received_at) as last_call
from public.v1_workforce_terminal_requests
where outcome = 'unknown_terminal' and received_at > now() - interval '1 hour'
group by serial_number order by last_call desc;
```

Register the one that just called, with its name and place:

```sql
select public.v1_wf_register_terminal(
  (select serial_number from public.v1_workforce_terminal_requests
   where outcome = 'unknown_terminal' and received_at > now() - interval '15 minutes'
   order by received_at desc limit 1),
  'Workshop gate', 'location:workshop');
```

The serial number is also on the terminal's label and under Menu, System
Info, Device Info, if you prefer to type it. A project's place is
`project:<project id>`. Registering the same serial number again renames or
moves the terminal and switches it back on; punches already stored keep the
place they were made at. The terminal tries again by itself within a minute
or two and is then answered.

**c. Run the acceptance check.** Open
`tool/attendance_terminal_acceptance.sql`, put the serial number on its
marked line and run it. Twelve lines, each PASS, WAIT or FAIL with what to do
next. WAIT lines walk through the test: check in once, then unplug the
network, check in three times, wait 15 minutes and plug it back in. The
terminal is accepted when all twelve read PASS. (Against the simulator, lines
7 to 9 read FAIL on purpose: it sends an unreadable line, a fingerprint and
an access-control call to prove they are handled.)

### 4. What to ask the supplier, in writing

The terminals' address answers only this, measured on 18 November 2026:

- **HTTPS, TLS 1.2 or newer.** TLS 1.0 and 1.1 are refused, and plain HTTP
  is redirected to HTTPS.
- **A domain name with the server name sent (SNI).** Without it the address
  presents a certificate for a different name.
- **Attendance (T&A) push firmware**, set by "Cloud Server Setting", not the
  access-control dialect.
- **Answers without a fixed length** ("chunked"). ZKTeco's protocol document
  allows them.

So the question for the exact model and firmware is: "Does it push
attendance (ADMS, T&A push) to our own domain name over HTTPS with TLS 1.2
and SNI?"

### 5. Check

```sql
select terminal_name, serial_number, is_active, device_name, firmware_version,
  first_seen_at, last_seen_at, last_handshake_at, last_punch_received_at
from public.v1_workforce_terminals;
```

```sql
select received_at, endpoint, table_name, outcome, received_count,
  stored_count, duplicate_count, rejected_count, details
from public.v1_workforce_terminal_requests
order by received_at desc limit 30;
```

```sql
select p.received_at, t.terminal_name, p.device_user_id, p.punched_at_local,
  p.punch_state, p.verify_mode, p.clock_suspect,
  w.worker_number, w.full_name as worker_with_that_number
from public.v1_workforce_terminal_punches p
join public.v1_workforce_terminals t on t.id = p.terminal_id
left join public.v1_workforce_workers w
  on p.device_user_id ~ '^[0-9]{1,6}$'
  and w.worker_number = 'WR-' || lpad(p.device_user_id, 6, '0')
order by p.received_at desc limit 30;
```

`tool/attendance_terminal_acceptance.sql` runs all of this as one check
(step 3c). One thing it cannot see in an afternoon: whether the terminal's
clock still agrees with Abu Dhabi time after a week. Run it again then.

### 6. Switch off, roll back

```sql
select public.v1_wf_set_terminal_active('<SERIAL>', false);  -- one terminal
select public.v1_wf_terminal_receiver(false);                -- every terminal
```

A refused terminal keeps its punches and sends them when it is answered
again. `supabase/release/attendance_terminals_rollback.sql` switches the
receiver off, revokes the functions and removes the schedule; tables and
punches stay. Deleting the Vercel project and the Edge Function removes the
address.

## When a check fails

| What you see | Likely cause | Try |
|---|---|---|
| No request row at all | The terminal is not reaching the address: HTTPS not supported or too old on this firmware, wrong address or port, no internet | Call the address from a laptop on the same network with the simulator. Ask the supplier for firmware with HTTPS. Plain HTTP cannot work: the address answers HTTPS only |
| `unknown_terminal` rows | The serial number is not registered as typed | Compare with `serial_number` in the row; register it |
| Handshake rows but no `punches` rows | The firmware reads `TransFlag` differently | `update public.v1_workforce_terminal_settings set trans_flag = 'TransData AttLog';` then restart the terminal |
| Punches several hours off | The terminal's clock or zone | Set the time on the terminal; if it drifts back, add `'ServerVer=2.4.1'` to `extra_option_lines` so it follows the server's time |
| Rows with `table_name` `OPERLOG`, `BIODATA` or `USERINFO` | The firmware uploads more than attendance | Nothing is stored. Check `trans_flag` as above |
| Rows with endpoint `other` and note `endpoint registry` | The terminal speaks the access-control dialect | It needs attendance firmware; this receiver does not speak that dialect |
| Rows in `v1_workforce_terminal_rejects` | A line format this receiver does not know | Nothing is lost. Read `raw_line` and extend the parser |
| Old punches missing after an outage | The terminal did not resend | `select public.v1_wf_terminal_resend_all('<SERIAL>');` then restart the terminal |

`extra_option_lines` takes up to twenty `Key=Value` lines added to the
handshake, for a firmware that needs one more option, without a deploy:

```sql
update public.v1_workforce_terminal_settings
set extra_option_lines = array['ServerVer=2.4.1', 'PushProtVer=2.4.1'];
```

## What is not proven

Everything on the Yorks side is proven on staging, including the hop through
the terminals' address. What is left is the terminal itself. The message
format comes from ZKTeco's published protocol summaries and a maintained
open-source receiver, not from a terminal on the bench. One real unit has to
settle:

- that its firmware can call an HTTPS address with TLS 1.2 and SNI;
- that it reads an answer sent without a fixed length;
- that `TransFlag=100000000000` makes it send attendance and nothing else;
- that punches made offline arrive after it reconnects;
- how slow a `Delay` it accepts, and whether its clock follows the server.

Also not built yet: matching a terminal user ID to a labourer, the in-app
terminal register, anything on an attendance day, alerts when a terminal goes
quiet, and authentication stronger than the serial number. Anyone who knew a
registered serial number and the address could add false punches to the log;
that is why nothing reads the log yet.

## Limits to plan for

- Supabase's free plan includes 500,000 Edge Function calls a month for the
  whole organisation. Six terminals at `Delay=60` use about 259,000.
- The database is in Frankfurt. Punches are a user ID and a time; biometric
  data stays on the terminal.

## Tests

| Check | Command | Covers |
|---|---|---|
| Protocol and receiver | `npx deno@latest test supabase/functions/attendance-terminal/` | Routing, line splitting, the handshake text, every refusal, "OK only after storing", no body in any call or log |
| Database | `supabase test db` (`yorks_workforce_attendance_terminals.test.sql`) | Off by default, registration, duplicates, unreadable lines, stamps, wrong clocks, append-only, the refusal cap, clean-up, no right for Project Engineer, Site Engineer, Procurement, Admin or a visitor, attendance untouched |
| Whole path | `./tool/attendance_terminal_simulator.sh` against a local stack or staging | The address, the function, the API and the database together |
| A real terminal | `tool/attendance_terminal_acceptance.sql` in the SQL editor | Twelve read-only checks: registered, heard from, handshake, a check-in, the clock, unreadable lines, attendance only, the dialect, wrong clocks, the outage test, stored once |

Evidence, 17 November 2026, on a private local stack (Supabase CLI 3.2.0,
Postgres 15, the real Edge Function runtime and API gateway):

| Check | Result |
|---|---|
| `supabase db reset` | Every migration applied, this one last |
| `supabase test db` | 193 files, 6,441 tests, all passed; the new file has 93 |
| Function tests (Deno 2.9.6) | 26 passed |
| Simulator through the gateway, function and database | 14 of 14: four punches stored once each, one unreadable line kept, a name and a fingerprint dropped, an unregistered serial refused |
| Database after the replay | No simulated name or template in any table; no attendance day or line created |
| Rollback, then the bundle again, then a third time while switched on | Handshake 500, then 503, then 200 once switched on; punches and the terminal kept; the switch left as it was |

`yorks_workforce_t13_hardening.test.sql` freezes the list of Workforce tables.
The five new tables were added to it, and `v1_workforce_terminal_requests` is
listed as the one new table without a delete guard, because it is cleared
after 30 days.

No Dart, web or Android file changed, so the Flutter analyze, test, web and
APK gates do not apply to this slice.

Staging rehearsal, 18 November 2026 (project `yorks-r35-staging`, Postgres
17.6, the hosted Edge Function runtime, Vercel):

| Step | Result |
|---|---|
| Before: name clashes and what the release depends on, staging and production | None; everything present on both |
| Release bundle on staging | Applied; five tables with row level security, receiver off, no right for `anon` or `authenticated`, schedule present |
| Function deployed, receiver off | Handshake 503; no sign-in needed |
| Simulator straight at the function | 14 of 14 |
| Simulator through `https://yorks-terminals-staging.vercel.app` | 14 of 14: the address passes on GET, POST bodies and query values |
| Database after both runs | 8 punches stored once each, 1 unreadable line kept once, no simulated name or template anywhere |
| Acceptance check on the simulator | Runs read-only; flags the simulator's three deliberate oddities and waits for the outage test |
| Time to answer one call, warm | About 0.5 s at the function, about 1.1 s through the address (measured from Pakistan) |
| Plain HTTP, TLS 1.0, TLS 1.1 | Redirected (308) or refused; TLS 1.2 accepted |

Production had the same before-check and nothing else: the release was not
applied there.

Release: `supabase/release/attendance_terminals_bundle.sql`; rollback:
`supabase/release/attendance_terminals_rollback.sql`.
