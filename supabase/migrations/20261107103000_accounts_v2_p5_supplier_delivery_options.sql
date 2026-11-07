-- R39 Accounts Workspace V2 — P5: confirmed deliveries a supplier bill can cite
--
-- A supplier bill's three-way match needs a confirmed receipt review, and the
-- form could only ask for its database ID, which nobody can know. This read lists
-- the ones v1_accounts_supplier_delivery_snapshot would accept, so the form can
-- offer them by delivery reference.
--
-- It returns delivery references, dates and good quantities only, no commercial
-- value, to the same actors who may write a supplier bill draft.
--
-- Additive: one new read function. No table or row changes.
-- Rollback: drop function public.v1_list_supplier_bill_delivery_options(uuid).

create or replace function public.v1_list_supplier_bill_delivery_options(
  p_project_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_exact text;
  v_items jsonb;
begin
  v_exact := public.v1_accounts_require_capability(
    p_project_id, 'manage_supplier_bills'
  );
  if v_exact not in ('procurement', 'accountant', 'admin')
    or not public.v1_current_user_has_capability(
      'view_supplier_costs', p_project_id
    ) then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(option.snapshot order by option.reviewed_at desc), '[]'::jsonb)
    into v_items
  from (
    select review.reviewed_at,
      public.v1_accounts_supplier_delivery_snapshot(p_project_id, review.id) as snapshot
    from public.v1_receipt_reviews review
    join public.v1_material_dispatches dispatch on dispatch.id = review.dispatch_id
    where dispatch.project_id = p_project_id
      and review.state = 'confirmed'
    order by review.reviewed_at desc
    limit 200
  ) option
  where option.snapshot is not null;

  return jsonb_build_object(
    'schema_version', 1,
    'project_id', p_project_id,
    'deliveries', v_items
  );
end;
$$;

revoke all on function public.v1_list_supplier_bill_delivery_options(uuid)
  from public, anon;
grant execute on function public.v1_list_supplier_bill_delivery_options(uuid)
  to authenticated, service_role;
