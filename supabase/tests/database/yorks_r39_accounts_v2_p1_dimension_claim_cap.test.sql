-- R39 Accounts Workspace V2 — P1 pgTAP: dimension claim cap across baseline revisions
--
-- Proves the P0 fix (migration 20261105094500_accounts_v2_p1_dimension_claim_cap):
--   * the single eligible source is byte-identical to the legacy percent-mode formula;
--   * "already claimed" is summed across ALL baseline revisions by the stable
--     dimension (project, building scope, stage_key), not a single progress row;
--   * a claim on a new baseline revision cannot re-claim capacity already claimed
--     on an earlier revision (the double-claim hole is closed);
--   * the projection helper (v1_accounts_consumed_claim_amount, used by
--     v1_list_billing_progress) agrees with the cap helper to the fil.
--
-- Scenario: contract 100,000 AED, one building at 100%, default stages; the
-- "design" stage is 10% -> stage value 10,000.00. Confirm 100% -> eligible
-- 10,000.00. Claim 6,000 on revision 1. Revise the baseline (revision 2),
-- re-confirm design 100%, then attempt to claim again.

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- ---------------------------------------------------------------------------
-- Fixtures (superuser): project, building scope, PE membership, evidence doc.
-- Reuses the seeded per-role auth users (PE ...0001, admin ...0004).
-- ---------------------------------------------------------------------------
insert into public.v1_projects(id,project_ref,name,state,current_action_owner_role,created_by_auth_user_id,created_by_role)
values('39f10000-0000-4000-8000-000000000001','R39-V2P1-001','R39 V2 P1 dimension claim cap','active','project_engineer','10000000-0000-4000-8000-000000000004','admin');

insert into public.v1_project_scopes(id,project_id,scope_kind,scope_code,name,is_immutable)
values('39f20000-0000-4000-8000-000000000001','39f10000-0000-4000-8000-000000000001','building','b01','Building 01',false);

insert into public.v1_project_members(project_id,member_auth_user_id,project_role,effective_from,reason,assigned_by_auth_user_id,assigned_by_role)
values('39f10000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','project_engineer',clock_timestamp()-interval '1 day','V2 P1 project authority','10000000-0000-4000-8000-000000000004','admin');

insert into public.v1_documents(id,classification,created_by_auth_user_id,created_by_role)
values('39f30000-0000-4000-8000-000000000001','operational','10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_document_versions(id,document_id,revision_number,object_path,original_file_name,mime_type,byte_size,sha256,origin,uploaded_by_auth_user_id,uploaded_by_role)
values('39f31000-0000-4000-8000-000000000001','39f30000-0000-4000-8000-000000000001',1,'r39/v2p1/progress.pdf','progress.pdf','application/pdf',128,repeat('c',64),'uploaded','10000000-0000-4000-8000-000000000004','admin');
update public.v1_documents set current_version_id='39f31000-0000-4000-8000-000000000001' where id='39f30000-0000-4000-8000-000000000001';
insert into public.v1_document_links(id,document_id,project_id,entity_type,entity_id,linked_by_auth_user_id,linked_by_role)
values('39f32000-0000-4000-8000-000000000001','39f30000-0000-4000-8000-000000000001','39f10000-0000-4000-8000-000000000001','project','39f10000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000004','admin');

create temporary table v1_r39_p1_results(result_key text primary key, payload jsonb not null);
grant select,insert,update on v1_r39_p1_results to authenticated;

-- ---------------------------------------------------------------------------
-- Revision 1: admin initializes the baseline; PE confirms design to 100%.
-- ---------------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
insert into v1_r39_p1_results select 'baseline1', public.v1_initialize_project_commercial_baseline(
  '39f10000-0000-4000-8000-000000000001','100000.00','AED','5.0000',null,null,
  jsonb_build_array(jsonb_build_object('building_scope_id','39f20000-0000-4000-8000-000000000001','allocation_percent','100.0000')),
  null,'{}'::jsonb,'V2 P1 baseline','39f90000-0000-4000-8000-000000000001');

reset role;
insert into v1_r39_p1_results select 'progress1', jsonb_build_object('progress_entry_id', id)
from public.v1_accounts_billing_progress
where project_id='39f10000-0000-4000-8000-000000000001' and stage_key='design';

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-pe"}}',true);
insert into v1_r39_p1_results select 'confirm1', public.v1_confirm_billing_progress(
  '39f10000-0000-4000-8000-000000000001',
  (select (payload->>'progress_entry_id')::uuid from v1_r39_p1_results where result_key='progress1'),
  1,'100.0000','Design complete', array['39f30000-0000-4000-8000-000000000001'::uuid],
  'Confirm design revision 1','39f90000-0000-4000-8000-000000000002');

-- Eligible helper is byte-identical to the legacy percent-mode formula.
-- Internal helpers are revoked from authenticated, so assert them as superuser.
reset role;
select is(
  public.v1_accounts_progress_eligible_amount(
    (select (payload->>'progress_entry_id')::uuid from v1_r39_p1_results where result_key='progress1'))::text,
  '10000.00',
  'Eligible helper returns the stage value for a 100%-confirmed 10% stage'
);
select is(
  public.v1_accounts_progress_eligible_amount(
    (select (payload->>'progress_entry_id')::uuid from v1_r39_p1_results where result_key='progress1')),
  round(public.v1_accounts_stage_value(
    (select (payload->>'progress_entry_id')::uuid from v1_r39_p1_results where result_key='progress1'))
    * 100 / 100, 2),
  'Eligible helper is byte-identical to round(stage_value x confirmed / 100, 2)'
);

-- PE claims 6,000 of 10,000 on revision 1 (draft reserves capacity).
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-pe"}}',true);
insert into v1_r39_p1_results select 'claim_rev1', public.v1_create_client_claim_draft(
  '39f10000-0000-4000-8000-000000000001','CLM-V2P1-A',date '2026-08-01',date '2026-08-25',
  jsonb_build_array(jsonb_build_object(
    'progress_entry_id',(select (payload->>'progress_entry_id')::uuid from v1_r39_p1_results where result_key='progress1'),
    'claimed_amount','6000.00','evidence_reference','VAL-V2P1-A')),
  'Revision 1 claim','39f90000-0000-4000-8000-000000000003');
select is((select payload->>'status' from v1_r39_p1_results where result_key='claim_rev1'),'draft','Revision 1 claim reserves 6,000');

-- ---------------------------------------------------------------------------
-- Revision 2: admin revises the baseline; PE re-confirms design to 100%.
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',true);
insert into v1_r39_p1_results select 'baseline2', public.v1_revise_project_commercial_baseline(
  '39f10000-0000-4000-8000-000000000001',1,
  '100000.00','AED','5.0000',null,null,
  jsonb_build_array(jsonb_build_object('building_scope_id','39f20000-0000-4000-8000-000000000001','allocation_percent','100.0000')),
  null,'{}'::jsonb,'V2 P1 baseline revision 2','39f90000-0000-4000-8000-000000000004');
select is((select payload->>'baseline_revision_number' from v1_r39_p1_results where result_key='baseline2'),'2','Baseline advances to revision 2');

reset role;
insert into v1_r39_p1_results select 'progress2', jsonb_build_object('progress_entry_id', id)
from public.v1_accounts_billing_progress
where project_id='39f10000-0000-4000-8000-000000000001' and stage_key='design'
  and baseline_revision_id = (select current_baseline_revision_id
    from public.v1_accounts_project_commercial_profiles
    where project_id='39f10000-0000-4000-8000-000000000001');

-- The revision-2 design row is a NEW progress row (distinct id, same dimension).
select isnt(
  (select payload->>'progress_entry_id' from v1_r39_p1_results where result_key='progress2'),
  (select payload->>'progress_entry_id' from v1_r39_p1_results where result_key='progress1'),
  'A baseline revision materializes a new progress row for the same dimension'
);

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-pe"}}',true);
insert into v1_r39_p1_results select 'confirm2', public.v1_confirm_billing_progress(
  '39f10000-0000-4000-8000-000000000001',
  (select (payload->>'progress_entry_id')::uuid from v1_r39_p1_results where result_key='progress2'),
  1,'100.0000','Design still complete', array['39f30000-0000-4000-8000-000000000001'::uuid],
  'Confirm design revision 2','39f90000-0000-4000-8000-000000000005');

-- ---------------------------------------------------------------------------
-- The fix: claimed is dimension-wide across revisions; the cap and the
-- projection helper agree; the old per-row keying would have missed it.
-- ---------------------------------------------------------------------------
reset role;
select is(
  public.v1_accounts_dimension_claimed_amount(
    '39f10000-0000-4000-8000-000000000001','39f20000-0000-4000-8000-000000000001','design',null)::text,
  '6000.00',
  'Dimension-claimed counts the revision-1 claim against the revision-2 dimension'
);
select is(
  public.v1_accounts_consumed_claim_amount(
    (select (payload->>'progress_entry_id')::uuid from v1_r39_p1_results where result_key='progress2'))::text,
  '6000.00',
  'Consumed helper (used by the projection) is dimension-wide for the revision-2 row'
);
-- Documents the bug the fix closes: the old per-progress-row sum saw nothing.
select is(
  (select coalesce(sum(claimed_amount),0)::text from public.v1_accounts_client_claim_lines
   where progress_entry_id=(select (payload->>'progress_entry_id')::uuid from v1_r39_p1_results where result_key='progress2')),
  '0',
  'The revision-2 progress row has no lines of its own (old keying would have allowed a re-claim)'
);
-- Cap and projection agree to the fil.
select is(
  public.v1_accounts_consumed_claim_amount(
    (select (payload->>'progress_entry_id')::uuid from v1_r39_p1_results where result_key='progress2'))::numeric(20,2),
  public.v1_accounts_dimension_claimed_amount(
    '39f10000-0000-4000-8000-000000000001','39f20000-0000-4000-8000-000000000001','design',null),
  'Projection consumed equals the cap dimension-claimed to the fil'
);

-- Cross-revision double-claim is DENIED: available = 10,000 - 6,000 = 4,000.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-pe"}}',true);
select throws_ok(
  $$select public.v1_create_client_claim_draft(
    '39f10000-0000-4000-8000-000000000001','CLM-V2P1-OVER',date '2026-09-01',date '2026-09-25',
    jsonb_build_array(jsonb_build_object(
      'progress_entry_id',(select (payload->>'progress_entry_id')::uuid from v1_r39_p1_results where result_key='progress2'),
      'claimed_amount','6000.00','evidence_reference','VAL-V2P1-OVER')),
    'Revision 2 over-claim','39f90000-0000-4000-8000-000000000006')$$,
  '23514','R39_ACCOUNTS_CLAIM_CAP_EXCEEDED',
  'A revision-2 claim cannot re-claim capacity already claimed on revision 1'
);

-- A claim within the remaining 4,000 is allowed.
insert into v1_r39_p1_results select 'claim_rev2', public.v1_create_client_claim_draft(
  '39f10000-0000-4000-8000-000000000001','CLM-V2P1-OK',date '2026-09-01',date '2026-09-25',
  jsonb_build_array(jsonb_build_object(
    'progress_entry_id',(select (payload->>'progress_entry_id')::uuid from v1_r39_p1_results where result_key='progress2'),
    'claimed_amount','4000.00','evidence_reference','VAL-V2P1-OK')),
  'Revision 2 remaining claim','39f90000-0000-4000-8000-000000000007');
select is((select payload->>'status' from v1_r39_p1_results where result_key='claim_rev2'),'draft','A revision-2 claim within the remaining 4,000 is allowed');

-- Excluding a claim from the dimension total restores its capacity (the
-- revise-successor path passes the predecessor as p_excluded_claim_id).
reset role;
select is(
  public.v1_accounts_dimension_claimed_amount(
    '39f10000-0000-4000-8000-000000000001','39f20000-0000-4000-8000-000000000001','design',
    (select (payload->>'claim_id')::uuid from v1_r39_p1_results where result_key='claim_rev1'))::text,
  '4000.00',
  'Excluding the revision-1 claim removes only its share from the dimension total'
);

reset role;
select finish();
rollback;
