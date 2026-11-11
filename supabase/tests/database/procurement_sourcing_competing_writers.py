#!/usr/bin/env python3
"""Real two-session sourcing conflicts in a disposable local Postgres clone.

Never resets the developer database or contacts a hosted Supabase project.
Requires the local Supabase Docker database and the sourcing migration.
"""
from pathlib import Path
import json
import subprocess
import time
import uuid

CONTAINER = 'supabase_db_material_ledger'
DATABASE = 'sourcing_race_' + uuid.uuid4().hex[:12]
BASE = ['docker', 'exec', '-i', CONTAINER]


def sql(script, check=True):
    return subprocess.run(BASE + ['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1',
        '-U', 'postgres', '-d', DATABASE], input=script, text=True,
        capture_output=True, check=check)


created = False
try:
    subprocess.run(BASE + ['createdb', '-U', 'postgres', DATABASE], check=True,
                   capture_output=True)
    created = True
    dump = subprocess.Popen(BASE + ['pg_dump', '-U', 'postgres', '-d', 'postgres',
        '--no-owner', '--no-privileges'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    # pg_cron is configured for the original postgres database and cannot be
    # recreated in a clone. As in the existing dispatch race harness, restore
    # the remaining schema and verify the operational fixtures below.
    restore = subprocess.run(BASE + ['psql', '-X', '-q',
        '-U', 'postgres', '-d', DATABASE], stdin=dump.stdout, capture_output=True)
    dump.stdout.close()
    dump.wait()
    if dump.returncode or restore.returncode:
        raise RuntimeError('Disposable database clone failed: ' + restore.stderr.decode()[-2500:])
    fixture = Path('supabase/tests/database/yorks_v1_arrangement_sourcing_progress.test.sql').read_text()
    fixture = fixture[:fixture.index("select ok((select relrowsecurity")]
    fixture = fixture.replace('select no_plan();', '')
    fixture += """
      create table public.sourcing_race_fixture as select
        pg_temp.sourcing_payload() as progress_payload,
        pg_temp.sourcing_final_payload() as final_payload;
      commit;
    """
    sql(fixture)
    claims = json.dumps({'sub': '10000000-0000-4000-8000-000000000003',
        'role': 'authenticated', 'app_metadata': {'role': 'procurement',
        'app_user_id': 'usr-local-procurement'}})
    setup = "set request.jwt.claims='" + claims + "';"

    def race(first_command, second_command, expected_error):
        first = subprocess.Popen(BASE + ['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1',
            '-U', 'postgres', '-d', DATABASE], stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        first.stdin.write(setup + 'begin; ' + first_command
                          + "; select 'SOURCING_LOCK_HELD'; select pg_sleep(2); commit;\n")
        first.stdin.close()
        while True:
            line = first.stdout.readline()
            if 'SOURCING_LOCK_HELD' in line:
                break
            if not line:
                raise RuntimeError('First writer failed: ' + first.stderr.read())
        start = time.monotonic()
        second = sql(setup + second_command, check=False)
        elapsed = time.monotonic() - start
        first.wait()
        assert first.returncode == 0, first.stderr.read()
        assert second.returncode != 0 and expected_error in second.stderr, second.stderr
        assert elapsed > 1, 'Second writer did not wait for the actual request lock'

    race("select public.v1_save_arrangement_sourcing_progress(progress_payload,gen_random_uuid()) is not null from public.sourcing_race_fixture",
         "select public.v1_save_arrangement_sourcing_progress(progress_payload,gen_random_uuid()) from public.sourcing_race_fixture;",
         'V1_ARRANGEMENT_SOURCING_REVISION_CONFLICT')
    count = sql("select count(*) from public.v1_arrangement_sourcing_revisions where request_id=(select (progress_payload->>'request_id')::uuid from public.sourcing_race_fixture);").stdout.strip()
    assert count == '1', count

    race("select public.v1_save_arrangement(final_payload,gen_random_uuid()) is not null from public.sourcing_race_fixture",
         "select public.v1_save_arrangement_sourcing_progress(jsonb_set(progress_payload,'{expected_revision}','1'),gen_random_uuid()) from public.sourcing_race_fixture;",
         'V1_ARRANGEMENT_SOURCING_STATE_INVALID')
    result = sql("""select jsonb_build_object(
      'revisions',(select count(*) from public.v1_arrangement_sourcing_revisions where request_id=(f.progress_payload->>'request_id')::uuid),
      'state',(select state from public.v1_material_requests where id=(f.progress_payload->>'request_id')::uuid),
      'engineering_alerts',(select count(*) from public.v1_notifications where entity_id=(f.progress_payload->>'arrangement_id')::uuid
       and event_code='arrangement_preparation_completed' and recipient_auth_user_id in
       ('10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002')))
      from public.sourcing_race_fixture f;""")
    facts = json.loads(result.stdout.strip())
    assert facts == {'revisions': 1, 'state': 'approved', 'engineering_alerts': 2}, facts
    print('PASS: competing sourcing writers serialize, reject stale revisions, and reject updates after concurrent finalization; one alert per Engineering recipient.')
finally:
    if created:
        subprocess.run(BASE + ['dropdb', '-U', 'postgres', '--force', DATABASE],
                       check=True, capture_output=True)
