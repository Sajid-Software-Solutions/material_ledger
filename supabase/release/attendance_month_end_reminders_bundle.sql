-- Release bundle: Workforce month-end confirmation reminders
-- (PRODUCT_DECISIONS.md section 37). Applies migration 20261113090000 in one
-- transaction, then checks itself. Additive: one table, functions, a daily
-- pg_cron job. Requires pr_role_and_attendance_v2_bundle.sql first.
-- Apply by hand (staging, then production):
--   npx supabase@latest db query --remote=<ref> --yes -f supabase/release/attendance_month_end_reminders_bundle.sql
-- Then deploy the send-push edge function (new notification copy).
-- Rollback: supabase/release/attendance_month_end_reminders_rollback.sql

begin;

-- Workforce attendance V2: month-end confirmation reminders with priority
-- (PRODUCT_DECISIONS.md section 37, following the approved prototype).
--
-- On a month's last day, and every morning after it until it is confirmed,
-- each confirmer receives one notification naming how many of their crews
-- are waiting. A crew's confirmers are the Project Engineers on its project;
-- a crew whose project has no Project Engineer falls back to the Senior
-- Mechanical Engineers and Project Managers, so no crew is forgotten. The
-- daily job runs at 04:05 UTC (08:05 in Dubai).
--
-- People in the app see the same list through v1_wf_get_confirmations_due.
--
-- Data preservation: additive. The earlier per-crew reminder table is kept
-- (unused). Rollback: cron.unschedule('yorks-workforce-month-end-reminders')
-- and revoke v1_wf_get_confirmations_due; keep every table and row.



create table public.v1_workforce_month_reminder_digests (
  id uuid primary key default gen_random_uuid(),
  recipient_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  period_month date not null check (
    period_month = date_trunc('month', period_month)::date
  ),
  sent_on date not null,
  crew_count integer not null check (crew_count > 0),
  notification_id uuid,
  created_at timestamptz not null default clock_timestamp(),
  unique (recipient_auth_user_id, period_month, sent_on)
);
create trigger v1_workforce_month_reminder_digests_no_delete
before delete on public.v1_workforce_month_reminder_digests
for each row execute function public.v1_workforce_block_delete();
alter table public.v1_workforce_month_reminder_digests
  enable row level security;
revoke all on table public.v1_workforce_month_reminder_digests
  from public, anon, authenticated;

-- Months waiting for confirmation on [p_today]: the current month from its
-- last day, and the previous month until it is confirmed.
create or replace function public.v1_wf_due_months(p_today date)
returns setof date
language sql
immutable
set search_path = ''
as $$
  select month_start
  from (
    select (date_trunc('month', p_today) - interval '1 month')::date
    union all
    select date_trunc('month', p_today)::date
  ) months(month_start)
  where (month_start + interval '1 month - 1 day')::date <= p_today;
$$;

-- Crews and months a confirmer still has to confirm. The crew must have
-- existed before the month ended and need confirmation.
create or replace function public.v1_wf_due_crew_months(p_today date)
returns table (team_id uuid, project_id uuid, period_month date)
language sql
stable
security definer
set search_path = ''
as $$
  select profile.team_id, profile.project_id, due.month_start
  from public.v1_workforce_crew_profiles profile
  join public.v1_workforce_teams team on team.id = profile.team_id
  cross join lateral public.v1_wf_due_months(p_today) due(month_start)
  where profile.is_active
    and team.is_active
    and profile.needs_confirmation
    and (profile.created_at at time zone 'Asia/Dubai')::date
      <= (due.month_start + interval '1 month - 1 day')::date
    and not exists (
      select 1 from public.v1_workforce_month_confirmations confirmation
      where confirmation.team_id = profile.team_id
        and confirmation.period_month = due.month_start
        and confirmation.is_confirmed
    );
$$;

-- For the signed-in person: the crews and months waiting for them.
create or replace function public.v1_wf_get_confirmations_due()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.v1_current_actor_is_active() then
    raise exception 'V1_ACTIVE_ACTOR_REQUIRED' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'schema_version', 'yorks.workforce.confirmations_due.v1',
    'today', public.v1_wf_today(),
    'due', coalesce((
      select jsonb_agg(jsonb_build_object(
        'crew_id', due.team_id,
        'crew_name', team.team_name,
        'month', due.period_month,
        'last_day', (due.period_month + interval '1 month - 1 day')::date,
        'overdue', (due.period_month + interval '1 month - 1 day')::date
          < public.v1_wf_today(),
        'missing_days', (
          select count(*)
          from generate_series(
            due.period_month,
            (due.period_month + interval '1 month - 1 day')::date,
            interval '1 day'
          ) series(day_ts)
          where public.v1_wf_day_type(series.day_ts::date) = 'work'
            and not exists (
              select 1 from public.v1_workforce_day_sheets sheet
              where sheet.team_id = due.team_id
                and sheet.work_date = series.day_ts::date
            )
        )
      ) order by due.period_month, lower(team.team_name))
      from public.v1_wf_due_crew_months(public.v1_wf_today()) due
      join public.v1_workforce_teams team on team.id = due.team_id
      where coalesce(
        (public.v1_wf_crew_access(due.team_id) ->> 'confirm')::boolean, false
      )
    ), '[]'::jsonb)
  );
end;
$$;

-- The daily job. One notification per confirmer and month per day.
create or replace function public.v1_wf_send_month_end_reminders()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := public.v1_wf_today();
  v_count integer := 0;
  v_row record;
  v_digest uuid;
  v_notification uuid;
begin
  for v_row in
    with recipients as (
      select due.period_month, member.member_auth_user_id as auth_user_id,
        due.team_id
      from public.v1_wf_due_crew_months(v_today) due
      join public.v1_project_members member
        on member.project_id = due.project_id
        and member.project_role = 'project_engineer'
        and member.effective_from <= clock_timestamp()
        and (member.effective_to is null
          or member.effective_to > clock_timestamp())
      union
      -- No Project Engineer on the project: the organization's senior
      -- engineers are reminded instead.
      select due.period_month, profile.auth_user_id, due.team_id
      from public.v1_wf_due_crew_months(v_today) due
      cross join public.v1_profiles profile
      where not exists (
          select 1 from public.v1_project_members member
          where member.project_id = due.project_id
            and member.project_role = 'project_engineer'
            and member.effective_from <= clock_timestamp()
            and (member.effective_to is null
              or member.effective_to > clock_timestamp())
        )
        and public.v1_permission_exact_role(profile.auth_user_id) in (
          'senior_mechanical_engineer', 'project_manager'
        )
    )
    select recipients.period_month, recipients.auth_user_id,
      count(distinct recipients.team_id)::integer as crew_count
    from recipients
    join public.v1_profiles profile
      on profile.auth_user_id = recipients.auth_user_id and profile.is_active
    group by recipients.period_month, recipients.auth_user_id
  loop
    insert into public.v1_workforce_month_reminder_digests (
      recipient_auth_user_id, period_month, sent_on, crew_count
    ) values (v_row.auth_user_id, v_row.period_month, v_today, v_row.crew_count)
    on conflict (recipient_auth_user_id, period_month, sent_on) do nothing
    returning id into v_digest;
    if v_digest is null then
      continue;
    end if;
    v_notification := gen_random_uuid();
    insert into public.v1_notifications (
      id, recipient_auth_user_id, event_code, entity_type, entity_id,
      project_id
    ) values (
      v_notification, v_row.auth_user_id,
      -- On the last day it is ready; once the month has ended it is overdue
      -- (urgent in the notification catalogue).
      case
        when (v_row.period_month + interval '1 month - 1 day')::date < v_today
          then 'workforce_attendance_month_overdue'
        else 'workforce_attendance_month_ready'
      end,
      'workforce_month_reminder', v_digest, null
    );
    update public.v1_workforce_month_reminder_digests
    set notification_id = v_notification
    where id = v_digest;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- Notification link and label for the digest.
create or replace function public.v1_wf_notification_is_attendance(
  n public.v1_notifications
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select n.event_code like 'workforce_attendance_%'
    and n.entity_type in (
      'workforce_day_sheet', 'workforce_crew', 'workforce_month_reminder'
    );
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
  v_team uuid;
  v_date date;
begin
  if public.v1_wf_notification_is_attendance(n) then
    if n.entity_type = 'workforce_month_reminder' then
      select digest.period_month into v_date
      from public.v1_workforce_month_reminder_digests digest
      where digest.id = n.entity_id
        and digest.recipient_auth_user_id = n.recipient_auth_user_id;
      return '/yorks/workforce/confirm'
        || coalesce('?month=' || to_char(v_date, 'YYYY-MM-DD'), '');
    end if;
    if n.entity_type = 'workforce_crew' then
      return '/yorks/workforce/confirm';
    end if;
    select sheet.team_id, sheet.work_date into v_team, v_date
    from public.v1_workforce_day_sheets sheet
    where sheet.id = n.entity_id;
    if v_team is null then
      return '/yorks/workforce';
    end if;
    return '/yorks/workforce/attendance?crew=' || v_team::text
      || '&date=' || to_char(v_date, 'YYYY-MM-DD');
  end if;
  return public.v1_notification_module_route_before_attendance(n);
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
  if public.v1_wf_notification_is_attendance(n) then
    if auth.uid() is distinct from n.recipient_auth_user_id then
      return null;
    end if;
    if n.entity_type = 'workforce_month_reminder' then
      select to_char(digest.period_month, 'FMMonth YYYY') || ' · '
        || digest.crew_count::text
      into v_label
      from public.v1_workforce_month_reminder_digests digest
      where digest.id = n.entity_id
        and digest.recipient_auth_user_id = n.recipient_auth_user_id;
    elsif n.entity_type = 'workforce_crew' then
      select team.team_name into v_label
      from public.v1_workforce_teams team
      where team.id = n.entity_id;
    else
      select team.team_name || ' · ' || to_char(sheet.work_date, 'DD Mon')
      into v_label
      from public.v1_workforce_day_sheets sheet
      join public.v1_workforce_teams team on team.id = sheet.team_id
      where sheet.id = n.entity_id;
    end if;
    return nullif(
      left(btrim(regexp_replace(v_label, '[[:cntrl:]]', ' ', 'g')), 180),
      ''
    );
  end if;
  return public.v1_notification_record_label_before_attendance(n);
end;
$$;

revoke all on function
  public.v1_wf_due_months(date),
  public.v1_wf_due_crew_months(date),
  public.v1_wf_send_month_end_reminders(),
  public.v1_wf_notification_is_attendance(public.v1_notifications),
  public.v1_notification_module_route(public.v1_notifications),
  public.v1_notification_record_label(public.v1_notifications)
  from public, anon, authenticated, service_role;
revoke all on function public.v1_wf_get_confirmations_due()
  from public, anon;
grant execute on function public.v1_wf_get_confirmations_due()
  to authenticated;

-- Daily at 04:05 UTC (08:05 in Dubai). A named schedule is idempotent.
do $schedule$
begin
  perform cron.schedule(
    'yorks-workforce-month-end-reminders', '5 4 * * *',
    'select public.v1_wf_send_month_end_reminders();'
  );
end;
$schedule$;




-- Self-check.
do $check$
begin
  if not exists (
      select 1 from cron.job
      where jobname = 'yorks-workforce-month-end-reminders'
        and schedule = '5 4 * * *' and active
    )
    or not has_function_privilege('authenticated',
      'public.v1_wf_get_confirmations_due()', 'execute')
    or has_function_privilege('anon',
      'public.v1_wf_get_confirmations_due()', 'execute')
    or has_function_privilege('authenticated',
      'public.v1_wf_send_month_end_reminders()', 'execute')
    or has_table_privilege('authenticated',
      'public.v1_workforce_month_reminder_digests', 'select') then
    raise exception 'month-end reminders bundle self-check failed';
  end if;
end;
$check$;

commit;

notify pgrst, 'reload schema';
