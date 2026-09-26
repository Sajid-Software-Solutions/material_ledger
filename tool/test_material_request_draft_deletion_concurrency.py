"""Local-only, two-session MR recovery races. Requires the isolated seeded DB.

Usage: python3 tool/test_material_request_draft_deletion_concurrency.py
Never accepts a remote DSN or uses production credentials.
"""
import concurrent.futures
import json
import subprocess
import time
import uuid
import base64
import hashlib
import hmac
import urllib.error
import urllib.request

CONTAINER = 'supabase_db_yorks_draft_lifecycle_20260927'
ACTOR = '10000000-0000-4000-8000-000000000001'
CLAIMS = json.dumps({'sub': ACTOR, 'role': 'authenticated',
                     'app_metadata': {'role': 'project_engineer',
                                      'app_user_id': 'usr-local-project-engineer'}})
PSQL = ['docker', 'exec', '-i', CONTAINER, 'psql', '-X', '-Atq',
        '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1']


def run(sql):
    return subprocess.run(PSQL, input=sql, text=True, capture_output=True,
                          timeout=15)


def session(sql):
    return f"begin; set local role authenticated; select set_config('request.jwt.claims', '{CLAIMS}', true); {sql}; commit;"


def command(kind, draft, project=None, scope=None):
    if kind == 'sync':
        payload = {'draft_id': draft, 'expected_sync_version': 0,
                   'client_updated_at': '2026-09-27T00:00:00Z',
                   'draft_data': {'title': 'Local concurrency fixture', 'lines': []}}
        func = 'v1_sync_material_request_private_draft'
    elif kind == 'delete':
        payload = {'draft_id': draft, 'expected_sync_version': 0}
        func = 'v1_delete_my_material_request_private_draft'
    else:
        payload = {'request_id': draft, 'expected_version': 0,
                   'project_id': project, 'scope_id': scope,
                   'timing': 'normal', 'lines': []}
        return f"select public.v1_save_material_request_draft('{json.dumps(payload)}'::jsonb)"
    return f"select public.{func}('{json.dumps(payload)}'::jsonb, '{uuid.uuid4()}')"


def race(first, second, project, scope):
    draft = str(uuid.uuid4())
    lock = f"select pg_advisory_xact_lock(hashtextextended('v1_mr_private:{ACTOR}:{draft}',0)); select 'LOCKED'; select pg_sleep(0.4);"
    process = subprocess.Popen(PSQL, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True)
    process.stdin.write(session(lock + command(first, draft, project, scope)))
    process.stdin.close()
    while process.stdout.readline().strip() != 'LOCKED':
        if process.poll() is not None:
            raise AssertionError(process.stderr.read())
    started = time.monotonic()
    with concurrent.futures.ThreadPoolExecutor() as executor:
        competing = executor.submit(run, session(command(second, draft, project, scope)))
        process.wait(timeout=15)
        result = competing.result(timeout=15)
    assert process.returncode == 0, process.stderr.read()
    assert result.returncode != 0, result.stdout
    expected_error = ('V1_PRIVATE_DRAFT_DELETED' if first == 'delete' else
                      'V1_PRIVATE_DRAFT_VERSION_CONFLICT' if first == 'sync' else
                      'V1_PRIVATE_DRAFT_ALREADY_SAVED')
    assert expected_error in result.stderr, result.stderr
    facts = run(f"select (select count(*) from public.v1_material_request_private_draft_retirements where draft_id='{draft}'),"
                f"(select count(*) from public.v1_material_request_private_drafts where draft_id='{draft}'),"
                f"(select count(*) from public.v1_material_requests where id='{draft}');")
    assert facts.returncode == 0, facts.stderr
    expected_facts = {'delete': '1|0|0', 'sync': '0|1|0', 'save': '0|0|1'}
    assert facts.stdout.strip() == expected_facts[first], facts.stdout
    return round((time.monotonic() - started) * 1000)


def local_token(claims):
    # The public, deterministic local Supabase key; never accepted remotely.
    encode = lambda value: base64.urlsafe_b64encode(json.dumps(value, separators=(',', ':')).encode()).rstrip(b'=')
    body = encode({'alg': 'HS256', 'typ': 'JWT'}) + b'.' + encode(claims)
    signature = hmac.new(b'super-secret-jwt-token-with-at-least-32-characters-long', body, hashlib.sha256).digest()
    return (body + b'.' + base64.urlsafe_b64encode(signature).rstrip(b'=')).decode()


def rest_contract():
    claims = json.loads(CLAIMS)
    claims.update(exp=int(time.time()) + 600, iss='supabase-demo', aud='authenticated')
    actor_token = local_token(claims)
    anon_token = local_token({'role': 'anon', 'iss': 'supabase-demo', 'exp': int(time.time()) + 600})

    def rpc(function, payload, key=None, anonymous=False):
        body = {'p_payload': payload}
        if key is not None:
            body['p_idempotency_key'] = key
        request = urllib.request.Request('http://127.0.0.1:56321/rest/v1/rpc/' + function,
          data=json.dumps(body).encode(), headers={'Content-Type': 'application/json',
          'apikey': anon_token, 'Authorization': 'Bearer ' + (anon_token if anonymous else actor_token)})
        started = time.monotonic()
        try:
            with urllib.request.urlopen(request, timeout=5) as response:
                status, result = response.status, json.load(response)
        except urllib.error.HTTPError as error:
            status, result = error.code, json.load(error)
        return status, result, round((time.monotonic() - started) * 1000)

    draft = str(uuid.uuid4())
    sync = {'draft_id': draft, 'expected_sync_version': 0,
            'client_updated_at': '2026-09-27T00:00:00Z', 'draft_data': {'lines': []}}
    status, _, _ = rpc('v1_sync_material_request_private_draft', sync, str(uuid.uuid4()))
    assert status == 200
    status, body, conflict_ms = rpc('v1_delete_my_material_request_private_draft',
      {'draft_id': draft, 'expected_sync_version': 0}, str(uuid.uuid4()))
    assert status == 409 and body['code'] == '40001', (status, body)
    assert conflict_ms < 1500, conflict_ms
    delete = {'draft_id': draft, 'expected_sync_version': 1}
    key = str(uuid.uuid4())
    status, original, _ = rpc('v1_delete_my_material_request_private_draft', delete, key)
    assert status == 200 and original['deleted'] is True
    status, retry, _ = rpc('v1_delete_my_material_request_private_draft', delete, key)
    assert status == 200 and retry == original
    status, body, _ = rpc('v1_sync_material_request_private_draft', sync, str(uuid.uuid4()))
    assert status == 409 and body['code'] == '55000', (status, body)
    status, _, _ = rpc('v1_delete_my_material_request_private_draft', delete, str(uuid.uuid4()), anonymous=True)
    assert status >= 400, status
    latencies = []
    for _ in range(20):
        status, body, elapsed = rpc('v1_delete_my_material_request_private_draft',
          {'draft_id': str(uuid.uuid4()), 'expected_sync_version': 0}, str(uuid.uuid4()))
        assert status == 200 and body['deleted'] is True, (status, body)
        latencies.append(elapsed)
    print(json.dumps({'local_rest_contract': 'PASS', 'stale_delete_http': 409,
                      'conflict_ms': conflict_ms, 'retired_sync_http': 409,
                      'delete_samples': len(latencies), 'delete_p95_ms': sorted(latencies)[18]}))


if __name__ == '__main__':
    # Container name and Docker-local execution are fixed intentionally.
    check = run('select current_database();')
    assert check.returncode == 0 and check.stdout.strip() == 'postgres', check.stderr
    fixture = {'project_ref': 'DRAFT-RACE', 'name': 'Local draft concurrency',
               'parties': {}, 'initial_members': [],
               'buildings': [{'code': 'B1', 'name': 'Test building'}], 'attachments': []}
    existing = run("select id from public.v1_projects where project_ref='DRAFT-RACE';")
    if not existing.stdout.strip():
        created = run(session(f"select public.v1_create_project('{json.dumps(fixture)}'::jsonb, '{uuid.uuid4()}')"))
        assert created.returncode == 0, created.stderr
    ids = run("select p.id,s.id from public.v1_projects p join public.v1_project_scopes s on s.project_id=p.id and s.scope_kind='common' where p.project_ref='DRAFT-RACE';")
    project, scope = ids.stdout.strip().split('|')
    cases = [('sync', 'delete'), ('delete', 'sync'), ('save', 'delete'), ('delete', 'save')]
    timings = [race(first, second, project, scope) for first, second in cases for _ in range(3)]
    print(json.dumps({'two_session_races_passed': len(timings),
                      'maximum_ms_including_400ms_lock': max(timings),
                      'cases': cases}))
    rest_contract()
