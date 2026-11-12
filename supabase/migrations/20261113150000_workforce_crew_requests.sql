-- Workforce Center: crew requests (docs/yorks-v1/WORKFORCE_CENTER_DESIGN.md,
-- owner approval 12 November 2026).
--
-- A Site Engineer, Project Engineer or Workshop In-Charge asks for people
-- for a project (or the workshop). The project's Project Engineer approves,
-- returns or rejects it; a request raised by someone who may approve it is
-- approved on submit. PR (or Admin) then assigns workers line by line, into
-- an existing crew on that project or a new one, recording Partial or
-- Cannot provide now with a reason, exactly like a Material Request
-- arrangement. Assigned workers become ordinary crew members, so attendance
-- picks them up at once.
--
--   Submitted -> Approved -> Partially fulfilled -> Fulfilled
--   Submitted -> Returned -> Submitted        Submitted -> Rejected
--   Submitted/Returned/Approved (nothing assigned) -> Cancelled
--   Approved/Partially fulfilled -> Closed (reason)
--
-- Access is checked on the server for every call, on role, dated project
-- membership and the Workforce capability boundary (v1_wf_allowed).
-- Procurement has no access; Accountant reads.
--
-- Data preservation: additive tables and functions; notification wrappers
-- keep the previous chain. Rollback: unschedule
-- 'yorks-workforce-crew-request-reminders', restore the three notification
-- functions from their *_before_crew_requests versions, revoke the new RPCs;
-- keep every table and row.

begin;

-- ---------------------------------------------------------------------------
-- 1. Tables.
-- ---------------------------------------------------------------------------

create table public.v1_workforce_crew_request_counters (
  request_year integer primary key,
  last_number integer not null check (last_number >= 0)
);

create table public.v1_workforce_crew_requests (
  id uuid primary key default gen_random_uuid(),
  request_number text not null unique,
  crew_kind text not null check (crew_kind in ('project', 'workshop')),
  project_id uuid references public.v1_projects (id) on delete restrict,
  work_label text check (
    work_label is null
    or (btrim(work_label) <> '' and char_length(work_label) <= 160)
  ),
  target_team_id uuid references public.v1_workforce_teams (id)
    on delete restrict,
  needed_from date not null,
  needed_until date,
  notes text check (notes is null or char_length(notes) <= 1000),
  state text not null check (state in (
    'submitted', 'returned', 'approved', 'partially_fulfilled',
    'fulfilled', 'closed', 'rejected', 'cancelled'
  )),
  requested_by_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  requested_by_role text not null,
  submitted_at timestamptz not null default clock_timestamp(),
  decided_by_auth_user_id uuid
    references public.v1_profiles (auth_user_id) on delete restrict,
  decided_by_role text,
  decided_at timestamptz,
  decision_reason text check (
    decision_reason is null or char_length(decision_reason) <= 1000
  ),
  last_actor_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  last_actor_role text not null,
  record_version bigint not null default 1 check (record_version > 0),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check ((crew_kind = 'project') = (project_id is not null)),
  check (needed_until is null or needed_until >= needed_from)
);
create index v1_workforce_crew_requests_project_idx
  on public.v1_workforce_crew_requests (project_id, state);
create index v1_workforce_crew_requests_state_idx
  on public.v1_workforce_crew_requests (state, needed_from);

create table public.v1_workforce_crew_request_lines (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null
    references public.v1_workforce_crew_requests (id) on delete restrict,
  line_number integer not null check (line_number between 1 and 50),
  trade text not null check (
    btrim(trade) <> '' and char_length(trade) <= 120
  ),
  quantity integer not null check (quantity between 1 and 200),
  note text check (note is null or char_length(note) <= 500),
  decision text check (
    decision is null or decision in ('full', 'partial', 'cannot_provide')
  ),
  decision_reason text check (
    decision_reason is null or char_length(decision_reason) <= 500
  ),
  is_current boolean not null default true,
  created_at timestamptz not null default clock_timestamp()
);
create unique index v1_workforce_crew_request_lines_current_uidx
  on public.v1_workforce_crew_request_lines (request_id, line_number)
  where is_current;

create table public.v1_workforce_crew_request_assignments (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null
    references public.v1_workforce_crew_requests (id) on delete restrict,
  line_id uuid not null
    references public.v1_workforce_crew_request_lines (id) on delete restrict,
  worker_id uuid not null
    references public.v1_workforce_workers (id) on delete restrict,
  team_id uuid not null
    references public.v1_workforce_teams (id) on delete restrict,
  crew_member_id uuid not null
    references public.v1_workforce_crew_members (id) on delete restrict,
  assigned_by_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  assigned_at timestamptz not null default clock_timestamp(),
  unique (request_id, worker_id)
);
create index v1_workforce_crew_request_assignments_line_idx
  on public.v1_workforce_crew_request_assignments (line_id);

create table public.v1_workforce_crew_request_events (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null
    references public.v1_workforce_crew_requests (id) on delete restrict,
  event_type text not null check (event_type in (
    'submitted', 'resubmitted', 'approved', 'returned', 'rejected',
    'cancelled', 'workers_assigned', 'closed'
  )),
  actor_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  actor_role text not null,
  from_state text,
  to_state text not null,
  reason text check (reason is null or char_length(reason) <= 1000),
  detail jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default clock_timestamp()
);
create index v1_workforce_crew_request_events_request_idx
  on public.v1_workforce_crew_request_events (request_id, occurred_at);

-- One overdue summary per person per day.
create table public.v1_workforce_crew_request_digests (
  id uuid primary key default gen_random_uuid(),
  recipient_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  sent_on date not null,
  request_count integer not null check (request_count > 0),
  created_at timestamptz not null default clock_timestamp(),
  unique (recipient_auth_user_id, sent_on)
);

create trigger v1_workforce_crew_request_events_append_only
before update or delete on public.v1_workforce_crew_request_events
for each row execute function public.v1_wf_block_history_mutation();

do $no_delete$
declare
  v_table text;
begin
  foreach v_table in array array[
    'v1_workforce_crew_request_counters',
    'v1_workforce_crew_requests', 'v1_workforce_crew_request_lines',
    'v1_workforce_crew_request_assignments',
    'v1_workforce_crew_request_digests'
  ] loop
    execute format(
      'create trigger %I before delete on public.%I '
      'for each row execute function public.v1_workforce_block_delete()',
      v_table || '_no_delete', v_table
    );
  end loop;
  foreach v_table in array array[
    'v1_workforce_crew_request_counters', 'v1_workforce_crew_requests',
    'v1_workforce_crew_request_lines',
    'v1_workforce_crew_request_assignments',
    'v1_workforce_crew_request_events', 'v1_workforce_crew_request_digests'
  ] loop
    execute format('alter table public.%I enable row level security', v_table);
    execute format(
      'revoke all on table public.%I from public, anon, authenticated',
      v_table
    );
  end loop;
end;
$no_delete$;

-- ---------------------------------------------------------------------------
-- 2. Access.
-- ---------------------------------------------------------------------------

-- The signed-in person's standing on a project: member, Project Engineer.
create or replace function public.v1_wf_project_standing(p_project_id uuid)
returns table (is_member boolean, is_project_engineer boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select
    coalesce(bool_or(true), false),
    coalesce(bool_or(member.project_role = 'project_engineer'), false)
  from public.v1_project_members member
  where p_project_id is not null
    and member.project_id = p_project_id
    and member.member_auth_user_id = auth.uid()
    and member.effective_from <= clock_timestamp()
    and (member.effective_to is null
      or member.effective_to > clock_timestamp());
$$;

-- May the signed-in person raise a request for this project (null: the
-- workshop)?
create or replace function public.v1_wf_can_request(p_project_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text := public.v1_current_exact_role();
  v_member boolean;
  v_pe boolean;
begin
  if auth.uid() is null or not public.v1_current_actor_is_active()
    or not public.v1_wf_allowed('workforce.attendance.maintain') then
    return false;
  end if;
  if v_role in ('admin', 'pr') or public.v1_wf_role_is_global(v_role) then
    return true;
  end if;
  if p_project_id is null then
    return false;
  end if;
  select standing.is_member, standing.is_project_engineer
  into v_member, v_pe
  from public.v1_wf_project_standing(p_project_id) standing;
  return v_role in ('project_engineer', 'site_engineer') and v_member;
end;
$$;

-- May the signed-in person approve requests for this project?
create or replace function public.v1_wf_can_decide(p_project_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text := public.v1_current_exact_role();
  v_pe boolean;
begin
  if auth.uid() is null or not public.v1_current_actor_is_active()
    or not public.v1_wf_allowed('workforce.teams.manage') then
    return false;
  end if;
  if v_role = 'admin' or public.v1_wf_role_is_global(v_role) then
    return true;
  end if;
  if p_project_id is null or v_role <> 'project_engineer' then
    return false;
  end if;
  select standing.is_project_engineer into v_pe
  from public.v1_wf_project_standing(p_project_id) standing;
  return coalesce(v_pe, false);
end;
$$;

-- {view, decide, fulfil, cancel, resubmit} on one request.
create or replace function public.v1_wf_request_access(p_request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text := public.v1_current_exact_role();
  v_request public.v1_workforce_crew_requests%rowtype;
  v_member boolean := false;
  v_view boolean;
  v_mine boolean;
  v_assigned boolean;
  v_none jsonb := jsonb_build_object(
    'view', false, 'decide', false, 'fulfil', false, 'cancel', false,
    'resubmit', false
  );
begin
  if auth.uid() is null or v_role = ''
    or not public.v1_current_actor_is_active() then
    return v_none;
  end if;
  select * into v_request
  from public.v1_workforce_crew_requests request
  where request.id = p_request_id;
  if not found then
    return v_none;
  end if;
  select coalesce(standing.is_member, false) into v_member
  from public.v1_wf_project_standing(v_request.project_id) standing;
  v_mine := v_request.requested_by_auth_user_id = auth.uid();
  v_view := (
      v_role in ('admin', 'pr', 'accountant')
      or public.v1_wf_role_is_global(v_role)
      or v_mine
      or (v_role in ('project_engineer', 'site_engineer') and v_member)
    )
    and public.v1_wf_allowed('workforce.view');
  if not v_view then
    return v_none;
  end if;
  v_assigned := exists (
    select 1 from public.v1_workforce_crew_request_assignments assignment
    where assignment.request_id = v_request.id
  );
  return jsonb_build_object(
    'view', true,
    'decide', v_request.state = 'submitted'
      and not v_mine
      and public.v1_wf_can_decide(v_request.project_id),
    'fulfil', v_request.state in ('approved', 'partially_fulfilled')
      and v_role in ('admin', 'pr')
      and public.v1_wf_allowed('workforce.workers.manage'),
    'cancel', v_request.state in ('submitted', 'returned', 'approved')
      and not v_assigned
      and (v_mine or v_role = 'admin'),
    'resubmit', v_request.state = 'returned' and v_mine
  );
end;
$$;

create or replace function public.v1_wf_assert_request(
  p_request_id uuid,
  p_right text
)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_request_id is null
    or not coalesce(
      (public.v1_wf_request_access(p_request_id) ->> p_right)::boolean, false
    ) then
    raise exception 'V1_WORKFORCE_REQUEST_ACCESS_DENIED' using errcode = '42501';
  end if;
  return auth.uid();
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Notifications.
-- ---------------------------------------------------------------------------

create or replace function public.v1_wf_request_notify(
  p_recipient uuid,
  p_event_code text,
  p_request_id uuid,
  p_project_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_recipient is null or p_recipient = auth.uid() then
    return;
  end if;
  if not exists (
    select 1 from public.v1_profiles profile
    where profile.auth_user_id = p_recipient and profile.is_active
  ) then
    return;
  end if;
  insert into public.v1_notifications (
    id, recipient_auth_user_id, event_code, entity_type, entity_id,
    project_id
  ) values (
    gen_random_uuid(), p_recipient,
    case p_event_code
      when 'workforce_crew_request_submitted'
        then 'workforce_crew_request_submitted'
      when 'workforce_crew_request_approved'
        then 'workforce_crew_request_approved'
      when 'workforce_crew_request_returned'
        then 'workforce_crew_request_returned'
      when 'workforce_crew_request_rejected'
        then 'workforce_crew_request_rejected'
      when 'workforce_crew_request_fulfilled'
        then 'workforce_crew_request_fulfilled'
    end,
    'workforce_crew_request', p_request_id, p_project_id
  );
end;
$$;

-- Approvers for a project: its Project Engineers; with none (or for the
-- workshop) the Senior Mechanical Engineers and Project Managers.
create or replace function public.v1_wf_request_approvers(p_project_id uuid)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  with pe as (
    select distinct member.member_auth_user_id as auth_user_id
    from public.v1_project_members member
    where p_project_id is not null
      and member.project_id = p_project_id
      and member.project_role = 'project_engineer'
      and member.effective_from <= clock_timestamp()
      and (member.effective_to is null
        or member.effective_to > clock_timestamp())
  )
  select auth_user_id from pe
  union
  select profile.auth_user_id
  from public.v1_profiles profile
  where not exists (select 1 from pe)
    and profile.is_active
    and public.v1_permission_exact_role(profile.auth_user_id) in (
      'senior_mechanical_engineer', 'project_manager'
    );
$$;

-- Who assigns workers: PR; Admin when there is no active PR.
create or replace function public.v1_wf_request_fulfillers()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  with pr as (
    select profile.auth_user_id
    from public.v1_profiles profile
    where profile.is_active
      and public.v1_permission_exact_role(profile.auth_user_id) = 'pr'
  )
  select auth_user_id from pr
  union
  select profile.auth_user_id
  from public.v1_profiles profile
  where not exists (select 1 from pr)
    and profile.is_active
    and public.v1_permission_exact_role(profile.auth_user_id) = 'admin';
$$;

-- ---------------------------------------------------------------------------
-- 4. Projections.
-- ---------------------------------------------------------------------------

create or replace function public.v1_wf_request_json(
  p_request_id uuid,
  p_detail boolean
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', request.id,
    'number', request.request_number,
    'state', request.state,
    'crew_kind', request.crew_kind,
    'project_id', request.project_id,
    'project_name', project.name,
    'project_ref', project.project_ref,
    'work_label', request.work_label,
    'target_crew_id', request.target_team_id,
    'target_crew_name', target.team_name,
    'needed_from', request.needed_from,
    'needed_until', request.needed_until,
    'notes', request.notes,
    'requested_by', jsonb_build_object(
      'id', request.requested_by_auth_user_id,
      'name', public.v1_wf_display_name(request.requested_by_auth_user_id),
      'role', request.requested_by_role
    ),
    'submitted_at', request.submitted_at,
    'decided_by', case when request.decided_by_auth_user_id is not null then
      jsonb_build_object(
        'id', request.decided_by_auth_user_id,
        'name', public.v1_wf_display_name(request.decided_by_auth_user_id),
        'role', request.decided_by_role
      ) end,
    'decided_at', request.decided_at,
    'decision_reason', request.decision_reason,
    'last_actor', jsonb_build_object(
      'name', public.v1_wf_display_name(request.last_actor_auth_user_id),
      'role', request.last_actor_role
    ),
    'updated_at', request.updated_at,
    'record_version', request.record_version,
    'owner', case request.state
      when 'submitted' then 'project_engineer'
      when 'returned' then 'requester'
      when 'approved' then 'pr'
      when 'partially_fulfilled' then 'pr'
    end,
    'overdue', request.state in ('approved', 'partially_fulfilled')
      and request.needed_from <= public.v1_wf_today(),
    'requested_count', totals.requested,
    'assigned_count', totals.assigned,
    'trades', totals.trades,
    'access', public.v1_wf_request_access(request.id),
    'lines', case when p_detail then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', line.id,
        'line_number', line.line_number,
        'trade', line.trade,
        'quantity', line.quantity,
        'note', line.note,
        'decision', line.decision,
        'decision_reason', line.decision_reason,
        'assigned', coalesce((
          select jsonb_agg(jsonb_build_object(
            'worker_id', worker.id,
            'number', worker.worker_number,
            'name', worker.full_name,
            'designation', worker.designation,
            'crew_id', assignment.team_id,
            'crew_name', team.team_name,
            'assigned_at', assignment.assigned_at
          ) order by assignment.assigned_at, lower(worker.full_name))
          from public.v1_workforce_crew_request_assignments assignment
          join public.v1_workforce_workers worker
            on worker.id = assignment.worker_id
          join public.v1_workforce_teams team on team.id = assignment.team_id
          where assignment.line_id = line.id
        ), '[]'::jsonb)
      ) order by line.line_number)
      from public.v1_workforce_crew_request_lines line
      where line.request_id = request.id and line.is_current
    ), '[]'::jsonb) end,
    'events', case when p_detail then coalesce((
      select jsonb_agg(jsonb_build_object(
        'type', event.event_type,
        'actor_name', public.v1_wf_display_name(event.actor_auth_user_id),
        'actor_role', event.actor_role,
        'from_state', event.from_state,
        'to_state', event.to_state,
        'reason', event.reason,
        'detail', event.detail,
        'at', event.occurred_at
      ) order by event.occurred_at, event.id)
      from public.v1_workforce_crew_request_events event
      where event.request_id = request.id
    ), '[]'::jsonb) end
  )
  from public.v1_workforce_crew_requests request
  left join public.v1_projects project on project.id = request.project_id
  left join public.v1_workforce_teams target
    on target.id = request.target_team_id
  cross join lateral (
    select
      coalesce(sum(line.quantity), 0)::integer as requested,
      (select count(*)::integer
       from public.v1_workforce_crew_request_assignments assignment
       where assignment.request_id = request.id) as assigned,
      coalesce(jsonb_agg(jsonb_build_object(
        'trade', line.trade, 'quantity', line.quantity
      ) order by line.line_number), '[]'::jsonb) as trades
    from public.v1_workforce_crew_request_lines line
    where line.request_id = request.id and line.is_current
  ) totals
  where request.id = p_request_id;
$$;

create or replace function public.v1_wf_list_requests()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text := public.v1_current_exact_role();
begin
  if auth.uid() is null or not public.v1_current_actor_is_active()
    or v_role = 'procurement'
    or not public.v1_wf_allowed('workforce.view') then
    raise exception 'V1_WORKFORCE_REQUEST_ACCESS_DENIED' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'schema_version', 'yorks.workforce.crew_requests.v1',
    'today', public.v1_wf_today(),
    'can_request', public.v1_wf_can_request(null)
      or exists (
        select 1 from public.v1_project_members member
        where member.member_auth_user_id = auth.uid()
          and member.effective_from <= clock_timestamp()
          and (member.effective_to is null
            or member.effective_to > clock_timestamp())
          and public.v1_wf_can_request(member.project_id)
      ),
    'requests', coalesce((
      select jsonb_agg(item.json order by item.sort_key desc)
      from (
        select public.v1_wf_request_json(request.id, false) as json,
          request.updated_at as sort_key
        from public.v1_workforce_crew_requests request
        where coalesce(
          (public.v1_wf_request_access(request.id) ->> 'view')::boolean,
          false
        )
        order by request.updated_at desc
        limit 500
      ) item
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.v1_wf_get_request(p_request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.v1_wf_assert_request(p_request_id, 'view');
  return public.v1_wf_request_json(p_request_id, true);
end;
$$;

-- Projects the signed-in person may request crews for, and active workers
-- available for assignment (PR/Admin only).
create or replace function public.v1_wf_request_options()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text := public.v1_current_exact_role();
  v_officer boolean;
begin
  if auth.uid() is null or not public.v1_current_actor_is_active()
    or v_role = 'procurement'
    or not public.v1_wf_allowed('workforce.view') then
    raise exception 'V1_WORKFORCE_REQUEST_ACCESS_DENIED' using errcode = '42501';
  end if;
  v_officer := v_role in ('admin', 'pr')
    and public.v1_wf_allowed('workforce.workers.manage');
  return jsonb_build_object(
    'schema_version', 'yorks.workforce.crew_request_options.v1',
    'today', public.v1_wf_today(),
    'workshop', public.v1_wf_can_request(null),
    'projects', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', project.id, 'name', project.name, 'ref', project.project_ref,
        'approved_on_submit', public.v1_wf_can_decide(project.id)
      ) order by lower(project.name))
      from public.v1_projects project
      where project.state in ('draft', 'active', 'on_hold')
        and public.v1_wf_can_request(project.id)
    ), '[]'::jsonb),
    'trades', coalesce((
      select jsonb_agg(designation order by designation)
      from (
        select distinct btrim(worker.designation) as designation
        from public.v1_workforce_workers worker
        where worker.current_status = 'active'
          and btrim(coalesce(worker.designation, '')) <> ''
        limit 200
      ) trades
    ), '[]'::jsonb),
    'crews', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', team.id, 'name', team.team_name,
        'kind', profile.crew_kind, 'project_id', profile.project_id,
        'shift_start_minute', profile.shift_start_minute,
        'shift_finish_minute', profile.shift_finish_minute,
        'break_start_minute', profile.break_start_minute,
        'break_finish_minute', profile.break_finish_minute
      ) order by lower(team.team_name))
      from public.v1_workforce_crew_profiles profile
      join public.v1_workforce_teams team on team.id = profile.team_id
      where profile.is_active and team.is_active
        and coalesce(
          (public.v1_wf_crew_access(team.id) ->> 'view')::boolean, false
        )
    ), '[]'::jsonb),
    'workers', case when v_officer then coalesce((
      select jsonb_agg(public.v1_wf_worker_json(worker.id)
        order by lower(worker.full_name))
      from public.v1_workforce_workers worker
      where worker.current_status = 'active'
    ), '[]'::jsonb) else '[]'::jsonb end
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Commands.
-- ---------------------------------------------------------------------------

-- Raise a request, or resubmit a returned one (request_id + version).
create or replace function public.v1_wf_submit_request(
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
  v_request public.v1_workforce_crew_requests%rowtype;
  v_request_id uuid;
  v_project uuid;
  v_kind text := coalesce(p_payload ->> 'crew_kind', 'project');
  v_label text := nullif(btrim(coalesce(p_payload ->> 'work_label', '')), '');
  v_notes text := nullif(btrim(coalesce(p_payload ->> 'notes', '')), '');
  v_target uuid;
  v_from date;
  v_until date;
  v_lines jsonb := coalesce(p_payload -> 'lines', '[]'::jsonb);
  v_line jsonb;
  v_index integer := 0;
  v_trade text;
  v_quantity integer;
  v_note text;
  v_auto boolean;
  v_state text;
  v_year integer := extract(year from public.v1_wf_today())::integer;
  v_number integer;
  v_approver uuid;
  v_fulfiller uuid;
  v_resubmit boolean;
begin
  if v_actor is null or not public.v1_current_actor_is_active() then
    raise exception 'V1_ACTIVE_ACTOR_REQUIRED' using errcode = '42501';
  end if;
  perform public.v1_assert_object_keys(
    p_payload,
    array[
      'request_id', 'crew_kind', 'project_id', 'work_label',
      'target_crew_id', 'needed_from', 'needed_until', 'notes', 'lines'
    ],
    'submit_workforce_crew_request_payload'
  );
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_wf_submit_request', p_idempotency_key,
    jsonb_build_object('payload', p_payload, 'expected', p_expected_version)
  );
  if v_existing is not null then
    return public.v1_wf_request_json(
      (v_existing ->> 'request_id')::uuid, true
    );
  end if;

  begin
    v_request_id := nullif(p_payload ->> 'request_id', '')::uuid;
    v_project := nullif(p_payload ->> 'project_id', '')::uuid;
    v_target := nullif(p_payload ->> 'target_crew_id', '')::uuid;
    v_from := (p_payload ->> 'needed_from')::date;
    v_until := nullif(p_payload ->> 'needed_until', '')::date;
  exception when others then
    raise exception 'V1_WORKFORCE_REQUEST_INVALID' using errcode = '22023';
  end;
  if v_kind not in ('project', 'workshop')
    or (v_kind = 'project') <> (v_project is not null)
    or v_from is null or v_from < public.v1_wf_today()
    or (v_until is not null and v_until < v_from)
    or (v_label is not null and char_length(v_label) > 160)
    or (v_notes is not null and char_length(v_notes) > 1000)
    or jsonb_typeof(v_lines) <> 'array'
    or jsonb_array_length(v_lines) not between 1 and 50 then
    raise exception 'V1_WORKFORCE_REQUEST_INVALID' using errcode = '22023';
  end if;
  if v_project is not null and not exists (
    select 1 from public.v1_projects project where project.id = v_project
  ) then
    raise exception 'V1_WORKFORCE_REQUEST_INVALID' using errcode = '22023';
  end if;
  if v_target is not null and not exists (
    select 1 from public.v1_workforce_crew_profiles profile
    where profile.team_id = v_target and profile.is_active
      and profile.project_id is not distinct from v_project
      and profile.crew_kind = v_kind
  ) then
    raise exception 'V1_WORKFORCE_REQUEST_INVALID' using errcode = '22023';
  end if;
  if not public.v1_wf_can_request(v_project) then
    raise exception 'V1_WORKFORCE_REQUEST_ACCESS_DENIED' using errcode = '42501';
  end if;

  v_auto := public.v1_wf_can_decide(v_project);
  v_state := case when v_auto then 'approved' else 'submitted' end;
  v_resubmit := v_request_id is not null;

  if v_resubmit then
    perform public.v1_wf_assert_request(v_request_id, 'resubmit');
    select * into v_request
    from public.v1_workforce_crew_requests request
    where request.id = v_request_id
    for update;
    if coalesce(p_expected_version, -1) <> v_request.record_version then
      perform public.v1_raise_version_conflict(
        'V1_WORKFORCE_REQUEST_VERSION_CONFLICT'
      );
    end if;
    update public.v1_workforce_crew_request_lines
    set is_current = false
    where request_id = v_request_id and is_current;
    update public.v1_workforce_crew_requests
    set crew_kind = v_kind,
        project_id = v_project,
        work_label = v_label,
        target_team_id = v_target,
        needed_from = v_from,
        needed_until = v_until,
        notes = v_notes,
        state = v_state,
        submitted_at = clock_timestamp(),
        decided_by_auth_user_id = case when v_auto then v_actor end,
        decided_by_role = case when v_auto then v_role end,
        decided_at = case when v_auto then clock_timestamp() end,
        decision_reason = null,
        last_actor_auth_user_id = v_actor,
        last_actor_role = v_role,
        record_version = record_version + 1,
        updated_at = clock_timestamp()
    where id = v_request_id;
  else
    insert into public.v1_workforce_crew_request_counters (
      request_year, last_number
    ) values (v_year, 1)
    on conflict (request_year) do update
      set last_number = public.v1_workforce_crew_request_counters.last_number + 1
    returning last_number into v_number;
    insert into public.v1_workforce_crew_requests (
      request_number, crew_kind, project_id, work_label, target_team_id,
      needed_from, needed_until, notes, state, requested_by_auth_user_id,
      requested_by_role, decided_by_auth_user_id, decided_by_role,
      decided_at, last_actor_auth_user_id, last_actor_role
    ) values (
      'CRQ-' || v_year::text || '-' || lpad(v_number::text, 4, '0'),
      v_kind, v_project, v_label, v_target, v_from, v_until, v_notes,
      v_state, v_actor, v_role,
      case when v_auto then v_actor end,
      case when v_auto then v_role end,
      case when v_auto then clock_timestamp() end,
      v_actor, v_role
    )
    returning id into v_request_id;
  end if;

  for v_line in select value from jsonb_array_elements(v_lines) loop
    v_index := v_index + 1;
    if jsonb_typeof(v_line) <> 'object' then
      raise exception 'V1_WORKFORCE_REQUEST_INVALID' using errcode = '22023';
    end if;
    perform public.v1_assert_object_keys(
      v_line, array['trade', 'quantity', 'note'],
      'submit_workforce_crew_request_line'
    );
    v_trade := btrim(coalesce(v_line ->> 'trade', ''));
    v_note := nullif(btrim(coalesce(v_line ->> 'note', '')), '');
    begin
      v_quantity := (v_line ->> 'quantity')::integer;
    exception when others then
      raise exception 'V1_WORKFORCE_REQUEST_INVALID' using errcode = '22023';
    end;
    if v_trade = '' or char_length(v_trade) > 120
      or v_quantity is null or v_quantity not between 1 and 200
      or (v_note is not null and char_length(v_note) > 500) then
      raise exception 'V1_WORKFORCE_REQUEST_INVALID' using errcode = '22023';
    end if;
    insert into public.v1_workforce_crew_request_lines (
      request_id, line_number, trade, quantity, note
    ) values (v_request_id, v_index, v_trade, v_quantity, v_note);
  end loop;

  insert into public.v1_workforce_crew_request_events (
    request_id, event_type, actor_auth_user_id, actor_role, from_state,
    to_state
  ) values (
    v_request_id,
    case when v_resubmit then 'resubmitted' else 'submitted' end,
    v_actor, v_role,
    case when v_resubmit then 'returned' end, 'submitted'
  );
  if v_auto then
    insert into public.v1_workforce_crew_request_events (
      request_id, event_type, actor_auth_user_id, actor_role, from_state,
      to_state, detail
    ) values (
      v_request_id, 'approved', v_actor, v_role, 'submitted', 'approved',
      jsonb_build_object('approved_on_submit', true)
    );
    for v_fulfiller in select public.v1_wf_request_fulfillers() loop
      perform public.v1_wf_request_notify(
        v_fulfiller, 'workforce_crew_request_approved', v_request_id,
        v_project
      );
    end loop;
  else
    for v_approver in select public.v1_wf_request_approvers(v_project) loop
      perform public.v1_wf_request_notify(
        v_approver, 'workforce_crew_request_submitted', v_request_id,
        v_project
      );
    end loop;
  end if;

  perform public.v1_write_audit_event(
    case when v_resubmit then 'workforce_crew_request_resubmitted'
      else 'workforce_crew_request_submitted' end,
    'workforce_crew_request', v_request_id, v_project, null,
    jsonb_build_object('state', v_state, 'lines', jsonb_array_length(v_lines)),
    null, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_wf_submit_request', p_idempotency_key,
    jsonb_build_object('request_id', v_request_id)
  );
  return public.v1_wf_request_json(v_request_id, true);
end;
$$;

-- Approve, return (reason) or reject (reason) a submitted request.
create or replace function public.v1_wf_decide_request(
  p_request_id uuid,
  p_decision text,
  p_reason text,
  p_expected_version bigint,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
  v_role text := public.v1_current_exact_role();
  v_existing jsonb;
  v_request public.v1_workforce_crew_requests%rowtype;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_state text;
  v_recipient uuid;
begin
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_wf_decide_request', p_idempotency_key,
    jsonb_build_object(
      'request', p_request_id, 'decision', p_decision, 'reason', p_reason,
      'expected', p_expected_version
    )
  );
  if v_existing is not null then
    return public.v1_wf_request_json(p_request_id, true);
  end if;
  v_actor := public.v1_wf_assert_request(p_request_id, 'decide');
  if p_decision not in ('approve', 'return', 'reject')
    or (p_decision <> 'approve' and v_reason is null)
    or char_length(coalesce(v_reason, '')) > 1000 then
    raise exception 'V1_WORKFORCE_REQUEST_INVALID' using errcode = '22023';
  end if;
  select * into v_request
  from public.v1_workforce_crew_requests request
  where request.id = p_request_id
  for update;
  if coalesce(p_expected_version, -1) <> v_request.record_version
    or v_request.state <> 'submitted' then
    perform public.v1_raise_version_conflict(
      'V1_WORKFORCE_REQUEST_VERSION_CONFLICT'
    );
  end if;
  v_state := case p_decision
    when 'approve' then 'approved'
    when 'return' then 'returned'
    else 'rejected'
  end;
  update public.v1_workforce_crew_requests
  set state = v_state,
      decided_by_auth_user_id = v_actor,
      decided_by_role = v_role,
      decided_at = clock_timestamp(),
      decision_reason = v_reason,
      last_actor_auth_user_id = v_actor,
      last_actor_role = v_role,
      record_version = record_version + 1,
      updated_at = clock_timestamp()
  where id = p_request_id;
  insert into public.v1_workforce_crew_request_events (
    request_id, event_type, actor_auth_user_id, actor_role, from_state,
    to_state, reason
  ) values (
    p_request_id,
    case p_decision when 'approve' then 'approved'
      when 'return' then 'returned' else 'rejected' end,
    v_actor, v_role, 'submitted', v_state, v_reason
  );
  if p_decision = 'approve' then
    for v_recipient in select public.v1_wf_request_fulfillers() loop
      perform public.v1_wf_request_notify(
        v_recipient, 'workforce_crew_request_approved', p_request_id,
        v_request.project_id
      );
    end loop;
  elsif p_decision = 'return' then
    perform public.v1_wf_request_notify(
      v_request.requested_by_auth_user_id, 'workforce_crew_request_returned',
      p_request_id, v_request.project_id
    );
  else
    perform public.v1_wf_request_notify(
      v_request.requested_by_auth_user_id, 'workforce_crew_request_rejected',
      p_request_id, v_request.project_id
    );
  end if;
  perform public.v1_write_audit_event(
    'workforce_crew_request_' || v_state, 'workforce_crew_request',
    p_request_id, v_request.project_id,
    jsonb_build_object('state', 'submitted'),
    jsonb_build_object('state', v_state), v_reason, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_wf_decide_request', p_idempotency_key,
    jsonb_build_object('request_id', p_request_id)
  );
  return public.v1_wf_request_json(p_request_id, true);
end;
$$;

create or replace function public.v1_wf_cancel_request(
  p_request_id uuid,
  p_reason text,
  p_expected_version bigint,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
  v_role text := public.v1_current_exact_role();
  v_existing jsonb;
  v_request public.v1_workforce_crew_requests%rowtype;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_wf_cancel_request', p_idempotency_key,
    jsonb_build_object(
      'request', p_request_id, 'reason', p_reason,
      'expected', p_expected_version
    )
  );
  if v_existing is not null then
    return public.v1_wf_request_json(p_request_id, true);
  end if;
  v_actor := public.v1_wf_assert_request(p_request_id, 'cancel');
  if char_length(coalesce(v_reason, '')) > 1000 then
    raise exception 'V1_WORKFORCE_REQUEST_INVALID' using errcode = '22023';
  end if;
  select * into v_request
  from public.v1_workforce_crew_requests request
  where request.id = p_request_id
  for update;
  if coalesce(p_expected_version, -1) <> v_request.record_version
    or v_request.state not in ('submitted', 'returned', 'approved')
    or exists (
      select 1 from public.v1_workforce_crew_request_assignments assignment
      where assignment.request_id = p_request_id
    ) then
    perform public.v1_raise_version_conflict(
      'V1_WORKFORCE_REQUEST_VERSION_CONFLICT'
    );
  end if;
  update public.v1_workforce_crew_requests
  set state = 'cancelled',
      last_actor_auth_user_id = v_actor,
      last_actor_role = v_role,
      record_version = record_version + 1,
      updated_at = clock_timestamp()
  where id = p_request_id;
  insert into public.v1_workforce_crew_request_events (
    request_id, event_type, actor_auth_user_id, actor_role, from_state,
    to_state, reason
  ) values (
    p_request_id, 'cancelled', v_actor, v_role, v_request.state,
    'cancelled', v_reason
  );
  perform public.v1_write_audit_event(
    'workforce_crew_request_cancelled', 'workforce_crew_request',
    p_request_id, v_request.project_id,
    jsonb_build_object('state', v_request.state),
    jsonb_build_object('state', 'cancelled'), v_reason, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_wf_cancel_request', p_idempotency_key,
    jsonb_build_object('request_id', p_request_id)
  );
  return public.v1_wf_request_json(p_request_id, true);
end;
$$;

-- PR assigns workers. Atomic: an optional new crew, the line decisions and
-- every crew membership, or nothing.
--
-- p_payload: {
--   crew_id | new_crew {name, shift_start_minute, shift_finish_minute,
--                       break_start_minute, break_finish_minute,
--                       needs_confirmation},
--   lines: [{line_id, worker_ids[], decision?, reason?}]
-- }
-- decision is 'partial' or 'cannot_provide' (reason required) for a line
-- still short after this assignment; a line that reaches its quantity is
-- 'full'.
create or replace function public.v1_wf_fulfil_request(
  p_request_id uuid,
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
  v_actor uuid;
  v_role text := public.v1_current_exact_role();
  v_existing jsonb;
  v_request public.v1_workforce_crew_requests%rowtype;
  v_team uuid;
  v_new_crew jsonb := p_payload -> 'new_crew';
  v_lines jsonb := coalesce(p_payload -> 'lines', '[]'::jsonb);
  v_entry jsonb;
  v_line public.v1_workforce_crew_request_lines%rowtype;
  v_worker uuid;
  v_member uuid;
  v_assigned integer;
  v_added integer := 0;
  v_decision text;
  v_reason text;
  v_total_requested integer;
  v_total_assigned integer;
  v_state text;
  v_crew jsonb;
  v_recipient uuid;
  v_any_workers boolean;
begin
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_wf_fulfil_request', p_idempotency_key,
    jsonb_build_object(
      'request', p_request_id, 'payload', p_payload,
      'expected', p_expected_version
    )
  );
  if v_existing is not null then
    return public.v1_wf_request_json(p_request_id, true);
  end if;
  v_actor := public.v1_wf_assert_request(p_request_id, 'fulfil');
  perform public.v1_assert_object_keys(
    p_payload, array['crew_id', 'new_crew', 'lines'],
    'fulfil_workforce_crew_request_payload'
  );
  if jsonb_typeof(v_lines) <> 'array'
    or jsonb_array_length(v_lines) not between 1 and 50 then
    raise exception 'V1_WORKFORCE_REQUEST_INVALID' using errcode = '22023';
  end if;
  select * into v_request
  from public.v1_workforce_crew_requests request
  where request.id = p_request_id
  for update;
  if coalesce(p_expected_version, -1) <> v_request.record_version
    or v_request.state not in ('approved', 'partially_fulfilled') then
    perform public.v1_raise_version_conflict(
      'V1_WORKFORCE_REQUEST_VERSION_CONFLICT'
    );
  end if;

  v_any_workers := exists (
    select 1 from jsonb_array_elements(v_lines) entry
    where jsonb_typeof(entry -> 'worker_ids') = 'array'
      and jsonb_array_length(entry -> 'worker_ids') > 0
  );

  -- The crew the workers join.
  if v_any_workers then
    if (nullif(p_payload ->> 'crew_id', '') is null) = (v_new_crew is null) then
      raise exception 'V1_WORKFORCE_REQUEST_INVALID' using errcode = '22023';
    end if;
    if v_new_crew is not null then
      if jsonb_typeof(v_new_crew) <> 'object' then
        raise exception 'V1_WORKFORCE_REQUEST_INVALID' using errcode = '22023';
      end if;
      v_crew := public.v1_wf_save_crew(
        jsonb_build_object(
          'name', v_new_crew ->> 'name',
          'kind', v_request.crew_kind,
          'project_id', v_request.project_id,
          'work_label', v_request.work_label,
          'needs_confirmation', coalesce(
            (v_new_crew ->> 'needs_confirmation')::boolean,
            v_request.crew_kind = 'project'
          ),
          'shift_start_minute', v_new_crew -> 'shift_start_minute',
          'shift_finish_minute', v_new_crew -> 'shift_finish_minute',
          'break_start_minute', v_new_crew -> 'break_start_minute',
          'break_finish_minute', v_new_crew -> 'break_finish_minute'
        ),
        null,
        md5(p_idempotency_key::text || ':crew')::uuid
      );
      v_team := (v_crew ->> 'id')::uuid;
    else
      begin
        v_team := (p_payload ->> 'crew_id')::uuid;
      exception when others then
        raise exception 'V1_WORKFORCE_REQUEST_INVALID' using errcode = '22023';
      end;
      if not exists (
        select 1 from public.v1_workforce_crew_profiles profile
        join public.v1_workforce_teams team on team.id = profile.team_id
        where profile.team_id = v_team and profile.is_active
          and team.is_active
          and profile.crew_kind = v_request.crew_kind
          and profile.project_id is not distinct from v_request.project_id
      ) then
        raise exception 'V1_WORKFORCE_REQUEST_CREW_MISMATCH'
          using errcode = '22023';
      end if;
      perform public.v1_wf_assert_crew(v_team, 'take');
    end if;
  end if;

  for v_entry in select value from jsonb_array_elements(v_lines) loop
    if jsonb_typeof(v_entry) <> 'object' then
      raise exception 'V1_WORKFORCE_REQUEST_INVALID' using errcode = '22023';
    end if;
    perform public.v1_assert_object_keys(
      v_entry, array['line_id', 'worker_ids', 'decision', 'reason'],
      'fulfil_workforce_crew_request_line'
    );
    select * into v_line
    from public.v1_workforce_crew_request_lines line
    where line.id = nullif(v_entry ->> 'line_id', '')::uuid
      and line.request_id = p_request_id
      and line.is_current
    for update;
    if not found then
      raise exception 'V1_WORKFORCE_REQUEST_INVALID' using errcode = '22023';
    end if;

    for v_worker in
      select value::uuid
      from jsonb_array_elements_text(
        coalesce(v_entry -> 'worker_ids', '[]'::jsonb)
      )
    loop
      if not exists (
        select 1 from public.v1_workforce_workers worker
        where worker.id = v_worker and worker.current_status = 'active'
      ) then
        raise exception 'V1_WORKFORCE_WORKER_NOT_ACTIVE' using errcode = '22023';
      end if;
      if exists (
        select 1 from public.v1_workforce_crew_members member
        where member.worker_id = v_worker and member.removed_at is null
      ) then
        raise exception 'V1_WORKFORCE_WORKER_ON_CREW' using errcode = '23505';
      end if;
      begin
        insert into public.v1_workforce_crew_members (
          team_id, worker_id, added_by_auth_user_id
        ) values (v_team, v_worker, v_actor)
        returning id into v_member;
        insert into public.v1_workforce_crew_request_assignments (
          request_id, line_id, worker_id, team_id, crew_member_id,
          assigned_by_auth_user_id
        ) values (
          p_request_id, v_line.id, v_worker, v_team, v_member, v_actor
        );
      exception when unique_violation then
        raise exception 'V1_WORKFORCE_WORKER_ON_CREW' using errcode = '23505';
      end;
      v_added := v_added + 1;
    end loop;

    select count(*)::integer into v_assigned
    from public.v1_workforce_crew_request_assignments assignment
    where assignment.line_id = v_line.id;
    if v_assigned > v_line.quantity then
      raise exception 'V1_WORKFORCE_REQUEST_OVER_ASSIGNED'
        using errcode = '22023';
    end if;
    v_decision := nullif(v_entry ->> 'decision', '');
    v_reason := nullif(btrim(coalesce(v_entry ->> 'reason', '')), '');
    if v_assigned = v_line.quantity then
      v_decision := 'full';
      v_reason := null;
    elsif v_decision is not null then
      if v_decision not in ('partial', 'cannot_provide')
        or v_reason is null or char_length(v_reason) > 500
        or (v_decision = 'partial' and v_assigned = 0)
        or (v_decision = 'cannot_provide' and v_assigned > 0) then
        raise exception 'V1_WORKFORCE_REQUEST_INVALID' using errcode = '22023';
      end if;
    elsif v_line.decision_reason is not null then
      -- Still short: the reason given earlier stands.
      v_decision := case when v_assigned > 0 then 'partial'
        else 'cannot_provide' end;
      v_reason := v_line.decision_reason;
    elsif v_assigned > 0 then
      -- A short line needs its reason recorded.
      raise exception 'V1_WORKFORCE_REQUEST_REASON_REQUIRED'
        using errcode = '22023';
    end if;
    if v_decision is not null then
      update public.v1_workforce_crew_request_lines
      set decision = v_decision, decision_reason = v_reason
      where id = v_line.id;
    end if;
  end loop;

  select coalesce(sum(line.quantity), 0)::integer into v_total_requested
  from public.v1_workforce_crew_request_lines line
  where line.request_id = p_request_id and line.is_current;
  select count(*)::integer into v_total_assigned
  from public.v1_workforce_crew_request_assignments assignment
  where assignment.request_id = p_request_id;
  v_state := case
    when v_total_assigned >= v_total_requested then 'fulfilled'
    when v_total_assigned > 0 then 'partially_fulfilled'
    else 'approved'
  end;

  update public.v1_workforce_crew_requests
  set state = v_state,
      target_team_id = coalesce(target_team_id, v_team),
      last_actor_auth_user_id = v_actor,
      last_actor_role = v_role,
      record_version = record_version + 1,
      updated_at = clock_timestamp()
  where id = p_request_id;
  insert into public.v1_workforce_crew_request_events (
    request_id, event_type, actor_auth_user_id, actor_role, from_state,
    to_state, detail
  ) values (
    p_request_id, 'workers_assigned', v_actor, v_role, v_request.state,
    v_state,
    jsonb_build_object(
      'added', v_added, 'crew_id', v_team,
      'crew_name', (select team_name from public.v1_workforce_teams
                    where id = v_team),
      'assigned', v_total_assigned, 'requested', v_total_requested
    )
  );
  if v_added > 0 then
    perform public.v1_wf_request_notify(
      v_request.requested_by_auth_user_id, 'workforce_crew_request_fulfilled',
      p_request_id, v_request.project_id
    );
    for v_recipient in
      select public.v1_wf_request_approvers(v_request.project_id)
    loop
      if v_recipient <> v_request.requested_by_auth_user_id then
        perform public.v1_wf_request_notify(
          v_recipient, 'workforce_crew_request_fulfilled', p_request_id,
          v_request.project_id
        );
      end if;
    end loop;
  end if;
  perform public.v1_write_audit_event(
    'workforce_crew_request_workers_assigned', 'workforce_crew_request',
    p_request_id, v_request.project_id,
    jsonb_build_object('state', v_request.state),
    jsonb_build_object(
      'state', v_state, 'added', v_added, 'crew_id', v_team
    ),
    null, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_wf_fulfil_request', p_idempotency_key,
    jsonb_build_object('request_id', p_request_id)
  );
  return public.v1_wf_request_json(p_request_id, true);
end;
$$;

-- Close what is left of an approved request (reason required).
create or replace function public.v1_wf_close_request(
  p_request_id uuid,
  p_reason text,
  p_expected_version bigint,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
  v_role text := public.v1_current_exact_role();
  v_existing jsonb;
  v_request public.v1_workforce_crew_requests%rowtype;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_wf_close_request', p_idempotency_key,
    jsonb_build_object(
      'request', p_request_id, 'reason', p_reason,
      'expected', p_expected_version
    )
  );
  if v_existing is not null then
    return public.v1_wf_request_json(p_request_id, true);
  end if;
  v_actor := public.v1_wf_assert_request(p_request_id, 'fulfil');
  if v_reason is null or char_length(v_reason) > 1000 then
    raise exception 'V1_WORKFORCE_REQUEST_INVALID' using errcode = '22023';
  end if;
  select * into v_request
  from public.v1_workforce_crew_requests request
  where request.id = p_request_id
  for update;
  if coalesce(p_expected_version, -1) <> v_request.record_version
    or v_request.state not in ('approved', 'partially_fulfilled') then
    perform public.v1_raise_version_conflict(
      'V1_WORKFORCE_REQUEST_VERSION_CONFLICT'
    );
  end if;
  update public.v1_workforce_crew_requests
  set state = 'closed',
      last_actor_auth_user_id = v_actor,
      last_actor_role = v_role,
      record_version = record_version + 1,
      updated_at = clock_timestamp()
  where id = p_request_id;
  insert into public.v1_workforce_crew_request_events (
    request_id, event_type, actor_auth_user_id, actor_role, from_state,
    to_state, reason
  ) values (
    p_request_id, 'closed', v_actor, v_role, v_request.state, 'closed',
    v_reason
  );
  perform public.v1_wf_request_notify(
    v_request.requested_by_auth_user_id, 'workforce_crew_request_fulfilled',
    p_request_id, v_request.project_id
  );
  perform public.v1_write_audit_event(
    'workforce_crew_request_closed', 'workforce_crew_request',
    p_request_id, v_request.project_id,
    jsonb_build_object('state', v_request.state),
    jsonb_build_object('state', 'closed'), v_reason, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_wf_close_request', p_idempotency_key,
    jsonb_build_object('request_id', p_request_id)
  );
  return public.v1_wf_request_json(p_request_id, true);
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Daily overdue summary: one notification per person per day.
-- ---------------------------------------------------------------------------

create or replace function public.v1_wf_send_crew_request_reminders()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := public.v1_wf_today();
  v_waiting integer;
  v_recipient uuid;
  v_digest uuid;
  v_count integer := 0;
begin
  select count(*)::integer into v_waiting
  from public.v1_workforce_crew_requests request
  where request.state in ('approved', 'partially_fulfilled')
    and request.needed_from <= v_today;
  if v_waiting = 0 then
    return 0;
  end if;
  for v_recipient in select public.v1_wf_request_fulfillers() loop
    v_digest := null;
    insert into public.v1_workforce_crew_request_digests (
      recipient_auth_user_id, sent_on, request_count
    ) values (v_recipient, v_today, v_waiting)
    on conflict (recipient_auth_user_id, sent_on) do nothing
    returning id into v_digest;
    if v_digest is null then
      continue;
    end if;
    insert into public.v1_notifications (
      id, recipient_auth_user_id, event_code, entity_type, entity_id,
      project_id
    ) values (
      gen_random_uuid(), v_recipient, 'workforce_crew_request_overdue',
      'workforce_crew_request_digest', v_digest, null
    );
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Notification link, label and delivery.
-- ---------------------------------------------------------------------------

do $wrap$
begin
  if to_regprocedure(
    'public.v1_notification_module_route_before_crew_requests(public.v1_notifications)'
  ) is null then
    alter function public.v1_notification_module_route(public.v1_notifications)
      rename to v1_notification_module_route_before_crew_requests;
    alter function public.v1_notification_record_label(public.v1_notifications)
      rename to v1_notification_record_label_before_crew_requests;
    alter function public.v1_push_notification_entity_allowed(public.v1_notifications)
      rename to v1_push_notification_entity_allowed_before_crew_requests;
  end if;
end;
$wrap$;

create or replace function public.v1_wf_notification_is_crew_request(
  n public.v1_notifications
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select n.event_code like 'workforce_crew_request_%'
    and n.entity_type in (
      'workforce_crew_request', 'workforce_crew_request_digest'
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
begin
  if public.v1_wf_notification_is_crew_request(n) then
    if n.entity_type = 'workforce_crew_request_digest' then
      return '/yorks/workforce?view=requests';
    end if;
    return '/yorks/workforce/requests/' || n.entity_id::text;
  end if;
  return public.v1_notification_module_route_before_crew_requests(n);
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
  if public.v1_wf_notification_is_crew_request(n) then
    if auth.uid() is distinct from n.recipient_auth_user_id then
      return null;
    end if;
    if n.entity_type = 'workforce_crew_request_digest' then
      select digest.request_count::text into v_label
      from public.v1_workforce_crew_request_digests digest
      where digest.id = n.entity_id
        and digest.recipient_auth_user_id = n.recipient_auth_user_id;
    else
      select request.request_number
        || coalesce(' · ' || project.project_ref, '')
      into v_label
      from public.v1_workforce_crew_requests request
      left join public.v1_projects project on project.id = request.project_id
      where request.id = n.entity_id;
    end if;
    return nullif(
      left(btrim(regexp_replace(v_label, '[[:cntrl:]]', ' ', 'g')), 180),
      ''
    );
  end if;
  return public.v1_notification_record_label_before_crew_requests(n);
end;
$$;

create or replace function public.v1_push_notification_entity_allowed(
  n public.v1_notifications
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if public.v1_wf_notification_is_crew_request(n) then
    return true;
  end if;
  return public.v1_push_notification_entity_allowed_before_crew_requests(n);
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Grants and schedule.
-- ---------------------------------------------------------------------------

do $grants$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'v1_wf_project_standing(uuid)',
    'v1_wf_can_request(uuid)',
    'v1_wf_can_decide(uuid)',
    'v1_wf_request_access(uuid)',
    'v1_wf_assert_request(uuid,text)',
    'v1_wf_request_notify(uuid,text,uuid,uuid)',
    'v1_wf_request_approvers(uuid)',
    'v1_wf_request_fulfillers()',
    'v1_wf_request_json(uuid,boolean)',
    'v1_wf_send_crew_request_reminders()',
    'v1_wf_notification_is_crew_request(public.v1_notifications)',
    'v1_notification_module_route(public.v1_notifications)',
    'v1_notification_record_label(public.v1_notifications)',
    'v1_push_notification_entity_allowed(public.v1_notifications)',
    'v1_notification_module_route_before_crew_requests(public.v1_notifications)',
    'v1_notification_record_label_before_crew_requests(public.v1_notifications)',
    'v1_push_notification_entity_allowed_before_crew_requests(public.v1_notifications)'
  ] loop
    execute format(
      'revoke all on function public.%s from public, anon, authenticated, service_role',
      v_signature
    );
  end loop;
  foreach v_signature in array array[
    'v1_wf_list_requests()',
    'v1_wf_get_request(uuid)',
    'v1_wf_request_options()',
    'v1_wf_submit_request(jsonb,bigint,uuid)',
    'v1_wf_decide_request(uuid,text,text,bigint,uuid)',
    'v1_wf_cancel_request(uuid,text,bigint,uuid)',
    'v1_wf_fulfil_request(uuid,jsonb,bigint,uuid)',
    'v1_wf_close_request(uuid,text,bigint,uuid)'
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

-- Daily at 04:10 UTC (08:10 in Dubai). A named schedule is idempotent.
do $schedule$
begin
  perform cron.schedule(
    'yorks-workforce-crew-request-reminders', '10 4 * * *',
    'select public.v1_wf_send_crew_request_reminders();'
  );
end;
$schedule$;

notify pgrst, 'reload schema';

commit;
