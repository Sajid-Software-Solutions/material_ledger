-- Shared, explicitly published sourcing facts for scheduled Project requests.
-- Separate from owner-private raw editor recovery and final arrangement facts.
-- No stock, reservation, approval, dispatch, cost or private checkpoint writes.
-- Data preservation: append-only revisions; no backfill or rewrite.
-- Rollback: stop calling these RPCs and restore the previous read projection in
-- a forward migration. Retain all revisions/audit/notifications as evidence.
begin;

create table if not exists public.v1_arrangement_sourcing_revisions (
  arrangement_id uuid not null references public.v1_procurement_arrangements(id) on delete restrict,
  revision integer not null check (revision > 0),
  request_id uuid not null references public.v1_material_requests(id) on delete restrict,
  base_request_version integer not null check (base_request_version > 0),
  base_arrangement_version integer not null check (base_arrangement_version > 0),
  lines jsonb not null check (jsonb_typeof(lines) = 'array'),
  updated_at timestamptz not null default clock_timestamp(),
  updated_by_auth_user_id uuid not null references public.v1_profiles(auth_user_id) on delete restrict,
  updated_by_display_name text not null,
  updated_by_role text not null,
  primary key (arrangement_id, revision)
);
create index if not exists v1_arrangement_sourcing_request_idx
  on public.v1_arrangement_sourcing_revisions(request_id);
create index if not exists v1_arrangement_sourcing_actor_idx
  on public.v1_arrangement_sourcing_revisions(updated_by_auth_user_id);
alter table public.v1_arrangement_sourcing_revisions enable row level security;
revoke all on public.v1_arrangement_sourcing_revisions from public, anon, authenticated;
grant select, insert on public.v1_arrangement_sourcing_revisions to service_role;

create or replace function public.v1_arrangement_sourcing_immutable()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  raise exception 'V1_ARRANGEMENT_SOURCING_HISTORY_IMMUTABLE' using errcode = '42501';
end;
$$;
drop trigger if exists v1_arrangement_sourcing_immutable on public.v1_arrangement_sourcing_revisions;
create trigger v1_arrangement_sourcing_immutable
before update or delete on public.v1_arrangement_sourcing_revisions
for each row execute function public.v1_arrangement_sourcing_immutable();

create or replace function public.v1_get_arrangement_sourcing_progress(
  p_request_id uuid, p_arrangement_id uuid default null
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  r public.v1_material_requests%rowtype;
  a public.v1_procurement_arrangements%rowtype;
  s public.v1_arrangement_sourcing_revisions%rowtype;
begin
  if auth.uid() is null or not public.v1_current_actor_is_active()
    or not public.v1_material_request_participant(p_request_id, auth.uid()) then
    raise exception 'V1_ARRANGEMENT_SOURCING_DENIED' using errcode = '42501';
  end if;
  select * into r from public.v1_material_requests where id = p_request_id;
  select * into a from public.v1_procurement_arrangements
  where request_id = p_request_id and (p_arrangement_id is null or id = p_arrangement_id)
  order by (status = 'working') desc, is_current desc, arrangement_version desc limit 1;
  if not found then return null; end if;
  select * into s from public.v1_arrangement_sourcing_revisions
  where arrangement_id = a.id order by revision desc limit 1;
  if not found then return null; end if;
  return jsonb_build_object(
    'request_id', s.request_id, 'arrangement_id', s.arrangement_id,
    'revision', s.revision, 'base_request_version', s.base_request_version,
    'base_arrangement_version', s.base_arrangement_version,
    'is_current', s.base_request_version = r.record_version
      and s.base_arrangement_version = a.record_version
      and a.status = 'working' and r.state = 'arranging'
      and r.procurement_clarification_revision = r.approved_procurement_clarification_revision,
    'updated_at', s.updated_at, 'updated_by_display_name', s.updated_by_display_name,
    'updated_by_role', s.updated_by_role, 'lines', s.lines,
    'line_count', jsonb_array_length(s.lines),
    'ready_line_count', (select count(*) from jsonb_array_elements(s.lines) j
      where (j->>'ready_qty')::numeric = (j->>'requested_qty')::numeric),
    'partial_line_count', (select count(*) from jsonb_array_elements(s.lines) j
      where (j->>'ready_qty')::numeric > 0 and (j->>'ready_qty')::numeric < (j->>'requested_qty')::numeric),
    'waiting_line_count', (select count(*) from jsonb_array_elements(s.lines) j where (j->>'ready_qty')::numeric = 0)
  );
end;
$$;

create or replace function public.v1_save_arrangement_sourcing_progress(
  p_payload jsonb, p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  r public.v1_material_requests%rowtype;
  a public.v1_procurement_arrangements%rowtype;
  request_id uuid; arrangement_id uuid; expected_revision integer; current_revision integer;
  j jsonb; normalized jsonb := '[]'::jsonb; previous jsonb; result jsonb;
  line_id uuid; item_id uuid; seen uuid[] := '{}'; ready numeric; requested numeric;
  line_unit text; source text; expected_date date; expected_text text; quantity_text text;
  inventory_qty numeric; other_reserved numeric; item_total numeric; actor_name text;
begin
  perform public.v1_assert_object_keys(p_payload,
    array['request_id','arrangement_id','expected_request_version','expected_arrangement_version','expected_revision','lines'],
    'arrangement_sourcing_progress');
  request_id := nullif(p_payload->>'request_id','')::uuid;
  arrangement_id := nullif(p_payload->>'arrangement_id','')::uuid;
  expected_revision := (p_payload->>'expected_revision')::integer;
  if not public.v1_can_arrange_material_request(request_id) then
    raise exception 'V1_ARRANGEMENT_SOURCING_DENIED' using errcode = '42501';
  end if;
  select * into r from public.v1_material_requests where id = request_id for update;
  if not found or arrangement_id is null or expected_revision is null or expected_revision < 0
    or jsonb_typeof(p_payload->'lines') is distinct from 'array'
    or octet_length(p_payload::text) > 1048576 then
    raise exception 'V1_ARRANGEMENT_SOURCING_INVALID' using errcode = '22023';
  end if;
  select * into a from public.v1_procurement_arrangements
  where id = arrangement_id and v1_procurement_arrangements.request_id = r.id for update;
  if not found then raise exception 'V1_ARRANGEMENT_SOURCING_INVALID' using errcode = '22023'; end if;
  previous := public.v1_idempotency_get_or_claim('v1_save_arrangement_sourcing_progress',p_idempotency_key,p_payload);
  if previous is not null then
    -- Return a fresh role-safe projection: a finalized/edited request must not
    -- replay a historical is_current=true snapshot to a late retry.
    return public.v1_get_arrangement_sourcing_progress(r.id,a.id);
  end if;
  if r.timing <> 'scheduled' or r.state <> 'arranging' or a.status <> 'working'
    or r.procurement_clarification_revision <> r.approved_procurement_clarification_revision then
    raise exception 'V1_ARRANGEMENT_SOURCING_STATE_INVALID' using errcode = '55000';
  end if;
  if r.record_version is distinct from (p_payload->>'expected_request_version')::integer
    or a.record_version is distinct from (p_payload->>'expected_arrangement_version')::integer then
    raise exception 'V1_ARRANGEMENT_SOURCING_BASE_CONFLICT' using errcode = '40001';
  end if;
  select coalesce(max(s.revision),0) into current_revision
  from public.v1_arrangement_sourcing_revisions s where s.arrangement_id = a.id;
  if expected_revision <> current_revision then
    raise exception 'V1_ARRANGEMENT_SOURCING_REVISION_CONFLICT' using errcode = '40001';
  end if;
  if jsonb_array_length(p_payload->'lines') <> (select count(*) from public.v1_material_request_lines where v1_material_request_lines.request_id = r.id)
    or jsonb_array_length(p_payload->'lines') > 2000 then
    raise exception 'V1_ARRANGEMENT_SOURCING_LINES_INVALID' using errcode = '22023';
  end if;
  for j in select value from jsonb_array_elements(p_payload->'lines') loop
    perform public.v1_assert_object_keys(j,array['request_line_id','ready_qty','source_kind','inventory_item_id','expected_available_date'],'arrangement_sourcing_line');
    line_id := nullif(j->>'request_line_id','')::uuid;
    if line_id is null or line_id = any(seen) then
      raise exception 'V1_ARRANGEMENT_SOURCING_LINES_INVALID' using errcode = '22023';
    end if;
    select l.requested_qty,l.unit into requested,line_unit from public.v1_material_request_lines l
      join public.v1_procurement_arrangement_lines al on al.request_line_id=l.id and al.arrangement_id=a.id
      where l.id=line_id and l.request_id=r.id;
    if not found then raise exception 'V1_ARRANGEMENT_SOURCING_LINES_INVALID' using errcode = '22023'; end if;
    seen := array_append(seen,line_id);
    quantity_text := j->>'ready_qty';
    if quantity_text is null or quantity_text !~ '^[0-9]{1,14}([.][0-9]{1,4})?$' then
      raise exception 'V1_ARRANGEMENT_SOURCING_QUANTITY_INVALID' using errcode = '22023';
    end if;
    ready := quantity_text::numeric;
    if ready > requested then raise exception 'V1_ARRANGEMENT_SOURCING_QUANTITY_INVALID' using errcode = '22023'; end if;
    source := j->>'source_kind'; item_id := nullif(j->>'inventory_item_id','')::uuid;
    if source is null or source not in ('warehouse','external_supplier')
      or (source='external_supplier' and item_id is not null)
      or (source='warehouse' and ready>0 and item_id is null) then
      raise exception 'V1_ARRANGEMENT_SOURCING_SOURCE_INVALID' using errcode = '22023';
    end if;
    if item_id is not null and not exists(select 1 from public.v1_inventory_items i
      where i.id=item_id and i.is_active and i.unit=line_unit) then
      raise exception 'V1_ARRANGEMENT_SOURCING_SOURCE_INVALID' using errcode = '22023';
    end if;
    expected_text := nullif(j->>'expected_available_date',''); expected_date := null;
    if expected_text is not null then
      if expected_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
        raise exception 'V1_ARRANGEMENT_SOURCING_DATE_INVALID' using errcode = '22023';
      end if;
      begin expected_date := expected_text::date;
      exception when others then raise exception 'V1_ARRANGEMENT_SOURCING_DATE_INVALID' using errcode = '22023'; end;
    end if;
    normalized := normalized || jsonb_build_array(jsonb_build_object(
      'request_line_id',line_id,'ready_qty',ready::text,'requested_qty',requested::text,'unit',line_unit,
      'source_kind',source,'inventory_item_id',item_id,'expected_available_date',expected_date));
  end loop;
  -- A readiness statement is a stock observation, not a reservation. Lock the
  -- same balance rows and aggregate shared item demand before publishing it.
  perform 1 from public.v1_inventory_balances b where b.inventory_item_id in
    (select (entry.value->>'inventory_item_id')::uuid from jsonb_array_elements(normalized) entry(value)
      where entry.value->>'source_kind'='warehouse' and entry.value->>'inventory_item_id' is not null)
    order by b.inventory_item_id for update;
  for item_id,item_total in select (entry.value->>'inventory_item_id')::uuid,sum((entry.value->>'ready_qty')::numeric)
    from jsonb_array_elements(normalized) entry(value) where entry.value->>'source_kind'='warehouse' and entry.value->>'inventory_item_id' is not null
    group by entry.value->>'inventory_item_id' loop
    select on_hand_qty into inventory_qty from public.v1_inventory_balances where inventory_item_id=item_id;
    select coalesce(sum(reserved_qty-consumed_qty),0) into other_reserved from public.v1_inventory_reservations
    where inventory_item_id=item_id and state in ('active','partially_consumed')
      and (request_kind<>'project' or v1_inventory_reservations.request_id<>r.id);
    if inventory_qty is null or item_total > greatest(0,inventory_qty-other_reserved) then
      raise exception 'V1_ARRANGEMENT_SOURCING_STOCK_CHANGED' using errcode = '22023';
    end if;
  end loop;
  select display_name into actor_name from public.v1_profiles where auth_user_id=auth.uid();
  insert into public.v1_arrangement_sourcing_revisions(arrangement_id,revision,request_id,
    base_request_version,base_arrangement_version,lines,updated_by_auth_user_id,updated_by_display_name,updated_by_role)
  values(a.id,current_revision+1,r.id,r.record_version,a.record_version,normalized,auth.uid(),actor_name,public.v1_current_exact_role());
  perform public.v1_write_audit_event('arrangement_sourcing_updated','procurement_arrangement',a.id,r.project_id,null,
    jsonb_build_object('request_id',r.id,'revision',current_revision+1,'line_count',jsonb_array_length(normalized)),
    'Scheduled sourcing progress shared with the project team',p_idempotency_key);
  result := public.v1_get_arrangement_sourcing_progress(r.id,a.id);
  perform public.v1_complete_idempotency('v1_save_arrangement_sourcing_progress',p_idempotency_key,result);
  return result;
end;
$$;

-- Existing finalization notifies Procurement. Reuse its trusted event/outbox
-- for the active project Engineering team and requester. Progress updates do
-- not create notifications; no daily reminders or new approval stage is added.
create or replace function public.v1_notify_arrangement_ready_team()
returns trigger language plpgsql security definer set search_path = '' as $$
declare req uuid; project uuid;
begin
  if new.event_type <> 'preapproved_arrangement_finalized' then return new; end if;
  select a.request_id,r.project_id into req,project from public.v1_procurement_arrangements a
    join public.v1_material_requests r on r.id=a.request_id
    where a.id=new.entity_id and a.status='approved' and r.state='approved';
  if req is null then return new; end if;
  insert into public.v1_notifications(recipient_auth_user_id,event_code,entity_type,entity_id,project_id)
  select candidate.actor,'arrangement_preparation_completed','procurement_arrangement',new.entity_id,project
  from (select r.created_by_auth_user_id as actor from public.v1_material_requests r where r.id=req
    union select m.member_auth_user_id from public.v1_project_members m
      where m.project_id=project and m.effective_from<=clock_timestamp()
      and (m.effective_to is null or m.effective_to>clock_timestamp())) candidate
  where public.v1_material_request_participant(req,candidate.actor)
    and not exists(select 1 from public.v1_notifications n where n.recipient_auth_user_id=candidate.actor
      and n.event_code='arrangement_preparation_completed' and n.entity_type='procurement_arrangement' and n.entity_id=new.entity_id);
  return new;
end;
$$;
drop trigger if exists v1_notify_arrangement_ready_team on public.v1_audit_events;
create trigger v1_notify_arrangement_ready_team
  after insert on public.v1_audit_events for each row
  when (new.event_type = 'preapproved_arrangement_finalized')
  execute function public.v1_notify_arrangement_ready_team();

-- Engineering receives an informational completion update, not Procurement's
-- dispatch action. Keep the request participant permission check and require
-- a current approved arrangement so queued alerts cannot describe old versions.
do $patch$
declare
  definition text := pg_get_functiondef('public.v1_push_notification_entity_allowed(public.v1_notifications)'::regprocedure);
  version_anchor text := 'if n.event_code in (''arrangement_review_required'',''arrangement_ready_for_dispatch'',';
  state_anchor text := 'if n.event_code=''receipt_review_required'' and not exists(';
begin
  if strpos(definition, 'arrangement_preparation_completed') = 0 then
    if strpos(definition,version_anchor)=0 or strpos(definition,state_anchor)=0 then
      raise exception 'V1_SOURCING_NOTIFICATION_GUARD_ANCHOR_MISSING';
    end if;
    definition := replace(definition,version_anchor,
      'if n.event_code in (''arrangement_review_required'',''arrangement_preparation_completed'',''arrangement_ready_for_dispatch'',');
    definition := replace(definition,state_anchor,
      'if n.event_code=''arrangement_preparation_completed'' and v_state not in
     (''approved'',''partially_dispatched'',''dispatched'',''partially_received'') then return false; end if;
   ' || state_anchor);
    execute definition;
  end if;
end;
$patch$;

-- Scheduled work can be prepared ahead of supply, but final completion may
-- only promise positive external quantities explicitly confirmed ready. Normal
-- and Urgent keep the published adoption policy. Partial ready supply retains
-- the existing reason/cap rules; expected dates never imply readiness.
do $$ begin
  if to_regprocedure('public.v1_save_arrangement_before_sourcing(jsonb,uuid)') is null then
    alter function public.v1_save_arrangement(jsonb,uuid) rename to v1_save_arrangement_before_sourcing;
  end if;
end $$;
create or replace function public.v1_save_arrangement(p_payload jsonb,p_idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare request_record public.v1_material_requests%rowtype;
begin
  select * into request_record from public.v1_material_requests
  where id=nullif(p_payload->>'request_id','')::uuid for update;
  if request_record.timing='scheduled' and request_record.state='arranging'
    and public.v1_can_arrange_material_request(request_record.id)
    and exists(select 1 from jsonb_array_elements(p_payload->'lines') entry(value)
      where entry.value->>'source_kind'='external_supplier'
        and entry.value->>'decision' in ('full','partial')
        and coalesce((entry.value->>'external_source_ready')::boolean,false) is false) then
    raise exception 'V1_EXTERNAL_SOURCE_READINESS_REQUIRED' using errcode='22023';
  end if;
  return public.v1_save_arrangement_before_sourcing(p_payload,p_idempotency_key);
end;
$$;
revoke all on function public.v1_save_arrangement_before_sourcing(jsonb,uuid),
  public.v1_save_arrangement(jsonb,uuid) from public,anon,authenticated;
grant execute on function public.v1_save_arrangement(jsonb,uuid) to authenticated,service_role;

-- Supply timing stays with the editor's already-authorized workspace fetch.
do $$ begin
  if to_regprocedure('public.v1_arrangement_projection_before_sourcing(uuid)') is null then
    alter function public.v1_arrangement_projection(uuid) rename to v1_arrangement_projection_before_sourcing;
  end if;
end $$;
create or replace function public.v1_arrangement_projection(p_request_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  result := public.v1_arrangement_projection_before_sourcing(p_request_id);
  return result || (select jsonb_build_object('timing',r.timing,'scheduled_date',r.scheduled_date)
    from public.v1_material_requests r where r.id=p_request_id);
end;
$$;
revoke all on function public.v1_arrangement_sourcing_immutable(),public.v1_notify_arrangement_ready_team(),
  public.v1_get_arrangement_sourcing_progress(uuid,uuid),public.v1_save_arrangement_sourcing_progress(jsonb,uuid),
  public.v1_arrangement_projection_before_sourcing(uuid),public.v1_arrangement_projection(uuid) from public,anon,authenticated;
grant execute on function public.v1_get_arrangement_sourcing_progress(uuid,uuid),
  public.v1_save_arrangement_sourcing_progress(jsonb,uuid),public.v1_arrangement_projection(uuid) to authenticated,service_role;
commit;
