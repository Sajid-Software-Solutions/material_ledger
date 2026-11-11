-- Release bundle: R39 Accounts — Project Engineer full commercial access
-- Applies migration 20261111120000 in one transaction, then checks itself.
-- Its scope function is the 20261111130000 definition, which also keeps the
-- organization-wide engineering roles' 9 November claim rights.
-- Apply by hand (staging, then production):
--   npx supabase@latest db query --remote=<ref> --yes -f supabase/release/accounts_project_engineer_bundle.sql
-- Rollback: supabase/release/accounts_project_engineer_rollback.sql

begin;

-- 1. Role defaults: every Accounts key, without delegation.
insert into public.v1_permission_role_defaults (
  role_name, capability_key, is_granted, can_delegate
)
select 'project_engineer', catalog.capability_key, true, false
from public.v1_capability_catalog catalog
where public.v1_accounts_is_capability_key(catalog.capability_key)
on conflict (role_name, capability_key) do update
set is_granted = true,
    updated_at = clock_timestamp();

-- 2. Scope: a Project Engineer member may hold any Accounts key. Everything
-- else in this function is as defined by 20261107130000.
create or replace function public.v1_accounts_has_project_scope(
  p_auth_user_id uuid,
  p_project_id uuid,
  p_capability_key text
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_exact_role text := public.v1_permission_exact_role(p_auth_user_id);
  v_has_membership boolean := false;
begin
  if v_exact_role = ''
    or p_project_id is null
    or not coalesce(public.v1_accounts_is_capability_key(p_capability_key), false)
    or not exists (
      select 1 from public.v1_projects project where project.id = p_project_id
    ) then
    return false;
  end if;

  if v_exact_role in ('accountant', 'admin') then
    return true;
  end if;
  if v_exact_role = 'procurement' then
    return p_capability_key in ('manage_supplier_bills', 'view_supplier_costs');
  end if;
  if v_exact_role in (
    'senior_mechanical_engineer', 'project_manager',
    'workshop_in_charge', 'document_controller'
  ) then
    return p_capability_key in (
      'view_project_accounts', 'view_project_commercial_values',
      'export_accounts_registers', 'review_commercial_progress',
      'configure_project_commercials',
      'confirm_billing_progress', 'prepare_client_claim'
    );
  end if;
  if v_exact_role not in ('project_engineer', 'site_engineer') then
    return false;
  end if;

  select exists (
    select 1
    from public.v1_project_members member
    where member.project_id = p_project_id
      and member.member_auth_user_id = p_auth_user_id
      and member.project_role = v_exact_role
      and member.effective_from <= clock_timestamp()
      and (
        member.effective_to is null
        or member.effective_to > clock_timestamp()
      )
  ) into v_has_membership;
  if not v_has_membership then
    return false;
  end if;

  if v_exact_role = 'site_engineer' then
    return p_capability_key in (
      'view_project_accounts', 'suggest_billing_progress'
    );
  end if;
  return true;
end;
$$;

-- 3. Supplier bill and payment commands also check the exact role after the
-- capability. Add Project Engineer to those lists in the live definitions, so
-- each function keeps every other line exactly as deployed. Repeatable: a
-- definition that already names project_engineer is left alone.
do $$
declare
  v_fn record;
  v_def text;
  v_new text;
  v_changed integer := 0;
begin
  for v_fn in
    select p.oid, p.proname
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = any(array[
        'v1_create_supplier_bill_draft', 'v1_update_supplier_bill_draft',
        'v1_cancel_supplier_bill', 'v1_approve_supplier_bill',
        'v1_reopen_supplier_bill', 'v1_record_supplier_payment',
        'v1_reverse_supplier_payment', 'v1_correct_supplier_payment',
        'v1_list_supplier_bill_delivery_options'
      ]::text[])
  loop
    v_def := pg_get_functiondef(v_fn.oid);
    v_new := replace(
      replace(
        v_def,
        'v_exact not in (''procurement'', ''accountant'', ''admin'')',
        'v_exact not in (''procurement'', ''accountant'', ''admin'', ''project_engineer'')'
      ),
      'v_exact not in (''accountant'', ''admin'')',
      'v_exact not in (''accountant'', ''admin'', ''project_engineer'')'
    );
    if v_new <> v_def then
      execute v_new;
      v_changed := v_changed + 1;
    elsif position('''project_engineer''' in v_def) = 0 then
      raise exception 'Accounts PE access: % has no role list to widen',
        v_fn.proname;
    end if;
  end loop;
  raise notice 'Accounts PE access: % supplier functions widened', v_changed;
end;
$$;

-- 4. Actor-role CHECK constraints on Accounts tables that name Accountant but
-- not Project Engineer. Widening keeps every existing row valid.
do $$
declare
  v_con record;
  v_new text;
begin
  for v_con in
    select c.conname, c.conrelid::regclass as rel,
      pg_get_constraintdef(c.oid) as def
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public'
      and t.relname like 'v1\_accounts\_%'
      and c.contype = 'c'
      and pg_get_constraintdef(c.oid) like '%''accountant''::text%'
      and pg_get_constraintdef(c.oid) like '%''admin''::text%'
      and pg_get_constraintdef(c.oid) not like '%''project_engineer''::text%'
      and pg_get_constraintdef(c.oid) ~ '(role|exact_role)'
  loop
    v_new := replace(
      v_con.def, '''accountant''::text',
      '''project_engineer''::text, ''accountant''::text'
    );
    execute format(
      'alter table %s drop constraint %I', v_con.rel, v_con.conname
    );
    execute format(
      'alter table %s add constraint %I %s', v_con.rel, v_con.conname, v_new
    );
    raise notice 'Accounts PE access: widened %.%', v_con.rel, v_con.conname;
  end loop;
end;
$$;


-- Self-checks: abort the whole transaction if anything did not land.
do $$
declare
  v_keys integer;
  v_granted integer;
  v_fn integer;
  v_con integer;
begin
  select count(*) into v_keys from public.v1_capability_catalog
  where public.v1_accounts_is_capability_key(capability_key);
  select count(*) into v_granted from public.v1_permission_role_defaults
  where role_name = 'project_engineer' and is_granted
    and public.v1_accounts_is_capability_key(capability_key);
  if v_keys < 15 or v_granted <> v_keys then
    raise exception 'PE bundle check: % of % Accounts keys granted', v_granted, v_keys;
  end if;

  select count(*) into v_fn from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = any(array[
      'v1_create_supplier_bill_draft','v1_update_supplier_bill_draft',
      'v1_cancel_supplier_bill','v1_approve_supplier_bill',
      'v1_reopen_supplier_bill','v1_record_supplier_payment',
      'v1_reverse_supplier_payment','v1_correct_supplier_payment',
      'v1_list_supplier_bill_delivery_options'])
    and position('''project_engineer''' in pg_get_functiondef(p.oid)) = 0;
  if v_fn <> 0 then
    raise exception 'PE bundle check: % supplier functions still exclude PE', v_fn;
  end if;

  select count(*) into v_con from pg_constraint c
  join pg_class t on t.oid = c.conrelid
  join pg_namespace n on n.oid = t.relnamespace
  where n.nspname = 'public' and t.relname like 'v1\_accounts\_%' and c.contype = 'c'
    and pg_get_constraintdef(c.oid) like '%''accountant''::text%'
    and pg_get_constraintdef(c.oid) like '%''admin''::text%'
    and pg_get_constraintdef(c.oid) not like '%''project_engineer''::text%'
    and pg_get_constraintdef(c.oid) ~ '(role|exact_role)';
  if v_con <> 0 then
    raise exception 'PE bundle check: % actor-role constraints still exclude PE', v_con;
  end if;
end;
$$;

commit;

notify pgrst, 'reload schema';
