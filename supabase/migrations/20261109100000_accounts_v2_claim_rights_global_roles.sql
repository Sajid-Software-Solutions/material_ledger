-- R39 Accounts Workspace V2 — owner decision of 9 November 2026
--
-- Who may record billing progress and prepare a client claim. Until now only a
-- Project Engineer with dated membership of the project could, so on YRA-322
-- the Owner (Admin) and the organization-wide engineering roles had no "New
-- claim" and the project looked stuck after Claim #02.
--
-- Admin, Senior Mechanical Engineer, Project Manager, Workshop In-Charge and
-- Document Controller now hold the Project Engineer's claim rights by default:
--   view_project_accounts, view_project_commercial_values,
--   confirm_billing_progress, prepare_client_claim.
-- The four engineering roles are organization-wide (AGENTS.md: they act as
-- Project Engineer on every project without a membership row), so they need no
-- project membership. Workshop In-Charge and Document Controller had no Accounts
-- scope at all; they get the same scope list as Senior Mechanical Engineer and
-- Project Manager. Their role defaults grant only the four keys above, so the
-- other keys in that scope list stay off for them.
--
-- Site Engineer, Procurement and Accountant are unchanged. Per-user denials and
-- every record state check still apply. Role defaults and one scope function:
-- additive and repeatable; no record changes.
--
-- Rollback: set the role defaults back to false (admin keeps can_delegate) and
-- re-apply v1_accounts_has_project_scope from
-- 20261107130000_accounts_v2_owner_contract_access.sql.

insert into public.v1_permission_role_defaults (
  role_name, capability_key, is_granted, can_delegate
)
select role_name, capability_key, true, false
from unnest(array[
  'admin', 'senior_mechanical_engineer', 'project_manager',
  'workshop_in_charge', 'document_controller'
]) as role_name
cross join unnest(array[
  'view_project_accounts', 'view_project_commercial_values',
  'confirm_billing_progress', 'prepare_client_claim'
]) as capability_key
on conflict (role_name, capability_key) do update
set is_granted = true,
    updated_at = clock_timestamp();

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
  return p_capability_key in (
    'view_project_accounts', 'view_project_commercial_values',
    'confirm_billing_progress', 'prepare_client_claim',
    'export_accounts_registers', 'configure_project_commercials'
  );
end;
$$;
