-- Rollback: R39 Accounts — Project Engineer full commercial access
--
-- Returns Project Engineer to the section 29 access (7 November 2026):
-- view_project_accounts, view_project_commercial_values,
-- confirm_billing_progress, prepare_client_claim, export_accounts_registers
-- and configure_project_commercials on member projects.
--
-- Actor-role CHECK constraints stay widened on purpose: records a Project
-- Engineer created meanwhile must stay valid. Without the capability and the
-- command role checks, no new such record can be written. No data is changed.

begin;

update public.v1_permission_role_defaults
set is_granted = false,
    updated_at = clock_timestamp()
where role_name = 'project_engineer'
  and public.v1_accounts_is_capability_key(capability_key)
  and capability_key <> all(array[
    'view_project_accounts', 'view_project_commercial_values',
    'confirm_billing_progress', 'prepare_client_claim',
    'export_accounts_registers', 'configure_project_commercials'
  ]::text[]);

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
  if v_exact_role in ('senior_mechanical_engineer', 'project_manager') then
    return p_capability_key in (
      'view_project_accounts', 'view_project_commercial_values',
      'export_accounts_registers', 'review_commercial_progress',
      'configure_project_commercials'
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
  return p_capability_key in (
    'view_project_accounts', 'view_project_commercial_values',
    'confirm_billing_progress', 'prepare_client_claim',
    'export_accounts_registers', 'configure_project_commercials'
  );
end;
$$;

do $$
declare
  v_fn record;
  v_def text;
  v_new text;
begin
  for v_fn in
    select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
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
    v_new := replace(v_def, ', ''admin'', ''project_engineer'')', ', ''admin'')');
    if v_new <> v_def then
      execute v_new;
    end if;
  end loop;
end;
$$;

commit;

notify pgrst, 'reload schema';
