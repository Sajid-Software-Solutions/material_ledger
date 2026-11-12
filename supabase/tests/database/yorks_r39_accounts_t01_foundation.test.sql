begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select no_plan();

select ok(
  public.v1_is_valid_role('accountant')
  and public.v1_canonical_role_from_exact_role('accountant') = 'accountant'
  and public.v1_safe_auth_audit_role(
    '{"role":"accountant"}'::jsonb
  ) = 'accountant',
  'Accountant is an exact server-owned role with distinct canonical audit identity'
);

select is(
  public.v1_permission_exact_role(
    '10000000-0000-4000-8000-000000000013'
  ),
  'accountant',
  'The deterministic Accountant persona resolves only through live Auth and profile state'
);

select is(
  (select count(*)
   from public.v1_capability_catalog catalog
   where public.v1_accounts_is_capability_key(catalog.capability_key)),
  15::bigint,
  'The R39 catalog contains exactly the fifteen approved capability keys'
);

select ok(
  (select count(*) from public.v1_capability_catalog catalog
   where public.v1_accounts_is_capability_key(catalog.capability_key)
     and catalog.status = 'operational'
     and catalog.authorization_mode = 'enforced'
     and catalog.is_assignable) = 15
  and (select count(*) from public.v1_capability_catalog catalog
   where public.v1_accounts_is_capability_key(catalog.capability_key)
     and catalog.status = 'planned'
     and catalog.authorization_mode = 'shadow'
     and not catalog.is_assignable) = 0
  and not exists (
    select 1 from public.v1_capability_catalog catalog
    where public.v1_accounts_is_capability_key(catalog.capability_key)
      and (catalog.module_key <> 'accounts'
        or not catalog.requires_project_access
        or catalog.allowed_scope_kinds <> array['project']::text[])
  ),
  'T01 retains all fifteen keys while T02-T06 activate every tested consumer'
);

select is(
  (select count(*) from public.v1_permission_role_defaults),
  (select count(*) * 10 from public.v1_capability_catalog),
  'The explicit role matrix covers all ten exact roles and every capability'
);

select ok(
  not exists (
    select 1
    from public.v1_permission_role_defaults role_default
    join public.v1_capability_catalog catalog using (capability_key)
    where role_default.role_name = 'accountant'
      and role_default.is_granted
      and not public.v1_accounts_is_capability_key(catalog.capability_key)
      -- PRODUCT_DECISIONS.md section 33: the only exception is the two
      -- organization-wide worker record keys.
      and catalog.capability_key not in (
        'worker_records.view', 'worker_records.manage'
      )
  ),
  'Accountant has no technical or non-Accounts role-template grant'
);

select ok(
  (select is_granted from public.v1_permission_role_defaults
   where role_name = 'accountant'
     and capability_key = 'manage_client_invoices')
  and (select is_granted from public.v1_permission_role_defaults
   where role_name = 'accountant'
     and capability_key = 'manage_supplier_bills')
  and not (select is_granted from public.v1_permission_role_defaults
   where role_name = 'accountant'
     and capability_key = 'confirm_billing_progress')
  and (select is_granted from public.v1_permission_role_defaults
   where role_name = 'accountant'
     and capability_key = 'configure_project_commercials'),
  'Accountant separates Accounts recording from Engineering confirmation, and may edit the contract (owner decision, 7 Nov 2026)'
);

select ok(
  (select is_granted from public.v1_permission_role_defaults
   where role_name = 'procurement'
     and capability_key = 'manage_supplier_bills')
  and (select is_granted from public.v1_permission_role_defaults
   where role_name = 'procurement'
     and capability_key = 'view_supplier_costs')
  and not (select is_granted from public.v1_permission_role_defaults
   where role_name = 'procurement'
     and capability_key = 'manage_client_invoices'),
  'Procurement future Accounts ceiling is supplier-only'
);

select ok(
  not (select is_granted from public.v1_permission_role_defaults
   where role_name = 'project_manager'
     and capability_key = 'review_commercial_progress')
  and not (select is_granted from public.v1_permission_role_defaults
   where role_name = 'senior_mechanical_engineer'
     and capability_key = 'review_commercial_progress'),
  'Management commercial review remains explicit rather than inherited'
);

select is(
  (select row(
     default_payment_terms_days,
     default_reminder_lead_days,
     common_scope_is_physical
   )::text
   from public.v1_accounts_foundation_settings where singleton),
  '(90,10,f)',
  'Binding Accounts defaults are 90-day terms, 10-day lead and Common excluded'
);

select is(
  (select string_agg(
     stage_key || ':' || allocation_percent::text,
     ',' order by display_order
   ) from public.v1_accounts_billing_stage_templates where is_active),
  'design:10.0000,material_supply:50.0000,installation:30.0000,commissioning_handover:5.0000,energizing:5.0000',
  'The protected stage template is exactly 10/50/30/5/5 in approved order'
);

select is(
  (select sum(allocation_percent)
   from public.v1_accounts_billing_stage_templates where is_active),
  100.0000::numeric,
  'Active default billing stages allocate exactly 100 percent'
);

select ok(
  (select count(*)
   from public.v1_configuration_settings setting
   where setting.setting_key = any(array[
     'accounts.billing_stage_weights',
     'accounts.payment_terms_days',
     'accounts.pdc_reminder_days'
   ]::text[])
     and setting.control_mode = 'planned'
     and setting.enforcement_target = 'retained_reference'
     and setting.default_value = setting.published_value
     and setting.published_value = case setting.setting_key
       when 'accounts.billing_stage_weights' then
         '{"design":10,"material_supply":50,"installation":30,"commissioning_handover":5,"energizing":5}'::jsonb
       when 'accounts.payment_terms_days' then '90'::jsonb
       when 'accounts.pdc_reminder_days' then '10'::jsonb
     end
  ) = 3,
  'Legacy R38 Accounts configuration stays planned, non-authoritative and aligned to T01 defaults'
);

select ok(
  (select relrowsecurity from pg_catalog.pg_class
   where oid = 'public.v1_accounts_foundation_settings'::regclass)
  and (select relrowsecurity from pg_catalog.pg_class
   where oid = 'public.v1_accounts_billing_stage_templates'::regclass)
  and not has_table_privilege(
    'authenticated', 'public.v1_accounts_foundation_settings', 'select'
  )
  and not has_table_privilege(
    'authenticated', 'public.v1_accounts_foundation_settings', 'insert'
  )
  and not has_table_privilege(
    'authenticated', 'public.v1_accounts_billing_stage_templates', 'update'
  ),
  'Foundation defaults are RLS-protected with no authenticated direct-table access'
);

select ok(
  has_function_privilege(
    'authenticated', 'public.v1_get_accounts_foundation(uuid)', 'execute'
  )
  and not has_function_privilege(
    'anon', 'public.v1_get_accounts_foundation(uuid)', 'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.v1_accounts_has_project_scope(uuid,uuid,text)', 'execute'
  ),
  'Only the safe foundation projection is exposed to authenticated callers'
);

insert into public.v1_projects (
  id, project_ref, name, state, current_action_owner_role,
  created_by_auth_user_id, created_by_role
) values (
  '39010000-0000-4000-8000-000000000001', 'R39-T01-001',
  'R39 Accounts foundation test', 'active', 'project_engineer',
  '10000000-0000-4000-8000-000000000004', 'admin'
);

insert into public.v1_project_scopes (
  id, project_id, scope_kind, scope_code, name, is_immutable
) values (
  '39020000-0000-4000-8000-000000000001',
  '39010000-0000-4000-8000-000000000001',
  'common', 'common', 'Common / All Buildings', true
);

insert into public.v1_project_members (
  project_id, member_auth_user_id, project_role, effective_from,
  reason, assigned_by_auth_user_id, assigned_by_role
) values
  (
    '39010000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001', 'project_engineer',
    clock_timestamp() - interval '1 day', 'R39 scope test',
    '10000000-0000-4000-8000-000000000004', 'admin'
  ),
  (
    '39010000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000002', 'site_engineer',
    clock_timestamp() - interval '1 day', 'R39 scope test',
    '10000000-0000-4000-8000-000000000004', 'admin'
  );

insert into public.v1_material_requests (
  id, project_id, scope_id, request_number, title, timing, state,
  record_version, created_by_auth_user_id, requester_display_name,
  requester_project_role, requester_exact_role,
  current_action_owner_role, current_action_code, submitted_at
) values (
  '39030000-0000-4000-8000-000000000010',
  '39010000-0000-4000-8000-000000000001',
  '39020000-0000-4000-8000-000000000001',
  'R39-T01-001-MR001', 'Accountant logistics denial fixture', 'normal',
  'approved', 1, '10000000-0000-4000-8000-000000000001',
  'Local Project Engineer', 'project_engineer', 'project_engineer',
  'procurement', 'dispatch_required', clock_timestamp()
);

select ok(
  not public.v1_permission_has_project_access(
    '10000000-0000-4000-8000-000000000013',
    '39010000-0000-4000-8000-000000000001'
  )
  and public.v1_accounts_has_project_scope(
    '10000000-0000-4000-8000-000000000013',
    '39010000-0000-4000-8000-000000000001',
    'view_project_accounts'
  ),
  'Accountant receives Accounts scope without technical project access'
);

select ok(
  public.v1_accounts_has_project_scope(
    '10000000-0000-4000-8000-000000000003',
    '39010000-0000-4000-8000-000000000001',
    'manage_supplier_bills'
  )
  and not public.v1_accounts_has_project_scope(
    '10000000-0000-4000-8000-000000000003',
    '39010000-0000-4000-8000-000000000001',
    'manage_client_invoices'
  ),
  'Procurement has structural scope only for supplier-side Accounts keys'
);

select ok(
  public.v1_accounts_has_project_scope(
    '10000000-0000-4000-8000-000000000010',
    '39010000-0000-4000-8000-000000000001',
    'review_commercial_progress'
  )
  and not (select is_granted from public.v1_permission_role_defaults
    where role_name = 'project_manager'
      and capability_key = 'review_commercial_progress'),
  'Project Manager review has a structural seam but requires an explicit future grant'
);

select ok(
  public.v1_accounts_has_project_scope(
    '10000000-0000-4000-8000-000000000001',
    '39010000-0000-4000-8000-000000000001',
    'confirm_billing_progress'
  )
  -- Owner decision of 11 November 2026: a PE member holds every Accounts key.
  and public.v1_accounts_has_project_scope(
    '10000000-0000-4000-8000-000000000001',
    '39010000-0000-4000-8000-000000000001',
    'manage_client_invoices'
  )
  and not public.v1_accounts_has_project_scope(
    '10000000-0000-4000-8000-000000000002',
    '39010000-0000-4000-8000-000000000001',
    'manage_client_invoices'
  )
  and public.v1_accounts_has_project_scope(
    '10000000-0000-4000-8000-000000000002',
    '39010000-0000-4000-8000-000000000001',
    'suggest_billing_progress'
  )
  and not public.v1_accounts_has_project_scope(
    '10000000-0000-4000-8000-000000000002',
    '39010000-0000-4000-8000-000000000001',
    'confirm_billing_progress'
  ),
  'Dated PE and Site membership resolves only their approved Accounts scope'
);

select is(
  public.v1_permission_candidate_raw(
    '10000000-0000-4000-8000-000000000013',
    'view_project_accounts',
    '39010000-0000-4000-8000-000000000001'
  ) ->> 'source',
  'role_default',
  'The tested T02 Accountant view consumer resolves from its protected role template'
);

select is(
  public.v1_permission_candidate_raw(
    '10000000-0000-4000-8000-000000000013',
    'boq.edit',
    '39010000-0000-4000-8000-000000000001'
  ) ->> 'source',
  'hard_invariant',
  'Accountant is hard-denied from non-Accounts project capability resolution'
);

select throws_ok(
  $$insert into public.v1_project_members (
      project_id, member_auth_user_id, project_role, effective_from,
      reason, assigned_by_auth_user_id, assigned_by_role
    ) values (
      '39010000-0000-4000-8000-000000000001',
      '10000000-0000-4000-8000-000000000013', 'project_engineer',
      clock_timestamp(), 'Malformed technical membership test',
      '10000000-0000-4000-8000-000000000004', 'admin'
    )$$,
  '42501', 'V1_ACCOUNTANT_TECHNICAL_MEMBERSHIP_FORBIDDEN',
  'Database guards reject active Accountant technical membership'
);

update public.v1_capability_catalog
set status = 'operational'
where capability_key = 'accounts.view';

select is(
  public.v1_permission_candidate_raw(
    '10000000-0000-4000-8000-000000000013',
    'accounts.view',
    '39010000-0000-4000-8000-000000000001'
  ) ->> 'source',
  'hard_invariant',
  'Legacy dotted accounts.view stays non-authoritative even if forced operational'
);

select throws_ok(
  $$insert into public.v1_permission_assignments (
      auth_user_id, capability_key, effect, scope_kind, reason
    ) values (
      '10000000-0000-4000-8000-000000000013',
      'accounts.view', 'grant', 'organization',
      'Malformed legacy Accounts grant proof'
    )$$,
  '42501', 'V1_ACCOUNTANT_NON_ACCOUNTS_CAPABILITY_DENIED',
  'Assignment storage rejects noncanonical Accounts grants for Accountant'
);

update public.v1_capability_catalog
set status = 'planned'
where capability_key = 'accounts.view';

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true
);

select ok(
  public.v1_current_user_can_assign_new_exact_role('accountant')
  and (public.v1_get_user_admin_options(null)
    -> 'assignable_exact_roles') ? 'accountant',
  'Admin can provision and assign the exact Accountant role through protected server projections'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000009","role":"authenticated","app_metadata":{"role":"senior_mechanical_engineer","app_user_id":"usr-local-senior-mechanical-engineer"}}',
  true
);

select ok(
  public.v1_current_user_can_assign_new_exact_role('accountant')
  and (public.v1_get_user_admin_options(null)
    -> 'assignable_exact_roles') ? 'accountant',
  'Senior Mechanical Engineer retains its established audited authority to assign Accountant'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);

select ok(
  not public.v1_current_user_can_assign_new_exact_role('accountant'),
  'An unauthorized exact role cannot provision Accountant'
);

select throws_ok(
  $$select public.v1_get_user_admin_options(null)$$,
  '42501', 'V1_USER_ADMIN_OPTIONS_ACCESS_DENIED',
  'An unauthorized actor cannot enumerate Accountant through User Management options'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000013","role":"authenticated","app_metadata":{"role":"accountant","app_user_id":"usr-local-accountant"}}',
  true
);

select ok(
  public.v1_current_user_has_capability(
    'view_project_accounts',
    '39010000-0000-4000-8000-000000000001'
  )
  and not public.v1_current_user_has_capability(
    'boq.edit', '39010000-0000-4000-8000-000000000001'
  )
  and not public.v1_current_user_has_capability(
    'material_requests.create', '39010000-0000-4000-8000-000000000001'
  )
  and not public.v1_current_user_has_capability(
    'dispatch.create', '39010000-0000-4000-8000-000000000001'
  ),
  'T02 enables Accountant role-safe Accounts reads without BOQ, MR or dispatch authority'
);

select is(
  (public.v1_get_accounts_foundation(
    '39010000-0000-4000-8000-000000000001'
  ) ->> 'consumers_enabled')::boolean,
  true,
  'The role-safe Accounts foundation reports its tested T02 consumers enabled'
);

select is(
  (select count(*)
   from jsonb_each(public.v1_get_accounts_foundation(
     '39010000-0000-4000-8000-000000000001'
   ) -> 'capabilities')),
  15::bigint,
  'The foundation projection exposes exactly the approved future command flags'
);

select ok(
  (select count(*)
    from jsonb_each(public.v1_get_accounts_foundation(
      '39010000-0000-4000-8000-000000000001'
    ) -> 'capabilities') capability
    where coalesce((capability.value ->> 'command_enabled')::boolean, true)
  ) = 11,
  'Only the eleven accepted Accountant consumers are enabled for its role, now including contract editing'
);

select throws_ok(
  $$insert into public.v1_accounts_foundation_settings (singleton)
    values (false)$$,
  '42501', 'permission denied for table v1_accounts_foundation_settings',
  'Authenticated callers cannot bypass the foundation projection with a direct write'
);

select throws_ok(
  $$select public.v1_create_project(
    '{"project_ref":"R39-DENIED","name":"Denied","parties":{},"initial_members":[],"buildings":[],"attachments":[]}'::jsonb,
    '39090000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'V1_ROLE_NOT_ALLOWED_TO_CREATE_PROJECT',
  'Accountant cannot create a technical project'
);

select throws_ok(
  $$select public.v1_create_boq_group(
    jsonb_build_object(
      'project_id', '39010000-0000-4000-8000-000000000001',
      'scope_id', '39020000-0000-4000-8000-000000000001',
      'name', 'Accountant denied BOQ'
    ),
    '39090000-0000-4000-8000-000000000002'
  )$$,
  '42501', 'V1_BOQ_EDIT_DENIED',
  'Accountant cannot mutate a BOQ'
);

select throws_ok(
  $$select public.v1_save_material_request_draft(jsonb_build_object(
    'request_id', '39030000-0000-4000-8000-000000000001',
    'expected_version', 0,
    'project_id', '39010000-0000-4000-8000-000000000001',
    'scope_id', '39020000-0000-4000-8000-000000000001',
    'title', 'Accountant denied MR',
    'timing', 'normal',
    'scheduled_date', null,
    'delivery_note', null,
    'lines', '[]'::jsonb
  ))$$,
  '42501', 'V1_MATERIAL_REQUEST_DRAFT_DENIED',
  'Accountant cannot mutate a Material Request draft'
);

select throws_ok(
  $$select public.v1_dispatch_materials(
    jsonb_build_object(
      'request_id', '39030000-0000-4000-8000-000000000010',
      'expected_version', 1,
      'dispatch_date', current_date::text,
      'delivery_reference', 'R39-ACCOUNTANT-DENIED',
      'driver_name', 'Denied Accountant',
      'vehicle_reference', 'DENIED',
      'lines', jsonb_build_array(jsonb_build_object(
        'request_line_id', '39031000-0000-4000-8000-000000000001',
        'dispatch_qty', '1'
      ))
    ), '39090000-0000-4000-8000-000000000004'::uuid
  )$$,
  '42501', 'V1_DISPATCH_DENIED',
  'The real transactional dispatch command denies Accountant before idempotency or stock mutation'
);

reset role;

select lives_ok(
  $$select public.v1_write_audit_event(
    'accounts_foundation_test', 'project',
    '39010000-0000-4000-8000-000000000001',
    '39010000-0000-4000-8000-000000000001',
    null, '{"foundation":true}'::jsonb,
    'R39 Accountant audit attribution proof',
    '39090000-0000-4000-8000-000000000003'
  )$$,
  'Accountant actions can retain canonical and exact server audit attribution'
);

select ok(
  exists (
    select 1
    from public.v1_audit_events audit
    where audit.event_type = 'accounts_foundation_test'
      and audit.actor_role = 'accountant'
      and audit.actor_exact_role = 'accountant'
  ),
  'The append-only audit row preserves Accountant attribution'
);

select lives_ok(
  $$insert into public.v1_documents (
    id, classification, created_by_auth_user_id, created_by_role
  ) values (
    '39040000-0000-4000-8000-000000000001', 'commercial',
    '10000000-0000-4000-8000-000000000013', 'accountant'
  )$$,
  'Controlled-document history can retain Accountant attribution'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000013","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-accountant"}}',
  true
);

select throws_ok(
  $$select public.v1_get_accounts_foundation(
    '39010000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'R39_ACCOUNTS_FOUNDATION_ACCESS_DENIED',
  'A stale JWT role fails closed for the Accounts foundation'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000013","role":"authenticated","app_metadata":{"role":"accounts_manager","app_user_id":"usr-local-accountant"}}',
  true
);

select throws_ok(
  $$select public.v1_get_accounts_foundation(
    '39010000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'R39_ACCOUNTS_FOUNDATION_ACCESS_DENIED',
  'AT-SEC-007: an unknown exact-role session fails closed at the Accounts boundary'
);

reset role;
update public.v1_profiles
set is_active = false
where auth_user_id = '10000000-0000-4000-8000-000000000013';

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000013","role":"authenticated","app_metadata":{"role":"accountant","app_user_id":"usr-local-accountant"}}',
  true
);

select throws_ok(
  $$select public.v1_get_accounts_foundation(
    '39010000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'R39_ACCOUNTS_FOUNDATION_ACCESS_DENIED',
  'An inactive Accountant cannot read the Accounts foundation'
);

reset role;
update public.v1_profiles
set is_active = true
where auth_user_id = '10000000-0000-4000-8000-000000000013';

select * from finish();
rollback;
