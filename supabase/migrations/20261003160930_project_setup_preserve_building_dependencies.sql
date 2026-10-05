-- Project setup cannot yet preview every operational/commercial dependency of
-- retiring a physical scope. Fail closed for omitted persisted scopes until a
-- controlled reconciliation command is accepted. Renames/reorders/additions
-- retain their existing supported behavior; no rows or history are deleted.
-- Rollback: restore the previous function body in a forward migration only
-- after the supported dependency resolver has passed its release gate.
do $migration$
declare
  v_definition text;
  v_anchor text := E'  -- Project setup is mutable, but its complete prior and resulting shape must\n';
  v_guard text := $guard$
  -- V1_PROJECT_SETUP_SCOPE_RETIREMENT_GUARD: preserve active scope identity.
  -- This is deliberately conservative: setup has no accepted reconciliation
  -- path for MR/BOQ/documents or physical-building Accounts allocations.
  if exists (
    select 1
    from public.v1_project_scopes scope
    where scope.project_id = v_project_id
      and scope.scope_kind = 'building'
      and scope.is_active
      and not exists (
        select 1 from jsonb_array_elements(v_buildings) submitted
        where nullif(btrim(coalesce(submitted ->> 'id', '')), '')::uuid = scope.id
      )
  ) then
    raise exception 'V1_PROJECT_BUILDING_RETIREMENT_REQUIRES_RECONCILIATION'
      using errcode = '55000';
  end if;

$guard$;
begin
  select pg_catalog.pg_get_functiondef(
    'public.v1_update_project(jsonb,uuid)'::regprocedure
  ) into v_definition;
  if position('V1_PROJECT_SETUP_SCOPE_RETIREMENT_GUARD' in v_definition) > 0 then
    return;
  end if;
  if position(v_anchor in v_definition) = 0 then
    raise exception 'V1_PROJECT_SETUP_UPDATE_GUARD_ANCHOR_MISSING';
  end if;
  execute replace(v_definition, v_anchor, v_guard || v_anchor);
end;
$migration$;
