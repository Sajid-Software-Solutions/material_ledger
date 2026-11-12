-- Weekly off days become a setting (owner, 13 November 2026).
--
-- Sunday was hard-coded as the rest day. It is now the default of
-- `workforce.weekly_off_days`, edited in Configuration › Workforce by Admin
-- and PR. Work on an off day counts as holiday overtime, exactly as Sunday
-- did. Days already saved keep the hours they were saved with.
--
-- Data preservation: one new setting row (default ["sunday"], so nothing
-- changes until someone edits it); the area check is widened; three
-- function bodies are extended by guarded rewrites. Rollback: restore the
-- previous v1_wf_day_type (Sunday only); the setting row may stay.

begin;

alter table public.v1_configuration_settings
  drop constraint if exists v1_configuration_settings_area_check;
alter table public.v1_configuration_settings
  add constraint v1_configuration_settings_area_check
  check (area in (
    'company_regional', 'projects_teams', 'boq_materials',
    'material_requests', 'procurement_inventory', 'accounts',
    'documents_printing', 'notifications', 'security_audit',
    'numbering_data', 'workforce'
  ));

insert into public.v1_configuration_settings (
  setting_key, area, value_type, default_value, published_value,
  display_order, control_mode, impact_scope, enforcement_target
) values (
  'workforce.weekly_off_days', 'workforce', 'string_array',
  '["sunday"]'::jsonb, '["sunday"]'::jsonb, 1, 'operational',
  array['workforce']::text[], 'attendance_day_type'
)
on conflict (setting_key) do nothing;

-- Off days: a list of distinct weekday names (none to six).
create or replace function public.v1_cfg_validate_off_days(p_value jsonb)
returns void
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_value is null or jsonb_typeof(p_value) <> 'array'
    or jsonb_array_length(p_value) > 6
    or exists (
      select 1 from jsonb_array_elements(p_value) item
      where jsonb_typeof(item) <> 'string'
        or item #>> '{}' not in (
          'monday', 'tuesday', 'wednesday', 'thursday', 'friday',
          'saturday', 'sunday'
        )
    )
    or (select count(distinct item #>> '{}') from jsonb_array_elements(p_value) item)
      <> jsonb_array_length(p_value) then
    raise exception 'V1_CFG_OFF_DAYS_INVALID' using errcode = '22023';
  end if;
end;
$$;
revoke all on function public.v1_cfg_validate_off_days(jsonb)
  from public, anon, authenticated;

-- The day type every attendance rule uses.
create or replace function public.v1_wf_day_type(p_date date)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when (array[
        'monday', 'tuesday', 'wednesday', 'thursday', 'friday',
        'saturday', 'sunday'
      ])[extract(isodow from p_date)::integer] in (
        select jsonb_array_elements_text(coalesce((
          select setting.published_value
          from public.v1_configuration_settings setting
          where setting.setting_key = 'workforce.weekly_off_days'
        ), '["sunday"]'::jsonb))
      ) then 'holiday'
    when exists (
      select 1 from public.v1_workforce_public_holidays holiday
      where holiday.holiday_date = p_date
    ) then 'holiday'
    else 'work'
  end;
$$;

-- Configuration: the Workforce section saves the setting; the workspace
-- returns it to Admin and PR.
do $rewrite$
declare
  v_definition text;
  v_updated text;
begin
  v_definition := pg_get_functiondef(
    'public.v1_cfg_apply(text,jsonb,text,integer,uuid)'::regprocedure
  );
  if position('workforce.weekly_off_days' in v_definition) = 0 then
    v_updated := replace(
      v_definition,
      E'    when ''rentals'' then ''rentals''\n  end;',
      E'    when ''rentals'' then ''rentals''\n    when ''workforce'' then ''workforce''\n  end;'
    );
    v_updated := replace(
      v_updated,
      E'    when ''notifications'' then array[''notifications.push_enabled'']',
      E'    when ''notifications'' then array[''notifications.push_enabled'']\n    when ''workforce'' then array[''workforce.weekly_off_days'']'
    );
    v_updated := replace(
      v_updated,
      E'      else\n        perform public.v1_validate_configuration_setting_value(v_key, v_value);',
      E'      elsif v_key = ''workforce.weekly_off_days'' then\n        perform public.v1_cfg_validate_off_days(v_value);\n      else\n        perform public.v1_validate_configuration_setting_value(v_key, v_value);'
    );
    if v_updated = v_definition
      or (length(v_updated) - length(v_definition)) < 150 then
      raise exception 'V1_CFG_APPLY_ANCHOR_MISSING';
    end if;
    execute v_updated;
  end if;

  v_definition := pg_get_functiondef(
    'public.v1_cfg_get_workspace()'::regprocedure
  );
  if position('weekly_off_days' in v_definition) = 0 then
    v_updated := replace(
      v_definition,
      E'    ''today'', v_today,\n',
      E'    ''today'', v_today,\n    ''weekly_off_days'', coalesce((\n      select setting.published_value\n      from public.v1_configuration_settings setting\n      where setting.setting_key = ''workforce.weekly_off_days''\n    ), ''["sunday"]''::jsonb),\n'
    );
    if v_updated = v_definition then
      raise exception 'V1_CFG_WORKSPACE_ANCHOR_MISSING';
    end if;
    execute v_updated;
  end if;
end;
$rewrite$;

notify pgrst, 'reload schema';

commit;
