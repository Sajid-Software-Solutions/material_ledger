-- Read-only preflight for supabase/release/contract_materials_bundle.sql
-- (PRODUCT_DECISIONS.md section 61). Changes nothing; returns one JSON row with
-- no personal data (counts and fingerprints only).
--   npx supabase@latest db query --remote=<ref> --read-only -f supabase/preflight/contract_materials_preflight.sql
--
-- Proceed when both *_matches_20261107160000 values are true (or the bundle
-- was already applied: bundle_applied true and both *_has_row_ties true).

select jsonb_build_object(
  'bundle_applied',
    to_regclass('public.v1_accounts_material_boq_row_links') is not null
    and to_regprocedure('public.v1_get_accounts_material_register(uuid)') is not null,
  'sources_matches_20261107160000',
    md5((select prosrc from pg_proc
      where oid = 'public.v1_get_accounts_material_sources(uuid)'::regprocedure))
      = '4af579d13cd9366f84f49ef9adff4598',
  'save_links_matches_20261107160000',
    md5((select prosrc from pg_proc
      where oid = 'public.v1_save_accounts_material_boq_links(uuid,jsonb,text,uuid)'::regprocedure))
      = '89d731f60c13bf713dd4ab64bf9a368d',
  'sources_has_row_ties',
    position('v1_accounts_material_boq_row_links' in pg_get_functiondef(
      'public.v1_get_accounts_material_sources(uuid)'::regprocedure)) > 0,
  'save_links_has_row_ties',
    position('v1_accounts_material_boq_row_links' in pg_get_functiondef(
      'public.v1_save_accounts_material_boq_links(uuid,jsonb,text,uuid)'::regprocedure)) > 0,
  'helpers_present', jsonb_build_object(
    'stage_item_value', to_regprocedure('public.v1_accounts_stage_item_value(uuid)') is not null,
    'item_qty_at', to_regprocedure('public.v1_accounts_item_qty_at(uuid,uuid,text,text,timestamp with time zone)') is not null,
    'stage_value', to_regprocedure('public.v1_accounts_stage_value(uuid)') is not null,
    'eligible_amount', to_regprocedure('public.v1_accounts_progress_eligible_amount(uuid)') is not null,
    'unit_key', to_regprocedure('public.v1_accounts_unit_key(text)') is not null,
    'boq_number', to_regprocedure('public.v1_accounts_boq_number(text)') is not null),
  'return_lines_have_basis_kind', exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'v1_material_return_lines'
      and column_name = 'basis_kind'),
  'folder_links', (select count(*) from public.v1_accounts_material_boq_links),
  'projects_with_item_stages', (
    select count(distinct sa.project_id)
    from public.v1_accounts_baseline_stage_allocations sa
    join public.v1_accounts_project_commercial_profiles cp
      on cp.current_baseline_revision_id = sa.baseline_revision_id
    where sa.measurement_mode = 'items')
) as preflight;
