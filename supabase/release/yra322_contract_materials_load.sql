-- YRA-322: load the Contract Materials sheets (PRODUCT_DECISIONS.md section 61).
--
-- What it does, in one transaction, through the same trusted commands the app
-- uses, acting as the Owner who imported the signed invoice INVOICE#02R.1:
--   1. In each physical building (DF3W, DF4W, DF6W, DF7W) creates a BOQ folder
--      "Contract Materials" holding the contract's 15 lines in invoice order and
--      numbering (A.1 ... A.10.1 ... A.11; B.x, C.x, D.x): Ref, Description,
--      Qty, Unit. Built from the Material Supply lines already in Accounts;
--      nothing is re-typed. No prices are written to the BOQ.
--   2. Ties each row to its contract line (v1_save_accounts_material_row_links).
--   3. Links DF3W's "VCD" folder to line A.7 Air Outlets / Inlets & Dampers on
--      Material Supply (owner decision 5).
--   4. Tidies the BOQ (owner decision 4): archives the "Test material" folders
--      and the empty duplicate "Workshop Material" folders, and renames DF4W's
--      "AC Units" folder (duct sheets and flanges) to "Ductwork Materials".
--      Archive and rename are recoverable; no row, request or document changes.
--   5. Checks the result before it commits; any surprise rolls everything back.
--
-- Re-running it changes nothing: each step first checks whether it is already
-- done, and every command uses a fixed idempotency key. It refuses to touch a
-- Contract Materials sheet, tie or folder link that someone changed by hand.
--
-- Requires supabase/release/contract_materials_bundle.sql first.
-- Before it: the read-only supabase/preflight/yra322_contract_materials_preflight.sql.
-- After it: the read-only supabase/preflight/yra322_contract_materials_verify.sql.
-- Apply by hand only with the owner's explicit yes:
--   npx supabase@latest db query --remote=<ref> --yes -f supabase/release/yra322_contract_materials_load.sql
-- Undo (corrective, recoverable): supabase/release/yra322_contract_materials_undo.sql

begin;

do $load$
declare
  c_ref constant text := 'YRA-322';
  c_sheet constant text := 'Contract Materials';
  c_reason constant text :=
    'Contract Materials sheet from the contract lines of the signed invoice '
    'YRA32202R.1 (PRODUCT_DECISIONS section 61)';
  v_project uuid;
  v_baseline uuid;
  v_actor uuid;
  v_meta jsonb;
  v_scope record;
  v_index integer := 0;
  v_letter text;
  v_group uuid;
  v_version integer;
  v_live integer;
  v_columns jsonb;
  v_rows jsonb;
  v_expected_rows jsonb;
  v_ties jsonb := '[]'::jsonb;
  v_current jsonb;
  v_resp jsonb;
  v_vcd uuid;
  v_df3w uuid;
  v_links jsonb;
  v_folder record;
  v_ac uuid;
  v_check integer;
begin
  -- 1. The project and its contract, as read on 15 November 2026.
  select id into v_project
  from public.v1_projects where project_ref = c_ref and state = 'active';
  if v_project is null then
    raise exception 'YRA322_CM: project % is missing or not active', c_ref;
  end if;
  if to_regprocedure('public.v1_save_accounts_material_row_links(uuid,jsonb,text,uuid)') is null
    or to_regprocedure('public.v1_get_accounts_material_register(uuid)') is null then
    raise exception 'YRA322_CM: apply contract_materials_bundle.sql first';
  end if;
  select cp.current_baseline_revision_id into v_baseline
  from public.v1_accounts_project_commercial_profiles cp where cp.project_id = v_project;
  select count(*) into v_check
  from public.v1_accounts_baseline_stage_items si
  join public.v1_accounts_baseline_stage_allocations sa
    on sa.baseline_revision_id = si.baseline_revision_id
   and sa.stage_key = si.stage_key and sa.measurement_mode = 'items'
  where si.baseline_revision_id = v_baseline
    and si.stage_key in ('material_supply', 'installation');
  if v_check <> 120 then
    raise exception 'YRA322_CM: expected 120 contract lines (4 buildings x 2 stages x 15), found %', v_check;
  end if;
  select count(*) into v_check
  from public.v1_project_scopes s
  where s.project_id = v_project and s.scope_kind = 'building' and s.is_active
    and (select count(*) from public.v1_accounts_baseline_stage_items si
         where si.baseline_revision_id = v_baseline and si.project_scope_id = s.id
           and si.stage_key = 'material_supply') = 15;
  if v_check <> 4 then
    raise exception 'YRA322_CM: expected 4 buildings with 15 Material Supply lines, found %', v_check;
  end if;

  -- 2. Act as the Owner who imported the signed invoice.
  select si.imported_by_auth_user_id, u.raw_app_meta_data into v_actor, v_meta
  from public.v1_accounts_source_imports si
  join auth.users u on u.id = si.imported_by_auth_user_id
  where si.project_id = v_project and si.original_file_name = 'INVOICE#02R.1.xlsx';
  if v_actor is null or v_meta ->> 'role' is distinct from 'admin' then
    raise exception 'YRA322_CM: the invoice importer is not an Admin account';
  end if;
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_actor, 'role', 'authenticated', 'app_metadata', v_meta)::text, true);
  if auth.uid() is distinct from v_actor then
    raise exception 'YRA322_CM: could not act as the Owner';
  end if;

  -- 3. One Contract Materials sheet per building, in building order.
  for v_scope in
    select s.id, s.scope_code from public.v1_project_scopes s
    where s.project_id = v_project and s.scope_kind = 'building' and s.is_active
    order by s.scope_code
  loop
    v_index := v_index + 1;
    v_letter := chr(64 + v_index);
    v_group := null;
    select g.id into v_group from public.v1_boq_groups g
    where g.scope_id = v_scope.id and not g.is_archived
      and lower(btrim(g.name)) = lower(c_sheet);
    if v_group is null then
      -- Keyed by how many sheets of this name the building already archived,
      -- so a load after an undo creates a fresh sheet instead of replaying.
      v_resp := public.v1_create_boq_group(
        jsonb_build_object('project_id', v_project, 'scope_id', v_scope.id, 'name', c_sheet),
        md5('yra322-cm|create|' || v_scope.id::text || '|' || (
          select count(*) from public.v1_boq_groups g
          where g.scope_id = v_scope.id and g.is_archived
            and lower(btrim(g.name)) = lower(c_sheet)))::uuid);
      v_group := (v_resp ->> 'id')::uuid;
    end if;
    select record_version into v_version from public.v1_boq_groups where id = v_group;

    v_columns := jsonb_build_array(
      jsonb_build_object('id', md5('yra322-cm|col|' || v_group::text || '|ref')::uuid,
        'heading', 'Ref', 'display_order', 1, 'canonical_field', null, 'is_commercial', false),
      jsonb_build_object('id', md5('yra322-cm|col|' || v_group::text || '|description')::uuid,
        'heading', 'Description', 'display_order', 2, 'canonical_field', 'description', 'is_commercial', false),
      jsonb_build_object('id', md5('yra322-cm|col|' || v_group::text || '|quantity')::uuid,
        'heading', 'Qty', 'display_order', 3, 'canonical_field', 'quantity', 'is_commercial', false),
      jsonb_build_object('id', md5('yra322-cm|col|' || v_group::text || '|unit')::uuid,
        'heading', 'Unit', 'display_order', 4, 'canonical_field', 'unit', 'is_commercial', false));

    -- The lines, numbered as the invoice numbers them: one number per line in
    -- contract order; keys "10-1" ... sit under one group number (A.10.1).
    with lines as (
      select si.item_key, si.item_label, si.display_order, si.quantity, si.unit_code,
        split_part(si.item_key, '-', 1) as grp,
        case when position('-' in si.item_key) > 0
          then split_part(si.item_key, '-', 2) end as sub
      from public.v1_accounts_baseline_stage_items si
      where si.baseline_revision_id = v_baseline and si.project_scope_id = v_scope.id
        and si.stage_key = 'material_supply'
    ), grp as (
      select l.grp, min(l.display_order) as first_order from lines l group by l.grp
    ), num as (
      select g.grp, row_number() over (order by g.first_order, g.grp) as n from grp g
    ), coded as (
      select l.*, v_letter || '.' || num.n || coalesce('.' || l.sub, '') as code,
        row_number() over (order by l.display_order, l.item_key) as ord
      from lines l join num on num.grp = l.grp
    )
    select
      jsonb_agg(jsonb_build_object(
        'id', md5('yra322-cm|row|' || v_group::text || '|' || c.item_key)::uuid,
        'display_order', c.ord,
        'raw_values', jsonb_build_object(
          md5('yra322-cm|col|' || v_group::text || '|ref')::uuid::text, c.code,
          md5('yra322-cm|col|' || v_group::text || '|description')::uuid::text, c.item_label,
          md5('yra322-cm|col|' || v_group::text || '|quantity')::uuid::text,
            rtrim(rtrim(c.quantity::text, '0'), '.'),
          md5('yra322-cm|col|' || v_group::text || '|unit')::uuid::text, c.unit_code))
        order by c.ord),
      jsonb_agg(jsonb_build_object(
        'project_scope_id', v_scope.id,
        'item_key', c.item_key,
        'boq_row_id', md5('yra322-cm|row|' || v_group::text || '|' || c.item_key)::uuid)
        order by c.ord)
    into v_rows, v_expected_rows
    from coded c;

    select count(*) into v_live from public.v1_boq_rows r
    where r.group_id = v_group and not r.is_archived;
    if v_live = 0 then
      perform public.v1_save_boq_worksheet(
        jsonb_build_object('group_id', v_group, 'expected_version', v_version,
          'worksheet_title', c_sheet, 'columns', v_columns, 'rows', v_rows,
          'reason', c_reason),
        md5('yra322-cm|save|' || v_group::text || '|' || v_version)::uuid);
    elsif v_live <> 15 or exists (
        select 1 from jsonb_array_elements(v_rows) wanted
        where not exists (
          select 1 from public.v1_boq_rows r
          where r.id = (wanted ->> 'id')::uuid and r.group_id = v_group
            and not r.is_archived
            and r.raw_values = wanted -> 'raw_values')) then
      raise exception 'YRA322_CM: % was changed by hand; nothing was written', c_sheet || ' ' || v_scope.scope_code;
    end if;
    v_ties := v_ties || v_expected_rows;
  end loop;

  -- 4. Tie every row to its contract line.
  select coalesce(jsonb_agg(jsonb_build_object('project_scope_id', project_scope_id,
      'item_key', item_key, 'boq_row_id', boq_row_id)), '[]'::jsonb)
  into v_current
  from public.v1_accounts_material_boq_row_links where project_id = v_project;
  if jsonb_array_length(v_current) = 0 then
    perform public.v1_save_accounts_material_row_links(
      v_project, v_ties, c_reason,
      -- Keyed by the payload and by how often ties were saved before, so a
      -- load after an undo writes again instead of replaying.
      md5('yra322-cm|ties|' || md5(v_ties::text) || '|' || (
        select count(*) from public.v1_audit_events a
        where a.project_id = v_project
          and a.event_type = 'accounts.material_row_links.saved'))::uuid);
  elsif not (v_current @> v_ties and v_ties @> v_current) then
    raise exception 'YRA322_CM: the project''s ties were changed by hand; nothing was written';
  end if;

  -- 5. DF3W's VCD folder stands for A.7 on Material Supply.
  select s.id into v_df3w from public.v1_project_scopes s
  where s.project_id = v_project and s.scope_code = 'a-df3w';
  select g.id into v_vcd from public.v1_boq_groups g
  where g.scope_id = v_df3w and not g.is_archived and g.name = 'VCD';
  if v_vcd is null then
    raise exception 'YRA322_CM: DF3W has no live VCD folder';
  end if;
  v_links := jsonb_build_array(jsonb_build_object('project_scope_id', v_df3w,
    'stage_key', 'material_supply', 'item_key', '7', 'boq_group_id', v_vcd));
  select coalesce(jsonb_agg(jsonb_build_object('project_scope_id', project_scope_id,
      'stage_key', stage_key, 'item_key', item_key, 'boq_group_id', boq_group_id)), '[]'::jsonb)
  into v_current
  from public.v1_accounts_material_boq_links where project_id = v_project;
  if jsonb_array_length(v_current) = 0 then
    perform public.v1_save_accounts_material_boq_links(
      v_project, v_links,
      'DF3W VCD folder counts toward A.7 Air Outlets / Inlets & Dampers (PRODUCT_DECISIONS section 61)',
      md5('yra322-cm|link|' || md5(v_links::text) || '|' || (
        select count(*) from public.v1_audit_events a
        where a.project_id = v_project
          and a.event_type = 'accounts.material_links.saved'))::uuid);
  elsif not (v_current @> v_links and v_links @> v_current) then
    raise exception 'YRA322_CM: the project''s folder links were changed by hand; nothing was written';
  end if;

  -- 6. Tidy: archive Test material and the empty duplicate Workshop Material
  -- folders. None may have a live column (nothing is shown), a Material Request
  -- source or a document; Workshop Material must also be empty.
  for v_folder in
    select g.id, g.name, g.record_version, s.scope_code
    from public.v1_boq_groups g join public.v1_project_scopes s on s.id = g.scope_id
    where g.project_id = v_project and not g.is_archived and g.is_custom
      and g.name in ('Test material', 'Workshop Material')
    order by s.scope_code, g.name
  loop
    if exists (select 1 from public.v1_boq_columns c where c.group_id = v_folder.id and not c.is_archived)
      or (v_folder.name = 'Workshop Material' and exists (
        select 1 from public.v1_boq_rows r where r.group_id = v_folder.id and not r.is_archived))
      or exists (select 1 from public.v1_material_request_lines l
        where l.source_boq_group_id = v_folder.id
           or l.source_boq_row_id in (select r.id from public.v1_boq_rows r where r.group_id = v_folder.id))
      or exists (select 1 from public.v1_document_links dl
        where dl.entity_type = 'boq_group' and dl.entity_id = v_folder.id and dl.removed_at is null) then
      raise exception 'YRA322_CM: % in % is in use; nothing was written', v_folder.name, v_folder.scope_code;
    end if;
    perform public.v1_archive_boq_group(
      jsonb_build_object('group_id', v_folder.id, 'expected_version', v_folder.record_version,
        'reason', 'BOQ tidy for the Contract Materials sheets: ' || v_folder.name
          || ' folder archived, recoverable (PRODUCT_DECISIONS section 61)'),
      md5('yra322-cm|archive|' || v_folder.id::text || '|' || v_folder.record_version)::uuid);
  end loop;

  -- DF4W's "AC Units" holds duct sheets and flanges: rename it.
  select g.id, g.record_version into v_ac, v_version
  from public.v1_boq_groups g join public.v1_project_scopes s on s.id = g.scope_id
  where g.project_id = v_project and s.scope_code = 'b-df4w' and not g.is_archived
    and g.name = 'AC Units';
  if v_ac is not null then
    perform public.v1_rename_boq_group(
      jsonb_build_object('group_id', v_ac, 'expected_version', v_version,
        'name', 'Ductwork Materials',
        'reason', 'It holds duct sheets, angles and flanges, not AC units (PRODUCT_DECISIONS section 61)'),
      md5('yra322-cm|rename|' || v_ac::text || '|' || v_version)::uuid);
  end if;

  -- 7. Check the result before committing.
  select count(*) into v_check
  from public.v1_boq_groups g join public.v1_project_scopes s on s.id = g.scope_id
  where g.project_id = v_project and s.scope_kind = 'building' and not g.is_archived
    and g.name = c_sheet
    and (select count(*) from public.v1_boq_rows r where r.group_id = g.id and not r.is_archived) = 15;
  if v_check <> 4 then
    raise exception 'YRA322_CM check: % Contract Materials sheets with 15 lines, expected 4', v_check;
  end if;
  select count(*) into v_check
  from public.v1_accounts_material_boq_row_links rl
  join public.v1_boq_rows r on r.id = rl.boq_row_id and not r.is_archived
  join public.v1_boq_groups g on g.id = r.group_id and g.name = c_sheet and not g.is_archived
  where rl.project_id = v_project;
  if v_check <> 60 then
    raise exception 'YRA322_CM check: % ties, expected 60', v_check;
  end if;
  if (select count(*) from public.v1_accounts_material_boq_links where project_id = v_project) <> 1 then
    raise exception 'YRA322_CM check: expected the one VCD folder link';
  end if;
  if exists (select 1 from public.v1_boq_groups g where g.project_id = v_project
      and not g.is_archived and g.is_custom and g.name in ('Test material', 'Workshop Material'))
    or not exists (select 1 from public.v1_boq_groups g join public.v1_project_scopes s on s.id = g.scope_id
      where g.project_id = v_project and s.scope_code = 'b-df4w' and not g.is_archived
        and g.name = 'Ductwork Materials') then
    raise exception 'YRA322_CM check: the tidy-up did not land';
  end if;
  select count(*) into v_check
  from jsonb_array_elements(public.v1_get_accounts_material_register(v_project) -> 'buildings') b,
    jsonb_array_elements(b -> 'lines') l
  where l ->> 'boq_row_id' is not null;
  if v_check <> 60 then
    raise exception 'YRA322_CM check: Accounts shows % tied lines, expected 60', v_check;
  end if;

  raise notice 'YRA322_CM: 4 Contract Materials sheets, 60 ties, VCD linked to A.7, BOQ tidied';
end;
$load$;

commit;
