-- Read-only preflight for supabase/release/yra322_contract_materials_load.sql
-- (PRODUCT_DECISIONS.md section 61). Changes nothing; returns one JSON row
-- with counts and folder names only (no personal data).
--   npx supabase@latest db query --remote=<ref> --read-only -f supabase/preflight/yra322_contract_materials_preflight.sql
--
-- Proceed when ready is true. already_loaded true means a re-run, which
-- changes nothing.

with p as (
  select id, state from public.v1_projects where project_ref = 'YRA-322'
), base as (
  select cp.current_baseline_revision_id as id
  from public.v1_accounts_project_commercial_profiles cp join p on p.id = cp.project_id
), facts as (
  select
    (select state from p) as project_state,
    to_regprocedure('public.v1_save_accounts_material_row_links(uuid,jsonb,text,uuid)') is not null
      and to_regprocedure('public.v1_get_accounts_material_register(uuid)') is not null as bundle_applied,
    (select count(*) from public.v1_accounts_baseline_stage_items si
      join public.v1_accounts_baseline_stage_allocations sa
        on sa.baseline_revision_id = si.baseline_revision_id and sa.stage_key = si.stage_key
       and sa.measurement_mode = 'items'
      join base on base.id = si.baseline_revision_id
      where si.stage_key in ('material_supply', 'installation')) as contract_lines,
    (select count(*) from public.v1_project_scopes s join p on p.id = s.project_id
      where s.scope_kind = 'building' and s.is_active
        and (select count(*) from public.v1_accounts_baseline_stage_items si join base on base.id = si.baseline_revision_id
             where si.project_scope_id = s.id and si.stage_key = 'material_supply') = 15) as buildings_with_15_lines,
    (select u.raw_app_meta_data ->> 'role' = 'admin' and pr.is_active
      from public.v1_accounts_source_imports si join p on p.id = si.project_id
      join auth.users u on u.id = si.imported_by_auth_user_id
      join public.v1_profiles pr on pr.auth_user_id = u.id
      where si.original_file_name = 'INVOICE#02R.1.xlsx') as owner_ready,
    (select count(*) from public.v1_boq_groups g join p on p.id = g.project_id
      where not g.is_archived and g.name = 'Contract Materials') as contract_sheets,
    (select count(*) from public.v1_boq_groups g join p on p.id = g.project_id
      join public.v1_project_scopes s on s.id = g.scope_id
      where not g.is_archived and g.name = 'VCD' and s.scope_code = 'a-df3w') as df3w_vcd,
    (select count(*) from public.v1_boq_groups g join p on p.id = g.project_id
      join public.v1_project_scopes s on s.id = g.scope_id
      where not g.is_archived and s.scope_code = 'b-df4w'
        and g.name in ('AC Units', 'Ductwork Materials')) as df4w_duct_folder,
    (select count(*) from public.v1_boq_groups g join p on p.id = g.project_id
      where not g.is_archived and g.is_custom and g.name in ('Test material', 'Workshop Material')) as to_archive,
    (select count(*) from public.v1_boq_groups g join p on p.id = g.project_id
      where not g.is_archived and g.is_custom and g.name in ('Test material', 'Workshop Material')
        and (exists (select 1 from public.v1_boq_columns c where c.group_id = g.id and not c.is_archived)
          or (g.name = 'Workshop Material' and exists (select 1 from public.v1_boq_rows r where r.group_id = g.id and not r.is_archived))
          or exists (select 1 from public.v1_material_request_lines l where l.source_boq_group_id = g.id
            or l.source_boq_row_id in (select r.id from public.v1_boq_rows r where r.group_id = g.id))
          or exists (select 1 from public.v1_document_links dl where dl.entity_type = 'boq_group'
            and dl.entity_id = g.id and dl.removed_at is null))) as to_archive_in_use,
    (select count(*) from public.v1_accounts_material_boq_links l join p on p.id = l.project_id) as folder_links,
    -- Counted through a query string, so this preflight also runs before the
    -- bundle has created the table (a plain reference fails at parse time).
    case when to_regclass('public.v1_accounts_material_boq_row_links') is null then null
      else (xpath('/row/n/text()', query_to_xml(
        'select count(*) as n from public.v1_accounts_material_boq_row_links l '
        || 'join public.v1_projects p on p.id = l.project_id '
        || 'where p.project_ref = ''YRA-322''', false, true, '')))[1]::text::bigint
      end as ties
)
select jsonb_build_object(
  'ready', f.project_state = 'active' and f.bundle_applied and f.contract_lines = 120
    and f.buildings_with_15_lines = 4 and coalesce(f.owner_ready, false)
    and f.df3w_vcd = 1 and f.df4w_duct_folder = 1 and f.to_archive_in_use = 0
    and ((f.contract_sheets = 0 and coalesce(f.ties, 0) = 0 and f.folder_links = 0)
      or (f.contract_sheets = 4 and f.ties = 60 and f.folder_links = 1)),
  'already_loaded', f.contract_sheets = 4 and f.ties = 60 and f.folder_links = 1,
  'facts', to_jsonb(f)
) as preflight
from facts f;
