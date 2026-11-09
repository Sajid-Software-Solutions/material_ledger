-- Owner-private Procurement checkpoints and immutable pending command intents.
-- Additive only: no MR, stock, reservation, approval or document is rewritten.
-- Rollback: stop calling these RPCs; retain the private records for recovery.
begin;

create table if not exists public.v1_procurement_progress (
  id uuid primary key default gen_random_uuid(),
  owner_auth_user_id uuid not null references public.v1_profiles(auth_user_id) on delete restrict,
  request_id uuid not null references public.v1_material_requests(id) on delete restrict,
  editor_kind text not null check (editor_kind in ('arrangement','dispatch')),
  arrangement_id uuid references public.v1_procurement_arrangements(id) on delete restrict,
  base_request_version integer not null check (base_request_version > 0),
  base_arrangement_version integer,
  schema_version integer not null check (schema_version = 1),
  revision integer not null default 1 check (revision > 0),
  inputs jsonb not null check (jsonb_typeof(inputs) = 'object'),
  saved_at timestamptz not null default clock_timestamp(),
  retired_at timestamptz,
  check ((editor_kind='arrangement' and arrangement_id is not null and base_arrangement_version is not null and base_arrangement_version > 0)
    or (editor_kind='dispatch' and arrangement_id is null and base_arrangement_version is null))
);
create unique index if not exists v1_procurement_progress_owner_key
  on public.v1_procurement_progress(owner_auth_user_id,request_id,editor_kind,
    coalesce(arrangement_id,'00000000-0000-0000-0000-000000000000'::uuid));
create index if not exists v1_procurement_progress_request_idx on public.v1_procurement_progress(request_id);
create index if not exists v1_procurement_progress_arrangement_idx on public.v1_procurement_progress(arrangement_id) where arrangement_id is not null;
create table if not exists public.v1_procurement_progress_commercials (
  progress_id uuid primary key references public.v1_procurement_progress(id) on delete restrict,
  inputs jsonb not null check (jsonb_typeof(inputs)='object')
);
create table if not exists public.v1_procurement_command_intents (
  id uuid primary key default gen_random_uuid(),
  owner_auth_user_id uuid not null references public.v1_profiles(auth_user_id) on delete restrict,
  request_id uuid not null references public.v1_material_requests(id) on delete restrict,
  progress_id uuid not null references public.v1_procurement_progress(id) on delete restrict,
  checkpoint_revision integer not null,
  command_name text not null check (command_name in ('v1_save_arrangement','v1_dispatch_materials')),
  command_key uuid not null,
  command_payload jsonb not null check (jsonb_typeof(command_payload)='object'),
  contains_commercial boolean not null default false,
  prepared_at timestamptz not null default clock_timestamp(),
  abandoned_at timestamptz,
  unique(owner_auth_user_id,command_name,command_key)
);
create index if not exists v1_procurement_command_intents_progress_idx on public.v1_procurement_command_intents(progress_id,prepared_at desc) where abandoned_at is null;
create index if not exists v1_procurement_command_intents_request_idx on public.v1_procurement_command_intents(request_id);
alter table public.v1_procurement_progress enable row level security;
alter table public.v1_procurement_progress_commercials enable row level security;
alter table public.v1_procurement_command_intents enable row level security;
-- No direct API grants, including SELECT. All reads re-authorize the current
-- actor and redact the separate commercial relation before serialization.
revoke all on public.v1_procurement_progress, public.v1_procurement_progress_commercials,
  public.v1_procurement_command_intents from public, anon, authenticated;
grant all on public.v1_procurement_progress, public.v1_procurement_progress_commercials,
  public.v1_procurement_command_intents to service_role;

create or replace function public.v1_procurement_progress_authorized(p_request_id uuid,p_editor_kind text)
returns boolean language sql stable security definer set search_path='' as $$
  select auth.uid() is not null and public.v1_current_actor_is_active()
    and case p_editor_kind
      when 'arrangement' then public.v1_can_arrange_material_request(p_request_id)
      when 'dispatch' then public.v1_can_dispatch_material_request(p_request_id)
      else false end;
$$;

-- Strict field allowlists are the boundary between technical recovery and costs.
-- Business validation (positive quantities, complete reasons, dates, stock) is
-- deliberately deferred to the final command. Intermediate strings survive.
create or replace function public.v1_validate_procurement_progress_inputs(
  p_request_id uuid,p_editor_kind text,p_arrangement_id uuid,p_inputs jsonb,p_commercial jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare j jsonb; kv record; v_id uuid; v_keys text[]; v_seen uuid[] := '{}';
begin
  if jsonb_typeof(p_inputs) is distinct from 'object' or octet_length(p_inputs::text)>1048576 then
    raise exception 'V1_PROCUREMENT_PROGRESS_INPUTS_INVALID' using errcode='22023';
  end if;
  if p_editor_kind='arrangement' then
    perform public.v1_assert_object_keys(p_inputs,array['note','lines'],'procurement_progress_inputs');
    v_keys:=array['arrangement_line_id','decision','source_kind','inventory_item_id','arranged_qty',
      'reason','external_supplier','external_ready','expected_available_date','external_reference'];
  else
    perform public.v1_assert_object_keys(p_inputs,array['dispatch_date','delivery_reference','driver_name','vehicle_reference','lines'],'procurement_progress_inputs');
    v_keys:=array['request_line_id','dispatch_qty'];
  end if;
  for kv in select * from jsonb_each(p_inputs) where key<>'lines' loop
    if jsonb_typeof(kv.value) not in ('string','null') or length(kv.value#>>'{}')>10000 then
      raise exception 'V1_PROCUREMENT_PROGRESS_FIELD_INVALID' using errcode='22023';
    end if;
  end loop;
  if jsonb_typeof(p_inputs->'lines') is distinct from 'array'
    or jsonb_array_length(p_inputs->'lines')>2000 then
    raise exception 'V1_PROCUREMENT_PROGRESS_LINES_INVALID' using errcode='22023';
  end if;
  for j in select value from jsonb_array_elements(p_inputs->'lines') loop
    perform public.v1_assert_object_keys(j,v_keys,'procurement_progress_line');
    v_id:=nullif(j->>case when p_editor_kind='arrangement' then 'arrangement_line_id' else 'request_line_id' end,'')::uuid;
    if v_id is null or v_id=any(v_seen) then
      raise exception 'V1_PROCUREMENT_PROGRESS_LINE_ID_INVALID' using errcode='22023';
    end if;
    v_seen:=array_append(v_seen,v_id);
    if (p_editor_kind='arrangement' and not exists(select 1 from public.v1_procurement_arrangement_lines
        where id=v_id and arrangement_id=p_arrangement_id))
      or (p_editor_kind='dispatch' and not exists(select 1 from public.v1_material_request_lines
        where id=v_id and request_id=p_request_id)) then
      raise exception 'V1_PROCUREMENT_PROGRESS_LINE_ID_INVALID' using errcode='22023';
    end if;
    for kv in select * from jsonb_each(j) loop
      if kv.key='external_ready' then
        if jsonb_typeof(kv.value) not in ('boolean','null') then
          raise exception 'V1_PROCUREMENT_PROGRESS_FIELD_INVALID' using errcode='22023';
        end if;
      elsif jsonb_typeof(kv.value) not in ('string','null') or length(kv.value#>>'{}')>10000 then
        raise exception 'V1_PROCUREMENT_PROGRESS_FIELD_INVALID' using errcode='22023';
      end if;
    end loop;
    if nullif(j->>'inventory_item_id','') is not null and not exists(select 1 from public.v1_inventory_items
      where id=(j->>'inventory_item_id')::uuid) then
      raise exception 'V1_PROCUREMENT_PROGRESS_INVENTORY_ID_INVALID' using errcode='22023';
    end if;
    if coalesce(j->>'decision','') not in ('','full','partial','unavailable')
      or coalesce(j->>'source_kind','') not in ('','warehouse','external_supplier') then
      raise exception 'V1_PROCUREMENT_PROGRESS_FIELD_INVALID' using errcode='22023';
    end if;
  end loop;
  if p_commercial is not null and p_commercial<>'null'::jsonb then
    if p_editor_kind<>'arrangement' or not public.v1_has_capability('manage_commercials') then
      raise exception 'V1_PROCUREMENT_PROGRESS_COMMERCIAL_DENIED' using errcode='42501';
    end if;
    perform public.v1_assert_object_keys(p_commercial,array['lines'],'procurement_progress_commercial');
    if jsonb_typeof(p_commercial->'lines') is distinct from 'array'
      or jsonb_array_length(p_commercial->'lines')>2000 or octet_length(p_commercial::text)>262144 then
      raise exception 'V1_PROCUREMENT_PROGRESS_COMMERCIAL_INVALID' using errcode='22023';
    end if;
    v_seen:='{}';
    for j in select value from jsonb_array_elements(p_commercial->'lines') loop
      perform public.v1_assert_object_keys(j,array['arrangement_line_id','unit_cost'],'procurement_progress_commercial_line');
      v_id:=nullif(j->>'arrangement_line_id','')::uuid;
      if v_id is null or v_id=any(v_seen) or not exists(select 1 from public.v1_procurement_arrangement_lines
        where id=v_id and arrangement_id=p_arrangement_id)
        or jsonb_typeof(j->'unit_cost') is distinct from 'string' or length(j->>'unit_cost')>128 then
        raise exception 'V1_PROCUREMENT_PROGRESS_COMMERCIAL_INVALID' using errcode='22023';
      end if;
      v_seen:=array_append(v_seen,v_id);
    end loop;
  end if;
end;
$$;

create or replace function public.v1_procurement_progress_projection(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.v1_procurement_progress%rowtype; result jsonb; commercial jsonb; pending jsonb;
begin
  select * into r from public.v1_procurement_progress where id=p_id and owner_auth_user_id=auth.uid();
  if not found then return null; end if;
  if not public.v1_procurement_progress_authorized(r.request_id,r.editor_kind) then
    raise exception 'V1_PROCUREMENT_PROGRESS_DENIED' using errcode='42501';
  end if;
  result:=jsonb_build_object('id',r.id,'request_id',r.request_id,'editor_kind',r.editor_kind,
    'arrangement_id',r.arrangement_id,'base_request_version',r.base_request_version,
    'base_arrangement_version',r.base_arrangement_version,'schema_version',r.schema_version,
    'revision',r.revision,'saved_at',r.saved_at,'discarded',r.retired_at is not null,
    'inputs',case when r.retired_at is null then r.inputs else '{}'::jsonb end);
  if r.retired_at is null and public.v1_has_capability('view_commercials') then
    select inputs into commercial from public.v1_procurement_progress_commercials where progress_id=r.id;
    if found then result:=result || jsonb_build_object('commercial_inputs',commercial); end if;
  end if;
  select jsonb_build_object('attempt_id',id,'command_name',command_name,'command_key',command_key)
    into pending from public.v1_procurement_command_intents
    where progress_id=r.id and owner_auth_user_id=auth.uid() and abandoned_at is null
    order by prepared_at desc limit 1;
  if found then result:=result || jsonb_build_object('pending_command',pending); end if;
  return result;
end;
$$;

create or replace function public.v1_get_procurement_progress(
  p_request_id uuid,p_editor_kind text,p_arrangement_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_id uuid;
begin
  if not public.v1_procurement_progress_authorized(p_request_id,p_editor_kind) then
    raise exception 'V1_PROCUREMENT_PROGRESS_DENIED' using errcode='42501';
  end if;
  select id into v_id from public.v1_procurement_progress
    where owner_auth_user_id=auth.uid() and request_id=p_request_id
      and editor_kind=p_editor_kind and arrangement_id is not distinct from p_arrangement_id;
  return public.v1_procurement_progress_projection(v_id);
end;
$$;

create or replace function public.v1_save_procurement_progress(p_payload jsonb,p_idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.v1_material_requests%rowtype; a public.v1_procurement_arrangements%rowtype;
  c public.v1_procurement_progress%rowtype; req uuid; arr uuid; kind text; expected integer;
  result jsonb; previous jsonb; current_id uuid;
begin
  perform public.v1_assert_object_keys(p_payload,array['request_id','editor_kind','arrangement_id',
    'expected_revision','base_request_version','base_arrangement_version','schema_version','inputs','commercial_inputs'],
    'procurement_progress');
  req:=nullif(p_payload->>'request_id','')::uuid;
  arr:=nullif(p_payload->>'arrangement_id','')::uuid;
  kind:=p_payload->>'editor_kind'; expected:=(p_payload->>'expected_revision')::integer;
  if not public.v1_procurement_progress_authorized(req,kind) then
    raise exception 'V1_PROCUREMENT_PROGRESS_DENIED' using errcode='42501';
  end if;
  select * into r from public.v1_material_requests where id=req for update;
  if expected is null or expected<0 or (p_payload->>'schema_version')::integer is distinct from 1
    or (kind='arrangement' and arr is null) or (kind='dispatch' and arr is not null) then
    raise exception 'V1_PROCUREMENT_PROGRESS_PAYLOAD_INVALID' using errcode='22023';
  end if;
  perform public.v1_validate_procurement_progress_inputs(req,kind,arr,p_payload->'inputs',p_payload->'commercial_inputs');
  previous:=public.v1_idempotency_get_or_claim('v1_save_procurement_progress',p_idempotency_key,p_payload);
  if previous is not null then
    if not public.v1_has_capability('view_commercials') then previous:=previous-'commercial_inputs'; end if;
    return previous;
  end if;
  if r.record_version is distinct from (p_payload->>'base_request_version')::integer then
    raise exception 'V1_PROCUREMENT_PROGRESS_BASE_CONFLICT' using errcode='40001';
  end if;
  if kind='arrangement' then
    select * into a from public.v1_procurement_arrangements where id=arr and request_id=req for update;
    if not found or r.state not in ('arranging','awaiting_request_approval') or a.status<>'working' or a.record_version is distinct from (p_payload->>'base_arrangement_version')::integer then
      raise exception 'V1_PROCUREMENT_PROGRESS_BASE_CONFLICT' using errcode='40001';
    end if;
  elsif r.state not in ('approved','partially_dispatched','partially_received')
    or p_payload->>'base_arrangement_version' is not null then
    raise exception 'V1_PROCUREMENT_PROGRESS_BASE_CONFLICT' using errcode='40001';
  end if;
  select * into c from public.v1_procurement_progress
    where owner_auth_user_id=auth.uid() and request_id=req and editor_kind=kind
      and arrangement_id is not distinct from arr for update;
  if (found and c.revision<>expected) or (not found and expected<>0) then
    raise exception 'V1_PROCUREMENT_PROGRESS_REVISION_CONFLICT' using errcode='40001';
  end if;
  if c.id is not null and exists(select 1 from public.v1_procurement_command_intents
    where progress_id=c.id and abandoned_at is null) then
    raise exception 'V1_PROCUREMENT_COMMAND_UNRESOLVED' using errcode='55000';
  end if;
  if c.id is null then
    insert into public.v1_procurement_progress(owner_auth_user_id,request_id,editor_kind,arrangement_id,
      base_request_version,base_arrangement_version,schema_version,inputs)
    values(auth.uid(),req,kind,arr,r.record_version,case when kind='arrangement' then a.record_version end,1,p_payload->'inputs')
    returning id into current_id;
  else
    current_id:=c.id;
    if c.retired_at is not null then
      update public.v1_procurement_progress_commercials set inputs='{"lines":[]}'::jsonb where progress_id=c.id;
    end if;
    update public.v1_procurement_progress set base_request_version=r.record_version,
      base_arrangement_version=case when kind='arrangement' then a.record_version end,
      inputs=p_payload->'inputs',revision=revision+1,saved_at=clock_timestamp(),retired_at=null where id=c.id;
  end if;
  if p_payload->'commercial_inputs' is not null and p_payload->'commercial_inputs'<>'null'::jsonb then
    insert into public.v1_procurement_progress_commercials(progress_id,inputs)
      values(current_id,p_payload->'commercial_inputs')
      on conflict(progress_id) do update set inputs=excluded.inputs;
  end if;
  result:=public.v1_procurement_progress_projection(current_id);
  perform public.v1_complete_idempotency('v1_save_procurement_progress',p_idempotency_key,result);
  return result;
end;
$$;

create or replace function public.v1_discard_procurement_progress(p_payload jsonb,p_idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare req uuid; kind text; c public.v1_procurement_progress%rowtype; previous jsonb; result jsonb;
begin
  perform public.v1_assert_object_keys(p_payload,array['request_id','editor_kind','arrangement_id','expected_revision'],'discard_procurement_progress');
  req:=(p_payload->>'request_id')::uuid; kind:=p_payload->>'editor_kind';
  if not public.v1_procurement_progress_authorized(req,kind) then
    raise exception 'V1_PROCUREMENT_PROGRESS_DENIED' using errcode='42501';
  end if;
  perform 1 from public.v1_material_requests where id=req for update;
  previous:=public.v1_idempotency_get_or_claim('v1_discard_procurement_progress',p_idempotency_key,p_payload);
  if previous is not null then return previous; end if;
  select * into c from public.v1_procurement_progress where owner_auth_user_id=auth.uid()
    and request_id=req and editor_kind=kind
    and arrangement_id is not distinct from nullif(p_payload->>'arrangement_id','')::uuid for update;
  if not found or c.revision is distinct from (p_payload->>'expected_revision')::integer then
    raise exception 'V1_PROCUREMENT_PROGRESS_REVISION_CONFLICT' using errcode='40001';
  end if;
  if exists(select 1 from public.v1_procurement_command_intents i where i.progress_id=c.id and i.abandoned_at is null
    and not exists(select 1 from public.v1_idempotency_keys k where k.actor_auth_user_id=auth.uid()
      and k.idempotency_key=i.command_key and k.command_name=case when i.command_name='v1_save_arrangement'
        then 'v1_save_arrangement_phase3' else i.command_name end and k.completed_at is not null)) then
    raise exception 'V1_PROCUREMENT_COMMAND_UNRESOLVED' using errcode='55000';
  end if;
  update public.v1_procurement_command_intents set abandoned_at=clock_timestamp()
    where progress_id=c.id and abandoned_at is null;
  update public.v1_procurement_progress set revision=revision+1,retired_at=clock_timestamp(),saved_at=clock_timestamp() where id=c.id;
  result:=jsonb_build_object('discarded',true,'revision',c.revision+1);
  perform public.v1_complete_idempotency('v1_discard_procurement_progress',p_idempotency_key,result);
  return result;
end;
$$;

create or replace function public.v1_prepare_procurement_command(p_payload jsonb,p_idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare req uuid; arr uuid; kind text; cmd text; key uuid; body jsonb; j jsonb;
  r public.v1_material_requests%rowtype; c public.v1_procurement_progress%rowtype;
  i public.v1_procurement_command_intents%rowtype; commercial boolean; result jsonb; previous jsonb;
begin
  perform public.v1_assert_object_keys(p_payload,array['request_id','editor_kind','arrangement_id','checkpoint_revision',
    'command_name','command_key','command_payload'],'prepare_procurement_command');
  req:=(p_payload->>'request_id')::uuid; arr:=nullif(p_payload->>'arrangement_id','')::uuid;
  kind:=p_payload->>'editor_kind'; cmd:=p_payload->>'command_name'; key:=(p_payload->>'command_key')::uuid;
  body:=p_payload->'command_payload';
  if not public.v1_procurement_progress_authorized(req,kind) then
    raise exception 'V1_PROCUREMENT_PROGRESS_DENIED' using errcode='42501';
  end if;
  if key is null or jsonb_typeof(body) is distinct from 'object' or octet_length(body::text)>1048576
    or cmd is distinct from (case when kind='arrangement' then 'v1_save_arrangement' else 'v1_dispatch_materials' end)
    or (body->>'request_id')::uuid is distinct from req then
    raise exception 'V1_PROCUREMENT_COMMAND_PAYLOAD_INVALID' using errcode='22023';
  end if;
  commercial:=kind='arrangement' and exists(select 1 from jsonb_array_elements(body->'lines') l where l.value ? 'unit_cost');
  if commercial and not public.v1_has_capability('manage_commercials') then
    raise exception 'V1_PROCUREMENT_PROGRESS_COMMERCIAL_DENIED' using errcode='42501';
  end if;
  select * into r from public.v1_material_requests where id=req for update;
  previous:=public.v1_idempotency_get_or_claim('v1_prepare_procurement_command',p_idempotency_key,p_payload);
  if previous is not null then
    if exists(select 1 from public.v1_procurement_command_intents where owner_auth_user_id=auth.uid()
      and command_name=cmd and command_key=key and abandoned_at is not null) then
      raise exception 'V1_PROCUREMENT_COMMAND_INTENT_CHANGED' using errcode='40001';
    end if;
    return previous;
  end if;
  select * into i from public.v1_procurement_command_intents where owner_auth_user_id=auth.uid()
    and command_name=cmd and command_key=key;
  if found then
    if i.command_payload<>body or i.request_id<>req or i.abandoned_at is not null then
      raise exception 'V1_PROCUREMENT_COMMAND_KEY_REUSED' using errcode='22023';
    end if;
  else
    select * into c from public.v1_procurement_progress where owner_auth_user_id=auth.uid()
      and request_id=req and editor_kind=kind and arrangement_id is not distinct from arr for update;
    if not found or c.retired_at is not null or c.revision is distinct from (p_payload->>'checkpoint_revision')::integer
      or c.base_request_version<>r.record_version then
      raise exception 'V1_PROCUREMENT_PROGRESS_BASE_CONFLICT' using errcode='40001';
    end if;
    if exists(select 1 from public.v1_procurement_command_intents where progress_id=c.id and abandoned_at is null) then
      raise exception 'V1_PROCUREMENT_COMMAND_UNRESOLVED' using errcode='55000';
    end if;
    if kind='arrangement' then
      perform public.v1_assert_object_keys(body,array['request_id','arrangement_id','expected_request_version',
        'expected_arrangement_version','procurement_note','lines'],'prepare_arrangement');
      if (body->>'arrangement_id')::uuid is distinct from arr
        or (body->>'expected_request_version')::integer is distinct from c.base_request_version
        or (body->>'expected_arrangement_version')::integer is distinct from c.base_arrangement_version
        or not exists(select 1 from public.v1_procurement_arrangements where id=arr and request_id=req
          and record_version=c.base_arrangement_version and status='working') then
        raise exception 'V1_PROCUREMENT_PROGRESS_BASE_CONFLICT' using errcode='40001';
      end if;
    else
      perform public.v1_assert_object_keys(body,array['request_id','expected_version','dispatch_date','delivery_reference',
        'driver_name','vehicle_reference','lines'],'prepare_dispatch');
      if (body->>'expected_version')::integer is distinct from c.base_request_version then
        raise exception 'V1_PROCUREMENT_PROGRESS_BASE_CONFLICT' using errcode='40001';
      end if;
    end if;
    if jsonb_typeof(body->'lines') is distinct from 'array' or jsonb_array_length(body->'lines')>2000 then
      raise exception 'V1_PROCUREMENT_COMMAND_PAYLOAD_INVALID' using errcode='22023';
    end if;
    for j in select value from jsonb_array_elements(body->'lines') loop
      if kind='arrangement' then
        perform public.v1_assert_object_keys(j,array['arrangement_line_id','source_kind','external_supplier','inventory_item_id',
          'decision','arranged_qty','reason','unit_cost','external_source_ready','external_expected_date','external_reference'],'prepared_arrangement_line');
        if not exists(select 1 from public.v1_procurement_arrangement_lines where id=(j->>'arrangement_line_id')::uuid
          and arrangement_id=arr) then raise exception 'V1_PROCUREMENT_PROGRESS_LINE_ID_INVALID' using errcode='22023'; end if;
      else
        perform public.v1_assert_object_keys(j,array['request_line_id','dispatch_qty'],'prepared_dispatch_line');
        if not exists(select 1 from public.v1_material_request_lines where id=(j->>'request_line_id')::uuid
          and request_id=req) then raise exception 'V1_PROCUREMENT_PROGRESS_LINE_ID_INVALID' using errcode='22023'; end if;
      end if;
    end loop;
    insert into public.v1_procurement_command_intents(owner_auth_user_id,request_id,progress_id,checkpoint_revision,
      command_name,command_key,command_payload,contains_commercial)
    values(auth.uid(),req,c.id,c.revision,cmd,key,body,commercial) returning * into i;
  end if;
  result:=jsonb_build_object('attempt_id',i.id,'request_id',req,'command_name',cmd,'command_key',key,'status','prepared');
  perform public.v1_complete_idempotency('v1_prepare_procurement_command',p_idempotency_key,result);
  return result;
end;
$$;

create or replace function public.v1_get_procurement_command_outcome(p_request_id uuid,p_command_name text,p_idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare i public.v1_procurement_command_intents%rowtype; k public.v1_idempotency_keys%rowtype;
  kind text; result jsonb; stored_name text;
begin
  kind:=case p_command_name when 'v1_save_arrangement' then 'arrangement' when 'v1_dispatch_materials' then 'dispatch' end;
  if not public.v1_procurement_progress_authorized(p_request_id,kind) then
    raise exception 'V1_PROCUREMENT_PROGRESS_DENIED' using errcode='42501';
  end if;
  -- Serializes with the final RPC: not_found/prepared cannot be returned while
  -- that transaction is changing this request. A client timeout stays unknown.
  perform 1 from public.v1_material_requests where id=p_request_id for update;
  select * into i from public.v1_procurement_command_intents where owner_auth_user_id=auth.uid()
    and request_id=p_request_id and command_name=p_command_name and command_key=p_idempotency_key;
  stored_name:=case when kind='arrangement' then 'v1_save_arrangement_phase3' else p_command_name end;
  select * into k from public.v1_idempotency_keys where actor_auth_user_id=auth.uid()
    and command_name=stored_name and idempotency_key=p_idempotency_key;
  result:=jsonb_build_object('request_id',p_request_id,'command_name',p_command_name,'idempotency_key',p_idempotency_key);
  if k.completed_at is not null then
    if coalesce(k.response_json->>'request_id','')<>p_request_id::text then
      raise exception 'V1_PROCUREMENT_PROGRESS_DENIED' using errcode='42501';
    end if;
    return result||jsonb_build_object('status','confirmed','attempt_id',i.id,'workspace',
      case when kind='arrangement' then public.v1_arrangement_projection(p_request_id)
        else public.v1_logistics_workspace_projection(p_request_id) end);
  end if;
  if i.id is null then return result||jsonb_build_object('status','not_found'); end if;
  if i.abandoned_at is not null then return result||jsonb_build_object('status','abandoned','attempt_id',i.id); end if;
  if i.contains_commercial and (not public.v1_has_capability('view_commercials') or not public.v1_has_capability('manage_commercials')) then
    return result||jsonb_build_object('status','access_changed','attempt_id',i.id);
  end if;
  return result||jsonb_build_object('status',case when k.idempotency_key is null then 'prepared' else 'pending' end,
    'attempt_id',i.id,'command_payload',i.command_payload);
end;
$$;

create or replace function public.v1_abandon_procurement_command(p_request_id uuid,p_command_name text,p_idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
  result:=public.v1_get_procurement_command_outcome(p_request_id,p_command_name,p_idempotency_key);
  if result->>'status' in ('confirmed','pending') then return result; end if;
  update public.v1_procurement_command_intents set abandoned_at=clock_timestamp()
    where owner_auth_user_id=auth.uid() and request_id=p_request_id and command_name=p_command_name
      and command_key=p_idempotency_key and abandoned_at is null;
  return (result-'command_payload')||jsonb_build_object('status','abandoned');
end;
$$;

revoke all on function public.v1_procurement_progress_authorized(uuid,text),
  public.v1_validate_procurement_progress_inputs(uuid,text,uuid,jsonb,jsonb),
  public.v1_procurement_progress_projection(uuid),public.v1_get_procurement_progress(uuid,text,uuid),
  public.v1_save_procurement_progress(jsonb,uuid),public.v1_discard_procurement_progress(jsonb,uuid),
  public.v1_prepare_procurement_command(jsonb,uuid),public.v1_get_procurement_command_outcome(uuid,text,uuid),
  public.v1_abandon_procurement_command(uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.v1_get_procurement_progress(uuid,text,uuid),
  public.v1_save_procurement_progress(jsonb,uuid),public.v1_discard_procurement_progress(jsonb,uuid),
  public.v1_prepare_procurement_command(jsonb,uuid),public.v1_get_procurement_command_outcome(uuid,text,uuid),
  public.v1_abandon_procurement_command(uuid,text,uuid) to authenticated;

-- Prepared commands are immutable even if a stale tab later sends a different
-- body or a delayed HTTP request arrives after an explicit abandon decision.
create or replace function public.v1_assert_prepared_procurement_command(p_command_name text,p_key uuid,p_payload jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare i public.v1_procurement_command_intents%rowtype;
begin
  select * into i from public.v1_procurement_command_intents where owner_auth_user_id=auth.uid()
    and command_name=p_command_name and command_key=p_key;
  if found and (i.abandoned_at is not null or i.command_payload<>p_payload) then
    raise exception 'V1_PROCUREMENT_COMMAND_INTENT_CHANGED' using errcode='40001';
  end if;
end;
$$;
revoke all on function public.v1_assert_prepared_procurement_command(text,uuid,jsonb) from public,anon,authenticated;
do $patch$
declare definition text; anchor text;
begin
  select pg_get_functiondef('public.v1_dispatch_materials(jsonb,uuid)'::regprocedure) into definition;
  anchor := '  v_existing_response := public.v1_idempotency_get_or_claim(';
  if position('v1_assert_prepared_procurement_command' in definition)=0 then
    if position(anchor in definition)=0 then raise exception 'Dispatch command guard anchor missing'; end if;
    definition:=replace(definition,anchor,
      '  perform public.v1_assert_prepared_procurement_command(''v1_dispatch_materials'',p_idempotency_key,p_payload);' || chr(10) || anchor);
    execute definition;
  end if;
  select pg_get_functiondef('public.v1_save_arrangement(jsonb,uuid)'::regprocedure) into definition;
  anchor := '  return public.v1_save_arrangement_before_clarification_reapproval(';
  if position('v1_assert_prepared_procurement_command' in definition)=0 then
    if position(anchor in definition)=0 then raise exception 'Arrangement command guard anchor missing'; end if;
    definition:=replace(definition,anchor,
      '  perform public.v1_assert_prepared_procurement_command(''v1_save_arrangement'',p_idempotency_key,p_payload);' || chr(10) || anchor);
    execute definition;
  end if;
end;
$patch$;
commit;
