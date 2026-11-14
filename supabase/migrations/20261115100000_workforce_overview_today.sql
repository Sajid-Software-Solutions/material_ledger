-- Today on the Workforce overview (PRODUCT_DECISIONS section 58).
--
-- My sites and the office Overview show, for each place, whether today is
-- saved, who saved it last and when, and how many labourers are present,
-- absent or on leave; and across every place the reader may see, how many
-- labourers are working today (a labourer at two places counts once).
--
-- v1_wf_get_overview keeps every key it returned and adds:
--   * crews[].today: {date, entered, entered_by, last_saved_by,
--     last_saved_at, present, absent, leave, rest}
--   * today_summary: {date, places, places_entered, present, absent, leave}
-- Both read only the sheets v1_wf_crew_access lets the reader view, as the
-- crews and feed already do. No table changes; nothing is written.
--
-- Rollback: restore v1_wf_get_overview from 20261112140000 and drop
-- v1_wf_today_json(uuid,date)
-- (supabase/release/attendance_overview_today_rollback.sql).

begin;

-- One sheet's day: saved or not, by whom, and its counts by status.
create or replace function public.v1_wf_today_json(
  p_team_id uuid,
  p_work_date date
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'date', p_work_date,
    'entered', sheet.id is not null,
    'entered_by', case when sheet.id is not null
      then public.v1_wf_display_name(sheet.entered_by_auth_user_id) end,
    'last_saved_by', case when sheet.id is not null
      then public.v1_wf_display_name(sheet.last_saved_by_auth_user_id) end,
    'last_saved_at', sheet.last_saved_at,
    'present', coalesce(counted.present, 0),
    'absent', coalesce(counted.absent, 0),
    'leave', coalesce(counted.on_leave, 0),
    'rest', coalesce(counted.rest, 0)
  )
  from (select 1) anchor
  left join public.v1_workforce_day_sheets sheet
    on sheet.team_id = p_team_id and sheet.work_date = p_work_date
  left join lateral (
    select
      count(*) filter (where day_row.attendance_status = 'P') as present,
      count(*) filter (where day_row.attendance_status = 'A') as absent,
      count(*) filter (
        where day_row.attendance_status in ('AL', 'SL', 'OL', 'UL')
      ) as on_leave,
      count(*) filter (where day_row.attendance_status = 'OFF') as rest
    from public.v1_workforce_day_rows day_row
    where day_row.sheet_id = sheet.id
  ) counted on true;
$$;

create or replace function public.v1_wf_get_overview(p_month date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_today date := public.v1_wf_today();
  v_month date := date_trunc('month', coalesce(p_month, v_today))::date;
  v_teams uuid[];
  v_crews jsonb;
  v_feed jsonb;
  v_summary jsonb;
begin
  if auth.uid() is null or not public.v1_current_actor_is_active() then
    raise exception 'V1_ACTIVE_ACTOR_REQUIRED' using errcode = '42501';
  end if;

  -- The active sheets this person may view, checked once.
  select coalesce(array_agg(team.id), array[]::uuid[])
  into v_teams
  from public.v1_workforce_teams team
  join public.v1_workforce_crew_profiles profile on profile.team_id = team.id
  where profile.is_active
    and (public.v1_wf_crew_access(team.id) ->> 'view')::boolean;

  select coalesce(jsonb_agg(
    public.v1_wf_crew_json(team.id)
      || jsonb_build_object(
        'month', public.v1_wf_month_json(team.id, v_month),
        'today', public.v1_wf_today_json(team.id, v_today)
      )
    order by lower(team.team_name)
  ), '[]'::jsonb)
  into v_crews
  from public.v1_workforce_teams team
  where team.id = any(v_teams);

  -- Labourers today across those sheets: present anywhere counts once as
  -- present, else on leave, else absent.
  select jsonb_build_object(
    'date', v_today,
    'places', cardinality(v_teams),
    'places_entered', (
      select count(distinct sheet.team_id)
      from public.v1_workforce_day_sheets sheet
      where sheet.work_date = v_today and sheet.team_id = any(v_teams)
    ),
    'present', count(*) filter (where worker_day.present),
    'leave', count(*) filter (
      where not worker_day.present and worker_day.on_leave
    ),
    'absent', count(*) filter (
      where not worker_day.present and not worker_day.on_leave
        and worker_day.absent
    )
  )
  into v_summary
  from (
    select
      bool_or(day_row.attendance_status = 'P') as present,
      bool_or(day_row.attendance_status in ('AL', 'SL', 'OL', 'UL'))
        as on_leave,
      bool_or(day_row.attendance_status = 'A') as absent
    from public.v1_workforce_day_rows day_row
    where day_row.work_date = v_today and day_row.team_id = any(v_teams)
    group by day_row.worker_id
  ) worker_day;

  select coalesce(jsonb_agg(item order by occurred_at desc), '[]'::jsonb)
  into v_feed
  from (
    select
      event.occurred_at,
      jsonb_build_object(
        'id', event.id,
        'kind', event.event_kind,
        'crew_id', event.team_id,
        'crew_name', team.team_name,
        'date', event.work_date,
        'month', event.period_month,
        'summary', event.summary,
        'by', public.v1_wf_display_name(event.actor_auth_user_id),
        'at', event.occurred_at
      ) as item
    from public.v1_workforce_attendance_events event
    join public.v1_workforce_teams team on team.id = event.team_id
    where (public.v1_wf_crew_access(event.team_id) ->> 'view')::boolean
    order by event.occurred_at desc
    limit 12
  ) recent;

  return jsonb_build_object(
    'schema_version', 'yorks.workforce.overview.v2',
    'today', public.v1_wf_today(),
    'month', v_month,
    'crews', v_crews,
    'feed', v_feed,
    'today_summary', v_summary
  );
end;
$$;

revoke all on function public.v1_wf_today_json(uuid, date)
  from public, anon, authenticated;
revoke all on function public.v1_wf_get_overview(date) from public, anon;
grant execute on function public.v1_wf_get_overview(date) to authenticated;

commit;

notify pgrst, 'reload schema';
