-- Additive read-projection correction. No records or quantity semantics change.
-- Rollback: restore the previous projection; company reservations then disappear
-- from the register again. Do not remove shared reservations or movements.
begin;
CREATE OR REPLACE FUNCTION public.v1_inventory_workspace_projection(p_search text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_search text := nullif(lower(btrim(coalesce(p_search, ''))), '');
begin
  if not public.v1_can_view_inventory() then
    raise exception 'V1_INVENTORY_WORKSPACE_DENIED' using errcode = '42501';
  end if;
  return (
    with projected_items as materialized (
      select
        item.id,
        item.is_active,
        item.category_id,
        lower(item.item_description) as description_order,
        lower(coalesce(item.brand_origin, '')) as brand_order,
        public.v1_inventory_item_projection(item.id) as item_projection
      from public.v1_inventory_items item
      left join public.v1_inventory_categories category
        on category.id = item.category_id
      where v_search is null
        or lower(coalesce(item.item_code, '')) like '%' || v_search || '%'
        or lower(item.item_description) like '%' || v_search || '%'
        or lower(coalesce(item.brand_origin, '')) like '%' || v_search || '%'
        or lower(item.unit) like '%' || v_search || '%'
        or lower(coalesce(item.location_bin, '')) like '%' || v_search || '%'
        or lower(coalesce(category.name, '')) like '%' || v_search || '%'
    ), movement_stats as (
      select inventory_item_id, count(*) movement_count, max(created_at) last_movement_at
      from public.v1_inventory_movements group by inventory_item_id
    ), enriched_items as (
      select projected_items.*,
        projected_items.item_projection || jsonb_build_object(
          'movement_count', coalesce(stats.movement_count,0),
          'last_movement_at', stats.last_movement_at
        ) as item
      from projected_items
      left join movement_stats stats on stats.inventory_item_id=projected_items.id
    )
    select jsonb_build_object(
      'items', coalesce((
        select jsonb_agg(item order by description_order, brand_order)
        from enriched_items
      ), '[]'::jsonb),
      'categories', coalesce((
        select jsonb_agg(
          public.v1_inventory_category_projection(category.id)
          order by lower(category.name)
        )
        from public.v1_inventory_categories category
        where category.is_active
      ), '[]'::jsonb),
      'recent_movements', coalesce((
        select jsonb_agg(movement_record order by created_at desc)
        from (
          select
            movement.created_at,
            jsonb_build_object(
              'id', movement.id,
              'inventory_item_id', movement.inventory_item_id,
              'item_code', item.item_code,
              'item_description', item.item_description,
              'unit', item.unit,
              'movement_type', movement.movement_type,
              'quantity_delta', movement.quantity_delta::text,
              'on_hand_after_qty', movement.on_hand_after_qty::text,
              'source_entity_type', movement.source_entity_type,
              'source_entity_id', movement.source_entity_id,
              'reason', movement.reason,
              'actor_display_name', public.v1_safe_profile_display_name(
                profile.display_name, profile.auth_user_id
              ),
              'created_at', movement.created_at
            ) as movement_record
          from public.v1_inventory_movements movement
          join public.v1_inventory_items item on item.id = movement.inventory_item_id
          join public.v1_profiles profile on profile.auth_user_id = movement.actor_auth_user_id
          order by movement.created_at desc
          limit 100
        ) recent
      ), '[]'::jsonb),
      'reservations', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', reservation.id,
          'inventory_item_id', reservation.inventory_item_id,
          'item_code', item.item_code,
          'item_description', item.item_description,
          'unit', item.unit,
          'request_id', coalesce(request_record.id, company_request.id),
          'request_kind', reservation.request_kind,
          'request_number', coalesce(request_record.request_number, company_request.request_number),
          'project_name', coalesce(project.name, company_unit.display_name),
          'scope_name', coalesce(scope.name, company_category.display_name),
          'reserved_qty', reservation.reserved_qty::text,
          'remaining_qty', (reservation.reserved_qty - reservation.consumed_qty)::text,
          'state', reservation.state,
          'created_at', reservation.created_at
        ) order by reservation.created_at desc)
        from public.v1_inventory_reservations reservation
        join public.v1_inventory_items item on item.id = reservation.inventory_item_id
        left join public.v1_material_requests request_record on request_record.id = reservation.request_id
          and reservation.request_kind = 'project'
        left join public.v1_projects project on project.id = request_record.project_id
        left join public.v1_project_scopes scope on scope.id = request_record.scope_id
        left join public.v1_company_material_requests company_request
          on company_request.id = reservation.request_id and reservation.request_kind = 'company'
        left join public.v1_company_material_request_units company_unit
          on company_unit.id = company_request.responsible_unit_id
        left join public.v1_company_material_request_categories company_category
          on company_category.id = company_request.category_id
        where reservation.state in ('active', 'partially_consumed')
      ), '[]'::jsonb),
      'summary', jsonb_build_object(
        'total_active_items', (
          select count(*) from enriched_items where is_active
        ),
        'low_stock_count', (
          select count(*) from enriched_items
          where is_active
            and nullif(item_projection ->> 'minimum_stock', '') is not null
            and (item_projection ->> 'available_qty')::numeric > 0
            and (item_projection ->> 'available_qty')::numeric
              <= (item_projection ->> 'minimum_stock')::numeric
        ),
        'out_of_stock_count', (
          select count(*) from enriched_items
          where is_active and (item_projection ->> 'available_qty')::numeric <= 0
        ),
        'reserved_count', (
          select count(*) from enriched_items
          where is_active and (item_projection ->> 'reserved_qty')::numeric > 0
        ),
        'incoming_count', 0
      )
    )
  );
end;
$function$;
revoke all on function public.v1_inventory_workspace_projection(text) from public, anon;
grant execute on function public.v1_inventory_workspace_projection(text) to authenticated;
-- The global history page sorts by time and ID; retain the existing per-item index.
create index if not exists v1_inventory_movements_created_id_idx
  on public.v1_inventory_movements(created_at desc,id desc);
-- Bounded, role-safe keyset history. No commercial fields or record mutation.
create or replace function public.v1_inventory_movement_page(
  p_item_id uuid default null, p_search text default null,
  p_kind text default 'all', p_before_at timestamptz default null,
  p_before_id uuid default null, p_limit integer default 50
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_rows jsonb; v_limit integer := greatest(1, least(coalesce(p_limit,50),500));
begin
  if not public.v1_can_view_inventory() then
    raise exception 'V1_INVENTORY_WORKSPACE_DENIED' using errcode='42501';
  end if;
  if p_kind not in ('all','stockIn','stockOut','dispatch','materialReturn') or
     ((p_before_at is null) <> (p_before_id is null)) then
    raise exception 'V1_INVALID_INPUT' using errcode='22023';
  end if;
  select coalesce(jsonb_agg(row_json order by created_at desc, id desc),'[]'::jsonb)
  into v_rows from (
    select m.id, m.created_at, jsonb_build_object(
      'id',m.id,'inventory_item_id',m.inventory_item_id,'item_code',i.item_code,
      'item_description',i.item_description,'unit',i.unit,
      'movement_type',m.movement_type,'quantity_delta',m.quantity_delta::text,
      'on_hand_after_qty',m.on_hand_after_qty::text,'source_entity_type',m.source_entity_type,
      'source_entity_id',m.source_entity_id,'reason',m.reason,
      'actor_display_name',public.v1_safe_profile_display_name(p.display_name,p.auth_user_id),
      'created_at',m.created_at) row_json
    from public.v1_inventory_movements m
    join public.v1_inventory_items i on i.id=m.inventory_item_id
    join public.v1_profiles p on p.auth_user_id=m.actor_auth_user_id
    where (p_item_id is null or m.inventory_item_id=p_item_id)
      and (p_before_at is null or (m.created_at,m.id)<(p_before_at,p_before_id))
      and (p_kind='all' or (p_kind='stockIn' and m.quantity_delta>0)
        or (p_kind='stockOut' and m.quantity_delta<0)
        or (p_kind='dispatch' and m.movement_type like '%dispatch%')
        or (p_kind='materialReturn' and m.movement_type like '%return%'))
      and (nullif(btrim(p_search),'') is null or
        concat_ws(' ',i.item_code,i.item_description,m.reason,
          public.v1_safe_profile_display_name(p.display_name,p.auth_user_id),m.source_entity_id::text)
        ilike '%' || left(btrim(p_search),160) || '%')
    order by m.created_at desc,m.id desc limit v_limit+1
  ) selected;
  return jsonb_build_object('items', case when jsonb_array_length(v_rows)>v_limit
    then v_rows - v_limit else v_rows end,'has_more',jsonb_array_length(v_rows)>v_limit);
end $$;
revoke all on function public.v1_inventory_movement_page(uuid,text,text,timestamptz,uuid,integer) from public,anon;
grant execute on function public.v1_inventory_movement_page(uuid,text,text,timestamptz,uuid,integer) to authenticated;

create or replace function public.v1_inventory_item_workspace_v2(p_inventory_item_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_item jsonb;
begin
  if not public.v1_can_view_inventory() then
    raise exception 'V1_INVENTORY_WORKSPACE_DENIED' using errcode='42501';
  end if;
  v_item := public.v1_inventory_item_projection(p_inventory_item_id);
  if v_item is null then
    raise exception 'V1_INVENTORY_ITEM_NOT_FOUND' using errcode='22023';
  end if;
  return jsonb_build_object('item',v_item,'movements','[]'::jsonb);
end $$;
revoke all on function public.v1_inventory_item_workspace_v2(uuid) from public,anon;
grant execute on function public.v1_inventory_item_workspace_v2(uuid) to authenticated;

commit;
