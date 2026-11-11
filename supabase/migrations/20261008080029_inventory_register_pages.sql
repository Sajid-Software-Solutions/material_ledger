-- Additive bounded transport for stock and reservations. Reuses the protected
-- projection so summary/category/quantity semantics remain identical.
-- Rollback client first; retain existing functions and all stock/history data.
begin;
create or replace function public.v1_inventory_register_page(
  p_register text default 'stock', p_search text default null,
  p_status text default 'all', p_unit text default null,
  p_category_id uuid default null, p_offset integer default 0,
  p_limit integer default 50
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  v_workspace jsonb; v_matches jsonb; v_page jsonb; v_units jsonb;
  v_limit integer := greatest(1,least(coalesce(p_limit,50),500));
  v_offset integer := greatest(0,coalesce(p_offset,0));
begin
  if not public.v1_can_view_inventory() then
    raise exception 'V1_INVENTORY_WORKSPACE_DENIED' using errcode='42501';
  end if;
  if p_register not in ('stock','reservations') or p_status not in
    ('all','active','inactive','reserved','low','out') then
    raise exception 'V1_INVALID_INPUT' using errcode='22023';
  end if;
  v_workspace := public.v1_inventory_workspace_projection(null);
  select coalesce(jsonb_agg(unit order by unit),'[]'::jsonb) into v_units
    from (select distinct item->>'unit' unit from jsonb_array_elements(v_workspace->'items') item) units;
  if p_register='stock' then
    select coalesce(jsonb_agg(item order by lower(item->>'item_description'), item->>'id'),'[]'::jsonb)
      into v_matches from jsonb_array_elements(v_workspace->'items') item
      where (p_unit is null or item->>'unit'=p_unit)
        and (p_category_id is null or item->>'category_id'=p_category_id::text)
        and (nullif(btrim(p_search),'') is null or position(lower(btrim(p_search)) in
          lower(concat_ws(' ',item->>'item_code',item->>'item_description',item->>'brand_origin',
            item->>'unit',coalesce(item->>'category_path',item->>'category_name'),item->>'location_bin')))>0)
        and (p_status='all'
          or (p_status='active' and (item->>'is_active')::boolean)
          or (p_status='inactive' and not (item->>'is_active')::boolean)
          or (p_status='reserved' and (item->>'reserved_qty')::numeric>0)
          or (p_status='out' and (item->>'available_qty')::numeric<=0)
          or (p_status='low' and nullif(item->>'minimum_stock','') is not null
            and (item->>'available_qty')::numeric>0
            and (item->>'available_qty')::numeric<=(item->>'minimum_stock')::numeric));
  else
    select coalesce(jsonb_agg(item order by item->>'created_at' desc,item->>'id' desc),'[]'::jsonb)
      into v_matches from jsonb_array_elements(v_workspace->'reservations') item;
  end if;
  select coalesce(jsonb_agg(item order by ordinal),'[]'::jsonb) into v_page
    from jsonb_array_elements(v_matches) with ordinality as rows(item,ordinal)
    where ordinal>v_offset and ordinal<=v_offset+v_limit;
  return jsonb_build_object(
    'items',case when p_register='stock' then v_page else '[]'::jsonb end,
    'reservations',case when p_register='reservations' then v_page else '[]'::jsonb end,
    'recent_movements','[]'::jsonb,'categories',v_workspace->'categories',
    'summary',v_workspace->'summary','available_units',v_units,
    'total_matches',jsonb_array_length(v_matches), 'page_offset',v_offset,
    'has_more',v_offset+v_limit<jsonb_array_length(v_matches)
  );
end $$;
revoke all on function public.v1_inventory_register_page(text,text,text,text,uuid,integer,integer) from public,anon;
grant execute on function public.v1_inventory_register_page(text,text,text,text,uuid,integer,integer) to authenticated;
commit;
