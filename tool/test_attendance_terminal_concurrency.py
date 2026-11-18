#!/usr/bin/env python3
"""Race real terminal uploads against real saves of the same attendance day.

pgTAP runs in one session, so it can only prove the order of events. This
runs separate database sessions at the same time and checks what
PRODUCT_DECISIONS section 65 promises:

  1. while a person's save holds a day, a terminal's check-in waits, then
     decides on what the person saved (no second line);
  2. while a terminal's check-in holds a day, a person's save from an app
     that has not seen the terminal's line waits, then goes through with no
     version conflict and keeps that line;
  3. a save that holds a day for more than two seconds does not hold the
     terminal: the check-in is stored, the terminal is answered, and the line
     is added with the terminal's next upload;
  4. under load, a terminal never makes a lone keeper's save conflict, no
     line is lost or doubled, the day's version counts only people's saves,
     and nothing deadlocks.

Local throwaway database only. The fixtures are committed and cannot be
deleted (attendance and terminal rows are never hard-deleted), so use a
private stack and reset it afterwards:

    python3 tool/test_attendance_terminal_concurrency.py supabase_db_<project_id>
"""
import concurrent.futures
import json
import random
import subprocess
import sys
import threading
import time
import uuid

ADMIN = '10000000-0000-4000-8000-000000000004'
CLAIMS = json.dumps({
    'sub': ADMIN, 'role': 'authenticated', 'app_metadata': {'role': 'admin'},
})
PROJECT = '7b010000-0000-4000-8000-000000000001'
SHARED_CONTAINER = 'supabase_db_material_ledger'

ROWS_AS_THE_APP_SENDS = """(
  select coalesce(jsonb_agg(jsonb_build_object(
    'worker_id', e -> 'worker_id', 'status', e -> 'status',
    'start_minute', e -> 'start_minute',
    'break_start_minute', e -> 'break_start_minute',
    'break_finish_minute', e -> 'break_finish_minute',
    'finish_minute', e -> 'finish_minute',
    'work_project_id', e -> 'work_project_id', 'work_label', e -> 'work_label',
    'work_scope_id', e -> 'work_scope_id',
    'overtime_note', e -> 'overtime_note', 'copied', e -> 'copied'
  )), '[]'::jsonb)
  from jsonb_array_elements(
    public.v1_wf_get_day('{team}'::uuid, '{day}'::date) -> 'rows') e
)"""


def literal(value):
    return "'" + value.replace("'", "''") + "'"


def worker(number):
    return f'7b020000-0000-4000-8000-0000000000{number:02d}'


def pin(number):
    return f'9200{number:02d}'


class Database:
    def __init__(self, container):
        self.container = container

    def run(self, sql):
        return subprocess.run(
            ['docker', 'exec', '-i', self.container, 'psql', '-U', 'postgres',
             '-d', 'postgres', '-X', '-t', '-A', '-v', 'ON_ERROR_STOP=1'],
            input=sql, text=True, capture_output=True, check=False,
        )

    def value(self, sql):
        result = self.run(sql)
        assert result.returncode == 0, result.stderr
        return result.stdout.strip()


def as_admin(body, hold=0.0):
    return (
        'begin; set local role authenticated; '
        f"select set_config('request.jwt.claims', {literal(CLAIMS)}, true); "
        f'{body}; '
        + (f'reset role; select pg_sleep({hold}); ' if hold else '')
        + 'commit;'
    )


def upload(serial, punches):
    lines = [{
        'raw': f'{user}\t{at}\t0\t15\t0\t0', 'pin': user, 'time': at,
        'state': '0', 'verify': '15', 'work_code': '0',
    } for user, at in punches]
    return (
        f"select public.v1_wf_terminal_punches({literal(serial)}, null, "
        f"{literal(json.dumps(lines))}::jsonb, '{{}}'::jsonb)"
    )


def together(first, second, delay=0.8):
    """Starts `first`, then `second` after `delay`; returns results, seconds."""
    def timed(action, wait):
        time.sleep(wait)
        started = time.monotonic()
        result = action()
        return result, time.monotonic() - started

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        one = pool.submit(timed, first, 0.0)
        two = pool.submit(timed, second, delay)
        return one.result(), two.result()


def main():
    if len(sys.argv) != 2 or sys.argv[1] == SHARED_CONTAINER:
        sys.exit(__doc__)
    db = Database(sys.argv[1])
    if db.value(f"select count(*) from public.v1_projects where id = '{PROJECT}'") != '0':
        sys.exit('This database already holds the fixtures: reset it first.')

    day = db.value("""
        select series.day_ts::date
        from generate_series(public.v1_wf_today() - 6, public.v1_wf_today() - 1,
          interval '1 day') series(day_ts)
        where public.v1_wf_day_type(series.day_ts::date) = 'work'
        order by series.day_ts desc limit 1""")
    assert day, 'no working day in the last six'

    matches = json.dumps([
        {'device_user_id': pin(n), 'worker_id': worker(n)} for n in range(1, 31)
    ])
    fixture = db.run(f"""
        begin;
        insert into public.v1_projects (id, project_ref, name, state,
          current_action_owner_role, created_by_auth_user_id, created_by_role)
        values ('{PROJECT}', 'TR-001', 'Terminal race', 'active',
          'project_engineer', '{ADMIN}', 'admin');
        insert into public.v1_project_scopes (id, project_id, scope_kind,
          scope_code, name, is_immutable)
        values ('7b050000-0000-4000-8000-000000000001', '{PROJECT}', 'common',
          'common', 'Common / All Buildings', true);
        insert into public.v1_workforce_workers (id, worker_number, full_name,
          designation, employer_company, worker_type, joining_date,
          created_by_auth_user_id, updated_by_auth_user_id)
        select ('7b020000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
          'TR-9200' || lpad(n::text, 2, '0'), 'Race Labourer ' || n, 'Helper',
          'Example Manpower LLC', 'agency_worker', date '2025-01-01',
          '{ADMIN}', '{ADMIN}'
        from generate_series(1, 30) n;
        set local role authenticated;
        select set_config('request.jwt.claims', {literal(CLAIMS)}, true);
        select public.v1_wf_open_place('{PROJECT}', null) ->> 'id';
        select public.v1_wf_confirm_terminal_users({literal(matches)}::jsonb,
          gen_random_uuid()) is not null;
        reset role;
        select public.v1_wf_terminal_receiver(true) is not null;
        select public.v1_wf_register_terminal('RACE-0001', 'Race gate one',
          'project:{PROJECT}') is not null;
        select public.v1_wf_register_terminal('RACE-0002', 'Race gate two',
          'project:{PROJECT}') is not null;
        select public.v1_wf_set_terminal_mode('RACE-0001', 'add') is not null;
        select public.v1_wf_set_terminal_mode('RACE-0002', 'add') is not null;
        commit;""")
    assert fixture.returncode == 0, fixture.stderr
    team = db.value(f"""select team_id from public.v1_workforce_crew_profiles
        where place_key = 'project:{PROJECT}'""")
    rows_sql = ROWS_AS_THE_APP_SENDS.format(team=team, day=day)

    def line(number):
        return db.value(f"""
            select coalesce(updated_by_auth_user_id::text, 'terminal') || ' '
              || start_minute || '-' || finish_minute
            from public.v1_workforce_day_rows
            where team_id = '{team}' and work_date = '{day}'
              and worker_id = '{worker(number)}'""")

    def finding(number, serial='RACE-0001'):
        return db.value(f"""
            select day.finding || ' ' || day.added
            from public.v1_workforce_terminal_days day
            join public.v1_workforce_terminals terminal
              on terminal.id = day.terminal_id
            where terminal.serial_number = '{serial}'
              and day.work_date = '{day}' and day.device_user_id = '{pin(number)}'""")

    def version():
        return db.value(f"""select record_version from public.v1_workforce_day_sheets
            where team_id = '{team}' and work_date = '{day}'""")

    def save(extra_row, expected, hold=0.0):
        return as_admin(
            f"select public.v1_wf_save_day('{team}', '{day}', {rows_sql} || "
            f"{literal(json.dumps([extra_row]))}::jsonb, {expected}, null, "
            f"gen_random_uuid()) is not null", hold)

    def hand_row(number, start, finish):
        return {'worker_id': worker(number), 'status': 'P',
                'start_minute': start, 'finish_minute': finish}

    # 1. A person's save holds the day; the terminal waits, then decides.
    (saved, _), (punched, waited) = together(
        lambda: db.run(save(hand_row(1, 420, 900), 0, hold=1.8)),
        lambda: db.run(upload('RACE-0001', [
            (pin(1), f'{day} 06:20:00'), (pin(2), f'{day} 06:21:00')])))
    assert saved.returncode == 0, saved.stderr
    assert punched.returncode == 0, punched.stderr
    assert json.loads(punched.stdout)['stored'] == 2, punched.stdout
    assert waited > 0.5, f'the terminal did not wait for the save ({waited:.2f}s)'
    assert line(1) == f'{ADMIN} 420-900', line(1)
    assert finding(1) == 'on_day false', finding(1)
    assert line(2) == 'terminal 390-870', line(2)
    assert finding(2) == 'add true', finding(2)
    assert version() == '1', version()
    print(f'1 ok: the terminal waited {waited:.2f}s for the save, then added '
          'only the labourer who was not on the day')

    # 2. A terminal's check-in holds the day; a save from an app that has not
    #    seen its line waits, then goes through and keeps the line.
    (punched, _), (saved, waited) = together(
        lambda: db.run('begin; ' + upload('RACE-0001', [(pin(3), f'{day} 06:22:00')])
                       + '; select pg_sleep(1.8); commit;'),
        lambda: db.run(save(hand_row(4, 390, 870), 1)))
    assert punched.returncode == 0, punched.stderr
    assert saved.returncode == 0, saved.stderr
    assert waited > 0.5, f'the save did not wait for the terminal ({waited:.2f}s)'
    assert version() == '2', version()
    assert line(3) == 'terminal 390-870', line(3)
    assert line(4) == f'{ADMIN} 390-870', line(4)
    assert line(2) == 'terminal 390-870', line(2)
    print(f'2 ok: the save waited {waited:.2f}s for the terminal, did not '
          'conflict and kept the line it had not seen')

    # 3. A save that holds the day for 4.5 seconds does not hold the terminal.
    (saved, _), (punched, waited) = together(
        lambda: db.run(save(hand_row(25, 390, 870), 2, hold=4.5)),
        lambda: db.run(upload('RACE-0001', [(pin(5), f'{day} 06:23:00')])))
    assert saved.returncode == 0, saved.stderr
    assert punched.returncode == 0, punched.stderr
    assert json.loads(punched.stdout) == {
        'outcome': 'ok', 'received': 1, 'stored': 1, 'duplicates': 0,
        'rejected': 0}, punched.stdout
    assert 1.5 < waited < 3.4, f'the terminal was held {waited:.2f}s'
    assert finding(5) == 'error false', finding(5)
    assert line(5) == '', line(5)
    retried = db.run(upload('RACE-0001', [(pin(6), f'{day} 06:24:00')]))
    assert retried.returncode == 0, retried.stderr
    assert finding(5) == 'add true', finding(5)
    assert line(5) == 'terminal 390-870', line(5)
    assert line(6) == 'terminal 390-870', line(6)
    assert version() == '3', version()
    print(f'3 ok: the terminal was answered after {waited:.2f}s with its '
          'check-in stored; the line was added with its next upload')

    # 4. Load: two terminals and people saving the same day.
    log_from = time.strftime('%Y-%m-%dT%H:%M:%S')
    random.seed(65)

    def terminal_session(serial, count):
        statements = []
        for _ in range(count):
            number = random.randint(7, 24)
            at = (f'{day} {random.randint(5, 13):02d}:{random.randint(0, 59):02d}:'
                  f'{random.randint(0, 59):02d}')
            statements.append(upload(serial, [(pin(number), at)]) + " ->> 'outcome';")
        return db.run('\n'.join(statements))

    def keeper_session(count, keeper):
        block = f"""
            do $keeper$
            declare
              v_day jsonb;
              v_rows jsonb;
            begin
              perform set_config('request.jwt.claims', {literal(CLAIMS)}, true);
              v_day := public.v1_wf_get_day('{team}'::uuid, '{day}'::date);
              select jsonb_agg(case
                when entry ->> 'worker_id' = '{worker(1)}' then entry
                  || jsonb_build_object('finish_minute',
                    900 + (random() * 30)::integer)
                else entry end)
              into v_rows
              from jsonb_array_elements({rows_sql}) entry;
              perform public.v1_wf_save_day('{team}'::uuid, '{day}'::date,
                v_rows, (v_day ->> 'record_version')::bigint, null,
                gen_random_uuid());
              raise notice 'SAVED {keeper}';
            exception when serialization_failure then
              raise notice 'CONFLICT {keeper}';
            end;
            $keeper$;"""
        return db.run('set role authenticated;\n' + block * count)

    def load(keepers, saves, punches):
        with concurrent.futures.ThreadPoolExecutor(max_workers=keepers + 4) as pool:
            terminals = [
                pool.submit(terminal_session, serial, punches)
                for serial in ('RACE-0001', 'RACE-0002', 'RACE-0001', 'RACE-0002')]
            people = [
                pool.submit(keeper_session, saves, index)
                for index in range(keepers)]
            for future in terminals:
                result = future.result()
                assert result.returncode == 0, result.stderr
                outcomes = set(result.stdout.split())
                assert outcomes == {'ok'}, outcomes
            notices = ''
            for future in people:
                result = future.result()
                assert result.returncode == 0, result.stderr
                notices += result.stderr
            return notices.count('SAVED'), notices.count('CONFLICT')

    before = int(version())
    saved_count, conflicts = load(keepers=1, saves=40, punches=50)
    assert conflicts == 0, f'{conflicts} saves conflicted with only terminals writing'
    assert saved_count == 40, saved_count
    assert int(version()) == before + 40, version()
    print(f'4a ok: 200 check-ins on two terminals while one keeper saved the '
          f'day 40 times: no conflict, version {before} -> {version()}')

    before = int(version())
    saved_count, conflicts = load(keepers=3, saves=25, punches=50)
    assert int(version()) == before + saved_count, (version(), before, saved_count)
    print(f'4b ok: 200 more check-ins while three keepers saved: {saved_count} '
          f'saves, {conflicts} conflicts between the keepers')

    # One more upload on each terminal picks up anything left for a retry.
    for serial in ('RACE-0001', 'RACE-0002'):
        assert db.run(upload(serial, [(pin(30), f'{day} 06:25:00')])).returncode == 0

    checks = {
        'check-ins left unapplied': f"""
            select count(*) from public.v1_workforce_terminal_days day
            where day.work_date = '{day}' and day.finding = 'error'""",
        'lines a terminal added that are not on the day': f"""
            select count(*) from public.v1_workforce_terminal_days day
            where day.work_date = '{day}' and day.added and not exists (
              select 1 from public.v1_workforce_day_rows day_row
              where day_row.team_id = day.team_id
                and day_row.work_date = day.work_date
                and day_row.worker_id = day.worker_id)""",
        'labourers who checked in and have no line': f"""
            select count(distinct match.worker_id)
            from public.v1_workforce_terminal_punches punch
            join public.v1_workforce_terminal_users match
              on match.device_user_id = punch.device_user_id
              and match.ended_at is null
            where punch.work_date = '{day}' and punch.team_id = '{team}'
              and not exists (
                select 1 from public.v1_workforce_day_rows day_row
                where day_row.team_id = '{team}' and day_row.work_date = '{day}'
                  and day_row.worker_id = match.worker_id)""",
        'terminal lines that are not the usual shift': f"""
            select count(*) from public.v1_workforce_day_rows
            where team_id = '{team}' and work_date = '{day}'
              and updated_by_auth_user_id is null
              and (start_minute, finish_minute, worked_minutes,
                normal_overtime_minutes, attendance_status)
                is distinct from (390, 870, 480, 0, 'P')""",
        'saves by people not counted by the version': f"""
            select (select count(*) from public.v1_audit_events event
                where event.entity_id = sheet.id and event.event_type in (
                  'workforce_day_entered', 'workforce_day_updated'))
              - sheet.record_version
            from public.v1_workforce_day_sheets sheet
            where sheet.team_id = '{team}' and sheet.work_date = '{day}'""",
    }
    for name, sql in checks.items():
        assert db.value(sql) == '0', f'{name}: {db.value(sql)}'
    lines = db.value(f"""select count(*) || ' lines, '
          || count(*) filter (where updated_by_auth_user_id is null)
          || ' still the terminal''s'
        from public.v1_workforce_day_rows
        where team_id = '{team}' and work_date = '{day}'""")
    deadlocks = subprocess.run(
        ['docker', 'logs', '--since', log_from, db.container],
        text=True, capture_output=True, check=False)
    assert 'deadlock detected' not in deadlocks.stdout + deadlocks.stderr
    print(f'4c ok: {lines}; nothing lost, doubled or left unapplied; '
          'the version counts only saves by people; no deadlock')
    print('TERMINAL_ATTENDANCE_CONCURRENCY_PASS')


if __name__ == '__main__':
    main()
