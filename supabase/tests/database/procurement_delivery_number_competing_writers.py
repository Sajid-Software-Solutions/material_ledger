#!/usr/bin/env python3
"""Prove per-project DO numbering with two transactions in a disposable clone.

Never changes the source database. Uses the committed command fixture and an
explicit sleep while the first connection retains the real allocator row lock.
"""
from pathlib import Path
import json
import subprocess
import time
import uuid

CONTAINER = 'supabase_db_material_ledger'
DB = 'procurement_do_race_' + uuid.uuid4().hex[:12]
BASE = ['docker', 'exec', '-i', CONTAINER]


def sql(script):
    result = subprocess.run(BASE + ['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1',
        '-U', 'postgres', '-d', DB], input=script, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr)
    return result


created = False
try:
    subprocess.run(BASE + ['createdb', '-U', 'postgres', DB], check=True, capture_output=True)
    created = True
    dump = subprocess.Popen(BASE + ['pg_dump', '-U', 'postgres', '-d', 'postgres',
        '--no-owner', '--no-privileges'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    # Supabase operational extensions may not restore into a differently named
    # database. The strict migration/real-command fixtures below validate every
    # relation/function used by this test; nothing runs against source postgres.
    restore = subprocess.run(BASE + ['psql', '-X', '-q', '-U', 'postgres', '-d', DB],
        stdin=dump.stdout, capture_output=True)
    dump.stdout.close()
    dump.wait()
    if dump.returncode or restore.returncode:
        raise RuntimeError('Disposable database clone failed')
    sql(Path('supabase/migrations/20261008185456_procurement_automatic_delivery_numbers.sql').read_text())
    fixture = Path('supabase/tests/database/yorks_v1_automatic_delivery_numbers.test.sql').read_text()
    fixture = fixture[:fixture.index('grant select on auto_do_targets')]
    fixture = fixture.replace('create temp table auto_do_targets', 'create table public.auto_do_targets')
    fixture = fixture.replace("'quantity_delta','8'", "'quantity_delta','24'")
    fixture = fixture.replace('  for n in 1..3 loop', '''  for n in 1..3 loop
    if n > 1 then
      r:=pg_temp.audit_request(p,s,item,array[2]::numeric[]);
      select jsonb_agg(jsonb_build_object('request_line_id',id,'dispatch_qty','2')) into q
      from public.v1_material_request_lines where request_id=r;
    end if;''')
    fixture = fixture.replace("set payload=jsonb_build_object('request_id',r", "set payload=jsonb_build_object('request_id',t.request_id")
    start = fixture.index('  update auto_do_targets t set payload')
    fixture = fixture[:start] + fixture[start:].replace("where id=r)", "where id=t.request_id)")
    sql(fixture + 'commit;')
    claims = json.dumps({'sub':'10000000-0000-4000-8000-000000000003', 'role':'authenticated',
        'app_metadata':{'role':'procurement','app_user_id':'usr-local-procurement'}})
    setup = "set request.jwt.claims='" + claims + "';"
    sql(setup + "select public.v1_generate_delivery_order(payload||jsonb_build_object('delivery_order_reference','AUTO-DO-TEST-DO001'),command_key) is not null from public.auto_do_targets where ordinal=1;")
    first = subprocess.Popen(BASE + ['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1',
        '-U', 'postgres', '-d', DB], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True)
    first.stdin.write(setup + "begin; select public.v1_generate_delivery_order(payload,command_key) is not null from public.auto_do_targets where ordinal=2; select 'NUMBER_LOCK_HELD'; select pg_sleep(2); commit;\n")
    first.stdin.close()
    while True:
        line = first.stdout.readline()
        if 'NUMBER_LOCK_HELD' in line:
            break
        if not line:
            raise RuntimeError('First numbering transaction failed: ' + first.stderr.read())
    started = time.monotonic()
    sql(setup + "select public.v1_generate_delivery_order(payload,command_key) is not null from public.auto_do_targets where ordinal=3;")
    elapsed = time.monotonic() - started
    first.wait()
    assert first.returncode == 0, first.stderr.read()
    assert elapsed > 1, 'Second transaction did not wait on the shared project allocator'
    # Lost-response retries preserve their original identifiers and revisions.
    sql(setup + "select public.v1_generate_delivery_order(payload,command_key) is not null from public.auto_do_targets where ordinal in (2,3);")
    facts = json.loads(sql("""select jsonb_build_object(
        'references',(select jsonb_agg(delivery_order_reference order by delivery_order_reference)
          from public.v1_delivery_orders where dispatch_id in (select dispatch_id from public.auto_do_targets)),
        'revisions',(select count(*) from public.v1_delivery_order_revisions where delivery_order_id in
          (select id from public.v1_delivery_orders where dispatch_id in (select dispatch_id from public.auto_do_targets))),
        'next',(select next_sequence from public.v1_delivery_order_reference_counters where project_id=
          (select project_id from public.v1_material_requests where id=(select request_id from public.auto_do_targets limit 1))))""").stdout.strip())
    assert facts == {'references':['AUTO-DO-TEST-DO001','AUTO-DO-TEST-DO002','AUTO-DO-TEST-DO003'],
        'revisions':3,'next':4}, facts
    print('PASS: independent requests serialize on project DO numbering, skip retained references, and retry without duplicate revisions or numbers')
finally:
    if created:
        subprocess.run(BASE + ['dropdb', '-U', 'postgres', '--force', DB], check=True, capture_output=True)
