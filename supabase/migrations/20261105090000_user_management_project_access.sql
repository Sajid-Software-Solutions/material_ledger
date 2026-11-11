-- User Management: project access directory and app-user keyed team commands.
--
-- The User Management screen lists accounts by their stable application user
-- ID (the admin-users Edge Function never discloses Auth UUIDs). Project teams
-- are stored per Auth UUID in v1_project_members. These additive functions
-- bridge the two inside the trusted boundary:
--
--   v1_list_user_project_access()
--     One read for the screen: every account's structural project access
--     (organisation-wide role, Procurement's active/on-hold scope, or dated
--     Project/Site Engineer memberships) plus each visible project's team.
--
--   v1_set_user_project_membership(payload, idempotency_key)
--     Assigns, changes or removes one user's role on one project. It resolves
--     the app user ID and delegates to the existing audited
--     v1_assign_project_member / v1_revoke_project_member commands, so every
--     rule (team manager authority, project state, version check, at least one
--     Project Engineer on an active project, audit, idempotency) is unchanged.
--
-- Project rows are redacted to projects the caller can currently read. Auth
-- UUIDs never leave the database.

begin;

create or replace function public.v1_user_project_access_target(
  p_app_user_id text
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select auth_user.id
      from auth.users auth_user
      where auth_user.raw_app_meta_data ->> 'app_user_id' =
        nullif(btrim(coalesce(p_app_user_id, '')), '')
      order by auth_user.created_at, auth_user.id
      limit 1
    ),
    public.v1_permission_target_auth_id(p_app_user_id)
  );
$$;

create or replace function public.v1_user_project_access_basis(
  p_exact_role text
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_exact_role in (
      'admin', 'senior_mechanical_engineer', 'project_manager',
      'workshop_in_charge', 'document_controller'
    ) then 'all_projects'
    when p_exact_role = 'procurement' then 'active_projects'
    when p_exact_role in ('project_engineer', 'site_engineer') then 'assigned'
    else 'none'
  end;
$$;

create or replace function public.v1_list_user_project_access()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set jit = off
as $$
declare
  v_actor uuid := auth.uid();
  v_include_commercial boolean;
  v_now timestamptz := clock_timestamp();
  v_result jsonb;
begin
  if v_actor is null or not public.v1_current_actor_is_active() then
    raise exception 'V1_ACTIVE_ACTOR_REQUIRED' using errcode = '42501';
  end if;
  if not public.v1_current_user_has_capability('users.view', null) then
    raise exception 'V1_USER_PROJECT_ACCESS_DENIED' using errcode = '42501';
  end if;
  -- The per-user commercial projection keeps its established Admin boundary.
  v_include_commercial := public.v1_current_exact_role() = 'admin';

  with visible_project as materialized (
    select project.id as project_id, project.project_ref, project.name as project_name,
      project.state, project.record_version
    from public.v1_projects project
    where public.v1_permission_actor_can_view_project(project.id)
  ),
  person as materialized (
    select auth_user.id as auth_user_id,
      coalesce(
        nullif(btrim(coalesce(auth_user.raw_app_meta_data ->> 'app_user_id', '')), ''),
        nullif(btrim(coalesce(profile.legacy_app_user_id, '')), '')
      ) as app_user_id,
      coalesce(auth_user.raw_app_meta_data ->> 'role', '') as exact_role,
      public.v1_safe_profile_display_name(profile.display_name, auth_user.id)
        as display_name,
      coalesce(profile.is_active, false)
        and (auth_user.banned_until is null or auth_user.banned_until <= v_now)
        as is_active,
      auth_user.last_sign_in_at,
      coalesce(profile.canonical_role_snapshot, '') as canonical_role
    from auth.users auth_user
    left join public.v1_profiles profile
      on profile.auth_user_id = auth_user.id
  ),
  active_member as materialized (
    select member.project_id, member.member_auth_user_id as auth_user_id,
      member.project_role, member.effective_from
    from public.v1_project_members member
    join visible_project project on project.project_id = member.project_id
    where member.effective_to is null or member.effective_to > v_now
  ),
  project_json as (
    select coalesce(jsonb_agg(jsonb_build_object(
        'project_id', project.project_id,
        'project_ref', project.project_ref,
        'project_name', project.project_name,
        'state', project.state,
        'record_version', project.record_version,
        'can_manage_team',
          project.state in ('draft', 'active', 'on_hold')
          and public.v1_can_manage_project(project.project_id),
        'members', coalesce((
          select jsonb_agg(jsonb_build_object(
              'app_user_id', person.app_user_id,
              'display_name', coalesce(person.display_name, ''),
              'project_role', member.project_role,
              'effective_from', member.effective_from,
              'is_active', coalesce(person.is_active, false)
            ) order by
              case member.project_role when 'project_engineer' then 0 else 1 end,
              lower(coalesce(person.display_name, '')),
              member.effective_from)
          from active_member member
          left join person on person.auth_user_id = member.auth_user_id
          where member.project_id = project.project_id
        ), '[]'::jsonb)
      ) order by project.project_ref, project.project_id), '[]'::jsonb) as value
    from visible_project project
  ),
  user_json as (
    select coalesce(jsonb_agg(jsonb_build_object(
        'app_user_id', person.app_user_id,
        'exact_role', person.exact_role,
        'access_basis', public.v1_user_project_access_basis(person.exact_role),
        'is_active', person.is_active,
        'team_eligible', person.is_active
          and person.exact_role in ('project_engineer', 'site_engineer'),
        'last_sign_in_at', person.last_sign_in_at,
        'project_count', case public.v1_user_project_access_basis(person.exact_role)
          when 'all_projects' then (select count(*) from visible_project)
          when 'active_projects' then (
            select count(*) from visible_project project
            where project.state in ('active', 'on_hold')
          )
          when 'assigned' then (
            select count(distinct member.project_id)
            from active_member member
            where member.auth_user_id = person.auth_user_id
              and member.effective_from <= v_now
          )
          else 0
        end,
        'memberships', coalesce((
          select jsonb_agg(jsonb_build_object(
              'project_id', project.project_id,
              'project_ref', project.project_ref,
              'project_name', project.project_name,
              'project_state', project.state,
              'project_role', member.project_role,
              'effective_from', member.effective_from
            ) order by project.project_ref, member.project_role)
          from active_member member
          join visible_project project on project.project_id = member.project_id
          where member.auth_user_id = person.auth_user_id
        ), '[]'::jsonb),
        'commercial', case
          when v_include_commercial and person.canonical_role <> '' then (
            select jsonb_build_object(
              'view', coalesce(
                (commercial.envelope #>> '{capabilities,view_commercials,effective}')::boolean,
                false
              ),
              'manage', coalesce(
                (commercial.envelope #>> '{capabilities,manage_commercials,effective}')::boolean,
                false
              )
            )
            from (
              select public.v1_commercial_capability_envelope(person.auth_user_id)
                as envelope
            ) commercial
          )
          else null
        end
      ) order by lower(coalesce(person.display_name, '')), person.app_user_id),
      '[]'::jsonb) as value
    from person
    where person.app_user_id is not null
      and length(person.app_user_id) <= 128
  )
  select jsonb_build_object(
    'generated_at', v_now,
    'commercial_visible', v_include_commercial,
    'users', (select value from user_json),
    'projects', (select value from project_json)
  )
  into v_result;

  return v_result;
end;
$$;

create or replace function public.v1_set_user_project_membership(
  p_payload jsonb,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_app_user_id text;
  v_target uuid;
  v_project_id uuid;
  v_role text;
  v_expected_version integer;
  v_reason text;
  v_current_role text;
  v_inner jsonb;
  v_version integer;
begin
  perform public.v1_assert_object_keys(
    p_payload,
    array['app_user_id', 'project_id', 'project_role', 'expected_version', 'reason'],
    'set_user_project_membership_payload'
  );
  if v_actor is null or not public.v1_current_actor_is_active() then
    raise exception 'V1_ACTIVE_ACTOR_REQUIRED' using errcode = '42501';
  end if;
  if p_idempotency_key is null then
    raise exception 'V1_IDEMPOTENCY_KEY_REQUIRED' using errcode = '22023';
  end if;

  v_app_user_id := nullif(btrim(coalesce(p_payload ->> 'app_user_id', '')), '');
  v_project_id := nullif(btrim(coalesce(p_payload ->> 'project_id', '')), '')::uuid;
  v_role := nullif(btrim(coalesce(p_payload ->> 'project_role', '')), '');
  v_expected_version := nullif(
    btrim(coalesce(p_payload ->> 'expected_version', '')), ''
  )::integer;
  v_reason := coalesce(
    nullif(btrim(coalesce(p_payload ->> 'reason', '')), ''),
    'Project access updated from User Management'
  );
  if v_app_user_id is null or v_project_id is null
    or v_expected_version is null then
    raise exception 'V1_SET_USER_PROJECT_MEMBERSHIP_REQUIRED_FIELDS_MISSING'
      using errcode = '22023';
  end if;
  if v_role is not null and v_role not in ('project_engineer', 'site_engineer') then
    raise exception 'V1_INVALID_PROJECT_MEMBER_ROLE' using errcode = '22023';
  end if;
  if not public.v1_permission_actor_can_view_project(v_project_id) then
    raise exception 'V1_PROJECT_TEAM_MANAGEMENT_DENIED' using errcode = '42501';
  end if;

  v_target := public.v1_user_project_access_target(v_app_user_id);
  if v_target is null then
    raise exception 'V1_USER_PROJECT_ACCESS_TARGET_NOT_FOUND' using errcode = 'P0002';
  end if;

  select member.project_role into v_current_role
  from public.v1_project_members member
  where member.project_id = v_project_id
    and member.member_auth_user_id = v_target
    and member.effective_to is null
  order by member.effective_from desc
  limit 1;

  if v_role is not distinct from v_current_role then
    if not public.v1_can_manage_project(v_project_id) then
      raise exception 'V1_PROJECT_TEAM_MANAGEMENT_DENIED' using errcode = '42501';
    end if;
    select project.record_version into v_version
    from public.v1_projects project where project.id = v_project_id;
    return jsonb_build_object(
      'app_user_id', v_app_user_id,
      'project_id', v_project_id,
      'project_role', v_role,
      'changed', false,
      'project_record_version', v_version
    );
  end if;

  if v_role is null then
    v_inner := public.v1_revoke_project_member(
      jsonb_build_object(
        'project_id', v_project_id,
        'member_auth_user_id', v_target,
        'project_role', v_current_role,
        'expected_version', v_expected_version,
        'reason', v_reason
      ),
      p_idempotency_key
    );
  else
    v_inner := public.v1_assign_project_member(
      jsonb_build_object(
        'project_id', v_project_id,
        'member_auth_user_id', v_target,
        'project_role', v_role,
        'expected_version', v_expected_version,
        'reason', v_reason
      ),
      p_idempotency_key
    );
  end if;

  return jsonb_build_object(
    'app_user_id', v_app_user_id,
    'project_id', v_project_id,
    'project_role', v_role,
    'changed', true,
    'project_record_version', (v_inner ->> 'project_record_version')::integer
  );
end;
$$;

revoke all on function public.v1_user_project_access_target(text)
  from public, anon, authenticated;
revoke all on function public.v1_user_project_access_basis(text)
  from public, anon, authenticated;
revoke all on function public.v1_list_user_project_access()
  from public, anon, authenticated;
revoke all on function public.v1_set_user_project_membership(jsonb, uuid)
  from public, anon, authenticated;
grant execute on function public.v1_list_user_project_access() to authenticated;
grant execute on function public.v1_set_user_project_membership(jsonb, uuid)
  to authenticated;

commit;
