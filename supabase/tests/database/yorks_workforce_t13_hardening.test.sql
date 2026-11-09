begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

create temporary table t13_workforce_tables on commit drop as
select class.oid, class.relname, class.relrowsecurity
from pg_catalog.pg_class class
join pg_catalog.pg_namespace namespace on namespace.oid = class.relnamespace
where namespace.nspname = 'public'
  and class.relkind in ('r', 'p')
  and class.relname like 'v1_workforce_%';

select is(
  (select array_agg(relname order by relname) from t13_workforce_tables),
  array[
    'v1_workforce_attendance_days',
    'v1_workforce_calendar_dates',
    'v1_workforce_calendar_weekdays',
    'v1_workforce_calendars',
    'v1_workforce_document_upload_metadata',
    'v1_workforce_document_version_metadata',
    'v1_workforce_internal_locations',
    'v1_workforce_monthly_approval_revisions',
    'v1_workforce_monthly_approved_snapshots',
    'v1_workforce_monthly_correction_contexts',
    'v1_workforce_monthly_edit_scope_entries',
    'v1_workforce_monthly_edit_scopes',
    'v1_workforce_monthly_period_dates',
    'v1_workforce_monthly_period_workers',
    'v1_workforce_monthly_periods',
    'v1_workforce_monthly_reopen_requests',
    'v1_workforce_monthly_reviewer_corrections',
    'v1_workforce_monthly_transitions',
    'v1_workforce_monthly_validation_issues',
    'v1_workforce_monthly_validation_runs',
    'v1_workforce_notification_deliveries',
    'v1_workforce_notification_digests',
    'v1_workforce_report_artifact_snapshots',
    'v1_workforce_report_artifacts',
    'v1_workforce_responsibility_assignments',
    'v1_workforce_shift_templates',
    'v1_workforce_team_schedule_links',
    'v1_workforce_teams',
    'v1_workforce_timesheet_allocation_revisions',
    'v1_workforce_timesheet_allocation_sets',
    'v1_workforce_timesheet_allocations',
    'v1_workforce_timesheet_discussions',
    'v1_workforce_trades',
    'v1_workforce_worker_assignments',
    'v1_workforce_workers'
  ]::name[],
  'T13 freezes the exact accepted T01-T12 Workforce relation inventory'
);

select ok(
  (select bool_and(relrowsecurity) from t13_workforce_tables),
  'RLS remains enabled on every accepted Workforce relation'
);

select ok(
  not exists (
    select 1
    from t13_workforce_tables table_row
    cross join unnest(array['anon', 'authenticated']) role_name
    cross join unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE']) privilege
    where pg_catalog.has_table_privilege(
      role_name,
      table_row.oid,
      privilege
    )
  ),
  'Anon and authenticated retain no direct Workforce table CRUD'
);

select ok(
  not exists (
    select 1
    from t13_workforce_tables table_row
    cross join unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE']) privilege
    where not pg_catalog.has_table_privilege(
      'service_role',
      table_row.oid,
      privilege
    )
  ),
  'Service administration retains explicit CRUD on every Workforce relation'
);

select is(
  (
    select array_agg(table_row.relname order by table_row.relname)
    from t13_workforce_tables table_row
    where not exists (
      select 1
      from pg_catalog.pg_trigger trigger
      where trigger.tgrelid = table_row.oid
        and not trigger.tgisinternal
        and pg_catalog.pg_get_triggerdef(trigger.oid) ilike '%before delete%'
    )
  ),
  array['v1_workforce_monthly_correction_contexts']::name[],
  'Only the transaction-scoped correction context is exempt from retained-row hard-delete guards'
);

select is(
  (
    select count(*)
    from information_schema.columns
    where table_schema = 'public'
      and table_name like 'v1_workforce_%'
      and column_name ~* '(^|_)(salary|wage|pay_rate|payroll|bank_account|unit_cost|total_cost|cost_amount)(_|$)'
  ),
  0::bigint,
  'The Workforce schema contains no payroll, bank or commercial cost authority'
);

select ok(
  not pg_catalog.has_table_privilege(
    'authenticated', 'public.v1_audit_events', 'INSERT'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.v1_audit_events', 'UPDATE'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.v1_audit_events', 'DELETE'
  ),
  'Authenticated callers cannot forge or rewrite audit evidence directly'
);

select ok(
  exists (
    select 1 from pg_catalog.pg_indexes
    where schemaname = 'public'
      and indexname = 'v1_workforce_attendance_days_worker_id_work_date_key'
  )
  and exists (
    select 1 from pg_catalog.pg_indexes
    where schemaname = 'public'
      and indexname = 'v1_workforce_worker_assignments_worker_date_idx'
  )
  and exists (
    select 1 from pg_catalog.pg_indexes
    where schemaname = 'public'
      and indexname = 'v1_workforce_monthly_workers_page_idx'
  )
  and exists (
    select 1 from pg_catalog.pg_indexes
    where schemaname = 'public'
      and indexname = 'v1_workforce_monthly_issues_filter_idx'
  )
  and exists (
    select 1 from pg_catalog.pg_indexes
    where schemaname = 'public'
      and indexname = 'v1_workforce_monthly_transitions_period_idx'
  )
  and exists (
    select 1 from pg_catalog.pg_indexes
    where schemaname = 'public'
      and indexname = 'v1_workforce_report_artifacts_actor_page_idx'
  ),
  'Worker-date, period-page, issue, lifecycle and report read paths remain indexed'
);

create temporary table t13_workforce_functions on commit drop as
select procedure.oid,
  procedure.proname,
  pg_catalog.pg_get_function_identity_arguments(procedure.oid) as arguments,
  procedure.prosecdef,
  procedure.proconfig
from pg_catalog.pg_proc procedure
join pg_catalog.pg_namespace namespace
  on namespace.oid = procedure.pronamespace
where namespace.nspname = 'public'
  and procedure.prokind = 'f'
  and (
    procedure.proname like '%workforce%'
    or case
      when procedure.prokind = 'f'
        then pg_catalog.pg_get_functiondef(procedure.oid) ilike '%v1_workforce_%'
      else false
    end
  );

create temporary table t13_authenticated_rpc_inventory(
  signature text primary key
) on commit drop;

insert into t13_authenticated_rpc_inventory(signature) values
  ('v1_apply_user_permission_changes_with_workforce(p_target_app_user_id text, p_changes jsonb, p_reason text, p_expected_revision bigint, p_assign_organization_responsibility boolean, p_idempotency_key uuid)'),
  ('v1_approve_lock_workforce_monthly_period(p_payload jsonb, p_expected_period_version bigint, p_idempotency_key uuid)'),
  ('v1_assign_user_workforce_organization(p_target_app_user_id text, p_reason text, p_idempotency_key uuid)'),
  ('v1_authorize_workforce_monthly_reopen(p_payload jsonb, p_expected_period_version bigint, p_idempotency_key uuid)'),
  ('v1_chat_is_active_member(p_conversation_id uuid, p_auth_user_id uuid)'),
  ('v1_correct_workforce_monthly_entry_during_review(p_payload jsonb, p_expected_period_version bigint, p_idempotency_key uuid)'),
  ('v1_dispatch_workforce_notification_digest(p_payload jsonb, p_idempotency_key uuid)'),
  ('v1_document_target_project_id(p_entity_type text, p_entity_id uuid)'),
  ('v1_document_target_readable(p_entity_type text, p_entity_id uuid)'),
  ('v1_document_target_writable(p_entity_type text, p_entity_id uuid, p_classification text)'),
  ('v1_generate_workforce_report(p_payload jsonb, p_idempotency_key uuid)'),
  ('v1_get_my_yorks_profile(p_project_offset integer, p_project_limit integer)'),
  ('v1_get_my_yorks_profile_workspace()'),
  ('v1_get_operational_analytics_foundation(p_project_id uuid, p_months integer)'),
  ('v1_get_workforce_attendance(p_work_date date, p_worker_id uuid)'),
  ('v1_get_workforce_administration_options(p_on_date date)'),
  ('v1_get_workforce_collaboration(p_period_id uuid)'),
  ('v1_get_workforce_configuration(p_on_date date)'),
  ('v1_get_workforce_daily_roster(p_work_date date, p_team_id uuid, p_project_id uuid, p_project_scope_id uuid, p_internal_location_id uuid, p_query text, p_limit integer, p_offset integer)'),
  ('v1_get_workforce_team_workers(p_team_id uuid, p_offset integer)'),
  ('v1_create_workforce_team_worker(p_team_id uuid, p_payload jsonb, p_idempotency_key uuid)'),
  ('v1_get_workforce_foundation(p_query text, p_status text, p_limit integer, p_offset integer, p_on_date date)'),
  ('v1_get_workforce_monthly_lifecycle(p_period_id uuid)'),
  ('v1_get_workforce_monthly_period(p_team_id uuid, p_period_month date, p_query text, p_issue_severity text, p_issue_code text, p_worker_limit integer, p_worker_offset integer)'),
  ('v1_get_workforce_monthly_worker_detail(p_period_id uuid, p_validation_run_id uuid, p_worker_id uuid)'),
  ('v1_get_workforce_overview(p_request jsonb)'),
  ('v1_get_workforce_timesheet_allocations(p_work_date date, p_worker_id uuid)'),
  ('v1_get_user_permission_workspace(p_target_app_user_id text)'),
  ('v1_issue_workforce_report_export(p_payload jsonb, p_idempotency_key uuid)'),
  ('v1_list_workforce_documents(p_period_id uuid, p_attendance_day_id uuid, p_worker_id uuid)'),
  ('v1_list_workforce_monthly_approval_queue(p_status text, p_limit integer, p_offset integer)'),
  ('v1_list_workforce_monthly_issues(p_period_id uuid, p_validation_run_id uuid, p_severity text, p_issue_code text, p_worker_id uuid, p_limit integer, p_offset integer)'),
  ('v1_list_workforce_monthly_teams(p_period_month date, p_query text, p_limit integer, p_offset integer)'),
  ('v1_list_workforce_report_artifacts(p_limit integer, p_offset integer)'),
  ('v1_open_workforce_timesheet_discussion(p_period_id uuid, p_idempotency_key uuid)'),
  ('v1_prepare_workforce_document_upload(p_payload jsonb, p_idempotency_key uuid)'),
  ('v1_request_workforce_monthly_reopen(p_payload jsonb, p_expected_period_version bigint, p_idempotency_key uuid)'),
  ('v1_return_workforce_monthly_period(p_payload jsonb, p_expected_period_version bigint, p_idempotency_key uuid)'),
  ('v1_save_workforce_attendance_day(p_payload jsonb, p_expected_version bigint, p_idempotency_key uuid)'),
  ('v1_save_workforce_calendar(p_payload jsonb, p_expected_version bigint, p_idempotency_key uuid)'),
  ('v1_save_workforce_calendar_date(p_payload jsonb, p_expected_version bigint, p_idempotency_key uuid)'),
  ('v1_save_workforce_daily_roster(p_work_date date, p_rows jsonb, p_reason text, p_idempotency_key uuid)'),
  ('v1_save_workforce_internal_location(p_payload jsonb, p_expected_version bigint, p_idempotency_key uuid)'),
  ('v1_save_workforce_responsibility_assignment(p_payload jsonb, p_expected_version bigint, p_idempotency_key uuid)'),
  ('v1_save_workforce_shift_template(p_payload jsonb, p_expected_version bigint, p_idempotency_key uuid)'),
  ('v1_save_workforce_team(p_payload jsonb, p_expected_version bigint, p_idempotency_key uuid)'),
  ('v1_save_workforce_team_schedule(p_payload jsonb, p_expected_version bigint, p_idempotency_key uuid)'),
  ('v1_save_workforce_timesheet_allocations(p_payload jsonb, p_expected_version bigint, p_idempotency_key uuid)'),
  ('v1_save_workforce_trade(p_payload jsonb, p_expected_version bigint, p_idempotency_key uuid)'),
  ('v1_save_workforce_worker(p_payload jsonb, p_expected_version bigint, p_idempotency_key uuid)'),
  ('v1_save_workforce_worker_assignment(p_payload jsonb, p_expected_version bigint, p_idempotency_key uuid)'),
  ('v1_send_workforce_timesheet_message(p_payload jsonb, p_idempotency_key uuid)'),
  ('v1_submit_workforce_monthly_period(p_payload jsonb, p_expected_period_version bigint, p_idempotency_key uuid)'),
  ('v1_transfer_workforce_worker_assignment(p_payload jsonb, p_expected_current_assignment_id uuid, p_expected_current_version bigint, p_idempotency_key uuid)'),
  ('v1_validate_workforce_monthly_period(p_payload jsonb, p_expected_period_version bigint, p_idempotency_key uuid)'),
  ('v1_verify_workforce_monthly_period(p_payload jsonb, p_expected_period_version bigint, p_idempotency_key uuid)'),
  ('v1_withdraw_workforce_timesheet_allocations(p_attendance_day_id uuid, p_reason text, p_expected_version bigint, p_idempotency_key uuid)');

select set_eq(
  'select proname || ''('' || arguments || '')''
     from t13_workforce_functions
    where pg_catalog.has_function_privilege(
      ''authenticated'', oid, ''EXECUTE''
    )',
  'select signature from t13_authenticated_rpc_inventory',
  'Authenticated execution matches the exact accepted RPC inventory'
);

select ok(
  not exists (
    select 1
    from t13_workforce_functions function_row
    where pg_catalog.has_function_privilege(
      'authenticated', function_row.oid, 'EXECUTE'
    )
      and (
        not function_row.prosecdef
        or coalesce(array_to_string(function_row.proconfig, ','), '')
          <> 'search_path=""'
      )
  ),
  'Every authenticated Workforce RPC is SECURITY DEFINER with an empty search path'
);

select ok(
  not exists (
    select 1
    from t13_workforce_functions function_row
    where function_row.proname like 'v1_workforce_%'
      and (
        pg_catalog.has_function_privilege(
          'public', function_row.oid, 'EXECUTE'
        )
        or pg_catalog.has_function_privilege(
          'anon', function_row.oid, 'EXECUTE'
        )
        or pg_catalog.has_function_privilege(
          'authenticated', function_row.oid, 'EXECUTE'
        )
      )
  ),
  'Internal Workforce helpers remain non-callable by public client roles'
);

select ok(
  not exists (
    select 1
    from t13_workforce_functions function_row
    where pg_catalog.has_function_privilege(
      'public', function_row.oid, 'EXECUTE'
    )
      or pg_catalog.has_function_privilege(
        'anon', function_row.oid, 'EXECUTE'
      )
  ),
  'No Workforce-related function is executable by PUBLIC or anon'
);

select ok(
  not exists (
    select 1
    from t13_workforce_functions function_row
    where function_row.prosecdef
      and coalesce(array_to_string(function_row.proconfig, ','), '')
        <> 'search_path=""'
  ),
  'Every privileged Workforce-related helper fixes an empty search path'
);

select is(
  (
    select jsonb_agg(
      jsonb_build_object(
        'key', capability_key,
        'status', status,
        'authorization_mode', authorization_mode,
        'is_assignable', is_assignable
      ) order by capability_key
    )
    from public.v1_capability_catalog
    where capability_key like 'workforce.%'
  ),
  '[
    {"key":"workforce.attendance.maintain","status":"operational","authorization_mode":"enforced","is_assignable":true},
    {"key":"workforce.configuration.manage","status":"operational","authorization_mode":"enforced","is_assignable":true},
    {"key":"workforce.periods.reopen","status":"operational","authorization_mode":"enforced","is_assignable":true},
    {"key":"workforce.reports.export","status":"operational","authorization_mode":"enforced","is_assignable":true},
    {"key":"workforce.teams.manage","status":"operational","authorization_mode":"enforced","is_assignable":true},
    {"key":"workforce.timesheets.correct_during_review","status":"operational","authorization_mode":"enforced","is_assignable":true},
    {"key":"workforce.timesheets.final_approve","status":"operational","authorization_mode":"enforced","is_assignable":true},
    {"key":"workforce.timesheets.maintain","status":"operational","authorization_mode":"enforced","is_assignable":true},
    {"key":"workforce.timesheets.review","status":"operational","authorization_mode":"enforced","is_assignable":true},
    {"key":"workforce.timesheets.verify","status":"operational","authorization_mode":"enforced","is_assignable":true},
    {"key":"workforce.view","status":"operational","authorization_mode":"enforced","is_assignable":true},
    {"key":"workforce.workers.manage","status":"operational","authorization_mode":"enforced","is_assignable":true}
  ]'::jsonb,
  'T13 plus Workforce Administration preserves the exact accepted operational capability states'
);

select is(
  (
    select jsonb_agg(
      jsonb_build_object('id', id, 'public', public) order by id
    )
    from storage.buckets
    where id in ('yorks-chat-attachments', 'yorks-documents')
  ),
  '[
    {"id":"yorks-chat-attachments","public":false},
    {"id":"yorks-documents","public":false}
  ]'::jsonb,
  'Workforce collaboration reuses only the accepted private Storage buckets'
);

select is(
  (
    select array_agg(policyname || ':' || cmd order by policyname)
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname in (
        'v1_chat_attachment_insert_intent',
        'v1_chat_attachment_select_member',
        'v1_yorks_documents_insert_intent',
        'v1_yorks_documents_select_linked'
      )
  ),
  array[
    'v1_chat_attachment_insert_intent:INSERT',
    'v1_chat_attachment_select_member:SELECT',
    'v1_yorks_documents_insert_intent:INSERT',
    'v1_yorks_documents_select_linked:SELECT'
  ]::text[],
  'Storage access remains limited to linked reads and upload-intent inserts'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and cmd in ('UPDATE', 'DELETE')
      and roles && array['authenticated']::name[]
  ),
  0::bigint,
  'Authenticated clients receive no direct Storage update or delete policy'
);

select ok(
  position(
    'ifv_role=''admin''then'
    in regexp_replace(
      pg_catalog.pg_get_functiondef(
        'public.v1_workforce_t07_period_authorized(text,uuid,boolean)'
          ::regprocedure
      ), '\s', '', 'g'
    )
  ) = 0
  and position(
    'responsibility.scope_kind=''organization'''
    in regexp_replace(
      pg_catalog.pg_get_functiondef(
        'public.v1_workforce_t07_period_authorized(text,uuid,boolean)'
          ::regprocedure
      ), '\s', '', 'g'
    )
  ) > 0,
  'T13 freezes T07 without an Admin role shortcut and with dated organization authority'
);

select ok(
  position(
    'ifv_role=''admin''then'
    in regexp_replace(
      pg_catalog.pg_get_functiondef(
        'public.v1_workforce_monthly_empty_scope_authorized(text,uuid,date)'
          ::regprocedure
      ), '\s', '', 'g'
    )
  ) = 0
  and position(
    'responsibility.scope_kind=''organization'''
    in regexp_replace(
      pg_catalog.pg_get_functiondef(
        'public.v1_workforce_monthly_empty_scope_authorized(text,uuid,date)'
          ::regprocedure
      ), '\s', '', 'g'
    )
  ) > 0
  and position(
    'responsibility.scope_kindin(''organization'',''team'')'
    in regexp_replace(
      pg_catalog.pg_get_functiondef(
        'public.v1_workforce_monthly_empty_scope_authorized(text,uuid,date)'
          ::regprocedure
      ), '\s', '', 'g'
    )
  ) > 0,
  'Empty periods retain organization or exact-team responsibility without an Admin bypass'
);

select ok(
  position(
    'v_role'
    in regexp_replace(
      pg_catalog.pg_get_functiondef(
        'public.v1_workforce_t10_period_authorized(text,uuid,boolean)'
          ::regprocedure
      ), '\s', '', 'g'
    )
  ) = 0
  and position(
    'responsibility.scope_kind=''organization'''
    in regexp_replace(
      pg_catalog.pg_get_functiondef(
        'public.v1_workforce_t10_period_authorized(text,uuid,boolean)'
          ::regprocedure
      ), '\s', '', 'g'
    )
  ) > 0,
  'T10 remains role-neutral and enforces its dated organization fast path'
);

select * from finish();
rollback;
