-- Configuration redesign (PRODUCT_DECISIONS.md section 39,
-- docs/yorks-v1/CONFIGURATION_REDESIGN_PLAN.md).
--
-- One workspace read and one save command for every Configuration section.
-- A save applies a section's changes with a reason in one transaction and is
-- recorded as an ordinary configuration publication (before -> after for
-- every change), so the existing history, audit and runtime readers keep
-- working. A stale save (someone published meanwhile) is refused.
--
--   company        company.* letterhead, contact and bank; support contact
--   requests       material request policies; Company MR categories and
--                  departments
--   inventory      external-source readiness; inventory categories; units
--   projects       default BOQ folders a new building or Common scope gets
--   accounts       default payment policy and billing stages (new baselines)
--   notifications  push notifications on/off
--   rentals        rental reminders and their push (Admin and PR)
--
-- Admin edits every section; PR edits Rentals (Workforce keeps its own
-- commands, which PR already uses). Changes affect future records only:
-- issued invoices, Delivery Orders and reports keep their frozen copies,
-- existing BOQ folders and project baselines are never touched.
--
-- Also fixed: v1_get_runtime_configuration refused the PR role.
--
-- Data preservation: additive. Company contact and bank settings, which
-- invoices already print, are reclassified as operational; nothing is
-- deleted. Settings with no effect stay in the table and are no longer
-- shown. Rollback: revoke the two new functions and restore the previous
-- control_mode values listed below; publications stay.

begin;

-- ---------------------------------------------------------------------------
-- 1. What is live.
-- ---------------------------------------------------------------------------

-- Invoices and workforce reports print these; they are real settings.
update public.v1_configuration_settings
set control_mode = 'operational',
    impact_scope = array['accounts', 'documents_printing']::text[],
    enforcement_target = 'document_letterhead'
where setting_key in (
  'company.legal_name', 'company.short_name', 'company.arabic_name',
  'company.address', 'company.phone', 'company.fax', 'company.email',
  'company.trn', 'company.bank_name', 'company.bank_account_name',
  'company.bank_iban'
)
  and control_mode <> 'operational';

-- PR publishes the Rentals section (strict superset of the old check).
alter table public.v1_configuration_publications
  drop constraint if exists v1_configuration_publications_published_by_exact_role_check;
alter table public.v1_configuration_publications
  add constraint v1_configuration_publications_published_by_exact_role_check
  check (published_by_exact_role in ('admin', 'pr', 'system'));

-- PR may read the runtime configuration like every other signed-in role.
do $runtime$
declare
  v_definition text := pg_get_functiondef(
    'public.v1_get_runtime_configuration()'::regprocedure
  );
  v_updated text;
begin
  if position('''document_controller'', ''pr''' in v_definition) > 0 then
    return;
  end if;
  v_updated := replace(
    v_definition,
    '''workshop_in_charge'', ''document_controller''',
    '''workshop_in_charge'', ''document_controller'', ''pr'''
  );
  if v_updated = v_definition then
    raise exception 'V1_CFG_RUNTIME_ANCHOR_MISSING';
  end if;
  execute v_updated;
end;
$runtime$;

-- ---------------------------------------------------------------------------
-- 2. Access.
-- ---------------------------------------------------------------------------

create or replace function public.v1_cfg_section_editable(p_section text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text := public.v1_current_exact_role();
begin
  if auth.uid() is null or not public.v1_current_actor_is_active() then
    return false;
  end if;
  if v_role = 'admin' then
    return coalesce(
      public.v1_current_user_has_capability('configuration.publish', null),
      false
    );
  end if;
  if v_role = 'pr' and p_section in ('rentals', 'workforce') then
    return true;
  end if;
  return false;
end;
$$;

create or replace function public.v1_cfg_slug(p_text text)
returns text
language sql
immutable
set search_path = ''
as $$
  select left(
    trim(both '_' from regexp_replace(
      lower(coalesce(p_text, '')), '[^a-z0-9]+', '_', 'g'
    )),
    40
  );
$$;

-- ---------------------------------------------------------------------------
-- 3. The workspace.
-- ---------------------------------------------------------------------------

create or replace function public.v1_cfg_get_workspace()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text := public.v1_current_exact_role();
  v_admin boolean;
  v_today date := (clock_timestamp() at time zone 'Asia/Dubai')::date;
  v_settings jsonb;
begin
  if auth.uid() is null or not public.v1_current_actor_is_active()
    or v_role not in ('admin', 'pr') then
    raise exception 'V1_CONFIGURATION_ACCESS_DENIED' using errcode = '42501';
  end if;
  v_admin := v_role = 'admin';

  select coalesce(jsonb_object_agg(setting.setting_key, jsonb_build_object(
    'value', setting.published_value,
    'default', setting.default_value,
    'type', setting.value_type,
    'mode', setting.control_mode
  )), '{}'::jsonb)
  into v_settings
  from public.v1_configuration_settings setting;

  return jsonb_build_object(
    'schema_version', 'yorks.configuration.workspace.v1',
    'version', coalesce((
      select max(publication.version_number)
      from public.v1_configuration_publications publication
    ), 0),
    'today', v_today,
    'editable', jsonb_build_object(
      'company', public.v1_cfg_section_editable('company'),
      'requests', public.v1_cfg_section_editable('requests'),
      'inventory', public.v1_cfg_section_editable('inventory'),
      'projects', public.v1_cfg_section_editable('projects'),
      'accounts', public.v1_cfg_section_editable('accounts'),
      'notifications', public.v1_cfg_section_editable('notifications'),
      'rentals', public.v1_cfg_section_editable('rentals'),
      'workforce', public.v1_cfg_section_editable('workforce')
    ),
    'settings', case when v_admin then v_settings else '{}'::jsonb end,
    'boq_templates', case when v_admin then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', template.id,
        'key', template.template_key,
        'name', template.display_name,
        'order', template.display_order,
        'active', template.is_active,
        'scopes', (
          select count(*) from public.v1_boq_groups boq_group
          where boq_group.template_id = template.id
        )
      ) order by template.display_order, template.display_name)
      from public.v1_boq_group_templates template
    ), '[]'::jsonb) else '[]'::jsonb end,
    'inventory_categories', case when v_admin then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', category.id,
        'name', category.name,
        'parent_id', category.parent_category_id,
        'system', category.is_system,
        'active', category.is_active,
        'aliases', coalesce((
          select jsonb_agg(alias.alias_name order by alias.alias_name)
          from public.v1_inventory_category_aliases alias
          where alias.category_id = category.id
        ), '[]'::jsonb)
      ) order by lower(category.name))
      from public.v1_inventory_categories category
    ), '[]'::jsonb) else '[]'::jsonb end,
    'units', case when v_admin then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', unit.id,
        'name', unit.name,
        'code', unit.short_code,
        'type', unit.unit_type,
        'decimals', unit.decimal_places,
        'system', unit.is_system,
        'active', unit.is_active
      ) order by lower(unit.name))
      from public.v1_configuration_units unit
    ), '[]'::jsonb) else '[]'::jsonb end,
    'mr_categories', case when v_admin then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', category.id, 'code', category.category_code,
        'name', category.display_name, 'active', category.is_active
      ) order by lower(category.display_name))
      from public.v1_company_material_request_categories category
    ), '[]'::jsonb) else '[]'::jsonb end,
    'mr_departments', case when v_admin then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', unit.id, 'code', unit.unit_code,
        'name', unit.display_name, 'active', unit.is_active
      ) order by lower(unit.display_name))
      from public.v1_company_material_request_units unit
    ), '[]'::jsonb) else '[]'::jsonb end,
    'accounts', case when v_admin then jsonb_build_object(
      'payment_terms_days', (
        select settings.default_payment_terms_days
        from public.v1_accounts_foundation_settings settings
        where settings.singleton
      ),
      'reminder_lead_days', (
        select settings.default_reminder_lead_days
        from public.v1_accounts_foundation_settings settings
        where settings.singleton
      ),
      'stages', coalesce((
        select jsonb_agg(jsonb_build_object(
          'key', stage.stage_key,
          'name', stage.stage_name,
          'percent', stage.allocation_percent::text,
          'order', stage.display_order,
          'active', stage.is_active
        ) order by stage.display_order)
        from public.v1_accounts_billing_stage_templates stage
      ), '[]'::jsonb)
    ) else null end,
    'rentals', (
      select jsonb_build_object(
        'enabled', control.enabled,
        'push', control.external_push_enabled,
        'last_run_at', control.last_success_at
      )
      from public.v1_rental_notification_control control
      where control.id
    ),
    -- What still needs attention, for the setup checklist.
    'checks', jsonb_build_object(
      'bank_missing', v_admin and (
        coalesce(v_settings #>> '{company.bank_iban,value}', '') = ''
        or coalesce(v_settings #>> '{company.bank_name,value}', '') = ''
      ),
      'trn_missing', v_admin
        and coalesce(v_settings #>> '{company.trn,value}', '') = '',
      'push_off', v_admin
        and coalesce(v_settings #>> '{notifications.push_enabled,value}', 'true')
          = 'false',
      'holidays_this_year', (
        select count(*) from public.v1_workforce_public_holidays holiday
        where extract(year from holiday.holiday_date) = extract(year from v_today)
      ),
      'active_pr_users', (
        select count(*) from public.v1_profiles profile
        where profile.is_active
          and public.v1_permission_exact_role(profile.auth_user_id) = 'pr'
      ),
      'default_folders', (
        select count(*) from public.v1_boq_group_templates template
        where template.is_active
      ),
      'rentals_off', not coalesce((
        select control.enabled from public.v1_rental_notification_control control
        where control.id
      ), false)
    )
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Saving a section.
-- ---------------------------------------------------------------------------

-- Company text: names and contact lines are trimmed, bounded and plain;
-- the IBAN, TRN and email have their own shapes (empty is allowed).
create or replace function public.v1_cfg_validate_company_value(
  p_key text,
  p_value jsonb
)
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_text text;
begin
  if p_value is null or jsonb_typeof(p_value) <> 'string' then
    raise exception 'V1_CONFIGURATION_STRING_REQUIRED' using errcode = '22023';
  end if;
  v_text := btrim(p_value #>> '{}');
  if v_text <> (p_value #>> '{}') or char_length(v_text) > 300
    or v_text ~ '[[:cntrl:]]' then
    raise exception 'V1_CFG_TEXT_INVALID' using errcode = '22023',
      detail = p_key;
  end if;
  if p_key in ('company.legal_name', 'company.short_name')
    and v_text = '' then
    raise exception 'V1_CFG_TEXT_REQUIRED' using errcode = '22023',
      detail = p_key;
  end if;
  if p_key = 'company.bank_iban' and v_text <> ''
    and replace(upper(v_text), ' ', '') !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$' then
    raise exception 'V1_CFG_IBAN_INVALID' using errcode = '22023';
  end if;
  if p_key = 'company.trn' and v_text <> '' and v_text !~ '^[0-9]{15}$' then
    raise exception 'V1_CFG_TRN_INVALID' using errcode = '22023';
  end if;
  if p_key = 'company.email' and v_text <> ''
    and v_text !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'V1_CFG_EMAIL_INVALID' using errcode = '22023';
  end if;
end;
$$;

-- p_changes: [{ "kind": ..., ... }] — see each branch below.
create or replace function public.v1_cfg_apply(
  p_section text,
  p_changes jsonb,
  p_reason text,
  p_expected_version integer,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_role text := public.v1_current_exact_role();
  v_reason text := btrim(coalesce(p_reason, ''));
  v_existing jsonb;
  v_version integer;
  v_publication uuid := gen_random_uuid();
  v_change jsonb;
  v_kind text;
  v_action text;
  v_key text;
  v_value jsonb;
  v_before jsonb;
  v_after jsonb;
  v_setting public.v1_configuration_settings%rowtype;
  v_id uuid;
  v_name text;
  v_count integer := 0;
  v_order integer;
  v_item jsonb;
  v_index integer;
  v_stage_key text;
  v_area text := case p_section
    when 'company' then 'company_regional'
    when 'requests' then 'material_requests'
    when 'inventory' then 'procurement_inventory'
    when 'projects' then 'boq_materials'
    when 'accounts' then 'accounts'
    when 'notifications' then 'notifications'
    when 'rentals' then 'rentals'
  end;
  v_allowed_settings text[] := case p_section
    when 'company' then array[
      'company.legal_name', 'company.short_name', 'company.arabic_name',
      'company.address', 'company.phone', 'company.fax', 'company.email',
      'company.trn', 'company.bank_name', 'company.bank_account_name',
      'company.bank_iban', 'support.developer_whatsapp'
    ]
    when 'requests' then array[
      'requests.default_timing', 'requests.urgent_enabled',
      'requests.allow_authorized_creator_self_approval'
    ]
    when 'inventory' then array['procurement.require_external_source_readiness']
    when 'notifications' then array['notifications.push_enabled']
    else array[]::text[]
  end;
begin
  if v_area is null then
    raise exception 'V1_CFG_SECTION_UNKNOWN' using errcode = '22023';
  end if;
  if not public.v1_cfg_section_editable(p_section) then
    raise exception 'V1_CONFIGURATION_ACCESS_DENIED' using errcode = '42501';
  end if;
  if char_length(v_reason) not between 8 and 500 then
    raise exception 'V1_CONFIGURATION_PUBLISH_REASON_REQUIRED'
      using errcode = '22023';
  end if;
  if jsonb_typeof(p_changes) <> 'array'
    or jsonb_array_length(p_changes) not between 1 and 200 then
    raise exception 'V1_CFG_CHANGES_INVALID' using errcode = '22023';
  end if;
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_cfg_apply', p_idempotency_key,
    jsonb_build_object(
      'section', p_section, 'changes', p_changes, 'reason', v_reason,
      'expected', p_expected_version
    )
  );
  if v_existing is not null then
    return v_existing;
  end if;

  -- One writer at a time; a save based on an older version is refused.
  perform 1 from public.v1_configuration_draft_state
  where singleton for update;
  select coalesce(max(version_number), 0) into v_version
  from public.v1_configuration_publications;
  if p_expected_version is null or p_expected_version <> v_version then
    raise exception 'V1_CONFIGURATION_DRAFT_VERSION_CONFLICT'
      using errcode = '40001';
  end if;
  v_version := v_version + 1;
  insert into public.v1_configuration_publications (
    id, version_number, version_label, reason, affected_areas,
    published_by_auth_user_id, published_by_exact_role, idempotency_key
  ) values (
    v_publication, v_version, format('v1.%s.0', v_version - 1), v_reason,
    array[v_area], v_actor, v_role, p_idempotency_key
  );

  for v_change in select value from jsonb_array_elements(p_changes) loop
    v_kind := v_change ->> 'kind';
    v_action := coalesce(v_change ->> 'action', 'update');
    v_before := null;
    v_after := null;
    v_key := null;

    if v_kind = 'setting' then
      v_key := v_change ->> 'key';
      v_value := v_change -> 'value';
      if not (v_key = any (v_allowed_settings)) then
        raise exception 'V1_CONFIGURATION_SETTING_NOT_EDITABLE'
          using errcode = '22023', detail = coalesce(v_key, '');
      end if;
      select * into v_setting from public.v1_configuration_settings
      where setting_key = v_key for update;
      if not found or v_setting.control_mode <> 'operational' then
        raise exception 'V1_CONFIGURATION_SETTING_NOT_OPERATIONAL'
          using errcode = '22023', detail = v_key;
      end if;
      if v_key like 'company.%' then
        perform public.v1_cfg_validate_company_value(v_key, v_value);
        if v_key = 'company.bank_iban' then
          v_value := to_jsonb(replace(upper(v_value #>> '{}'), ' ', ''));
        end if;
      else
        perform public.v1_validate_configuration_setting_value(v_key, v_value);
      end if;
      if v_value = v_setting.published_value then
        continue;
      end if;
      v_before := v_setting.published_value;
      v_after := v_value;
      update public.v1_configuration_settings
      set published_value = v_value, updated_at = clock_timestamp()
      where setting_key = v_key;

    elsif v_kind = 'boq_template' and p_section = 'projects' then
      v_name := btrim(coalesce(v_change ->> 'name', ''));
      if v_action = 'create' then
        if v_name = '' or char_length(v_name) > 80 then
          raise exception 'V1_CFG_NAME_INVALID' using errcode = '22023';
        end if;
        select coalesce(max(display_order), 0) + 1 into v_order
        from public.v1_boq_group_templates;
        v_key := 'custom_' || public.v1_cfg_slug(v_name);
        if v_key = 'custom_' or exists (
          select 1 from public.v1_boq_group_templates
          where template_key = v_key
        ) then
          v_key := 'custom_' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);
        end if;
        insert into public.v1_boq_group_templates (
          template_key, display_name, display_order, is_frozen, is_active,
          allows_scope_archive
        ) values (v_key, v_name, v_order, true, true, true)
        returning id into v_id;
        v_after := jsonb_build_object('name', v_name, 'active', true);
        v_key := 'boq_template.' || v_id::text;
      else
        v_id := nullif(v_change ->> 'id', '')::uuid;
        select jsonb_build_object(
          'name', display_name, 'active', is_active, 'order', display_order
        ) into v_before
        from public.v1_boq_group_templates where id = v_id for update;
        if v_before is null then
          raise exception 'V1_CFG_ITEM_NOT_FOUND' using errcode = '22023';
        end if;
        if v_action = 'rename' then
          if v_name = '' or char_length(v_name) > 80 then
            raise exception 'V1_CFG_NAME_INVALID' using errcode = '22023';
          end if;
          update public.v1_boq_group_templates set display_name = v_name
          where id = v_id;
        elsif v_action = 'activate' then
          -- Every scope folder is archivable (per-scope folder rule).
          update public.v1_boq_group_templates
          set is_active = true, allows_scope_archive = true
          where id = v_id;
        elsif v_action = 'deactivate' then
          update public.v1_boq_group_templates set is_active = false
          where id = v_id;
        elsif v_action = 'move' then
          v_order := (v_change ->> 'order')::integer;
          if v_order is null or v_order < 1 then
            raise exception 'V1_CFG_CHANGES_INVALID' using errcode = '22023';
          end if;
          update public.v1_boq_group_templates set display_order = v_order
          where id = v_id;
        else
          raise exception 'V1_CFG_CHANGES_INVALID' using errcode = '22023';
        end if;
        select jsonb_build_object(
          'name', display_name, 'active', is_active, 'order', display_order
        ) into v_after
        from public.v1_boq_group_templates where id = v_id;
        v_key := 'boq_template.' || v_id::text;
      end if;

    elsif v_kind = 'inventory_category' and p_section = 'inventory' then
      v_name := btrim(coalesce(v_change ->> 'name', ''));
      if v_action = 'create' then
        if v_name = '' or char_length(v_name) > 80 then
          raise exception 'V1_CFG_NAME_INVALID' using errcode = '22023';
        end if;
        insert into public.v1_inventory_categories (
          name, normalized_name, parent_category_id, is_system, is_active,
          created_by_auth_user_id
        ) values (
          public.v1_inventory_category_display_name(v_name),
          public.v1_inventory_category_key(v_name),
          nullif(v_change ->> 'parent_id', '')::uuid, false, true, v_actor
        )
        returning id into v_id;
        v_after := jsonb_build_object('name', v_name, 'active', true);
      else
        v_id := nullif(v_change ->> 'id', '')::uuid;
        select jsonb_build_object('name', name, 'active', is_active)
        into v_before
        from public.v1_inventory_categories where id = v_id for update;
        if v_before is null then
          raise exception 'V1_CFG_ITEM_NOT_FOUND' using errcode = '22023';
        end if;
        if v_action = 'rename' then
          if v_name = '' or char_length(v_name) > 80 then
            raise exception 'V1_CFG_NAME_INVALID' using errcode = '22023';
          end if;
          update public.v1_inventory_categories
          set name = public.v1_inventory_category_display_name(v_name),
              normalized_name = public.v1_inventory_category_key(v_name),
              record_version = record_version + 1,
              updated_at = clock_timestamp()
          where id = v_id;
        elsif v_action in ('archive', 'restore') then
          update public.v1_inventory_categories
          set is_active = v_action = 'restore',
              record_version = record_version + 1,
              updated_at = clock_timestamp()
          where id = v_id;
        elsif v_action = 'add_alias' then
          if v_name = '' or char_length(v_name) > 80 then
            raise exception 'V1_CFG_NAME_INVALID' using errcode = '22023';
          end if;
          insert into public.v1_inventory_category_aliases (
            category_id, alias_name, normalized_alias, created_by_auth_user_id
          ) values (
            v_id, v_name, public.v1_inventory_category_key(v_name), v_actor
          );
        else
          raise exception 'V1_CFG_CHANGES_INVALID' using errcode = '22023';
        end if;
        select jsonb_build_object('name', name, 'active', is_active)
        into v_after
        from public.v1_inventory_categories where id = v_id;
        if v_action = 'add_alias' then
          v_after := v_after || jsonb_build_object('alias', v_name);
        end if;
      end if;
      v_key := 'inventory_category.' || v_id::text;

    elsif v_kind = 'unit' and p_section = 'inventory' then
      if v_action = 'create' then
        insert into public.v1_configuration_units (
          name, short_code, unit_type, decimal_places, is_system,
          created_by_auth_user_id
        ) values (
          btrim(v_change ->> 'name'), btrim(v_change ->> 'code'),
          v_change ->> 'type',
          coalesce((v_change ->> 'decimals')::integer, 0), false, v_actor
        )
        returning id into v_id;
        v_after := jsonb_build_object(
          'name', btrim(v_change ->> 'name'),
          'code', btrim(v_change ->> 'code'), 'active', true
        );
      elsif v_action in ('archive', 'restore') then
        v_id := nullif(v_change ->> 'id', '')::uuid;
        select jsonb_build_object('name', name, 'active', is_active)
        into v_before
        from public.v1_configuration_units where id = v_id for update;
        if v_before is null then
          raise exception 'V1_CFG_ITEM_NOT_FOUND' using errcode = '22023';
        end if;
        update public.v1_configuration_units
        set is_active = v_action = 'restore', updated_at = clock_timestamp()
        where id = v_id;
        v_after := v_before || jsonb_build_object('active', v_action = 'restore');
      else
        raise exception 'V1_CFG_CHANGES_INVALID' using errcode = '22023';
      end if;
      v_key := 'unit.' || v_id::text;

    elsif v_kind in ('mr_category', 'mr_department') and p_section = 'requests' then
      v_name := btrim(coalesce(v_change ->> 'name', ''));
      if v_action = 'create' then
        if v_name = '' or char_length(v_name) > 120 then
          raise exception 'V1_CFG_NAME_INVALID' using errcode = '22023';
        end if;
        if v_kind = 'mr_category' then
          insert into public.v1_company_material_request_categories (
            category_code, display_name
          ) values (
            left('c_' || public.v1_cfg_slug(v_name), 40)
              || '_' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6),
            v_name
          )
          returning id into v_id;
        else
          insert into public.v1_company_material_request_units (
            unit_code, display_name
          ) values (
            upper(left(regexp_replace(public.v1_cfg_slug(v_name), '_', '-', 'g'), 24))
              || '-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 4)),
            v_name
          )
          returning id into v_id;
        end if;
        v_after := jsonb_build_object('name', v_name, 'active', true);
      else
        v_id := nullif(v_change ->> 'id', '')::uuid;
        if v_kind = 'mr_category' then
          select jsonb_build_object('name', display_name, 'active', is_active)
          into v_before
          from public.v1_company_material_request_categories
          where id = v_id for update;
        else
          select jsonb_build_object('name', display_name, 'active', is_active)
          into v_before
          from public.v1_company_material_request_units
          where id = v_id for update;
        end if;
        if v_before is null then
          raise exception 'V1_CFG_ITEM_NOT_FOUND' using errcode = '22023';
        end if;
        if v_action = 'rename' then
          if v_name = '' or char_length(v_name) > 120 then
            raise exception 'V1_CFG_NAME_INVALID' using errcode = '22023';
          end if;
          v_after := v_before || jsonb_build_object('name', v_name);
        elsif v_action in ('archive', 'restore') then
          v_after := v_before || jsonb_build_object(
            'active', v_action = 'restore'
          );
        else
          raise exception 'V1_CFG_CHANGES_INVALID' using errcode = '22023';
        end if;
        if v_kind = 'mr_category' then
          update public.v1_company_material_request_categories
          set display_name = v_after ->> 'name',
              is_active = (v_after ->> 'active')::boolean,
              updated_at = clock_timestamp()
          where id = v_id;
        else
          update public.v1_company_material_request_units
          set display_name = v_after ->> 'name',
              is_active = (v_after ->> 'active')::boolean,
              updated_at = clock_timestamp()
          where id = v_id;
        end if;
      end if;
      v_key := v_kind || '.' || v_id::text;

    elsif v_kind = 'accounts_policy' and p_section = 'accounts' then
      select jsonb_build_object(
        'payment_terms_days', default_payment_terms_days,
        'reminder_lead_days', default_reminder_lead_days
      ) into v_before
      from public.v1_accounts_foundation_settings where singleton for update;
      begin
        update public.v1_accounts_foundation_settings
        set default_payment_terms_days = (v_change ->> 'payment_terms_days')::integer,
            default_reminder_lead_days = (v_change ->> 'reminder_lead_days')::integer
        where singleton;
      exception when check_violation or invalid_text_representation
        or not_null_violation then
        raise exception 'V1_CFG_ACCOUNTS_POLICY_INVALID' using errcode = '22023';
      end;
      if (v_change ->> 'payment_terms_days')::integer > 365 then
        raise exception 'V1_CFG_ACCOUNTS_POLICY_INVALID' using errcode = '22023';
      end if;
      v_after := jsonb_build_object(
        'payment_terms_days', (v_change ->> 'payment_terms_days')::integer,
        'reminder_lead_days', (v_change ->> 'reminder_lead_days')::integer
      );
      v_key := 'accounts.default_policy';

    elsif v_kind = 'accounts_stages' and p_section = 'accounts' then
      -- The whole ordered list; active stages must total exactly 100%
      -- (checked when the transaction commits). Stages missing from the
      -- list are switched off, never deleted.
      if jsonb_typeof(v_change -> 'stages') <> 'array'
        or jsonb_array_length(v_change -> 'stages') not between 1 and 12 then
        raise exception 'V1_CFG_CHANGES_INVALID' using errcode = '22023';
      end if;
      select coalesce(jsonb_agg(jsonb_build_object(
        'key', stage_key, 'name', stage_name,
        'percent', allocation_percent::text, 'active', is_active
      ) order by display_order), '[]'::jsonb)
      into v_before
      from public.v1_accounts_billing_stage_templates;
      -- Free the display positions first.
      update public.v1_accounts_billing_stage_templates
      set display_order = display_order + 1000;
      update public.v1_accounts_billing_stage_templates set is_active = false;
      v_index := 0;
      for v_item in select value from jsonb_array_elements(v_change -> 'stages') loop
        v_index := v_index + 1;
        v_name := btrim(coalesce(v_item ->> 'name', ''));
        if v_name = '' or char_length(v_name) > 80 then
          raise exception 'V1_CFG_NAME_INVALID' using errcode = '22023';
        end if;
        v_stage_key := nullif(btrim(coalesce(v_item ->> 'key', '')), '');
        if v_stage_key is null then
          v_stage_key := coalesce(nullif(public.v1_cfg_slug(v_name), ''), 'stage');
          if v_stage_key !~ '^[a-z]' then
            v_stage_key := 'stage_' || v_stage_key;
          end if;
          while exists (
            select 1 from public.v1_accounts_billing_stage_templates
            where stage_key = v_stage_key
          ) loop
            v_stage_key := v_stage_key || '_' || v_index::text;
          end loop;
        end if;
        begin
          insert into public.v1_accounts_billing_stage_templates (
            stage_key, stage_name, allocation_percent, display_order, is_active
          ) values (
            v_stage_key, v_name,
            round((v_item ->> 'percent')::numeric, 4), v_index, true
          )
          on conflict (stage_key) do update
            set stage_name = excluded.stage_name,
                allocation_percent = excluded.allocation_percent,
                display_order = excluded.display_order,
                is_active = true;
        exception when check_violation or invalid_text_representation
          or numeric_value_out_of_range or not_null_violation then
          raise exception 'V1_CFG_STAGE_INVALID' using errcode = '22023';
        end;
      end loop;
      if (
        select coalesce(sum(allocation_percent), 0)
        from public.v1_accounts_billing_stage_templates where is_active
      ) <> 100 then
        raise exception 'V1_CFG_STAGE_TOTAL_INVALID' using errcode = '23514';
      end if;
      select coalesce(jsonb_agg(jsonb_build_object(
        'key', stage_key, 'name', stage_name,
        'percent', allocation_percent::text, 'active', is_active
      ) order by display_order), '[]'::jsonb)
      into v_after
      from public.v1_accounts_billing_stage_templates;
      v_key := 'accounts.default_stages';

    elsif v_kind = 'rentals' and p_section = 'rentals' then
      select jsonb_build_object(
        'enabled', enabled, 'push', external_push_enabled
      ) into v_before
      from public.v1_rental_notification_control where id for update;
      if jsonb_typeof(v_change -> 'enabled') <> 'boolean'
        or jsonb_typeof(v_change -> 'push') <> 'boolean' then
        raise exception 'V1_CFG_CHANGES_INVALID' using errcode = '22023';
      end if;
      update public.v1_rental_notification_control
      set enabled = (v_change ->> 'enabled')::boolean,
          external_push_enabled = (v_change ->> 'enabled')::boolean
            and (v_change ->> 'push')::boolean
      where id;
      select jsonb_build_object(
        'enabled', enabled, 'push', external_push_enabled
      ) into v_after
      from public.v1_rental_notification_control where id;
      v_key := 'rentals.reminders';

    else
      raise exception 'V1_CFG_CHANGES_INVALID' using errcode = '22023',
        detail = coalesce(v_kind, '');
    end if;

    if v_before is distinct from v_after then
      insert into public.v1_configuration_publication_changes (
        publication_id, setting_key, area, before_value, after_value,
        change_kind
      ) values (
        v_publication, v_key, v_area, v_before, v_after,
        case
          when v_kind = 'setting' then 'setting'
          when v_action = 'create' then 'master_create'
          when v_action in ('archive', 'deactivate') then 'master_archive'
          else 'setting'
        end
      );
      v_count := v_count + 1;
    end if;
  end loop;

  if v_count = 0 then
    raise exception 'V1_CONFIGURATION_NO_DRAFT_CHANGES' using errcode = '22023';
  end if;

  if exists (
    select 1 from public.v1_boq_group_templates where is_active
  ) is false and p_section = 'projects' then
    raise exception 'V1_CFG_DEFAULT_FOLDER_REQUIRED' using errcode = '23514';
  end if;

  perform public.v1_write_audit_event(
    'configuration_published', 'configuration_publication', v_publication,
    null, null,
    jsonb_build_object(
      'version', format('v1.%s.0', v_version - 1),
      'areas', jsonb_build_array(v_area),
      'record_version', v_version,
      'changes', v_count
    ),
    v_reason, p_idempotency_key
  );
  v_existing := jsonb_build_object(
    'publication_id', v_publication,
    'version', v_version,
    'changes', v_count
  );
  perform public.v1_complete_idempotency(
    'v1_cfg_apply', p_idempotency_key, v_existing
  );
  return v_existing;
exception
  when unique_violation then
    raise exception 'V1_CFG_NAME_TAKEN' using errcode = '23505';
end;
$$;

revoke all on function
  public.v1_cfg_section_editable(text),
  public.v1_cfg_slug(text),
  public.v1_cfg_validate_company_value(text, jsonb)
  from public, anon, authenticated;
revoke all on function public.v1_cfg_get_workspace() from public, anon;
revoke all on function public.v1_cfg_apply(text, jsonb, text, integer, uuid)
  from public, anon;
grant execute on function public.v1_cfg_get_workspace() to authenticated;
grant execute on function public.v1_cfg_apply(text, jsonb, text, integer, uuid)
  to authenticated;

notify pgrst, 'reload schema';

commit;
