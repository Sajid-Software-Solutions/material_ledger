-- Read-only preflight for supabase/release/production_function_alignment_bundle.sql
-- (docs/yorks-v1/PRODUCTION_FUNCTION_DRIFT_2026-11-15.md). Changes nothing and
-- reads only catalogs; returns one JSON row with no personal data.
--   npx supabase@latest db query --remote=<ref> --read-only -f supabase/preflight/production_function_alignment_preflight.sql
--
-- Apply the bundle only when ready_to_apply is true: each function is either
-- production's of 15 Nov 2026 ("production_20261115") or main's ("main") and
-- every dependency exists. After the bundle, already_applied is true. A value
-- "unknown" means someone changed that function since 15 Nov: stop and compare
-- again before applying.

with expected(signature, production_fingerprint, main_fingerprint) as (
  values
    ('v1_material_search_normalize(text)', null, '351a0430756a5e2cb730ac22091901ee'),
    ('v1_material_search_synonyms(text)', null, '664152d721f94a1fcaeda2216f92462f'),
    ('v1_material_search_one_edit(text,text)', null, 'da4e7a95947adcd0d7af32e6b790bf83'),
    ('v1_search_material_request_candidates(uuid,uuid,text,integer)', 'c64083a914330a7aa5c353dae5af6963', '1f177e9087dee103fd7eb74b97649b58'),
    ('v1_search_company_material_request_candidates(uuid,uuid,text,integer)', '23c23e4227f368f14e4856d90e7c2aa0', '9d0e9f3888b285cd9bffa2f797de5780'),
    ('v1_material_request_overview(integer)', '5c6b96e54bcc884e19b8381816e7df8f', '83e9d3c1227b0baa191b966d8b8b95c5'),
    ('v1_material_request_submission_diagnostic(uuid,uuid,uuid)', null, 'd4c4af385dd1ac080362dc15a04779ba'),
    ('v1_can_confirm_material_return(uuid)', 'f22a335dcb7a7143cd4da6f16174866a', '99b6cbc8dcec9fb5272703afb5692b38'),
    ('app_role()', '0bc9a3e2215721f357a3333f6cc66b83', 'fe73549c0b069d7287eefe83082cc20d'),
    ('app_user_id()', 'f3d905b9020548149ccfeadca7d1e2fe', 'e27089640fe1db6cd8203b747aa6e387'),
    ('notification_visible_to_caller(jsonb)', '937c030c5fe6e9288c67816938ab9f40', 'f5f29d8967430dd7aff95c03b079659d'),
    ('app_legacy_project_readable(jsonb)', null, '868de3343460e5f23dd2b6fb91cacb97'),
    ('app_legacy_project_writable(jsonb)', null, '2f9886f3dc5d8e9569ac11b1c983582e'),
    ('app_legacy_plan_readable(jsonb)', null, '4c419e9288ed298eea5958a05c222fd5'),
    ('app_legacy_plan_writable(jsonb)', null, '1bfe72c4ef608cfd9601b7a5cca8206d'),
    ('project_progress_definitions(jsonb)', '839096d402ff865fd30f88c536d2c34f', '2669c15d30544e6d11170d8eb9abe73f'),
    ('project_require_approved_phase1()', '5728a75dc73870bc046a28629f02ca75', '84228975d49436cb8d8b677d6749f2e4'),
    ('v1_create_document_version(uuid,text,bigint,text)', '33c32837d5a32331c9cca1a1cdea4a8d', '468a0043e2754c640ddf4af5bea0e6c6'),
    ('v1_import_boq_worksheet(jsonb,uuid)', '181ada5a87b31b7a6aab12421f652df6', '6578655c386d24a1c22a84b3dfdeb173'),
    ('app_has_cap(text)', '52a353bc83eefc45e5ac91afb93a7acb', '52a353bc83eefc45e5ac91afb93a7acb'),
    ('app_touch_updated_at()', '76377695287d53f3bc550b0b8beb0a9c', '76377695287d53f3bc550b0b8beb0a9c')
), main_execute(signature, anon, authenticated, service_role) as (
  values
    ('v1_material_search_normalize(text)', false, false, true),
    ('v1_material_search_synonyms(text)', false, false, true),
    ('v1_material_search_one_edit(text,text)', false, false, true),
    ('v1_search_material_request_candidates(uuid,uuid,text,integer)', false, true, true),
    ('v1_search_company_material_request_candidates(uuid,uuid,text,integer)', false, true, true),
    ('v1_material_request_overview(integer)', false, true, true),
    ('v1_material_request_submission_diagnostic(uuid,uuid,uuid)', false, true, true),
    ('v1_can_confirm_material_return(uuid)', false, false, true),
    ('app_role()', false, true, true),
    ('app_user_id()', false, true, true),
    ('notification_visible_to_caller(jsonb)', false, true, true),
    ('app_legacy_project_readable(jsonb)', false, true, true),
    ('app_legacy_project_writable(jsonb)', false, true, true),
    ('app_legacy_plan_readable(jsonb)', false, true, true),
    ('app_legacy_plan_writable(jsonb)', false, true, true),
    ('project_progress_definitions(jsonb)', false, true, true),
    ('project_require_approved_phase1()', false, false, true),
    ('v1_create_document_version(uuid,text,bigint,text)', false, false, true),
    ('v1_import_boq_worksheet(jsonb,uuid)', false, true, true),
    ('app_has_cap(text)', false, true, true),
    ('app_touch_updated_at()', false, false, true)
), current_state as (
  select expected.*,
    to_regprocedure('public.' || expected.signature) as procedure,
    (
      select md5(p.prosrc || coalesce(p.proconfig::text, '') || p.provolatile::text || p.prosecdef::text)
      from pg_catalog.pg_proc p
      where p.oid = to_regprocedure('public.' || expected.signature)
    ) as fingerprint
  from expected
), labelled as (
  select current_state.*,
    case
      when fingerprint = main_fingerprint
        and fingerprint is not distinct from production_fingerprint
        then 'same_in_both'
      when fingerprint = main_fingerprint then 'main'
      when fingerprint is not distinct from production_fingerprint
        then 'production_20261115'
      when fingerprint is null then 'missing'
      else 'unknown'
    end as state,
    procedure is not null and (
      has_function_privilege('anon', procedure, 'execute')
        is distinct from main_execute.anon
      or has_function_privilege('authenticated', procedure, 'execute')
        is distinct from main_execute.authenticated
      or has_function_privilege('service_role', procedure, 'execute')
        is distinct from main_execute.service_role
      or exists (
        select 1
        from pg_catalog.pg_proc p,
          aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) grant_row
        where p.oid = procedure and grant_row.grantee = 0
      )
    ) as execute_differs_from_main
  from current_state
  join main_execute using (signature)
), missing_dependencies as (
  select dependency.name
  from unnest(array[
    'v1_assert_object_keys', 'v1_boq_group_projection',
    'v1_can_create_material_request', 'v1_can_edit_boq_project',
    'v1_can_edit_material_request_before_approval',
    'v1_can_manage_inventory',
    'v1_company_material_request_active_authorization',
    'v1_complete_idempotency', 'v1_current_actor_is_active',
    'v1_current_exact_role', 'v1_current_role',
    'v1_current_user_has_capability', 'v1_has_capability',
    'v1_idempotency_get_or_claim', 'v1_material_register_permission_map',
    'v1_material_request_published_policy_boolean',
    'v1_material_request_readable', 'v1_project_readable',
    'v1_required_boq_commercial_canonical', 'v1_save_boq_worksheet',
    'v1_write_audit_event'
  ]) as dependency(name)
  where not exists (
    select 1 from pg_catalog.pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.proname = dependency.name
  )
  union all
  select dependency.name
  from unnest(array[
    'phase1_plans', 'projects', 'v1_audit_events', 'v1_boq_columns',
    'v1_boq_groups', 'v1_boq_rows',
    'v1_company_material_request_categories',
    'v1_company_material_request_units', 'v1_document_links',
    'v1_document_upload_intents', 'v1_document_versions', 'v1_documents',
    'v1_idempotency_keys', 'v1_inventory_items',
    'v1_material_request_lines',
    'v1_material_request_private_draft_retirements',
    'v1_material_requests', 'v1_permission_revisions',
    'v1_procurement_arrangements', 'v1_profiles', 'v1_project_members',
    'v1_project_scopes', 'v1_projects'
  ]) as dependency(name)
  where to_regclass('public.' || quote_ident(dependency.name)) is null
)
select jsonb_build_object(
  'ready_to_apply',
    bool_and(state in ('production_20261115', 'main', 'same_in_both'))
    and not exists (select 1 from missing_dependencies),
  'already_applied',
    bool_and(state in ('main', 'same_in_both') and not execute_differs_from_main),
  'functions', jsonb_object_agg(signature, state),
  'execute_differs_from_main', coalesce(
    jsonb_agg(signature order by signature) filter (where execute_differs_from_main),
    '[]'::jsonb),
  'missing_dependencies', (
    select coalesce(jsonb_agg(name order by name), '[]'::jsonb)
    from missing_dependencies)
) as preflight
from labelled;
