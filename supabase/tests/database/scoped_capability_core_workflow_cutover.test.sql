begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select no_plan();

select is(
  (
    select array_agg(catalog.capability_key order by catalog.capability_key)
    from public.v1_capability_catalog catalog
    where catalog.authorization_mode = 'enforced'
  ),
  array[
    'analytics.view',
    'approve_supplier_bill_payment',
    'boq.edit',
    'boq.manage_folders',
    'boq.view',
    'configure_project_commercials',
    'confirm_billing_progress',
    'delivery_orders.generate',
    'dispatch.create',
    'export_accounts_registers',
    'manage_client_invoices',
    'manage_pdc',
    'manage_supplier_bills',
    'material_requests.approve',
    'material_requests.cancel',
    'material_requests.close',
    'material_requests.create',
    'material_requests.edit',
    'material_requests.return_for_changes',
    'material_requests.submit',
    'material_requests.view',
    'permissions.delegate',
    'permissions.manage',
    'permissions.view',
    'prepare_client_claim',
    'procurement.arrange',
    'projects.archive',
    'projects.create',
    'projects.edit',
    'projects.view',
    'receipts.confirm',
    'record_client_certification',
    'record_client_payment',
    'returns.approve',
    'returns.create',
    'returns.dispatch',
    'returns.view',
    'review_commercial_progress',
    'suggest_billing_progress',
    'users.activation.manage',
    'users.create',
    'users.password.reset',
    'users.roles.assign',
    'users.view',
    'view_project_accounts',
    'view_project_commercial_values',
    'view_supplier_costs',
    'worker_records.manage',
    'worker_records.view',
    'workforce.attendance.maintain',
    'workforce.configuration.manage',
    'workforce.periods.reopen',
    'workforce.reports.export',
    'workforce.teams.manage',
    'workforce.timesheets.correct_during_review',
    'workforce.timesheets.final_approve',
    'workforce.timesheets.maintain',
    'workforce.timesheets.review',
    'workforce.timesheets.verify',
    'workforce.view',
    'workforce.workers.manage'
  ]::text[],
  'The exact aggregate allowlist contains only fully guarded cutovers'
);

select ok(
  not exists (
    select 1
    from public.v1_capability_catalog catalog
    where catalog.capability_key = any(array[
      'projects.change_state', 'projects.manage_team',
      'boq.import', 'boq.export',
      'material_requests.print', 'procurement.view',
      'procurement.external_readiness.manage', 'dispatch.view',
      'delivery_reports.print', 'receipts.view',
      'receipts.attach_evidence', 'returns.confirm'
    ]::text[])
      and catalog.authorization_mode <> 'shadow'
  ),
  'Combined or membership-role-specific consumers deliberately remain shadow'
);

create temporary table v1_cutover_revision_baseline (
  auth_user_id uuid primary key,
  revision bigint not null
) on commit drop;

insert into v1_cutover_revision_baseline (auth_user_id, revision)
select revision.auth_user_id, revision.revision
from public.v1_permission_revisions revision
join public.v1_profiles profile
  on profile.auth_user_id = revision.auth_user_id
where profile.is_active;

select is(
  public.v1_invalidate_active_permission_snapshots(),
  (select count(*)::integer from v1_cutover_revision_baseline),
  'The private cutover invalidator touches every active user exactly once'
);

select ok(
  not exists (
    select 1
    from v1_cutover_revision_baseline baseline
    join public.v1_permission_revisions revision
      on revision.auth_user_id = baseline.auth_user_id
    where revision.revision <> baseline.revision + 1
  ),
  'Every active permission revision advances by one monotonic step'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.v1_invalidate_active_permission_snapshots()', 'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.v1_invalidate_active_permission_snapshots()', 'execute'
  ),
  'Ordinary clients cannot invoke the permission snapshot invalidator'
);

select ok(
  position(
    'material_requests.edit' in pg_get_functiondef(
      'public.v1_save_material_request_draft(jsonb)'::regprocedure
    )
  ) > 0
  and position(
    'v1_can_create_material_request(v_project_id)' in pg_get_functiondef(
      'public.v1_save_material_request_draft(jsonb)'::regprocedure
    )
  ) > 0
  and position(
    'material_requests.submit' in pg_get_functiondef(
      'public.v1_submit_material_request(jsonb,uuid)'::regprocedure
    )
  ) > 0
  and position(
    'v1_can_create_material_request(v_project.id)' in pg_get_functiondef(
      'public.v1_submit_material_request(jsonb,uuid)'::regprocedure
    )
  ) = 0,
  'Draft creation, draft editing and submission use independent server guards'
);

select ok(
  position(
    'projects.manage_team' in pg_get_functiondef(
      'public.v1_assign_project_member(jsonb,uuid)'::regprocedure
    )
  ) = 0
  and position(
    'projects.manage_team' in pg_get_functiondef(
      'public.v1_revoke_project_member(jsonb,uuid)'::regprocedure
    )
  ) = 0
  and position(
    'projects.change_state' in pg_get_functiondef(
      'public.v1_set_project_state(jsonb,uuid)'::regprocedure
    )
  ) = 0,
  'Shadow team and state capabilities do not alter their legacy-authoritative RPCs'
);

-- Workshop In-Charge and Document Controller are not part of the historical
-- seed. Add exact-role test identities without changing any production data;
-- the transaction rolls them back with the rest of this fixture.
with personas(auth_user_id, email, display_name, app_role, app_user_id) as (
  values
    (
      '10000000-0000-4000-8000-000000000011'::uuid,
      'workshop.in.charge@capability.test',
      'Capability Workshop In-Charge',
      'workshop_in_charge',
      'usr-capability-workshop-in-charge'
    ),
    (
      '10000000-0000-4000-8000-000000000012'::uuid,
      'document.controller@capability.test',
      'Capability Document Controller',
      'document_controller',
      'usr-capability-document-controller'
    )
)
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select
  source.instance_id,
  persona.auth_user_id,
  source.aud,
  source.role,
  persona.email,
  source.encrypted_password,
  source.email_confirmed_at,
  jsonb_build_object(
    'provider', 'email', 'providers', jsonb_build_array('email'),
    'role', persona.app_role, 'app_user_id', persona.app_user_id,
    'caps', '[]'::jsonb
  ),
  jsonb_build_object(
    'full_name', persona.display_name, 'must_change_password', false
  ),
  source.created_at,
  source.updated_at,
  '', '', '', ''
from personas persona
cross join lateral (
  select seed_user.*
  from auth.users seed_user
  where seed_user.id = '10000000-0000-4000-8000-000000000001'::uuid
) source
on conflict (id) do nothing;

insert into public.v1_profiles (
  auth_user_id, legacy_app_user_id, display_name,
  canonical_role_snapshot, is_active
)
values
  (
    '10000000-0000-4000-8000-000000000011',
    'usr-capability-workshop-in-charge',
    'Capability Workshop In-Charge', 'project_engineer', true
  ),
  (
    '10000000-0000-4000-8000-000000000012',
    'usr-capability-document-controller',
    'Capability Document Controller', 'project_engineer', true
  )
on conflict (auth_user_id) do nothing;

insert into public.v1_projects (
  id, project_ref, name, state, current_action_owner_role,
  created_by_auth_user_id, created_by_role
)
values
  (
    'cc000000-0000-4000-8000-000000000001', 'CUTOVER-001',
    'Core cutover project one', 'active', 'project_engineer',
    '10000000-0000-4000-8000-000000000004', 'admin'
  ),
  (
    'cc000000-0000-4000-8000-000000000002', 'CUTOVER-002',
    'Core cutover project two', 'active', 'project_engineer',
    '10000000-0000-4000-8000-000000000004', 'admin'
  ),
  (
    'cc000000-0000-4000-8000-000000000003', 'CUTOVER-003',
    'Unassigned capability project', 'active', 'project_engineer',
    '10000000-0000-4000-8000-000000000004', 'admin'
  );

insert into public.v1_project_scopes (
  id, project_id, scope_kind, scope_code, name, is_active, is_immutable
)
values
  (
    'cc100000-0000-4000-8000-000000000001',
    'cc000000-0000-4000-8000-000000000001',
    'common', 'common', 'Common / All Buildings', true, true
  ),
  (
    'cc100000-0000-4000-8000-000000000002',
    'cc000000-0000-4000-8000-000000000002',
    'common', 'common', 'Common / All Buildings', true, true
  ),
  (
    'cc100000-0000-4000-8000-000000000003',
    'cc000000-0000-4000-8000-000000000003',
    'common', 'common', 'Common / All Buildings', true, true
  );

insert into public.v1_project_members (
  project_id, member_auth_user_id, project_role, effective_from,
  reason, assigned_by_auth_user_id, assigned_by_role
)
values
  (
    'cc000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001', 'project_engineer',
    '2026-08-01 00:00:00+00', 'Core cutover fixture',
    '10000000-0000-4000-8000-000000000004', 'admin'
  ),
  (
    'cc000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000002', 'project_engineer',
    '2026-08-01 00:00:00+00', 'Core cutover fixture',
    '10000000-0000-4000-8000-000000000004', 'admin'
  ),
  (
    'cc000000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000002', 'site_engineer',
    '2026-08-01 00:00:00+00', 'Core cutover fixture',
    '10000000-0000-4000-8000-000000000004', 'admin'
  );

insert into public.v1_material_requests (
  id, project_id, scope_id, request_number, title, timing, state,
  record_version, created_by_auth_user_id, requester_display_name,
  requester_project_role, requester_exact_role,
  current_action_owner_role, current_action_code, submitted_at
)
values
  (
    'cc200000-0000-4000-8000-000000000001',
    'cc000000-0000-4000-8000-000000000001',
    'cc100000-0000-4000-8000-000000000001',
    null, 'Capability draft', 'normal', 'draft', 1,
    '10000000-0000-4000-8000-000000000002', null, null, null,
    'site_engineer', 'draft_owner', null
  ),
  (
    'cc200000-0000-4000-8000-000000000002',
    'cc000000-0000-4000-8000-000000000001',
    'cc100000-0000-4000-8000-000000000001',
    'CUTOVER-001-MR001', 'Awaiting capability decision', 'normal',
    'awaiting_request_approval', 1,
    '10000000-0000-4000-8000-000000000001', 'Local Project Engineer',
    'project_engineer', 'project_engineer', 'project_engineer',
    'request_approval_required', clock_timestamp()
  ),
  (
    'cc200000-0000-4000-8000-000000000003',
    'cc000000-0000-4000-8000-000000000001',
    'cc100000-0000-4000-8000-000000000001',
    'CUTOVER-001-MR002', 'Committed logistics request', 'normal',
    'dispatched', 1,
    '10000000-0000-4000-8000-000000000002', 'Local Site Engineer',
    'site_engineer', 'site_engineer', 'site_engineer',
    'receipt_review_required', clock_timestamp()
  ),
  (
    'cc200000-0000-4000-8000-000000000005',
    'cc000000-0000-4000-8000-000000000002',
    'cc100000-0000-4000-8000-000000000002',
    'CUTOVER-002-MR001', 'Site-role approval boundary', 'normal',
    'awaiting_request_approval', 1,
    '10000000-0000-4000-8000-000000000001', 'Local Project Engineer',
    'project_engineer', 'project_engineer', 'project_engineer',
    'request_approval_required', clock_timestamp()
  );

insert into public.v1_material_request_lines (
  id, request_id, display_order, source_kind, item_description,
  brand_origin, technical_attributes, requested_qty, unit
)
values (
  'cc210000-0000-4000-8000-000000000001',
  'cc200000-0000-4000-8000-000000000001', 1, 'custom',
  'Capability test item', 'UAE', '{}'::jsonb, 2, 'Nos'
);

insert into public.v1_material_dispatches (
  id, request_id, project_id, dispatch_number, dispatch_date,
  delivery_reference, state, dispatched_by_auth_user_id, dispatched_by_role
)
values (
  'cc220000-0000-4000-8000-000000000001',
  'cc200000-0000-4000-8000-000000000003',
  'cc000000-0000-4000-8000-000000000001',
  'CUTOVER-001-DSP001', current_date, 'CUTOVER-DN-001',
  'receipt_pending', '10000000-0000-4000-8000-000000000003', 'procurement'
);

insert into public.v1_material_returns (
  id, request_id, project_id, scope_id, state, note,
  drafted_by_auth_user_id, drafted_by_role
)
values (
  'cc230000-0000-4000-8000-000000000001',
  'cc200000-0000-4000-8000-000000000003',
  'cc000000-0000-4000-8000-000000000001',
  'cc100000-0000-4000-8000-000000000001',
  'draft', 'Capability return fixture',
  '10000000-0000-4000-8000-000000000002', 'site_engineer'
);

-- Site Engineer overrides exercise project specificity and the invariant that
-- an assignment cannot manufacture project membership.
insert into public.v1_permission_assignments (
  id, auth_user_id, capability_key, effect, scope_kind, reason,
  changed_by_auth_user_id
)
values
  (
    'cc300000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000002',
    'projects.edit', 'deny', 'organization',
    'Core cutover organization deny fixture',
    '10000000-0000-4000-8000-000000000004'
  ),
  (
    'cc300000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000002',
    'projects.edit', 'grant', 'project',
    'Core cutover project grant fixture',
    '10000000-0000-4000-8000-000000000004'
  ),
  (
    'cc300000-0000-4000-8000-000000000003',
    '10000000-0000-4000-8000-000000000002',
    'projects.view', 'deny', 'project',
    'Core cutover project deny fixture',
    '10000000-0000-4000-8000-000000000004'
  ),
  (
    'cc300000-0000-4000-8000-000000000004',
    '10000000-0000-4000-8000-000000000002',
    'projects.view', 'grant', 'project',
    'No-membership grant fixture',
    '10000000-0000-4000-8000-000000000004'
  ),
  (
    'cc300000-0000-4000-8000-000000000005',
    '10000000-0000-4000-8000-000000000002',
    'material_requests.create', 'deny', 'project',
    'Create must not control edit or submit',
    '10000000-0000-4000-8000-000000000004'
  ),
  (
    'cc300000-0000-4000-8000-000000000006',
    '10000000-0000-4000-8000-000000000002',
    'material_requests.approve', 'grant', 'project',
    'Site-as-Project-Engineer approval fixture',
    '10000000-0000-4000-8000-000000000004'
  ),
  (
    'cc300000-0000-4000-8000-000000000008',
    '10000000-0000-4000-8000-000000000003',
    'material_requests.approve', 'grant', 'project',
    'Procurement separation-of-duties fixture',
    '10000000-0000-4000-8000-000000000004'
  );

insert into public.v1_permission_assignment_projects (
  assignment_id, project_id
)
values
  (
    'cc300000-0000-4000-8000-000000000002',
    'cc000000-0000-4000-8000-000000000001'
  ),
  (
    'cc300000-0000-4000-8000-000000000003',
    'cc000000-0000-4000-8000-000000000002'
  ),
  (
    'cc300000-0000-4000-8000-000000000004',
    'cc000000-0000-4000-8000-000000000003'
  ),
  (
    'cc300000-0000-4000-8000-000000000005',
    'cc000000-0000-4000-8000-000000000001'
  ),
  (
    'cc300000-0000-4000-8000-000000000006',
    'cc000000-0000-4000-8000-000000000001'
  ),
  (
    'cc300000-0000-4000-8000-000000000006',
    'cc000000-0000-4000-8000-000000000002'
  ),
  (
    'cc300000-0000-4000-8000-000000000008',
    'cc000000-0000-4000-8000-000000000002'
  );

-- Senior Mechanical Engineer: every approved global Engineering workflow
-- action succeeds without a synthetic project-membership row.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000009","role":"authenticated","app_metadata":{"role":"senior_mechanical_engineer","app_user_id":"usr-local-senior-mechanical-engineer"}}',
  true
);
reset role;
select ok(public.v1_project_readable('cc000000-0000-4000-8000-000000000001'),
  'Senior Mechanical Engineer can read every project');
select ok(public.v1_can_edit_project('cc000000-0000-4000-8000-000000000001'),
  'Senior Mechanical Engineer can edit every project');
select ok(public.v1_can_edit_boq_project('cc000000-0000-4000-8000-000000000001'),
  'Senior Mechanical Engineer can edit every project BOQ');
select ok(public.v1_can_decide_material_request('cc200000-0000-4000-8000-000000000002'),
  'Senior Mechanical Engineer can decide an Engineering request');
select ok(public.v1_can_confirm_material_receipt('cc200000-0000-4000-8000-000000000003'),
  'Senior Mechanical Engineer can confirm a site receipt');
select ok(public.v1_can_generate_delivery_order('cc200000-0000-4000-8000-000000000003'),
  'Senior Mechanical Engineer can generate a committed Delivery Order');

-- Project Manager.
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000010","role":"authenticated","app_metadata":{"role":"project_manager","app_user_id":"usr-local-project-manager"}}',
  true
);
select ok(public.v1_project_readable('cc000000-0000-4000-8000-000000000001'),
  'Project Manager can read every project');
select ok(public.v1_can_edit_project('cc000000-0000-4000-8000-000000000001'),
  'Project Manager can edit every project');
select ok(public.v1_can_edit_boq_project('cc000000-0000-4000-8000-000000000001'),
  'Project Manager can edit every project BOQ');
select ok(public.v1_can_decide_material_request('cc200000-0000-4000-8000-000000000002'),
  'Project Manager can decide an Engineering request');
select ok(public.v1_can_confirm_material_receipt('cc200000-0000-4000-8000-000000000003'),
  'Project Manager can confirm a site receipt');
select ok(public.v1_can_generate_delivery_order('cc200000-0000-4000-8000-000000000003'),
  'Project Manager can generate a committed Delivery Order');

-- Workshop In-Charge.
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000011","role":"authenticated","app_metadata":{"role":"workshop_in_charge","app_user_id":"usr-capability-workshop-in-charge"}}',
  true
);
select ok(public.v1_project_readable('cc000000-0000-4000-8000-000000000001'),
  'Workshop In-Charge can read every project');
select ok(public.v1_can_edit_project('cc000000-0000-4000-8000-000000000001'),
  'Workshop In-Charge can edit every project');
select ok(public.v1_can_edit_boq_project('cc000000-0000-4000-8000-000000000001'),
  'Workshop In-Charge can edit every project BOQ');
select ok(public.v1_can_decide_material_request('cc200000-0000-4000-8000-000000000002'),
  'Workshop In-Charge can decide an Engineering request');
select ok(public.v1_can_confirm_material_receipt('cc200000-0000-4000-8000-000000000003'),
  'Workshop In-Charge can confirm a site receipt');
select ok(public.v1_can_generate_delivery_order('cc200000-0000-4000-8000-000000000003'),
  'Workshop In-Charge can generate a committed Delivery Order');

-- Document Controller.
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000012","role":"authenticated","app_metadata":{"role":"document_controller","app_user_id":"usr-capability-document-controller"}}',
  true
);
select ok(public.v1_project_readable('cc000000-0000-4000-8000-000000000001'),
  'Document Controller can read every project');
select ok(public.v1_can_edit_project('cc000000-0000-4000-8000-000000000001'),
  'Document Controller can edit every project');
select ok(public.v1_can_edit_boq_project('cc000000-0000-4000-8000-000000000001'),
  'Document Controller can edit every project BOQ');
select ok(public.v1_can_decide_material_request('cc200000-0000-4000-8000-000000000002'),
  'Document Controller can decide an Engineering request');
select ok(public.v1_can_confirm_material_receipt('cc200000-0000-4000-8000-000000000003'),
  'Document Controller can confirm a site receipt');
select ok(public.v1_can_generate_delivery_order('cc200000-0000-4000-8000-000000000003'),
  'Document Controller can generate a committed Delivery Order');

select ok(
  public.v1_material_return_readable('cc230000-0000-4000-8000-000000000001')
  and public.v1_can_create_project_material_return(
    'cc000000-0000-4000-8000-000000000001'
  )
  and public.v1_can_approve_project_material_return(
    'cc000000-0000-4000-8000-000000000001'
  )
  and public.v1_can_dispatch_project_material_return(
    'cc000000-0000-4000-8000-000000000001'
  ),
  'A global Engineering role retains the controlled Material Return workflow'
);

-- Site Engineer: project-scoped allow/deny, hard membership and SoD.
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);

select ok(
  public.v1_can_edit_project('cc000000-0000-4000-8000-000000000001')
  and not public.v1_can_edit_project('cc000000-0000-4000-8000-000000000002'),
  'A project grant overrides an organization deny only for that project'
);

select ok(
  public.v1_project_readable('cc000000-0000-4000-8000-000000000001')
  and not public.v1_project_readable('cc000000-0000-4000-8000-000000000002')
  and not public.v1_project_readable('cc000000-0000-4000-8000-000000000003'),
  'A project deny wins and a grant cannot manufacture missing membership'
);

set local role authenticated;
select is(
  (
    select count(*)
    from public.v1_projects project
    where project.id in (
      'cc000000-0000-4000-8000-000000000001',
      'cc000000-0000-4000-8000-000000000002',
      'cc000000-0000-4000-8000-000000000003'
    )
  ),
  1::bigint,
  'Project RLS applies the same scoped decision to direct table reads'
);
reset role;

select ok(
  not public.v1_can_decide_material_request(
    'cc200000-0000-4000-8000-000000000002'
  )
  and not public.v1_can_decide_material_request(
    'cc200000-0000-4000-8000-000000000005'
  )
  and public.v1_can_confirm_material_receipt(
    'cc200000-0000-4000-8000-000000000003'
  )
  and public.v1_can_generate_delivery_order(
    'cc200000-0000-4000-8000-000000000003'
  ),
  'An exact Site Engineer cannot approve, even with a Project Engineer membership label and approval grant'
);

select ok(
  public.v1_can_create_project_material_return(
    'cc000000-0000-4000-8000-000000000001'
  )
  and not public.v1_can_approve_project_material_return(
    'cc000000-0000-4000-8000-000000000001'
  )
  and public.v1_can_dispatch_project_material_return(
    'cc000000-0000-4000-8000-000000000001'
  ),
  'Site Engineer retains controlled Return creation/dispatch without approval'
);

set local role authenticated;
select throws_ok(
  $$select public.v1_decide_material_request(
    jsonb_build_object(
      'request_id', 'cc200000-0000-4000-8000-000000000005',
      'expected_version', 1, 'decision', 'approved', 'reason', null
    ),
    'cc400000-0000-4000-8000-000000000001'::uuid
  )$$,
  '42501', 'V1_MATERIAL_REQUEST_DECISION_DENIED',
  'A Site Engineer approval grant cannot bypass the exact-role boundary'
);

select throws_ok(
  $$select public.v1_decide_material_request(
    jsonb_build_object(
      'request_id', 'cc200000-0000-4000-8000-000000000002',
      'expected_version', 1, 'decision', 'approved', 'reason', null
    ),
    'cc400000-0000-4000-8000-000000000003'::uuid
  )$$,
  '42501', 'V1_MATERIAL_REQUEST_DECISION_DENIED',
  'A Project Engineer membership label cannot elevate an exact Site Engineer to approve'
);

select is(
  (
    select count(*)
    from public.v1_material_request_decisions decision_record
    where decision_record.request_id =
      'cc200000-0000-4000-8000-000000000002'
  ),
  0::bigint,
  'A denied exact Site Engineer approval creates no decision record'
);

select lives_ok(
  $$select public.v1_save_material_request_draft(jsonb_build_object(
    'request_id', 'cc200000-0000-4000-8000-000000000001',
    'expected_version', 1,
    'project_id', 'cc000000-0000-4000-8000-000000000001',
    'scope_id', 'cc100000-0000-4000-8000-000000000001',
    'title', 'Capability draft edited', 'timing', 'normal',
    'scheduled_date', null, 'delivery_note', null,
    'lines', jsonb_build_array(jsonb_build_object(
      'id', 'cc210000-0000-4000-8000-000000000001',
      'display_order', 1, 'source_kind', 'custom',
      'source_boq_group_id', null, 'source_boq_row_id', null,
      'item_description', 'Capability test item updated',
      'brand_origin', 'UAE', 'technical_attributes', '{}'::jsonb,
      'requested_qty', '3', 'unit', 'Nos'
    ))
  ))$$,
  'An existing own draft remains editable when create is explicitly denied'
);

select throws_ok(
  $$select public.v1_save_material_request_draft(jsonb_build_object(
    'request_id', 'cc200000-0000-4000-8000-000000000004',
    'expected_version', 0,
    'project_id', 'cc000000-0000-4000-8000-000000000001',
    'scope_id', 'cc100000-0000-4000-8000-000000000001',
    'title', 'Denied new draft', 'timing', 'normal',
    'scheduled_date', null, 'delivery_note', null, 'lines', '[]'::jsonb
  ))$$,
  '42501', 'V1_MATERIAL_REQUEST_DRAFT_DENIED',
  'The same project-scoped create deny blocks only new drafts'
);

select lives_ok(
  $$select public.v1_submit_material_request(
    jsonb_build_object(
      'request_id', 'cc200000-0000-4000-8000-000000000001',
      'expected_version', 2
    ),
    'cc400000-0000-4000-8000-000000000002'::uuid
  )$$,
  'Submit remains independent from the create capability after an existing edit'
);

select throws_ok(
  $$insert into public.v1_projects (
      project_ref, name, created_by_auth_user_id, created_by_role
    ) values (
      'CUTOVER-BYPASS', 'Direct bypass',
      '10000000-0000-4000-8000-000000000002', 'site_engineer'
    )$$,
  '42501', 'permission denied for table v1_projects',
  'An authorized app user cannot bypass trusted project RPCs with a direct write'
);

-- Procurement has logistics authority but no Engineering mutation authority.
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);
reset role;

select ok(
  public.v1_project_readable('cc000000-0000-4000-8000-000000000001')
  and not public.v1_can_edit_project('cc000000-0000-4000-8000-000000000001')
  and not public.v1_can_edit_boq_project('cc000000-0000-4000-8000-000000000001'),
  'Procurement keeps running-project read access without project or BOQ writes'
);

select ok(
  public.v1_can_arrange_material_request(
    'cc200000-0000-4000-8000-000000000003'
  )
  and public.v1_can_dispatch_material_request(
    'cc200000-0000-4000-8000-000000000003'
  )
  and public.v1_can_generate_delivery_order(
    'cc200000-0000-4000-8000-000000000003'
  ),
  'Procurement keeps arrangement, dispatch and Delivery Order authority'
);

select ok(
  not public.v1_can_decide_material_request(
    'cc200000-0000-4000-8000-000000000005'
  )
  and not public.v1_can_confirm_material_receipt(
    'cc200000-0000-4000-8000-000000000003'
  )
  and not public.v1_can_create_project_material_return(
    'cc000000-0000-4000-8000-000000000001'
  )
  and not public.v1_can_approve_project_material_return(
    'cc000000-0000-4000-8000-000000000001'
  )
  and not public.v1_can_dispatch_project_material_return(
    'cc000000-0000-4000-8000-000000000001'
  ),
  'Procurement cannot inherit Engineering approval, receipt or Return actions'
);

set local role authenticated;
select throws_ok(
  $$select public.v1_decide_material_request(
    jsonb_build_object(
      'request_id', 'cc200000-0000-4000-8000-000000000005',
      'expected_version', 1, 'decision', 'approved', 'reason', null
    ),
    'cc400000-0000-4000-8000-000000000004'::uuid
  )$$,
  '42501', 'V1_MATERIAL_REQUEST_DECISION_DENIED',
  'A direct Procurement approval grant cannot bypass Engineering separation of duties'
);
reset role;

-- The live Auth role and presented JWT role must still match after cutover.
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);

select ok(
  not public.v1_project_readable('cc000000-0000-4000-8000-000000000001')
  and not public.v1_current_user_has_capability(
    'material_requests.submit',
    'cc000000-0000-4000-8000-000000000001'
  ),
  'A stale or spoofed exact-role claim fails closed across RLS and commands'
);

reset role;
select * from finish();
rollback;
