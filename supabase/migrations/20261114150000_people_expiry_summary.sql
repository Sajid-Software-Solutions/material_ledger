-- People and Company documents: one daily expiry summary for PR and Admin
-- (owner decision, 13 November 2026; PRODUCT_DECISIONS section 44).
--
-- Every morning at 08:15 in Dubai (04:15 UTC) each active PR and Admin
-- receives one notification when documents have expired or expire within
-- 60 days: staff and labour documents (People) and the company's own
-- documents (Company documents). It is sent only when something changed
-- since that person's last summary: a document entered the 60-day window,
-- one expired, or one was renewed or ended. Nothing waiting, or nothing
-- changed, sends nothing. At most one per person per day.
--
-- The notification is urgent when anything has expired. It opens People's
-- Needs attention, or Company documents when only company documents need
-- attention.
--
-- Data preservation: additive (one table, functions, a schedule). The three
-- notification functions are wrapped, keeping the previous ones as
-- *_before_people_expiry. Rollback: cron.unschedule('yorks-people-expiry-
-- summary') and restore the three functions from their *_before_people_expiry
-- versions; keep every row.

begin;

create table if not exists public.v1_people_expiry_digests (
  id uuid primary key default gen_random_uuid(),
  recipient_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  sent_on date not null,
  expired_count integer not null check (expired_count >= 0),
  expiring_count integer not null check (expiring_count >= 0),
  people_count integer not null check (people_count >= 0),
  company_count integer not null check (company_count >= 0),
  -- What needed attention, so the next summary is sent only on a change.
  fingerprint text not null check (fingerprint ~ '^[0-9a-f]{32}$'),
  notification_id uuid,
  created_at timestamptz not null default clock_timestamp(),
  unique (recipient_auth_user_id, sent_on),
  check (expired_count + expiring_count > 0),
  check (people_count + company_count = expired_count + expiring_count)
);
create index if not exists v1_people_expiry_digests_recipient_idx
  on public.v1_people_expiry_digests (recipient_auth_user_id, sent_on desc);

drop trigger if exists v1_people_expiry_digests_no_delete
  on public.v1_people_expiry_digests;
create trigger v1_people_expiry_digests_no_delete
  before delete on public.v1_people_expiry_digests
  for each row execute function public.v1_people_block_history_change();

alter table public.v1_people_expiry_digests enable row level security;
revoke all on table public.v1_people_expiry_digests
  from public, anon, authenticated;

-- Every current document expired or ending within 60 days of [p_today]:
-- active people's documents and active company records' documents.
create or replace function public.v1_people_expiry_attention(p_today date)
returns table (source text, document_id uuid, status text)
language sql
stable
security definer
set search_path = ''
as $$
  select 'people', document.id,
    public.v1_people_status(document.expiry_date, p_today)
  from public.v1_people_documents document
  join public.v1_workforce_workers worker on worker.id = document.worker_id
  where document.is_current
    and worker.current_status = 'active'
    and document.expiry_date <= p_today + 60
  union all
  select 'company', document.id,
    public.v1_people_status(document.expiry_date, p_today)
  from public.v1_company_docs_documents document
  join public.v1_company_docs_records record on record.id = document.record_id
  where document.is_current
    and record.status = 'active'
    and document.expiry_date <= p_today + 60;
$$;

-- Who receives it: every active PR and Admin.
create or replace function public.v1_people_expiry_recipients()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select profile.auth_user_id
  from public.v1_profiles profile
  where profile.is_active
    and public.v1_permission_exact_role(profile.auth_user_id) in ('pr', 'admin');
$$;

-- The daily job. Returns how many notifications it sent.
create or replace function public.v1_people_send_expiry_summary()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := public.v1_wf_today();
  v_expired integer;
  v_expiring integer;
  v_people integer;
  v_company integer;
  v_fingerprint text;
  v_recipient uuid;
  v_last text;
  v_digest uuid;
  v_notification uuid;
  v_count integer := 0;
begin
  select
    count(*) filter (where attention.status = 'expired')::integer,
    count(*) filter (where attention.status = 'expiring')::integer,
    count(*) filter (where attention.source = 'people')::integer,
    count(*) filter (where attention.source = 'company')::integer,
    md5(coalesce(string_agg(
      attention.source || ':' || attention.document_id::text || ':'
        || attention.status,
      ',' order by attention.source, attention.document_id
    ), ''))
  into v_expired, v_expiring, v_people, v_company, v_fingerprint
  from public.v1_people_expiry_attention(v_today) attention;

  if v_expired + v_expiring = 0 then
    return 0;
  end if;

  for v_recipient in select public.v1_people_expiry_recipients() loop
    select digest.fingerprint into v_last
    from public.v1_people_expiry_digests digest
    where digest.recipient_auth_user_id = v_recipient
    order by digest.sent_on desc
    limit 1;
    -- Nothing changed since this person's last summary.
    if v_last is not distinct from v_fingerprint then
      continue;
    end if;
    v_digest := null;
    insert into public.v1_people_expiry_digests (
      recipient_auth_user_id, sent_on, expired_count, expiring_count,
      people_count, company_count, fingerprint
    ) values (
      v_recipient, v_today, v_expired, v_expiring, v_people, v_company,
      v_fingerprint
    )
    on conflict (recipient_auth_user_id, sent_on) do nothing
    returning id into v_digest;
    if v_digest is null then
      continue;
    end if;
    v_notification := gen_random_uuid();
    insert into public.v1_notifications (
      id, recipient_auth_user_id, event_code, entity_type, entity_id,
      project_id
    ) values (
      v_notification, v_recipient,
      case when v_expired > 0 then 'people_documents_overdue'
        else 'people_documents_due' end,
      'people_expiry_digest', v_digest, null
    );
    update public.v1_people_expiry_digests
    set notification_id = v_notification
    where id = v_digest;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- Notification link, label and delivery.
-- ---------------------------------------------------------------------------

do $wrap$
begin
  if to_regprocedure(
    'public.v1_notification_module_route_before_people_expiry(public.v1_notifications)'
  ) is null then
    alter function public.v1_notification_module_route(public.v1_notifications)
      rename to v1_notification_module_route_before_people_expiry;
    alter function public.v1_notification_record_label(public.v1_notifications)
      rename to v1_notification_record_label_before_people_expiry;
    alter function public.v1_push_notification_entity_allowed(public.v1_notifications)
      rename to v1_push_notification_entity_allowed_before_people_expiry;
  end if;
end;
$wrap$;

create or replace function public.v1_people_notification_is_expiry(
  n public.v1_notifications
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select n.event_code in ('people_documents_overdue', 'people_documents_due')
    and n.entity_type = 'people_expiry_digest';
$$;

create or replace function public.v1_notification_module_route(
  n public.v1_notifications
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_people integer;
begin
  if public.v1_people_notification_is_expiry(n) then
    select digest.people_count into v_people
    from public.v1_people_expiry_digests digest
    where digest.id = n.entity_id
      and digest.recipient_auth_user_id = n.recipient_auth_user_id;
    -- Company documents only when nothing in People needs attention.
    if v_people = 0 then
      return '/yorks/company-documents';
    end if;
    return '/yorks/people';
  end if;
  return public.v1_notification_module_route_before_people_expiry(n);
end;
$$;

create or replace function public.v1_notification_record_label(
  n public.v1_notifications
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_label text;
begin
  if public.v1_people_notification_is_expiry(n) then
    if auth.uid() is distinct from n.recipient_auth_user_id then
      return null;
    end if;
    select (digest.expired_count + digest.expiring_count)::text
    into v_label
    from public.v1_people_expiry_digests digest
    where digest.id = n.entity_id
      and digest.recipient_auth_user_id = n.recipient_auth_user_id;
    return v_label;
  end if;
  return public.v1_notification_record_label_before_people_expiry(n);
end;
$$;

create or replace function public.v1_push_notification_entity_allowed(
  n public.v1_notifications
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if public.v1_people_notification_is_expiry(n) then
    return true;
  end if;
  return public.v1_push_notification_entity_allowed_before_people_expiry(n);
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants and schedule.
-- ---------------------------------------------------------------------------

do $grants$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'v1_people_expiry_attention(date)',
    'v1_people_expiry_recipients()',
    'v1_people_send_expiry_summary()',
    'v1_people_notification_is_expiry(public.v1_notifications)',
    'v1_notification_module_route(public.v1_notifications)',
    'v1_notification_record_label(public.v1_notifications)',
    'v1_push_notification_entity_allowed(public.v1_notifications)',
    'v1_notification_module_route_before_people_expiry(public.v1_notifications)',
    'v1_notification_record_label_before_people_expiry(public.v1_notifications)',
    'v1_push_notification_entity_allowed_before_people_expiry(public.v1_notifications)'
  ] loop
    execute format(
      'revoke all on function public.%s from public, anon, authenticated, service_role',
      v_signature
    );
  end loop;
end;
$grants$;

-- Daily at 04:15 UTC (08:15 in Dubai). A named schedule is idempotent.
do $schedule$
begin
  perform cron.schedule(
    'yorks-people-expiry-summary', '15 4 * * *',
    'select public.v1_people_send_expiry_summary();'
  );
end;
$schedule$;

commit;

notify pgrst, 'reload schema';
