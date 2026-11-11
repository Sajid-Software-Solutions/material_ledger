-- R39 Accounts — keep both owner decisions in the Accounts scope function
--
-- 20261109100000 (owner decision of 9 November 2026, PRODUCT_DECISIONS.md
-- section 35) gave Senior Mechanical Engineer, Project Manager, Workshop
-- In-Charge and Document Controller the Project Engineer's claim rights on
-- every project. 20261111120000 (owner decision of 11 November 2026, section
-- 34) then redefined v1_accounts_has_project_scope from the 7 November text,
-- so those four roles lost confirm_billing_progress and prepare_client_claim
-- and Workshop In-Charge and Document Controller lost Accounts scope entirely.
-- Their role defaults were never changed.
--
-- This definition keeps both decisions:
--   * a Project Engineer with dated membership may hold every Accounts key
--     (section 34);
--   * the four organization-wide engineering roles keep the 9 November scope
--     list, including confirm_billing_progress and prepare_client_claim
--     (section 35).
-- Everything else is as 20261111120000 defines it.
--
-- One CREATE OR REPLACE; additive and repeatable; no record changes.
-- Rollback: re-apply v1_accounts_has_project_scope from 20261111120000.

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
