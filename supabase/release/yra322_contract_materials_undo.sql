-- YRA-322: undo the Contract Materials load (PRODUCT_DECISIONS.md section 61).
--
-- Corrective and recoverable, never a delete. In one transaction, as the same
-- Owner, through the app's own commands:
--   1. clears the project's row ties and folder links (both commands replace
--      the set; audit keeps what was there);
--   2. archives the four Contract Materials sheets (their rows stay, and
--      Restore brings them back);
--   3. restores the Test material and Workshop Material folders the load
--      archived, and renames DF4W's "Ductwork Materials" back to "AC Units".
-- Use only with the owner's explicit yes:
--   npx supabase@latest db query --remote=<ref> --yes -f supabase/release/yra322_contract_materials_undo.sql

begin;

do $undo$
declare
  c_reason constant text := 'Undo of the Contract Materials load (PRODUCT_DECISIONS section 61)';
  v_project uuid;
  v_actor uuid;
  v_meta jsonb;
  v_folder record;
begin
  select id into v_project from public.v1_projects where project_ref = 'YRA-322';
  select si.imported_by_auth_user_id, u.raw_app_meta_data into v_actor, v_meta
  from public.v1_accounts_source_imports si
  join auth.users u on u.id = si.imported_by_auth_user_id
  where si.project_id = v_project and si.original_file_name = 'INVOICE#02R.1.xlsx';
  if v_project is null or v_actor is null or v_meta ->> 'role' is distinct from 'admin' then
    raise exception 'YRA322_CM undo: project or Owner not found';
  end if;
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_actor, 'role', 'authenticated', 'app_metadata', v_meta)::text, true);

  perform public.v1_save_accounts_material_row_links(
    v_project, '[]'::jsonb, c_reason, gen_random_uuid());
  perform public.v1_save_accounts_material_boq_links(
    v_project, '[]'::jsonb, c_reason, gen_random_uuid());

  for v_folder in
    select g.id, g.record_version from public.v1_boq_groups g
    where g.project_id = v_project and not g.is_archived and g.name = 'Contract Materials'
  loop
    perform public.v1_archive_boq_group(jsonb_build_object('group_id', v_folder.id,
      'expected_version', v_folder.record_version, 'reason', c_reason), gen_random_uuid());
  end loop;

  -- Only the folders the load archived (its audit events name them).
  for v_folder in
    select g.id, g.record_version from public.v1_boq_groups g
    where g.project_id = v_project and g.is_archived and g.is_custom
      and g.name in ('Test material', 'Workshop Material')
      and exists (select 1 from public.v1_audit_events a
        where a.entity_id = g.id and a.event_type = 'boq_group_archived'
          and a.reason like 'BOQ tidy for the Contract Materials sheets:%')
  loop
    perform public.v1_restore_boq_group(jsonb_build_object('group_id', v_folder.id,
      'expected_version', v_folder.record_version, 'reason', c_reason), gen_random_uuid());
  end loop;

  for v_folder in
    select g.id, g.record_version from public.v1_boq_groups g
    join public.v1_project_scopes s on s.id = g.scope_id
    where g.project_id = v_project and s.scope_code = 'b-df4w' and not g.is_archived
      and g.name = 'Ductwork Materials'
  loop
    perform public.v1_rename_boq_group(jsonb_build_object('group_id', v_folder.id,
      'expected_version', v_folder.record_version, 'name', 'AC Units', 'reason', c_reason),
      gen_random_uuid());
  end loop;
end;
$undo$;

commit;
