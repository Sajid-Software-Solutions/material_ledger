-- Rollback: Today on the Workforce overview (PRODUCT_DECISIONS section 58).
-- Restores v1_wf_get_overview from 20261112140000 (no today per place, no
-- today_summary) and drops the helper. Nothing in data changes. The app
-- falls back to its earlier figures when today is missing.
--   npx supabase@latest db query --remote=<ref> --yes -f supabase/release/attendance_overview_today_rollback.sql

begin;

create or replace function public.v1_wf_get_overview(p_month date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_month date := date_trunc('month', coalesce(p_month, public.v1_wf_today()))::date;
  v_crews jsonb;
  v_feed jsonb;
begin
  if auth.uid() is null or not public.v1_current_actor_is_active() then
    raise exception 'V1_ACTIVE_ACTOR_REQUIRED' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(
    public.v1_wf_crew_json(team.id)
      || jsonb_build_object(
        'month', public.v1_wf_month_json(team.id, v_month)
      )
    order by lower(team.team_name)
  ), '[]'::jsonb)
  into v_crews
  from public.v1_workforce_teams team
  join public.v1_workforce_crew_profiles profile on profile.team_id = team.id
  where profile.is_active
    and (public.v1_wf_crew_access(team.id) ->> 'view')::boolean;

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
    'feed', v_feed
  );
end;
$$;

drop function if exists public.v1_wf_today_json(uuid, date);

revoke all on function public.v1_wf_get_overview(date) from public, anon;
grant execute on function public.v1_wf_get_overview(date) to authenticated;

commit;

notify pgrst, 'reload schema';
