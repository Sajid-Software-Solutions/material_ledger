-- Rollback for the terminal attendance bundle (PRODUCT_DECISIONS.md section
-- 65). Every terminal goes back to watching, the eight functions the bundle
-- replaced are restored exactly as they are on main, and the functions it
-- added are removed. Nothing is deleted: both new tables, every match,
-- everything terminals recorded and the new columns stay, and the receiver
-- and the punch log (section 64) are not touched.
--
-- It refuses to run while a terminal's own line or a day only a terminal has
-- written on exists: the previous functions cannot read those. Have a person
-- save or remove them first (or keep this release and switch the terminals to
-- watching, which already stops new lines). While no terminal has ever been
-- switched to adding there are none.
--
-- Apply by hand, with the owner's OK:
--   npx supabase@latest db query --remote=<ref> --yes -f supabase/release/terminal_attendance_rollback.sql
-- The bundle can be applied again afterwards.

begin;

do $guard$
declare
  v_lines integer;
  v_days integer;
begin
  select count(*) into v_lines
  from public.v1_workforce_day_rows day_row
  where day_row.updated_by_auth_user_id is null;
  select count(*) into v_days
  from public.v1_workforce_day_sheets sheet
  where sheet.entered_by_auth_user_id is null
    or sheet.last_saved_by_auth_user_id is null;
  if v_lines > 0 or v_days > 0 then
    raise exception
      'terminal attendance rollback: % terminal line(s) and % day(s) only a terminal has written on must be saved or removed by a person first',
      v_lines, v_days;
  end if;
end;
$guard$;

-- No terminal adds.
update public.v1_workforce_terminals
set attendance_mode = 'watch',
    record_version = record_version + 1,
    updated_at = clock_timestamp()
where attendance_mode <> 'watch';

-- The seven-argument save is replaced by the six-argument one below.
drop function if exists public.v1_wf_save_day(
  uuid, date, jsonb, bigint, text, uuid, uuid[]
);

-- ---------------------------------------------------------------------------
-- The functions as they are on main.
-- ---------------------------------------------------------------------------

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

create or replace function public.v1_wf_get_month_sheet(
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
  v_workers jsonb;
  v_takers jsonb;
begin
  perform public.v1_wf_assert_crew(p_team_id, 'view');
  if p_month is null then
    raise exception 'V1_WORKFORCE_DATE_REQUIRED' using errcode = '22023';
  end if;

  select coalesce(jsonb_agg(
    public.v1_wf_worker_json(worker_ids.worker_id)
      || jsonb_build_object('days', coalesce((
        select jsonb_agg(
          public.v1_wf_row_json(day_row)
            || jsonb_build_object('date', day_row.work_date)
          order by day_row.work_date
        )
        from public.v1_workforce_day_rows day_row
        where day_row.team_id = p_team_id
          and day_row.worker_id = worker_ids.worker_id
          and day_row.work_date between v_month and v_last
      ), '[]'::jsonb))
    order by lower(worker.full_name)
  ), '[]'::jsonb)
  into v_workers
  from (
    select distinct day_row.worker_id
    from public.v1_workforce_day_rows day_row
    where day_row.team_id = p_team_id
      and day_row.work_date between v_month and v_last
    union
    select member.worker_id
    from public.v1_workforce_crew_members member
    where member.team_id = p_team_id and member.removed_at is null
  ) worker_ids
  join public.v1_workforce_workers worker on worker.id = worker_ids.worker_id;

  -- Who entered each date, for the weekly site in-charge line.
  select coalesce(jsonb_agg(jsonb_build_object(
    'date', sheet.work_date,
    'entered_by', public.v1_wf_display_name(sheet.entered_by_auth_user_id),
    'changed', exists (
      select 1 from public.v1_workforce_day_changes change
      where change.sheet_id = sheet.id
    )
  ) order by sheet.work_date), '[]'::jsonb)
  into v_takers
  from public.v1_workforce_day_sheets sheet
  where sheet.team_id = p_team_id
    and sheet.work_date between v_month and v_last;

  return jsonb_build_object(
    'schema_version', 'yorks.workforce.month_sheet.v2',
    'crew', public.v1_wf_crew_json(p_team_id),
    'month', public.v1_wf_month_json(p_team_id, v_month),
    'workers', v_workers,
    'sheets', v_takers,
    'holidays', coalesce((
      select jsonb_agg(jsonb_build_object(
        'date', holiday.holiday_date, 'name', holiday.holiday_name
      ) order by holiday.holiday_date)
      from public.v1_workforce_public_holidays holiday
      where holiday.holiday_date between v_month and v_last
    ), '[]'::jsonb),
    'can_export', public.v1_wf_allowed('workforce.reports.export')
  );
end;
$$;

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

create or replace function public.v1_wf_terminal_json(p_terminal_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', terminal.id,
    'serial_number', terminal.serial_number,
    'terminal_name', terminal.terminal_name,
    'place_key', place.place_key,
    'is_active', terminal.is_active,
    'utc_offset_minutes', terminal.utc_offset_minutes,
    'resend_all_requested', terminal.resend_all_requested,
    'device_name', terminal.device_name,
    'firmware_version', terminal.firmware_version,
    'push_version', terminal.push_version,
    'first_seen_at', terminal.first_seen_at,
    'last_seen_at', terminal.last_seen_at,
    'last_handshake_at', terminal.last_handshake_at,
    'last_punch_received_at', terminal.last_punch_received_at,
    'record_version', terminal.record_version
  )
  from public.v1_workforce_terminals terminal
  left join public.v1_workforce_crew_profiles place
    on place.team_id = terminal.team_id
  where terminal.id = p_terminal_id;
$$;

create or replace function public.v1_wf_register_terminal(
  p_serial_number text,
  p_terminal_name text,
  p_place_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_serial text := public.v1_wf_terminal_serial(p_serial_number);
  v_name text := nullif(btrim(coalesce(p_terminal_name, '')), '');
  v_place text := nullif(lower(btrim(coalesce(p_place_key, ''))), '');
  v_team uuid;
  v_id uuid;
begin
  if v_serial is null then
    raise exception 'V1_WORKFORCE_TERMINAL_SERIAL_INVALID'
      using errcode = '22023';
  end if;
  if v_name is null or char_length(v_name) > 80 then
    raise exception 'V1_WORKFORCE_TERMINAL_NAME_INVALID'
      using errcode = '22023';
  end if;
  if v_place is not null then
    select place.team_id into v_team
    from public.v1_workforce_crew_profiles place
    where place.place_key = v_place and place.is_active;
    if not found then
      raise exception 'V1_WORKFORCE_TERMINAL_PLACE_NOT_FOUND'
        using errcode = '22023';
    end if;
  end if;

  insert into public.v1_workforce_terminals (
    serial_number, terminal_name, team_id
  ) values (v_serial, v_name, v_team)
  on conflict (serial_number) do update
  set terminal_name = excluded.terminal_name,
      team_id = excluded.team_id,
      is_active = true,
      record_version = public.v1_workforce_terminals.record_version + 1,
      updated_at = clock_timestamp()
  returning id into v_id;

  return public.v1_wf_terminal_json(v_id);
end;
$$;

create or replace function public.v1_wf_terminal_punches(
  p_serial_number text,
  p_stamp text,
  p_lines jsonb,
  p_details jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_serial text := public.v1_wf_terminal_serial(p_serial_number);
  v_details jsonb := public.v1_wf_terminal_details(p_details);
  v_gate record;
  v_terminal public.v1_workforce_terminals%rowtype;
  v_now timestamptz := clock_timestamp();
  v_stamp text := case when p_stamp ~ '^[0-9]{1,18}$' then p_stamp end;
  v_received integer := 0;
  v_valid integer := 0;
  v_stored integer := 0;
  v_rejected integer := 0;
  v_future integer := 0;
begin
  select * into v_gate from public.v1_wf_terminal_gate(p_serial_number);
  if v_gate.outcome <> 'ok' then
    if v_gate.outcome <> 'invalid' then
      perform public.v1_wf_terminal_note(
        v_gate.terminal_id, v_serial, 'punches', 'ATTLOG', v_gate.outcome,
        0, 0, 0, 0, v_details
      );
    end if;
    return jsonb_build_object('outcome', v_gate.outcome);
  end if;
  if p_lines is null
    or jsonb_typeof(p_lines) <> 'array'
    or jsonb_array_length(p_lines) > 50000 then
    perform public.v1_wf_terminal_note(
      v_gate.terminal_id, v_serial, 'punches', 'ATTLOG', 'invalid',
      0, 0, 0, 0, v_details
    );
    return jsonb_build_object('outcome', 'invalid');
  end if;

  select * into v_terminal
  from public.v1_workforce_terminals terminal
  where terminal.id = v_gate.terminal_id;
  v_received := jsonb_array_length(p_lines);

  with lines as (
    select
      left(coalesce(item.value ->> 'raw', ''), 300) as raw_line,
      char_length(coalesce(item.value ->> 'raw', '')) > 300 as truncated,
      jsonb_typeof(item.value) = 'object' as is_object,
      item.value ->> 'pin' as pin,
      public.v1_wf_terminal_time(item.value ->> 'time') as local_time,
      public.v1_wf_terminal_int(item.value ->> 'state') as state,
      public.v1_wf_terminal_int(item.value ->> 'verify') as verify,
      nullif(left(coalesce(item.value ->> 'work_code', ''), 24), '')
        as work_code
    from jsonb_array_elements(p_lines) as item(value)
  ),
  judged as (
    select
      lines.*,
      case
        when not lines.is_object then 'shape'
        when lines.pin is null
          or lines.pin !~ '^[0-9A-Za-z]{1,24}$'
          or lines.pin ~ '^0+$' then 'user_id'
        when lines.local_time is null then 'time'
      end as reason,
      (lines.local_time
        - make_interval(mins => v_terminal.utc_offset_minutes))
        at time zone 'UTC' as moment
    from lines
  ),
  stored as (
    insert into public.v1_workforce_terminal_punches (
      terminal_id, team_id, device_user_id, punched_at_local,
      utc_offset_minutes, punched_at, work_date, punch_state, verify_mode,
      work_code, clock_suspect, raw_line, received_at
    )
    select
      v_terminal.id, v_terminal.team_id, judged.pin, judged.local_time,
      v_terminal.utc_offset_minutes, judged.moment, judged.local_time::date,
      case when judged.state between 0 and 255
        then judged.state::smallint end,
      case when judged.verify between 0 and 999
        then judged.verify::smallint end,
      judged.work_code,
      judged.moment > v_now + interval '10 minutes'
        or judged.local_time < timestamp '2020-01-01 00:00:00',
      judged.raw_line, v_now
    from judged
    where judged.reason is null
    on conflict (terminal_id, device_user_id, punched_at_local) do nothing
    returning 1
  ),
  kept as (
    insert into public.v1_workforce_terminal_rejects (
      terminal_id, raw_line, truncated, reason, received_at
    )
    select v_terminal.id, judged.raw_line, judged.truncated, judged.reason,
      v_now
    from judged
    where judged.reason is not null
    on conflict (terminal_id, raw_line) do nothing
    returning 1
  )
  select
    (select count(*) from judged where judged.reason is null),
    (select count(*) from stored),
    (select count(*) from judged where judged.reason is not null),
    (select count(*) from judged
      where judged.reason is null
        and judged.moment > v_now + interval '10 minutes')
  into v_valid, v_stored, v_rejected, v_future;

  -- The stamp only moves forward, and never on a batch whose clock was
  -- ahead: a wrong future stamp would hide later punches.
  update public.v1_workforce_terminals terminal
  set first_seen_at = coalesce(terminal.first_seen_at, v_now),
      last_seen_at = v_now,
      last_punch_received_at = case
        when v_received > 0 then v_now else terminal.last_punch_received_at
      end,
      attlog_stamp = case
        when v_stamp is null or v_future > 0 then terminal.attlog_stamp
        when terminal.attlog_stamp is null
          or v_stamp::numeric > terminal.attlog_stamp::numeric then v_stamp
        else terminal.attlog_stamp
      end,
      last_remote_ip = coalesce(v_details ->> 'remote_ip', terminal.last_remote_ip)
  where terminal.id = v_terminal.id;

  perform public.v1_wf_terminal_note(
    v_terminal.id, v_serial, 'punches', 'ATTLOG', 'ok',
    v_received, v_stored, v_valid - v_stored, v_rejected, v_details
  );

  return jsonb_build_object(
    'outcome', 'ok',
    'received', v_received,
    'stored', v_stored,
    'duplicates', v_valid - v_stored,
    'rejected', v_rejected
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- The functions the bundle added.
-- ---------------------------------------------------------------------------

drop function if exists public.v1_wf_terminal_apply_day(text, date);
drop function if exists public.v1_wf_terminal_after_punches(uuid, timestamp with time zone);
drop function if exists public.v1_wf_terminal_mark_failed(uuid, date, text[]);
drop function if exists public.v1_wf_terminal_note_old(uuid, timestamp with time zone);
drop function if exists public.v1_wf_terminal_apply(uuid, date, text[]);
drop function if exists public.v1_wf_terminal_finding(uuid, date, uuid, integer);
drop function if exists public.v1_wf_set_terminal_mode(text, text);
drop function if exists public.v1_wf_end_terminal_user(text, text, uuid);
drop function if exists public.v1_wf_confirm_terminal_users(jsonb, uuid);
drop function if exists public.v1_wf_list_terminal_users();
drop function if exists public.v1_wf_terminal_users_actor();
drop function if exists public.v1_wf_terminal_day_json(uuid, date);
drop function if exists public.v1_wf_saved_by(uuid, uuid);
drop function if exists public.v1_wf_terminal_minute(timestamp without time zone);
drop function if exists public.v1_wf_terminal_number_id(text);
drop function if exists public.v1_wf_terminal_user_key(text);

-- ---------------------------------------------------------------------------
-- Every sheet and line is a person's again (the guard above made sure).
-- ---------------------------------------------------------------------------

alter table public.v1_workforce_day_rows
  drop constraint if exists v1_workforce_day_rows_saved_by_check;
alter table public.v1_workforce_day_rows
  alter column updated_by_auth_user_id set not null;
alter table public.v1_workforce_day_sheets
  drop constraint if exists v1_workforce_day_sheets_saved_by_check;
alter table public.v1_workforce_day_sheets
  alter column entered_by_auth_user_id set not null,
  alter column last_saved_by_auth_user_id set not null;
do $version$
begin
  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conname = 'v1_workforce_day_sheets_record_version_check'
  ) then
    alter table public.v1_workforce_day_sheets
      add constraint v1_workforce_day_sheets_record_version_check
      check (record_version > 0);
  end if;
end;
$version$;

-- ---------------------------------------------------------------------------
-- Grants, as before.
-- ---------------------------------------------------------------------------

do $grants$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'public.v1_wf_row_json(public.v1_workforce_day_rows)',
    'public.v1_wf_today_json(uuid, date)',
    'public.v1_wf_terminal_json(uuid)',
    'public.v1_wf_register_terminal(text, text, text)',
    'public.v1_wf_terminal_punches(text, text, jsonb, jsonb)'
  ] loop
    execute format(
      'revoke all on function %s from public, anon, authenticated',
      v_signature
    );
  end loop;
  foreach v_signature in array array[
    'public.v1_wf_get_day(uuid, date)',
    'public.v1_wf_get_month_sheet(uuid, date)',
    'public.v1_wf_save_day(uuid, date, jsonb, bigint, text, uuid)'
  ] loop
    execute format(
      'revoke all on function %s from public, anon', v_signature
    );
    execute format(
      'grant execute on function %s to authenticated', v_signature
    );
  end loop;
  foreach v_signature in array array[
    'public.v1_wf_register_terminal(text, text, text)',
    'public.v1_wf_terminal_punches(text, text, jsonb, jsonb)'
  ] loop
    execute format(
      'grant execute on function %s to service_role', v_signature
    );
  end loop;
end;
$grants$;

do $check$
begin
  if to_regprocedure(
      'public.v1_wf_save_day(uuid,date,jsonb,bigint,text,uuid)') is null
    or not has_function_privilege('authenticated',
      'public.v1_wf_save_day(uuid,date,jsonb,bigint,text,uuid)', 'execute')
    or has_function_privilege('anon',
      'public.v1_wf_save_day(uuid,date,jsonb,bigint,text,uuid)', 'execute')
    or has_function_privilege('authenticated',
      'public.v1_wf_terminal_punches(text,text,jsonb,jsonb)', 'execute')
    or exists (
      select 1 from public.v1_workforce_terminals
      where attendance_mode <> 'watch'
    ) then
    raise exception 'terminal attendance rollback self-check failed';
  end if;
end;
$check$;

commit;

notify pgrst, 'reload schema';
