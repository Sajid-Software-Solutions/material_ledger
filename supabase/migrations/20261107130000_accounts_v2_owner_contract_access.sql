-- R39 Accounts Workspace V2 — owner decisions of 7 November 2026
--
-- Contract editing: Project Engineer, Senior Mechanical Engineer, Project
-- Manager, Admin and Accountant hold configure_project_commercials by default.
-- This supersedes working decision D1. Site Engineer and Procurement stay out.
--
-- Commercial values: Project Engineer holds view_project_commercial_values by
-- default. This already held on a migrated database and is restated so a
-- database that drifted from it comes back to the owner's decision.
--
-- These are role defaults: project scope, per-user denials and every record
-- state check still apply. Additive and repeatable; no record changes.

insert into public.v1_permission_role_defaults (
  role_name, capability_key, is_granted, can_delegate
)
select role_name, 'configure_project_commercials', true, false
from unnest(array[
  'project_engineer', 'senior_mechanical_engineer', 'project_manager',
  'accountant'
]) as role_name
on conflict (role_name, capability_key) do update
set is_granted = true,
    updated_at = clock_timestamp();

insert into public.v1_permission_role_defaults (
  role_name, capability_key, is_granted, can_delegate
)
values ('project_engineer', 'view_project_commercial_values', true, false)
on conflict (role_name, capability_key) do update
set is_granted = true,
    updated_at = clock_timestamp();

-- The role default only counts within this scope list, which held contract
-- editing back from the engineering roles. A Project Engineer still needs dated
-- membership of the project; Senior Mechanical Engineer and Project Manager are
-- organization-wide. Grants on this function are unchanged.
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
