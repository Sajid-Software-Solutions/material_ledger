begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(16);

select ok(
  not has_function_privilege('anon', 'public.v1_raise_version_conflict(text)', 'execute')
  and not has_function_privilege('authenticated', 'public.v1_raise_version_conflict(text)', 'execute'),
  'The conflict helper is not an exposed RPC'
);
select ok(
  position('v1_raise_version_conflict' in pg_get_functiondef(
    'public.v1_sync_material_request_private_draft(jsonb,uuid)'::regprocedure)) > 0
  and position('v1_raise_version_conflict' in pg_get_functiondef(
    'public.v1_update_material_request_for_approval(jsonb,uuid)'::regprocedure)) > 0,
  'Both measured remaining conflict paths use the non-retryable envelope'
);

create temporary table conflict_results (sqlstate text, message text, detail text);
do $test$
declare v_state text; v_message text; v_detail text;
begin
  perform set_config('request.method', 'POST', true);
  begin
    perform public.v1_raise_version_conflict('V1_PRIVATE_DRAFT_VERSION_CONFLICT');
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate,
      v_message = message_text, v_detail = pg_exception_detail;
    insert into conflict_results values (v_state, v_message, v_detail);
  end;
end;
$test$;
select is((select sqlstate from conflict_results), 'PGRST', 'REST transaction is not classified as serialization failure');
select is((select (message::jsonb ->> 'code') from conflict_results), '40001', 'Existing clients retain their conflict code');
select is((select (detail::jsonb ->> 'status')::integer from conflict_results), 409, 'REST response is explicitly a conflict');
select is((select (message::jsonb ->> 'message') from conflict_results), 'V1_PRIVATE_DRAFT_VERSION_CONFLICT', 'Domain message remains unchanged');

insert into public.v1_material_request_private_drafts
  (draft_id, owner_auth_user_id, sync_version, draft_data, client_updated_at)
values
  ('b2500000-0000-4000-8000-000000000001',
   '10000000-0000-4000-8000-000000000002', 1, '{}', clock_timestamp());
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}', true);

select throws_ok(
  $$select public.v1_sync_material_request_private_draft(
    '{"draft_id":"b2500000-0000-4000-8000-000000000001","expected_sync_version":0,"client_updated_at":"2026-09-03T00:00:00Z","draft_data":{}}',
    'b2500000-0000-4000-8000-000000000002')$$,
  'PGRST', jsonb_build_object('code','40001','message','V1_PRIVATE_DRAFT_VERSION_CONFLICT','details',null,'hint',null)::text,
  'A stale REST recovery save fails once and does not overwrite'
);
select throws_ok(
  $$select public.v1_delete_my_material_request_private_draft(
    '{"draft_id":"b2500000-0000-4000-8000-000000000001","expected_sync_version":2}',
    'b2500000-0000-4000-8000-000000000003')$$,
  'PGRST', jsonb_build_object('code','40001','message','V1_PRIVATE_DRAFT_VERSION_CONFLICT','details',null,'hint',null)::text,
  'A stale REST delete fails once and does not delete'
);
select is((public.v1_get_my_material_request_private_draft('b2500000-0000-4000-8000-000000000001')->>'sync_version')::integer, 1, 'Both stale commands preserve the original draft');

reset role;
select is((select count(*) from public.v1_idempotency_keys
  where idempotency_key in ('b2500000-0000-4000-8000-000000000002','b2500000-0000-4000-8000-000000000003')),
  0::bigint, 'Failed commands roll back their idempotency claims');
select set_config('request.method', '', true);
select throws_ok($$select public.v1_raise_version_conflict('direct')$$, '40001', 'direct', 'Direct SQL callers retain the original contract');

set local role authenticated;
select set_config('request.method', 'POST', true);
select is((public.v1_sync_material_request_private_draft(
  '{"draft_id":"b2500000-0000-4000-8000-000000000001","expected_sync_version":1,"client_updated_at":"2026-09-03T00:00:00Z","draft_data":{}}',
  'b2500000-0000-4000-8000-000000000004')->>'sync_version')::integer, 2, 'A current-version REST save still succeeds');
select is((public.v1_sync_material_request_private_draft(
  '{"draft_id":"b2500000-0000-4000-8000-000000000001","expected_sync_version":1,"client_updated_at":"2026-09-03T00:00:00Z","draft_data":{}}',
  'b2500000-0000-4000-8000-000000000004')->>'sync_version')::integer, 2, 'An exact save retry still replays one result');
select is((public.v1_delete_my_material_request_private_draft(
  '{"draft_id":"b2500000-0000-4000-8000-000000000001","expected_sync_version":2}',
  'b2500000-0000-4000-8000-000000000005')->>'deleted')::boolean, true, 'A current-version REST delete still succeeds');
select is((public.v1_delete_my_material_request_private_draft(
  '{"draft_id":"b2500000-0000-4000-8000-000000000001","expected_sync_version":2}',
  'b2500000-0000-4000-8000-000000000005')->>'deleted')::boolean, true, 'An exact delete retry stays idempotent');
select set_config('request.method', '', true);
select throws_ok(
  $$select public.v1_get_my_material_request_private_draft('b2500000-0000-4000-8000-000000000001')$$,
  '55000', 'V1_PRIVATE_DRAFT_DELETED',
  'Owner receives confirmed retirement on another device'
);
select * from finish();
rollback;
