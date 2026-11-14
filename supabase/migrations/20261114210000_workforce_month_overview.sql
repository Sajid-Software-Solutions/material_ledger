-- Workforce month overview, labour timesheets and the year summary (owner
-- decisions, 14 November 2026; PRODUCT_DECISIONS section 52).
--
--   * Everyone's month: every labourer recorded at the places the reader may
--     see, day by day, for any month (earlier months included).
--   * One labourer's month: every row at every place the reader may see,
--     with times, building, hours and who saved it, for the printed
--     timesheet.
--   * The workforce year: month by month, place by place and labourer by
--     labourer totals for a year, plus the active labour headcount for those
--     who see every place (Admin, HR/PRO, the Accountant and the
--     organization-wide engineers).
--
-- Read only. What a reader sees is exactly the sheets v1_wf_crew_access
-- lets them view: Site and Project Engineers their projects, everyone with
-- organization-wide Workforce access every place. No table changes.
-- Rollback: drop the five functions.

begin;

-- The sheets the signed-in person may view.
create or replace function public.v1_wf_visible_teams()
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(profile.team_id), array[]::uuid[])
  from public.v1_workforce_crew_profiles profile
  where coalesce(
    (public.v1_wf_crew_access(profile.team_id) ->> 'view')::boolean, false
  );
$$;

-- Roles with Workforce: those who keep or read attendance. Procurement and
-- other roles are refused rather than shown an empty month.
create or replace function public.v1_wf_reads_workforce()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.v1_wf_allowed('workforce.view')
    and (
      public.v1_current_exact_role() in (
        'admin', 'pr', 'accountant', 'site_engineer', 'project_engineer'
      )
      or public.v1_wf_role_is_global(public.v1_current_exact_role())
    );
$$;

-- Everyone's month: one entry per labourer, place and day.
create or replace function public.v1_wf_people_month(p_month date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_month date := date_trunc(
    'month', coalesce(p_month, public.v1_wf_today())
  )::date;
  v_last date;
  v_teams uuid[];
begin
  if auth.uid() is null or not public.v1_current_actor_is_active() then
    raise exception 'V1_ACTIVE_ACTOR_REQUIRED' using errcode = '42501';
  end if;
  if not public.v1_wf_reads_workforce() then
    raise exception 'V1_WORKFORCE_CREW_ACCESS_DENIED' using errcode = '42501';
  end if;
  v_last := (v_month + interval '1 month - 1 day')::date;
  v_teams := public.v1_wf_visible_teams();

  return (
    with month_rows as (
      select day_row.*
      from public.v1_workforce_day_rows day_row
      where day_row.team_id = any(v_teams)
        and day_row.work_date between v_month and v_last
    )
    select jsonb_build_object(
      'schema_version', 'yorks.workforce.people_month.v1',
      'today', public.v1_wf_today(),
      'month', v_month,
      'last_day', v_last,
      'days', (
        select jsonb_agg(jsonb_build_object(
          'date', series.day_ts::date,
          'day_type', public.v1_wf_day_type(series.day_ts::date),
          'holiday_name', (
            select holiday.holiday_name
            from public.v1_workforce_public_holidays holiday
            where holiday.holiday_date = series.day_ts::date
          )
        ) order by series.day_ts)
        from generate_series(v_month, v_last, interval '1 day') series(day_ts)
      ),
      'workers', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', worker.id,
          'number', worker.worker_number,
          'name', worker.full_name,
          'designation', worker.designation,
          'company', worker.employer_company
        ) order by lower(worker.full_name), worker.id)
        from public.v1_workforce_workers worker
        where worker.id in (select worker_id from month_rows)
      ), '[]'::jsonb),
      'places', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', team.id,
          'name', team.team_name,
          'project_id', profile.project_id,
          'project_ref', project.project_ref,
          'project_name', project.name,
          'place_kind', case
            when profile.place_key like 'project:%' then 'project'
            when profile.place_key like 'location:%' then 'location'
          end,
          'confirmed', coalesce((
            select confirmation.is_confirmed
            from public.v1_workforce_month_confirmations confirmation
            where confirmation.team_id = team.id
              and confirmation.period_month = v_month
          ), false)
        ) order by lower(team.team_name), team.id)
        from public.v1_workforce_teams team
        join public.v1_workforce_crew_profiles profile
          on profile.team_id = team.id
        left join public.v1_projects project on project.id = profile.project_id
        where team.id in (select team_id from month_rows)
      ), '[]'::jsonb),
      'entries', coalesce((
        select jsonb_agg(jsonb_build_object(
          'w', month_row.worker_id,
          'd', month_row.work_date,
          'c', month_row.team_id,
          's', month_row.attendance_status,
          'm', month_row.worked_minutes,
          'r', month_row.regular_minutes,
          'o', month_row.normal_overtime_minutes,
          'h', month_row.holiday_overtime_minutes
        ) order by month_row.work_date, month_row.start_minute nulls last,
          month_row.id)
        from month_rows month_row
      ), '[]'::jsonb)
    )
  );
end;
$$;

-- One labourer's month at every place the reader may see.
create or replace function public.v1_wf_worker_month(
  p_worker_id uuid,
  p_month date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_month date := date_trunc(
    'month', coalesce(p_month, public.v1_wf_today())
  )::date;
  v_last date;
  v_teams uuid[];
  v_worker jsonb;
begin
  if auth.uid() is null or not public.v1_current_actor_is_active() then
    raise exception 'V1_ACTIVE_ACTOR_REQUIRED' using errcode = '42501';
  end if;
  if not public.v1_wf_reads_workforce() then
    raise exception 'V1_WORKFORCE_CREW_ACCESS_DENIED' using errcode = '42501';
  end if;
  v_last := (v_month + interval '1 month - 1 day')::date;
  v_teams := public.v1_wf_visible_teams();

  select jsonb_build_object(
    'id', worker.id,
    'number', worker.worker_number,
    'name', worker.full_name,
    'designation', worker.designation,
    'company', worker.employer_company
  )
  into v_worker
  from public.v1_workforce_workers worker
  where worker.id = p_worker_id;
  if v_worker is null then
    raise exception 'V1_WORKFORCE_WORKER_NOT_FOUND' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'schema_version', 'yorks.workforce.worker_month.v1',
    'today', public.v1_wf_today(),
    'month', v_month,
    'last_day', v_last,
    'worker', v_worker,
    'days', (
      select jsonb_agg(jsonb_build_object(
        'date', series.day_ts::date,
        'day_type', public.v1_wf_day_type(series.day_ts::date),
        'holiday_name', (
          select holiday.holiday_name
          from public.v1_workforce_public_holidays holiday
          where holiday.holiday_date = series.day_ts::date
        )
      ) order by series.day_ts)
      from generate_series(v_month, v_last, interval '1 day') series(day_ts)
    ),
    'rows', coalesce((
      select jsonb_agg(
        public.v1_wf_row_json(day_row)
          || jsonb_build_object(
            'date', day_row.work_date,
            'crew_id', day_row.team_id,
            'crew_name', team.team_name,
            'project_ref', coalesce(work_project.project_ref, project.project_ref),
            'project_name', coalesce(work_project.name, project.name),
            'confirmed', coalesce(confirmation.is_confirmed, false),
            'confirmed_by', public.v1_wf_display_name(
              confirmation.confirmed_by_auth_user_id
            )
          )
        order by day_row.work_date, day_row.start_minute nulls last,
          day_row.id
      )
      from public.v1_workforce_day_rows day_row
      join public.v1_workforce_teams team on team.id = day_row.team_id
      join public.v1_workforce_crew_profiles profile
        on profile.team_id = day_row.team_id
      left join public.v1_projects project on project.id = profile.project_id
      left join public.v1_projects work_project
        on work_project.id = day_row.work_project_id
      left join public.v1_workforce_month_confirmations confirmation
        on confirmation.team_id = day_row.team_id
        and confirmation.period_month = v_month
      where day_row.worker_id = p_worker_id
        and day_row.team_id = any(v_teams)
        and day_row.work_date between v_month and v_last
    ), '[]'::jsonb)
  );
end;
$$;

-- The workforce year: totals by month, by place and by labourer. A day
-- counts once per labourer: present when present anywhere, else on leave,
-- else absent.
create or replace function public.v1_wf_workforce_year(p_year integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text := public.v1_current_exact_role();
  v_year integer := coalesce(
    p_year, extract(year from public.v1_wf_today())::integer
  );
  v_from date;
  v_to date;
  v_teams uuid[];
  v_everywhere boolean;
begin
  if auth.uid() is null or not public.v1_current_actor_is_active() then
    raise exception 'V1_ACTIVE_ACTOR_REQUIRED' using errcode = '42501';
  end if;
  if not public.v1_wf_reads_workforce() then
    raise exception 'V1_WORKFORCE_CREW_ACCESS_DENIED' using errcode = '42501';
  end if;
  if v_year < 2000 or v_year > 2100 then
    raise exception 'V1_WORKFORCE_DATE_REQUIRED' using errcode = '22023';
  end if;
  v_from := make_date(v_year, 1, 1);
  v_to := make_date(v_year, 12, 31);
  v_teams := public.v1_wf_visible_teams();
  v_everywhere := v_role in ('admin', 'pr', 'accountant')
    or public.v1_wf_role_is_global(v_role);

  return (
    with year_rows as (
      select day_row.*
      from public.v1_workforce_day_rows day_row
      where day_row.team_id = any(v_teams)
        and day_row.work_date between v_from and v_to
    ),
    worker_days as (
      select
        year_row.worker_id,
        year_row.work_date,
        case
          when bool_or(year_row.attendance_status = 'P') then 'P'
          when bool_or(year_row.attendance_status in ('AL', 'SL', 'OL', 'UL'))
            then 'L'
          when bool_or(year_row.attendance_status = 'A') then 'A'
          else 'OFF'
        end as status,
        sum(year_row.worked_minutes) as worked,
        sum(year_row.regular_minutes) as regular,
        sum(year_row.normal_overtime_minutes) as normal_ot,
        sum(year_row.holiday_overtime_minutes) as holiday_ot
      from year_rows year_row
      group by year_row.worker_id, year_row.work_date
    )
    select jsonb_build_object(
      'schema_version', 'yorks.workforce.year.v1',
      'today', public.v1_wf_today(),
      'year', v_year,
      'labour_headcount', case when v_everywhere then (
        select count(*)
        from public.v1_workforce_workers worker
        where worker.current_status = 'active'
          and public.v1_wf_is_labour(worker.id)
      ) end,
      'months', (
        select jsonb_agg(jsonb_build_object(
          'month', months.month_start,
          'workers', coalesce(totals.workers, 0),
          'present_days', coalesce(totals.present_days, 0),
          'absent_days', coalesce(totals.absent_days, 0),
          'leave_days', coalesce(totals.leave_days, 0),
          'worked_minutes', coalesce(totals.worked, 0),
          'regular_minutes', coalesce(totals.regular, 0),
          'normal_overtime_minutes', coalesce(totals.normal_ot, 0),
          'holiday_overtime_minutes', coalesce(totals.holiday_ot, 0)
        ) order by months.month_start)
        from (
          select make_date(v_year, month_number, 1) as month_start
          from generate_series(1, 12) month_number
        ) months
        left join lateral (
          select
            count(distinct worker_day.worker_id)
              filter (where worker_day.status = 'P') as workers,
            count(*) filter (where worker_day.status = 'P') as present_days,
            count(*) filter (where worker_day.status = 'A') as absent_days,
            count(*) filter (where worker_day.status = 'L') as leave_days,
            sum(worker_day.worked) as worked,
            sum(worker_day.regular) as regular,
            sum(worker_day.normal_ot) as normal_ot,
            sum(worker_day.holiday_ot) as holiday_ot
          from worker_days worker_day
          where date_trunc('month', worker_day.work_date)::date
            = months.month_start
        ) totals on true
      ),
      'places', coalesce((
        select jsonb_agg(entry order by entry ->> 'sort')
        from (
          select jsonb_build_object(
            'id', team.id,
            'name', team.team_name,
            'project_ref', project.project_ref,
            'project_name', project.name,
            'workers', count(distinct year_row.worker_id)
              filter (where year_row.attendance_status = 'P'),
            'present_days', count(*)
              filter (where year_row.attendance_status = 'P'),
            'worked_minutes', sum(year_row.worked_minutes),
            'regular_minutes', sum(year_row.regular_minutes),
            'normal_overtime_minutes', sum(year_row.normal_overtime_minutes),
            'holiday_overtime_minutes', sum(year_row.holiday_overtime_minutes),
            'sort', lower(team.team_name)
          ) as entry
          from year_rows year_row
          join public.v1_workforce_teams team on team.id = year_row.team_id
          join public.v1_workforce_crew_profiles profile
            on profile.team_id = team.id
          left join public.v1_projects project
            on project.id = profile.project_id
          group by team.id, team.team_name, project.project_ref, project.name
        ) places
      ), '[]'::jsonb),
      'workers', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', worker.id,
          'number', worker.worker_number,
          'name', worker.full_name,
          'designation', worker.designation,
          'company', worker.employer_company,
          'present_days', totals.present_days,
          'absent_days', totals.absent_days,
          'leave_days', totals.leave_days,
          'worked_minutes', totals.worked,
          'regular_minutes', totals.regular,
          'normal_overtime_minutes', totals.normal_ot,
          'holiday_overtime_minutes', totals.holiday_ot
        ) order by lower(worker.full_name), worker.id)
        from (
          select
            worker_day.worker_id,
            count(*) filter (where worker_day.status = 'P') as present_days,
            count(*) filter (where worker_day.status = 'A') as absent_days,
            count(*) filter (where worker_day.status = 'L') as leave_days,
            sum(worker_day.worked) as worked,
            sum(worker_day.regular) as regular,
            sum(worker_day.normal_ot) as normal_ot,
            sum(worker_day.holiday_ot) as holiday_ot
          from worker_days worker_day
          group by worker_day.worker_id
        ) totals
        join public.v1_workforce_workers worker on worker.id = totals.worker_id
      ), '[]'::jsonb)
    )
  );
end;
$$;

do $grants$
declare
  v_signature text;
begin
  execute 'revoke all on function public.v1_wf_visible_teams() '
    'from public, anon, authenticated';
  execute 'revoke all on function public.v1_wf_reads_workforce() '
    'from public, anon, authenticated';
  foreach v_signature in array array[
    'v1_wf_people_month(date)',
    'v1_wf_worker_month(uuid,date)',
    'v1_wf_workforce_year(integer)'
  ] loop
    execute format(
      'revoke all on function public.%s from public, anon', v_signature
    );
    execute format(
      'grant execute on function public.%s to authenticated', v_signature
    );
  end loop;
end;
$grants$;

commit;

notify pgrst, 'reload schema';
