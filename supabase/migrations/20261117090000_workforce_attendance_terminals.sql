-- Attendance terminals: the receiver and the punch log (owner request,
-- 17 November 2026; PRODUCT_DECISIONS section 64).
--
--   * A biometric attendance terminal calls Yorks by itself (the ZKTeco
--     attendance push protocol). The `attendance-terminal` Edge Function
--     answers it and stores what it sends through the functions below.
--   * Only a terminal registered here, by serial number, is answered, and
--     only while the receiver is switched on. Both start off: this migration
--     registers nothing and leaves the receiver off.
--   * Every check-in and check-out is kept in an append-only punch log with
--     the terminal, the place it served, the terminal's user ID and the time.
--     A punch sent twice is stored once. An attendance line that cannot be
--     read is kept as it arrived, never dropped.
--   * Nothing here touches attendance: no day, row, month, hours or screen
--     reads the punch log. Taking attendance works exactly as before.
--   * No face, fingerprint, photo or name is stored. The terminal is told to
--     send attendance only; anything else it sends is counted and discarded.
--
-- Access: every table has row level security on and no grant to signed-in
-- people. The functions run for the service role only (the Edge Function and
-- the SQL editor). In-app management with audit events is a later slice.
--
-- Data preservation: additive only. Five new tables; no existing table,
-- function, row or grant is changed.
-- Rollback: supabase/release/attendance_terminals_rollback.sql switches the
-- receiver off, revokes the functions and removes the schedule; every table
-- and punch stays.

begin;

-- ---------------------------------------------------------------------------
-- 1. Small helpers (no table access).
-- ---------------------------------------------------------------------------

-- A serial number as stored: trimmed and upper case, or null when it is not
-- one.
create or replace function public.v1_wf_terminal_serial(p_serial_number text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_serial text := upper(btrim(coalesce(p_serial_number, '')));
begin
  if v_serial ~ '^[A-Z0-9][A-Z0-9_-]{3,39}$' then
    return v_serial;
  end if;
  return null;
end;
$$;

-- A small whole number, or null.
create or replace function public.v1_wf_terminal_int(p_text text)
returns integer
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_text ~ '^[0-9]{1,9}$' then
    return p_text::integer;
  end if;
  return null;
end;
$$;

-- The terminal's own clock time ("2026-11-17 06:31:05"), or null when the
-- text is not a real date and time. Never raises.
create or replace function public.v1_wf_terminal_time(p_text text)
returns timestamp without time zone
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_year integer;
  v_month integer;
  v_day integer;
  v_hour integer;
  v_minute integer;
  v_second integer;
begin
  if p_text is null
    or p_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$' then
    return null;
  end if;
  v_year := substr(p_text, 1, 4)::integer;
  v_month := substr(p_text, 6, 2)::integer;
  v_day := substr(p_text, 9, 2)::integer;
  v_hour := substr(p_text, 12, 2)::integer;
  v_minute := substr(p_text, 15, 2)::integer;
  v_second := substr(p_text, 18, 2)::integer;
  if v_year not between 1970 and 2099
    or v_month not between 1 and 12
    or v_day < 1
    or v_hour > 23 or v_minute > 59 or v_second > 59 then
    return null;
  end if;
  if v_day > extract(day from (
    make_date(v_year, v_month, 1) + interval '1 month' - interval '1 day'
  ))::integer then
    return null;
  end if;
  return make_timestamp(v_year, v_month, v_day, v_hour, v_minute, v_second);
end;
$$;

-- Extra handshake lines an operator may add ("ServerVer=2.4.1"): at most
-- twenty, each Key=Value in plain printable characters.
create or replace function public.v1_wf_terminal_option_lines_ok(p_lines text[])
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_line text;
begin
  if coalesce(cardinality(p_lines), 0) > 20 then
    return false;
  end if;
  foreach v_line in array coalesce(p_lines, '{}'::text[]) loop
    if v_line is null
      or v_line !~ E'^[A-Za-z][A-Za-z0-9]{0,39}=[\t -~]{0,200}$' then
      return false;
    end if;
  end loop;
  return true;
end;
$$;

-- What may be kept about a request: a fixed list of short facts. A request
-- body never reaches the log through here.
create or replace function public.v1_wf_terminal_details(p_details jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_source jsonb := case
    when jsonb_typeof(p_details) = 'object' then p_details else '{}'::jsonb
  end;
  v_keys jsonb;
  v_kinds jsonb;
begin
  select jsonb_agg(item.value order by item.position)
  into v_keys
  from jsonb_array_elements_text(case
    when jsonb_typeof(v_source -> 'query_keys') = 'array'
      then v_source -> 'query_keys' else '[]'::jsonb
  end) with ordinality as item(value, position)
  where item.position <= 24
    and item.value ~ '^[A-Za-z0-9_~.-]{1,32}$';

  select jsonb_object_agg(kind.key, kind.value::integer)
  into v_kinds
  from (
    select entry.key, entry.value
    from jsonb_each_text(case
      when jsonb_typeof(v_source -> 'line_kinds') = 'object'
        then v_source -> 'line_kinds' else '{}'::jsonb
    end) entry
    where entry.key ~ '^[A-Za-z0-9_]{1,24}$'
      and entry.value ~ '^[0-9]{1,9}$'
    order by entry.key
    limit 16
  ) kind;

  return jsonb_strip_nulls(jsonb_build_object(
    'method', nullif(left(v_source ->> 'method', 8), ''),
    'path', nullif(left(v_source ->> 'path', 120), ''),
    'query_keys', v_keys,
    'push_version', nullif(left(v_source ->> 'push_version', 40), ''),
    'language', nullif(left(v_source ->> 'language', 16), ''),
    'device_type', nullif(left(v_source ->> 'device_type', 24), ''),
    'user_agent', nullif(left(v_source ->> 'user_agent', 120), ''),
    'content_type', nullif(left(v_source ->> 'content_type', 80), ''),
    'remote_ip', nullif(left(v_source ->> 'remote_ip', 64), ''),
    'stamp', nullif(left(v_source ->> 'stamp', 24), ''),
    'body_bytes', public.v1_wf_terminal_int(v_source ->> 'body_bytes'),
    'line_count', public.v1_wf_terminal_int(v_source ->> 'line_count'),
    'line_kinds', v_kinds,
    'info', nullif(left(v_source ->> 'info', 200), ''),
    'firmware_version', nullif(left(v_source ->> 'firmware_version', 80), ''),
    'device_name', nullif(left(v_source ->> 'device_name', 80), ''),
    'user_count', public.v1_wf_terminal_int(v_source ->> 'user_count'),
    'punch_count', public.v1_wf_terminal_int(v_source ->> 'punch_count'),
    'note', nullif(left(v_source ->> 'note', 200), '')
  ));
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Tables.
-- ---------------------------------------------------------------------------

-- One row: the receiver's switch and what a terminal is told at its
-- handshake. The receiver starts off.
create table if not exists public.v1_workforce_terminal_settings (
  id boolean primary key default true check (id),
  receiver_enabled boolean not null default false,
  -- How often a terminal asks for instructions (seconds).
  poll_seconds integer not null default 60
    check (poll_seconds between 5 and 3600),
  -- How long a terminal waits after a failed call (seconds).
  error_delay_seconds integer not null default 60
    check (error_delay_seconds between 5 and 3600),
  -- Send each punch as it happens.
  realtime boolean not null default true,
  trans_times text not null default '00:00;14:05'
    check (trans_times ~ '^[0-9]{2}:[0-9]{2}(;[0-9]{2}:[0-9]{2}){0,9}$'),
  trans_interval_minutes integer not null default 1
    check (trans_interval_minutes between 1 and 1440),
  -- Which data the terminal uploads. The default is attendance only: the
  -- first of twelve positions.
  trans_flag text not null default '100000000000'
    check (trans_flag ~ E'^[\t -~]{1,200}$'),
  extra_option_lines text[] not null default '{}'::text[]
    check (public.v1_wf_terminal_option_lines_ok(extra_option_lines)),
  updated_at timestamptz not null default clock_timestamp()
);

insert into public.v1_workforce_terminal_settings (id) values (true)
on conflict (id) do nothing;

-- Registered terminals. A terminal that is not here is never answered.
create table if not exists public.v1_workforce_terminals (
  id uuid primary key default gen_random_uuid(),
  serial_number text not null check (
    serial_number ~ '^[A-Z0-9][A-Z0-9_-]{3,39}$'
  ),
  terminal_name text not null check (
    btrim(terminal_name) <> '' and char_length(terminal_name) <= 80
  ),
  -- The place it serves now (an attendance place). Null: no place yet.
  team_id uuid
    references public.v1_workforce_crew_profiles (team_id) on delete restrict,
  is_active boolean not null default true,
  -- The terminal's clock against UTC. Abu Dhabi is +4 hours all year.
  utc_offset_minutes integer not null default 240 check (
    utc_offset_minutes between -720 and 840
    and utc_offset_minutes % 60 = 0
  ),
  -- Ask the terminal to send every stored punch again at its next handshake.
  resend_all_requested boolean not null default false,
  -- The newest attendance stamp the terminal has reported.
  attlog_stamp text check (
    attlog_stamp is null or attlog_stamp ~ '^[0-9]{1,18}$'
  ),
  device_name text check (
    device_name is null or char_length(device_name) <= 80
  ),
  firmware_version text check (
    firmware_version is null or char_length(firmware_version) <= 80
  ),
  push_version text check (
    push_version is null or char_length(push_version) <= 40
  ),
  reported_user_count integer check (
    reported_user_count is null or reported_user_count >= 0
  ),
  reported_punch_count integer check (
    reported_punch_count is null or reported_punch_count >= 0
  ),
  last_remote_ip text check (
    last_remote_ip is null or char_length(last_remote_ip) <= 64
  ),
  first_seen_at timestamptz,
  last_seen_at timestamptz,
  last_handshake_at timestamptz,
  last_punch_received_at timestamptz,
  record_version bigint not null default 1 check (record_version > 0),
  registered_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);
create unique index if not exists v1_workforce_terminals_serial_uidx
  on public.v1_workforce_terminals (serial_number);
create index if not exists v1_workforce_terminals_team_idx
  on public.v1_workforce_terminals (team_id)
  where team_id is not null;

-- The punch log: one row per check-in or check-out, exactly as the terminal
-- reported it. Append-only.
create table if not exists public.v1_workforce_terminal_punches (
  id uuid primary key default gen_random_uuid(),
  terminal_id uuid not null
    references public.v1_workforce_terminals (id) on delete restrict,
  -- The place the terminal served when the punch arrived.
  team_id uuid
    references public.v1_workforce_crew_profiles (team_id) on delete restrict,
  -- The user ID enrolled on the terminal.
  device_user_id text not null check (
    device_user_id ~ '^[0-9A-Za-z]{1,24}$'
  ),
  -- The terminal's own clock, and the same moment in UTC.
  punched_at_local timestamp without time zone not null,
  utc_offset_minutes integer not null,
  punched_at timestamptz not null,
  work_date date not null,
  -- 0 check-in, 1 check-out, 2 break out, 3 break in, 4 overtime in,
  -- 5 overtime out, 255 none.
  punch_state smallint check (punch_state between 0 and 255),
  -- 1 fingerprint, 15 face, 25 palm, and others.
  verify_mode smallint check (verify_mode between 0 and 999),
  work_code text check (work_code is null or char_length(work_code) <= 24),
  -- The time is in the future or before 2020: the terminal's clock was wrong.
  clock_suspect boolean not null default false,
  raw_line text not null check (char_length(raw_line) <= 300),
  received_at timestamptz not null default clock_timestamp(),
  unique (terminal_id, device_user_id, punched_at_local),
  check (work_date = punched_at_local::date)
);
create index if not exists v1_workforce_terminal_punches_day_idx
  on public.v1_workforce_terminal_punches (work_date, device_user_id);
create index if not exists v1_workforce_terminal_punches_received_idx
  on public.v1_workforce_terminal_punches (terminal_id, received_at desc);
create index if not exists v1_workforce_terminal_punches_place_idx
  on public.v1_workforce_terminal_punches (team_id, work_date)
  where team_id is not null;

-- Attendance lines that could not be read, kept as they arrived so nothing a
-- terminal was told "OK" for is lost. A line sent again is kept once.
-- Append-only.
create table if not exists public.v1_workforce_terminal_rejects (
  id uuid primary key default gen_random_uuid(),
  terminal_id uuid not null
    references public.v1_workforce_terminals (id) on delete restrict,
  raw_line text not null check (char_length(raw_line) <= 300),
  truncated boolean not null default false,
  reason text not null check (reason in ('shape', 'user_id', 'time')),
  received_at timestamptz not null default clock_timestamp(),
  unique (terminal_id, raw_line)
);
create index if not exists v1_workforce_terminal_rejects_received_idx
  on public.v1_workforce_terminal_rejects (terminal_id, received_at desc);

-- A short diagnostic log of what terminals asked and what they were told.
-- It holds counts and a fixed list of short facts, never a request body, and
-- is cleared after 30 days.
create table if not exists public.v1_workforce_terminal_requests (
  id bigint generated always as identity primary key,
  received_at timestamptz not null default clock_timestamp(),
  terminal_id uuid
    references public.v1_workforce_terminals (id) on delete restrict,
  serial_number text not null check (char_length(serial_number) <= 40),
  endpoint text not null check (endpoint in (
    'handshake', 'punches', 'data', 'poll', 'command_result', 'ping', 'other'
  )),
  table_name text check (
    table_name is null or table_name ~ '^[A-Za-z0-9_]{1,32}$'
  ),
  outcome text not null check (outcome in (
    'ok', 'receiver_off', 'unknown_terminal', 'inactive_terminal', 'invalid'
  )),
  received_count integer not null default 0 check (received_count >= 0),
  stored_count integer not null default 0 check (stored_count >= 0),
  duplicate_count integer not null default 0 check (duplicate_count >= 0),
  rejected_count integer not null default 0 check (rejected_count >= 0),
  details jsonb not null default '{}'::jsonb
);
create index if not exists v1_workforce_terminal_requests_received_idx
  on public.v1_workforce_terminal_requests (received_at desc);
create index if not exists v1_workforce_terminal_requests_terminal_idx
  on public.v1_workforce_terminal_requests (terminal_id, received_at desc)
  where terminal_id is not null;
create index if not exists v1_workforce_terminal_requests_refused_idx
  on public.v1_workforce_terminal_requests (received_at)
  where outcome <> 'ok';

-- The punch log and the unread lines never change; terminals and the
-- settings row are never deleted (a terminal is switched off instead).
create or replace trigger v1_workforce_terminal_punches_append_only
before update or delete on public.v1_workforce_terminal_punches
for each row execute function public.v1_wf_block_history_mutation();
create or replace trigger v1_workforce_terminal_rejects_append_only
before update or delete on public.v1_workforce_terminal_rejects
for each row execute function public.v1_wf_block_history_mutation();
create or replace trigger v1_workforce_terminals_no_delete
before delete on public.v1_workforce_terminals
for each row execute function public.v1_workforce_block_delete();
create or replace trigger v1_workforce_terminal_settings_no_delete
before delete on public.v1_workforce_terminal_settings
for each row execute function public.v1_workforce_block_delete();

-- All access is through the functions below.
do $lock_tables$
declare
  v_table text;
begin
  foreach v_table in array array[
    'v1_workforce_terminal_settings', 'v1_workforce_terminals',
    'v1_workforce_terminal_punches', 'v1_workforce_terminal_rejects',
    'v1_workforce_terminal_requests'
  ] loop
    execute format('alter table public.%I enable row level security', v_table);
    execute format(
      'revoke all on table public.%I from public, anon, authenticated',
      v_table
    );
  end loop;
end;
$lock_tables$;

-- ---------------------------------------------------------------------------
-- 3. Private pieces of the receiver.
-- ---------------------------------------------------------------------------

-- Whether a terminal may be answered: the receiver is on, the serial number
-- is registered and the terminal is active. Locks the terminal's row.
create or replace function public.v1_wf_terminal_gate(
  p_serial_number text,
  out outcome text,
  out terminal_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_serial text := public.v1_wf_terminal_serial(p_serial_number);
  v_active boolean;
begin
  terminal_id := null;
  if v_serial is null then
    outcome := 'invalid';
    return;
  end if;
  if not coalesce((
    select settings.receiver_enabled
    from public.v1_workforce_terminal_settings settings
    where settings.id
  ), false) then
    outcome := 'receiver_off';
    return;
  end if;
  select terminal.id, terminal.is_active
  into terminal_id, v_active
  from public.v1_workforce_terminals terminal
  where terminal.serial_number = v_serial
  for update;
  if not found then
    terminal_id := null;
    outcome := 'unknown_terminal';
  elsif not v_active then
    outcome := 'inactive_terminal';
  else
    outcome := 'ok';
  end if;
end;
$$;

-- One line in the diagnostic log. Refusals are capped at 200 a day so a
-- stranger calling the address cannot fill it.
create or replace function public.v1_wf_terminal_note(
  p_terminal_id uuid,
  p_serial_number text,
  p_endpoint text,
  p_table_name text,
  p_outcome text,
  p_received integer,
  p_stored integer,
  p_duplicates integer,
  p_rejected integer,
  p_details jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_outcome <> 'ok' and (
    select count(*)
    from public.v1_workforce_terminal_requests request
    where request.outcome <> 'ok'
      and request.received_at > clock_timestamp() - interval '1 day'
  ) >= 200 then
    return;
  end if;
  insert into public.v1_workforce_terminal_requests (
    terminal_id, serial_number, endpoint, table_name, outcome,
    received_count, stored_count, duplicate_count, rejected_count, details
  ) values (
    p_terminal_id,
    left(coalesce(p_serial_number, ''), 40),
    p_endpoint,
    case when p_table_name ~ '^[A-Za-z0-9_]{1,32}$' then p_table_name end,
    p_outcome,
    greatest(coalesce(p_received, 0), 0),
    greatest(coalesce(p_stored, 0), 0),
    greatest(coalesce(p_duplicates, 0), 0),
    greatest(coalesce(p_rejected, 0), 0),
    coalesce(p_details, '{}'::jsonb)
  );
end;
$$;

-- A terminal as the operator functions return it.
create or replace function public.v1_wf_terminal_json(p_terminal_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', terminal.id,
    'serial_number', terminal.serial_number,
    'terminal_name', terminal.terminal_name,
    'place_key', place.place_key,
    'is_active', terminal.is_active,
    'utc_offset_minutes', terminal.utc_offset_minutes,
    'resend_all_requested', terminal.resend_all_requested,
    'device_name', terminal.device_name,
    'firmware_version', terminal.firmware_version,
    'push_version', terminal.push_version,
    'first_seen_at', terminal.first_seen_at,
    'last_seen_at', terminal.last_seen_at,
    'last_handshake_at', terminal.last_handshake_at,
    'last_punch_received_at', terminal.last_punch_received_at,
    'record_version', terminal.record_version
  )
  from public.v1_workforce_terminals terminal
  left join public.v1_workforce_crew_profiles place
    on place.team_id = terminal.team_id
  where terminal.id = p_terminal_id;
$$;

-- ---------------------------------------------------------------------------
-- 4. What the Edge Function calls.
-- ---------------------------------------------------------------------------

-- The handshake: the terminal says who it is and is told how to behave.
create or replace function public.v1_wf_terminal_handshake(
  p_serial_number text,
  p_details jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_serial text := public.v1_wf_terminal_serial(p_serial_number);
  v_details jsonb := public.v1_wf_terminal_details(p_details);
  v_gate record;
  v_terminal public.v1_workforce_terminals%rowtype;
  v_settings public.v1_workforce_terminal_settings%rowtype;
  v_now timestamptz := clock_timestamp();
  v_stamp text;
begin
  select * into v_gate from public.v1_wf_terminal_gate(p_serial_number);
  if v_gate.outcome <> 'ok' then
    if v_gate.outcome <> 'invalid' then
      perform public.v1_wf_terminal_note(
        v_gate.terminal_id, v_serial, 'handshake', null, v_gate.outcome,
        0, 0, 0, 0, v_details
      );
    end if;
    return jsonb_build_object('outcome', v_gate.outcome);
  end if;

  select * into v_terminal
  from public.v1_workforce_terminals terminal
  where terminal.id = v_gate.terminal_id;
  select * into v_settings
  from public.v1_workforce_terminal_settings settings
  where settings.id;

  -- "0" asks for every stored punch again; otherwise the terminal carries on
  -- from the newest stamp it reported ("None": nothing reported yet).
  v_stamp := case
    when v_terminal.resend_all_requested then '0'
    else coalesce(v_terminal.attlog_stamp, 'None')
  end;

  update public.v1_workforce_terminals terminal
  set first_seen_at = coalesce(terminal.first_seen_at, v_now),
      last_seen_at = v_now,
      last_handshake_at = v_now,
      push_version = coalesce(v_details ->> 'push_version', terminal.push_version),
      last_remote_ip = coalesce(v_details ->> 'remote_ip', terminal.last_remote_ip),
      attlog_stamp = case
        when terminal.resend_all_requested then null else terminal.attlog_stamp
      end,
      resend_all_requested = false
  where terminal.id = v_terminal.id;

  perform public.v1_wf_terminal_note(
    v_terminal.id, v_serial, 'handshake', null, 'ok', 0, 0, 0, 0,
    v_details || jsonb_build_object('stamp', v_stamp)
  );

  return jsonb_build_object(
    'outcome', 'ok',
    'serial_number', v_serial,
    'attlog_stamp', v_stamp,
    'poll_seconds', v_settings.poll_seconds,
    'error_delay_seconds', v_settings.error_delay_seconds,
    'realtime', v_settings.realtime,
    'trans_times', v_settings.trans_times,
    'trans_interval_minutes', v_settings.trans_interval_minutes,
    'trans_flag', v_settings.trans_flag,
    'utc_offset_minutes', v_terminal.utc_offset_minutes,
    'extra_option_lines', to_jsonb(v_settings.extra_option_lines)
  );
end;
$$;

-- Attendance lines from a terminal. Each line is {raw, pin, time, state,
-- verify, work_code}. A line already held is counted as a duplicate; a line
-- that cannot be read is kept in v1_workforce_terminal_rejects. The whole
-- call stores or keeps every line, or fails as a whole.
create or replace function public.v1_wf_terminal_punches(
  p_serial_number text,
  p_stamp text,
  p_lines jsonb,
  p_details jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_serial text := public.v1_wf_terminal_serial(p_serial_number);
  v_details jsonb := public.v1_wf_terminal_details(p_details);
  v_gate record;
  v_terminal public.v1_workforce_terminals%rowtype;
  v_now timestamptz := clock_timestamp();
  v_stamp text := case when p_stamp ~ '^[0-9]{1,18}$' then p_stamp end;
  v_received integer := 0;
  v_valid integer := 0;
  v_stored integer := 0;
  v_rejected integer := 0;
  v_future integer := 0;
begin
  select * into v_gate from public.v1_wf_terminal_gate(p_serial_number);
  if v_gate.outcome <> 'ok' then
    if v_gate.outcome <> 'invalid' then
      perform public.v1_wf_terminal_note(
        v_gate.terminal_id, v_serial, 'punches', 'ATTLOG', v_gate.outcome,
        0, 0, 0, 0, v_details
      );
    end if;
    return jsonb_build_object('outcome', v_gate.outcome);
  end if;
  if p_lines is null
    or jsonb_typeof(p_lines) <> 'array'
    or jsonb_array_length(p_lines) > 50000 then
    perform public.v1_wf_terminal_note(
      v_gate.terminal_id, v_serial, 'punches', 'ATTLOG', 'invalid',
      0, 0, 0, 0, v_details
    );
    return jsonb_build_object('outcome', 'invalid');
  end if;

  select * into v_terminal
  from public.v1_workforce_terminals terminal
  where terminal.id = v_gate.terminal_id;
  v_received := jsonb_array_length(p_lines);

  with lines as (
    select
      left(coalesce(item.value ->> 'raw', ''), 300) as raw_line,
      char_length(coalesce(item.value ->> 'raw', '')) > 300 as truncated,
      jsonb_typeof(item.value) = 'object' as is_object,
      item.value ->> 'pin' as pin,
      public.v1_wf_terminal_time(item.value ->> 'time') as local_time,
      public.v1_wf_terminal_int(item.value ->> 'state') as state,
      public.v1_wf_terminal_int(item.value ->> 'verify') as verify,
      nullif(left(coalesce(item.value ->> 'work_code', ''), 24), '')
        as work_code
    from jsonb_array_elements(p_lines) as item(value)
  ),
  judged as (
    select
      lines.*,
      case
        when not lines.is_object then 'shape'
        when lines.pin is null
          or lines.pin !~ '^[0-9A-Za-z]{1,24}$'
          or lines.pin ~ '^0+$' then 'user_id'
        when lines.local_time is null then 'time'
      end as reason,
      (lines.local_time
        - make_interval(mins => v_terminal.utc_offset_minutes))
        at time zone 'UTC' as moment
    from lines
  ),
  stored as (
    insert into public.v1_workforce_terminal_punches (
      terminal_id, team_id, device_user_id, punched_at_local,
      utc_offset_minutes, punched_at, work_date, punch_state, verify_mode,
      work_code, clock_suspect, raw_line, received_at
    )
    select
      v_terminal.id, v_terminal.team_id, judged.pin, judged.local_time,
      v_terminal.utc_offset_minutes, judged.moment, judged.local_time::date,
      case when judged.state between 0 and 255
        then judged.state::smallint end,
      case when judged.verify between 0 and 999
        then judged.verify::smallint end,
      judged.work_code,
      judged.moment > v_now + interval '10 minutes'
        or judged.local_time < timestamp '2020-01-01 00:00:00',
      judged.raw_line, v_now
    from judged
    where judged.reason is null
    on conflict (terminal_id, device_user_id, punched_at_local) do nothing
    returning 1
  ),
  kept as (
    insert into public.v1_workforce_terminal_rejects (
      terminal_id, raw_line, truncated, reason, received_at
    )
    select v_terminal.id, judged.raw_line, judged.truncated, judged.reason,
      v_now
    from judged
    where judged.reason is not null
    on conflict (terminal_id, raw_line) do nothing
    returning 1
  )
  select
    (select count(*) from judged where judged.reason is null),
    (select count(*) from stored),
    (select count(*) from judged where judged.reason is not null),
    (select count(*) from judged
      where judged.reason is null
        and judged.moment > v_now + interval '10 minutes')
  into v_valid, v_stored, v_rejected, v_future;

  -- The stamp only moves forward, and never on a batch whose clock was
  -- ahead: a wrong future stamp would hide later punches.
  update public.v1_workforce_terminals terminal
  set first_seen_at = coalesce(terminal.first_seen_at, v_now),
      last_seen_at = v_now,
      last_punch_received_at = case
        when v_received > 0 then v_now else terminal.last_punch_received_at
      end,
      attlog_stamp = case
        when v_stamp is null or v_future > 0 then terminal.attlog_stamp
        when terminal.attlog_stamp is null
          or v_stamp::numeric > terminal.attlog_stamp::numeric then v_stamp
        else terminal.attlog_stamp
      end,
      last_remote_ip = coalesce(v_details ->> 'remote_ip', terminal.last_remote_ip)
  where terminal.id = v_terminal.id;

  perform public.v1_wf_terminal_note(
    v_terminal.id, v_serial, 'punches', 'ATTLOG', 'ok',
    v_received, v_stored, v_valid - v_stored, v_rejected, v_details
  );

  return jsonb_build_object(
    'outcome', 'ok',
    'received', v_received,
    'stored', v_stored,
    'duplicates', v_valid - v_stored,
    'rejected', v_rejected
  );
end;
$$;

-- Every other call: asking for instructions, a ping, a command result, or a
-- kind of data Yorks does not keep. Marks the terminal as seen.
create or replace function public.v1_wf_terminal_seen(
  p_serial_number text,
  p_endpoint text,
  p_table_name text,
  p_details jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_serial text := public.v1_wf_terminal_serial(p_serial_number);
  v_details jsonb := public.v1_wf_terminal_details(p_details);
  v_endpoint text := case
    when p_endpoint in ('data', 'poll', 'command_result', 'ping', 'other')
      then p_endpoint
    else 'other'
  end;
  v_gate record;
  v_now timestamptz := clock_timestamp();
begin
  select * into v_gate from public.v1_wf_terminal_gate(p_serial_number);
  if v_gate.outcome <> 'ok' then
    if v_gate.outcome <> 'invalid' then
      perform public.v1_wf_terminal_note(
        v_gate.terminal_id, v_serial, v_endpoint, p_table_name,
        v_gate.outcome, 0, 0, 0, 0, v_details
      );
    end if;
    return jsonb_build_object('outcome', v_gate.outcome);
  end if;

  update public.v1_workforce_terminals terminal
  set first_seen_at = coalesce(terminal.first_seen_at, v_now),
      last_seen_at = v_now,
      device_name = coalesce(v_details ->> 'device_name', terminal.device_name),
      firmware_version = coalesce(
        v_details ->> 'firmware_version', terminal.firmware_version
      ),
      reported_user_count = coalesce(
        (v_details ->> 'user_count')::integer, terminal.reported_user_count
      ),
      reported_punch_count = coalesce(
        (v_details ->> 'punch_count')::integer, terminal.reported_punch_count
      ),
      last_remote_ip = coalesce(v_details ->> 'remote_ip', terminal.last_remote_ip)
  where terminal.id = v_gate.terminal_id;

  -- Asking for instructions happens every minute; it is not logged.
  if v_endpoint not in ('poll', 'ping') then
    perform public.v1_wf_terminal_note(
      v_gate.terminal_id, v_serial, v_endpoint, p_table_name, 'ok',
      coalesce((v_details ->> 'line_count')::integer, 0), 0, 0, 0, v_details
    );
  end if;

  return jsonb_build_object('outcome', 'ok');
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Operator functions (SQL editor, service role).
-- ---------------------------------------------------------------------------

-- Switches the receiver on or off for every terminal.
create or replace function public.v1_wf_terminal_receiver(p_enabled boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_settings public.v1_workforce_terminal_settings%rowtype;
begin
  if p_enabled is null then
    raise exception 'V1_WORKFORCE_TERMINAL_INVALID' using errcode = '22023';
  end if;
  update public.v1_workforce_terminal_settings settings
  set receiver_enabled = p_enabled,
      updated_at = clock_timestamp()
  where settings.id
  returning * into v_settings;
  return jsonb_build_object(
    'receiver_enabled', v_settings.receiver_enabled,
    'poll_seconds', v_settings.poll_seconds,
    'error_delay_seconds', v_settings.error_delay_seconds,
    'trans_flag', v_settings.trans_flag,
    'updated_at', v_settings.updated_at
  );
end;
$$;

-- Registers a terminal by its serial number, or renames, moves and
-- re-activates one already registered. p_place_key is an attendance place
-- ("location:workshop", "project:<id>") or null for no place yet.
create or replace function public.v1_wf_register_terminal(
  p_serial_number text,
  p_terminal_name text,
  p_place_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_serial text := public.v1_wf_terminal_serial(p_serial_number);
  v_name text := nullif(btrim(coalesce(p_terminal_name, '')), '');
  v_place text := nullif(lower(btrim(coalesce(p_place_key, ''))), '');
  v_team uuid;
  v_id uuid;
begin
  if v_serial is null then
    raise exception 'V1_WORKFORCE_TERMINAL_SERIAL_INVALID'
      using errcode = '22023';
  end if;
  if v_name is null or char_length(v_name) > 80 then
    raise exception 'V1_WORKFORCE_TERMINAL_NAME_INVALID'
      using errcode = '22023';
  end if;
  if v_place is not null then
    select place.team_id into v_team
    from public.v1_workforce_crew_profiles place
    where place.place_key = v_place and place.is_active;
    if not found then
      raise exception 'V1_WORKFORCE_TERMINAL_PLACE_NOT_FOUND'
        using errcode = '22023';
    end if;
  end if;

  insert into public.v1_workforce_terminals (
    serial_number, terminal_name, team_id
  ) values (v_serial, v_name, v_team)
  on conflict (serial_number) do update
  set terminal_name = excluded.terminal_name,
      team_id = excluded.team_id,
      is_active = true,
      record_version = public.v1_workforce_terminals.record_version + 1,
      updated_at = clock_timestamp()
  returning id into v_id;

  return public.v1_wf_terminal_json(v_id);
end;
$$;

-- Switches one terminal on or off. An inactive terminal is refused and
-- keeps its punches until it is switched on again.
create or replace function public.v1_wf_set_terminal_active(
  p_serial_number text,
  p_is_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_serial text := public.v1_wf_terminal_serial(p_serial_number);
  v_id uuid;
begin
  if v_serial is null or p_is_active is null then
    raise exception 'V1_WORKFORCE_TERMINAL_INVALID' using errcode = '22023';
  end if;
  update public.v1_workforce_terminals terminal
  set is_active = p_is_active,
      record_version = terminal.record_version + 1,
      updated_at = clock_timestamp()
  where terminal.serial_number = v_serial
  returning terminal.id into v_id;
  if v_id is null then
    raise exception 'V1_WORKFORCE_TERMINAL_NOT_FOUND' using errcode = 'P0002';
  end if;
  return public.v1_wf_terminal_json(v_id);
end;
$$;

-- Asks a terminal to send every punch it still holds, at its next handshake
-- (restart it to make that happen now). Punches already held are not stored
-- twice.
create or replace function public.v1_wf_terminal_resend_all(
  p_serial_number text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_serial text := public.v1_wf_terminal_serial(p_serial_number);
  v_id uuid;
begin
  if v_serial is null then
    raise exception 'V1_WORKFORCE_TERMINAL_INVALID' using errcode = '22023';
  end if;
  update public.v1_workforce_terminals terminal
  set resend_all_requested = true,
      updated_at = clock_timestamp()
  where terminal.serial_number = v_serial
  returning terminal.id into v_id;
  if v_id is null then
    raise exception 'V1_WORKFORCE_TERMINAL_NOT_FOUND' using errcode = 'P0002';
  end if;
  return public.v1_wf_terminal_json(v_id);
end;
$$;

-- Clears diagnostic lines older than 30 days. The punch log is never
-- cleared.
create or replace function public.v1_wf_terminal_prune_requests()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from public.v1_workforce_terminal_requests request
  where request.received_at < clock_timestamp() - interval '30 days';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Grants: the service role only.
-- ---------------------------------------------------------------------------

do $grants$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'public.v1_wf_terminal_serial(text)',
    'public.v1_wf_terminal_int(text)',
    'public.v1_wf_terminal_time(text)',
    'public.v1_wf_terminal_option_lines_ok(text[])',
    'public.v1_wf_terminal_details(jsonb)',
    'public.v1_wf_terminal_gate(text)',
    'public.v1_wf_terminal_note(uuid, text, text, text, text, integer, integer, integer, integer, jsonb)',
    'public.v1_wf_terminal_json(uuid)',
    'public.v1_wf_terminal_handshake(text, jsonb)',
    'public.v1_wf_terminal_punches(text, text, jsonb, jsonb)',
    'public.v1_wf_terminal_seen(text, text, text, jsonb)',
    'public.v1_wf_terminal_receiver(boolean)',
    'public.v1_wf_register_terminal(text, text, text)',
    'public.v1_wf_set_terminal_active(text, boolean)',
    'public.v1_wf_terminal_resend_all(text)',
    'public.v1_wf_terminal_prune_requests()'
  ] loop
    execute format(
      'revoke all on function %s from public, anon, authenticated',
      v_signature
    );
  end loop;
  foreach v_signature in array array[
    'public.v1_wf_terminal_handshake(text, jsonb)',
    'public.v1_wf_terminal_punches(text, text, jsonb, jsonb)',
    'public.v1_wf_terminal_seen(text, text, text, jsonb)',
    'public.v1_wf_terminal_receiver(boolean)',
    'public.v1_wf_register_terminal(text, text, text)',
    'public.v1_wf_set_terminal_active(text, boolean)',
    'public.v1_wf_terminal_resend_all(text)'
  ] loop
    execute format(
      'grant execute on function %s to service_role', v_signature
    );
  end loop;
end;
$grants$;

-- Daily at 22:25 UTC (02:25 in Abu Dhabi). A named schedule is idempotent.
do $schedule$
begin
  perform cron.schedule(
    'yorks-workforce-terminal-request-retention', '25 22 * * *',
    'select public.v1_wf_terminal_prune_requests();'
  );
end;
$schedule$;

commit;

notify pgrst, 'reload schema';
