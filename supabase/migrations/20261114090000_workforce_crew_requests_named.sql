-- Crew requests: by name or designation, approve and assign in one step,
-- finish when the work is done (owner, 14 November 2026; PRODUCT_DECISIONS
-- section 40).
--
--   * A request line names a worker (one person) or a designation with how
--     many. A named worker already on another crew is shown with a warning
--     to the requester and the approver; if approved and assigned, that
--     worker moves to this request's crew.
--   * The project's approver (Project Engineer, organization-wide engineer,
--     Admin) may approve and assign in one step. Assigning later is open to
--     the same approvers and to PR.
--   * When the work is done the requester (or an assigner) finishes the
--     request: the workers it brought onto the crew leave it. Their
--     attendance stays.
--
-- Data preservation: additive. A nullable worker column on request lines,
-- the 'completed' state and event, and new function bodies. No row is
-- changed. Rollback: re-apply the definitions from 20261113150000 and revoke
-- v1_wf_finish_request; the column and states may stay.

begin;

alter table public.v1_workforce_crew_request_lines
  add column if not exists worker_id uuid
    references public.v1_workforce_workers (id) on delete restrict;
alter table public.v1_workforce_crew_request_lines
  drop constraint if exists v1_workforce_crew_request_lines_named_check;
alter table public.v1_workforce_crew_request_lines
  add constraint v1_workforce_crew_request_lines_named_check
  check (worker_id is null or quantity = 1);

alter table public.v1_workforce_crew_requests
  drop constraint if exists v1_workforce_crew_requests_state_check;
alter table public.v1_workforce_crew_requests
  add constraint v1_workforce_crew_requests_state_check
  check (state in (
    'submitted', 'returned', 'approved', 'partially_fulfilled',
    'fulfilled', 'completed', 'closed', 'rejected', 'cancelled'
  ));

alter table public.v1_workforce_crew_request_events
  drop constraint if exists v1_workforce_crew_request_events_event_type_check;
alter table public.v1_workforce_crew_request_events
  add constraint v1_workforce_crew_request_events_event_type_check
  check (event_type in (
    'submitted', 'resubmitted', 'approved', 'returned', 'rejected',
    'cancelled', 'workers_assigned', 'closed', 'completed'
  ));

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
    'resubmit', false, 'finish', false
  );
  v_assigner boolean;
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
  -- Assigners: the project's approvers and PR (Admin is both).
  v_assigner := (
      (v_role in ('admin', 'pr')
        and public.v1_wf_allowed('workforce.workers.manage'))
      or public.v1_wf_can_decide(v_request.project_id)
    );
  return jsonb_build_object(
    'view', true,
    'decide', v_request.state = 'submitted'
      and not v_mine
      and public.v1_wf_can_decide(v_request.project_id),
    'fulfil', v_request.state in ('approved', 'partially_fulfilled')
      and v_assigner,
    'cancel', v_request.state in ('submitted', 'returned', 'approved')
      and not v_assigned
      and (v_mine or v_role = 'admin'),
    'resubmit', v_request.state = 'returned' and v_mine,
    -- Work done: the requester, an assigner or Admin finishes the request
    -- and its workers leave the crew.
    'finish', v_request.state in ('partially_fulfilled', 'fulfilled')
      and (v_mine or v_assigner)
  );
end;
$$;

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
      when 'fulfilled' then 'requester'
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
        -- A worker asked for by name, with the crew they are on now.
        'worker', case when line.worker_id is not null then (
          select jsonb_build_object(
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
        ) end,
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
        'trade', line.trade, 'quantity', line.quantity,
        'worker_name', (
          select worker.full_name from public.v1_workforce_workers worker
          where worker.id = line.worker_id
        )
      ) order by line.line_number), '[]'::jsonb) as trades
    from public.v1_workforce_crew_request_lines line
    where line.request_id = request.id and line.is_current
  ) totals
  where request.id = p_request_id;
$$;

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
  -- Everyone who may raise or assign a request picks workers by name.
  v_officer := (v_role in ('admin', 'pr')
      and public.v1_wf_allowed('workforce.workers.manage'))
    or public.v1_wf_can_request(null)
    or exists (
      select 1 from public.v1_project_members member
      where member.member_auth_user_id = auth.uid()
        and member.effective_from <= clock_timestamp()
        and (member.effective_to is null
          or member.effective_to > clock_timestamp())
        and public.v1_wf_can_request(member.project_id)
    );
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
  v_worker uuid;
  v_designation text;
  v_named uuid[] := array[]::uuid[];
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
      v_line, array['trade', 'quantity', 'note', 'worker_id'],
      'submit_workforce_crew_request_line'
    );
    v_trade := btrim(coalesce(v_line ->> 'trade', ''));
    v_note := nullif(btrim(coalesce(v_line ->> 'note', '')), '');
    begin
      v_worker := nullif(v_line ->> 'worker_id', '')::uuid;
      v_quantity := coalesce((v_line ->> 'quantity')::integer, 1);
    exception when others then
      raise exception 'V1_WORKFORCE_REQUEST_INVALID' using errcode = '22023';
    end;
    -- A worker asked for by name: one person, their designation as the
    -- trade unless one was typed. The same person once per request.
    if v_worker is not null then
      select worker.designation into v_designation
      from public.v1_workforce_workers worker
      where worker.id = v_worker and worker.current_status = 'active';
      if not found then
        raise exception 'V1_WORKFORCE_WORKER_NOT_ACTIVE' using errcode = '22023';
      end if;
      if v_worker = any (v_named) then
        raise exception 'V1_WORKFORCE_REQUEST_INVALID' using errcode = '22023';
      end if;
      v_named := v_named || v_worker;
      v_quantity := 1;
      if v_trade = '' then
        v_trade := coalesce(nullif(btrim(v_designation), ''), 'Worker');
      end if;
    end if;
    if v_trade = '' or char_length(v_trade) > 120
      or v_quantity is null or v_quantity not between 1 and 200
      or (v_note is not null and char_length(v_note) > 500) then
      raise exception 'V1_WORKFORCE_REQUEST_INVALID' using errcode = '22023';
    end if;
    insert into public.v1_workforce_crew_request_lines (
      request_id, line_number, trade, quantity, note, worker_id
    ) values (v_request_id, v_index, v_trade, v_quantity, v_note, v_worker);
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
  v_approve boolean := coalesce((p_payload ->> 'approve')::boolean, false);
  v_approved_now boolean := false;
  v_previous_team uuid;
  v_moved jsonb := '[]'::jsonb;
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
  -- An approver may approve and assign in one step.
  v_actor := public.v1_wf_assert_request(
    p_request_id, case when v_approve then 'decide' else 'fulfil' end
  );
  perform public.v1_assert_object_keys(
    p_payload, array['crew_id', 'new_crew', 'lines', 'approve'],
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
    or (v_approve and v_request.state <> 'submitted')
    or (not v_approve
      and v_request.state not in ('approved', 'partially_fulfilled')) then
    perform public.v1_raise_version_conflict(
      'V1_WORKFORCE_REQUEST_VERSION_CONFLICT'
    );
  end if;
  if v_approve then
    update public.v1_workforce_crew_requests
    set state = 'approved',
        decided_by_auth_user_id = v_actor,
        decided_by_role = v_role,
        decided_at = clock_timestamp(),
        decision_reason = null
    where id = p_request_id;
    insert into public.v1_workforce_crew_request_events (
      request_id, event_type, actor_auth_user_id, actor_role, from_state,
      to_state, detail
    ) values (
      p_request_id, 'approved', v_actor, v_role, 'submitted', 'approved',
      jsonb_build_object('with_assignment', true)
    );
    v_request.state := 'approved';
    v_approved_now := true;
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
      v_previous_team := null;
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
      'assigned', v_total_assigned, 'requested', v_total_requested,
      'moved', v_moved
    )
  );
  -- Approved now but still short: PR is asked for the rest.
  if v_approved_now and v_state <> 'fulfilled' then
    for v_recipient in select public.v1_wf_request_fulfillers() loop
      perform public.v1_wf_request_notify(
        v_recipient, 'workforce_crew_request_approved', p_request_id,
        v_request.project_id
      );
    end loop;
  end if;
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

-- Work done: the request finishes and its workers leave the crew.
create or replace function public.v1_wf_finish_request(
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
  v_released integer;
begin
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_wf_finish_request', p_idempotency_key,
    jsonb_build_object(
      'request', p_request_id, 'reason', p_reason,
      'expected', p_expected_version
    )
  );
  if v_existing is not null then
    return public.v1_wf_request_json(p_request_id, true);
  end if;
  v_actor := public.v1_wf_assert_request(p_request_id, 'finish');
  if char_length(coalesce(v_reason, '')) > 1000 then
    raise exception 'V1_WORKFORCE_REQUEST_INVALID' using errcode = '22023';
  end if;
  select * into v_request
  from public.v1_workforce_crew_requests request
  where request.id = p_request_id
  for update;
  if coalesce(p_expected_version, -1) <> v_request.record_version
    or v_request.state not in ('partially_fulfilled', 'fulfilled') then
    perform public.v1_raise_version_conflict(
      'V1_WORKFORCE_REQUEST_VERSION_CONFLICT'
    );
  end if;
  update public.v1_workforce_crew_members member
  set removed_at = clock_timestamp(), removed_by_auth_user_id = v_actor
  from public.v1_workforce_crew_request_assignments assignment
  where assignment.request_id = p_request_id
    and member.id = assignment.crew_member_id
    and member.removed_at is null;
  get diagnostics v_released = row_count;
  update public.v1_workforce_crew_requests
  set state = 'completed',
      last_actor_auth_user_id = v_actor,
      last_actor_role = v_role,
      record_version = record_version + 1,
      updated_at = clock_timestamp()
  where id = p_request_id;
  insert into public.v1_workforce_crew_request_events (
    request_id, event_type, actor_auth_user_id, actor_role, from_state,
    to_state, reason, detail
  ) values (
    p_request_id, 'completed', v_actor, v_role, v_request.state, 'completed',
    v_reason, jsonb_build_object('released', v_released)
  );
  perform public.v1_write_audit_event(
    'workforce_crew_request_completed', 'workforce_crew_request',
    p_request_id, v_request.project_id,
    jsonb_build_object('state', v_request.state),
    jsonb_build_object('state', 'completed', 'released', v_released),
    v_reason, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_wf_finish_request', p_idempotency_key,
    jsonb_build_object('request_id', p_request_id)
  );
  return public.v1_wf_request_json(p_request_id, true);
end;
$$;

revoke all on function
  public.v1_wf_request_access(uuid),
  public.v1_wf_request_json(uuid, boolean)
  from public, anon, authenticated, service_role;
revoke all on function public.v1_wf_finish_request(uuid, text, bigint, uuid)
  from public, anon;
grant execute on function public.v1_wf_finish_request(uuid, text, bigint, uuid)
  to authenticated;

notify pgrst, 'reload schema';

commit;
