begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select ok(not has_table_privilege('authenticated',
  'public.v1_material_request_private_draft_retirements', 'select,insert,update,delete'),
  'ordinary signed-in clients cannot inspect or mutate retirement markers');
select ok(not has_table_privilege('anon',
  'public.v1_material_request_private_draft_retirements', 'select,insert,update,delete'),
  'anonymous clients cannot inspect or mutate retirement markers');
select ok((select relrowsecurity from pg_class where oid =
  'public.v1_material_request_private_draft_retirements'::regclass), 'retirement RLS is enabled');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}', true);

select lives_ok($$select public.v1_sync_material_request_private_draft(
  '{"draft_id":"de270000-0000-4000-8000-000000000001","expected_sync_version":0,"client_updated_at":"2026-09-27T00:00:00Z","draft_data":{"title":"private","lines":[]}}',
  'de271000-0000-4000-8000-000000000001')$$, 'owner creates a private account draft');
select throws_ok($$select public.v1_delete_my_material_request_private_draft(
  '{"draft_id":"de270000-0000-4000-8000-000000000001","expected_sync_version":0}',
  'de271000-0000-4000-8000-000000000002')$$, '40001', 'V1_PRIVATE_DRAFT_VERSION_CONFLICT',
  'stale deletion is rejected without mutating the draft');
reset role;
select is((select count(*) from public.v1_material_request_private_drafts where
  draft_id='de270000-0000-4000-8000-000000000001'), 1::bigint, 'stale delete preserves draft');
set local role authenticated;

select lives_ok($$select public.v1_delete_my_material_request_private_draft(
  '{"draft_id":"de270000-0000-4000-8000-000000000001","expected_sync_version":1}',
  'de271000-0000-4000-8000-000000000003')$$, 'owner deletes current account copy');
select lives_ok($$select public.v1_delete_my_material_request_private_draft(
  '{"draft_id":"de270000-0000-4000-8000-000000000001","expected_sync_version":1}',
  'de271000-0000-4000-8000-000000000003')$$, 'exact delete retry replays success');
select lives_ok($$select public.v1_delete_my_material_request_private_draft(
  '{"draft_id":"de270000-0000-4000-8000-000000000001","expected_sync_version":1}',
  'de271000-0000-4000-8000-000000000004')$$, 'another delete retry remains safe');
select throws_ok($$select public.v1_sync_material_request_private_draft(
  '{"draft_id":"de270000-0000-4000-8000-000000000001","expected_sync_version":0,"client_updated_at":"2026-09-27T00:00:00Z","draft_data":{"title":"revive","lines":[]}}',
  'de271000-0000-4000-8000-000000000005')$$, '55000', 'V1_PRIVATE_DRAFT_DELETED', 'offline autosave cannot resurrect deleted ID');
select throws_ok($$select public.v1_sync_material_request_private_draft(
  '{"draft_id":"de270000-0000-4000-8000-000000000001","expected_sync_version":0,"client_updated_at":"2026-09-27T00:00:00Z","draft_data":{"title":"private","lines":[]}}',
  'de271000-0000-4000-8000-000000000001')$$, '55000', 'V1_PRIVATE_DRAFT_DELETED', 'old sync receipt cannot restore client recovery after deletion');
select lives_ok($$select public.v1_delete_my_material_request_private_draft(
  '{"draft_id":"de270000-0000-4000-8000-000000000002","expected_sync_version":0}',
  'de271000-0000-4000-8000-000000000006')$$, 'local-only draft can be retired before its first autosave');
select throws_ok($$select public.v1_sync_material_request_private_draft(
  '{"draft_id":"de270000-0000-4000-8000-000000000002","expected_sync_version":0,"client_updated_at":"2026-09-27T00:00:00Z","draft_data":{"lines":[]}}',
  'de271000-0000-4000-8000-000000000007')$$, '55000', 'V1_PRIVATE_DRAFT_DELETED', 'first delayed autosave is rejected');
select throws_ok($$select public.v1_get_my_material_request_private_draft(
  'de270000-0000-4000-8000-000000000001')$$, '55000', 'V1_PRIVATE_DRAFT_DELETED',
  'resume identifies an owner-confirmed retirement without returning content');

reset role;
select is((select count(*) from public.v1_audit_events where entity_id=
  'de270000-0000-4000-8000-000000000001' and event_type='material_request_private_draft_deleted'), 1::bigint, 'delete retries create one audit event');
select is((select count(*) from public.v1_material_request_private_draft_retirements
  where draft_id='de270000-0000-4000-8000-000000000001'), 1::bigint, 'one retirement marker survives retries');

-- Four required platform roles keep the same owner-only recovery authority.
-- Admin may not erase another actor's private draft by guessing its UUID.
do $$declare r record; begin
  for r in select auth_user_id, canonical_role_snapshot as app_role from public.v1_profiles
    where auth_user_id in ('10000000-0000-4000-8000-000000000001',
      '10000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000003',
      '10000000-0000-4000-8000-000000000004')
  loop
    perform set_config('request.jwt.claims', jsonb_build_object('sub',r.auth_user_id,
      'role','authenticated','app_metadata',jsonb_build_object('role',r.app_role))::text, true);
    perform public.v1_sync_material_request_private_draft(
      '{"draft_id":"de270000-0000-4000-8000-000000000010","expected_sync_version":0,"client_updated_at":"2026-09-27T00:00:00Z","draft_data":{"lines":[]}}', gen_random_uuid());
  end loop;
end $$;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}', true);
select lives_ok($$select public.v1_delete_my_material_request_private_draft(
  '{"draft_id":"de270000-0000-4000-8000-000000000010","expected_sync_version":1}', gen_random_uuid())$$, 'Admin deletes only its own recovery copy');
reset role;
select is((select count(*) from public.v1_material_request_private_drafts where
  draft_id='de270000-0000-4000-8000-000000000010'), 3::bigint, 'Engineering and Procurement drafts remain intact after Admin deletion');
do $$declare r record; begin
  for r in select auth_user_id, canonical_role_snapshot as app_role from public.v1_profiles where auth_user_id in (
    '10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000003')
  loop
    perform set_config('request.jwt.claims', jsonb_build_object('sub',r.auth_user_id,
      'role','authenticated','app_metadata',jsonb_build_object('role',r.app_role))::text, true);
    perform public.v1_delete_my_material_request_private_draft(
      '{"draft_id":"de270000-0000-4000-8000-000000000010","expected_sync_version":1}', gen_random_uuid());
  end loop;
end $$;
select is((select count(*) from public.v1_material_request_private_drafts where
  draft_id='de270000-0000-4000-8000-000000000010'), 0::bigint, 'Project/Site Engineers and Procurement delete their own recovery copies');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}', true);
select public.v1_create_project('{"project_ref":"DELETE-REL","name":"Deletion safety","parties":{},"initial_members":[],"buildings":[{"code":"B1","name":"Test building"}],"attachments":[]}', 'de271000-0000-4000-8000-000000000020');
reset role;
create temp table deletion_payload as select jsonb_build_object('request_id',
  'de270000-0000-4000-8000-000000000001', 'expected_version',0,
  'project_id',p.id,'scope_id',s.id,'timing','normal','lines','[]'::jsonb) payload
  from public.v1_projects p join public.v1_project_scopes s on s.project_id=p.id
  and s.scope_kind='common' where p.project_ref='DELETE-REL';
grant select on deletion_payload to authenticated;
set local role authenticated;
select throws_ok($$select public.v1_save_material_request_draft((select payload from deletion_payload))$$,
  '55000', 'V1_PRIVATE_DRAFT_DELETED', 'stale connected Save cannot create a request after deletion');
reset role;
insert into public.v1_material_request_private_drafts
(draft_id,owner_auth_user_id,sync_version,draft_data,client_updated_at,created_at,updated_at)
select 'de270000-0000-4000-8000-000000000020','10000000-0000-4000-8000-000000000001',1,
 payload-'request_id'-'expected_version',now(),now(),now() from deletion_payload;
set local role authenticated;
select lives_ok($$select public.v1_save_material_request_draft((select payload ||
  '{"request_id":"de270000-0000-4000-8000-000000000020"}' from deletion_payload))$$, 'a fresh UUID still saves normally');
reset role;
select is((select count(*) from public.v1_material_request_private_drafts where draft_id='de270000-0000-4000-8000-000000000020'),0::bigint,'exact accepted save snapshot is atomically retired');
select is((select reason from public.v1_material_request_recovery_archive where draft_id='de270000-0000-4000-8000-000000000020' and sync_version=1),'saved_snapshot_matches','save archive explains its supersession');
set local role authenticated;
select throws_ok($$select public.v1_sync_material_request_private_draft(
  '{"draft_id":"de270000-0000-4000-8000-000000000020","expected_sync_version":0,"client_updated_at":"2026-09-27T00:00:00Z","draft_data":{"lines":[]}}', gen_random_uuid())$$,
  '55000', 'V1_PRIVATE_DRAFT_ALREADY_SAVED', 'delayed autosave cannot recreate a saved request recovery');
select is((select count(*) from jsonb_array_elements(public.v1_list_my_material_request_private_drafts()) draft
  where draft->>'draft_id'='de270000-0000-4000-8000-000000000020'), 0::bigint,
  'saved workflow records are excluded from the private recovery notice');
select lives_ok($$select public.v1_delete_my_material_request_private_draft(
  '{"draft_id":"de270000-0000-4000-8000-000000000020","expected_sync_version":0}', gen_random_uuid())$$,
  'removing absent recovery succeeds and preserves saved workflow draft');
reset role;
select is((select count(*) from public.v1_material_requests where id=
  'de270000-0000-4000-8000-000000000020'),1::bigint,'saved MR remains intact');

-- A retained legacy recovery contains extra input, including unknown keys.
reset role;
insert into public.v1_material_request_private_drafts
(draft_id,owner_auth_user_id,sync_version,draft_data,client_updated_at,created_at,updated_at)
values ('de270000-0000-4000-8000-000000000020','10000000-0000-4000-8000-000000000001',7,
 '{"title":"Extra work","unknown_future_field":{"preserve":true},"lines":[{"id":"extra-line"}]}',now(),now(),now());
set local role authenticated;
select is((public.v1_get_my_material_request_private_draft('de270000-0000-4000-8000-000000000020')->>'saved_request_version')::int,
  1, 'saved recovery identifies its normalized version');
select is((select count(*) from jsonb_array_elements(public.v1_list_my_material_request_private_drafts()) d
  where d->>'draft_id'='de270000-0000-4000-8000-000000000020'),1::bigint,
  'divergent saved recovery is visible for review');
select throws_ok($$select public.v1_delete_my_material_request_private_draft(
  '{"draft_id":"de270000-0000-4000-8000-000000000020","expected_sync_version":6}',gen_random_uuid())$$,
  '40001','V1_PRIVATE_DRAFT_VERSION_CONFLICT','newer saved recovery cannot be erased by stale delete');
select lives_ok($$select public.v1_delete_my_material_request_private_draft(
  '{"draft_id":"de270000-0000-4000-8000-000000000020","expected_sync_version":7}',gen_random_uuid())$$,
  'explicit deletion removes only current saved recovery');
select throws_ok($$select public.v1_archive_material_request_recovery(
  'de270000-0000-4000-8000-000000000020',auth.uid(),'request_progressed')$$,
  '42501','permission denied for function v1_archive_material_request_recovery','ordinary callers cannot invoke cleanup helper');
reset role;
select is((select draft_data->'unknown_future_field' from public.v1_material_request_recovery_archive
  where draft_id='de270000-0000-4000-8000-000000000020' and sync_version=7),'{"preserve":true}'::jsonb,
  'archive retains unknown recovery contents verbatim');
select is((select count(*) from public.v1_material_request_private_draft_retirements
  where draft_id='de270000-0000-4000-8000-000000000020'),0::bigint,
  'recovery removal does not retire the editable business draft');
select ok(not has_table_privilege('authenticated','public.v1_material_request_recovery_archive','select,insert,update,delete'),
  'archive has no ordinary client authority');
select ok(not has_table_privilege('anon','public.v1_material_request_recovery_archive','select,insert,update,delete'),
  'archive has no anonymous authority');
set local role authenticated;
select lives_ok($$select public.v1_save_material_request_draft((select payload ||
  '{"request_id":"de270000-0000-4000-8000-000000000020","expected_version":1}' from deletion_payload))$$,
  'saved request remains editable after recovery removal');
reset role;
-- Simulate a different pre-existing snapshot; progression archives atomically.
insert into public.v1_material_request_private_drafts
(draft_id,owner_auth_user_id,sync_version,draft_data,client_updated_at,created_at,updated_at)
values ('de270000-0000-4000-8000-000000000020','10000000-0000-4000-8000-000000000001',8,
 '{"title":"Pre-submit recovery","lines":[]}',now(),now(),now());
update public.v1_material_requests set state='closed', request_number='TEST-RECOVERY', submitted_at=now()
where id='de270000-0000-4000-8000-000000000020';
select is((select count(*) from public.v1_material_request_private_drafts
  where draft_id='de270000-0000-4000-8000-000000000020'),0::bigint,
  'progression removes active recovery in the same transaction');
select is((select count(*) from public.v1_material_request_recovery_archive
  where draft_id='de270000-0000-4000-8000-000000000020'),3::bigint,
  'all historical recovery versions remain preserved');
select is((select state from public.v1_material_requests
  where id='de270000-0000-4000-8000-000000000020'),'closed','progressed business state remains intact');
set local role authenticated;
select throws_ok($$select public.v1_get_my_material_request_private_draft(
  'de270000-0000-4000-8000-000000000020')$$,'55000','V1_PRIVATE_DRAFT_ALREADY_SAVED',
  'old private resume resolves to existing request instead of a draft editor');
select lives_ok($$select public.v1_delete_my_material_request_private_draft(
  '{"draft_id":"de270000-0000-4000-8000-000000000020","expected_sync_version":8}',gen_random_uuid())$$,
  'old-device recovery removal succeeds after progression');
select is(jsonb_array_length(public.v1_obsolete_material_request_recovery_ids(array[
  'de270000-0000-4000-8000-000000000020'::uuid,
  'de270000-0000-4000-8000-000000000001'::uuid,
  'de270000-0000-4000-8000-000000000099'::uuid])),2,
  'classification suppresses only confirmed progressed or retired IDs');
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',true);
select is(public.v1_obsolete_material_request_recovery_ids(array[
  'de270000-0000-4000-8000-000000000020'::uuid,
  'de270000-0000-4000-8000-000000000001'::uuid]),'[]'::jsonb,
  'another owner cannot classify a guessed request or retirement');
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}',true);
reset role;
update public.v1_profiles set is_active=false where auth_user_id='10000000-0000-4000-8000-000000000001';
set local role authenticated;
select throws_ok($$select public.v1_delete_my_material_request_private_draft(
  '{"draft_id":"de270000-0000-4000-8000-000000000030","expected_sync_version":0}', gen_random_uuid())$$,
  '22023', 'V1_PRIVATE_DRAFT_DELETE_INVALID', 'inactive actors cannot delete drafts');
reset role;
set local role anon;
select throws_ok($$select public.v1_delete_my_material_request_private_draft(
  '{"draft_id":"de270000-0000-4000-8000-000000000020","expected_sync_version":0}', gen_random_uuid())$$,
  '42501', 'permission denied for function v1_delete_my_material_request_private_draft', 'anonymous deletion is denied');
reset role;
select * from finish();
rollback;
