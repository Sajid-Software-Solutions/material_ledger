-- Read-only check after supabase/release/yra322_contract_materials_load.sql
-- (PRODUCT_DECISIONS.md section 61). Changes nothing.
--   npx supabase@latest db query --remote=<ref> --read-only -f supabase/preflight/yra322_contract_materials_verify.sql

with p as (select id from public.v1_projects where project_ref = 'YRA-322')
select jsonb_build_object(
  'sheets', (
    select jsonb_agg(jsonb_build_object(
      'building', s.scope_code,
      'lines', (select count(*) from public.v1_boq_rows r where r.group_id = g.id and not r.is_archived),
      'tied', (select count(*) from public.v1_accounts_material_boq_row_links rl
        join public.v1_boq_rows r on r.id = rl.boq_row_id and not r.is_archived where r.group_id = g.id),
      'columns', (select jsonb_agg(c.heading order by c.display_order) from public.v1_boq_columns c
        where c.group_id = g.id and not c.is_archived),
      'refs', (select jsonb_agg(r.raw_values ->> (select c.id::text from public.v1_boq_columns c
          where c.group_id = g.id and not c.is_archived and c.heading = 'Ref') order by r.display_order)
        from public.v1_boq_rows r where r.group_id = g.id and not r.is_archived),
      'commercial_values', (select count(*) from public.v1_boq_rows r
        where r.group_id = g.id and r.commercial_values <> '{}'::jsonb))
      order by s.scope_code)
    from public.v1_boq_groups g join p on p.id = g.project_id
    join public.v1_project_scopes s on s.id = g.scope_id
    where not g.is_archived and g.name = 'Contract Materials'),
  'ties', (select count(*) from public.v1_accounts_material_boq_row_links l join p on p.id = l.project_id),
  'vcd_link', (select jsonb_agg(jsonb_build_object('stage', l.stage_key, 'item', l.item_key, 'folder', g.name))
    from public.v1_accounts_material_boq_links l join p on p.id = l.project_id
    join public.v1_boq_groups g on g.id = l.boq_group_id),
  'archived_today', (select jsonb_agg(s.scope_code || ' · ' || g.name order by s.scope_code, g.name)
    from public.v1_boq_groups g join p on p.id = g.project_id
    join public.v1_project_scopes s on s.id = g.scope_id
    where g.is_archived and g.archived_at > now() - interval '7 days'),
  'df4w_folders', (select jsonb_agg(g.name order by g.name) from public.v1_boq_groups g join p on p.id = g.project_id
    join public.v1_project_scopes s on s.id = g.scope_id
    where s.scope_code = 'b-df4w' and not g.is_archived and g.name in ('AC Units', 'Ductwork Materials')),
  'audit', (select jsonb_object_agg(event_type, n) from (
    select a.event_type, count(*) as n from public.v1_audit_events a join p on p.id = a.project_id
    where a.occurred_at > now() - interval '1 day'
      and a.event_type in ('boq_group_created', 'boq_worksheet_saved', 'boq_group_archived',
        'boq_group_renamed', 'accounts.material_row_links.saved', 'accounts.material_links.saved')
    group by a.event_type) x)
) as verify;
