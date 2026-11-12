-- PR reads every project (PRODUCT_DECISIONS.md section 37), fixed.
--
-- 20261112120000 widened the role lists that already named Accountant. The
-- project read path keeps its own list of organization-wide readers (Admin and
-- the four global engineering roles) without Accountant, so PR was left out:
-- the project register, its BOQ, documents and team came back empty for PR.
-- This adds PR to exactly those read lists:
--
--   v1_project_readable                               project RLS and reads
--   v1_permission_actor_has_unrestricted_project_authority
--   v1_get_current_permission_snapshot                "all projects" in the app
--   v1_permission_workspace_json                      same, in User Access
--   v1_user_project_access_basis                      "All projects" label
--
-- Write and approval rules, project chat membership and engineering
-- notification fan-out are deliberately unchanged: PR stays read-only on
-- projects (its capability boundary already refuses every mutation key).
--
-- Data preservation: function-body rewrites only; no row changes.
-- Rollback: re-apply the previous definitions; nothing to undo in data.

begin;

do $pr_read$
declare
  v_function regprocedure;
  v_definition text;
  v_updated text;
begin
  foreach v_function in array array[
    'public.v1_project_readable(uuid)'::regprocedure,
    'public.v1_permission_actor_has_unrestricted_project_authority()'::regprocedure,
    'public.v1_get_current_permission_snapshot()'::regprocedure,
    'public.v1_user_project_access_basis(text)'::regprocedure
  ] loop
    v_definition := pg_get_functiondef(v_function);
    if position('''document_controller'', ''pr''' in v_definition) > 0 then
      continue;
    end if;
    v_updated := replace(
      v_definition,
      '''workshop_in_charge'', ''document_controller''',
      '''workshop_in_charge'', ''document_controller'', ''pr'''
    );
    if v_updated = v_definition then
      raise exception 'V1_PR_READ_ANCHOR_MISSING: %', v_function;
    end if;
    execute v_updated;
  end loop;

  -- The User Access workspace takes arguments; rewrite every overload.
  for v_function in
    select p.oid::regprocedure
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'v1_permission_workspace_json'
  loop
    v_definition := pg_get_functiondef(v_function);
    if position('''document_controller'', ''pr''' in v_definition) > 0 then
      continue;
    end if;
    v_updated := replace(
      v_definition,
      '''workshop_in_charge'', ''document_controller''',
      '''workshop_in_charge'', ''document_controller'', ''pr'''
    );
    if v_updated = v_definition then
      raise exception 'V1_PR_READ_ANCHOR_MISSING: %', v_function;
    end if;
    execute v_updated;
  end loop;
end;
$pr_read$;

notify pgrst, 'reload schema';

commit;
