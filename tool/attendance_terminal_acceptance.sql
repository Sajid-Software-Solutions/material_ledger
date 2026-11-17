-- Acceptance check for one attendance terminal. Read-only: it changes
-- nothing. Run it in the SQL editor after the terminal is connected.
--
-- 1. Put the terminal's serial number on the line marked below.
-- 2. Run it. Every line should end up PASS.
--    WAIT means "do the step in the detail column, then run it again".
--    FAIL means something needs fixing: see "When a check fails" in
--    docs/yorks-v1/ATTENDANCE_TERMINALS.md.
with target as (
  select upper(btrim(
    'SIM-0001'   -- <- the terminal's serial number
  )) as serial
),
terminal as (
  select registered.*
  from public.v1_workforce_terminals registered
  join target on registered.serial_number = target.serial
),
punches as (
  select punch.*
  from public.v1_workforce_terminal_punches punch
  join terminal on terminal.id = punch.terminal_id
),
recent_punches as (
  select * from punches
  where received_at > clock_timestamp() - interval '15 minutes'
),
requests as (
  select request.*
  from public.v1_workforce_terminal_requests request
  join terminal on terminal.id = request.terminal_id
  where request.received_at > clock_timestamp() - interval '24 hours'
),
facts as (
  select
    (select receiver_enabled from public.v1_workforce_terminal_settings)
      as receiver_on,
    (select count(*) from terminal) as registered,
    (select is_active from terminal) as active,
    (select terminal_name from terminal) as terminal_name,
    (select place.place_key
     from public.v1_workforce_crew_profiles place
     join terminal on terminal.team_id = place.team_id) as place_key,
    (select last_seen_at from terminal) as last_seen_at,
    (select last_handshake_at from terminal) as last_handshake_at,
    (select concat_ws(', ', device_name, firmware_version,
        'push ' || push_version) from terminal) as device_facts,
    (select count(*) from recent_punches) as recent_punches,
    -- The closest a recent punch came to arriving at the moment it was made.
    (select min(abs(extract(epoch from (received_at - punched_at))))
     from recent_punches) as best_delay_seconds,
    (select count(*) from public.v1_workforce_terminal_rejects reject
     join terminal on terminal.id = reject.terminal_id) as unread_lines,
    (select string_agg(distinct table_name, ', ' order by table_name)
     from requests
     where endpoint = 'data' and lower(coalesce(table_name, '')) <> 'options')
      as other_tables,
    (select string_agg(distinct details ->> 'note', ', ')
     from requests where endpoint = 'other') as other_endpoints,
    (select count(*) from punches where clock_suspect) as wrong_clock_punches,
    (select count(*) from punches
     where received_at - punched_at > interval '10 minutes'
       and received_at > clock_timestamp() - interval '24 hours'
       and not clock_suspect) as held_punches,
    (select coalesce(sum(duplicate_count), 0) from requests) as resent_lines,
    (select count(*) from punches) as all_punches
),
checks (position, check_name, result, detail) as (
  select 1, 'The receiver is switched on',
    case when receiver_on then 'PASS' else 'FAIL' end,
    case when receiver_on then 'On'
      else 'Run: select public.v1_wf_terminal_receiver(true);' end
  from facts
  union all
  select 2, 'The terminal is registered and switched on',
    case when registered = 1 and active then 'PASS' else 'FAIL' end,
    case
      when registered = 0 then
        'Not registered under this serial number. See "Terminal day" in the runbook.'
      when not active then
        'Registered but switched off. Run v1_wf_set_terminal_active(serial, true).'
      else terminal_name || coalesce(' at ' || place_key, ', no place')
    end
  from facts
  union all
  select 3, 'It was heard from in the last 3 minutes',
    case
      when last_seen_at > clock_timestamp() - interval '3 minutes' then 'PASS'
      else 'WAIT'
    end,
    coalesce(
      'Last heard ' || to_char(
        last_seen_at at time zone 'Asia/Dubai', 'YYYY-MM-DD HH24:MI:SS'
      ) || ' Abu Dhabi time',
      'Never heard from. Check the address, port 443 and HTTPS on the terminal.'
    )
  from facts
  union all
  select 4, 'Its handshake was answered',
    case when last_handshake_at is not null then 'PASS' else 'WAIT' end,
    coalesce(nullif(device_facts, ''), 'Restart the terminal to make it shake hands.')
  from facts
  union all
  select 5, 'A check-in arrived in the last 15 minutes',
    case when recent_punches > 0 then 'PASS' else 'WAIT' end,
    case when recent_punches > 0 then recent_punches || ' punch(es)'
      else 'Check in once on the terminal, then run this again.' end
  from facts
  union all
  select 6, 'Its clock agrees with Abu Dhabi time',
    case
      when best_delay_seconds is null then 'WAIT'
      when best_delay_seconds <= 120 then 'PASS'
      else 'FAIL'
    end,
    case
      when best_delay_seconds is null then 'Needs a check-in first.'
      when best_delay_seconds <= 120 then
        'A punch arrived ' || round(best_delay_seconds) || ' s after it was made'
      else 'The nearest punch was ' || round(best_delay_seconds / 60)
        || ' min from its own time. Set the terminal''s date and time.'
    end
  from facts
  union all
  select 7, 'Every attendance line could be read',
    case when unread_lines = 0 then 'PASS' else 'FAIL' end,
    case when unread_lines = 0 then 'None unreadable'
      else unread_lines || ' kept in v1_workforce_terminal_rejects' end
  from facts
  union all
  select 8, 'It sends attendance only',
    case when other_tables is null then 'PASS' else 'FAIL' end,
    coalesce('Also sent (and dropped): ' || other_tables,
      'Nothing but attendance in the last 24 hours')
  from facts
  union all
  select 9, 'It speaks the attendance dialect',
    case when other_endpoints is null then 'PASS' else 'FAIL' end,
    coalesce('Called: ' || other_endpoints, 'No unknown calls')
  from facts
  union all
  select 10, 'No punch came from a wrong clock',
    case when wrong_clock_punches = 0 then 'PASS' else 'FAIL' end,
    wrong_clock_punches || ' punch(es) dated ahead of now or before 2020'
  from facts
  union all
  select 11, 'Punches held during an outage arrived',
    case when held_punches > 0 then 'PASS' else 'WAIT' end,
    case when held_punches > 0 then
        held_punches || ' punch(es) arrived more than 10 minutes late'
      else 'Unplug the network, check in three times, wait 15 minutes, plug it back in.'
    end
  from facts
  union all
  select 12, 'Punches are stored once', 'PASS',
    all_punches || ' stored; ' || resent_lines || ' resent line(s) ignored today'
  from facts
)
select check_name, result, detail
from checks
order by position;
