-- Additive assigned-team worker entry. No existing worker, assignment or role grant
-- is rewritten. Rollback: revoke the two public RPC grants and disable the UI;
-- preserve all created workers, assignments, command receipts and audit events.
begin;
create or replace function public.v1_workforce_can_add_team_worker(p_team_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
 select public.v1_current_actor_is_active()
 and public.v1_permission_exact_role(auth.uid()) <> ''
 and exists (
   select 1 from public.v1_workforce_teams t
   where t.id = p_team_id and t.is_active
     and t.valid_from <= (now() at time zone 'Asia/Dubai')::date
     and (t.valid_to is null or t.valid_to >= (now() at time zone 'Asia/Dubai')::date)
     and public.v1_current_user_has_capability('workforce.view', t.default_project_id)
     and public.v1_current_user_has_capability('workforce.attendance.maintain', t.default_project_id)
     and (public.v1_permission_exact_role(auth.uid()) = 'admin'
       or t.default_supervisor_auth_user_id = auth.uid()
       or exists (
         select 1 from public.v1_workforce_responsibility_assignments r
         where r.auth_user_id = auth.uid() and r.scope_kind = 'team'
           and r.team_id = t.id
           and r.valid_from <= (now() at time zone 'Asia/Dubai')::date
           and (r.valid_to is null or r.valid_to >= (now() at time zone 'Asia/Dubai')::date)
       ))
 );
$$;
revoke all on function public.v1_workforce_can_add_team_worker(uuid) from public, anon, authenticated;

create or replace function public.v1_get_workforce_team_workers(p_team_id uuid default null, p_offset integer default 0)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_actor uuid := auth.uid(); v_teams jsonb; v_rows jsonb;
begin
 if v_actor is null or not public.v1_current_actor_is_active() then
   raise exception 'V1_WORKFORCE_TEAM_WORKER_DENIED' using errcode='42501'; end if;
 perform public.v1_sync_profile_from_auth(v_actor);
 if p_offset is null or p_offset < 0 then raise exception 'V1_WORKFORCE_INPUT_INVALID' using errcode='22023'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'name',t.team_name) order by t.team_name),'[]'::jsonb)
 into v_teams from public.v1_workforce_teams t where public.v1_workforce_can_add_team_worker(t.id);
 if p_team_id is not null and not public.v1_workforce_can_add_team_worker(p_team_id) then
   raise exception 'V1_WORKFORCE_TEAM_WORKER_DENIED' using errcode='42501'; end if;
 select coalesce(jsonb_agg(row_data order by full_name, id),'[]'::jsonb) into v_rows from (
 select w.id,w.full_name,jsonb_build_object('id',w.id,'name',w.full_name,'number',w.worker_number,'designation',w.designation) row_data
 from public.v1_workforce_workers w
 where p_team_id is not null and exists (
   select 1 from public.v1_workforce_worker_assignments a
   where a.worker_id=w.id and a.team_id=p_team_id
     and a.valid_from <= (now() at time zone 'Asia/Dubai')::date
     and (a.valid_to is null or a.valid_to >= (now() at time zone 'Asia/Dubai')::date))
 order by w.full_name,w.id limit 50 offset p_offset
 ) x;
 return jsonb_build_object('teams',v_teams,'workers',v_rows,'offset',p_offset);
end; $$;

create or replace function public.v1_create_workforce_team_worker(p_team_id uuid, p_payload jsonb, p_idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
 v_actor uuid:=auth.uid(); v_existing jsonb; v_worker uuid:=gen_random_uuid();
 v_assignment uuid:=gen_random_uuid(); v_team public.v1_workforce_teams%rowtype;
 v_joining date; v_type text; v_today date:=(now() at time zone 'Asia/Dubai')::date; v_number text; v_result jsonb;
begin
 if v_actor is null then raise exception 'V1_WORKFORCE_TEAM_WORKER_DENIED' using errcode='42501'; end if;
 perform public.v1_sync_profile_from_auth(v_actor);
 select * into v_team from public.v1_workforce_teams where id=p_team_id for update;
 if not found or not public.v1_workforce_can_add_team_worker(p_team_id) then
   raise exception 'V1_WORKFORCE_TEAM_WORKER_DENIED' using errcode='42501'; end if;
 -- Lock matching responsibility rows against concurrent removal while committing.
 perform 1 from public.v1_workforce_responsibility_assignments
 where auth_user_id=v_actor and team_id=p_team_id for share;
 if not public.v1_workforce_can_add_team_worker(p_team_id) then
   raise exception 'V1_WORKFORCE_TEAM_WORKER_DENIED' using errcode='42501'; end if;
 perform public.v1_assert_object_keys(p_payload,array['full_name','worker_number','designation','employer_company','joining_date','worker_type'],'team_worker');
 if nullif(btrim(p_payload->>'full_name'),'') is null
 or nullif(btrim(p_payload->>'designation'),'') is null
 or nullif(btrim(p_payload->>'employer_company'),'') is null then
   raise exception 'V1_WORKFORCE_WORKER_REQUIRED_FIELDS' using errcode='22023'; end if;
 v_joining:=nullif(p_payload->>'joining_date','')::date;
 v_type:=p_payload->>'worker_type';
 if v_joining is null or v_joining > v_today or v_type is null or v_type not in ('yorks_employee','temporary_worker','subcontractor_worker','agency_worker') then
 raise exception 'V1_WORKFORCE_WORKER_REQUIRED_FIELDS' using errcode='22023'; end if;
 v_existing:=public.v1_idempotency_get_or_claim('v1_create_workforce_team_worker',p_idempotency_key,
 jsonb_build_object('team_id',p_team_id,'payload',p_payload));
 if v_existing is not null then return v_existing; end if;
 v_number:=coalesce(nullif(upper(btrim(p_payload->>'worker_number')),''),'WF-'||upper(replace(v_worker::text,'-','')));
 insert into public.v1_workforce_workers(id,worker_number,full_name,designation,employer_company,worker_type,
 joining_date,created_by_auth_user_id,updated_by_auth_user_id)
 values(v_worker,v_number,btrim(p_payload->>'full_name'),btrim(p_payload->>'designation'),btrim(p_payload->>'employer_company'),
 v_type,v_joining,v_actor,v_actor);
 insert into public.v1_workforce_worker_assignments(id,worker_id,assignment_kind,team_id,supervisor_auth_user_id,
 valid_from,valid_to,reason,assigned_by_auth_user_id,assigned_by_exact_role,updated_by_auth_user_id)
 values(v_assignment,v_worker,'primary',p_team_id,v_team.default_supervisor_auth_user_id,v_today,v_team.valid_to,
 'Worker added to assigned team',v_actor,public.v1_permission_exact_role(v_actor),v_actor);
 v_result:=jsonb_build_object('worker_id',v_worker,'worker_number',v_number,'team_id',p_team_id,'assignment_id',v_assignment);
 perform public.v1_write_audit_event('workforce_worker_created','workforce_worker',v_worker,null,null,v_result,
 'Worker added to assigned team',p_idempotency_key);
 perform public.v1_write_audit_event('workforce_assignment_created','workforce_assignment',v_assignment,null,null,v_result,
 'Worker added to assigned team',p_idempotency_key);
 perform public.v1_complete_idempotency('v1_create_workforce_team_worker',p_idempotency_key,v_result);
 return v_result;
end; $$;
revoke all on function public.v1_get_workforce_team_workers(uuid,integer) from public,anon;
revoke all on function public.v1_create_workforce_team_worker(uuid,jsonb,uuid) from public,anon;
grant execute on function public.v1_get_workforce_team_workers(uuid,integer) to authenticated;
grant execute on function public.v1_create_workforce_team_worker(uuid,jsonb,uuid) to authenticated;
commit;
