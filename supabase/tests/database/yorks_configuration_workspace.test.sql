begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- Local personas: PE ...0001, Procurement ...0003, Admin ...0004, PR ...0014.

create function pg_temp.act(p_user uuid, p_role text)
returns void
language plpgsql
as $$
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', p_user, 'role', 'authenticated',
      'app_metadata', jsonb_build_object('role', p_role)
    )::text,
    true
  );
end;
$$;

select set_config('cfg.v0', (
  select coalesce(max(version_number), 0)::text
  from public.v1_configuration_publications
), true);
select set_config('cfg.baseline_rows', (
  select count(*)::text from public.v1_accounts_baseline_stage_allocations
), true);
select set_config('cfg.workshop', (
  select id::text from public.v1_boq_group_templates
  where template_key = 'workshop_materials'
), true);

-- Reading ----------------------------------------------------------------------

set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select throws_ok(
  $$select public.v1_cfg_get_workspace()$$, '42501', null,
  'A Project Engineer cannot open Configuration'
);
select pg_temp.act('10000000-0000-4000-8000-000000000003', 'procurement');
select throws_ok(
  $$select public.v1_cfg_get_workspace()$$, '42501', null,
  'Procurement cannot open Configuration'
);

select pg_temp.act('10000000-0000-4000-8000-000000000014', 'pr');
select ok(
  (public.v1_cfg_get_workspace() -> 'editable' ->> 'rentals')::boolean
  and not (public.v1_cfg_get_workspace() -> 'editable' ->> 'company')::boolean
  and public.v1_cfg_get_workspace() -> 'settings' = '{}'::jsonb,
  'PR sees only Workforce and Rentals; no company or commercial settings'
);
select ok(
  public.v1_get_runtime_configuration() ? 'support_whatsapp',
  'PR reads the runtime configuration'
);

select pg_temp.act('10000000-0000-4000-8000-000000000004', 'admin');
select ok(
  (public.v1_cfg_get_workspace() -> 'editable' ->> 'company')::boolean
  and public.v1_cfg_get_workspace() -> 'settings' ? 'company.bank_iban'
  and jsonb_array_length(public.v1_cfg_get_workspace() -> 'boq_templates') > 0,
  'Admin reads every section'
);

-- Company --------------------------------------------------------------------

select throws_ok(
  format($$select public.v1_cfg_apply('company',
    '[{"kind":"setting","key":"company.bank_iban","value":"NOT AN IBAN"}]',
    'Invoice bank details', %s, '9c000000-0000-4000-8000-000000000001')$$,
    current_setting('cfg.v0')),
  '22023', 'V1_CFG_IBAN_INVALID', 'An IBAN must look like one'
);
select throws_ok(
  format($$select public.v1_cfg_apply('company',
    '[{"kind":"setting","key":"company.bank_name","value":"Example Bank"}]',
    '', %s, '9c000000-0000-4000-8000-000000000002')$$,
    current_setting('cfg.v0')),
  '22023', null, 'Every save needs a reason'
);
select throws_ok(
  format($$select public.v1_cfg_apply('company',
    '[{"kind":"setting","key":"regional.currency","value":"USD"}]',
    'Try to change currency', %s, '9c000000-0000-4000-8000-000000000003')$$,
    current_setting('cfg.v0')),
  '22023', null, 'A fixed fact such as the currency cannot be changed'
);
select is(
  (public.v1_cfg_apply('company',
    '[{"kind":"setting","key":"company.bank_name","value":"Example Bank PJSC"},
      {"kind":"setting","key":"company.bank_iban","value":"ae07 0331 2345 6789 0123 456"}]',
    'Invoice bank details', current_setting('cfg.v0')::integer,
    '9c000000-0000-4000-8000-000000000004') ->> 'changes')::integer,
  2, 'Admin saves the bank block with a reason'
);
select is(
  (public.v1_cfg_apply('company',
    '[{"kind":"setting","key":"company.bank_name","value":"Example Bank PJSC"},
      {"kind":"setting","key":"company.bank_iban","value":"ae07 0331 2345 6789 0123 456"}]',
    'Invoice bank details', current_setting('cfg.v0')::integer,
    '9c000000-0000-4000-8000-000000000004') ->> 'changes')::integer,
  2, 'A retried save changes nothing twice'
);
reset role;
select is(
  (select published_value #>> '{}' from public.v1_configuration_settings
   where setting_key = 'company.bank_iban'),
  'AE070331234567890123456',
  'The IBAN is stored without spaces, in capitals'
);
select ok(
  exists (
    select 1 from public.v1_configuration_publication_changes change
    join public.v1_configuration_publications publication
      on publication.id = change.publication_id
    where change.setting_key = 'company.bank_name'
      and publication.reason = 'Invoice bank details'
      and change.after_value = '"Example Bank PJSC"'::jsonb
  ),
  'The change is in the configuration history with before and after'
);
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000004', 'admin');
select throws_ok(
  format($$select public.v1_cfg_apply('company',
    '[{"kind":"setting","key":"company.phone","value":"02-5550000"}]',
    'Phone update', %s, '9c000000-0000-4000-8000-000000000005')$$,
    current_setting('cfg.v0')),
  '40001', null, 'A save based on an older version is refused'
);
select pg_temp.act('10000000-0000-4000-8000-000000000014', 'pr');
select throws_ok(
  format($$select public.v1_cfg_apply('company',
    '[{"kind":"setting","key":"company.phone","value":"02-5550000"}]',
    'Phone update', %s, '9c000000-0000-4000-8000-000000000006')$$,
    current_setting('cfg.v0')::integer + 1),
  '42501', null, 'PR cannot change company settings'
);

-- Rentals (PR) ------------------------------------------------------------------

select lives_ok(
  format($$select public.v1_cfg_apply('rentals',
    '[{"kind":"rentals","enabled":true,"push":false}]',
    'Inbox only for now', %s, '9c000000-0000-4000-8000-000000000007')$$,
    current_setting('cfg.v0')::integer + 1),
  'PR turns rental reminders on without push'
);

-- Projects: default BOQ folders ---------------------------------------------------

select pg_temp.act('10000000-0000-4000-8000-000000000004', 'admin');
select lives_ok(
  format($$select public.v1_cfg_apply('projects',
    '[{"kind":"boq_template","action":"create","name":"Site Consumables"}]',
    'New default folder', %s, '9c000000-0000-4000-8000-000000000008')$$,
    current_setting('cfg.v0')::integer + 2),
  'Admin adds a default folder'
);
select throws_ok(
  format($$select public.v1_cfg_apply('projects',
    jsonb_build_array(
      jsonb_build_object('kind','boq_template','action','deactivate','id',%L),
      jsonb_build_object('kind','boq_template','action','deactivate','id',
        (select id from public.v1_boq_group_templates where template_key like 'custom_site_consumables%%'))
    ),
    'No defaults at all', %s, '9c000000-0000-4000-8000-000000000009')$$,
    current_setting('cfg.workshop'), current_setting('cfg.v0')::integer + 3),
  '23514', 'V1_CFG_DEFAULT_FOLDER_REQUIRED',
  'At least one default folder stays on'
);
reset role;
select ok(
  (select is_active and allows_scope_archive from public.v1_boq_group_templates
   where template_key like 'custom_site_consumables%'),
  'A new default folder is on and archivable per scope'
);

-- Accounts defaults ----------------------------------------------------------------

set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000004', 'admin');
select throws_ok(
  format($$select public.v1_cfg_apply('accounts',
    '[{"kind":"accounts_stages","stages":[
       {"key":"design","name":"Design","percent":"20"},
       {"key":"material_supply","name":"Material Supply","percent":"50"}]}]',
    'Two stages only', %s, '9c000000-0000-4000-8000-000000000010')$$,
    current_setting('cfg.v0')::integer + 3),
  '23514', 'V1_CFG_STAGE_TOTAL_INVALID', 'Stages must total 100%%'
);
select lives_ok(
  format($$select public.v1_cfg_apply('accounts',
    '[{"kind":"accounts_stages","stages":[
       {"key":"design","name":"Design","percent":"10"},
       {"key":"material_supply","name":"Material Supply","percent":"60"},
       {"key":"installation","name":"Installation","percent":"25"},
       {"name":"Handover","percent":"5"}]},
      {"kind":"accounts_policy","payment_terms_days":60,"reminder_lead_days":7}]',
    'New defaults for future projects', %s,
    '9c000000-0000-4000-8000-000000000011')$$,
    current_setting('cfg.v0')::integer + 3),
  'Admin changes the default stages and payment policy'
);
reset role;
select is(
  (select sum(allocation_percent) from public.v1_accounts_billing_stage_templates
   where is_active),
  100.0000::numeric, 'Active default stages total 100%'
);
select is(
  (select count(*)::text from public.v1_accounts_baseline_stage_allocations),
  current_setting('cfg.baseline_rows'),
  'Existing project baselines are untouched'
);
select is(
  (select default_payment_terms_days from public.v1_accounts_foundation_settings
   where singleton),
  60, 'The default payment terms are 60 days for new baselines'
);

-- Weekly off days -------------------------------------------------------------

reset role;
select is(public.v1_wf_day_type('2026-11-15'), 'holiday', 'Sunday is the default off day');
select is(public.v1_wf_day_type('2026-11-13'), 'work', 'Friday is a working day by default');
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000014', 'pr');
select ok(
  public.v1_cfg_get_workspace() -> 'weekly_off_days' = '["sunday"]'::jsonb,
  'PR sees the weekly off days'
);
select throws_ok(
  format($$select public.v1_cfg_apply('workforce',
    '[{"kind":"setting","key":"workforce.weekly_off_days","value":["funday"]}]',
    'Bad weekday name', %s, '9c000000-0000-4000-8000-000000000020')$$,
    current_setting('cfg.v0')::integer + 4),
  '22023', 'V1_CFG_OFF_DAYS_INVALID', 'Only real weekday names are accepted'
);
select lives_ok(
  format($$select public.v1_cfg_apply('workforce',
    '[{"kind":"setting","key":"workforce.weekly_off_days","value":["friday","saturday"]}]',
    'Site works a Friday-Saturday weekend', %s,
    '9c000000-0000-4000-8000-000000000021')$$,
    current_setting('cfg.v0')::integer + 4),
  'PR changes the weekly off days'
);
reset role;
select is(public.v1_wf_day_type('2026-11-15'), 'work', 'Sunday becomes a working day');
select is(public.v1_wf_day_type('2026-11-13'), 'holiday', 'Friday becomes an off day');

-- Boundary ----------------------------------------------------------------------

select ok(
  not has_function_privilege('anon', 'public.v1_cfg_apply(text,jsonb,text,integer,uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.v1_cfg_section_editable(text)', 'execute'),
  'Only signed-in people call the two commands; helpers stay internal'
);

select * from finish();
rollback;
