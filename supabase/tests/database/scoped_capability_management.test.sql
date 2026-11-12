begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select no_plan();

select ok(
  (select count(*) > 80 from public.v1_capability_catalog)
  and not exists (
    select 1 from public.v1_capability_catalog
    where authorization_mode not in ('shadow', 'enforced')
      or status not in ('operational', 'planned')
      or risk_level not in ('low', 'medium', 'high', 'critical')
  ),
  'The complete catalog remains typed across capability-by-capability cutover'
);

select is(
  (select count(*)
   from public.v1_permission_role_defaults),
  (select count(*) * 10 from public.v1_capability_catalog),
  'Every exact Yorks role has an explicit default for every catalog capability'
);

select ok(
  (select is_granted from public.v1_permission_role_defaults
   where role_name = 'project_engineer'
     and capability_key = 'material_requests.approve')
  and not (select is_granted from public.v1_permission_role_defaults
   where role_name = 'project_engineer'
     and capability_key = 'procurement.arrange'),
  'Project Engineer parity preserves approval without Procurement arrangement'
);

select ok(
  not (select is_granted from public.v1_permission_role_defaults
   where role_name = 'site_engineer'
     and capability_key = 'material_requests.approve')
  and not (select is_granted from public.v1_permission_role_defaults
   where role_name = 'site_engineer'
     and capability_key = 'material_requests.cancel')
  and (select is_granted from public.v1_permission_role_defaults
   where role_name = 'site_engineer'
     and capability_key = 'receipts.confirm'),
  'Site Engineer parity preserves receipt duty without approval or cancellation'
);

select ok(
  (select is_granted from public.v1_permission_role_defaults
   where role_name = 'senior_mechanical_engineer'
     and capability_key = 'users.roles.assign')
  and (select is_granted from public.v1_permission_role_defaults
   where role_name = 'senior_mechanical_engineer'
     and capability_key = 'inventory.view')
  and not (select is_granted from public.v1_permission_role_defaults
   where role_name = 'senior_mechanical_engineer'
     and capability_key = 'inventory.stock.adjust'),
  'Senior Mechanical Engineer preserves user administration and read-only inventory'
);

select ok(
  (select is_granted from public.v1_permission_role_defaults
   where role_name = 'project_manager'
     and capability_key = 'projects.view_all')
  and not (select is_granted from public.v1_permission_role_defaults
   where role_name = 'project_manager'
     and capability_key = 'users.view')
  and not (select is_granted from public.v1_permission_role_defaults
   where role_name = 'document_controller'
     and capability_key = 'users.view'),
  'Global Engineering roles preserve all-project Engineering access without User Management'
);

select ok(
  (select is_granted from public.v1_permission_role_defaults
   where role_name = 'procurement'
     and capability_key = 'procurement.arrange')
  and (select is_granted from public.v1_permission_role_defaults
   where role_name = 'procurement'
     and capability_key = 'inventory.stock.adjust')
  and not (select is_granted from public.v1_permission_role_defaults
   where role_name = 'procurement'
     and capability_key = 'material_requests.approve'),
  'Procurement parity preserves arrangement and stock authority without Engineering approval'
);

select ok(
  (select is_granted from public.v1_permission_role_defaults
   where role_name = 'admin'
     and capability_key = 'configuration.stage')
  and (select is_granted from public.v1_permission_role_defaults
   where role_name = 'admin'
     and capability_key = 'configuration.publish')
  and not (select is_granted from public.v1_permission_role_defaults
   where role_name = 'admin' and capability_key = 'leave.view_own')
  and not (select is_granted from public.v1_permission_role_defaults
   where role_name = 'admin' and capability_key = 'leave.request'),
  'Admin parity preserves configuration control without inventing Leave self-service'
);

select ok(
  not (select is_assignable from public.v1_capability_catalog
       where capability_key = 'projects.view_all')
  and (select status = 'planned' and not is_assignable
       from public.v1_capability_catalog
       where capability_key = 'users.delete')
  and not exists (
    select 1 from public.v1_permission_role_defaults role_default
    join public.v1_capability_catalog catalog using (capability_key)
    where catalog.status = 'planned'
      and role_default.is_granted
      and not (
        public.v1_accounts_is_capability_key(catalog.capability_key)
        or public.v1_workforce_is_capability_key(catalog.capability_key)
      )
  ),
  'Only approved Accounts and Workforce future templates may be pre-seeded while planned'
);

select ok(
  not exists (
    select 1
    from public.v1_capability_catalog catalog
    where catalog.capability_key = any (array[
      'boq.view', 'material_requests.view', 'dispatch.view',
      'receipts.view', 'returns.view', 'documents.view'
    ])
      and not ('projects.view' = any(catalog.dependencies))
  ),
  'Project-context projections depend explicitly on projects.view'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.v1_get_current_permission_snapshot()', 'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.v1_current_user_has_capability(text,uuid)', 'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.v1_current_user_can_assign_exact_role(text,text)', 'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.v1_current_user_can_assign_new_exact_role(text)', 'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.v1_get_current_permission_snapshot()', 'execute'
  ),
  'Only authenticated callers receive protected snapshot and decision endpoints'
);

select ok(
  not has_table_privilege(
    'authenticated', 'public.v1_permission_assignments', 'insert'
  )
  and not has_table_privilege(
    'authenticated', 'public.v1_permission_change_events', 'update'
  ),
  'Direct assignment writes and permission-history mutation are not granted'
);

select ok(
  exists (
    select 1 from pg_catalog.pg_publication_tables publication_table
    where publication_table.pubname = 'supabase_realtime'
      and publication_table.schemaname = 'public'
      and publication_table.tablename = 'v1_permission_revisions'
  ),
  'Only the safe permission revision signal is published for Realtime refresh'
);

select ok(
  position(
    'v1_permission_manager_continuity' in pg_get_functiondef(
      'public.v1_apply_user_permission_changes(text,jsonb,text,bigint,uuid)'::regprocedure
    )
  ) > 0
  and position(
    'for update' in lower(pg_get_functiondef(
      'public.v1_apply_user_permission_changes(text,jsonb,text,bigint,uuid)'::regprocedure
    ))
  ) > 0,
  'Competing permission batches serialize before locking and revising one target workspace'
);

insert into public.v1_projects (
  id, project_ref, name, state, current_action_owner_role,
  created_by_auth_user_id, created_by_role
) values
  (
    'ca000000-0000-4000-8000-000000000001', 'CAP-PROJECT-001',
    'Capability project one', 'active', 'project_engineer',
    '10000000-0000-4000-8000-000000000004', 'admin'
  ),
  (
    'ca000000-0000-4000-8000-000000000002', 'CAP-PROJECT-002',
    'Capability project two', 'active', 'project_engineer',
    '10000000-0000-4000-8000-000000000004', 'admin'
  ),
  (
    'ca000000-0000-4000-8000-000000000004', 'CAP-RESTRICTED-004',
    'Restricted capability project', 'active', 'project_engineer',
    '10000000-0000-4000-8000-000000000004', 'admin'
  ),
  (
    'ca000000-0000-4000-8000-000000000005', 'CAP-COMPLETED-005',
    'Completed capability project', 'completed', 'none',
    '10000000-0000-4000-8000-000000000004', 'admin'
  );

insert into public.v1_project_members (
  project_id, member_auth_user_id, project_role, effective_from,
  reason, assigned_by_auth_user_id, assigned_by_role
) values
  (
    'ca000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000002', 'site_engineer',
    '2026-08-01 00:00:00+00', 'Capability test membership',
    '10000000-0000-4000-8000-000000000004', 'admin'
  ),
  (
    'ca000000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000002', 'site_engineer',
    '2026-08-01 00:00:00+00', 'Capability test membership',
    '10000000-0000-4000-8000-000000000004', 'admin'
  );

create temporary table v1_permission_test_revision (
  label text primary key,
  revision bigint not null
) on commit drop;
grant select on v1_permission_test_revision to authenticated;

insert into v1_permission_test_revision (label, revision)
select 'site_after_membership_insert', revision.revision
from public.v1_permission_revisions revision
where revision.app_user_id = 'usr-local-site-engineer';

select is(
  (select revision from v1_permission_test_revision
   where label = 'site_after_membership_insert'),
  1::bigint,
  'A bulk membership insert emits one revision signal per affected user'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);

select lives_ok(
  $$select public.v1_get_current_permission_snapshot()$$,
  'An active exact-role user can load a self-only effective snapshot'
);

select ok(
  public.v1_get_current_permission_snapshot() ->> 'authorization_mode'
    in ('shadow', 'mixed', 'enforced')
  and jsonb_typeof(
    public.v1_get_current_permission_snapshot() -> 'schema_version'
  ) = 'number'
  and public.v1_current_user_has_capability('receipts.confirm', null)
  and not public.v1_current_user_has_capability('inventory.view', null),
  'The shadow snapshot exposes legacy-authoritative Site Engineer parity'
);

select is(
  public.v1_current_user_has_capability('future.unknown', null),
  false,
  'Unknown capability checks fail closed'
);

select throws_ok(
  $$insert into public.v1_permission_assignments (
      auth_user_id, capability_key, effect, scope_kind, reason
    ) values (
      '10000000-0000-4000-8000-000000000002',
      'inventory.view', 'grant', 'organization', 'Direct write'
    )$$,
  '42501', 'permission denied for table v1_permission_assignments',
  'An authenticated user cannot bypass RPC validation with a direct write'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true
);

with snapshot as materialized (
  select public.v1_get_current_permission_snapshot() as value
)
select ok(
  jsonb_array_length(snapshot.value -> 'capabilities') > 80
  and not exists (
    select 1
    from jsonb_array_elements(snapshot.value -> 'capabilities') capability
    where capability ->> 'capability_key' = any(array[
      'users.view', 'permissions.view',
      'permissions.manage', 'permissions.delegate'
    ]::text[])
      and (
        coalesce((capability ->> 'role_default')::boolean, false) is not true
        or coalesce((
          capability ->> 'authoritative_effective'
        )::boolean, false) is not true
        or capability ->> 'authoritative_source' <> 'role_default'
      )
  )
  and (
    select count(*)
    from jsonb_array_elements(snapshot.value -> 'capabilities') capability
    where capability ->> 'capability_key' = any(array[
      'users.view', 'permissions.view',
      'permissions.manage', 'permissions.delegate'
    ]::text[])
  ) = 4,
  'Admin keeps the complete inherited User Management permission chain'
)
from snapshot;

with started as materialized (
  select clock_timestamp() as started_at
), snapshot as materialized (
  select started.started_at,
    public.v1_get_current_permission_snapshot() as value
  from started
)
select ok(
  extract(epoch from (clock_timestamp() - snapshot.started_at)) < 3,
  'The current permission snapshot stays below the protected projection budget'
)
from snapshot;

reset role;
select is(
  (public.v1_get_user_permission_workspace('usr-local-site-engineer')
    ->> 'revision')::bigint,
  (select revision from v1_permission_test_revision
   where label = 'site_after_membership_insert'),
  'The target workspace resolves a stable application user ID and revision'
);

select ok(
  public.v1_get_user_permission_workspace('usr-local-site-engineer')
    -> 'actor' ->> 'app_user_id' = 'usr-local-admin'
  and public.v1_get_user_permission_workspace('usr-local-site-engineer')
    -> 'target' ->> 'app_user_id' = 'usr-local-site-engineer'
  and not (
    public.v1_get_user_permission_workspace('usr-local-site-engineer')::text
      like '%10000000-0000-4000-8000-000000000002%'
  ),
  'Admin workspace separates actor and stable target without exposing target Auth UUID'
);

select lives_ok(
  $$select public.v1_apply_user_permission_changes(
    'usr-local-site-engineer',
    '[
      {"operation":"set","capability_key":"inventory.view","effect":"grant","scope_kind":"organization","project_ids":[],"effective_from":null,"effective_until":null},
      {"operation":"set","capability_key":"projects.edit","effect":"deny","scope_kind":"organization","project_ids":[],"effective_from":null,"effective_until":null},
      {"operation":"set","capability_key":"projects.edit","effect":"grant","scope_kind":"project","project_ids":["ca000000-0000-4000-8000-000000000001"],"effective_from":null,"effective_until":null},
      {"operation":"set","capability_key":"boq.view","effect":"grant","scope_kind":"organization","project_ids":[],"effective_from":null,"effective_until":null},
      {"operation":"set","capability_key":"boq.view","effect":"deny","scope_kind":"project","project_ids":["ca000000-0000-4000-8000-000000000002"],"effective_from":null,"effective_until":null}
    ]'::jsonb,
    'Scoped precedence and shadow proof',
    (select revision from v1_permission_test_revision
     where label = 'site_after_membership_insert'),
    'ca100000-0000-4000-8000-000000000001'
  )$$,
  'Admin can atomically apply a typed multi-change review'
);

select is(
  (public.v1_get_user_permission_workspace('usr-local-site-engineer')
    ->> 'revision')::bigint,
  (select revision + 1 from v1_permission_test_revision
   where label = 'site_after_membership_insert'),
  'One atomic batch increments the target revision exactly once'
);

reset role;
select ok(
  coalesce((public.v1_permission_candidate_resolution(
    '10000000-0000-4000-8000-000000000002',
    'projects.edit', 'ca000000-0000-4000-8000-000000000001'
  ) ->> 'effective')::boolean, false)
  and not coalesce((public.v1_permission_candidate_resolution(
    '10000000-0000-4000-8000-000000000002',
    'projects.edit', 'ca000000-0000-4000-8000-000000000002'
  ) ->> 'effective')::boolean, false),
  'A project grant overrides an organization deny only at the more-specific project'
);

select ok(
  not coalesce((public.v1_permission_candidate_resolution(
    '10000000-0000-4000-8000-000000000002',
    'boq.view', 'ca000000-0000-4000-8000-000000000002'
  ) ->> 'effective')::boolean, false)
  and coalesce((public.v1_permission_candidate_resolution(
    '10000000-0000-4000-8000-000000000002',
    'boq.view', 'ca000000-0000-4000-8000-000000000001'
  ) ->> 'effective')::boolean, false),
  'A project deny overrides an organization grant only at the more-specific project'
);

select ok(
  not coalesce((public.v1_permission_authoritative_resolution(
    '10000000-0000-4000-8000-000000000002',
    'inventory.view', null
  ) ->> 'effective')::boolean, false)
  and coalesce((public.v1_permission_candidate_resolution(
    '10000000-0000-4000-8000-000000000002',
    'inventory.view', null
  ) ->> 'effective')::boolean, false),
  'A shadow assignment is visible as candidate drift but cannot change authoritative access'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true
);

reset role;
select is(
  (select count(*) from public.v1_permission_change_events
   where target_auth_user_id =
     '10000000-0000-4000-8000-000000000002'
     and idempotency_key =
       'ca100000-0000-4000-8000-000000000001'),
  5::bigint,
  'A batch writes one immutable delta event per reviewed change'
);

select is(
  (select count(*) from public.v1_audit_events
   where actor_auth_user_id =
     '10000000-0000-4000-8000-000000000004'
     and idempotency_key =
       'ca100000-0000-4000-8000-000000000001'
     and event_type = 'permission_assignments_changed'),
  1::bigint,
  'A batch writes exactly one trusted audit transaction'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true
);
select is(
  (public.v1_apply_user_permission_changes(
    'usr-local-site-engineer',
    '[
      {"operation":"set","capability_key":"inventory.view","effect":"grant","scope_kind":"organization","project_ids":[],"effective_from":null,"effective_until":null},
      {"operation":"set","capability_key":"projects.edit","effect":"deny","scope_kind":"organization","project_ids":[],"effective_from":null,"effective_until":null},
      {"operation":"set","capability_key":"projects.edit","effect":"grant","scope_kind":"project","project_ids":["ca000000-0000-4000-8000-000000000001"],"effective_from":null,"effective_until":null},
      {"operation":"set","capability_key":"boq.view","effect":"grant","scope_kind":"organization","project_ids":[],"effective_from":null,"effective_until":null},
      {"operation":"set","capability_key":"boq.view","effect":"deny","scope_kind":"project","project_ids":["ca000000-0000-4000-8000-000000000002"],"effective_from":null,"effective_until":null}
    ]'::jsonb,
    'Scoped precedence and shadow proof',
    (select revision from v1_permission_test_revision
     where label = 'site_after_membership_insert'),
    'ca100000-0000-4000-8000-000000000001'
  ) ->> 'revision')::bigint,
  (select revision + 1 from v1_permission_test_revision
   where label = 'site_after_membership_insert'),
  'An exact idempotent retry returns the original completed workspace'
);

select throws_ok(
  $$select public.v1_apply_user_permission_changes(
    'usr-local-site-engineer',
    '[{"operation":"set","capability_key":"inventory.view","effect":"deny","scope_kind":"organization","project_ids":[],"effective_from":null,"effective_until":null}]'::jsonb,
    'Different payload',
    (select revision from v1_permission_test_revision
     where label = 'site_after_membership_insert'),
    'ca100000-0000-4000-8000-000000000001'
  )$$,
  '22023', 'V1_IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD',
  'Reusing a batch idempotency key with a different payload is rejected'
);

select throws_ok(
  $$select public.v1_apply_user_permission_changes(
    'usr-local-site-engineer',
    '[{"operation":"set","capability_key":"inventory.export","effect":"grant","scope_kind":"organization","project_ids":[],"effective_from":null,"effective_until":null}]'::jsonb,
    'Stale writer',
    (select revision from v1_permission_test_revision
     where label = 'site_after_membership_insert'),
    'ca100000-0000-4000-8000-000000000002'
  )$$,
  '40001', 'V1_PERMISSION_REVISION_CONFLICT',
  'A stale expected revision cannot overwrite a newer permission workspace'
);

select throws_ok(
  $$select public.v1_apply_user_permission_changes(
    'usr-local-admin',
    '[{"operation":"set","capability_key":"permissions.manage","effect":"grant","scope_kind":"organization","project_ids":[],"effective_from":null,"effective_until":null}]'::jsonb,
    'Self escalation attempt', 0,
    'ca100000-0000-4000-8000-000000000003'
  )$$,
  '42501', 'V1_PERMISSION_SELF_ESCALATION_DENIED',
  'A permission manager cannot change their own assignments'
);

select throws_ok(
  $$select public.v1_apply_user_permission_changes(
    'usr-local-site-engineer',
    '[
      {"operation":"set","capability_key":"documents.view","effect":"deny","scope_kind":"organization","project_ids":[],"effective_from":null,"effective_until":null},
      {"operation":"set","capability_key":"documents.upload","effect":"grant","scope_kind":"project","project_ids":["ca000000-0000-4000-8000-000000000001"],"effective_from":null,"effective_until":null}
    ]'::jsonb,
    'Dependency should rollback',
    (select revision + 1 from v1_permission_test_revision
     where label = 'site_after_membership_insert'),
    'ca100000-0000-4000-8000-000000000004'
  )$$,
  '23514', 'V1_PERMISSION_DEPENDENCY_NOT_EFFECTIVE',
  'An explicit grant with an ineffective dependency rejects the complete batch'
);

reset role;
select ok(
  (select current_revision.revision = baseline.revision + 1
   from public.v1_permission_revisions current_revision
   cross join v1_permission_test_revision baseline
   where current_revision.app_user_id = 'usr-local-site-engineer'
     and baseline.label = 'site_after_membership_insert')
  and not exists (
    select 1 from public.v1_permission_assignments
    where auth_user_id = '10000000-0000-4000-8000-000000000002'
      and capability_key = 'documents.view'
  ),
  'A failed dependency batch leaves no partial assignment or revision effect'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000009","role":"authenticated","app_metadata":{"role":"senior_mechanical_engineer","app_user_id":"usr-local-senior-mechanical-engineer"}}',
  true
);
select throws_ok(
  $$select public.v1_apply_user_permission_changes(
    'usr-local-site-engineer',
    '[{"operation":"set","capability_key":"configuration.view","effect":"grant","scope_kind":"organization","project_ids":[],"effective_from":null,"effective_until":null}]'::jsonb,
    'Beyond SME ceiling',
    (select revision + 1 from v1_permission_test_revision
     where label = 'site_after_membership_insert'),
    'ca100000-0000-4000-8000-000000000005'
  )$$,
  '42501', 'V1_PERMISSION_DELEGATION_CEILING_EXCEEDED',
  'A delegated manager cannot grant beyond its exact-role ceiling'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-site-engineer"}}',
  true
);
select is(
  public.v1_current_user_has_capability('inventory.view', null),
  false,
  'A stale JWT exact role fails closed even when a candidate assignment exists'
);

select is(
  public.v1_current_user_can_assign_exact_role(
    'usr-local-procurement', 'admin'
  ),
  false,
  'A stale JWT cannot reach the exact-role mutation preflight'
);

reset role;
update public.v1_profiles
set is_active = false
where auth_user_id = '10000000-0000-4000-8000-000000000002';

select is(
  (select revision from public.v1_permission_revisions
   where app_user_id = 'usr-local-site-engineer'),
  (select revision + 2 from v1_permission_test_revision
   where label = 'site_after_membership_insert'),
  'An active-state change emits a permission revision signal'
);

select is(
  coalesce((public.v1_permission_candidate_resolution(
    '10000000-0000-4000-8000-000000000002', 'inventory.view', null
  ) ->> 'effective')::boolean, false),
  false,
  'Inactive users cannot gain access from role defaults or explicit grants'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true
);
select throws_ok(
  $$select public.v1_apply_user_permission_changes(
    'usr-local-site-engineer',
    '[{"operation":"set","capability_key":"inventory.view","effect":"grant","scope_kind":"organization","project_ids":[],"effective_from":null,"effective_until":null}]'::jsonb,
    'Inactive target grant', 1,
    'ca100000-0000-4000-8000-000000000006'
  )$$,
  '42501', 'V1_PERMISSION_INACTIVE_TARGET_DENIED',
  'The mutation RPC refuses to stage access for an inactive target'
);

reset role;
update public.v1_profiles
set is_active = true
where auth_user_id = '10000000-0000-4000-8000-000000000002';

select throws_ok(
  $$update public.v1_permission_change_events
      set reason = 'Tampered history'
      where idempotency_key =
        'ca100000-0000-4000-8000-000000000001'$$,
  '42501', 'V1_PERMISSION_HISTORY_IMMUTABLE',
  'Even a privileged direct update cannot rewrite permission history'
);

select throws_ok(
  $$delete from public.v1_permission_change_events
      where idempotency_key =
        'ca100000-0000-4000-8000-000000000001'$$,
  '42501', 'V1_PERMISSION_HISTORY_IMMUTABLE',
  'Even a privileged direct delete cannot erase permission history'
);

insert into public.v1_permission_assignments (
  id, auth_user_id, capability_key, effect, scope_kind, reason
) values (
  'ca200000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000002',
  'projects.archive', 'grant', 'project', 'Conflict trigger proof'
);
insert into public.v1_permission_assignment_projects (
  assignment_id, project_id
) values (
  'ca200000-0000-4000-8000-000000000001',
  'ca000000-0000-4000-8000-000000000001'
);
insert into public.v1_permission_assignments (
  id, auth_user_id, capability_key, effect, scope_kind, reason
) values (
  'ca200000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-000000000002',
  'projects.archive', 'deny', 'project', 'Opposite conflict proof'
);

select throws_ok(
  $$insert into public.v1_permission_assignment_projects (
      assignment_id, project_id
    ) values (
      'ca200000-0000-4000-8000-000000000003',
      'ca000000-0000-4000-8000-000000000001'
    )$$,
  '23505', 'V1_PERMISSION_CONFLICTING_PROJECT_EFFECT',
  'Opposing project effects cannot overlap through direct database writes'
);

select throws_ok(
  $$insert into public.v1_permission_assignments (
      auth_user_id, capability_key, effect, scope_kind, reason
    ) values (
      '10000000-0000-4000-8000-000000000002',
      'projects.archive', 'grant', 'project', 'Duplicate project effect'
    )$$,
  '23505', null,
  'Only one current project assignment row exists per user, capability and effect'
);

select throws_ok(
  $$insert into public.v1_permission_assignments (
      auth_user_id, capability_key, effect, scope_kind, reason
    ) values (
      '10000000-0000-4000-8000-000000000002',
      'projects.edit', 'grant', 'organization', 'Conflict proof'
    )$$,
  '23505', null,
  'Only one current organization effect can exist per user and capability'
);

update public.v1_profiles
set is_active = false
where auth_user_id = '10000000-0000-4000-8000-000000000009';

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000009","role":"authenticated","app_metadata":{"role":"senior_mechanical_engineer","app_user_id":"usr-local-senior-mechanical-engineer"}}',
  true
);
select is(
  public.v1_current_user_can_assign_exact_role(
    'usr-local-site-engineer', 'admin'
  ),
  false,
  'An inactive exact-role actor cannot reach the role-mutation preflight'
);

reset role;

select throws_ok(
  $$update public.v1_profiles
      set is_active = false
      where auth_user_id =
        '10000000-0000-4000-8000-000000000004'$$,
  '23514', 'V1_PERMISSION_LAST_MANAGER_REQUIRED',
  'The final active permission administrator cannot be deactivated'
);

update public.v1_profiles
set is_active = true
where auth_user_id = '10000000-0000-4000-8000-000000000009';

insert into v1_permission_test_revision (label, revision)
select 'site_before_legacy_commercial', revision.revision
from public.v1_permission_revisions revision
where revision.app_user_id = 'usr-local-site-engineer';

insert into public.v1_user_capabilities (
  auth_user_id, capability, is_granted, reason,
  changed_by_auth_user_id
) values (
  '10000000-0000-4000-8000-000000000002',
  'view_commercials', true, 'Legacy convergence proof',
  '10000000-0000-4000-8000-000000000004'
);

select ok(
  exists (
    select 1 from public.v1_permission_assignments
    where auth_user_id = '10000000-0000-4000-8000-000000000002'
      and capability_key = 'commercials.view'
      and effect = 'grant'
      and origin = 'legacy_commercial'
  )
  and exists (
    select 1 from public.v1_permission_change_events
    where target_auth_user_id =
      '10000000-0000-4000-8000-000000000002'
      and capability_key = 'commercials.view'
      and event_kind = 'legacy_sync'
  )
  and (public.v1_permission_candidate_resolution(
    '10000000-0000-4000-8000-000000000002',
    'commercials.view', null
  ) ->> 'source') = 'legacy_override',
  'The retained commercial writer converges candidate state and immutable history'
);

select is(
  (select revision from public.v1_permission_revisions
   where app_user_id = 'usr-local-site-engineer'),
  (select revision + 1 from v1_permission_test_revision
   where label = 'site_before_legacy_commercial'),
  'A retained commercial override emits a permission revision signal'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);
select ok(
  (public.v1_get_current_commercial_capabilities()
    -> 'capabilities' -> 'view_commercials' ->> 'effective')::boolean
  and public.v1_current_user_has_capability('commercials.view', null),
  'The retained commercial capability contract remains authoritative in shadow mode'
);

select is(
  public.v1_current_user_has_capability('accounts.view', null),
  false,
  'Planned Accounts catalog entries remain disabled for every role'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);
select is(
  (select count(*) from public.v1_permission_revisions),
  1::bigint,
  'Revision RLS exposes only the current user row to an ordinary user'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true
);
select ok(
  (select count(*) from public.v1_permission_revisions) >= 6,
  'A permission viewer can subscribe to authorized target revision rows'
);

select ok(
  jsonb_array_length(
    public.v1_list_user_permission_history(
      'usr-local-site-engineer', 2, null, null
    ) -> 'items'
  ) = 2
  and public.v1_list_user_permission_history(
    'usr-local-site-engineer', 2, null, null
  ) ? 'next_cursor',
  'History pagination returns a bounded page and opaque next cursor'
);

reset role;
insert into v1_permission_test_revision (label, revision)
select 'project_manager_before_exact_role_change', revision.revision
from public.v1_permission_revisions revision
where revision.app_user_id = 'usr-local-project-manager';

update auth.users
set raw_app_meta_data = jsonb_set(
  coalesce(raw_app_meta_data, '{}'::jsonb),
  '{role}', '"document_controller"'::jsonb
)
where id = '10000000-0000-4000-8000-000000000010';

select is(
  (select revision from public.v1_permission_revisions
   where app_user_id = 'usr-local-project-manager'),
  (select revision + 1 from v1_permission_test_revision
   where label = 'project_manager_before_exact_role_change'),
  'An exact global-role change emits one revision signal despite equal canonical roles'
);

insert into v1_permission_test_revision (label, revision)
select 'site_before_membership_update', revision.revision
from public.v1_permission_revisions revision
where revision.app_user_id = 'usr-local-site-engineer';

update public.v1_project_members member
set effective_from = member.effective_from - interval '1 minute'
where member.project_id = 'ca000000-0000-4000-8000-000000000001'
  and member.member_auth_user_id =
    '10000000-0000-4000-8000-000000000002';

select is(
  (select revision from public.v1_permission_revisions
   where app_user_id = 'usr-local-site-engineer'),
  (select revision + 1 from v1_permission_test_revision
   where label = 'site_before_membership_update'),
  'A dated project-membership change emits one target revision signal'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true
);
select ok(
  public.v1_current_user_can_assign_exact_role(
    'usr-local-site-engineer', 'procurement'
  )
  and public.v1_current_user_can_assign_new_exact_role('procurement')
  and not public.v1_current_user_can_assign_exact_role(
    'usr-local-admin', 'procurement'
  ),
  'Exact Admin may assign any exact role but cannot mutate its own role'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000009","role":"authenticated","app_metadata":{"role":"senior_mechanical_engineer","app_user_id":"usr-local-senior-mechanical-engineer"}}',
  true
);
select ok(
  public.v1_current_user_can_assign_exact_role(
    'usr-local-site-engineer', 'admin'
  )
  and public.v1_current_user_can_assign_new_exact_role('admin'),
  'The cutover preserves the established exact SME role-assignment gateway'
);

reset role;
insert into public.v1_permission_assignments (
  auth_user_id, capability_key, effect, scope_kind, reason
) values
  (
    '10000000-0000-4000-8000-000000000002',
    'users.view', 'grant', 'organization', 'Role guard test'
  ),
  (
    '10000000-0000-4000-8000-000000000002',
    'users.create', 'grant', 'organization', 'Role guard test'
  );
update public.v1_capability_catalog
set authorization_mode = 'enforced'
where capability_key in (
  'users.view', 'users.create', 'users.roles.assign'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);
select ok(
  not public.v1_current_user_has_capability('users.create', null)
  and not public.v1_current_user_can_assign_new_exact_role('site_engineer'),
  'users.create remains ineffective without its roles.assign dependency'
);

reset role;
insert into public.v1_permission_assignments (
  auth_user_id, capability_key, effect, scope_kind, reason
) values (
  '10000000-0000-4000-8000-000000000002',
  'users.roles.assign', 'grant', 'organization', 'Role guard test'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);
select ok(
  public.v1_current_user_has_capability('users.roles.assign', null)
  and public.v1_current_user_has_capability('users.create', null)
  and not public.v1_current_user_can_assign_exact_role(
    'usr-local-procurement', 'site_engineer'
  ),
  'A person-specific roles.assign grant alone cannot become an escalation primitive'
);

reset role;
insert into public.v1_permission_assignments (
  auth_user_id, capability_key, effect, scope_kind, reason
) values
  (
    '10000000-0000-4000-8000-000000000002',
    'permissions.view', 'grant', 'organization', 'Role guard test'
  ),
  (
    '10000000-0000-4000-8000-000000000002',
    'permissions.manage', 'grant', 'organization', 'Role guard test'
  ),
  (
    '10000000-0000-4000-8000-000000000002',
    'permissions.delegate', 'grant', 'organization', 'Role guard test'
  );
update public.v1_capability_catalog
set authorization_mode = 'enforced'
where capability_key in (
  'permissions.view', 'permissions.manage', 'permissions.delegate'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);
select ok(
  not public.v1_current_user_can_assign_exact_role(
    'usr-local-procurement', 'site_engineer'
  )
  and not public.v1_current_user_can_assign_new_exact_role('site_engineer')
  and not public.v1_current_user_can_assign_exact_role(
    'usr-local-procurement', 'admin'
  )
  and not public.v1_current_user_can_assign_new_exact_role('admin'),
  'A delegated ordinary manager cannot assign a role carrying nondelegable Accounts authority'
);

select ok(
  coalesce((
    select (capability ->> 'actor_can_delegate')::boolean
    from jsonb_array_elements(
      public.v1_get_user_permission_workspace('usr-local-procurement')
        -> 'catalog'
    ) capability
    where capability ->> 'capability_key' = 'material_requests.create'
  ), false)
  and not coalesce((
    select (capability ->> 'actor_can_delegate')::boolean
    from jsonb_array_elements(
      public.v1_get_user_permission_workspace('usr-local-procurement')
        -> 'catalog'
    ) capability
    where capability ->> 'capability_key' = 'configuration.view'
  ), true),
  'Target workspace projects the live actor delegation ceiling per capability'
);

select ok(
  coalesce((
    select capability -> 'actor_delegable_scope_kinds'
      = '["project"]'::jsonb
    from jsonb_array_elements(
      public.v1_get_user_permission_workspace('usr-local-procurement')
        -> 'catalog'
    ) capability
    where capability ->> 'capability_key' = 'boq.view'
  ), false)
  and coalesce((
    select capability -> 'actor_delegable_scope_kinds'
      = '["organization"]'::jsonb
    from jsonb_array_elements(
      public.v1_get_user_permission_workspace('usr-local-procurement')
        -> 'catalog'
    ) capability
    where capability ->> 'capability_key' = 'projects.create'
  ), false),
  'The server projects project-only versus organization scope ceilings without role inference'
);

select throws_ok(
  $$select public.v1_set_user_permission_assignment(
    'usr-local-procurement', 'boq.view', 'grant', 'organization',
    '{}'::uuid[], null, null, 'Delegated global scope attempt',
    (select revision from public.v1_permission_revisions
     where app_user_id = 'usr-local-procurement'),
    'ca100000-0000-4000-8000-000000000020'
  )$$,
  '42501',
  'V1_PERMISSION_ORGANIZATION_SCOPE_GLOBAL_AUTHORITY_REQUIRED',
  'A delegated project-bound capability cannot be widened to organization scope'
);

reset role;
insert into public.v1_permission_assignments (
  auth_user_id, capability_key, effect, scope_kind, reason
)
select
  '10000000-0000-4000-8000-000000000003'::uuid,
  capability_key,
  'grant',
  'organization',
  'Delegated Procurement scope-ceiling proof'
from unnest(array[
  'users.view', 'permissions.view',
  'permissions.manage', 'permissions.delegate'
]::text[]) capability_key;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);
select ok(
  public.v1_current_user_has_capability('projects.view_all', null)
  and not public.v1_current_user_has_capability(
    'projects.view',
    'ca000000-0000-4000-8000-000000000005'::uuid
  ),
  'A delegated Procurement actor is not globally unrestricted across completed project state'
);
select throws_ok(
  $$select public.v1_set_user_permission_assignment(
    'usr-local-site-engineer', 'boq.view', 'grant', 'organization',
    '{}'::uuid[], null, null, 'Procurement global scope attempt',
    (select revision from public.v1_permission_revisions
     where app_user_id = 'usr-local-site-engineer'),
    'ca100000-0000-4000-8000-000000000029'
  )$$,
  '42501',
  'V1_PERMISSION_ORGANIZATION_SCOPE_GLOBAL_AUTHORITY_REQUIRED',
  'projects.view_all alone cannot widen Procurement beyond its structural project states'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);

select throws_ok(
  $$select public.v1_set_user_permission_assignment(
    'usr-local-procurement', 'boq.view', 'grant', 'project',
    array[
      'ca000000-0000-4000-8000-000000000001',
      'ca000000-0000-4000-8000-000000000004'
    ]::uuid[], null, null, 'Mixed visible and hidden project attempt',
    (select revision from public.v1_permission_revisions
     where app_user_id = 'usr-local-procurement'),
    'ca100000-0000-4000-8000-000000000021'
  )$$,
  '42501', 'V1_PERMISSION_PROJECT_SCOPE_ACCESS_DENIED',
  'A project-scoped set requires actor access to every selected project'
);

select lives_ok(
  $$select public.v1_set_user_permission_assignment(
    'usr-local-procurement', 'boq.view', 'grant', 'project',
    array['ca000000-0000-4000-8000-000000000001']::uuid[],
    null, null, 'Delegated accessible project assignment',
    (select revision from public.v1_permission_revisions
     where app_user_id = 'usr-local-procurement'),
    'ca100000-0000-4000-8000-000000000022'
  )$$,
  'A delegated manager can assign its capability within a fully visible project scope'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true
);
select lives_ok(
  $$select public.v1_set_user_permission_assignment(
    'usr-local-procurement', 'boq.view', 'grant', 'project',
    array[
      'ca000000-0000-4000-8000-000000000001',
      'ca000000-0000-4000-8000-000000000004'
    ]::uuid[], null, null, 'Admin multi-project authority proof',
    (select revision from public.v1_permission_revisions
     where app_user_id = 'usr-local-procurement'),
    'ca100000-0000-4000-8000-000000000023'
  )$$,
  'Admin preserves organization-wide project assignment authority'
);

-- Keep the opaque assignment key only inside this transaction. A restricted
-- actor must not receive it through any workspace projection, but the clear
-- command must still reject an out-of-scope identifier if it is supplied.
select set_config(
  'test.mixed_scope_assignment_id',
  (
    select assignment ->> 'id'
    from jsonb_array_elements(
      public.v1_get_user_permission_workspace('usr-local-procurement')
        -> 'assignments'
    ) assignment
    where assignment ->> 'capability_key' = 'boq.view'
      and assignment ->> 'scope_kind' = 'project'
      and assignment ->> 'effect' = 'grant'
  ),
  true
);

select lives_ok(
  $$select public.v1_set_user_permission_assignment(
    'usr-local-procurement', 'material_requests.create', 'grant', 'project',
    array['ca000000-0000-4000-8000-000000000004']::uuid[],
    null, null, 'SECRET-HIDDEN-ONLY-REASON',
    (select revision from public.v1_permission_revisions
     where app_user_id = 'usr-local-procurement'),
    'ca100000-0000-4000-8000-000000000028'
  )$$,
  'Admin can create a hidden-only project assignment for redaction proof'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);
select ok(
  public.v1_get_user_permission_workspace('usr-local-procurement')::text
    not like '%ca000000-0000-4000-8000-000000000004%'
  and public.v1_get_user_permission_workspace('usr-local-procurement')::text
    not like '%CAP-RESTRICTED-004%'
  and public.v1_get_user_permission_workspace('usr-local-procurement')::text
    not like '%Restricted capability project%'
  and public.v1_get_user_permission_workspace('usr-local-procurement')::text
    like '%ca000000-0000-4000-8000-000000000001%'
  and public.v1_list_user_permission_history(
    'usr-local-procurement', 50, null, null
  )::text not like '%ca000000-0000-4000-8000-000000000004%'
  and public.v1_list_user_permission_history(
    'usr-local-procurement', 50, null, null
  )::text not like '%SECRET-HIDDEN-ONLY-REASON%',
  'Workspace, capability, assignment and history projections redact every inaccessible project identifier'
);

select ok(
  coalesce((
    select
      not (capability ->> 'organization_summary_visible')::boolean
      and capability -> 'authoritative_effective' = 'null'::jsonb
      and capability -> 'authoritative_source' = 'null'::jsonb
      and capability -> 'candidate_effective' = 'null'::jsonb
      and capability -> 'candidate_source' = 'null'::jsonb
      and capability -> 'parity' = 'null'::jsonb
    from jsonb_array_elements(
      public.v1_get_user_permission_workspace('usr-local-procurement')
        -> 'catalog'
    ) capability
    where capability ->> 'capability_key' = 'boq.view'
  ), false),
  'A project-only viewer receives no target organization grant, deny, source or parity summary'
);

select ok(
  not exists (
    select 1
    from jsonb_array_elements(
      public.v1_get_user_permission_workspace('usr-local-procurement')
        -> 'assignments'
    ) assignment
    where assignment ->> 'capability_key' = 'boq.view'
      and assignment ->> 'scope_kind' = 'project'
      and assignment ->> 'effect' = 'grant'
  )
  and not exists (
    select 1
    from jsonb_array_elements(
      public.v1_get_user_permission_workspace('usr-local-procurement')
        -> 'assignments'
    ) assignment
    where assignment ->> 'capability_key' = 'material_requests.create'
      and assignment ->> 'scope_kind' = 'project'
  ),
  'Mixed-scope and hidden-only assignments are omitted instead of returning empty or partial project arrays'
);

select ok(
  coalesce((
    select
      event ->> 'reason'
        = 'Partially visible project-scoped permission change'
      and event -> 'before' = 'null'::jsonb
      and event -> 'after' = 'null'::jsonb
      and event -> 'project_ids'
        = '["ca000000-0000-4000-8000-000000000001"]'::jsonb
    from jsonb_array_elements(
      public.v1_list_user_permission_history(
        'usr-local-procurement', 1, null, null
      ) -> 'items'
    ) event
  ), false),
  'History filters hidden-only events before pagination and safely summarizes a mixed-scope event'
);

select throws_ok(
  $$select public.v1_clear_user_permission_assignment(
    'usr-local-procurement',
    current_setting('test.mixed_scope_assignment_id')::uuid,
    'Delegated partial-scope clear attempt',
    (select revision from public.v1_permission_revisions
     where app_user_id = 'usr-local-procurement'),
    'ca100000-0000-4000-8000-000000000024'
  )$$,
  '42501', 'V1_PERMISSION_PROJECT_SCOPE_ACCESS_DENIED',
  'Clear cannot remove an assignment whose complete project scope is outside actor access'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000009","role":"authenticated","app_metadata":{"role":"senior_mechanical_engineer","app_user_id":"usr-local-senior-mechanical-engineer"}}',
  true
);
select ok(
  coalesce((
    select capability -> 'actor_delegable_scope_kinds'
      = '["organization", "project"]'::jsonb
    from jsonb_array_elements(
      public.v1_get_user_permission_workspace('usr-local-procurement')
        -> 'catalog'
    ) capability
    where capability ->> 'capability_key' = 'boq.view'
  ), false),
  'Senior Mechanical Engineer preserves both global and project scope ceilings'
);
select lives_ok(
  $$select public.v1_clear_user_permission_assignment(
    'usr-local-procurement',
    current_setting('test.mixed_scope_assignment_id')::uuid,
    'SME full-scope clear authority proof',
    (select revision from public.v1_permission_revisions
     where app_user_id = 'usr-local-procurement'),
    'ca100000-0000-4000-8000-000000000025'
  )$$,
  'Senior Mechanical Engineer can clear an assignment across its full global scope'
);
select lives_ok(
  $$select public.v1_set_user_permission_assignment(
    'usr-local-procurement', 'boq.view', 'deny', 'organization',
    '{}'::uuid[], null, null, 'SME global scope authority proof',
    (select revision from public.v1_permission_revisions
     where app_user_id = 'usr-local-procurement'),
    'ca100000-0000-4000-8000-000000000026'
  )$$,
  'Senior Mechanical Engineer preserves organization-wide assignment authority'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
  true
);
select lives_ok(
  $$select public.v1_set_user_permission_assignment(
    'usr-local-site-engineer', 'projects.view', 'deny', 'project',
    array['ca000000-0000-4000-8000-000000000001']::uuid[],
    null, null, 'Dependency projection proof',
    (select revision from public.v1_permission_revisions
     where app_user_id = 'usr-local-site-engineer'),
    'ca100000-0000-4000-8000-000000000027'
  )$$,
  'Admin can apply a project-specific prerequisite deny'
);
select ok(
  coalesce((
    select
      project_resolution ->> 'project_id'
        = 'ca000000-0000-4000-8000-000000000001'
      and project_resolution -> 'assignment_id' = 'null'::jsonb
      and not (project_resolution ->> 'authoritative_effective')::boolean
      and not (project_resolution ->> 'candidate_effective')::boolean
    from jsonb_array_elements(
      (
        select capability -> 'project_overrides'
        from jsonb_array_elements(
          public.v1_get_user_permission_workspace(
            'usr-local-site-engineer'
          ) -> 'catalog'
        ) capability
        where capability ->> 'capability_key' = 'boq.edit'
      )
    ) project_resolution
    where project_resolution ->> 'project_id'
      = 'ca000000-0000-4000-8000-000000000001'
  ), false),
  'Every accessible project is projected and a projects.view deny propagates to dependent BOQ resolution'
);

reset role;
select throws_ok(
  $$insert into public.v1_permission_assignments (
      auth_user_id, capability_key, effect, scope_kind,
      effective_from, reason
    ) values (
      '10000000-0000-4000-8000-000000000003',
      'permissions.manage', 'deny', 'organization',
      clock_timestamp() + interval '1 day', 'Scheduled manager deny'
    )$$,
  '23514', 'V1_PERMISSION_MANAGER_SCHEDULE_FORBIDDEN',
  'A future deny cannot silently remove permission-management authority'
);

select throws_ok(
  $$insert into public.v1_permission_assignments (
      auth_user_id, capability_key, effect, scope_kind,
      effective_until, reason
    ) values (
      '10000000-0000-4000-8000-000000000003',
      'permissions.delegate', 'grant', 'organization',
      clock_timestamp() + interval '1 day', 'Expiring manager grant'
    )$$,
  '23514', 'V1_PERMISSION_MANAGER_SCHEDULE_FORBIDDEN',
  'An expiring grant cannot silently remove permission-management authority'
);

select throws_ok(
  $$insert into public.v1_permission_assignments (
      auth_user_id, capability_key, effect, scope_kind,
      effective_until, reason
    ) values (
      '10000000-0000-4000-8000-000000000003',
      'users.view', 'deny', 'organization',
      clock_timestamp() + interval '1 day', 'Expiring dependency deny'
    )$$,
  '23514', 'V1_PERMISSION_MANAGER_SCHEDULE_FORBIDDEN',
  'A timed dependency change cannot bypass last-manager continuity'
);

select lives_ok(
  $$insert into public.v1_permission_assignments (
      auth_user_id, capability_key, effect, scope_kind,
      effective_from, effective_until, reason
    ) values (
      '10000000-0000-4000-8000-000000000003',
      'inventory.export', 'grant', 'organization',
      clock_timestamp() + interval '1 day',
      clock_timestamp() + interval '2 days',
      'Ordinary scheduled capability'
    )$$,
  'Ordinary non-administration capabilities remain schedulable'
);

reset role;
insert into public.v1_permission_assignments (
  id, auth_user_id, capability_key, effect, scope_kind, effective_from, reason
) values (
  'ca200000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000002',
  'inventory.categories.manage', 'grant', 'organization',
  '2099-01-01 00:00:00+00', 'Scheduled transition proof'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);
select is(
  (public.v1_get_current_permission_snapshot()
    ->> 'next_transition_at')::timestamptz,
  '2099-01-01 00:00:00+00'::timestamptz,
  'The self snapshot exposes the next timed assignment boundary for exact refresh'
);

reset role;
insert into public.v1_projects (
  id, project_ref, name, state, current_action_owner_role,
  created_by_auth_user_id, created_by_role
) values (
  'ca000000-0000-4000-8000-000000000003', 'CAP-PROJECT-003',
  'Scheduled membership project', 'active', 'project_engineer',
  '10000000-0000-4000-8000-000000000004', 'admin'
);
insert into public.v1_project_members (
  project_id, member_auth_user_id, project_role, effective_from,
  reason, assigned_by_auth_user_id, assigned_by_role
) values (
  'ca000000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-000000000002', 'site_engineer',
  '2098-01-01 00:00:00+00', 'Scheduled transition proof',
  '10000000-0000-4000-8000-000000000004', 'admin'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);
select is(
  (public.v1_get_current_permission_snapshot()
    ->> 'next_transition_at')::timestamptz,
  '2098-01-01 00:00:00+00'::timestamptz,
  'A nearer dated membership boundary becomes the exact next snapshot refresh'
);

reset role;
update public.v1_capability_catalog
set authorization_mode = 'shadow'
where capability_key in ('boq.view', 'boq.edit');

select ok(
  (public.v1_permission_cutover_parity_report(
    array['boq.view', 'boq.edit']::text[]
  ) ->> 'mismatch_count')::integer > 0
  and public.v1_permission_cutover_parity_report(
    array['boq.view', 'boq.edit']::text[]
  )::text not like '%@%'
  and public.v1_permission_cutover_parity_report(
    array['boq.view', 'boq.edit']::text[]
  )::text not like '%Restricted capability project%',
  'The reusable parity report detects drift while exposing only safe identifiers and counts'
);

select throws_ok(
  $test$
  do $cutover$
  begin
    perform public.v1_assert_permission_cutover_parity(
      array['boq.view', 'boq.edit']::text[]
    );
    update public.v1_capability_catalog
    set authorization_mode = 'enforced'
    where capability_key in ('boq.view', 'boq.edit');
  end;
  $cutover$;
  $test$,
  '23514', 'V1_PERMISSION_CUTOVER_PARITY_MISMATCH',
  'A parity mismatch aborts the cutover before any authorization mode flips'
);

select is(
  (
    select count(*)::integer
    from public.v1_capability_catalog
    where capability_key in ('boq.view', 'boq.edit')
      and authorization_mode = 'shadow'
  ),
  2,
  'A failed multi-key parity gate leaves every mode unchanged atomically'
);

select * from finish();
rollback;
