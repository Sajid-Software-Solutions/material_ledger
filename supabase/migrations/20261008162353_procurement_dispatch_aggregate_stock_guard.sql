-- Protect shared stock across all lines of a Project dispatch, including
-- replacement lines with consumed reservations. No data rewrite or backfill.
-- Rollback: restore the prior function only after resolving the stock risk;
-- existing movements, reservations and immutable documents must be retained.
begin;

CREATE OR REPLACE FUNCTION public.v1_dispatch_materials(p_payload jsonb, p_idempotency_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
  v_role text := public.v1_current_role();
  v_request_id uuid;
  v_expected_version integer;
  v_dispatch_date date;
  v_driver_name text;
  v_vehicle_reference text;
  v_delivery_reference text;
  v_lines jsonb;
  v_request public.v1_material_requests%rowtype;
  v_existing_response jsonb;
  v_before jsonb;
  v_response jsonb;
  v_state_summary jsonb;
  v_dispatch_id uuid;
  v_dispatch_number text;
  v_sequence integer;
  v_line jsonb;
  v_request_line_id uuid;
  v_dispatch_qty numeric(18, 4);
  v_line_count integer;
  v_item_id uuid;
  v_approved_qty numeric(18, 4);
  v_good_qty numeric(18, 4);
  v_in_transit_qty numeric(18, 4);
  v_source_kind text;
  v_arrangement_line_id uuid;
  v_external_supplier text;
  v_item_description text;
  v_brand_origin text;
  v_unit text;
  v_on_hand_qty numeric(18, 4);
  v_other_reserved_qty numeric(18, 4);
  v_reservation public.v1_inventory_reservations%rowtype;
  v_reservation_remaining numeric(18, 4);
  v_consume_qty numeric(18, 4);
  v_dispatch_line_id uuid;
begin
  perform public.v1_assert_object_keys(
    p_payload,
    array['request_id', 'expected_version', 'dispatch_date', 'delivery_reference', 'driver_name',
      'vehicle_reference', 'lines'],
    'dispatch_materials'
  );
  v_request_id := nullif(btrim(coalesce(p_payload ->> 'request_id', '')), '')::uuid;
  v_expected_version := nullif(p_payload ->> 'expected_version', '')::integer;
  v_dispatch_date := nullif(p_payload ->> 'dispatch_date', '')::date;
  v_delivery_reference := nullif(btrim(coalesce(p_payload ->> 'delivery_reference', '')), '');
  v_driver_name := nullif(btrim(coalesce(p_payload ->> 'driver_name', '')), '');
  v_vehicle_reference := nullif(btrim(coalesce(p_payload ->> 'vehicle_reference', '')), '');
  v_lines := coalesce(p_payload -> 'lines', '[]'::jsonb);
  if v_request_id is null or v_expected_version is null or v_expected_version < 1
    or v_dispatch_date is null or v_delivery_reference is null or jsonb_typeof(v_lines) <> 'array' then
    raise exception 'V1_DISPATCH_PAYLOAD_INVALID' using errcode = '22023';
  end if;
  select * into v_request from public.v1_material_requests request_record
  where request_record.id = v_request_id for update;
  if not found or not public.v1_can_dispatch_material_request(v_request_id) then
    raise exception 'V1_DISPATCH_DENIED' using errcode = '42501';
  end if;
  v_existing_response := public.v1_idempotency_get_or_claim(
    'v1_dispatch_materials', p_idempotency_key, p_payload
  );
  if v_existing_response is not null then return v_existing_response; end if;
  if v_request.state not in ('approved', 'partially_dispatched', 'partially_received')
    or v_request.record_version <> v_expected_version then
    raise exception 'V1_DISPATCH_STATE_OR_VERSION_INVALID' using errcode = '40001';
  end if;
  select count(*) into v_line_count from jsonb_array_elements(v_lines);
  if v_line_count = 0 or (
    select count(distinct nullif(btrim(coalesce(value ->> 'request_line_id', '')), '')::uuid)
    from jsonb_array_elements(v_lines)
  ) <> v_line_count then
    raise exception 'V1_DISPATCH_LINES_INVALID' using errcode = '22023';
  end if;

  -- All item locks use a deterministic ordering so competing dispatches on
  -- different requests cannot over-supply or deadlock each other.
  for v_item_id in
    select distinct arrangement_line.inventory_item_id
    from jsonb_array_elements(v_lines) line_json
    join public.v1_material_request_line_approvals approval
      on approval.request_line_id = nullif(
        btrim(coalesce(line_json.value ->> 'request_line_id', '')), ''
      )::uuid
    join public.v1_procurement_arrangement_lines arrangement_line
      on arrangement_line.id = approval.arrangement_line_id
    where arrangement_line.source_kind = 'warehouse'
    order by arrangement_line.inventory_item_id
  loop
    perform 1 from public.v1_inventory_balances balance
    join public.v1_inventory_items item on item.id = balance.inventory_item_id
    where balance.inventory_item_id = v_item_id and item.is_active
    for update of balance;
    if not found then
      raise exception 'V1_DISPATCH_INVENTORY_ITEM_INVALID' using errcode = '22023';
    end if;
    perform 1 from public.v1_inventory_reservations reservation
    where reservation.inventory_item_id = v_item_id
      and reservation.request_id = v_request.id
    order by reservation.id for update;
  end loop;

  -- Validate the complete payload before generating a document number or
  -- moving any stock.
  for v_line in select value from jsonb_array_elements(v_lines)
  loop
    perform public.v1_assert_object_keys(
      v_line, array['request_line_id', 'dispatch_qty'], 'dispatch_line'
    );
    v_request_line_id := nullif(btrim(coalesce(
      v_line ->> 'request_line_id', ''
    )), '')::uuid;
    v_dispatch_qty := nullif(v_line ->> 'dispatch_qty', '')::numeric(18, 4);
    if v_request_line_id is null or v_dispatch_qty is null or v_dispatch_qty <= 0 then
      raise exception 'V1_DISPATCH_LINE_INVALID' using errcode = '22023';
    end if;
    select approval.approved_qty, arrangement_line.source_kind,
        arrangement_line.id, arrangement_line.inventory_item_id,
        arrangement_line.external_supplier, request_line.item_description,
        request_line.brand_origin, request_line.unit
      into v_approved_qty, v_source_kind, v_arrangement_line_id, v_item_id,
        v_external_supplier, v_item_description, v_brand_origin, v_unit
    from public.v1_material_request_line_approvals approval
    join public.v1_procurement_arrangement_lines arrangement_line
      on arrangement_line.id = approval.arrangement_line_id
    join public.v1_material_request_lines request_line
      on request_line.id = approval.request_line_id
    where approval.request_line_id = v_request_line_id
      and request_line.request_id = v_request.id;
    if not found or v_approved_qty <= 0 then
      raise exception 'V1_DISPATCH_LINE_NOT_APPROVED' using errcode = '22023';
    end if;
    select coalesce(sum(review_line.good_qty), 0) into v_good_qty
    from public.v1_receipt_review_lines review_line
    join public.v1_receipt_reviews review on review.id = review_line.receipt_review_id
    join public.v1_material_dispatch_lines prior_dispatch_line
      on prior_dispatch_line.id = review_line.dispatch_line_id
    where review.state = 'confirmed'
      and prior_dispatch_line.request_line_id = v_request_line_id;
    select coalesce(sum(prior_dispatch_line.dispatched_qty), 0) into v_in_transit_qty
    from public.v1_material_dispatch_lines prior_dispatch_line
    join public.v1_material_dispatches prior_dispatch
      on prior_dispatch.id = prior_dispatch_line.dispatch_id
    where prior_dispatch.state = 'receipt_pending'
      and prior_dispatch_line.request_line_id = v_request_line_id;
    if v_dispatch_qty > v_approved_qty - v_good_qty - v_in_transit_qty then
      raise exception 'V1_DISPATCH_APPROVED_CAP_EXCEEDED' using errcode = '22023';
    end if;
    if v_source_kind = 'warehouse' then
      select balance.on_hand_qty into v_on_hand_qty
      from public.v1_inventory_balances balance
      where balance.inventory_item_id = v_item_id;
      select coalesce(sum(reservation.reserved_qty - reservation.consumed_qty), 0)
        into v_other_reserved_qty
      from public.v1_inventory_reservations reservation
      where reservation.inventory_item_id = v_item_id
        and (reservation.request_kind <> 'project'
          or reservation.request_id <> v_request.id)
        and reservation.state in ('active', 'partially_consumed');
      if v_on_hand_qty - v_other_reserved_qty < v_dispatch_qty then
        raise exception 'V1_DISPATCH_STOCK_CAP_EXCEEDED' using errcode = '22023';
      end if;
    end if;
  end loop;

  -- Every payload line is valid above. Validate each item's TOTAL once while
  -- holding its balance lock. Own Project reservations are reusable; all other
  -- Project and Company reservations remain protected, including ID collisions.
  for v_line in
    select jsonb_build_object('inventory_item_id', al.inventory_item_id,
      'dispatch_qty', sum((j.value ->> 'dispatch_qty')::numeric(18,4)))
    from jsonb_array_elements(v_lines) j
    join public.v1_material_request_line_approvals approval
      on approval.request_line_id = (j.value ->> 'request_line_id')::uuid
    join public.v1_procurement_arrangement_lines al
      on al.id = approval.arrangement_line_id
    where al.source_kind = 'warehouse'
    group by al.inventory_item_id
  loop
    v_item_id := (v_line ->> 'inventory_item_id')::uuid;
    v_dispatch_qty := (v_line ->> 'dispatch_qty')::numeric(18,4);
    select on_hand_qty into v_on_hand_qty
    from public.v1_inventory_balances where inventory_item_id = v_item_id;
    select coalesce(sum(reserved_qty - consumed_qty), 0)
      into v_other_reserved_qty
    from public.v1_inventory_reservations
    where inventory_item_id = v_item_id
      and (request_kind <> 'project' or request_id <> v_request.id)
      and state in ('active', 'partially_consumed');
    if v_on_hand_qty - v_other_reserved_qty < v_dispatch_qty then
      raise exception 'V1_DISPATCH_STOCK_CAP_EXCEEDED' using errcode = '22023';
    end if;
  end loop;

  v_before := public.v1_logistics_workspace_projection(v_request.id);
  insert into public.v1_dispatch_reference_counters (
    project_id, next_dispatch_sequence, updated_at
  ) values (v_request.project_id, 2, clock_timestamp())
  on conflict (project_id) do update set
    next_dispatch_sequence = public.v1_dispatch_reference_counters.next_dispatch_sequence + 1,
    updated_at = clock_timestamp()
  returning next_dispatch_sequence - 1 into v_sequence;
  select project_ref || '-DSP' || lpad(v_sequence::text, 3, '0')
    into v_dispatch_number
  from public.v1_projects where id = v_request.project_id;
  insert into public.v1_material_dispatches (
    request_id, project_id, dispatch_number, dispatch_date, delivery_reference, driver_name,
    vehicle_reference, state, dispatched_by_auth_user_id, dispatched_by_role
  ) values (
    v_request.id, v_request.project_id, v_dispatch_number, v_dispatch_date,
    v_delivery_reference, v_driver_name, v_vehicle_reference, 'receipt_pending', v_actor, v_role
  ) returning id into v_dispatch_id;

  for v_line in select value from jsonb_array_elements(v_lines)
  loop
    v_request_line_id := (v_line ->> 'request_line_id')::uuid;
    v_dispatch_qty := (v_line ->> 'dispatch_qty')::numeric(18, 4);
    select approval.approved_qty, arrangement_line.source_kind,
        arrangement_line.id, arrangement_line.inventory_item_id,
        arrangement_line.external_supplier, request_line.item_description,
        request_line.brand_origin, request_line.unit
      into v_approved_qty, v_source_kind, v_arrangement_line_id, v_item_id,
        v_external_supplier, v_item_description, v_brand_origin, v_unit
    from public.v1_material_request_line_approvals approval
    join public.v1_procurement_arrangement_lines arrangement_line
      on arrangement_line.id = approval.arrangement_line_id
    join public.v1_material_request_lines request_line
      on request_line.id = approval.request_line_id
    where approval.request_line_id = v_request_line_id;
    insert into public.v1_material_dispatch_lines (
      dispatch_id, request_line_id, arrangement_line_id, source_kind,
      inventory_item_id, external_supplier, item_description, brand_origin,
      unit, approved_qty_snapshot, dispatched_qty
    ) values (
      v_dispatch_id, v_request_line_id, v_arrangement_line_id, v_source_kind,
      v_item_id, v_external_supplier, v_item_description, v_brand_origin,
      v_unit, v_approved_qty, v_dispatch_qty
    ) returning id into v_dispatch_line_id;
    if v_source_kind = 'warehouse' then
      select * into v_reservation from public.v1_inventory_reservations reservation
      where reservation.arrangement_line_id = v_arrangement_line_id
      for update;
      if not found then
        raise exception 'V1_DISPATCH_RESERVATION_NOT_FOUND' using errcode = '22023';
      end if;
      v_reservation_remaining := v_reservation.reserved_qty - v_reservation.consumed_qty;
      v_consume_qty := least(v_dispatch_qty, greatest(v_reservation_remaining, 0));
      if v_consume_qty > 0 then
        update public.v1_inventory_reservations
           set consumed_qty = consumed_qty + v_consume_qty,
               state = case
                 when consumed_qty + v_consume_qty >= reserved_qty then 'consumed'
                 else 'partially_consumed'
               end,
               updated_at = clock_timestamp()
         where id = v_reservation.id;
      end if;
      select on_hand_qty into v_on_hand_qty from public.v1_inventory_balances
      where inventory_item_id = v_item_id;
      update public.v1_inventory_balances
         set on_hand_qty = on_hand_qty - v_dispatch_qty,
             record_version = record_version + 1,
             updated_at = clock_timestamp()
       where inventory_item_id = v_item_id;
      insert into public.v1_inventory_movements (
        inventory_item_id, movement_type, quantity_delta, on_hand_after_qty,
        source_entity_type, source_entity_id, reason, actor_auth_user_id,
        idempotency_key
      ) values (
        v_item_id, 'dispatch', -v_dispatch_qty, v_on_hand_qty - v_dispatch_qty,
        'material_dispatch_line', v_dispatch_line_id,
        'Dispatch ' || v_dispatch_number, v_actor, p_idempotency_key
      );
    end if;
  end loop;
  v_state_summary := public.v1_refresh_material_request_logistics_state(v_request.id);
  insert into public.v1_notifications (
    recipient_auth_user_id, event_code, entity_type, entity_id, project_id
  )
  select distinct member.member_auth_user_id, 'receipt_review_required',
    'material_dispatch', v_dispatch_id, v_request.project_id
  from public.v1_project_members member
  join public.v1_profiles profile on profile.auth_user_id = member.member_auth_user_id
  where member.project_id = v_request.project_id
    and member.project_role in ('project_engineer', 'site_engineer')
    and member.effective_from <= clock_timestamp()
    and (member.effective_to is null or member.effective_to > clock_timestamp())
    and profile.is_active;
  v_response := public.v1_logistics_workspace_projection(v_request.id);
  perform public.v1_write_audit_event(
    'materials_dispatched', 'material_dispatch', v_dispatch_id, v_request.project_id,
    v_before,
    jsonb_build_object(
      'dispatch_number', v_dispatch_number,
      'line_count', v_line_count,
      'request_state', v_state_summary ->> 'state',
      'request_record_version', v_expected_version + 1
    ), null, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_dispatch_materials', p_idempotency_key, v_response
  );
  return v_response;
end;
$function$;

CREATE OR REPLACE FUNCTION public.v1_dispatch_company_materials(p_payload jsonb, p_idempotency_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid:=auth.uid(); v_request_id uuid; v_expected integer; v_lines jsonb;
  v_request public.v1_company_material_requests%rowtype; v_existing jsonb; v_line jsonb;
  v_supply uuid; v_qty numeric(18,4); v_supply_row public.v1_company_material_supply_lines%rowtype;
  v_dispatched numeric(18,4); v_good numeric(18,4); v_transit numeric(18,4);
  v_on_hand numeric(18,4); v_other_reserved numeric(18,4); v_res record;
  v_consume numeric(18,4); v_item_id uuid; v_dispatch uuid; v_dispatch_line uuid; v_seq integer;
begin
  if v_actor is null or not public.v1_current_actor_is_active()
    or public.v1_current_role()<>'procurement' then
    raise exception 'V1_COMPANY_DISPATCH_DENIED' using errcode='42501'; end if;
  perform public.v1_assert_object_keys(p_payload,array['request_id','expected_version','lines'],
    'company_dispatch');
  begin v_request_id:=(p_payload->>'request_id')::uuid;
    v_expected:=(p_payload->>'expected_version')::integer;
  exception when others then raise exception 'V1_COMPANY_DISPATCH_INVALID' using errcode='22023'; end;
  v_lines:=p_payload->'lines';
  if jsonb_typeof(v_lines)<>'array' or jsonb_array_length(v_lines)=0 then
    raise exception 'V1_COMPANY_DISPATCH_INVALID' using errcode='22023'; end if;
  v_existing:=public.v1_idempotency_get_or_claim('v1_dispatch_company_materials',p_idempotency_key,p_payload);
  if v_existing is not null then return public.v1_company_material_request_projection(v_request_id); end if;
  select * into v_request from public.v1_company_material_requests where id=v_request_id for update;
  if not found or v_request.state not in ('ready_for_delivery','partially_dispatched','partially_received')
    or v_request.record_version<>v_expected then
    raise exception 'V1_COMPANY_DISPATCH_STATE_OR_VERSION_INVALID' using errcode='40001'; end if;
  if (select count(*) from jsonb_array_elements(v_lines)) <>
    (select count(distinct value->>'supply_line_id') from jsonb_array_elements(v_lines)) then
    raise exception 'V1_COMPANY_DISPATCH_LINE_INVALID' using errcode='22023';
  end if;
  -- Validate ownership before taking the shared warehouse locks, always in the
  -- same inventory-ID order as Project dispatch and arrangement commands.
  for v_supply in select distinct (value->>'supply_line_id')::uuid
    from jsonb_array_elements(v_lines) order by 1 loop
    if not exists(select 1 from public.v1_company_material_supply_lines sl
      join public.v1_company_material_supply_plans sp on sp.id=sl.plan_id and sp.is_current
      where sl.id=v_supply and sp.request_id=v_request_id) then
      raise exception 'V1_COMPANY_DISPATCH_LINE_INVALID' using errcode='22023';
    end if;
  end loop;
  for v_item_id in select distinct sl.inventory_item_id
    from jsonb_array_elements(v_lines) j
    join public.v1_company_material_supply_lines sl on sl.id=(j.value->>'supply_line_id')::uuid
    where sl.source_kind='warehouse' order by sl.inventory_item_id loop
    perform 1 from public.v1_inventory_balances where inventory_item_id=v_item_id for update;
  end loop;
  for v_line in select value from jsonb_array_elements(v_lines) loop
    perform public.v1_assert_object_keys(v_line,array['supply_line_id','dispatch_qty'],'company_dispatch_line');
    begin v_supply:=(v_line->>'supply_line_id')::uuid;
      v_qty:=(v_line->>'dispatch_qty')::numeric(18,4);
    exception when others then raise exception 'V1_COMPANY_DISPATCH_LINE_INVALID' using errcode='22023'; end;
    select sl.* into v_supply_row from public.v1_company_material_supply_lines sl
      join public.v1_company_material_supply_plans sp on sp.id=sl.plan_id and sp.is_current
      where sl.id=v_supply and sp.request_id=v_request_id;
    select coalesce(sum(dl.dispatched_qty),0) into v_dispatched
      from public.v1_company_material_dispatch_lines dl where dl.supply_line_id=v_supply;
    select coalesce(sum(rl.good_qty),0) into v_good from public.v1_company_material_receipt_lines rl
      where rl.request_line_id=v_supply_row.request_line_id;
    select coalesce(sum(dl.dispatched_qty),0) into v_transit
      from public.v1_company_material_dispatch_lines dl join public.v1_company_material_dispatches d
      on d.id=dl.dispatch_id where dl.request_line_id=v_supply_row.request_line_id and d.state='receipt_pending';
    if not found or v_qty is null or v_qty<=0 or v_dispatched+v_qty>v_supply_row.arranged_qty
      or v_good+v_transit+v_qty>(select requested_qty from public.v1_company_material_request_lines
        where id=v_supply_row.request_line_id) then
      raise exception 'V1_COMPANY_DISPATCH_QUANTITY_INVALID' using errcode='22023'; end if;
    if v_supply_row.source_kind='warehouse' then
      select on_hand_qty into v_on_hand from public.v1_inventory_balances
        where inventory_item_id=v_supply_row.inventory_item_id;
      select coalesce(sum(reserved_qty-consumed_qty),0) into v_other_reserved
        from public.v1_inventory_reservations where inventory_item_id=v_supply_row.inventory_item_id
        and (request_kind<>'company' or request_id<>v_request_id) and state in ('active','partially_consumed');
      if v_on_hand-v_other_reserved<v_qty then
        raise exception 'V1_COMPANY_DISPATCH_STOCK_CAP_EXCEEDED' using errcode='22023'; end if;
    end if;
  end loop;
  for v_line in select jsonb_build_object('inventory_item_id',sl.inventory_item_id,
      'dispatch_qty',sum((j.value->>'dispatch_qty')::numeric(18,4)))
    from jsonb_array_elements(v_lines) j
    join public.v1_company_material_supply_lines sl on sl.id=(j.value->>'supply_line_id')::uuid
    where sl.source_kind='warehouse' group by sl.inventory_item_id loop
    v_item_id:=(v_line->>'inventory_item_id')::uuid;
    select on_hand_qty into v_on_hand from public.v1_inventory_balances where inventory_item_id=v_item_id;
    select coalesce(sum(reserved_qty-consumed_qty),0) into v_other_reserved
      from public.v1_inventory_reservations where inventory_item_id=v_item_id
        and (request_kind<>'company' or request_id<>v_request_id)
        and state in ('active','partially_consumed');
    if v_on_hand-v_other_reserved<(v_line->>'dispatch_qty')::numeric(18,4) then
      raise exception 'V1_COMPANY_DISPATCH_STOCK_CAP_EXCEEDED' using errcode='22023';
    end if;
  end loop;
  update public.v1_company_material_dispatch_reference_counter set next_sequence=next_sequence+1
    where singleton returning next_sequence-1 into v_seq;
  insert into public.v1_company_material_dispatches(request_id,dispatch_number,
    dispatched_by_auth_user_id,idempotency_key) values(v_request_id,
    'CM-DSP-'||lpad(v_seq::text,7,'0'),v_actor,p_idempotency_key) returning id into v_dispatch;
  for v_line in select value from jsonb_array_elements(v_lines) loop
    v_supply:=(v_line->>'supply_line_id')::uuid; v_qty:=(v_line->>'dispatch_qty')::numeric(18,4);
    select * into v_supply_row from public.v1_company_material_supply_lines where id=v_supply;
    insert into public.v1_company_material_dispatch_lines(dispatch_id,supply_line_id,request_line_id,
      inventory_item_id,source_kind,dispatched_qty) values(v_dispatch,v_supply,
      v_supply_row.request_line_id,v_supply_row.inventory_item_id,v_supply_row.source_kind,v_qty)
      returning id into v_dispatch_line;
    if v_supply_row.source_kind='warehouse' then
      select * into v_res from public.v1_inventory_reservations where request_kind='company'
        and company_supply_line_id=v_supply and state in ('active','partially_consumed') for update;
      v_consume:=least(v_qty,v_res.reserved_qty-v_res.consumed_qty);
      update public.v1_inventory_reservations set consumed_qty=consumed_qty+v_consume,
        state=case when consumed_qty+v_consume=reserved_qty then 'consumed' else 'partially_consumed' end,
        updated_at=clock_timestamp() where id=v_res.id;
      update public.v1_inventory_balances set on_hand_qty=on_hand_qty-v_qty,
        record_version=record_version+1,updated_at=clock_timestamp()
        where inventory_item_id=v_supply_row.inventory_item_id returning on_hand_qty into v_on_hand;
      insert into public.v1_inventory_movements(inventory_item_id,movement_type,quantity_delta,
        on_hand_after_qty,source_entity_type,source_entity_id,reason,actor_auth_user_id,idempotency_key)
        values(v_supply_row.inventory_item_id,'dispatch',-v_qty,v_on_hand,
        'company_material_dispatch_line',v_dispatch_line,'Company material dispatch',v_actor,p_idempotency_key);
    end if;
  end loop;
  update public.v1_company_material_requests set state='receipt_pending',
    record_version=record_version+1,updated_at=clock_timestamp() where id=v_request_id;
  insert into public.v1_company_material_request_events(request_id,event_type,actor_auth_user_id,
    actor_exact_role,data,idempotency_key) values(v_request_id,'company_material_dispatched',
    v_actor,'procurement',jsonb_build_object('dispatch_id',v_dispatch),p_idempotency_key);
  perform public.v1_complete_idempotency('v1_dispatch_company_materials',p_idempotency_key,
    public.v1_company_material_request_projection(v_request_id));
  return public.v1_company_material_request_projection(v_request_id);
end $function$;

commit;
