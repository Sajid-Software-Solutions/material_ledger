"""Local-only competing MR approval/recovery transactions.

Usage: python3 tool/test_material_request_approval_recovery_concurrency.py \
  --container supabase_db_material_ledger

No remote DSN or application credentials are accepted. Fixtures use the public
deterministic local personas. The baseline trigger is restored only inside a
transaction that is rolled back, never deployed as a global schema change.
"""
import argparse
import concurrent.futures
import json
from pathlib import Path
import subprocess
import time
import uuid


PE = '10000000-0000-4000-8000-000000000001'
SE = '10000000-0000-4000-8000-000000000002'


def claims(actor, role):
    return json.dumps({'sub': actor, 'role': 'authenticated',
                       'app_metadata': {'role': role}}, separators=(',', ':'))


def actor_session(actor, role, sql):
    return ("set local role authenticated; select set_config('request.jwt.claims', "
            f"'{claims(actor, role)}', true); {sql}")


def json_sql(value):
    return "'" + json.dumps(value).replace("'", "''") + "'::jsonb"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--container', required=True)
    args = parser.parse_args()
    if (args.container != 'supabase_db_material_ledger'
            and not args.container.startswith('supabase_db_yorks_p0_')):
        raise SystemExit('Use the isolated yorks_p0 local database only.')
    psql = ['docker', 'exec', '-i', args.container, 'psql', '-X', '-Atq',
            '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1',
            '-v', 'VERBOSITY=verbose']

    def run(sql, check=True):
        result = subprocess.run(psql, input=sql, text=True, capture_output=True,
                                timeout=15)
        if check and result.returncode:
            raise AssertionError(result.stderr)
        return result

    def transact(actor, role, sql):
        return run('begin; ' + actor_session(actor, role, sql) + '; commit;')

    def measured(sql):
        started = time.monotonic()
        return run(sql, False), round((time.monotonic() - started) * 1000)

    project_ref = 'RECOVERY-RACE-' + uuid.uuid4().hex[:10].upper()
    project = {'project_ref': project_ref, 'name': 'Local recovery contention',
               'parties': {}, 'initial_members': [{'auth_user_id': SE,
               'project_role': 'site_engineer', 'reason': 'Local fixture'}],
               'buildings': [{'code': 'B1', 'name': 'Test'}], 'attachments': []}
    transact(PE, 'project_engineer',
             f"select public.v1_create_project({json_sql(project)},'{uuid.uuid4()}')")
    ids = run(f"select p.id,s.id from public.v1_projects p join public.v1_project_scopes s on s.project_id=p.id and s.scope_kind='common' where p.project_ref='{project_ref}';")
    project_id, scope_id = ids.stdout.strip().split('|')
    transact(PE, 'project_engineer',
        f"select public.v1_set_project_state({json_sql({'project_id': project_id, 'state': 'active', 'expected_version': 1, 'reason': 'Local contention fixture'})},'{uuid.uuid4()}')")

    def fixture():
        request_id = str(uuid.uuid4())
        payload = {'request_id': request_id, 'expected_version': 0,
                   'project_id': project_id, 'scope_id': scope_id,
                   'title': 'Approval contention', 'timing': 'normal',
                   'scheduled_date': None, 'delivery_note': None,
                   'lines': [{'id': str(uuid.uuid4()), 'display_order': 1,
                   'source_kind': 'custom', 'source_boq_group_id': None,
                   'source_boq_row_id': None, 'item_description': 'Test duct',
                   'brand_origin': None, 'technical_attributes': {},
                   'requested_qty': '2', 'unit': 'Meter'}]}
        transact(SE, 'site_engineer',
            f"select public.v1_save_material_request_draft({json_sql(payload)})")
        transact(SE, 'site_engineer',
            f"select public.v1_submit_material_request({json_sql({'request_id': request_id, 'expected_version': 1})},'{uuid.uuid4()}')")
        # Legacy divergent input retained from before normalized save. Public
        # sync itself cannot create this situation once an MR exists.
        run(f"insert into public.v1_material_request_private_drafts(draft_id,owner_auth_user_id,sync_version,draft_data,client_updated_at) values ('{request_id}','{SE}',7,'{{\"title\":\"Legacy recovery\",\"unknown_future\":{{\"retain\":true}},\"lines\":[]}}',now());")
        return request_id, payload

    def holder(request_id, command='delete', seconds=1.5):
        if command == 'delete':
            effect = actor_session(SE, 'site_engineer',
                f"select public.v1_delete_my_material_request_private_draft({json_sql({'draft_id': request_id, 'expected_sync_version': 7})},'{uuid.uuid4()}');")
        else:
            effect = ''  # Read-lock contention leaves cleanup to the worker.
        process = subprocess.Popen(psql, stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        sql = (f"begin; set local application_name='yorks_recovery_holder'; "
               f"select 1 from public.v1_material_request_private_drafts where draft_id='{request_id}' and owner_auth_user_id='{SE}' for update; "
               f"select 'LOCKED'; select pg_sleep({seconds}); {effect} commit;")
        process.stdin.write(sql)
        process.stdin.close()
        while process.stdout.readline().strip() != 'LOCKED':
            if process.poll() is not None:
                raise AssertionError(process.stderr.read())
        return process

    old = Path('supabase/migrations/20261007102033_material_request_recovery_lifecycle.sql').read_text()
    start = old.index('create or replace function public.v1_retire_progressed_material_request_recovery()')
    baseline_function = old[start:old.index('$$;', start) + 3]
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
        for baseline, competing in [(True, 'delete'), (False, 'delete'),
                                    (False, 'hold')]:
            request_id, payload = fixture()
            writer = holder(request_id, competing)
            before = (baseline_function + ';') if baseline else ''
            decision_key = str(uuid.uuid4())
            sql = ("begin; set local application_name='yorks_approval_race'; "
                   + before + " set local statement_timeout='700ms'; "
                   + actor_session(PE, 'project_engineer',
                   f"select public.v1_decide_material_request({json_sql({'request_id': request_id, 'expected_version': 2, 'decision': 'approved', 'reason': None})},'{decision_key}');")
                   + (' rollback;' if baseline else ' commit;'))
            approval = executor.submit(measured, sql)
            time.sleep(0.2)
            wait = run("select coalesce(wait_event_type,''),coalesce(wait_event,''),cardinality(pg_blocking_pids(pid)) from pg_stat_activity where application_name='yorks_approval_race';").stdout.strip()
            response, elapsed = approval.result()
            worker_elapsed = None
            if baseline:
                assert response.returncode != 0 and '57014' in response.stderr, response.stderr
                assert 'Lock|' in wait and not wait.endswith('|0'), wait
            else:
                assert response.returncode == 0, response.stderr
                assert elapsed < 700, elapsed
                pending = run(f"select count(*) from public.v1_material_request_recovery_archival_jobs where draft_id='{request_id}';")
                assert pending.stdout.strip() == '1', pending.stdout
                worker_start = time.monotonic()
                worker = run('select public.v1_process_material_request_recovery_archival(50);')
                worker_elapsed = round((time.monotonic() - worker_start) * 1000)
                assert worker_elapsed < 500, worker_elapsed
                assert json.loads(worker.stdout.strip())['deferred'] >= 1, worker.stdout
                # The pending job is fenced immediately, while the original
                # private row is still locked by the other connection.
                old_sync = {'draft_id': request_id, 'expected_sync_version': 7,
                    'client_updated_at': '2026-10-15T00:00:00Z',
                    'draft_data': {'title': 'stale', 'lines': []}}
                rejected = run('begin; ' + actor_session(SE, 'site_engineer',
                    f"select public.v1_sync_material_request_private_draft({json_sql(old_sync)},'{uuid.uuid4()}');") + ' commit;', False)
                assert rejected.returncode != 0 and 'V1_PRIVATE_DRAFT_ALREADY_SAVED' in rejected.stderr, rejected.stderr
            writer.wait(timeout=15)
            assert writer.returncode == 0, writer.stderr.read()
            if not baseline:
                run(f"update public.v1_material_request_recovery_archival_jobs set next_attempt_at=now() where draft_id='{request_id}'; select public.v1_process_material_request_recovery_archival(50);")
            state = run(f"select state,(select count(*) from public.v1_material_request_private_drafts where draft_id=r.id),(select count(*) from public.v1_material_request_recovery_archive where draft_id=r.id and sync_version=7 and draft_data->'unknown_future'='{{\"retain\":true}}'::jsonb),(select count(*) from public.v1_audit_events where entity_id=r.id and event_type='material_request_approved'),(select count(*) from public.v1_material_request_recovery_archival_jobs where draft_id=r.id) from public.v1_material_requests r where id='{request_id}';").stdout.strip()
            if baseline:
                assert state == 'awaiting_request_approval|0|1|0|0', state
            else:
                assert state == 'approved_for_arrangement|0|1|1|0', state
                transact(PE, 'project_engineer',
                    f"select public.v1_decide_material_request({json_sql({'request_id': request_id, 'expected_version': 2, 'decision': 'approved', 'reason': None})},'{decision_key}')")
                count = run(f"select count(*) from public.v1_audit_events where entity_id='{request_id}' and event_type='material_request_approved';")
                assert count.stdout.strip() == '1', count.stdout
            results.append({'baseline': baseline, 'competing': competing,
                'approval_ms': elapsed, 'observed_wait': wait,
                'contended_worker_ms': worker_elapsed,
                'state_private_archive_audit_queue': state})

        # Prove the absent-row edge: private sync began while no normalized MR
        # was visible. Progression must persist a cleanup obligation even though
        # its SELECT cannot yet see the uncommitted private INSERT.
        request_id = str(uuid.uuid4())
        sync_payload = {'draft_id': request_id, 'expected_sync_version': 0,
            'client_updated_at': '2026-10-15T00:00:00Z',
            'draft_data': {'title': 'In-flight sync', 'lines': []}}
        syncing = subprocess.Popen(psql, stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        syncing.stdin.write('begin; ' + actor_session(SE, 'site_engineer',
            f"select public.v1_sync_material_request_private_draft({json_sql(sync_payload)},'{uuid.uuid4()}');")
            + " select 'LOCKED'; select pg_sleep(1.5); commit;")
        syncing.stdin.close()
        while syncing.stdout.readline().strip() != 'LOCKED':
            if syncing.poll() is not None:
                raise AssertionError(syncing.stderr.read())
        started = time.monotonic()
        run(f"begin; insert into public.v1_material_requests(id,project_id,scope_id,timing,state,record_version,created_by_auth_user_id,current_action_owner_role,current_action_code) values ('{request_id}','{project_id}','{scope_id}','normal','draft',1,'{SE}','site_engineer','draft_owner'); update public.v1_material_requests set state='awaiting_request_approval',request_number='RACE-{uuid.uuid4().hex[:10]}',submitted_at=now() where id='{request_id}'; commit;")
        progression_ms = round((time.monotonic() - started) * 1000)
        assert progression_ms < 700, progression_ms
        worker = json.loads(run('select public.v1_process_material_request_recovery_archival(50);').stdout.strip())
        assert worker['deferred'] >= 1, worker
        syncing.wait(timeout=15)
        assert syncing.returncode == 0, syncing.stderr.read()
        rejected = run('begin; ' + actor_session(SE, 'site_engineer',
            f"select public.v1_get_my_material_request_private_draft('{request_id}');") + ' commit;', False)
        assert rejected.returncode != 0 and 'V1_PRIVATE_DRAFT_ALREADY_SAVED' in rejected.stderr, rejected.stderr
        run(f"update public.v1_material_request_recovery_archival_jobs set next_attempt_at=now() where draft_id='{request_id}'; select public.v1_process_material_request_recovery_archival(50);")
        fact = run(f"select (select count(*) from public.v1_material_request_private_drafts where draft_id='{request_id}'),(select count(*) from public.v1_material_request_recovery_archive where draft_id='{request_id}' and draft_data->>'title'='In-flight sync'),(select count(*) from public.v1_material_request_recovery_archival_jobs where draft_id='{request_id}');").stdout.strip()
        assert fact == '0|1|0', fact
        results.append({'competing': 'private_sync_before_normalized_insert',
                        'progression_ms': progression_ms,
                        'private_archive_queue': fact})
    print(json.dumps({'two_session_approval_recovery': 'PASS', 'cases': results}, indent=2))


if __name__ == '__main__':
    main()
