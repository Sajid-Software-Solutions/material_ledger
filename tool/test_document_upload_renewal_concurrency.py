"""Local-only independent-session upload renewal/finalizer races.

Fixtures use only the deterministic local personas and are removed by exact IDs.
No remote DSN, secret, filesystem hook or shell command input is accepted.
"""
import argparse
import concurrent.futures
import json
import subprocess
import time
import uuid


PE = '10000000-0000-4000-8000-000000000001'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--container', required=True)
    args = parser.parse_args()
    if args.container != 'supabase_db_material_ledger':
        raise SystemExit('Only the deterministic local material_ledger database is allowed.')
    psql = ['docker', 'exec', '-i', args.container, 'psql', '-X', '-Atq',
            '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1']

    def run(sql):
        result = subprocess.run(psql, input=sql, text=True, capture_output=True,
                                timeout=10)
        if result.returncode:
            raise AssertionError(result.stderr)
        return result.stdout.strip()

    claims = json.dumps({'sub': PE, 'role': 'authenticated',
                         'app_metadata': {'role': 'project_engineer'}})
    actor = ("set local role authenticated; select set_config("
             f"'request.jwt.claims','{claims}',true); ")
    service = ("set local role service_role; select set_config("
               "'request.jwt.claims','{\"role\":\"service_role\"}',true); ")
    project_id = str(uuid.uuid4())
    run(f"""begin;
      insert into public.v1_projects(id,project_ref,name,state,
        created_by_auth_user_id,created_by_role)
      values('{project_id}','RENEW-RACE-{project_id[:8]}','Local renewal race',
        'active','{PE}','project_engineer');
      insert into public.v1_project_members(project_id,member_auth_user_id,
        project_role,effective_from,assigned_by_auth_user_id,assigned_by_role,reason)
      values('{project_id}','{PE}','project_engineer',now()-interval '1 day',
        '{PE}','project_engineer','Local renewal race fixture');
      commit;""")
    fixtures = []
    holders = []

    def fixture(expired):
        intent_id, key = str(uuid.uuid4()), str(uuid.uuid4())
        path = f'documents/{project_id}/{intent_id}/content'
        run(f"""begin;
          insert into public.v1_document_upload_intents(id,project_id,
            target_entity_type,target_entity_id,planned_revision_number,
            classification,original_file_name,mime_type,byte_size,expected_sha256,
            origin,object_path,actor_auth_user_id,actor_role,idempotency_key,
            created_at,expires_at)
          values('{intent_id}','{project_id}','project','{project_id}',1,
            'operational','race.pdf','application/pdf',12,repeat('a',64),
            'uploaded','{path}','{PE}','project_engineer','{key}',
            now()-interval '16 minutes',
            now()+interval '{'-1 minute' if expired else '15 minutes'}');
          insert into storage.objects(bucket_id,name,owner_id,metadata)
          values('yorks-documents','{path}','{PE}',
            '{{"size":12,"mimetype":"application/pdf"}}');
          commit;""")
        fixtures.append((intent_id, key, path))
        resume = f"select public.v1_resume_document_upload('{intent_id}','{key}')"
        finalize = (f"select public.v1_create_document_version('{intent_id}',"
                    "repeat('a',64),12,'application/pdf')")
        return intent_id, key, resume, finalize

    def holder(sql):
        process = subprocess.Popen(psql, stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        holders.append(process)
        process.stdin.write("begin; " + sql
                            + "; select 'LOCKED'; select pg_sleep(0.7); commit;")
        process.stdin.close()
        while process.stdout.readline().strip() != 'LOCKED':
            if process.poll() is not None:
                raise AssertionError(process.stderr.read())
        return process

    cases = []
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
            for first in ['resume', 'finalize']:
                intent, key, resume, finalize = fixture(expired=first == 'resume')
                writer = holder((actor + resume) if first == 'resume' else
                                (service + finalize))
                second = (service + finalize) if first == 'resume' else (actor + resume)
                name = 'yorks_upload_renewal_race'
                competing = executor.submit(run,
                    f"begin; set local application_name='{name}'; "
                    + second + '; commit;')
                time.sleep(0.15)
                wait = run(f"select coalesce(wait_event_type,''),"
                    "cardinality(pg_blocking_pids(pid)) from pg_stat_activity "
                    f"where application_name='{name}';")
                assert wait.startswith('Lock|') and not wait.endswith('|0'), wait
                response = json.loads(competing.result().splitlines()[-1])
                writer.wait(timeout=10)
                assert writer.returncode == 0, writer.stderr.read()
                facts = run(f"select finalized_document_id,finalized_version_id,"
                    "(select count(*) from public.v1_document_versions v "
                    "where v.document_id=i.finalized_document_id),"
                    "(select count(*) from public.v1_audit_events a "
                    f"where a.idempotency_key='{key}' and a.event_type='document_version_created') "
                    f"from public.v1_document_upload_intents i where id='{intent}';")
                document, version, versions, audits = facts.split('|')
                assert document and version and versions == audits == '1', facts
                if first == 'finalize':
                    assert response['finalized_document_id'] == document, response
                    assert response['finalized_version_id'] == version, response
                else:
                    assert response['document_version_id'] == version, response
                # Retrying the original finalizer cannot add a second version.
                run('begin; ' + service + finalize + '; commit;')
                cases.append({'first_lock_holder': first,
                              'competing_wait': wait,
                              'document_versions': int(versions),
                              'finalization_audits': int(audits)})

            intent, _, resume, _ = fixture(expired=True)
            writer = holder(actor + resume)
            competing = executor.submit(run, 'begin; ' + actor + resume + '; commit;')
            resumed = json.loads(competing.result().splitlines()[-1])
            writer.wait(timeout=10)
            actual = run('begin; ' + actor + resume + '; commit;')
            assert json.loads(actual.splitlines()[-1])['expires_at'] == resumed['expires_at']
            cases.append({'competing_resumers': 'same original intent and expiry',
                          'created_version': resumed['finalized_version_id']})
    finally:
        for process in holders:
            if process.poll() is None:
                process.wait(timeout=10)
        ids = ','.join("'" + row[0] + "'" for row in fixtures)
        keys = ','.join("'" + row[1] + "'" for row in fixtures)
        # Only exact generated local fixture IDs are removed. The transaction-
        # local trigger bypass allows removal of the fixture's immutable audit/
        # versions without changing any other session or production invariant.
        run(f"""begin; set local session_replication_role=replica;
          delete from public.v1_audit_events where idempotency_key in ({keys});
          delete from public.v1_document_links where project_id='{project_id}';
          delete from public.v1_document_versions where document_id in
            (select finalized_document_id from public.v1_document_upload_intents where id in ({ids}));
          delete from public.v1_documents where id in
            (select finalized_document_id from public.v1_document_upload_intents where id in ({ids}));
          delete from storage.objects where name in
            (select object_path from public.v1_document_upload_intents where id in ({ids}));
          delete from public.v1_document_upload_intents where id in ({ids});
          delete from public.v1_project_members where project_id='{project_id}';
          delete from public.v1_projects where id='{project_id}';
          commit;""")
    print(json.dumps({'upload_renewal_independent_sessions': 'PASS', 'cases': cases}, indent=2))


if __name__ == '__main__':
    main()
