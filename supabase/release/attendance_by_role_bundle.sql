-- Release bundle: Workforce attendance by role (PRODUCT_DECISIONS.md
-- section 58). Applies migration 20261115090000 in one transaction, then
-- checks itself. Replaces six functions and adds one helper; no table,
-- column or row changes. Re-running it is harmless.
-- Before it: run the read-only supabase/preflight/attendance_by_role_preflight.sql
-- and check the live v1_wf_crew_access still matches 20261114200000.
-- Apply by hand (staging, then production, each with the owner's OK):
--   npx supabase@latest db query --remote=<ref> --yes -f supabase/release/attendance_by_role_bundle.sql
-- Like the other hand-applied bundles it does not write
-- supabase_migrations.schema_migrations.
-- Rollback: supabase/release/attendance_by_role_rollback.sql

begin;

-- ---------------------------------------------------------------------------
-- 1. Who keeps attendance.
-- ---------------------------------------------------------------------------

-- Roles that open and keep attendance sheets. The Accountant keeps them as
-- HR/PRO does.
create or replace function public.v1_wf_role_can_keep(p_role text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_role in (
    'site_engineer', 'project_engineer', 'senior_mechanical_engineer',
    'project_manager', 'workshop_in_charge', 'admin', 'pr', 'accountant'
  );
$$;

-- Roles that keep internal places (workshop, store, camp).
create or replace function public.v1_wf_role_keeps_internal(p_role text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_role in ('workshop_in_charge', 'admin', 'pr', 'accountant');
$$;

-- {view, take, confirm, manage, officer, keeper} for the signed-in person on
-- one sheet. Capabilities are checked on top of role and project membership.
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
  v_internal boolean;
  v_officer boolean;
  v_office boolean;
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

  -- An internal place (workshop, store, camp) has no project.
  v_internal := v_profile.project_id is null;
  -- Admin and HR/PRO reopen months and keep the holiday calendar; with the
  -- Accountant they keep attendance at every place.
  v_officer := v_role in ('admin', 'pr');
  v_office := v_officer or v_role = 'accountant';
  -- Senior Mechanical Engineer, Project Manager, Workshop In-Charge and
  -- Document Controller see every sheet; all but Document Controller keep
  -- project sheets.
  v_global_view := public.v1_wf_role_is_global(v_role);
  v_global_keep := v_global_view and v_role <> 'document_controller';
  v_keeper := v_profile.created_by_auth_user_id = v_actor
    and public.v1_wf_role_can_keep(v_role)
    and (not v_internal or public.v1_wf_role_keeps_internal(v_role));
  if not v_internal then
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
      v_office or v_global_view or v_keeper
      or (
        not v_internal
        and v_role in ('project_engineer', 'site_engineer')
        and v_member
      )
    )
    and public.v1_wf_allowed('workforce.view');
  v_take := v_view
    and (
      v_office or v_keeper
      or (v_internal and v_role = 'workshop_in_charge')
      or (
        not v_internal
        and (
          v_global_keep
          or (v_role in ('project_engineer', 'site_engineer') and v_member)
        )
      )
    )
    and public.v1_wf_allowed('workforce.attendance.maintain');
  v_confirm := v_view
    and v_profile.needs_confirmation
    and (
      v_role in ('admin', 'senior_mechanical_engineer')
      or (
        not v_internal
        and v_role in ('project_engineer', 'site_engineer')
        and v_pe_member
      )
    )
    and public.v1_wf_allowed('workforce.timesheets.final_approve');
  -- Sheet settings stay with Admin, HR/PRO, the sheet's keeper and its
  -- engineers; the Accountant changes days, not sheets.
  v_manage := v_view
    and (
      v_officer or v_keeper
      or (v_internal and v_role = 'workshop_in_charge')
      or (
        not v_internal
        and (
          v_global_keep
          or (v_role in ('project_engineer', 'site_engineer') and v_pe_member)
        )
      )
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
-- 2. Places, opening a place and creating a sheet.
-- ---------------------------------------------------------------------------

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
    -- Only the internal-place keepers add a new internal place.
    'can_add_location', v_keep and public.v1_wf_role_keeps_internal(v_role),
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

  -- An internal place is opened only by the Workshop In-Charge, HR/PRO, the
  -- Accountant or Admin (PRODUCT_DECISIONS section 58).
  if not public.v1_wf_role_can_keep(v_role)
    or not public.v1_wf_allowed('workforce.attendance.maintain')
    or (p_project_id is null
      and not public.v1_wf_role_keeps_internal(v_role)) then
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

  -- An internal sheet (no project) is created or kept only by the Workshop
  -- In-Charge, HR/PRO, the Accountant or Admin (PRODUCT_DECISIONS section 58).
  if v_project is null and not public.v1_wf_role_keeps_internal(v_role) then
    raise exception 'V1_WORKFORCE_CREW_ACCESS_DENIED' using errcode = '42501';
  end if;

  if v_team_id is null then
    -- Anyone who keeps sheets creates one; a Site or Project Engineer only
    -- for a project they are on.
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

-- ---------------------------------------------------------------------------
-- 3. Grants.
-- ---------------------------------------------------------------------------

do $grants$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'v1_wf_role_can_keep(text)',
    'v1_wf_role_keeps_internal(text)',
    'v1_wf_crew_access(uuid)'
  ] loop
    execute format(
      'revoke all on function public.%s from public, anon, authenticated',
      v_signature
    );
  end loop;
  foreach v_signature in array array[
    'v1_wf_list_places()',
    'v1_wf_open_place(uuid,text)',
    'v1_wf_save_crew(jsonb,bigint,uuid)'
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

-- Self-check.
do $check$
begin
  if not public.v1_wf_role_keeps_internal('workshop_in_charge')
    or not public.v1_wf_role_keeps_internal('accountant')
    or public.v1_wf_role_keeps_internal('site_engineer')
    or public.v1_wf_role_keeps_internal('project_engineer')
    or public.v1_wf_role_keeps_internal('senior_mechanical_engineer')
    or not public.v1_wf_role_can_keep('accountant')
    or public.v1_wf_role_can_keep('procurement')
    or has_function_privilege('authenticated',
      'public.v1_wf_role_keeps_internal(text)', 'execute')
    or has_function_privilege('authenticated',
      'public.v1_wf_crew_access(uuid)', 'execute')
    or not has_function_privilege('authenticated',
      'public.v1_wf_list_places()', 'execute')
    or has_function_privilege('anon',
      'public.v1_wf_open_place(uuid,text)', 'execute')
    or has_function_privilege('anon',
      'public.v1_wf_save_crew(jsonb,bigint,uuid)', 'execute')
    or position('v1_wf_role_keeps_internal' in
      pg_get_functiondef('public.v1_wf_open_place(uuid,text)'::regprocedure)) = 0
    or position('v1_wf_role_keeps_internal' in
      pg_get_functiondef('public.v1_wf_save_crew(jsonb,bigint,uuid)'::regprocedure)) = 0
    or position('can_add_location' in
      pg_get_functiondef('public.v1_wf_list_places()'::regprocedure)) = 0 then
    raise exception 'attendance by role bundle self-check failed';
  end if;
end;
$check$;

commit;

notify pgrst, 'reload schema';
