begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- Attendance terminals: the receiver and the punch log (PRODUCT_DECISIONS
-- section 64). The receiver starts off and answers only registered
-- terminals; punches are stored once and never changed; a line that cannot
-- be read is kept; nothing but attendance lines is stored; signed-in people
-- and visitors reach none of it; and attendance days are never touched.
--
-- Local personas: PE ...0001, SE ...0002, Procurement ...0003, Admin ...0004.
-- Fictional fixtures only.

create function pg_temp.act(p_user uuid, p_role text)
returns void
language plpgsql
as $$
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', p_user, 'role', 'authenticated',
      'app_metadata', jsonb_build_object('role', p_role)
    )::text,
    true
  );
end;
$$;

-- The terminal's clock (Abu Dhabi time), shifted from now.
create function pg_temp.local_text(p_shift interval)
returns text
language sql
as $$
  select to_char(
    (clock_timestamp() at time zone 'Asia/Dubai') + p_shift,
    'YYYY-MM-DD HH24:MI:SS'
  );
$$;

-- One attendance line as the Edge Function hands it on.
create function pg_temp.line(
  p_pin text, p_time text, p_state text, p_verify text
)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'raw', p_pin || E'\t' || p_time || E'\t' || p_state || E'\t' || p_verify
      || E'\t0\t0',
    'pin', p_pin, 'time', p_time, 'state', p_state, 'verify', p_verify,
    'work_code', '0'
  );
$$;

select set_config('at.t1', pg_temp.local_text(interval '-3 hours'), true);
select set_config('at.t2', pg_temp.local_text(interval '-170 minutes'), true);
select set_config('at.t3', pg_temp.local_text(interval '-2 hours'), true);
select set_config('at.t4', pg_temp.local_text(interval '2 hours'), true);
select set_config('at.t5', pg_temp.local_text(interval '-1 hour'), true);
select set_config('at.t6', pg_temp.local_text(interval '-30 minutes'), true);

select set_config('at.sheets_before',
  (select count(*) from public.v1_workforce_day_sheets)::text, true);
select set_config('at.rows_before',
  (select count(*) from public.v1_workforce_day_rows)::text, true);

-- Two attendance places for the terminal to serve.
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000004', 'admin');
select set_config('at.place1',
  public.v1_wf_open_place(null, 'Terminal test yard') ->> 'id', true);
select set_config('at.place2',
  public.v1_wf_open_place(null, 'Terminal test store') ->> 'id', true);
reset role;
select set_config('at.key1', (
  select place_key from public.v1_workforce_crew_profiles
  where team_id = current_setting('at.place1')::uuid
), true);
select set_config('at.key2', (
  select place_key from public.v1_workforce_crew_profiles
  where team_id = current_setting('at.place2')::uuid
), true);

-- Structure -----------------------------------------------------------------

select is(
  (select count(*)::integer from pg_catalog.pg_class
   where relnamespace = 'public'::regnamespace
     and relname in (
       'v1_workforce_terminal_settings', 'v1_workforce_terminals',
       'v1_workforce_terminal_punches', 'v1_workforce_terminal_rejects',
       'v1_workforce_terminal_requests')
     and relrowsecurity),
  5,
  'Every terminal table has row level security on'
);
select ok(
  not exists (
    select 1
    from unnest(array[
      'v1_workforce_terminal_settings', 'v1_workforce_terminals',
      'v1_workforce_terminal_punches', 'v1_workforce_terminal_rejects',
      'v1_workforce_terminal_requests'
    ]) relation,
    unnest(array['anon', 'authenticated']) grantee,
    unnest(array['select', 'insert', 'update', 'delete']) privilege
    where has_table_privilege(grantee, 'public.' || relation, privilege)
  ),
  'Signed-in people and visitors hold no right on any terminal table'
);
select ok(
  not exists (
    select 1
    from unnest(array[
      'public.v1_wf_terminal_serial(text)',
      'public.v1_wf_terminal_int(text)',
      'public.v1_wf_terminal_time(text)',
      'public.v1_wf_terminal_option_lines_ok(text[])',
      'public.v1_wf_terminal_details(jsonb)',
      'public.v1_wf_terminal_gate(text)',
      'public.v1_wf_terminal_note(uuid,text,text,text,text,integer,integer,integer,integer,jsonb)',
      'public.v1_wf_terminal_json(uuid)',
      'public.v1_wf_terminal_handshake(text,jsonb)',
      'public.v1_wf_terminal_punches(text,text,jsonb,jsonb)',
      'public.v1_wf_terminal_seen(text,text,text,jsonb)',
      'public.v1_wf_terminal_receiver(boolean)',
      'public.v1_wf_register_terminal(text,text,text)',
      'public.v1_wf_set_terminal_active(text,boolean)',
      'public.v1_wf_terminal_resend_all(text)',
      'public.v1_wf_terminal_prune_requests()'
    ]) signature,
    unnest(array['anon', 'authenticated']) grantee
    where has_function_privilege(grantee, signature, 'execute')
  ),
  'and may run none of the terminal functions'
);
select ok(
  has_function_privilege('service_role',
    'public.v1_wf_terminal_handshake(text,jsonb)', 'execute')
  and has_function_privilege('service_role',
    'public.v1_wf_terminal_punches(text,text,jsonb,jsonb)', 'execute')
  and has_function_privilege('service_role',
    'public.v1_wf_terminal_seen(text,text,text,jsonb)', 'execute')
  and has_function_privilege('service_role',
    'public.v1_wf_register_terminal(text,text,text)', 'execute'),
  'The service role runs the receiver and registers terminals'
);
select ok(
  exists (
    select 1 from cron.job
    where jobname = 'yorks-workforce-terminal-request-retention'
  ),
  'The diagnostic log is cleared on a schedule'
);

-- Off until switched on -------------------------------------------------------

select is(
  (select receiver_enabled from public.v1_workforce_terminal_settings),
  false,
  'The receiver starts off'
);
select is(
  (select count(*)::integer from public.v1_workforce_terminals), 0,
  'and no terminal is registered'
);

set local role service_role;
select is(
  public.v1_wf_terminal_handshake('SIM-0001', '{}'::jsonb) ->> 'outcome',
  'receiver_off',
  'While the receiver is off a handshake is refused'
);
select is(
  public.v1_wf_terminal_punches('SIM-0001', '1', jsonb_build_array(
    pg_temp.line('418', current_setting('at.t1'), '0', '15')
  ), '{}'::jsonb) ->> 'outcome',
  'receiver_off',
  'and so are punches'
);
reset role;
select is(
  (select count(*)::integer from public.v1_workforce_terminal_punches), 0,
  'Nothing is stored while the receiver is off'
);

-- Registering ---------------------------------------------------------------

set local role service_role;
select throws_ok(
  $$select public.v1_wf_register_terminal('ab', 'Gate')$$,
  '22023', 'V1_WORKFORCE_TERMINAL_SERIAL_INVALID',
  'A serial number that is not one is refused'
);
select throws_ok(
  $$select public.v1_wf_register_terminal('SIM-0001', '   ')$$,
  '22023', 'V1_WORKFORCE_TERMINAL_NAME_INVALID',
  'A terminal needs a name'
);
select throws_ok(
  $$select public.v1_wf_register_terminal('SIM-0001', 'Gate',
      'location:nowhere at all')$$,
  '22023', 'V1_WORKFORCE_TERMINAL_PLACE_NOT_FOUND',
  'A terminal cannot serve a place that is not open'
);
select is(
  public.v1_wf_register_terminal(
    ' sim-0001 ', 'Test gate', current_setting('at.key1')
  ) - 'id',
  jsonb_build_object(
    'serial_number', 'SIM-0001', 'terminal_name', 'Test gate',
    'place_key', current_setting('at.key1'), 'is_active', true,
    -- Every terminal starts watching (PRODUCT_DECISIONS section 65).
    'attendance_mode', 'watch',
    'utc_offset_minutes', 240, 'resend_all_requested', false,
    'device_name', null, 'firmware_version', null, 'push_version', null,
    'first_seen_at', null, 'last_seen_at', null, 'last_handshake_at', null,
    'last_punch_received_at', null, 'record_version', 1
  ),
  'A terminal is registered by serial number for a place, in Abu Dhabi time, watching'
);
select is(
  public.v1_wf_terminal_handshake('SIM-0001', '{}'::jsonb) ->> 'outcome',
  'receiver_off',
  'A registered terminal is still refused while the receiver is off'
);
select is(
  (public.v1_wf_terminal_receiver(true) ->> 'receiver_enabled')::boolean,
  true,
  'The receiver is switched on'
);

-- Who is answered -------------------------------------------------------------

select is(
  public.v1_wf_terminal_handshake('SIM-9999', '{}'::jsonb) ->> 'outcome',
  'unknown_terminal',
  'A terminal that is not registered is refused'
);
select is(
  public.v1_wf_terminal_handshake('not a serial', '{}'::jsonb) ->> 'outcome',
  'invalid',
  'and so is a call without a real serial number'
);
select is(
  (public.v1_wf_set_terminal_active('SIM-0001', false) ->> 'is_active')::boolean,
  false,
  'A terminal can be switched off'
);
select is(
  public.v1_wf_terminal_handshake('SIM-0001', '{}'::jsonb) ->> 'outcome',
  'inactive_terminal',
  'A terminal that is switched off is refused'
);
select is(
  public.v1_wf_terminal_punches('SIM-0001', '1', jsonb_build_array(
    pg_temp.line('418', current_setting('at.t1'), '0', '15')
  ), '{}'::jsonb) ->> 'outcome',
  'inactive_terminal',
  'and its punches are not taken'
);
select throws_ok(
  $$select public.v1_wf_set_terminal_active('SIM-4040', true)$$,
  'P0002', 'V1_WORKFORCE_TERMINAL_NOT_FOUND',
  'A terminal that does not exist cannot be switched'
);
select is(
  (public.v1_wf_set_terminal_active('SIM-0001', true) ->> 'is_active')::boolean,
  true,
  'and switched on again'
);
reset role;
select is(
  (select count(*)::integer from public.v1_workforce_terminal_punches), 0,
  'Nothing was stored for a refused terminal'
);
select is(
  (select array_agg(distinct outcome order by outcome)
   from public.v1_workforce_terminal_requests),
  array['inactive_terminal', 'receiver_off', 'unknown_terminal'],
  'Each refusal is in the diagnostic log; a call with no serial is not'
);

-- The handshake -----------------------------------------------------------------

set local role service_role;
select is(
  public.v1_wf_terminal_handshake('sim-0001', jsonb_build_object(
    'push_version', '2.4.1', 'remote_ip', '203.0.113.7',
    'query_keys', jsonb_build_array('SN', 'options', 'pushver'),
    'body', 'SECRET-BODY'
  )),
  jsonb_build_object(
    'outcome', 'ok', 'serial_number', 'SIM-0001', 'attlog_stamp', 'None',
    'poll_seconds', 60, 'error_delay_seconds', 60, 'realtime', true,
    'trans_times', '00:00;14:05', 'trans_interval_minutes', 1,
    'trans_flag', '100000000000', 'utc_offset_minutes', 240,
    'extra_option_lines', '[]'::jsonb
  ),
  'A registered terminal is told how to behave: attendance only, +4 hours'
);
reset role;
select ok(
  (select first_seen_at is not null and last_handshake_at is not null
     and push_version = '2.4.1' and last_remote_ip = '203.0.113.7'
   from public.v1_workforce_terminals where serial_number = 'SIM-0001'),
  'The handshake marks the terminal as seen'
);
select is(
  (select details from public.v1_workforce_terminal_requests
   where endpoint = 'handshake' and outcome = 'ok'),
  jsonb_build_object(
    'push_version', '2.4.1', 'remote_ip', '203.0.113.7',
    'query_keys', jsonb_build_array('SN', 'options', 'pushver'),
    'stamp', 'None'
  ),
  'The log keeps a fixed list of short facts and nothing else it was sent'
);

-- Punches -----------------------------------------------------------------------

set local role service_role;
select is(
  public.v1_wf_terminal_punches('SIM-0001', '100', jsonb_build_array(
    pg_temp.line('418', current_setting('at.t1'), '0', '15'),
    pg_temp.line('7', current_setting('at.t2'), '255', '1'),
    pg_temp.line('418', current_setting('at.t1'), '0', '15'),
    pg_temp.line('0', current_setting('at.t2'), '0', '15'),
    pg_temp.line('9', '2026-02-30 10:00:00', '0', '15'),
    to_jsonb('not a line'::text)
  ), '{}'::jsonb),
  jsonb_build_object(
    'outcome', 'ok', 'received', 6, 'stored', 2, 'duplicates', 1,
    'rejected', 3
  ),
  'Punches are stored once; lines that cannot be read are counted'
);
reset role;
select is(
  (select jsonb_agg(jsonb_build_object(
      'user', device_user_id, 'state', punch_state, 'verify', verify_mode,
      'place', team_id, 'offset', utc_offset_minutes, 'suspect', clock_suspect,
      'day_matches', work_date = punched_at_local::date,
      'utc_matches', punched_at
        = (punched_at_local - interval '4 hours') at time zone 'UTC'
    ) order by device_user_id)
   from public.v1_workforce_terminal_punches),
  jsonb_build_array(
    jsonb_build_object(
      'user', '418', 'state', 0, 'verify', 15,
      'place', current_setting('at.place1'), 'offset', 240, 'suspect', false,
      'day_matches', true, 'utc_matches', true),
    jsonb_build_object(
      'user', '7', 'state', 255, 'verify', 1,
      'place', current_setting('at.place1'), 'offset', 240, 'suspect', false,
      'day_matches', true, 'utc_matches', true)
  ),
  'Each punch keeps the terminal user, the time in both clocks and the place'
);
select is(
  (select punched_at_local::text from public.v1_workforce_terminal_punches
   where device_user_id = '418'),
  current_setting('at.t1'),
  'The time is exactly what the terminal reported'
);
select is(
  (select array_agg(reason order by reason)
   from public.v1_workforce_terminal_rejects),
  array['shape', 'time', 'user_id'],
  'A line that cannot be read is kept, with why'
);
select is(
  (select raw_line from public.v1_workforce_terminal_rejects
   where reason = 'time'),
  E'9\t2026-02-30 10:00:00\t0\t15\t0\t0',
  'exactly as it arrived'
);

set local role service_role;
select is(
  public.v1_wf_terminal_punches('SIM-0001', '100', jsonb_build_array(
    pg_temp.line('418', current_setting('at.t1'), '0', '15'),
    pg_temp.line('7', current_setting('at.t2'), '255', '1'),
    pg_temp.line('418', current_setting('at.t1'), '0', '15'),
    pg_temp.line('0', current_setting('at.t2'), '0', '15'),
    pg_temp.line('9', '2026-02-30 10:00:00', '0', '15'),
    to_jsonb('not a line'::text)
  ), '{}'::jsonb),
  jsonb_build_object(
    'outcome', 'ok', 'received', 6, 'stored', 0, 'duplicates', 3,
    'rejected', 3
  ),
  'The same lines sent again store nothing new'
);
reset role;
select is(
  (select count(*)::integer from public.v1_workforce_terminal_punches), 2,
  'A resend leaves the punch log as it was'
);
select is(
  (select count(*)::integer from public.v1_workforce_terminal_rejects), 3,
  'and the unread lines too'
);

set local role service_role;
select is(
  public.v1_wf_terminal_punches('SIM-0001', '5', '[]'::jsonb, '{}'::jsonb),
  jsonb_build_object(
    'outcome', 'ok', 'received', 0, 'stored', 0, 'duplicates', 0,
    'rejected', 0
  ),
  'An empty upload is accepted'
);
select is(
  public.v1_wf_terminal_punches('SIM-0001', '5', '{"not": "a list"}'::jsonb,
    '{}'::jsonb) ->> 'outcome',
  'invalid',
  'Something that is not a list of lines is refused'
);
reset role;

-- The stamp ----------------------------------------------------------------------

select is(
  (select attlog_stamp from public.v1_workforce_terminals
   where serial_number = 'SIM-0001'),
  '100',
  'The terminal''s newest stamp is remembered'
);
set local role service_role;
select is(
  public.v1_wf_terminal_punches('SIM-0001', '50', jsonb_build_array(
    pg_temp.line('12', current_setting('at.t3'), '1', '15')
  ), '{}'::jsonb) ->> 'stored',
  '1',
  'A later punch with an older stamp is stored'
);
select is(
  public.v1_wf_terminal_punches('SIM-0001', 'None', jsonb_build_array(
    pg_temp.line('13', current_setting('at.t3'), '1', '15')
  ), '{}'::jsonb) ->> 'stored',
  '1',
  'and so is one with no stamp'
);
select is(
  public.v1_wf_terminal_punches('SIM-0001', '900', jsonb_build_array(
    pg_temp.line('14', current_setting('at.t4'), '0', '15'),
    pg_temp.line('15', '2019-12-31 23:59:59', '0', '15')
  ), '{}'::jsonb) ->> 'stored',
  '2',
  'A punch from a wrong clock is still stored'
);
reset role;
select is(
  (select attlog_stamp from public.v1_workforce_terminals
   where serial_number = 'SIM-0001'),
  '100',
  'The stamp never goes back, and never follows a clock that was ahead'
);
select is(
  (select array_agg(device_user_id order by device_user_id)
   from public.v1_workforce_terminal_punches where clock_suspect),
  array['14', '15'],
  'Punches dated ahead of now or before 2020 are marked as a wrong clock'
);
set local role service_role;
select is(
  public.v1_wf_terminal_punches('SIM-0001', '200', jsonb_build_array(
    pg_temp.line('16', current_setting('at.t5'), '1', '25')
  ), '{}'::jsonb) ->> 'stored',
  '1',
  'A normal punch with a newer stamp is stored'
);
select is(
  public.v1_wf_terminal_handshake('SIM-0001', '{}'::jsonb) ->> 'attlog_stamp',
  '200',
  'The next handshake carries on from the newest stamp'
);
select is(
  (public.v1_wf_terminal_resend_all('SIM-0001') ->> 'resend_all_requested')::boolean,
  true,
  'An operator can ask for everything again'
);
select is(
  public.v1_wf_terminal_handshake('SIM-0001', '{}'::jsonb) ->> 'attlog_stamp',
  '0',
  'The next handshake asks the terminal to send every punch'
);
select is(
  public.v1_wf_terminal_handshake('SIM-0001', '{}'::jsonb) ->> 'attlog_stamp',
  'None',
  'once'
);
select throws_ok(
  $$select public.v1_wf_terminal_resend_all('SIM-4040')$$,
  'P0002', 'V1_WORKFORCE_TERMINAL_NOT_FOUND',
  'A terminal that does not exist cannot be asked'
);

-- Everything that is not attendance ----------------------------------------------

select is(
  public.v1_wf_terminal_seen('SIM-0001', 'poll', null, jsonb_build_object(
    'info', 'Ver 8.0.4.2-20200710,107,0,3520,192.168.1.201',
    'firmware_version', 'Ver 8.0.4.2-20200710',
    'user_count', 107, 'punch_count', 3520
  )) ->> 'outcome',
  'ok',
  'Asking for instructions is answered'
);
select is(
  public.v1_wf_terminal_seen('SIM-0001', 'data', 'OPERLOG',
    jsonb_build_object(
      'line_count', 3,
      'line_kinds', jsonb_build_object('USER', 1, 'FP', 2, 'bad kind!', 9),
      'body', 'FP PIN=418 TMP=SECRETTEMPLATE',
      'TMP', 'SECRETTEMPLATE',
      'note', repeat('n', 500)
    )) ->> 'outcome',
  'ok',
  'Data Yorks does not keep is acknowledged'
);
select is(
  public.v1_wf_terminal_seen('SIM-0001', 'handshake', 'x y', '{}'::jsonb)
    ->> 'outcome',
  'ok',
  'A call of an unexpected kind is recorded as other'
);
select is(
  public.v1_wf_terminal_seen('SIM-9999', 'poll', null, '{}'::jsonb)
    ->> 'outcome',
  'unknown_terminal',
  'An unregistered terminal gets no instructions'
);
reset role;
select ok(
  (select firmware_version = 'Ver 8.0.4.2-20200710'
     and reported_user_count = 107 and reported_punch_count = 3520
   from public.v1_workforce_terminals where serial_number = 'SIM-0001'),
  'The terminal''s firmware and counts are noted'
);
select is(
  (select count(*)::integer from public.v1_workforce_terminal_requests
   where endpoint = 'poll' and outcome = 'ok'),
  0,
  'Asking for instructions is not logged'
);
select is(
  (select details - 'note' from public.v1_workforce_terminal_requests
   where endpoint = 'data'),
  jsonb_build_object(
    'line_count', 3, 'line_kinds', jsonb_build_object('USER', 1, 'FP', 2)
  ),
  'Other data is logged as counts by kind'
);
select is(
  (select char_length(details ->> 'note')
   from public.v1_workforce_terminal_requests where endpoint = 'data'),
  200,
  'and long facts are cut short'
);
select ok(
  not exists (
    select 1 from public.v1_workforce_terminal_requests
    where details::text like '%SECRET%'
  )
  and not exists (
    select 1 from public.v1_workforce_terminal_punches
    where raw_line like '%SECRET%'
  ),
  'A fingerprint or face that was sent is nowhere in the database'
);
select is(
  (select jsonb_build_object('endpoint', endpoint, 'table', table_name)
   from public.v1_workforce_terminal_requests
   where endpoint = 'other' and outcome = 'ok'),
  jsonb_build_object('endpoint', 'other', 'table', null),
  'A table name that is not one is not kept'
);

-- Moving a terminal ----------------------------------------------------------------

set local role service_role;
select is(
  public.v1_wf_register_terminal(
    'SIM-0001', 'Store gate', current_setting('at.key2')
  ) - array['id', 'first_seen_at', 'last_seen_at', 'last_handshake_at',
    'last_punch_received_at'],
  jsonb_build_object(
    'serial_number', 'SIM-0001', 'terminal_name', 'Store gate',
    'place_key', current_setting('at.key2'), 'is_active', true,
    'attendance_mode', 'watch',
    'utc_offset_minutes', 240, 'resend_all_requested', false,
    'device_name', null, 'firmware_version', 'Ver 8.0.4.2-20200710',
    'push_version', '2.4.1',
    -- Registered, switched off, switched on, moved.
    'record_version', 4
  ),
  'Registering again renames and moves a terminal, and counts each change'
);
select is(
  public.v1_wf_terminal_punches('SIM-0001', '300', jsonb_build_array(
    pg_temp.line('418', current_setting('at.t6'), '1', '15')
  ), '{}'::jsonb) ->> 'stored',
  '1',
  'A punch after the move is stored'
);
reset role;
select is(
  (select jsonb_object_agg(team_id, punches) from (
     select team_id, count(*) as punches
     from public.v1_workforce_terminal_punches group by team_id
   ) by_place),
  jsonb_build_object(
    current_setting('at.place1'), 7, current_setting('at.place2'), 1
  ),
  'Earlier punches keep the place they were made at'
);
select is(
  (select count(*)::integer from public.v1_workforce_terminals), 1,
  'and the terminal is still one terminal'
);

-- The log never changes ------------------------------------------------------------

select throws_ok(
  $$update public.v1_workforce_terminal_punches set work_code = 'x'$$,
  '42501', 'V1_WORKFORCE_HISTORY_APPEND_ONLY',
  'A punch cannot be changed'
);
select throws_ok(
  $$delete from public.v1_workforce_terminal_punches$$,
  '42501', 'V1_WORKFORCE_HISTORY_APPEND_ONLY',
  'or removed'
);
select throws_ok(
  $$delete from public.v1_workforce_terminal_rejects$$,
  '42501', 'V1_WORKFORCE_HISTORY_APPEND_ONLY',
  'An unread line cannot be removed'
);
select throws_ok(
  $$delete from public.v1_workforce_terminals$$,
  '42501', 'V1_WORKFORCE_HISTORY_DELETE_FORBIDDEN',
  'A terminal is switched off, never deleted'
);
select throws_ok(
  $$delete from public.v1_workforce_terminal_settings$$,
  '42501', 'V1_WORKFORCE_HISTORY_DELETE_FORBIDDEN',
  'The settings row cannot be deleted'
);

-- Settings -------------------------------------------------------------------------

select throws_ok(
  $$update public.v1_workforce_terminal_settings set poll_seconds = 1$$,
  '23514', null,
  'A terminal cannot be told to ask every second'
);
select throws_ok(
  $$update public.v1_workforce_terminal_settings
    set extra_option_lines = array['not an option']$$,
  '23514', null,
  'An extra handshake line must be Key=Value'
);
select throws_ok(
  $$insert into public.v1_workforce_terminal_settings (id) values (false)$$,
  '23514', null,
  'There is one settings row'
);
update public.v1_workforce_terminal_settings
set poll_seconds = 120, extra_option_lines = array['ServerVer=2.4.1'];
set local role service_role;
select is(
  jsonb_build_object(
    'poll', public.v1_wf_terminal_handshake('SIM-0001', '{}'::jsonb)
      -> 'poll_seconds',
    'extra', public.v1_wf_terminal_handshake('SIM-0001', '{}'::jsonb)
      -> 'extra_option_lines'
  ),
  jsonb_build_object(
    'poll', 120, 'extra', jsonb_build_array('ServerVer=2.4.1')
  ),
  'A changed setting reaches the next handshake'
);
reset role;

-- Helpers ---------------------------------------------------------------------------

select is(
  array[
    public.v1_wf_terminal_time('2026-11-17 06:31:05'),
    public.v1_wf_terminal_time('2028-02-29 23:59:59'),
    public.v1_wf_terminal_time('2026-02-29 10:00:00'),
    public.v1_wf_terminal_time('2026-13-01 10:00:00'),
    public.v1_wf_terminal_time('2026-11-17 24:00:00'),
    public.v1_wf_terminal_time('2026-11-17 10:60:00'),
    public.v1_wf_terminal_time('2026-11-17T10:00:00'),
    public.v1_wf_terminal_time('17/11/2026 10:00'),
    public.v1_wf_terminal_time(null)
  ],
  array[
    timestamp '2026-11-17 06:31:05', timestamp '2028-02-29 23:59:59',
    null, null, null, null, null, null, null
  ]::timestamp[],
  'Only a real date and time is read as one'
);
select is(
  array[
    public.v1_wf_terminal_serial(' cgxh201260122 '),
    public.v1_wf_terminal_serial('abc'),
    public.v1_wf_terminal_serial('A1B2'';--'),
    public.v1_wf_terminal_serial(null)
  ],
  array['CGXH201260122', null, null, null],
  'Only a real serial number is read as one'
);

-- The refusal cap and the clean-up --------------------------------------------------

set local role service_role;
select is(
  (select count(*)::integer from generate_series(1, 250) n
   where public.v1_wf_terminal_handshake(
     'SIM-' || (5000 + n)::text, '{}'::jsonb) ->> 'outcome'
     = 'unknown_terminal'),
  250,
  'A stranger is refused every time'
);
reset role;
select is(
  (select count(*)::integer from public.v1_workforce_terminal_requests
   where outcome <> 'ok'),
  200,
  'but cannot fill the diagnostic log'
);
insert into public.v1_workforce_terminal_requests (
  received_at, serial_number, endpoint, outcome
) values (
  clock_timestamp() - interval '40 days', 'OLD-0001', 'handshake', 'ok'
);
select is(
  public.v1_wf_terminal_prune_requests(), 1,
  'Diagnostic lines older than 30 days are cleared'
);
select is(
  (select count(*)::integer from public.v1_workforce_terminal_punches), 8,
  'and the punch log is not'
);

-- Signed-in people and visitors ------------------------------------------------------

set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select throws_ok(
  $$select count(*) from public.v1_workforce_terminal_punches$$,
  '42501', null, 'A Project Engineer cannot read the punch log'
);
select throws_ok(
  $$select public.v1_wf_terminal_punches('SIM-0001', '1', '[]'::jsonb,
      '{}'::jsonb)$$,
  '42501', null, 'or send punches'
);
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select throws_ok(
  $$select count(*) from public.v1_workforce_terminals$$,
  '42501', null, 'A Site Engineer cannot read the terminals'
);
select throws_ok(
  $$select public.v1_wf_terminal_handshake('SIM-0001', '{}'::jsonb)$$,
  '42501', null, 'or pose as one'
);
select pg_temp.act('10000000-0000-4000-8000-000000000003', 'procurement');
select throws_ok(
  $$select count(*) from public.v1_workforce_terminal_requests$$,
  '42501', null, 'Procurement cannot read the diagnostic log'
);
select throws_ok(
  $$select public.v1_wf_register_terminal('SIM-0002', 'Mine')$$,
  '42501', null, 'or register a terminal'
);
select pg_temp.act('10000000-0000-4000-8000-000000000004', 'admin');
select throws_ok(
  $$select count(*) from public.v1_workforce_terminal_punches$$,
  '42501', null, 'Admin cannot read the punch log from the app yet'
);
select throws_ok(
  $$insert into public.v1_workforce_terminal_punches (
      terminal_id, device_user_id, punched_at_local, utc_offset_minutes,
      punched_at, work_date, raw_line)
    select id, '418', timestamp '2026-11-01 06:30:00', 240,
      timestamptz '2026-11-01 02:30:00+00', date '2026-11-01', 'forged'
    from public.v1_workforce_terminals$$,
  '42501', null, 'or write a punch by hand'
);
select throws_ok(
  $$select public.v1_wf_terminal_receiver(false)$$,
  '42501', null, 'or switch the receiver'
);
select throws_ok(
  $$select public.v1_wf_set_terminal_active('SIM-0001', false)$$,
  '42501', null, 'or switch a terminal'
);
reset role;
set local role anon;
select throws_ok(
  $$select count(*) from public.v1_workforce_terminal_punches$$,
  '42501', null, 'A visitor cannot read the punch log'
);
select throws_ok(
  $$select public.v1_wf_terminal_punches('SIM-0001', '1', '[]'::jsonb,
      '{}'::jsonb)$$,
  '42501', null, 'or send punches'
);
reset role;

-- Attendance is untouched -------------------------------------------------------------

select is(
  (select count(*)::text from public.v1_workforce_day_sheets),
  current_setting('at.sheets_before'),
  'No attendance day was created or removed'
);
select is(
  (select count(*)::text from public.v1_workforce_day_rows),
  current_setting('at.rows_before'),
  'and no attendance line'
);

select * from finish();
rollback;
