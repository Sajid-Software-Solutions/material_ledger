-- Workforce attendance V2: a labourer at several places in a day, sheets
-- kept by the people at each place, and new month confirmers
-- (owner decisions, 14 November 2026; PRODUCT_DECISIONS section 46).
--
--   * A crew is an attendance sheet for one place (a project, or an internal
--     location such as the workshop or store). A labourer may be on several
--     sheets and may work at up to three places on the same day; each place
--     records its own hours. Adding a worker to a sheet never takes them off
--     another sheet, so there is nothing to confirm.
--   * Times at two places on the same day may not overlap; a worker on leave
--     at one place cannot be present at another.
--   * Normal hours and overtime are counted over the whole day: in time
--     order, the first 8 hours of the worker's day are normal hours and every
--     later hour is overtime, on the sheet where it was worked. Every hour on
--     a Sunday or public holiday is holiday overtime, as before.
--   * Site and Project Engineers, Senior Mechanical Engineers, Project
--     Managers, Workshop In-Charges, Admin and PR create and keep sheets
--     without anyone setting them up. A Site or Project Engineer keeps sheets
--     for projects they are on, or for an internal location. Document
--     Controllers and the Accountant read.
--   * A month is confirmed by a Senior Mechanical Engineer, or by a Project
--     Engineer of the sheet's project (an internal location: a Senior
--     Mechanical Engineer), with Admin as an audited override. Project
--     Managers, Workshop In-Charges and Document Controllers no longer
--     confirm.
--   * Only labour goes on attendance sheets: staff (People category "staff")
--     are not offered and are refused.
--   * A member recorded at another place that day (present, resting or on
--     leave) need not be marked on this sheet; a day may be saved with no
--     rows when every member was elsewhere, so the month can be complete.
--
-- Data preservation: no row is changed or removed. A staff row already
-- saved on a day stays on it and may be saved again unchanged. The one-crew-per-worker
-- and one-sheet-per-worker-per-day uniqueness rules are replaced by
-- per-sheet rules. Production holds no crews or attendance yet.
-- Rollback: restore the functions from 20261112140000, 20261113090000,
-- 20261114090000 and 20261114100000, then recreate
-- v1_workforce_crew_members_current_uidx and the (worker_id, work_date)
-- unique constraint (only possible while no worker is on two sheets).

begin;

-- ---------------------------------------------------------------------------
-- 1. A worker on several sheets; a worker on several sheets a day.
-- ---------------------------------------------------------------------------

drop index if exists public.v1_workforce_crew_members_current_uidx;
create unique index if not exists v1_workforce_crew_members_team_worker_uidx
  on public.v1_workforce_crew_members (team_id, worker_id)
  where removed_at is null;
create index if not exists v1_workforce_crew_members_worker_idx
  on public.v1_workforce_crew_members (worker_id)
  where removed_at is null;

alter table public.v1_workforce_day_rows
  drop constraint if exists v1_workforce_day_rows_worker_id_work_date_key;
create index if not exists v1_workforce_day_rows_worker_date_idx
  on public.v1_workforce_day_rows (worker_id, work_date);

-- ---------------------------------------------------------------------------
-- 2. Helpers.
-- ---------------------------------------------------------------------------

-- Labour, not staff. A worker without a People record counts as labour.
create or replace function public.v1_wf_is_labour(p_worker_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not exists (
    select 1 from public.v1_people_profiles profile
    where profile.worker_id = p_worker_id and profile.category = 'staff'
  );
$$;

-- Roles that create and keep their own attendance sheets.
create or replace function public.v1_wf_role_can_keep(p_role text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_role in (
    'site_engineer', 'project_engineer', 'senior_mechanical_engineer',
    'project_manager', 'workshop_in_charge', 'admin', 'pr'
  );
$$;

-- The worker's rows on other sheets that day: place, status and times.
create or replace function public.v1_wf_elsewhere_json(
  p_worker_id uuid,
  p_work_date date,
  p_team_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'crew_id', day_row.team_id,
    'crew_name', team.team_name,
    'status', day_row.attendance_status,
    'start_minute', day_row.start_minute,
    'break_start_minute', day_row.break_start_minute,
    'break_finish_minute', day_row.break_finish_minute,
    'finish_minute', day_row.finish_minute,
    'worked_minutes', day_row.worked_minutes,
    'locked', public.v1_wf_month_locked(day_row.team_id, p_work_date)
  ) order by day_row.start_minute nulls last, lower(team.team_name)),
  '[]'::jsonb)
  from public.v1_workforce_day_rows day_row
  join public.v1_workforce_teams team on team.id = day_row.team_id
  where day_row.worker_id = p_worker_id
    and day_row.work_date = p_work_date
    and day_row.team_id <> p_team_id;
$$;

-- Normal hours and overtime over the worker's whole day, in time order:
-- the first 8 hours are normal, every later hour is normal overtime; every
-- hour on a Sunday or public holiday is holiday overtime. A row on a
-- confirmed month never changes: if it would, the save is refused.
create or replace function public.v1_wf_recompute_worker_day(
  p_worker_id uuid,
  p_work_date date
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_holiday boolean := public.v1_wf_day_type(p_work_date) = 'holiday';
  v_used integer := 0;
  v_row record;
  v_regular integer;
  v_normal_ot integer;
  v_holiday_ot integer;
begin
  for v_row in
    select day_row.id, day_row.team_id, day_row.worked_minutes,
      day_row.regular_minutes, day_row.normal_overtime_minutes,
      day_row.holiday_overtime_minutes
    from public.v1_workforce_day_rows day_row
    where day_row.worker_id = p_worker_id
      and day_row.work_date = p_work_date
      and day_row.attendance_status = 'P'
    order by day_row.start_minute, day_row.finish_minute, day_row.id
  loop
    if v_holiday then
      v_regular := 0;
      v_normal_ot := 0;
      v_holiday_ot := v_row.worked_minutes;
    else
      v_regular := least(v_row.worked_minutes, greatest(480 - v_used, 0));
      v_normal_ot := v_row.worked_minutes - v_regular;
      v_holiday_ot := 0;
      v_used := v_used + v_row.worked_minutes;
    end if;
    if (v_row.regular_minutes, v_row.normal_overtime_minutes,
        v_row.holiday_overtime_minutes)
      is distinct from (v_regular, v_normal_ot, v_holiday_ot) then
      if public.v1_wf_month_locked(v_row.team_id, p_work_date) then
        raise exception 'V1_WORKFORCE_OTHER_PLACE_LOCKED'
          using errcode = '55000';
      end if;
      update public.v1_workforce_day_rows
      set regular_minutes = v_regular,
          normal_overtime_minutes = v_normal_ot,
          holiday_overtime_minutes = v_holiday_ot
      where id = v_row.id;
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Access.
-- ---------------------------------------------------------------------------

-- {view, take, confirm, manage, officer, keeper} for the signed-in person on
-- one sheet. Capabilities are checked on top of role, keeper and project
-- membership.
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
    )
    and public.v1_wf_allowed('workforce.view');
  v_take := v_view
    and (
      v_officer or v_global_keep or v_keeper
      or (v_role in ('project_engineer', 'site_engineer') and v_member)
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

-- ---------------------------------------------------------------------------
-- 4. Projections and lists.
-- ---------------------------------------------------------------------------

-- A worker with every sheet they are on. crew_id / crew_name name the first
-- sheet (by name), for screens that show one.
create or replace function public.v1_wf_worker_json(p_worker_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', worker.id,
    'number', worker.worker_number,
    'name', worker.full_name,
    'designation', worker.designation,
    'company', worker.employer_company,
    'status', worker.current_status,
    'category', case
      when public.v1_wf_is_labour(worker.id) then 'labour' else 'staff' end,
    'crew_id', crews.list -> 0 ->> 'id',
    'crew_name', crews.list -> 0 ->> 'name',
    'crews', crews.list
  )
  from public.v1_workforce_workers worker
  cross join lateral (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', team.id, 'name', team.team_name
    ) order by lower(team.team_name), team.id), '[]'::jsonb) as list
    from public.v1_workforce_crew_members member
    join public.v1_workforce_teams team on team.id = member.team_id
    where member.worker_id = worker.id and member.removed_at is null
  ) crews
  where worker.id = p_worker_id;
$$;

create or replace function public.v1_wf_list_crews()
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
    'schema_version', 'yorks.workforce.crews.v2',
    'today', public.v1_wf_today(),
    'can_create_crew',
      public.v1_wf_role_can_keep(public.v1_current_exact_role())
      and public.v1_wf_allowed('workforce.teams.manage'),
    'crews', coalesce((
      select jsonb_agg(public.v1_wf_crew_json(team.id)
        order by lower(team.team_name))
      from public.v1_workforce_teams team
      join public.v1_workforce_crew_profiles profile
        on profile.team_id = team.id
      where profile.is_active
        and (public.v1_wf_crew_access(team.id) ->> 'view')::boolean
    ), '[]'::jsonb)
  );
end;
$$;

-- Active labourers a keeper may add to a sheet or a day. Staff are not
-- offered.
create or replace function public.v1_wf_list_workers()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null
    or not public.v1_current_actor_is_active()
    or not public.v1_wf_role_can_keep(public.v1_current_exact_role())
    or not public.v1_wf_allowed('workforce.attendance.maintain') then
    raise exception 'V1_WORKFORCE_CREW_ACCESS_DENIED' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'schema_version', 'yorks.workforce.workers.v2',
    'workers', coalesce((
      select jsonb_agg(public.v1_wf_worker_json(worker.id)
        order by lower(worker.full_name))
      from public.v1_workforce_workers worker
      where worker.current_status = 'active'
        and public.v1_wf_is_labour(worker.id)
    ), '[]'::jsonb)
  );
end;
$$;

-- The day for one sheet. Every current member is offered, with where else
-- they are recorded that day.
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
-- 5. Sheet setup.
-- ---------------------------------------------------------------------------

create or replace function public.v1_wf_save_crew(
  p_payload jsonb,
  p_expected_version bigint,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_role text := public.v1_current_exact_role();
  v_existing jsonb;
  v_team_id uuid;
  v_profile public.v1_workforce_crew_profiles%rowtype;
  v_name text := btrim(coalesce(p_payload ->> 'name', ''));
  v_kind text := coalesce(p_payload ->> 'kind', 'project');
  v_project uuid;
  v_label text := nullif(btrim(coalesce(p_payload ->> 'work_label', '')), '');
  v_needs boolean;
  v_start integer;
  v_finish integer;
  v_break_start integer;
  v_break_finish integer;
  v_active boolean := coalesce((p_payload ->> 'is_active')::boolean, true);
  v_member boolean := false;
begin
  if v_actor is null or not public.v1_current_actor_is_active() then
    raise exception 'V1_ACTIVE_ACTOR_REQUIRED' using errcode = '42501';
  end if;
  perform public.v1_assert_object_keys(
    p_payload,
    array[
      'crew_id', 'name', 'kind', 'project_id', 'work_label',
      'needs_confirmation', 'shift_start_minute', 'shift_finish_minute',
      'break_start_minute', 'break_finish_minute', 'is_active'
    ],
    'save_workforce_crew_payload'
  );
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_wf_save_crew', p_idempotency_key,
    jsonb_build_object('payload', p_payload, 'expected', p_expected_version)
  );
  if v_existing is not null then
    return public.v1_wf_crew_json((v_existing ->> 'crew_id')::uuid);
  end if;

  begin
    v_team_id := nullif(p_payload ->> 'crew_id', '')::uuid;
    v_project := nullif(p_payload ->> 'project_id', '')::uuid;
    v_start := (p_payload ->> 'shift_start_minute')::integer;
    v_finish := (p_payload ->> 'shift_finish_minute')::integer;
    v_break_start := (p_payload ->> 'break_start_minute')::integer;
    v_break_finish := (p_payload ->> 'break_finish_minute')::integer;
  exception when others then
    raise exception 'V1_WORKFORCE_CREW_INVALID' using errcode = '22023';
  end;
  if v_name = '' or char_length(v_name) > 160
    or v_kind not in ('project', 'workshop')
    or (v_kind = 'project') <> (v_project is not null)
    or v_start is null or v_finish is null or v_finish <= v_start
    or (v_break_start is null) <> (v_break_finish is null)
    or (v_break_start is not null and v_break_finish <= v_break_start) then
    raise exception 'V1_WORKFORCE_CREW_INVALID' using errcode = '22023';
  end if;
  v_needs := coalesce(
    (p_payload ->> 'needs_confirmation')::boolean, v_kind = 'project'
  );

  if v_project is not null then
    if not exists (
      select 1 from public.v1_projects project where project.id = v_project
    ) then
      raise exception 'V1_WORKFORCE_CREW_INVALID' using errcode = '22023';
    end if;
    select exists (
      select 1 from public.v1_project_members member
      where member.project_id = v_project
        and member.member_auth_user_id = v_actor
        and member.effective_from <= clock_timestamp()
        and (member.effective_to is null
          or member.effective_to > clock_timestamp())
    ) into v_member;
  end if;

  if v_team_id is null then
    -- Anyone who keeps sheets creates one; a Site or Project Engineer only
    -- for a project they are on (or an internal location).
    if not public.v1_wf_allowed('workforce.teams.manage')
      or not public.v1_wf_role_can_keep(v_role)
      or (
        v_project is not null
        and v_role in ('site_engineer', 'project_engineer')
        and not v_member
      ) then
      raise exception 'V1_WORKFORCE_CREW_ACCESS_DENIED' using errcode = '42501';
    end if;
    insert into public.v1_workforce_teams (
      team_code, team_name, default_project_id, valid_from,
      created_by_auth_user_id, updated_by_auth_user_id
    ) values (
      'CREW-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
      v_name, v_project, public.v1_wf_today(), v_actor, v_actor
    )
    returning id into v_team_id;
    insert into public.v1_workforce_crew_profiles (
      team_id, crew_kind, project_id, work_label, needs_confirmation,
      shift_start_minute, shift_finish_minute, break_start_minute,
      break_finish_minute, is_active, created_by_auth_user_id,
      updated_by_auth_user_id
    ) values (
      v_team_id, v_kind, v_project, v_label, v_needs, v_start, v_finish,
      v_break_start, v_break_finish, v_active, v_actor, v_actor
    );
  else
    perform public.v1_wf_assert_crew(v_team_id, 'manage');
    -- Moving a sheet to another project needs the same rule as creating it.
    if v_project is not null
      and v_role in ('site_engineer', 'project_engineer')
      and not v_member then
      raise exception 'V1_WORKFORCE_CREW_ACCESS_DENIED' using errcode = '42501';
    end if;
    select * into v_profile
    from public.v1_workforce_crew_profiles profile
    where profile.team_id = v_team_id
    for update;
    if coalesce(p_expected_version, -1) <> v_profile.record_version then
      perform public.v1_raise_version_conflict(
        'V1_WORKFORCE_CREW_VERSION_CONFLICT'
      );
    end if;
    update public.v1_workforce_teams
    set team_name = v_name,
        default_project_id = v_project,
        record_version = record_version + 1,
        updated_by_auth_user_id = v_actor,
        updated_at = clock_timestamp()
    where id = v_team_id;
    update public.v1_workforce_crew_profiles
    set crew_kind = v_kind,
        project_id = v_project,
        work_label = v_label,
        needs_confirmation = v_needs,
        shift_start_minute = v_start,
        shift_finish_minute = v_finish,
        break_start_minute = v_break_start,
        break_finish_minute = v_break_finish,
        is_active = v_active,
        record_version = record_version + 1,
        updated_by_auth_user_id = v_actor,
        updated_at = clock_timestamp()
    where team_id = v_team_id;
  end if;

  perform public.v1_write_audit_event(
    'workforce_crew_saved', 'workforce_crew', v_team_id, v_project, null,
    jsonb_build_object('name', v_name, 'kind', v_kind), null,
    p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_wf_save_crew', p_idempotency_key,
    jsonb_build_object('crew_id', v_team_id)
  );
  return public.v1_wf_crew_json(v_team_id);
exception
  when unique_violation then
    raise exception 'V1_WORKFORCE_CREW_NAME_TAKEN' using errcode = '23505';
end;
$$;

-- Add or remove labourers on a sheet. A labourer added here stays on every
-- other sheet they are on.
create or replace function public.v1_wf_set_crew_members(
  p_team_id uuid,
  p_add_worker_ids uuid[],
  p_remove_worker_ids uuid[],
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.v1_wf_assert_crew(p_team_id, 'take');
  v_existing jsonb;
  v_worker uuid;
begin
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_wf_set_crew_members', p_idempotency_key,
    jsonb_build_object(
      'team', p_team_id, 'add', p_add_worker_ids,
      'remove', p_remove_worker_ids
    )
  );
  if v_existing is not null then
    return public.v1_wf_crew_json(p_team_id);
  end if;
  if coalesce(cardinality(p_add_worker_ids), 0)
    + coalesce(cardinality(p_remove_worker_ids), 0) > 500 then
    raise exception 'V1_WORKFORCE_CREW_INVALID' using errcode = '22023';
  end if;

  foreach v_worker in array coalesce(p_remove_worker_ids, array[]::uuid[]) loop
    update public.v1_workforce_crew_members
    set removed_at = clock_timestamp(),
        removed_by_auth_user_id = v_actor
    where team_id = p_team_id
      and worker_id = v_worker
      and removed_at is null;
  end loop;

  foreach v_worker in array coalesce(p_add_worker_ids, array[]::uuid[]) loop
    if not exists (
      select 1 from public.v1_workforce_workers worker
      where worker.id = v_worker and worker.current_status = 'active'
    ) then
      raise exception 'V1_WORKFORCE_WORKER_NOT_ACTIVE' using errcode = '22023';
    end if;
    if not public.v1_wf_is_labour(v_worker) then
      raise exception 'V1_WORKFORCE_STAFF_NOT_ON_SHEETS' using errcode = '22023';
    end if;
    insert into public.v1_workforce_crew_members (
      team_id, worker_id, added_by_auth_user_id
    )
    select p_team_id, v_worker, v_actor
    where not exists (
      select 1 from public.v1_workforce_crew_members member
      where member.team_id = p_team_id
        and member.worker_id = v_worker
        and member.removed_at is null
    );
  end loop;

  perform public.v1_write_audit_event(
    'workforce_crew_members_changed', 'workforce_crew', p_team_id,
    (select project_id from public.v1_workforce_crew_profiles
     where team_id = p_team_id),
    null,
    jsonb_build_object(
      'added', coalesce(cardinality(p_add_worker_ids), 0),
      'removed', coalesce(cardinality(p_remove_worker_ids), 0)
    ),
    null, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_wf_set_crew_members', p_idempotency_key,
    jsonb_build_object('crew_id', p_team_id)
  );
  return public.v1_wf_crew_json(p_team_id);
exception
  when unique_violation then
    -- Two people added the same worker at once: they are on the sheet.
    return public.v1_wf_crew_json(p_team_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Saving a day.
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
  v_needs_reason boolean;
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

  select project_id into v_project
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

  v_needs_reason := v_has_sheet and v_sheet.entered_by_auth_user_id <> v_actor;
  if v_needs_reason and v_reason is null then
    raise exception 'V1_WORKFORCE_CHANGE_REASON_REQUIRED' using errcode = '22023';
  end if;
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
        'work_label', 'overtime_note', 'copied'
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
    if v_work_project is not null and not exists (
      select 1 from public.v1_projects project where project.id = v_work_project
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
    v_before := case when found then jsonb_build_object(
      'status', v_old.attendance_status,
      'start_minute', v_old.start_minute,
      'break_start_minute', v_old.break_start_minute,
      'break_finish_minute', v_old.break_finish_minute,
      'finish_minute', v_old.finish_minute,
      'work_project_id', v_old.work_project_id,
      'work_label', v_old.work_label
    ) end;
    v_after := jsonb_build_object(
      'status', v_status,
      'start_minute', v_start,
      'break_start_minute', v_break_start,
      'break_finish_minute', v_break_finish,
      'finish_minute', v_finish,
      'work_project_id', v_work_project,
      'work_label', v_label
    );

    insert into public.v1_workforce_day_rows (
      sheet_id, team_id, work_date, worker_id, attendance_status,
      start_minute, break_start_minute, break_finish_minute, finish_minute,
      work_project_id, work_label, overtime_note, copied,
      worked_minutes, regular_minutes, normal_overtime_minutes,
      holiday_overtime_minutes, updated_by_auth_user_id
    ) values (
      v_sheet.id, p_team_id, p_work_date, v_worker, v_status,
      v_start, v_break_start, v_break_finish, v_finish,
      v_work_project, v_label, v_note, v_copied,
      v_minutes[1], v_minutes[2], v_minutes[3], v_minutes[4], v_actor
    )
    on conflict (sheet_id, worker_id) do update
    set attendance_status = excluded.attendance_status,
        start_minute = excluded.start_minute,
        break_start_minute = excluded.break_start_minute,
        break_finish_minute = excluded.break_finish_minute,
        finish_minute = excluded.finish_minute,
        work_project_id = excluded.work_project_id,
        work_label = excluded.work_label,
        overtime_note = excluded.overtime_note,
        copied = excluded.copied,
        changed_after_entry = public.v1_workforce_day_rows.changed_after_entry
          or (v_needs_reason and v_before is distinct from v_after),
        worked_minutes = excluded.worked_minutes,
        regular_minutes = excluded.regular_minutes,
        normal_overtime_minutes = excluded.normal_overtime_minutes,
        holiday_overtime_minutes = excluded.holiday_overtime_minutes,
        updated_by_auth_user_id = v_actor,
        updated_at = clock_timestamp();

    if v_needs_reason and v_before is distinct from v_after then
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
  if exists (
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
    if v_needs_reason then
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
    perform public.v1_wf_notify(
      v_sheet.entered_by_auth_user_id, 'workforce_attendance_day_changed',
      'workforce_day_sheet', v_sheet.id, v_project
    );
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
-- 7. Month-end reminders: the project's Project Engineers, or the Senior
--    Mechanical Engineers when the project has none or the sheet is for an
--    internal location.
-- ---------------------------------------------------------------------------

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
        and public.v1_permission_exact_role(profile.auth_user_id)
          = 'senior_mechanical_engineer'
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

-- ---------------------------------------------------------------------------
-- 8. Crew requests: assigning adds the sheet and keeps the worker's others;
--    only labour is offered or assigned; a worker on several sheets shows
--    the first. Patched in place so the rest of each function is untouched.
-- ---------------------------------------------------------------------------

do $patch$
declare
  v_definition text;
  v_old text;
  v_new text;
  v_signature text;
begin
  -- Assigning a worker no longer moves them off another sheet.
  v_signature := 'public.v1_wf_fulfil_request(uuid,jsonb,bigint,uuid)';
  v_definition := pg_catalog.pg_get_functiondef(v_signature::regprocedure);
  v_old := $old$      v_previous_team := null;
      select member.team_id into v_previous_team
      from public.v1_workforce_crew_members member
      where member.worker_id = v_worker and member.removed_at is null
      for update;
      if v_previous_team is not null then
        -- Only the person named on this line may be moved from another
        -- crew; the requester and approver were both warned.
        if v_line.worker_id is distinct from v_worker
          or v_previous_team = v_team then
          raise exception 'V1_WORKFORCE_WORKER_ON_CREW' using errcode = '23505';
        end if;
        update public.v1_workforce_crew_members
        set removed_at = clock_timestamp(), removed_by_auth_user_id = v_actor
        where worker_id = v_worker and removed_at is null;
        v_moved := v_moved || jsonb_build_object(
          'worker_id', v_worker, 'from_crew_id', v_previous_team
        );
      end if;$old$;
  v_new := $new$      -- A labourer may work on several sheets: assigning adds this
      -- sheet and keeps the others (PRODUCT_DECISIONS section 46).
      if not public.v1_wf_is_labour(v_worker) then
        raise exception 'V1_WORKFORCE_STAFF_NOT_ON_SHEETS'
          using errcode = '22023';
      end if;
      if exists (
        select 1 from public.v1_workforce_crew_members member
        where member.worker_id = v_worker
          and member.team_id = v_team
          and member.removed_at is null
      ) then
        raise exception 'V1_WORKFORCE_WORKER_ON_CREW' using errcode = '23505';
      end if;$new$;
  -- Already patched (a re-run): nothing to do.
  if strpos(v_definition, v_new) = 0 then
    if (char_length(v_definition)
        - char_length(replace(v_definition, v_old, '')))
      / char_length(v_old) <> 1 then
      raise exception 'V1_WORKFORCE_MULTI_PLACE_PATCH_DRIFT: fulfil'
        using errcode = '55000';
    end if;
    execute replace(v_definition, v_old, v_new);
  end if;

  -- Only labour is offered when naming workers on a request.
  v_signature := 'public.v1_wf_request_options()';
  v_definition := pg_catalog.pg_get_functiondef(v_signature::regprocedure);
  v_old := $old$      from public.v1_workforce_workers worker
      where worker.current_status = 'active'
    ), '[]'::jsonb) else '[]'::jsonb end$old$;
  v_new := $new$      from public.v1_workforce_workers worker
      where worker.current_status = 'active'
        and public.v1_wf_is_labour(worker.id)
    ), '[]'::jsonb) else '[]'::jsonb end$new$;
  -- Already patched (a re-run): nothing to do.
  if strpos(v_definition, v_new) = 0 then
    if (char_length(v_definition)
        - char_length(replace(v_definition, v_old, '')))
      / char_length(v_old) <> 1 then
      raise exception 'V1_WORKFORCE_MULTI_PLACE_PATCH_DRIFT: options'
        using errcode = '55000';
    end if;
    execute replace(v_definition, v_old, v_new);
  end if;

  -- A named worker on several sheets shows the first instead of failing.
  v_signature := 'public.v1_wf_request_json(uuid,boolean)';
  v_definition := pg_catalog.pg_get_functiondef(v_signature::regprocedure);
  v_old := $old$          select jsonb_build_object(
            'id', worker.id,
            'number', worker.worker_number,
            'name', worker.full_name,
            'designation', worker.designation,
            'crew_id', member.team_id,
            'crew_name', crew.team_name
          )
          from public.v1_workforce_workers worker
          left join public.v1_workforce_crew_members member
            on member.worker_id = worker.id and member.removed_at is null
          left join public.v1_workforce_teams crew on crew.id = member.team_id
          where worker.id = line.worker_id
        ) end,$old$;
  v_new := $new$          select jsonb_build_object(
            'id', named.json ->> 'id',
            'number', named.json ->> 'number',
            'name', named.json ->> 'name',
            'designation', named.json ->> 'designation',
            'crew_id', named.json ->> 'crew_id',
            'crew_name', named.json ->> 'crew_name'
          )
          from (
            select public.v1_wf_worker_json(line.worker_id) as json
          ) named
          where named.json is not null
        ) end,$new$;
  -- Already patched (a re-run): nothing to do.
  if strpos(v_definition, v_new) = 0 then
    if (char_length(v_definition)
        - char_length(replace(v_definition, v_old, '')))
      / char_length(v_old) <> 1 then
      raise exception 'V1_WORKFORCE_MULTI_PLACE_PATCH_DRIFT: request json'
        using errcode = '55000';
    end if;
    execute replace(v_definition, v_old, v_new);
  end if;
end;
$patch$;

-- ---------------------------------------------------------------------------
-- 9. Grants.
-- ---------------------------------------------------------------------------

do $grants$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'v1_wf_is_labour(uuid)',
    'v1_wf_role_can_keep(text)',
    'v1_wf_elsewhere_json(uuid,date,uuid)',
    'v1_wf_recompute_worker_day(uuid,date)',
    'v1_wf_crew_access(uuid)',
    'v1_wf_worker_json(uuid)',
    'v1_wf_send_month_end_reminders()'
  ] loop
    execute format(
      'revoke all on function public.%s from public, anon, authenticated',
      v_signature
    );
  end loop;
  foreach v_signature in array array[
    'v1_wf_list_crews()',
    'v1_wf_list_workers()',
    'v1_wf_get_day(uuid,date)',
    'v1_wf_save_crew(jsonb,bigint,uuid)',
    'v1_wf_set_crew_members(uuid,uuid[],uuid[],uuid)',
    'v1_wf_save_day(uuid,date,jsonb,bigint,text,uuid)'
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
