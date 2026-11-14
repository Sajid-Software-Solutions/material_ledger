-- Read-only preflight for supabase/release/attendance_by_role_bundle.sql
-- (PRODUCT_DECISIONS.md section 58). Changes nothing; returns one JSON row
-- with no personal data (place names, roles and counts only).
--   npx supabase@latest db query --remote=<ref> -f supabase/preflight/attendance_by_role_preflight.sql
--
-- Proceed when live_access_is_places_version is true. internal_places and
-- internal_lines_by_role show who keeps the workshop and other internal
-- places today: Site and Project Engineers, Senior Mechanical Engineers and
-- Project Managers listed there stop keeping those places after the bundle
-- (their saved lines stay as saved).

select jsonb_build_object(
  'live_access_is_places_version',
    position('v_location_place' in pg_get_functiondef(
      'public.v1_wf_crew_access(uuid)'::regprocedure)) > 0,
  'keeps_internal_helper_exists',
    to_regprocedure('public.v1_wf_role_keeps_internal(text)') is not null,
  'internal_places', coalesce((
    select jsonb_agg(jsonb_build_object(
      'place', team.team_name,
      'place_key', profile.place_key,
      'active', profile.is_active and team.is_active,
      'needs_confirmation', profile.needs_confirmation,
      'opened_by_role', coalesce(opener.raw_app_meta_data ->> 'role', ''),
      'lines', (select count(*) from public.v1_workforce_day_rows day_row
        where day_row.team_id = team.id),
      'last_day', (select max(sheet.work_date)
        from public.v1_workforce_day_sheets sheet
        where sheet.team_id = team.id)
    ) order by team.team_name)
    from public.v1_workforce_crew_profiles profile
    join public.v1_workforce_teams team on team.id = profile.team_id
    left join auth.users opener
      on opener.id = profile.created_by_auth_user_id
    where profile.project_id is null
  ), '[]'::jsonb),
  'internal_lines_by_role_last_60_days', coalesce((
    select jsonb_object_agg(saved.role, jsonb_build_object(
      'people', saved.people, 'lines', saved.lines))
    from (
      select coalesce(saver.raw_app_meta_data ->> 'role', '') as role,
        count(distinct day_row.updated_by_auth_user_id) as people,
        count(*) as lines
      from public.v1_workforce_day_rows day_row
      join public.v1_workforce_crew_profiles profile
        on profile.team_id = day_row.team_id
      left join auth.users saver
        on saver.id = day_row.updated_by_auth_user_id
      where profile.project_id is null
        and day_row.work_date >= current_date - 60
      group by 1
    ) saved
  ), '{}'::jsonb),
  'accounts_by_role', coalesce((
    select jsonb_object_agg(counted.role, counted.accounts)
    from (
      select raw_app_meta_data ->> 'role' as role, count(*) as accounts
      from auth.users
      where raw_app_meta_data ->> 'role' in ('accountant', 'workshop_in_charge')
        and (banned_until is null or banned_until <= now())
      group by 1
    ) counted
  ), '{}'::jsonb)
) as attendance_by_role_preflight;
