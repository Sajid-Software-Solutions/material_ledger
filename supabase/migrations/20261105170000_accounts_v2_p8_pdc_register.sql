-- R39 Accounts Workspace V2 — P8: project-wide cheque (PDC) register read
--
-- v1_list_project_client_pdcs returns every client post-dated cheque for a
-- project (one row per cheque, current state) joined to its invoice reference,
-- so the Invoices & payments tab can render a standalone cheque register with
-- the In-hand -> Deposited -> Cleared/Bounced lifecycle. The PDC lifecycle
-- transitions themselves reuse the existing v1_transition_client_pdc command.
--
-- Cheques are commercial, so this requires view_project_commercial_values
-- (and view_project_accounts); amounts are decimal strings. Additive,
-- accounts-only, read-only.

create or replace function public.v1_list_project_client_pdcs(p_project_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_project public.v1_projects%rowtype;
  v_pdcs jsonb;
begin
  if auth.uid() is null or p_project_id is null
     or not public.v1_current_actor_is_active() then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
  end if;
  if not public.v1_current_user_has_capability('view_project_accounts', p_project_id)
     or not public.v1_current_user_has_capability(
       'view_project_commercial_values', p_project_id) then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
  end if;
  select * into v_project from public.v1_projects where id = p_project_id;
  if not found then
    raise exception 'R39_ACCOUNTS_PROJECT_NOT_FOUND' using errcode = 'P0002';
  end if;

  select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'pdc_id', pdc.id,
          'invoice_id', pdc.invoice_id,
          'invoice_reference', inv.invoice_reference,
          'cheque_number', pdc.cheque_number,
          'cheque_date', pdc.cheque_date,
          'received_date', pdc.received_date,
          'bank_name', pdc.bank_name,
          'amount', pdc.amount::text,
          'status', pdc.status,
          'action_required', pdc.action_required,
          'record_version', pdc.record_version
        )
        order by pdc.cheque_date desc, pdc.created_at desc
      ),
      '[]'::jsonb
    )
    into v_pdcs
  from public.v1_accounts_client_pdcs pdc
  join public.v1_accounts_client_invoices inv on inv.id = pdc.invoice_id
  where pdc.project_id = p_project_id;

  return jsonb_build_object(
    'schema_version', 1,
    'project_id', v_project.id,
    'pdcs', v_pdcs
  );
end;
$$;

revoke all on function public.v1_list_project_client_pdcs(uuid) from public, anon;
grant execute on function public.v1_list_project_client_pdcs(uuid)
  to authenticated, service_role;
