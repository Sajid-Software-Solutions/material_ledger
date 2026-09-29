-- P0 push transport correction. Additive and history preserving.
-- Rollback: pause transport, retain all new columns/events and restore the
-- previous function bodies only after a separately reviewed bounded worker is
-- installed. Never reopen terminalized historical work or delete notifications.

alter table public.v1_notification_push_outbox
  drop constraint if exists v1_notification_push_outbox_status_check;
alter table public.v1_notification_push_outbox
  add constraint v1_notification_push_outbox_status_check
  check (status in ('pending','sending','sent','no_devices','failed',
                   'retry_wait','dead_letter'));
alter table public.v1_notification_push_outbox
  add column if not exists claim_id uuid,
  add column if not exists dispatch_lease_until timestamptz,
  add column if not exists dispatch_count integer not null default 0,
  add column if not exists last_attempt_at timestamptz,
  add column if not exists send_started_at timestamptz,
  add column if not exists terminal_at timestamptz,
  add column if not exists terminal_reason text;
alter table public.v1_notification_push_outbox
  drop constraint if exists v1_push_dispatch_count_nonnegative;
alter table public.v1_notification_push_outbox
  add constraint v1_push_dispatch_count_nonnegative check (dispatch_count >= 0);

create table if not exists public.v1_push_transport_control (
  id boolean primary key default true check (id),
  -- Migration fails closed until the compatible sender and tests are ready.
  operator_paused boolean not null default true,
  circuit_open_until timestamptz,
  probe_notification_id uuid,
  last_global_error_code text,
  unclaimed_window_started_at timestamptz not null default clock_timestamp(),
  last_success_at timestamptz,
  last_worker_at timestamptz,
  allowed_web_origins text[] not null default array['https://yorks-r35.vercel.app'],
  updated_at timestamptz not null default clock_timestamp()
);
alter table public.v1_push_transport_control
  add column if not exists allowed_web_origins text[] not null
  default array['https://yorks-r35.vercel.app'];
insert into public.v1_push_transport_control(id) values (true)
on conflict (id) do nothing;
alter table public.v1_push_transport_control enable row level security;
revoke all on public.v1_push_transport_control from public, anon, authenticated;
grant select on public.v1_push_transport_control to service_role;

create table if not exists public.v1_push_delivery_events (
  id bigint generated always as identity primary key,
  notification_id uuid not null references public.v1_notifications(id),
  attempt_count integer not null,
  event_code text not null check (event_code in
    ('claimed','sent','no_devices','retry_wait','dead_letter')),
  error_code text,
  occurred_at timestamptz not null default clock_timestamp()
);
alter table public.v1_push_delivery_events enable row level security;
revoke all on public.v1_push_delivery_events from public, anon, authenticated;
create index if not exists v1_push_events_recent_idx
  on public.v1_push_delivery_events (occurred_at desc);
create index if not exists v1_push_events_error_recent_idx
  on public.v1_push_delivery_events (error_code, occurred_at desc)
  where error_code is not null;
create index if not exists v1_push_outbox_retry_due_idx
  on public.v1_notification_push_outbox (next_attempt_at, created_at)
  where status in ('pending','retry_wait','failed');
create index if not exists v1_push_outbox_created_idx
  on public.v1_notification_push_outbox (created_at desc);
create index if not exists v1_push_unclaimed_dispatch_idx
  on public.v1_notification_push_outbox (dispatch_lease_until)
  where status in ('pending','retry_wait','failed')
    and dispatch_count > 0;
create index if not exists v1_notifications_recent_health_idx
  on public.v1_notifications (created_at desc);
create index if not exists v1_push_tokens_seen_idx
  on public.v1_push_device_tokens (last_seen_at desc, auth_user_id);

create or replace function public.v1_record_push_event()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status is distinct from old.status or
     new.attempt_count is distinct from old.attempt_count then
    if new.status in ('sending','sent','no_devices','retry_wait','dead_letter') then
      insert into public.v1_push_delivery_events
        (notification_id,attempt_count,event_code,error_code)
      values (new.notification_id,new.attempt_count,
        case when new.status='sending' then 'claimed' else new.status end,
        case when new.status in ('sending','sent') then null
          when new.terminal_reason='HISTORICAL_EXHAUSTED_OR_STALE'
            then 'HISTORICAL_QUARANTINE'
          else new.last_error_code end);
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.v1_record_push_event() from public,anon,authenticated,service_role;
drop trigger if exists v1_push_record_event on public.v1_notification_push_outbox;
create trigger v1_push_record_event after update on public.v1_notification_push_outbox
  for each row execute function public.v1_record_push_event();

-- Existing failed or aged work must never wake up when transport is restored.
-- This retains the source error and historical attempt count. A pending row
-- over 24 hours is also stale, regardless of whether it has been dispatched.
update public.v1_notification_push_outbox o
   set status = 'dead_letter',
       terminal_at = clock_timestamp(),
       terminal_reason = 'HISTORICAL_EXHAUSTED_OR_STALE',
       last_attempt_at = case when o.attempt_count > 0 then o.updated_at
         else null end,
       lease_until = null,
       dispatch_lease_until = null,
       claim_id = null,
       completed_at = clock_timestamp(),
       updated_at = clock_timestamp()
 where o.status in ('pending','failed','sending')
   and (o.status in ('failed','sending')
     or o.attempt_count >= 6
     or o.created_at < clock_timestamp() - interval '24 hours');

-- One dispatcher reserves the HTTP invocation before pg_net is called. The
-- unique outbox PK remains the one-recipient-job identity. HTTP failures
-- before claim are bounded by dispatch_count; they cannot loop forever.
create or replace function public.v1_dispatch_push_notification(
  p_notification_id uuid
) returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_url text;
  v_secret text;
  v_control public.v1_push_transport_control%rowtype;
  v_outbox public.v1_notification_push_outbox%rowtype;
  v_now timestamptz := clock_timestamp();
begin
  select * into v_control from public.v1_push_transport_control
    where id for update;
  if v_control.operator_paused then return false; end if;
  if v_control.circuit_open_until is not null
     and v_control.circuit_open_until > v_now then return false; end if;
  if v_control.probe_notification_id is not null then return false; end if;

  select * into v_outbox from public.v1_notification_push_outbox o
    where o.notification_id = p_notification_id for update skip locked;
  if not found then return false; end if;
  if not (
    (v_outbox.status in ('pending','retry_wait','failed')
      and v_outbox.next_attempt_at <= v_now
      and (v_outbox.dispatch_lease_until is null
        or v_outbox.dispatch_lease_until < v_now))
  ) then return false; end if;
  if v_outbox.attempt_count >= 6
     or v_outbox.dispatch_count >= 6
     or v_outbox.created_at < v_now - interval '24 hours' then
    update public.v1_notification_push_outbox set
      status = 'dead_letter', terminal_at = v_now,
      terminal_reason = 'BUDGET_OR_AGE_EXHAUSTED',
      completed_at = v_now, dispatch_lease_until = null,
      lease_until = null, claim_id = null, updated_at = v_now
      where notification_id = p_notification_id;
    return false;
  end if;
  if to_regclass('vault.decrypted_secrets') is null then return false; end if;
  execute 'select decrypted_secret from vault.decrypted_secrets
           where name = $1 limit 1' into v_url using 'yorks_push_edge_url';
  execute 'select decrypted_secret from vault.decrypted_secrets
           where name = $1 limit 1' into v_secret using 'yorks_push_webhook_secret';
  if nullif(v_url,'') is null or nullif(v_secret,'') is null then return false; end if;

  update public.v1_notification_push_outbox set
    dispatch_count = dispatch_count + 1,
    dispatch_lease_until = v_now + interval '2 minutes', updated_at = v_now
    where notification_id = p_notification_id;
  if v_control.circuit_open_until is not null then
    update public.v1_push_transport_control set
      probe_notification_id = p_notification_id,
      circuit_open_until = v_now + interval '15 minutes',
      updated_at = v_now where id;
  end if;
  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object('Content-Type','application/json',
      'x-yorks-push-secret',v_secret),
    body := jsonb_build_object('notificationId',p_notification_id),
    timeout_milliseconds := 5000
  );
  return true;
exception when others then
  -- A pg_net/configuration exception must not create a per-minute fan-out.
  -- Its failed subtransaction rolled back the reservation; open the circuit.
  update public.v1_push_transport_control set
    circuit_open_until=clock_timestamp()+interval '15 minutes',
    probe_notification_id=null,last_global_error_code='DISPATCH_INTERNAL',
    updated_at=clock_timestamp() where id;
  return false;
end;
$$;

create or replace function public.v1_dispatch_pending_pushes()
returns integer language plpgsql security definer set search_path = '' as $$
declare v_row record; v_count integer := 0;
begin
  -- Every worker uses control -> outbox -> device lock order.
  perform 1 from public.v1_push_transport_control where id for update;
  update public.v1_push_transport_control set last_worker_at=clock_timestamp()
    where id;
  -- A claim that never began an FCM request can be safely reclaimed. Once
  -- send_started_at is set, the outcome after a lost lease is ambiguous.
  update public.v1_notification_push_outbox o set
    status = 'retry_wait', next_attempt_at = clock_timestamp(),
    claim_id = null, lease_until = null,
    dispatch_lease_until = null, updated_at = clock_timestamp()
    where o.status = 'sending' and o.lease_until < clock_timestamp()
      and o.send_started_at is null and o.attempt_count < 6
      and o.created_at >= clock_timestamp() - interval '24 hours';
  -- Never repeat a request that may already have reached FCM.
  update public.v1_notification_push_outbox o set
    status = 'dead_letter', terminal_at = clock_timestamp(),
    terminal_reason = 'DELIVERY_OUTCOME_UNKNOWN',
    last_error_code = 'DELIVERY_OUTCOME_UNKNOWN',
    completed_at = clock_timestamp(), claim_id = null,
    lease_until = null, dispatch_lease_until = null,
    updated_at = clock_timestamp()
    where o.status = 'sending' and o.lease_until < clock_timestamp();
  -- A probe whose HTTP request never claimed must release the probe slot.
  update public.v1_push_transport_control t set
    probe_notification_id = null,
    circuit_open_until = clock_timestamp() + interval '15 minutes',
    updated_at = clock_timestamp()
    where t.id and t.probe_notification_id is not null
      and exists (select 1 from public.v1_notification_push_outbox o
        where o.notification_id = t.probe_notification_id
          and o.status <> 'sending'
          and (o.dispatch_lease_until is null
            or o.dispatch_lease_until < clock_timestamp()
            or o.status in ('sent','no_devices','dead_letter')));
  -- Edge/auth failures before a claim have no finish RPC. Three unclaimed
  -- dispatches in one window open the same circuit instead of trying every
  -- pending job. A later single probe tests recovery.
  update public.v1_push_transport_control t set
    circuit_open_until = clock_timestamp() + interval '15 minutes',
    probe_notification_id = null,
    last_global_error_code = 'EDGE_UNCLAIMED',
    unclaimed_window_started_at = clock_timestamp(),
    updated_at = clock_timestamp()
    where t.id and not t.operator_paused
      and t.probe_notification_id is null
      and (t.circuit_open_until is null
        or t.circuit_open_until < clock_timestamp())
      and (select count(*) from public.v1_notification_push_outbox o
        where o.status in ('pending','retry_wait','failed')
          and o.dispatch_count > 0
          and o.dispatch_lease_until between
            greatest(t.unclaimed_window_started_at,
              clock_timestamp()-interval '5 minutes')
            and clock_timestamp()) >= 3;
  for v_row in
    select o.notification_id from public.v1_notification_push_outbox o
    where o.status in ('pending','retry_wait','failed')
      and o.next_attempt_at <= clock_timestamp()
      and (o.dispatch_lease_until is null
        or o.dispatch_lease_until < clock_timestamp())
    order by o.created_at limit 25
  loop
    if public.v1_dispatch_push_notification(v_row.notification_id) then
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;

-- Retain the one-argument signature for older test/database callers, but it
-- cannot claim without a dispatcher reservation. Old Edge senders must stay
-- paused until the new sender is deployed; the old finish grant is revoked.
create or replace function public.v1_claim_notification_push(
  p_notification_id uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_attempt integer;
  v_claim_id uuid := extensions.gen_random_uuid();
  v_notification public.v1_notifications%rowtype;
  v_control public.v1_push_transport_control%rowtype;
begin
  select * into v_control from public.v1_push_transport_control where id for update;
  if v_control.operator_paused then return null; end if;
  if v_control.circuit_open_until is not null
     and v_control.probe_notification_id is distinct from p_notification_id
    then return null; end if;
  select * into v_notification from public.v1_notifications
    where id = p_notification_id;
  if not found then return null; end if;
  if not public.v1_notification_push_allowed(
    v_notification.recipient_auth_user_id, v_notification.event_code) then
    update public.v1_notification_push_outbox o set
      status = 'no_devices', last_error_code = 'USER_PREFERENCE_DISABLED',
      lease_until = null, dispatch_lease_until = null,
      completed_at = clock_timestamp(), updated_at = clock_timestamp()
      where o.notification_id = p_notification_id
        and o.status in ('pending','retry_wait','failed');
    update public.v1_push_transport_control set
      probe_notification_id = null,
      circuit_open_until = clock_timestamp() + interval '15 minutes',
      updated_at = clock_timestamp()
      where id and probe_notification_id = p_notification_id;
    return null;
  end if;
  update public.v1_notification_push_outbox o set
    status = 'sending', attempt_count = o.attempt_count + 1,
    claim_id = v_claim_id, last_attempt_at = clock_timestamp(),
    send_started_at = null,
    lease_until = clock_timestamp() + interval '2 minutes',
    dispatch_lease_until = null, updated_at = clock_timestamp()
    where o.notification_id = p_notification_id
      and o.status in ('pending','retry_wait','failed')
      and o.dispatch_lease_until > clock_timestamp()
      and o.attempt_count < 6
      and o.created_at >= clock_timestamp() - interval '24 hours'
    returning o.attempt_count into v_attempt;
  if v_attempt is null then return null; end if;
  return jsonb_build_object(
    'notificationId',v_notification.id,
    'recipientAuthUserId',v_notification.recipient_auth_user_id,
    'eventCode',v_notification.event_code,
    'entityType',v_notification.entity_type,
    'entityId',v_notification.entity_id,
    'requestId',public.v1_resolve_notification_request_id(
      v_notification.entity_type,v_notification.entity_id),
    'projectId',v_notification.project_id,
    'chatConversationId',public.v1_resolve_notification_chat_conversation_id(
      v_notification.entity_type,v_notification.entity_id),
    'unreadCount',public.v1_notification_unread_count(
      v_notification.recipient_auth_user_id),
    'attemptCount',v_attempt,'claimId',v_claim_id
  );
end;
$$;
revoke all on function public.v1_claim_notification_push(uuid)
  from public, anon, authenticated;
grant execute on function public.v1_claim_notification_push(uuid)
  to service_role;

-- The worker must cross this point before its first FCM HTTP request. A
-- timed-out pre-send claim can be replaced; a possibly accepted send cannot.
create or replace function public.v1_mark_push_send_started(
  p_notification_id uuid, p_claim_id uuid
) returns boolean language plpgsql security definer set search_path = '' as $$
begin
  update public.v1_notification_push_outbox o set
    send_started_at = coalesce(o.send_started_at,clock_timestamp()),
    updated_at = clock_timestamp()
    where o.notification_id = p_notification_id
      and o.claim_id = p_claim_id and o.status = 'sending'
      and o.lease_until > clock_timestamp();
  return found;
end;
$$;
revoke all on function public.v1_mark_push_send_started(uuid,uuid)
  from public, anon, authenticated;
grant execute on function public.v1_mark_push_send_started(uuid,uuid)
  to service_role;

-- A fingerprint is sufficient for deduplication; no token is copied into
-- history. Device ownership is rechecked before each external send.
create table if not exists public.v1_push_device_deliveries (
  notification_id uuid not null references public.v1_notifications(id),
  token_hash text not null check (token_hash ~ '^[a-f0-9]{64}$'),
  claim_id uuid not null,
  status text not null check (status in
    ('sending','sent','retry_wait','dead_letter')),
  error_code text,
  updated_at timestamptz not null default clock_timestamp(),
  primary key (notification_id,token_hash)
);
alter table public.v1_push_device_deliveries enable row level security;
revoke all on public.v1_push_device_deliveries from public,anon,authenticated;
-- Supabase default grants are deliberately narrowed for new history tables.
revoke all on public.v1_push_delivery_events from service_role;
revoke all on public.v1_push_device_deliveries from service_role;
revoke all on public.v1_push_transport_control from service_role;
grant select on public.v1_push_transport_control to service_role;
create index if not exists v1_push_device_fingerprint_idx
  on public.v1_push_device_tokens
  ((encode(extensions.digest(token,'sha256'),'hex')),auth_user_id);

-- Legacy tokens remain preserved but web delivery requires explicit enrollment.
alter table public.v1_push_device_tokens
  add column if not exists web_origin text,
  add column if not exists installation_id uuid,
  add column if not exists retired_at timestamptz,
  add column if not exists enrolled_at timestamptz;
create unique index if not exists v1_push_active_installation_idx
  on public.v1_push_device_tokens(auth_user_id,web_origin,installation_id)
  where retired_at is null and installation_id is not null;

create or replace function public.v1_begin_push_device(
  p_notification_id uuid,p_claim_id uuid,p_token_hash text
) returns text language plpgsql security definer set search_path = '' as $$
declare v_o public.v1_notification_push_outbox%rowtype; v_status text;
begin
  perform 1 from public.v1_push_transport_control where id for update;
  if exists(select 1 from public.v1_push_transport_control where id and
    (operator_paused or (circuit_open_until is not null
      and probe_notification_id is distinct from p_notification_id))) then
    return 'blocked';
  end if;
  select * into v_o from public.v1_notification_push_outbox
    where notification_id=p_notification_id for update;
  if not found or v_o.status <> 'sending' or v_o.claim_id<>p_claim_id
    or p_claim_id is null or v_o.lease_until<=clock_timestamp() then
    return 'blocked';
  end if;
  select status into v_status from public.v1_push_device_deliveries
    where notification_id=p_notification_id and token_hash=p_token_hash;
  if v_status in ('sent','sending','dead_letter') then return v_status; end if;
  if not exists(select 1 from public.v1_push_device_tokens t
    join public.v1_notifications n on n.recipient_auth_user_id=t.auth_user_id
    where n.id=p_notification_id and t.retired_at is null
      and (t.platform<>'web' or (t.installation_id is not null and n.created_at>=t.enrolled_at
        and t.web_origin=any((select allowed_web_origins
          from public.v1_push_transport_control where id)::text[])))
      and encode(extensions.digest(t.token,'sha256'),'hex')=p_token_hash) then
    return 'not_owned';
  end if;
  update public.v1_notification_push_outbox set
    send_started_at=coalesce(send_started_at,clock_timestamp())
    where notification_id=p_notification_id;
  insert into public.v1_push_device_deliveries
    (notification_id,token_hash,claim_id,status) values
    (p_notification_id,p_token_hash,p_claim_id,'sending')
    on conflict(notification_id,token_hash) do update set
      claim_id=excluded.claim_id,status='sending',error_code=null,
      updated_at=clock_timestamp();
  return 'ready';
end;
$$;

create or replace function public.v1_finish_push_device(
  p_notification_id uuid,p_claim_id uuid,p_token_hash text,
  p_error_code text default null
) returns boolean language plpgsql security definer set search_path = '' as $$
declare v_code text; v_status text;
begin
  perform 1 from public.v1_push_transport_control where id for update;
  perform 1 from public.v1_notification_push_outbox
    where notification_id=p_notification_id and claim_id=p_claim_id
      and status='sending' for update;
  if not found then return false; end if;
  v_code:=case when p_error_code is null then null when p_error_code in
    ('TOKEN_UNREGISTERED','TOKEN_INVALID','SENDER_ID_MISMATCH',
     'THIRD_PARTY_AUTH','AUTH_CONFIGURATION','MALFORMED_REQUEST',
     'QUOTA_EXCEEDED','FCM_UNAVAILABLE','FCM_INTERNAL',
     'DELIVERY_OUTCOME_UNKNOWN','UNKNOWN_ERROR') then p_error_code
     else 'UNKNOWN_ERROR' end;
  v_status:=case when v_code is null then 'sent'
    when v_code in ('QUOTA_EXCEEDED','FCM_UNAVAILABLE','FCM_INTERNAL',
      'UNKNOWN_ERROR') then 'retry_wait' else 'dead_letter' end;
  update public.v1_push_device_deliveries set status=v_status,
    error_code=v_code,updated_at=clock_timestamp()
    where notification_id=p_notification_id and token_hash=p_token_hash
      and claim_id=p_claim_id and status='sending';
  if not found then return false; end if;
  -- Only definitive UNREGISTERED proves revocation. INVALID_ARGUMENT may
  -- describe a bad payload even inside FcmError, so never prune on it alone.
  if v_code='TOKEN_UNREGISTERED' then
    delete from public.v1_push_device_tokens t using public.v1_notifications n
      where n.id=p_notification_id and t.auth_user_id=n.recipient_auth_user_id
        and encode(extensions.digest(t.token,'sha256'),'hex')=p_token_hash;
  end if;
  return true;
end;
$$;
revoke all on function public.v1_begin_push_device(uuid,uuid,text)
  from public,anon,authenticated;
revoke all on function public.v1_finish_push_device(uuid,uuid,text,text)
  from public,anon,authenticated;
grant execute on function public.v1_begin_push_device(uuid,uuid,text),
  public.v1_finish_push_device(uuid,uuid,text,text) to service_role;

-- New signature is mandatory. The old four-argument function loses its
-- service-role grant so a deployed old sender cannot write an unfenced result.
create or replace function public.v1_finish_notification_push(
  p_notification_id uuid, p_claim_id uuid, p_status text,
  p_sent_device_count integer default 0, p_error_code text default null,
  p_retry_after_seconds integer default null
) returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_outbox public.v1_notification_push_outbox%rowtype;
  v_now timestamptz := clock_timestamp();
  v_status text;
  v_delay integer;
  v_code text;
begin
  if p_status not in ('sent','no_devices','retryable','terminal') then
    raise exception 'V1_PUSH_STATUS_INVALID' using errcode='22023';
  end if;
  v_code := case when p_error_code is null and
    p_status in ('sent','no_devices') then null
    when p_error_code in (
    'TOKEN_UNREGISTERED','TOKEN_INVALID','SENDER_ID_MISMATCH',
    'THIRD_PARTY_AUTH','AUTH_CONFIGURATION','FCM_NOT_CONFIGURED',
    'MALFORMED_REQUEST','QUOTA_EXCEEDED','FCM_UNAVAILABLE','FCM_INTERNAL',
    'NETWORK_ERROR','UNKNOWN_ERROR','TOKEN_LOOKUP_FAILED',
    'PARTIAL_SEND','FCM_SERVICE_ACCOUNT_INVALID','DELIVERY_OUTCOME_UNKNOWN'
  ) then p_error_code else 'UNKNOWN_ERROR' end;
  perform 1 from public.v1_push_transport_control where id for update;
  select * into v_outbox from public.v1_notification_push_outbox o
    where o.notification_id = p_notification_id for update;
  if not found or v_outbox.status <> 'sending'
     or v_outbox.claim_id is distinct from p_claim_id then return false; end if;
  if exists(select 1 from public.v1_push_device_deliveries
      where notification_id=p_notification_id and status='sending') then
    v_code:='DELIVERY_OUTCOME_UNKNOWN';
    p_status:='terminal';
  elsif p_status='sent' and exists(select 1 from public.v1_push_device_deliveries
      where notification_id=p_notification_id and status<>'sent') then
    raise exception 'V1_PUSH_DEVICE_RESULTS_INCOMPLETE' using errcode='22023';
  end if;
  v_status := case
    when p_status = 'sent' then 'sent'
    when p_status = 'no_devices' then 'no_devices'
    when p_status = 'terminal' or v_code in (
      'TOKEN_UNREGISTERED','TOKEN_INVALID','SENDER_ID_MISMATCH',
      'THIRD_PARTY_AUTH','AUTH_CONFIGURATION','FCM_NOT_CONFIGURED',
      'FCM_SERVICE_ACCOUNT_INVALID','MALFORMED_REQUEST','DELIVERY_OUTCOME_UNKNOWN'
    ) then 'dead_letter'
    when v_outbox.attempt_count >= 6
      or v_outbox.created_at < v_now - interval '24 hours'
      or coalesce(p_retry_after_seconds,0) >= 86400
      then 'dead_letter'
    else 'retry_wait' end;
  v_delay := greatest(60, least(3600,
    (60 * power(2, greatest(0,v_outbox.attempt_count - 1)))::integer));
  v_delay := greatest(v_delay,
    least(86400, greatest(0, coalesce(p_retry_after_seconds,0))));
  -- Stable per-job jitter (0-29 seconds), no unbounded random work.
  v_delay := v_delay +
    (get_byte(extensions.digest(p_notification_id::text,'sha256'),0) % 30);
  update public.v1_notification_push_outbox o set
    status = v_status,
    sent_device_count = case when exists(select 1 from
      public.v1_push_device_deliveries where notification_id=p_notification_id)
      then (select count(*)::integer from public.v1_push_device_deliveries
        where notification_id=p_notification_id and status='sent')
      else greatest(0,coalesce(p_sent_device_count,0)) end,
    last_error_code = case when v_status='sent' then
      nullif(v_code,'UNKNOWN_ERROR') else v_code end,
    next_attempt_at = case when v_status='retry_wait'
      then v_now + make_interval(secs=>v_delay) else o.next_attempt_at end,
    lease_until = null, claim_id = null,
    terminal_at = case when v_status='dead_letter' then v_now else null end,
    terminal_reason = case when v_status='dead_letter' then
      case when p_status='terminal' then v_code
        else 'RETRY_BUDGET_EXHAUSTED' end else null end,
    completed_at = case when v_status in ('sent','no_devices','dead_letter')
      then v_now else null end,
    updated_at = v_now
    where o.notification_id = p_notification_id;

  if v_code in ('THIRD_PARTY_AUTH',
    'AUTH_CONFIGURATION','FCM_NOT_CONFIGURED','FCM_SERVICE_ACCOUNT_INVALID')
     and v_status <> 'sent'
     or (v_code='SENDER_ID_MISMATCH' and v_status <> 'sent'
       and (select count(distinct e.notification_id)
         from public.v1_push_delivery_events e
         where e.error_code='SENDER_ID_MISMATCH'
           and e.occurred_at >= v_now-interval '5 minutes') >= 3) then
    update public.v1_push_transport_control set
      circuit_open_until = v_now + interval '15 minutes',
      probe_notification_id = null,
      last_global_error_code = v_code, updated_at = v_now where id;
  elsif v_status='sent' and (select circuit_open_until is null
       or probe_notification_id=p_notification_id
       from public.v1_push_transport_control where id) then
    update public.v1_push_transport_control set
      circuit_open_until = null, probe_notification_id = null,
      last_global_error_code = null, last_success_at = v_now,
      unclaimed_window_started_at = v_now,
      updated_at = v_now where id;
  elsif (select probe_notification_id from public.v1_push_transport_control
           where id) = p_notification_id then
    update public.v1_push_transport_control set
      probe_notification_id = null,
      circuit_open_until = v_now + interval '15 minutes',
      updated_at = v_now where id;
  end if;
  return true;
end;
$$;

revoke all on function public.v1_finish_notification_push(
  uuid,text,integer,text) from public, anon, authenticated, service_role;
revoke all on function public.v1_finish_notification_push(
  uuid,uuid,text,integer,text,integer) from public, anon, authenticated;
grant execute on function public.v1_finish_notification_push(
  uuid,uuid,text,integer,text,integer) to service_role;

-- Legacy registration remains compatible but never revives historical jobs.
create or replace function public.v1_register_push_device(
  p_token text,p_platform text
) returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_token text := btrim(coalesce(p_token,''));
  v_platform text := lower(btrim(coalesce(p_platform,'unknown')));
begin
  if v_actor is null or not public.v1_current_actor_is_active() then
    raise exception 'V1_PUSH_DEVICE_REGISTER_DENIED' using errcode='42501';
  end if;
  if length(v_token) not between 20 and 4096 then
    raise exception 'V1_PUSH_DEVICE_TOKEN_INVALID' using errcode='22023';
  end if;
  if v_platform not in
    ('android','ios','web','macos','windows','linux','unknown') then
    v_platform := 'unknown';
  end if;
  insert into public.v1_push_device_tokens
    (token,auth_user_id,platform,created_at,last_seen_at)
    values (v_token,v_actor,v_platform,clock_timestamp(),clock_timestamp())
    on conflict(token) do update set
      auth_user_id=excluded.auth_user_id,
      platform=excluded.platform,last_seen_at=clock_timestamp();
  -- Enrollment never replays notification history. New events enqueue normally.
  return true;
end;
$$;

-- Origin metadata scopes routing; it is not an authorization claim. Actor
-- ownership still comes from Supabase Auth. Retire only the same installation.
create or replace function public.v1_register_push_installation(
  p_token text,p_platform text,p_web_origin text,p_installation_id uuid
) returns boolean language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_token text:=btrim(coalesce(p_token,''));
begin
  if v_actor is null or not public.v1_current_actor_is_active() then
    raise exception 'V1_PUSH_DEVICE_REGISTER_DENIED' using errcode='42501';
  end if;
  -- Serializes rotation against other registrations and the send gate.
  perform 1 from public.v1_push_transport_control where id for update;
  if p_platform<>'web' or p_installation_id is null or not exists(
    select 1 from public.v1_push_transport_control where id
      and p_web_origin=any(allowed_web_origins)) then
    raise exception 'V1_PUSH_ORIGIN_NOT_ALLOWED' using errcode='22023';
  end if;
  if length(v_token) not between 20 and 4096 then
    raise exception 'V1_PUSH_DEVICE_TOKEN_INVALID' using errcode='22023';
  end if;
  update public.v1_push_device_tokens set retired_at=clock_timestamp()
    where auth_user_id=v_actor and web_origin=p_web_origin
      and installation_id=p_installation_id and token<>v_token
      and retired_at is null;
  insert into public.v1_push_device_tokens
    (token,auth_user_id,platform,web_origin,installation_id,retired_at,enrolled_at)
    values(v_token,v_actor,'web',p_web_origin,p_installation_id,null,clock_timestamp())
    on conflict(token) do update set auth_user_id=excluded.auth_user_id,
      platform='web',web_origin=excluded.web_origin,
      enrolled_at=case when public.v1_push_device_tokens.auth_user_id=v_actor
        and public.v1_push_device_tokens.web_origin=p_web_origin
        and public.v1_push_device_tokens.installation_id=p_installation_id
        then public.v1_push_device_tokens.enrolled_at else clock_timestamp() end,
      installation_id=excluded.installation_id,retired_at=null,
      last_seen_at=clock_timestamp();
  return true;
end;
$$;
revoke all on function public.v1_register_push_installation(text,text,text,uuid)
  from public,anon;
grant execute on function public.v1_register_push_installation(text,text,text,uuid)
  to authenticated;

-- A new notification is durable even when push is paused. The cron owns
-- delivery, avoiding an immediate external request inside workflow commits.
create or replace function public.v1_kick_notification_push()
returns trigger language plpgsql security definer set search_path = '' as $$
begin return new; end;
$$;

-- Protected, index-backed operational projection. It never scans raw logs.
create or replace function public.v1_push_backend_health()
returns jsonb language sql stable security definer set search_path = '' as $$
  with cutoff as (select clock_timestamp() as at),
  notification_counts as (
    select count(*) filter(where n.created_at>=c.at-interval '1 hour') as h1,
           count(*) as h24
    from public.v1_notifications n cross join cutoff c
    where n.created_at>=c.at-interval '24 hours'
  ),
  event_counts as (
    select count(*) filter(where e.event_code='claimed'
      and e.occurred_at>=c.at-interval '1 hour') as attempts_1h,
      count(*) filter(where e.event_code='sent'
      and e.occurred_at>=c.at-interval '1 hour') as sent_1h,
      count(*) filter(where e.event_code='no_devices'
      and e.occurred_at>=c.at-interval '1 hour') as no_devices_1h,
      count(*) filter(where e.event_code='dead_letter'
      and e.occurred_at>=c.at-interval '1 hour') as dead_letter_1h,
      count(*) filter(where e.event_code='claimed' and e.attempt_count>1
        and e.occurred_at>=c.at-interval '1 hour') as retries_1h,
      count(*) filter(where e.event_code='claimed' and e.attempt_count>1) as retries_24h,
      count(*) filter(where e.event_code='claimed') as attempts_24h,
      count(*) filter(where e.event_code='sent') as sent_24h,
      count(*) filter(where e.event_code='no_devices') as no_devices_24h,
      count(*) filter(where e.event_code='dead_letter') as dead_letter_24h,
      max(e.occurred_at) filter(where e.event_code='sent') as last_sent_at
    from public.v1_push_delivery_events e cross join cutoff c
    where e.occurred_at>=c.at-interval '24 hours'
  ),
  errors as (
    select coalesce(jsonb_object_agg(error_code,total),'{}'::jsonb) as categories
    from (select error_code,count(*) as total
      from public.v1_push_delivery_events e cross join cutoff c
      where e.occurred_at>=c.at-interval '24 hours'
        and e.error_code is not null
      group by error_code) grouped
  ),
  outbox_counts as (
    select count(*) filter(where status='retry_wait') as retrying,
           count(*) filter(where status='dead_letter') as dead_letter_total,
           max(attempt_count) as max_attempts,
           min(created_at) filter(where status='retry_wait') as oldest_retry
    from public.v1_notification_push_outbox
  ),
  devices as (select count(*) as tokens,
    count(distinct auth_user_id) as users from public.v1_push_device_tokens)
  select jsonb_build_object(
    'asOf',c.at,'notifications1h',n.h1,'notifications24h',n.h24,
    'attempts1h',e.attempts_1h,'attempts24h',e.attempts_24h,
    'retries1h',e.retries_1h,'retries24h',e.retries_24h,
    'sent1h',e.sent_1h,'sent24h',e.sent_24h,
    'noDevices1h',e.no_devices_1h,'noDevices24h',e.no_devices_24h,
    'deadLetter1h',e.dead_letter_1h,'deadLetter24h',e.dead_letter_24h,
    'successPercent24h',case when e.attempts_24h=0 then null
      else round(100.0*e.sent_24h/e.attempts_24h,1) end,
    'retrying',o.retrying,'deadLetterTotal',o.dead_letter_total,
    'highestHistoricalAttemptCount',o.max_attempts,
    'oldestRetry',o.oldest_retry,'latestSuccessfulPush',t.last_success_at,
    'errorsByCategory',er.categories,
    'activeTokens',d.tokens,'usersWithTokens',d.users,
    'operatorPaused',t.operator_paused,
    'circuitOpenUntil',t.circuit_open_until,
    'lastGlobalError',t.last_global_error_code,
    'lastWorkerAt',t.last_worker_at,
    'highestActiveAttemptCount', (select coalesce(max(attempt_count),0)
      from public.v1_notification_push_outbox where status in
        ('pending','retry_wait','sending','failed')))
  from cutoff c cross join notification_counts n cross join event_counts e
    cross join errors er cross join outbox_counts o cross join devices d
    cross join public.v1_push_transport_control t where t.id;
$$;
revoke all on function public.v1_push_backend_health()
  from public, anon, authenticated;
grant execute on function public.v1_push_backend_health() to service_role;
