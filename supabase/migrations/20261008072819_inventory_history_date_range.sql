-- Additive date-filtered history. Old clients retain their original RPC.
-- Rollback client first; no data changes or destructive rollback required.
begin;
create or replace function public.v1_inventory_movement_page_v2(
  p_item_id uuid default null, p_search text default null,
  p_kind text default 'all', p_before_at timestamptz default null,
  p_before_id uuid default null, p_limit integer default 50,
  p_from_at timestamptz default null, p_until_at timestamptz default null
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_rows jsonb; v_limit integer := greatest(1, least(coalesce(p_limit,50),500));
begin
  if not public.v1_can_view_inventory() then
    raise exception 'V1_INVENTORY_WORKSPACE_DENIED' using errcode='42501';
  end if;
  if p_kind not in ('all','stockIn','stockOut','dispatch','materialReturn') or
     ((p_before_at is null) <> (p_before_id is null)) or
     (p_from_at is not null and p_until_at is not null and p_from_at >= p_until_at) then
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
    where (p_from_at is null or m.created_at >= p_from_at)
      and (p_until_at is null or m.created_at < p_until_at)
      and (p_item_id is null or m.inventory_item_id=p_item_id)
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
revoke all on function public.v1_inventory_movement_page_v2(uuid,text,text,timestamptz,uuid,integer,timestamptz,timestamptz) from public,anon;
grant execute on function public.v1_inventory_movement_page_v2(uuid,text,text,timestamptz,uuid,integer,timestamptz,timestamptz) to authenticated;

commit;
