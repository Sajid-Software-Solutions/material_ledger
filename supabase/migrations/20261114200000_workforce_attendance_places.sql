-- Workforce attendance at places, with no crews to set up (owner decisions,
-- 14 November 2026; PRODUCT_DECISIONS section 51).
--
--   * Attendance is taken at a place: a project, or an internal location such
--     as the workshop or the store. The first person who keeps attendance
--     there opens the place, and it becomes the one shared sheet for it.
--     Everyone who keeps attendance at that place adds the labourers they
--     have that day; nobody sets up crews or members.
--   * A project's existing active sheet (the oldest) becomes that project's
--     place, with every day, row and month it already has. Its default shift
--     for new rows becomes 06:30 for 8 hours plus its break, so new rows carry
--     no overtime. Saved rows are not touched.
--   * Each row records the building (or Common) of the project it was worked
--     on. On a project's place every row is on that project.
--   * Changing or removing a row someone else saved needs a reason, is logged
--     and tells them. Adding a row, or saving a row again unchanged, never
--     does, and an unchanged row keeps who saved it.
--   * A place has no members, so a working day with no sheet there simply had
--     nobody recorded: it is not "missing", does not hold up the month, and a
--     place is due for confirmation only in a month it has days.
--   * Opening a place is a find-or-create on its unique key under a lock, so
--     a retry or two people opening it at once get the same place.
--
-- Data preservation: no row, sheet, change, question or month is changed or
-- removed. The adopted sheet keeps its name, history and confirmations; only
-- its default shift for new rows changes. Crews, crew members and crew
-- requests stay stored. Production holds one sheet (project DF3W, 2 rows).
-- Rollback: restore the functions from 20261114170000, 20261113090000 and
-- 20261112140000 and drop v1_wf_list_places, v1_wf_open_place and
-- v1_wf_project_buildings; the two new nullable columns may stay.

begin;

-- ---------------------------------------------------------------------------
-- 1. A sheet may be a place; a row may name its building.
-- ---------------------------------------------------------------------------

alter table public.v1_workforce_crew_profiles
  add column if not exists place_key text;

do $schema$
begin
  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conname = 'v1_workforce_crew_profiles_place_key_check'
  ) then
    alter table public.v1_workforce_crew_profiles
      add constraint v1_workforce_crew_profiles_place_key_check check (
        place_key is null
        or place_key ~ '^project:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        or (
          place_key like 'location:%'
          and char_length(place_key) between 10 and 89
          and place_key = lower(place_key)
        )
      );
  end if;
  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conname = 'v1_workforce_crew_profiles_place_project_check'
  ) then
    alter table public.v1_workforce_crew_profiles
      add constraint v1_workforce_crew_profiles_place_project_check check (
        place_key is null
        or (place_key like 'project:%')
          = (crew_kind = 'project' and project_id is not null
            and place_key = 'project:' || project_id::text)
      );
  end if;
end;
$schema$;

create unique index if not exists v1_workforce_crew_profiles_place_uidx
  on public.v1_workforce_crew_profiles (place_key)
  where place_key is not null;

alter table public.v1_workforce_day_rows
  add column if not exists work_scope_id uuid;

do $rows$
begin
  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conname = 'v1_workforce_day_rows_work_scope_fkey'
  ) then
    alter table public.v1_workforce_day_rows
      add constraint v1_workforce_day_rows_work_scope_fkey
      foreign key (work_project_id, work_scope_id)
      references public.v1_project_scopes (project_id, id)
      on delete restrict;
  end if;
  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conname = 'v1_workforce_day_rows_work_scope_check'
  ) then
    alter table public.v1_workforce_day_rows
      add constraint v1_workforce_day_rows_work_scope_check check (
        work_scope_id is null or work_project_id is not null
      );
  end if;
end;
$rows$;

-- ---------------------------------------------------------------------------
-- 2. Helpers and projections.
-- ---------------------------------------------------------------------------

-- A project's active buildings, Common first.
create or replace function public.v1_wf_project_buildings(p_project_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case when p_project_id is null then '[]'::jsonb else coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', scope.id,
      'name', scope.name,
      'kind', scope.scope_kind
    ) order by scope.scope_kind <> 'common', lower(scope.name), scope.id)
    from public.v1_project_scopes scope
    where scope.project_id = p_project_id and scope.is_active
  ), '[]'::jsonb) end;
$$;

create or replace function public.v1_wf_crew_access(p_team_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_role text := public.v1_current_exact_role();
  v_profile public.v1_workforce_crew_profiles%rowtype;
  v_member boolean := false;
  v_pe_member boolean := false;
  v_officer boolean;
  v_global_view boolean;
  v_global_keep boolean;
  v_keeper boolean;
  v_view boolean;
  v_take boolean;
  v_confirm boolean;
  v_manage boolean;
  v_location_place boolean;
begin
  if v_actor is null or v_role = ''
    or not public.v1_current_actor_is_active() then
    return jsonb_build_object(
      'view', false, 'take', false, 'confirm', false, 'manage', false,
      'officer', false, 'keeper', false
    );
  end if;
  select * into v_profile
  from public.v1_workforce_crew_profiles profile
  where profile.team_id = p_team_id;
  if not found then
    return jsonb_build_object(
      'view', false, 'take', false, 'confirm', false, 'manage', false,
      'officer', false, 'keeper', false
    );
  end if;

  -- An internal location (workshop, store) is kept by everyone who keeps
  -- attendance.
  v_location_place := coalesce(v_profile.place_key like 'location:%', false);
  v_officer := v_role in ('admin', 'pr');
  -- Senior Mechanical Engineer, Project Manager, Workshop In-Charge and
  -- Document Controller see every sheet; all but Document Controller keep.
  v_global_view := public.v1_wf_role_is_global(v_role);
  v_global_keep := v_global_view and v_role <> 'document_controller';
  v_keeper := v_profile.created_by_auth_user_id = v_actor
    and public.v1_wf_role_can_keep(v_role);
  if v_profile.project_id is not null then
    select
      coalesce(bool_or(true), false),
      coalesce(bool_or(member.project_role = 'project_engineer'), false)
    into v_member, v_pe_member
    from public.v1_project_members member
    where member.project_id = v_profile.project_id
      and member.member_auth_user_id = v_actor
      and member.effective_from <= clock_timestamp()
      and (member.effective_to is null
        or member.effective_to > clock_timestamp());
  end if;

  v_view := (
      v_officer or v_global_view or v_role = 'accountant' or v_keeper
      or (v_role in ('project_engineer', 'site_engineer') and v_member)
      or (v_location_place and public.v1_wf_role_can_keep(v_role))
    )
    and public.v1_wf_allowed('workforce.view');
  v_take := v_view
    and (
      v_officer or v_global_keep or v_keeper
      or (v_role in ('project_engineer', 'site_engineer') and v_member)
      or (v_location_place and public.v1_wf_role_can_keep(v_role))
    )
    and public.v1_wf_allowed('workforce.attendance.maintain');
  v_confirm := v_view
    and v_profile.needs_confirmation
    and (
      v_role in ('admin', 'senior_mechanical_engineer')
      or (
        v_profile.project_id is not null
        and v_role in ('project_engineer', 'site_engineer')
        and v_pe_member
      )
    )
    and public.v1_wf_allowed('workforce.timesheets.final_approve');
  v_manage := v_view
    and (
      v_officer or v_global_keep or v_keeper
      or (v_role in ('project_engineer', 'site_engineer') and v_pe_member)
    )
    and public.v1_wf_allowed('workforce.teams.manage');

  return jsonb_build_object(
    'view', v_view,
    'take', v_take,
    'confirm', v_confirm,
    'manage', v_manage,
    'officer', v_officer and v_view,
    'keeper', v_keeper and v_view
  );
end;
$$;

create or replace function public.v1_wf_crew_json(p_team_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', team.id,
    'name', team.team_name,
    'code', team.team_code,
    'kind', profile.crew_kind,
    'project_id', profile.project_id,
    'project_ref', project.project_ref,
    'project_name', project.name,
    'work_label', coalesce(
      profile.work_label,
      case when project.id is not null
        then project.name || ' · ' || project.project_ref end,
      team.team_name
    ),
    'needs_confirmation', profile.needs_confirmation,
    'shift_start_minute', profile.shift_start_minute,
    'shift_finish_minute', profile.shift_finish_minute,
    'break_start_minute', profile.break_start_minute,
    'break_finish_minute', profile.break_finish_minute,
    'is_active', profile.is_active and team.is_active,
    'record_version', profile.record_version,
    'place_key', profile.place_key,
    'place_kind', case
      when profile.place_key like 'project:%' then 'project'
      when profile.place_key like 'location:%' then 'location'
    end,
    'buildings', public.v1_wf_project_buildings(profile.project_id),
    'member_count', (
      select count(*) from public.v1_workforce_crew_members member
      where member.team_id = team.id and member.removed_at is null
    ),
    'access', public.v1_wf_crew_access(team.id)
  )
  from public.v1_workforce_teams team
  join public.v1_workforce_crew_profiles profile on profile.team_id = team.id
  left join public.v1_projects project on project.id = profile.project_id
  where team.id = p_team_id;
$$;

create or replace function public.v1_wf_row_json(
  p_row public.v1_workforce_day_rows
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'worker_id', p_row.worker_id,
    'status', p_row.attendance_status,
    'start_minute', p_row.start_minute,
    'break_start_minute', p_row.break_start_minute,
    'break_finish_minute', p_row.break_finish_minute,
    'finish_minute', p_row.finish_minute,
    'work_project_id', p_row.work_project_id,
    'work_label', p_row.work_label,
    'work_scope_id', p_row.work_scope_id,
    'work_scope_name', (
      select scope.name from public.v1_project_scopes scope
      where scope.id = p_row.work_scope_id
    ),
    'work_scope_kind', (
      select scope.scope_kind from public.v1_project_scopes scope
      where scope.id = p_row.work_scope_id
    ),
    'updated_by', public.v1_wf_display_name(p_row.updated_by_auth_user_id),
    'updated_by_me', p_row.updated_by_auth_user_id = auth.uid(),
    'overtime_note', p_row.overtime_note,
    'copied', p_row.copied,
    'changed_after_entry', p_row.changed_after_entry,
    'worked_minutes', p_row.worked_minutes,
    'regular_minutes', p_row.regular_minutes,
    'normal_overtime_minutes', p_row.normal_overtime_minutes,
    'holiday_overtime_minutes', p_row.holiday_overtime_minutes
  );
$$;

create or replace function public.v1_wf_get_day(
  p_team_id uuid,
  p_work_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_access jsonb;
  v_sheet public.v1_workforce_day_sheets%rowtype;
  v_has_sheet boolean;
  v_rows jsonb;
  v_previous date;
  v_question jsonb;
  v_changes jsonb;
  v_day_type text;
begin
  perform public.v1_wf_assert_crew(p_team_id, 'view');
  if p_work_date is null then
    raise exception 'V1_WORKFORCE_DATE_REQUIRED' using errcode = '22023';
  end if;
  v_access := public.v1_wf_crew_access(p_team_id);
  v_day_type := public.v1_wf_day_type(p_work_date);

  select * into v_sheet
  from public.v1_workforce_day_sheets sheet
  where sheet.team_id = p_team_id and sheet.work_date = p_work_date;
  v_has_sheet := found;

  -- Saved rows first; then current members who have no row yet.
  select coalesce(jsonb_agg(entry order by entry ->> 'sort_name'), '[]'::jsonb)
  into v_rows
  from (
    select public.v1_wf_row_json(day_row)
      || jsonb_build_object(
        'worker', public.v1_wf_worker_json(day_row.worker_id),
        'is_member', exists (
          select 1 from public.v1_workforce_crew_members member
          where member.team_id = p_team_id
            and member.worker_id = day_row.worker_id
            and member.removed_at is null
        ),
        'elsewhere', public.v1_wf_elsewhere_json(
          day_row.worker_id, p_work_date, p_team_id
        ),
        'sort_name', lower(worker.full_name)
      ) as entry
    from public.v1_workforce_day_rows day_row
    join public.v1_workforce_workers worker on worker.id = day_row.worker_id
    where day_row.sheet_id = v_sheet.id
    union all
    select jsonb_build_object(
      'worker_id', member.worker_id,
      'status', null,
      'worker', public.v1_wf_worker_json(member.worker_id),
      'is_member', true,
      'elsewhere', public.v1_wf_elsewhere_json(
        member.worker_id, p_work_date, p_team_id
      ),
      'sort_name', lower(worker.full_name)
    )
    from public.v1_workforce_crew_members member
    join public.v1_workforce_workers worker on worker.id = member.worker_id
    where member.team_id = p_team_id
      and member.removed_at is null
      and worker.current_status = 'active'
      and not exists (
        select 1 from public.v1_workforce_crew_profiles place
        where place.team_id = p_team_id and place.place_key is not null
      )
      and not exists (
        select 1 from public.v1_workforce_day_rows day_row
        where day_row.sheet_id = v_sheet.id
          and day_row.worker_id = member.worker_id
      )
  ) rows_source;

  select max(sheet.work_date) into v_previous
  from public.v1_workforce_day_sheets sheet
  where sheet.team_id = p_team_id
    and sheet.work_date < p_work_date
    and public.v1_wf_day_type(sheet.work_date) = v_day_type;

  select jsonb_build_object(
    'id', question.id,
    'question', question.question,
    'asked_by', public.v1_wf_display_name(question.asked_by_auth_user_id),
    'asked_at', question.asked_at,
    'answer', question.answer,
    'answered_by', public.v1_wf_display_name(question.answered_by_auth_user_id),
    'answered_at', question.answered_at,
    'is_open', question.answer is null
  )
  into v_question
  from public.v1_workforce_day_questions question
  where question.sheet_id = v_sheet.id
  order by question.asked_at desc
  limit 1;

  select coalesce(jsonb_agg(jsonb_build_object(
    'worker_id', change.worker_id,
    'worker_name', worker.full_name,
    'before', change.before_data,
    'after', change.after_data,
    'reason', change.reason,
    'by', public.v1_wf_display_name(change.actor_auth_user_id),
    'at', change.occurred_at
  ) order by change.occurred_at), '[]'::jsonb)
  into v_changes
  from public.v1_workforce_day_changes change
  join public.v1_workforce_workers worker on worker.id = change.worker_id
  where change.sheet_id = v_sheet.id;

  return jsonb_build_object(
    'schema_version', 'yorks.workforce.day.v2',
    'crew', public.v1_wf_crew_json(p_team_id),
    'date', p_work_date,
    'today', public.v1_wf_today(),
    'day_type', v_day_type,
    'holiday_name', (
      select holiday.holiday_name
      from public.v1_workforce_public_holidays holiday
      where holiday.holiday_date = p_work_date
    ),
    'saved', v_has_sheet,
    'record_version', case when v_has_sheet then v_sheet.record_version else 0 end,
    'entered_by', case when v_has_sheet
      then public.v1_wf_display_name(v_sheet.entered_by_auth_user_id) end,
    'entered_by_me', v_has_sheet
      and v_sheet.entered_by_auth_user_id = auth.uid(),
    'entered_at', v_sheet.entered_at,
    'entered_late', coalesce(v_sheet.entered_late, false),
    'last_saved_by', case when v_has_sheet
      then public.v1_wf_display_name(v_sheet.last_saved_by_auth_user_id) end,
    'last_saved_at', v_sheet.last_saved_at,
    'locked', public.v1_wf_month_locked(p_team_id, p_work_date),
    'is_future', p_work_date > public.v1_wf_today(),
    'previous_same_type_date', v_previous,
    'rows', v_rows,
    'question', v_question,
    'changes', v_changes,
    'access', v_access,
    'month', public.v1_wf_month_json(p_team_id, p_work_date)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Places.
-- ---------------------------------------------------------------------------

-- The places the signed-in person may keep or read: projects (with their
-- buildings and whether the place is open) and internal locations.
create or replace function public.v1_wf_list_places()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_role text := public.v1_current_exact_role();
  v_keep boolean;
  v_everywhere boolean;
begin
  if v_actor is null or v_role = ''
    or not public.v1_current_actor_is_active() then
    raise exception 'V1_ACTIVE_ACTOR_REQUIRED' using errcode = '42501';
  end if;
  v_keep := public.v1_wf_role_can_keep(v_role)
    and public.v1_wf_allowed('workforce.attendance.maintain');
  -- Site and Project Engineers keep attendance on projects they are on;
  -- every other keeper on any project.
  v_everywhere := v_role not in ('site_engineer', 'project_engineer');
  return jsonb_build_object(
    'schema_version', 'yorks.workforce.places.v1',
    'today', public.v1_wf_today(),
    'can_take', v_keep,
    'projects', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', project.id,
        'ref', project.project_ref,
        'name', project.name,
        'buildings', public.v1_wf_project_buildings(project.id),
        'crew_id', place.team_id,
        'is_member', membership.is_member,
        'can_take', case
          when place.team_id is not null then coalesce(
            (public.v1_wf_crew_access(place.team_id) ->> 'take')::boolean,
            false
          )
          else v_keep
            and project.state in ('draft', 'active', 'on_hold')
            and (v_everywhere or membership.is_member)
        end
      ) order by not membership.is_member, lower(project.name), project.id)
      from public.v1_projects project
      left join public.v1_workforce_crew_profiles place
        on place.place_key = 'project:' || project.id::text
      cross join lateral (
        select exists (
          select 1 from public.v1_project_members member
          where member.project_id = project.id
            and member.member_auth_user_id = v_actor
            and member.effective_from <= clock_timestamp()
            and (member.effective_to is null
              or member.effective_to > clock_timestamp())
        ) as is_member
      ) membership
      where (
          v_keep
          and project.state in ('draft', 'active', 'on_hold')
          and (v_everywhere or membership.is_member)
        )
        or (
          place.team_id is not null
          and coalesce(
            (public.v1_wf_crew_access(place.team_id) ->> 'view')::boolean,
            false
          )
        )
    ), '[]'::jsonb),
    'locations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'crew_id', team.id,
        'name', team.team_name,
        'can_take', coalesce((access.value ->> 'take')::boolean, false)
      ) order by lower(team.team_name), team.id)
      from public.v1_workforce_crew_profiles profile
      join public.v1_workforce_teams team on team.id = profile.team_id
      cross join lateral (
        select public.v1_wf_crew_access(team.id) as value
      ) access
      where profile.place_key like 'location:%'
        and profile.is_active
        and team.is_active
        and coalesce((access.value ->> 'view')::boolean, false)
    ), '[]'::jsonb)
  );
end;
$$;

-- Opens the place for a project or an internal location and returns its
-- sheet: the existing place, else the project's (or same-named location's)
-- oldest active sheet, else a new one. Only people who keep attendance there
-- open a new place; an open place is returned to anyone who may read it.
create or replace function public.v1_wf_open_place(
  p_project_id uuid,
  p_location text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_role text := public.v1_current_exact_role();
  v_label text := nullif(
    regexp_replace(btrim(coalesce(p_location, '')), '\s+', ' ', 'g'), ''
  );
  v_key text;
  v_team uuid;
  v_project public.v1_projects%rowtype;
  v_profile public.v1_workforce_crew_profiles%rowtype;
  v_name text;
  v_finish integer;
  v_adopted boolean := false;
begin
  if v_actor is null or v_role = ''
    or not public.v1_current_actor_is_active() then
    raise exception 'V1_ACTIVE_ACTOR_REQUIRED' using errcode = '42501';
  end if;
  if (p_project_id is null) = (v_label is null)
    or char_length(coalesce(v_label, '')) > 80 then
    raise exception 'V1_WORKFORCE_CREW_INVALID' using errcode = '22023';
  end if;
  v_key := case when p_project_id is not null
    then 'project:' || p_project_id::text
    else 'location:' || lower(v_label) end;

  select profile.team_id into v_team
  from public.v1_workforce_crew_profiles profile
  where profile.place_key = v_key;
  if v_team is not null then
    perform public.v1_wf_assert_crew(v_team, 'view');
    return public.v1_wf_crew_json(v_team);
  end if;

  if not public.v1_wf_role_can_keep(v_role)
    or not public.v1_wf_allowed('workforce.attendance.maintain') then
    raise exception 'V1_WORKFORCE_CREW_ACCESS_DENIED' using errcode = '42501';
  end if;
  if p_project_id is not null then
    select * into v_project
    from public.v1_projects project
    where project.id = p_project_id;
    if not found or v_project.state not in ('draft', 'active', 'on_hold') then
      raise exception 'V1_WORKFORCE_CREW_INVALID' using errcode = '22023';
    end if;
    if v_role in ('site_engineer', 'project_engineer') and not exists (
      select 1 from public.v1_project_members member
      where member.project_id = p_project_id
        and member.member_auth_user_id = v_actor
        and member.effective_from <= clock_timestamp()
        and (member.effective_to is null
          or member.effective_to > clock_timestamp())
    ) then
      raise exception 'V1_WORKFORCE_CREW_ACCESS_DENIED' using errcode = '42501';
    end if;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('workforce_place:' || v_key, 0)
  );
  select profile.team_id into v_team
  from public.v1_workforce_crew_profiles profile
  where profile.place_key = v_key;
  if v_team is not null then
    return public.v1_wf_crew_json(v_team);
  end if;

  select profile.* into v_profile
  from public.v1_workforce_crew_profiles profile
  join public.v1_workforce_teams team on team.id = profile.team_id
  where profile.place_key is null
    and profile.is_active
    and team.is_active
    and case
      when p_project_id is not null then
        profile.crew_kind = 'project' and profile.project_id = p_project_id
      else
        profile.crew_kind = 'workshop'
        and lower(regexp_replace(btrim(team.team_name), '\s+', ' ', 'g'))
          = lower(v_label)
    end
  order by profile.created_at, profile.team_id
  limit 1
  for update of profile;

  if found then
    v_team := v_profile.team_id;
    v_adopted := true;
    -- New rows start at 06:30 for 8 hours plus the break: no overtime.
    v_finish := 390 + 480 + coalesce(
      v_profile.break_finish_minute - v_profile.break_start_minute, 0
    );
    if v_profile.break_start_minute is not null
      and (v_profile.break_start_minute < 390
        or v_profile.break_finish_minute > v_finish) then
      v_profile.break_start_minute := null;
      v_profile.break_finish_minute := null;
      v_finish := 870;
    end if;
    update public.v1_workforce_crew_profiles
    set place_key = v_key,
        shift_start_minute = 390,
        shift_finish_minute = v_finish,
        break_start_minute = v_profile.break_start_minute,
        break_finish_minute = v_profile.break_finish_minute,
        record_version = record_version + 1,
        updated_by_auth_user_id = v_actor,
        updated_at = clock_timestamp()
    where team_id = v_team;
  else
    v_name := case when p_project_id is not null
      then left(btrim(v_project.project_ref || ' ' || v_project.name), 160)
      else v_label end;
    if exists (
      select 1 from public.v1_workforce_teams team
      where lower(btrim(team.team_name)) = lower(btrim(v_name))
    ) then
      v_name := left(v_name, 150) || ' · '
        || upper(substr(md5(v_key), 1, 6));
    end if;
    insert into public.v1_workforce_teams (
      team_code, team_name, default_project_id, valid_from,
      created_by_auth_user_id, updated_by_auth_user_id
    ) values (
      'PLACE-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
      v_name, p_project_id, public.v1_wf_today(), v_actor, v_actor
    )
    returning id into v_team;
    insert into public.v1_workforce_crew_profiles (
      team_id, crew_kind, project_id, work_label, needs_confirmation,
      shift_start_minute, shift_finish_minute, break_start_minute,
      break_finish_minute, is_active, created_by_auth_user_id,
      updated_by_auth_user_id, place_key
    ) values (
      v_team,
      case when p_project_id is null then 'workshop' else 'project' end,
      p_project_id, null, p_project_id is not null,
      390, 870, null, null, true, v_actor, v_actor, v_key
    );
  end if;

  perform public.v1_write_audit_event(
    case when v_adopted then 'workforce_place_adopted'
      else 'workforce_place_opened' end,
    'workforce_crew', v_team, p_project_id, null,
    jsonb_build_object('place', v_key), null, null
  );
  return public.v1_wf_crew_json(v_team);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Saving a day.
-- ---------------------------------------------------------------------------

create or replace function public.v1_wf_save_day(
  p_team_id uuid,
  p_work_date date,
  p_rows jsonb,
  p_expected_version bigint,
  p_change_reason text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.v1_wf_assert_crew(p_team_id, 'take');
  v_role text := public.v1_current_exact_role();
  v_existing jsonb;
  v_sheet public.v1_workforce_day_sheets%rowtype;
  v_has_sheet boolean;
  v_day_type text := public.v1_wf_day_type(p_work_date);
  v_today date := public.v1_wf_today();
  v_reason text := nullif(btrim(coalesce(p_change_reason, '')), '');
  v_item jsonb;
  v_worker uuid;
  v_status text;
  v_start integer;
  v_break_start integer;
  v_break_finish integer;
  v_finish integer;
  v_work_project uuid;
  v_label text;
  v_note text;
  v_copied boolean;
  v_minutes integer[];
  v_old public.v1_workforce_day_rows%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_seen uuid[] := array[]::uuid[];
  v_touched uuid[] := array[]::uuid[];
  v_changed_count integer := 0;
  v_project uuid;
  v_counts jsonb;
  v_work_scope uuid;
  v_place text;
  v_found boolean;
  v_by_other boolean;
  v_notify uuid[] := array[]::uuid[];
  v_recipient uuid;
begin
  if p_work_date is null then
    raise exception 'V1_WORKFORCE_DATE_REQUIRED' using errcode = '22023';
  end if;
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_wf_save_day', p_idempotency_key,
    jsonb_build_object(
      'team', p_team_id, 'date', p_work_date, 'rows', p_rows,
      'expected', p_expected_version, 'reason', p_change_reason
    )
  );
  if v_existing is not null then
    return public.v1_wf_get_day(p_team_id, p_work_date);
  end if;

  if p_work_date > v_today then
    raise exception 'V1_WORKFORCE_FUTURE_DATE' using errcode = '22023';
  end if;
  if public.v1_wf_month_locked(p_team_id, p_work_date) then
    raise exception 'V1_WORKFORCE_MONTH_LOCKED' using errcode = '55000';
  end if;
  -- No rows is a day when every member worked at another place (the
  -- member check below still requires everyone else).
  if jsonb_typeof(p_rows) <> 'array'
    or jsonb_array_length(p_rows) > 500 then
    raise exception 'V1_WORKFORCE_DAY_INVALID' using errcode = '22023';
  end if;

  select project_id, place_key into v_project, v_place
  from public.v1_workforce_crew_profiles where team_id = p_team_id;

  -- Serialize the sheet's day, then each worker's day across every place
  -- (in one order, so two places saving the same workers cannot deadlock).
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'workforce_day:' || p_team_id::text || ':' || p_work_date::text, 0
    )
  );
  select * into v_sheet
  from public.v1_workforce_day_sheets sheet
  where sheet.team_id = p_team_id and sheet.work_date = p_work_date
  for update;
  v_has_sheet := found;
  if coalesce(p_expected_version, -1)
    <> (case when v_has_sheet then v_sheet.record_version else 0 end) then
    perform public.v1_raise_version_conflict(
      'V1_WORKFORCE_DAY_VERSION_CONFLICT'
    );
  end if;
  for v_worker in
    select distinct worker_id from (
      select (entry.value ->> 'worker_id')::uuid as worker_id
      from jsonb_array_elements(p_rows) entry
      where (entry.value ->> 'worker_id')
        ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
      union
      select day_row.worker_id
      from public.v1_workforce_day_rows day_row
      where v_has_sheet and day_row.sheet_id = v_sheet.id
    ) workers
    order by worker_id
  loop
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        'workforce_worker_day:' || v_worker::text || ':'
          || p_work_date::text, 0
      )
    );
  end loop;

  -- A reason is needed only to change or remove a row someone else saved
  -- (checked row by row below). Adding a row never needs one.
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'V1_WORKFORCE_DAY_INVALID' using errcode = '22023';
  end if;

  if not v_has_sheet then
    insert into public.v1_workforce_day_sheets (
      team_id, work_date, entered_by_auth_user_id, entered_at, entered_late,
      last_saved_by_auth_user_id, last_saved_at
    ) values (
      p_team_id, p_work_date, v_actor, clock_timestamp(),
      p_work_date < v_today, v_actor, clock_timestamp()
    )
    returning * into v_sheet;
  else
    update public.v1_workforce_day_sheets
    set last_saved_by_auth_user_id = v_actor,
        last_saved_at = clock_timestamp(),
        record_version = record_version + 1
    where id = v_sheet.id
    returning * into v_sheet;
  end if;

  for v_item in select value from jsonb_array_elements(p_rows) loop
    perform public.v1_assert_object_keys(
      v_item,
      array[
        'worker_id', 'status', 'start_minute', 'break_start_minute',
        'break_finish_minute', 'finish_minute', 'work_project_id',
        'work_label', 'overtime_note', 'copied', 'work_scope_id'
      ],
      'save_workforce_day_row'
    );
    begin
      v_worker := (v_item ->> 'worker_id')::uuid;
      v_status := v_item ->> 'status';
      v_start := (v_item ->> 'start_minute')::integer;
      v_break_start := (v_item ->> 'break_start_minute')::integer;
      v_break_finish := (v_item ->> 'break_finish_minute')::integer;
      v_finish := (v_item ->> 'finish_minute')::integer;
      v_work_project := nullif(v_item ->> 'work_project_id', '')::uuid;
      v_work_scope := nullif(v_item ->> 'work_scope_id', '')::uuid;
      v_copied := coalesce((v_item ->> 'copied')::boolean, false);
    exception when others then
      raise exception 'V1_WORKFORCE_DAY_INVALID' using errcode = '22023';
    end;
    v_label := nullif(btrim(coalesce(v_item ->> 'work_label', '')), '');
    v_note := nullif(btrim(coalesce(v_item ->> 'overtime_note', '')), '');
    if v_worker is null or v_worker = any(v_seen) then
      raise exception 'V1_WORKFORCE_DAY_INVALID' using errcode = '22023';
    end if;
    v_seen := v_seen || v_worker;
    if v_status is null then
      raise exception 'V1_WORKFORCE_DAY_UNMARKED' using errcode = '22023';
    end if;
    if v_status not in ('P', 'A', 'OFF', 'AL', 'SL', 'OL', 'UL') then
      raise exception 'V1_WORKFORCE_DAY_INVALID' using errcode = '22023';
    end if;
    if v_status = 'OFF' and v_day_type = 'work' then
      raise exception 'V1_WORKFORCE_REST_DAY_NOT_ALLOWED' using errcode = '22023';
    end if;
    if v_status = 'P' then
      if v_start is null or v_finish is null or v_finish <= v_start
        or (v_break_start is null) <> (v_break_finish is null)
        or (v_break_start is not null and v_break_finish <= v_break_start)
      then
        raise exception 'V1_WORKFORCE_TIME_MISSING' using errcode = '22023';
      end if;
    else
      v_start := null; v_break_start := null;
      v_break_finish := null; v_finish := null;
    end if;
    -- Every row on a project's place is on that project.
    if v_place like 'project:%' then
      v_work_project := v_project;
    end if;
    if v_work_project is not null and not exists (
      select 1 from public.v1_projects project where project.id = v_work_project
    ) then
      raise exception 'V1_WORKFORCE_DAY_INVALID' using errcode = '22023';
    end if;
    -- The building (or Common) belongs to the row's project.
    if v_work_scope is not null and (
      v_work_project is null
      or not exists (
        select 1 from public.v1_project_scopes scope
        where scope.id = v_work_scope and scope.project_id = v_work_project
      )
    ) then
      raise exception 'V1_WORKFORCE_DAY_INVALID' using errcode = '22023';
    end if;
    if not exists (
      select 1 from public.v1_workforce_workers worker where worker.id = v_worker
    ) then
      raise exception 'V1_WORKFORCE_DAY_INVALID' using errcode = '22023';
    end if;
    -- Only labour goes on attendance sheets. A staff row saved on this day
    -- before the rule may be kept as it was; no new one is accepted.
    if not public.v1_wf_is_labour(v_worker) and not exists (
      select 1 from public.v1_workforce_day_rows saved_row
      where saved_row.sheet_id = v_sheet.id
        and saved_row.worker_id = v_worker
    ) then
      raise exception 'V1_WORKFORCE_STAFF_NOT_ON_SHEETS' using errcode = '22023';
    end if;

    -- The same worker at other places that day.
    if v_status = 'P' then
      if exists (
        select 1 from public.v1_workforce_day_rows other_row
        where other_row.worker_id = v_worker
          and other_row.work_date = p_work_date
          and other_row.sheet_id <> v_sheet.id
          and other_row.attendance_status in ('AL', 'SL', 'OL', 'UL')
      ) then
        raise exception 'V1_WORKFORCE_WORKER_ON_LEAVE_ELSEWHERE'
          using errcode = '22023';
      end if;
      if exists (
        select 1 from public.v1_workforce_day_rows other_row
        where other_row.worker_id = v_worker
          and other_row.work_date = p_work_date
          and other_row.sheet_id <> v_sheet.id
          and other_row.attendance_status = 'P'
          and other_row.start_minute < v_finish
          and v_start < other_row.finish_minute
      ) then
        raise exception 'V1_WORKFORCE_TIME_OVERLAP' using errcode = '22023';
      end if;
      if (
        select count(*) from public.v1_workforce_day_rows other_row
        where other_row.worker_id = v_worker
          and other_row.work_date = p_work_date
          and other_row.sheet_id <> v_sheet.id
          and other_row.attendance_status = 'P'
      ) >= 3 then
        raise exception 'V1_WORKFORCE_TOO_MANY_PLACES' using errcode = '22023';
      end if;
    elsif v_status in ('AL', 'SL', 'OL', 'UL') and exists (
      select 1 from public.v1_workforce_day_rows other_row
      where other_row.worker_id = v_worker
        and other_row.work_date = p_work_date
        and other_row.sheet_id <> v_sheet.id
        and other_row.attendance_status = 'P'
    ) then
      raise exception 'V1_WORKFORCE_WORKER_PRESENT_ELSEWHERE'
        using errcode = '22023';
    end if;

    v_minutes := public.v1_wf_compute_minutes(
      v_status, v_start, v_break_start, v_break_finish, v_finish, v_day_type
    );

    select * into v_old
    from public.v1_workforce_day_rows day_row
    where day_row.sheet_id = v_sheet.id and day_row.worker_id = v_worker;
    v_found := found;
    v_before := case when v_found then jsonb_build_object(
      'status', v_old.attendance_status,
      'start_minute', v_old.start_minute,
      'break_start_minute', v_old.break_start_minute,
      'break_finish_minute', v_old.break_finish_minute,
      'finish_minute', v_old.finish_minute,
      'work_project_id', v_old.work_project_id,
      'work_label', v_old.work_label,
      'work_scope_id', v_old.work_scope_id
    ) end;
    v_after := jsonb_build_object(
      'status', v_status,
      'start_minute', v_start,
      'break_start_minute', v_break_start,
      'break_finish_minute', v_break_finish,
      'finish_minute', v_finish,
      'work_project_id', v_work_project,
      'work_label', v_label,
      'work_scope_id', v_work_scope
    );
    -- A row saved again unchanged keeps who saved it.
    if v_found
      and v_before is not distinct from v_after
      and v_old.overtime_note is not distinct from v_note then
      continue;
    end if;
    -- Changing a row someone else saved needs a reason, is logged and tells
    -- them.
    v_by_other := v_found
      and v_old.updated_by_auth_user_id <> v_actor
      and v_before is distinct from v_after;
    if v_by_other and v_reason is null then
      raise exception 'V1_WORKFORCE_CHANGE_REASON_REQUIRED'
        using errcode = '22023';
    end if;

    insert into public.v1_workforce_day_rows (
      sheet_id, team_id, work_date, worker_id, attendance_status,
      start_minute, break_start_minute, break_finish_minute, finish_minute,
      work_project_id, work_scope_id, work_label, overtime_note, copied,
      worked_minutes, regular_minutes, normal_overtime_minutes,
      holiday_overtime_minutes, updated_by_auth_user_id
    ) values (
      v_sheet.id, p_team_id, p_work_date, v_worker, v_status,
      v_start, v_break_start, v_break_finish, v_finish,
      v_work_project, v_work_scope, v_label, v_note, v_copied,
      v_minutes[1], v_minutes[2], v_minutes[3], v_minutes[4], v_actor
    )
    on conflict (sheet_id, worker_id) do update
    set attendance_status = excluded.attendance_status,
        start_minute = excluded.start_minute,
        break_start_minute = excluded.break_start_minute,
        break_finish_minute = excluded.break_finish_minute,
        finish_minute = excluded.finish_minute,
        work_project_id = excluded.work_project_id,
        work_scope_id = excluded.work_scope_id,
        work_label = excluded.work_label,
        overtime_note = excluded.overtime_note,
        copied = excluded.copied,
        changed_after_entry = public.v1_workforce_day_rows.changed_after_entry
          or v_by_other,
        worked_minutes = excluded.worked_minutes,
        regular_minutes = excluded.regular_minutes,
        normal_overtime_minutes = excluded.normal_overtime_minutes,
        holiday_overtime_minutes = excluded.holiday_overtime_minutes,
        updated_by_auth_user_id = v_actor,
        updated_at = clock_timestamp();

    if v_by_other then
      v_notify := v_notify || v_old.updated_by_auth_user_id;
      insert into public.v1_workforce_day_changes (
        sheet_id, worker_id, before_data, after_data, reason,
        actor_auth_user_id, actor_exact_role
      ) values (
        v_sheet.id, v_worker, v_before, v_after, v_reason, v_actor, v_role
      );
      v_changed_count := v_changed_count + 1;
    end if;
  end loop;

  -- Every current member must be on the day, unless they are recorded
  -- present, resting or on leave at another place that day.
  if v_place is null and exists (
    select 1
    from public.v1_workforce_crew_members member
    join public.v1_workforce_workers worker on worker.id = member.worker_id
    where member.team_id = p_team_id
      and member.removed_at is null
      and worker.current_status = 'active'
      and not (member.worker_id = any(v_seen))
      and not exists (
        select 1 from public.v1_workforce_day_rows other_row
        where other_row.worker_id = member.worker_id
          and other_row.work_date = p_work_date
          and other_row.sheet_id <> v_sheet.id
          and other_row.attendance_status in (
            'P', 'OFF', 'AL', 'SL', 'OL', 'UL'
          )
      )
  ) then
    raise exception 'V1_WORKFORCE_DAY_UNMARKED' using errcode = '22023';
  end if;

  -- Rows left out of this save are removed and, when the day belonged to
  -- someone else, logged.
  for v_old in
    select * from public.v1_workforce_day_rows day_row
    where day_row.sheet_id = v_sheet.id
      and not (day_row.worker_id = any(v_seen))
  loop
    if v_old.updated_by_auth_user_id <> v_actor then
      if v_reason is null then
        raise exception 'V1_WORKFORCE_CHANGE_REASON_REQUIRED'
          using errcode = '22023';
      end if;
      v_notify := v_notify || v_old.updated_by_auth_user_id;
      insert into public.v1_workforce_day_changes (
        sheet_id, worker_id, before_data, after_data, reason,
        actor_auth_user_id, actor_exact_role
      ) values (
        v_sheet.id, v_old.worker_id,
        jsonb_build_object('status', v_old.attendance_status),
        null, v_reason, v_actor, v_role
      );
      v_changed_count := v_changed_count + 1;
    end if;
    v_touched := v_touched || v_old.worker_id;
    delete from public.v1_workforce_day_rows where id = v_old.id;
  end loop;

  -- Normal hours and overtime over each worker's whole day.
  for v_worker in
    select distinct worker_id
    from unnest(v_seen || v_touched) as touched(worker_id)
    order by worker_id
  loop
    perform public.v1_wf_recompute_worker_day(v_worker, p_work_date);
  end loop;

  select jsonb_build_object(
    'present', count(*) filter (where attendance_status = 'P'),
    'absent', count(*) filter (where attendance_status = 'A'),
    'leave', count(*) filter (
      where attendance_status in ('AL', 'SL', 'OL', 'UL')
    ),
    'normal_overtime_minutes', coalesce(sum(normal_overtime_minutes), 0),
    'holiday_overtime_minutes', coalesce(sum(holiday_overtime_minutes), 0)
  )
  into v_counts
  from public.v1_workforce_day_rows
  where sheet_id = v_sheet.id;

  if not v_has_sheet then
    insert into public.v1_workforce_attendance_events (
      team_id, work_date, event_kind, summary, actor_auth_user_id,
      actor_exact_role
    ) values (
      p_team_id, p_work_date, 'entered', v_counts, v_actor, v_role
    );
  elsif v_changed_count > 0 then
    insert into public.v1_workforce_attendance_events (
      team_id, work_date, event_kind, summary, actor_auth_user_id,
      actor_exact_role
    ) values (
      p_team_id, p_work_date, 'changed',
      v_counts || jsonb_build_object(
        'changed_rows', v_changed_count, 'reason', v_reason
      ),
      v_actor, v_role
    );
    -- Everyone whose rows were changed or removed is told once.
    for v_recipient in
      select distinct recipient from unnest(v_notify) as changed(recipient)
      where recipient <> v_actor
    loop
      perform public.v1_wf_notify(
        v_recipient, 'workforce_attendance_day_changed',
        'workforce_day_sheet', v_sheet.id, v_project
      );
    end loop;
  end if;

  perform public.v1_write_audit_event(
    case when v_has_sheet then 'workforce_day_updated'
      else 'workforce_day_entered' end,
    'workforce_day_sheet', v_sheet.id, v_project, null,
    v_counts || jsonb_build_object(
      'work_date', p_work_date, 'changed_rows', v_changed_count
    ),
    v_reason, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_wf_save_day', p_idempotency_key,
    jsonb_build_object('sheet_id', v_sheet.id)
  );
  return public.v1_wf_get_day(p_team_id, p_work_date);
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Months: a place's days without a sheet are not missing.
-- ---------------------------------------------------------------------------

create or replace function public.v1_wf_month_json(
  p_team_id uuid,
  p_month date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_month date := date_trunc('month', p_month)::date;
  v_last date := (date_trunc('month', p_month) + interval '1 month - 1 day')::date;
  v_today date := public.v1_wf_today();
  v_confirmation public.v1_workforce_month_confirmations%rowtype;
  v_profile public.v1_workforce_crew_profiles%rowtype;
  v_days jsonb;
  v_missing jsonb;
  v_totals record;
  v_work_days integer;
  v_entered integer;
begin
  select * into v_profile
  from public.v1_workforce_crew_profiles profile
  where profile.team_id = p_team_id;
  select * into v_confirmation
  from public.v1_workforce_month_confirmations confirmation
  where confirmation.team_id = p_team_id
    and confirmation.period_month = v_month;

  select
    jsonb_agg(jsonb_build_object(
      'date', day_value,
      'state', public.v1_wf_day_state(p_team_id, day_value),
      'day_type', public.v1_wf_day_type(day_value)
    ) order by day_value)
  into v_days
  from generate_series(v_month, v_last, interval '1 day') series(day_ts)
  cross join lateral (select series.day_ts::date as day_value) day_row;

  select coalesce(jsonb_agg(day_value order by day_value), '[]'::jsonb)
  into v_missing
  from generate_series(v_month, least(v_last, v_today), interval '1 day')
    series(day_ts)
  cross join lateral (select series.day_ts::date as day_value) day_row
  where v_profile.place_key is null
    and public.v1_wf_day_type(day_value) = 'work'
    and not exists (
      select 1 from public.v1_workforce_day_sheets sheet
      where sheet.team_id = p_team_id and sheet.work_date = day_value
    );

  select count(*) into v_work_days
  from generate_series(v_month, least(v_last, v_today), interval '1 day')
    series(day_ts)
  where public.v1_wf_day_type(series.day_ts::date) = 'work';

  select count(*) into v_entered
  from public.v1_workforce_day_sheets sheet
  where sheet.team_id = p_team_id
    and sheet.work_date between v_month and v_last;

  select
    coalesce(sum(day_row.regular_minutes), 0) as regular,
    coalesce(sum(day_row.normal_overtime_minutes), 0) as normal_ot,
    coalesce(sum(day_row.holiday_overtime_minutes), 0) as holiday_ot
  into v_totals
  from public.v1_workforce_day_rows day_row
  where day_row.team_id = p_team_id
    and day_row.work_date between v_month and v_last;

  return jsonb_build_object(
    'month', v_month,
    'last_day', v_last,
    'state', case
      when not coalesce(v_profile.needs_confirmation, true)
        then 'not_needed'
      when coalesce(v_confirmation.is_confirmed, false) then 'confirmed'
      when v_today >= v_last then 'ready'
      else 'recording'
    end,
    'confirmed_by', public.v1_wf_display_name(
      v_confirmation.confirmed_by_auth_user_id
    ),
    'confirmed_at', v_confirmation.confirmed_at,
    'reopened_by', public.v1_wf_display_name(
      v_confirmation.reopened_by_auth_user_id
    ),
    'reopened_at', v_confirmation.reopened_at,
    'reopen_reason', v_confirmation.reopen_reason,
    'record_version', coalesce(v_confirmation.record_version, 0),
    'days', coalesce(v_days, '[]'::jsonb),
    'missing_days', v_missing,
    'work_days_so_far', v_work_days,
    'days_entered', v_entered,
    'regular_minutes', v_totals.regular,
    'normal_overtime_minutes', v_totals.normal_ot,
    'holiday_overtime_minutes', v_totals.holiday_ot,
    'can_confirm', coalesce(
      (public.v1_wf_crew_access(p_team_id) ->> 'confirm')::boolean, false
    )
      and not coalesce(v_confirmation.is_confirmed, false)
      and v_today >= v_last
      and jsonb_array_length(v_missing) = 0
  );
end;
$$;

create or replace function public.v1_wf_confirm_month(
  p_team_id uuid,
  p_month date,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.v1_wf_assert_crew(p_team_id, 'confirm');
  v_month date := date_trunc('month', p_month)::date;
  v_last date := (date_trunc('month', p_month) + interval '1 month - 1 day')::date;
  v_existing jsonb;
  v_row public.v1_workforce_month_confirmations%rowtype;
  v_missing integer;
  v_project uuid;
begin
  if p_month is null then
    raise exception 'V1_WORKFORCE_DATE_REQUIRED' using errcode = '22023';
  end if;
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_wf_confirm_month', p_idempotency_key,
    jsonb_build_object('team', p_team_id, 'month', v_month)
  );
  if v_existing is not null then
    return public.v1_wf_month_json(p_team_id, v_month);
  end if;
  if public.v1_wf_today() < v_last then
    raise exception 'V1_WORKFORCE_MONTH_NOT_ENDED' using errcode = '55000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'workforce_month:' || p_team_id::text || ':' || v_month::text, 0
    )
  );
  -- A place has no members: a day nobody was recorded there is not missing.
  select count(*) into v_missing
  from generate_series(v_month, v_last, interval '1 day') series(day_ts)
  where public.v1_wf_day_type(series.day_ts::date) = 'work'
    and exists (
      select 1 from public.v1_workforce_crew_profiles profile
      where profile.team_id = p_team_id and profile.place_key is null
    )
    and not exists (
      select 1 from public.v1_workforce_day_sheets sheet
      where sheet.team_id = p_team_id
        and sheet.work_date = series.day_ts::date
    );
  if v_missing > 0 then
    raise exception 'V1_WORKFORCE_MONTH_INCOMPLETE' using errcode = '55000';
  end if;
  select * into v_row
  from public.v1_workforce_month_confirmations confirmation
  where confirmation.team_id = p_team_id
    and confirmation.period_month = v_month
  for update;
  if found and v_row.is_confirmed then
    raise exception 'V1_WORKFORCE_MONTH_LOCKED' using errcode = '55000';
  end if;
  insert into public.v1_workforce_month_confirmations (
    team_id, period_month, is_confirmed, confirmed_by_auth_user_id,
    confirmed_at
  ) values (p_team_id, v_month, true, v_actor, clock_timestamp())
  on conflict (team_id, period_month) do update
  set is_confirmed = true,
      confirmed_by_auth_user_id = v_actor,
      confirmed_at = clock_timestamp(),
      record_version = public.v1_workforce_month_confirmations.record_version + 1;

  select project_id into v_project
  from public.v1_workforce_crew_profiles where team_id = p_team_id;
  insert into public.v1_workforce_attendance_events (
    team_id, period_month, event_kind, summary, actor_auth_user_id,
    actor_exact_role
  ) values (
    p_team_id, v_month, 'confirmed', '{}'::jsonb, v_actor,
    public.v1_current_exact_role()
  );
  perform public.v1_write_audit_event(
    'workforce_month_confirmed', 'workforce_crew', p_team_id, v_project,
    null, jsonb_build_object('month', v_month), null, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_wf_confirm_month', p_idempotency_key,
    jsonb_build_object('team', p_team_id, 'month', v_month)
  );
  return public.v1_wf_month_json(p_team_id, v_month);
end;
$$;

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
    -- A place is due only in a month it has days.
    and (
      profile.place_key is null
      or exists (
        select 1 from public.v1_workforce_day_sheets sheet
        where sheet.team_id = profile.team_id
          and sheet.work_date between due.month_start
            and (due.month_start + interval '1 month - 1 day')::date
      )
    )
    and (profile.created_at at time zone 'Asia/Dubai')::date
      <= (due.month_start + interval '1 month - 1 day')::date
    and not exists (
      select 1 from public.v1_workforce_month_confirmations confirmation
      where confirmation.team_id = profile.team_id
        and confirmation.period_month = due.month_start
        and confirmation.is_confirmed
    );
$$;

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
            and exists (
              select 1 from public.v1_workforce_crew_profiles profile
              where profile.team_id = due.team_id
                and profile.place_key is null
            )
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

-- ---------------------------------------------------------------------------
-- 6. Grants.
-- ---------------------------------------------------------------------------

do $grants$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'v1_wf_project_buildings(uuid)',
    'v1_wf_crew_access(uuid)',
    'v1_wf_crew_json(uuid)',
    'v1_wf_row_json(public.v1_workforce_day_rows)',
    'v1_wf_month_json(uuid,date)',
    'v1_wf_due_crew_months(date)'
  ] loop
    execute format(
      'revoke all on function public.%s from public, anon, authenticated',
      v_signature
    );
  end loop;
  foreach v_signature in array array[
    'v1_wf_list_places()',
    'v1_wf_open_place(uuid,text)',
    'v1_wf_get_day(uuid,date)',
    'v1_wf_save_day(uuid,date,jsonb,bigint,text,uuid)',
    'v1_wf_confirm_month(uuid,date,uuid)',
    'v1_wf_get_confirmations_due()'
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
