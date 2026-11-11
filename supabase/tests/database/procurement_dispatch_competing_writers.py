#!/usr/bin/env python3
"""Two real connections compete for replacement stock in a disposable local clone.

Does not reset or mutate the developer database. Creates a uniquely named local
Postgres database from pg_dump, runs committed fixtures there, and drops it.
Run from repository root with Docker/local Supabase already running.
"""
from pathlib import Path
import json
import subprocess
import time
import uuid

CONTAINER = 'supabase_db_material_ledger'
DB = 'procurement_race_' + uuid.uuid4().hex[:12]
BASE = ['docker', 'exec', '-i', CONTAINER]

def sql(script, check=True):
    return subprocess.run(BASE + ['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1',
        '-U', 'postgres', '-d', DB], input=script, text=True, capture_output=True, check=check)

created = False
try:
    subprocess.run(BASE + ['createdb', '-U', 'postgres', DB], check=True, capture_output=True)
    created = True
    dump = subprocess.Popen(BASE + ['pg_dump', '-U', 'postgres', '-d', 'postgres', '--no-owner', '--no-privileges'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    restore = subprocess.run(BASE + ['psql', '-X', '-q', '-U', 'postgres', '-d', DB], stdin=dump.stdout, capture_output=True)
    dump.stdout.close()
    dump.wait()
    if dump.returncode or restore.returncode:
        raise RuntimeError('Disposable database clone failed')
    fixture = Path('docs/yorks-v1/evidence/procurement-review-20261008/shared_stock_repro.sql').read_text()
    fixture = fixture[:fixture.index("  raise notice 'BEFORE:")]
    fixture = fixture.replace('begin;\nset local', 'begin;\nset local', 1)
    fixture = fixture.replace('declare p uuid; s uuid; item uuid; a uuid; b uuid;', 'declare p uuid; s uuid; item uuid; a uuid; b uuid; c uuid;')
    fixture = fixture.replace('do $$\ndeclare', 'create table public.procurement_race_fixture(a uuid,c uuid,item uuid,b uuid,payload_a jsonb,payload_c jsonb);\ndo $$\ndeclare')
    fixture += """
  c:=pg_temp.audit_request(p,s,item,array[1,1]::numeric[]);
  select jsonb_agg(jsonb_build_object('request_line_id',id,'dispatch_qty','1')) into q from public.v1_material_request_lines where request_id=c;
  perform public.v1_dispatch_materials(jsonb_build_object('request_id',c,'expected_version',(select record_version from public.v1_material_requests where id=c),'dispatch_date',current_date,'delivery_reference','RACE-C-FIRST','lines',q),gen_random_uuid());
  select id into d from public.v1_material_dispatches where request_id=c;
  select jsonb_agg(jsonb_build_object('dispatch_line_id',id,'outcome','missing','good_qty','0','note','Race missing fixture')) into q from public.v1_material_dispatch_lines where dispatch_id=d;
  perform pg_temp.audit_actor(2,'site_engineer');
  perform public.v1_confirm_receipt(jsonb_build_object('request_id',c,'dispatch_id',d,'expected_request_version',(select record_version from public.v1_material_requests where id=c),'expected_dispatch_version',1,'lines',q),gen_random_uuid());
  perform pg_temp.audit_actor(3,'procurement');
  perform public.v1_adjust_inventory(jsonb_build_object('inventory_item_id',item,'quantity_delta','2','reason','Race fixture'),gen_random_uuid());
  insert into public.procurement_race_fixture(a,c,item,b,payload_a,payload_c)
  select a,c,item,b,
    jsonb_build_object('request_id',a,'expected_version',(select record_version from public.v1_material_requests where id=a),'dispatch_date',current_date,'delivery_reference','RACE-A','lines',(select jsonb_agg(jsonb_build_object('request_line_id',id,'dispatch_qty','1')) from public.v1_material_request_lines where request_id=a)),
    jsonb_build_object('request_id',c,'expected_version',(select record_version from public.v1_material_requests where id=c),'dispatch_date',current_date,'delivery_reference','RACE-C','lines',(select jsonb_agg(jsonb_build_object('request_line_id',id,'dispatch_qty','1')) from public.v1_material_request_lines where request_id=c));
end $$;
commit;
"""
    sql(fixture)
    claims = json.dumps({'sub':'10000000-0000-4000-8000-000000000003','role':'authenticated','app_metadata':{'role':'procurement','app_user_id':'usr-local-procurement'}})
    setup = "set request.jwt.claims='" + claims + "';"
    # First transaction deliberately retains the actual balance row lock after
    # its dispatch RPC. The second request must wait, then see committed stock.
    first = subprocess.Popen(BASE + ['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', DB], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    first.stdin.write(setup + "begin; select public.v1_dispatch_materials(payload_a,gen_random_uuid()) is not null from public.procurement_race_fixture; select 'STOCK_LOCK_HELD'; select pg_sleep(2); commit;\n")
    first.stdin.close()
    while True:
        line = first.stdout.readline()
        if 'STOCK_LOCK_HELD' in line:
            break
        if not line:
            raise RuntimeError('First writer did not reach stock lock: ' + first.stderr.read())
    start = time.monotonic()
    second = sql(setup + "select public.v1_dispatch_materials(payload_c,gen_random_uuid()) from public.procurement_race_fixture;", check=False)
    elapsed = time.monotonic() - start
    first.wait()
    assert first.returncode == 0, first.stderr.read()
    assert second.returncode != 0 and 'V1_DISPATCH_STOCK_CAP_EXCEEDED' in second.stderr, second.stderr
    assert elapsed > 1, 'Second writer did not wait for the real inventory lock'
    result = sql("select jsonb_build_object('on_hand',i.on_hand_qty,'reserved',(select sum(reserved_qty-consumed_qty) from public.v1_inventory_reservations where request_id=f.b and state in ('active','partially_consumed')),'a_dispatches',(select count(*) from public.v1_material_dispatches where request_id=f.a),'c_dispatches',(select count(*) from public.v1_material_dispatches where request_id=f.c)) from public.procurement_race_fixture f join public.v1_inventory_balances i on i.inventory_item_id=f.item;")
    facts = json.loads(result.stdout.strip())
    assert facts == {'on_hand': 4, 'reserved': 4, 'a_dispatches': 2, 'c_dispatches': 1}, facts

    # A delayed final HTTP request must remain fenced even if it reaches the
    # server after an explicit, confirmed abandon decision in another tab.
    sql(setup + """
      alter table public.procurement_race_fixture add column command_key uuid default gen_random_uuid();
      update public.procurement_race_fixture f set payload_a=jsonb_set(payload_a,'{expected_version}',to_jsonb(r.record_version))
        from public.v1_material_requests r where r.id=f.a;
      select public.v1_save_procurement_progress(jsonb_build_object('request_id',a,'editor_kind','dispatch',
        'expected_revision',0,'schema_version',1,'base_request_version',(payload_a->>'expected_version')::int,
        'inputs',jsonb_build_object('dispatch_date',current_date::text,'delivery_reference','RACE-A','lines',payload_a->'lines')),
        gen_random_uuid()) from public.procurement_race_fixture;
      select public.v1_prepare_procurement_command(jsonb_build_object('request_id',a,'editor_kind','dispatch',
        'checkpoint_revision',1,'command_name','v1_dispatch_materials','command_key',command_key,
        'command_payload',payload_a),gen_random_uuid()) from public.procurement_race_fixture;
    """)
    # Two browser tabs share one persisted automatic-check budget. The first
    # deliberately holds only the existing intent row; the other must observe
    # its consumed slot rather than racing a new local counter.
    check_first = subprocess.Popen(BASE + ['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', DB], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    check_first.stdin.write(setup + "begin; select public.v1_reconcile_procurement_command_outcome(a,'v1_dispatch_materials',command_key,true)->>'status' from public.procurement_race_fixture; select 'CHECK_BUDGET_HELD'; select pg_sleep(2); commit;\n")
    check_first.stdin.close()
    while True:
        line = check_first.stdout.readline()
        if 'CHECK_BUDGET_HELD' in line:
            break
        if not line:
            raise RuntimeError('Outcome check did not claim budget: ' + check_first.stderr.read())
    competing = sql(setup + "select public.v1_reconcile_procurement_command_outcome(a,'v1_dispatch_materials',command_key,true)->>'check_deferred' from public.procurement_race_fixture;")
    check_first.wait()
    assert check_first.returncode == 0, check_first.stderr.read()
    assert competing.stdout.strip() == 'true', competing.stdout
    budget = sql("select automatic_check_count from public.v1_procurement_command_intents i join public.procurement_race_fixture f on i.command_key=f.command_key;")
    assert budget.stdout.strip() == '1', budget.stdout
    abandon = subprocess.Popen(BASE + ['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', DB], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    abandon.stdin.write(setup + "begin; select public.v1_abandon_procurement_command(a,'v1_dispatch_materials',command_key)->>'status' from public.procurement_race_fixture; select 'ABANDON_LOCK_HELD'; select pg_sleep(2); commit;\n")
    abandon.stdin.close()
    while True:
        line = abandon.stdout.readline()
        if 'ABANDON_LOCK_HELD' in line:
            break
        if not line:
            raise RuntimeError('Abandon did not reach lock: ' + abandon.stderr.read())
    late = sql(setup + "select public.v1_dispatch_materials(payload_a,command_key) from public.procurement_race_fixture;", check=False)
    abandon.wait()
    assert abandon.returncode == 0, abandon.stderr.read()
    assert late.returncode != 0 and 'V1_PROCUREMENT_COMMAND_INTENT_CHANGED' in late.stderr, late.stderr
    # Reuse the checkpoint with a new *explicitly prepared* command after the
    # old command was authoritatively fenced. Simulate an in-flight transaction
    # then a lost HTTP response: a lookup miss must not release or replay it.
    sql(setup + """
      update public.procurement_race_fixture set command_key=gen_random_uuid();
      select public.v1_adjust_inventory(jsonb_build_object('inventory_item_id',item,
        'quantity_delta','2','reason','Outcome race fixture'),gen_random_uuid()) from public.procurement_race_fixture;
      select public.v1_prepare_procurement_command(jsonb_build_object('request_id',a,'editor_kind','dispatch',
        'checkpoint_revision',1,'command_name','v1_dispatch_materials','command_key',command_key,
        'command_payload',payload_a),gen_random_uuid()) from public.procurement_race_fixture;
    """)
    sending = subprocess.Popen(BASE + ['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', DB], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    sending.stdin.write(setup + "begin; select public.v1_dispatch_materials(payload_a,command_key) is not null from public.procurement_race_fixture; select 'DISPATCH_IN_FLIGHT'; select pg_sleep(2); commit;\n")
    sending.stdin.close()
    while True:
        line = sending.stdout.readline()
        if 'DISPATCH_IN_FLIGHT' in line:
            break
        if not line:
            raise RuntimeError('Dispatch did not reach in-flight boundary: ' + sending.stderr.read())
    start = time.monotonic()
    interim = sql(setup + "select public.v1_reconcile_procurement_command_outcome(a,'v1_dispatch_materials',command_key)->>'status' from public.procurement_race_fixture;")
    lookup_seconds = time.monotonic() - start
    assert interim.stdout.strip() in ('prepared', 'pending', 'not_found'), interim.stdout
    assert lookup_seconds < 1, 'Outcome lookup waited behind the in-flight request lock'
    sending.wait()
    assert sending.returncode == 0, sending.stderr.read()
    result = sql(setup + "select public.v1_reconcile_procurement_command_outcome(a,'v1_dispatch_materials',command_key) from public.procurement_race_fixture;")
    receipt = json.loads(result.stdout.strip())
    assert receipt['status'] == 'confirmed' and receipt['receipt']['effect_id'], receipt
    before = sql("select jsonb_build_object('dispatches',(select count(*) from public.v1_material_dispatches where request_id=f.a),'audit',(select count(*) from public.v1_audit_events where actor_auth_user_id='10000000-0000-4000-8000-000000000003' and idempotency_key=f.command_key),'stock',(select on_hand_qty from public.v1_inventory_balances where inventory_item_id=f.item)) from public.procurement_race_fixture f;").stdout.strip()
    sql(setup + "select public.v1_dispatch_materials(payload_a,command_key) is not null from public.procurement_race_fixture;")
    after = sql("select jsonb_build_object('dispatches',(select count(*) from public.v1_material_dispatches where request_id=f.a),'audit',(select count(*) from public.v1_audit_events where actor_auth_user_id='10000000-0000-4000-8000-000000000003' and idempotency_key=f.command_key),'stock',(select on_hand_qty from public.v1_inventory_balances where inventory_item_id=f.item)) from public.procurement_race_fixture f;").stdout.strip()
    assert before == after, (before, after)
    print('PASS: competing automatic status checks consumed exactly one shared budget slot.')
    print(f'PASS: in-flight lookup remained unknown in {lookup_seconds:.3f}s; later exact-key receipt confirmed; replay duplicated no stock, dispatch or audit.')
    print('PASS: independent requests waited on shared stock; one dispatch committed, one rejected; competing reservation fully covered; loser created no document.')
    print('PASS: delayed final command waited for abandon and was rejected by the immutable intent fence.')
finally:
    if created:
        subprocess.run(BASE + ['dropdb', '-U', 'postgres', '--force', DB], check=True, capture_output=True)
