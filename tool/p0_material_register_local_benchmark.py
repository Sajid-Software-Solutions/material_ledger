#!/usr/bin/env python3
"""Local-only before/after MR register benchmark. Never accepts a remote DSN.

Creates 30 isolated projects / 600 MRs / 2,400 lines, exercises independent
Postgres sessions at 5/10/20/30 concurrency, records server-side RPC latency
and EXPLAIN ANALYZE BUFFERS WAL SETTINGS, then removes only its own fixtures.
This is a read-load benchmark, not full workflow/browser/staging acceptance.
Run it while other database test suites are stopped: committed synthetic rows
would intentionally be visible to aggregate read tests until fixture cleanup.
"""
import concurrent.futures
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import threading
import time

ROOT = Path(__file__).resolve().parent.parent
CONTAINER = 'supabase_db_material_ledger'
BASELINE = 'v1_list_unified_material_request_summaries_p0_baseline'
OUTPUT = Path(os.environ.get('P0_BENCHMARK_OUTPUT', '/tmp/yorks-p0-register-benchmark'))
PREFIX = 'P0-REGISTER-LOAD-'


def sql(statement):
    result = subprocess.run(['docker', 'exec', '-i', CONTAINER, 'psql', '-X', '-Atq',
        '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres'],
        input=statement, text=True, capture_output=True, timeout=90)
    if result.returncode:
        raise RuntimeError(result.stderr.strip())
    return result.stdout.strip()


def claims(role):
    suffix = {'admin': '004', 'project_engineer': '001', 'site_engineer': '002',
        'procurement': '003', 'project_manager': '010'}[role]
    value = json.dumps({'sub': '10000000-0000-4000-8000-000000000'+suffix,
        'role': 'authenticated', 'app_metadata': {'role': role}})
    return "set request.jwt.claims = '"+value+"';\n"


def percentile(values, p):
    return sorted(values)[max(0, int(len(values)*p + 0.999999)-1)] if values else None


def cleanup():
    sql(f"""begin;
    -- Local fixture cleanup only. This setting is transaction/session-local;
    -- it never changes a trigger or grant used by another test session.
    set local session_replication_role=replica;
    delete from public.v1_material_request_revision_snapshots where request_id in
      (select id from public.v1_material_requests where request_number like '{PREFIX}%' and title='Synthetic load record');
    delete from public.v1_material_request_lines where request_id in
      (select id from public.v1_material_requests where request_number like '{PREFIX}%');
    delete from public.v1_material_requests where request_number like '{PREFIX}%';
    delete from public.v1_project_members where project_id in
      (select id from public.v1_projects where project_ref like '{PREFIX}%');
    delete from public.v1_project_scopes where project_id in
      (select id from public.v1_projects where project_ref like '{PREFIX}%');
    delete from public.v1_projects where project_ref like '{PREFIX}%';
    drop function if exists public.{BASELINE}(uuid,text,text[],uuid,text,timestamptz,boolean,text,text,integer,integer,text,text);
    commit;""")


def setup():
    baseline = (ROOT/'supabase/migrations/20260928144343_optimize_unified_material_request_register_setwise.sql').read_text()
    sql(baseline.replace('v1_list_unified_material_request_summaries', BASELINE))
    sql(f"""begin;
    insert into public.v1_projects(id,project_ref,name,state,created_by_auth_user_id,created_by_role)
    select md5('{PREFIX}project-'||i)::uuid,'{PREFIX}'||i,'P0 synthetic read-load project','active',
      '10000000-0000-4000-8000-000000000001','project_engineer' from generate_series(1,30) i;
    insert into public.v1_project_scopes(id,project_id,scope_kind,scope_code,name)
    select md5('{PREFIX}scope-'||i)::uuid,md5('{PREFIX}project-'||i)::uuid,'building','main','Main'
      from generate_series(1,30) i;
    insert into public.v1_project_members(project_id,member_auth_user_id,project_role,effective_from,reason,assigned_by_auth_user_id,assigned_by_role)
    select md5('{PREFIX}project-'||i)::uuid, actor,
      case when actor='10000000-0000-4000-8000-000000000001' then 'project_engineer' else 'site_engineer' end,
      now()-interval '1 day','P0 load fixture','10000000-0000-4000-8000-000000000004','admin'
      from generate_series(1,30) i cross join unnest(array['10000000-0000-4000-8000-000000000001'::uuid,'10000000-0000-4000-8000-000000000002'::uuid]) actor;
    insert into public.v1_material_requests(id,project_id,scope_id,request_number,title,timing,state,record_version,
      created_by_auth_user_id,requester_display_name,requester_project_role,requester_exact_role,current_action_owner_role,current_action_code,submitted_at,updated_at)
    select md5('{PREFIX}request-'||i)::uuid,md5('{PREFIX}project-'||((i-1)/20+1))::uuid,
      md5('{PREFIX}scope-'||((i-1)/20+1))::uuid,'{PREFIX}'||i,'Synthetic load record','normal',
      case i%4 when 0 then 'approved_for_arrangement' when 1 then 'awaiting_request_approval' when 2 then 'arranging' else 'closed' end,2,
      '10000000-0000-4000-8000-000000000002','P0 synthetic requester','site_engineer','site_engineer',
      case i%4 when 1 then 'project_engineer' else 'procurement' end,'arrange',now()-interval '1 day',now()-i*interval '1 second'
      from generate_series(1,600) i;
    insert into public.v1_material_request_lines(id,request_id,display_order,source_kind,item_description,requested_qty,unit)
    select md5('{PREFIX}line-'||i||'-'||j)::uuid,md5('{PREFIX}request-'||i)::uuid,j,'custom','Synthetic material '||j,10,'Nos'
      from generate_series(1,600) i cross join generate_series(1,4) j;
    analyze public.v1_material_requests;
    analyze public.v1_material_request_lines;
    analyze public.v1_project_members;
    commit;""")


def plan(function_body, output):
    query = function_body[function_body.index('  with\n'):function_body.index('  return v_result;')]
    query = query.replace(' into v_result', '')
    replacements = {'v_actor': "'10000000-0000-4000-8000-000000000004'::uuid", 'v_exact_role': "'admin'::text", 'v_role': "'admin'::text", 'v_actor_active': 'true',
        'v_allow_self_approval': "public.v1_material_request_published_policy_boolean('requests.allow_authorized_creator_self_approval',true)",
        'v_limit': '15', 'v_offset': '0', 'v_search': 'null::text', 'v_now': 'statement_timestamp()',
        'p_project_id': 'null::uuid', 'p_search': 'null::text', 'p_states': 'null::text[]', 'p_scope_id': 'null::uuid',
        'p_requester': 'null::text', 'p_updated_after': 'null::timestamptz', 'p_attention_only': 'false',
        'p_metric': "'all'", 'p_sort': "'updated_desc'", 'p_register_view': "'total'", 'p_request_kind': "'all'"}
    for variable, value in replacements.items():
        query = re.sub(r'\b'+variable+r'\b', value, query)
    result = sql(claims('admin')+"set statement_timeout='8s';\nEXPLAIN (ANALYZE, BUFFERS, WAL, SETTINGS, FORMAT JSON) "+query)
    output.write_text(result+'\n')
    return json.loads(result)[0]['Execution Time']


# Adapt timing output: a single result row avoids psql/client wall clock timing.
def run_worker(function_name, index, barrier):
    role = ['admin','project_engineer','site_engineer','procurement','project_manager'][index%5]
    kind = 'detail' if index%5 == 4 else 'register'
    command = (f"public.{function_name}(p_limit=>15,p_request_kind=>'all')" if kind=='register'
      else "public.v1_material_request_projection(md5('P0-REGISTER-LOAD-request-1')::uuid)")
    barrier.wait()
    try:
        result=sql(claims(role)+f"""set role authenticated; set statement_timeout='8s';
        with started as materialized (select clock_timestamp() t),
        response as materialized (select {command} data,started.t from started)
        select jsonb_build_object('ms',extract(epoch from(clock_timestamp()-t))*1000,
          'items',coalesce(jsonb_array_length(data->'items'),0)) from response;""")
        return {'kind':kind,'role':role,'ok':True,**json.loads(result)}
    except RuntimeError as error:
        return {'kind':kind,'role':role,'ok':False,'error':str(error)[:300]}


def main():
    actual=subprocess.check_output(['docker','inspect',CONTAINER,'--format','{{index .Config.Labels "com.supabase.cli.workdir"}}'],text=True).strip()
    if Path(actual).resolve()!=ROOT.resolve():
        raise RuntimeError('Refusing non-repository-local database container')
    OUTPUT.mkdir(parents=True,exist_ok=True)
    cleanup()
    report={'scope':'local synthetic mixed register/detail read load; no critical workflow writes or HTTP/browser evidence','projects':30,'requests':600,'lines':2400,'rounds':[]}
    try:
        setup()
        for label,function_name,file in [('before',BASELINE,'20260928144343_optimize_unified_material_request_register_setwise.sql'),('after','v1_list_unified_material_request_summaries','20261015081241_p0_register_permission_graph_memoization.sql')]:
            body=(ROOT/'supabase/migrations'/file).read_text()
            report[label+'_plan_ms']=plan(body,OUTPUT/(label+'-explain.json'))
            for concurrency in [5,10,20,30]:
                samples=[]
                for repeat in range(3):
                    barrier=threading.Barrier(concurrency)
                    with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency) as pool:
                        samples.extend(list(pool.map(lambda i:run_worker(function_name,i,barrier),range(concurrency))))
                row={'version':label,'concurrency':concurrency,'samples':samples}
                for kind in ['register','detail']:
                    durations=[s['ms'] for s in samples if s['ok'] and s['kind']==kind]
                    row[kind]={'count':len(durations),'p50_ms':statistics.median(durations) if durations else None,
                        'p95_ms':percentile(durations,.95),'p99_ms':percentile(durations,.99)}
                row['errors']=[s for s in samples if not s['ok']]
                report['rounds'].append(row)
                (OUTPUT/'report.json').write_text(json.dumps(report,indent=2)+'\n')
                print(json.dumps({k:v for k,v in row.items() if k!='samples'}),flush=True)
    finally:
        cleanup()
    print('Evidence: '+str(OUTPUT),flush=True)

if __name__=='__main__':
    main()
