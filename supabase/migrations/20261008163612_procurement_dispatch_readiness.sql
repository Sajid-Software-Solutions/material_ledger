-- Add the Procurement next-action fact to the existing full MR projection.
-- No status, owner, receipt or dispatch is modified. Rollback is UI fallback;
-- existing Project and Company histories remain unchanged.
begin;
create or replace function public.v1_material_request_dispatch_ready(p_request_id uuid)
returns boolean language plpgsql stable security definer set search_path='' as $$
begin
  if not public.v1_can_dispatch_material_request(p_request_id) then return false; end if;
  return exists(select 1 from public.v1_material_requests r
    join public.v1_material_request_lines l on l.request_id=r.id
    join public.v1_material_request_line_approvals a on a.request_line_id=l.id
    where r.id=p_request_id and r.state in ('approved','partially_dispatched','partially_received')
      and a.approved_qty > coalesce((select sum(rl.good_qty)
        from public.v1_receipt_review_lines rl join public.v1_receipt_reviews rv on rv.id=rl.receipt_review_id
        join public.v1_material_dispatch_lines dl on dl.id=rl.dispatch_line_id
        where rv.state='confirmed' and dl.request_line_id=l.id),0)
        + coalesce((select sum(dl.dispatched_qty)
          from public.v1_material_dispatch_lines dl join public.v1_material_dispatches d on d.id=dl.dispatch_id
          where d.state='receipt_pending' and dl.request_line_id=l.id),0));
end;
$$;
do $$ begin
  if to_regprocedure('public.v1_material_request_projection_before_procurement_readiness(uuid)') is null then
    alter function public.v1_material_request_projection(uuid)
      rename to v1_material_request_projection_before_procurement_readiness;
  end if;
end $$;
create or replace function public.v1_material_request_projection(p_request_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  result:=public.v1_material_request_projection_before_procurement_readiness(p_request_id);
  return result||jsonb_build_object('dispatch_ready',public.v1_material_request_dispatch_ready(p_request_id));
end;
$$;
revoke all on function public.v1_material_request_dispatch_ready(uuid),
  public.v1_material_request_projection_before_procurement_readiness(uuid),
  public.v1_material_request_projection(uuid) from public,anon,authenticated;
grant execute on function public.v1_material_request_projection(uuid) to authenticated;
commit;
