-- Crew requests: release workers one by one (owner, 13 November 2026;
-- PRODUCT_DECISIONS section 41).
--
--   * While workers are on site, the requester or an assigner (the people
--     who may finish the request) may release one worker: that worker leaves
--     the crew and is free for other crews. Attendance already taken stays.
--   * Releasing the last worker still on site of a fully assigned request
--     finishes it.
--   * Each assigned worker shows when they left the crew, however they left
--     (released here, finished, moved by another request, or a crew edit).
--
-- Data preservation: additive. The 'worker_released' event, a released time
-- in the request view and a new function. No row is changed. Rollback:
-- re-apply v1_wf_request_json from 20261114090000 and revoke
-- v1_wf_release_request_worker; the event type may stay.

begin;

alter table public.v1_workforce_crew_request_events
  drop constraint if exists v1_workforce_crew_request_events_event_type_check;
alter table public.v1_workforce_crew_request_events
  add constraint v1_workforce_crew_request_events_event_type_check
  check (event_type in (
    'submitted', 'resubmitted', 'approved', 'returned', 'rejected',
    'cancelled', 'workers_assigned', 'closed', 'completed', 'worker_released'
  ));

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
            'assigned_at', assignment.assigned_at,
            -- Left the crew: released one by one, finished, or moved.
            'released_at', member.removed_at
          ) order by assignment.assigned_at, lower(worker.full_name))
          from public.v1_workforce_crew_request_assignments assignment
          join public.v1_workforce_workers worker
            on worker.id = assignment.worker_id
          join public.v1_workforce_teams team on team.id = assignment.team_id
          join public.v1_workforce_crew_members member
            on member.id = assignment.crew_member_id
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

-- One worker is no longer needed: they leave the crew. The last one out of
-- a fully assigned request finishes it.
create or replace function public.v1_wf_release_request_worker(
  p_request_id uuid,
  p_worker_id uuid,
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
  v_member uuid;
  v_team uuid;
  v_remaining integer;
  v_state text;
begin
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_wf_release_request_worker', p_idempotency_key,
    jsonb_build_object(
      'request', p_request_id, 'worker', p_worker_id, 'reason', p_reason,
      'expected', p_expected_version
    )
  );
  if v_existing is not null then
    return public.v1_wf_request_json(p_request_id, true);
  end if;
  v_actor := public.v1_wf_assert_request(p_request_id, 'finish');
  if p_worker_id is null or char_length(coalesce(v_reason, '')) > 1000 then
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
  select member.id, member.team_id into v_member, v_team
  from public.v1_workforce_crew_request_assignments assignment
  join public.v1_workforce_crew_members member
    on member.id = assignment.crew_member_id
  where assignment.request_id = p_request_id
    and assignment.worker_id = p_worker_id
    and member.removed_at is null
  for update of member;
  if v_member is null then
    -- Not on this request, or already gone from the crew.
    raise exception 'V1_WORKFORCE_REQUEST_WORKER_NOT_ON_SITE'
      using errcode = '22023';
  end if;
  update public.v1_workforce_crew_members
  set removed_at = clock_timestamp(), removed_by_auth_user_id = v_actor
  where id = v_member;

  select count(*)::integer into v_remaining
  from public.v1_workforce_crew_request_assignments assignment
  join public.v1_workforce_crew_members member
    on member.id = assignment.crew_member_id
  where assignment.request_id = p_request_id
    and member.removed_at is null;
  v_state := case
    when v_request.state = 'fulfilled' and v_remaining = 0 then 'completed'
    else v_request.state
  end;

  update public.v1_workforce_crew_requests
  set state = v_state,
      last_actor_auth_user_id = v_actor,
      last_actor_role = v_role,
      record_version = record_version + 1,
      updated_at = clock_timestamp()
  where id = p_request_id;
  insert into public.v1_workforce_crew_request_events (
    request_id, event_type, actor_auth_user_id, actor_role, from_state,
    to_state, reason, detail
  ) values (
    p_request_id, 'worker_released', v_actor, v_role, v_request.state,
    v_state, v_reason,
    jsonb_build_object(
      'worker_id', p_worker_id,
      'worker_name', (select full_name from public.v1_workforce_workers
                      where id = p_worker_id),
      'crew_id', v_team,
      'crew_name', (select team_name from public.v1_workforce_teams
                    where id = v_team),
      'remaining', v_remaining
    )
  );
  if v_state = 'completed' then
    insert into public.v1_workforce_crew_request_events (
      request_id, event_type, actor_auth_user_id, actor_role, from_state,
      to_state, detail
    ) values (
      p_request_id, 'completed', v_actor, v_role, v_request.state,
      'completed', jsonb_build_object('released', 1, 'last_worker', true)
    );
  end if;
  perform public.v1_write_audit_event(
    'workforce_crew_request_worker_released', 'workforce_crew_request',
    p_request_id, v_request.project_id,
    jsonb_build_object('state', v_request.state),
    jsonb_build_object(
      'state', v_state, 'worker_id', p_worker_id, 'crew_id', v_team,
      'remaining', v_remaining
    ),
    v_reason, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_wf_release_request_worker', p_idempotency_key,
    jsonb_build_object('request_id', p_request_id)
  );
  return public.v1_wf_request_json(p_request_id, true);
end;
$$;

revoke all on function public.v1_wf_request_json(uuid, boolean)
  from public, anon, authenticated, service_role;
revoke all on function
  public.v1_wf_release_request_worker(uuid, uuid, text, bigint, uuid)
  from public, anon;
grant execute on function
  public.v1_wf_release_request_worker(uuid, uuid, text, bigint, uuid)
  to authenticated;

notify pgrst, 'reload schema';

commit;
