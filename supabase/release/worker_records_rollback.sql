-- Worker Records rollback: restore the R39 Accountant rule and withdraw
-- the capabilities from use. Keeps every record, revision and photo.
begin;
do $rollback$
declare v_target record; v_def text;
begin
  for v_target in select * from (values
    ('public.v1_permission_candidate_raw(uuid,text,uuid)','not public.v1_accountant_may_hold_capability(p_capability_key)','not public.v1_accounts_is_capability_key(p_capability_key)'),
    ('public.v1_permission_legacy_raw(uuid,text,uuid)','not public.v1_accountant_may_hold_capability(p_capability_key)','not public.v1_accounts_is_capability_key(p_capability_key)'),
    ('public.v1_permission_guard_assignment()','not public.v1_accountant_may_hold_capability(new.capability_key)','not public.v1_accounts_is_capability_key(new.capability_key)')
  ) t(signature, new_text, old_text) loop
    v_def := pg_get_functiondef(v_target.signature::regprocedure);
    if position(v_target.new_text in v_def) > 0 then
      execute replace(v_def, v_target.new_text, v_target.old_text);
    end if;
  end loop;
end;
$rollback$;
update public.v1_capability_catalog set is_assignable = false, status = 'planned', authorization_mode = 'shadow'
  where capability_key in ('worker_records.view','worker_records.manage');
revoke execute on function public.v1_list_worker_records(text,text,text,integer,integer), public.v1_get_worker_record(uuid),
  public.v1_save_worker_record(jsonb,bigint,uuid), public.v1_set_worker_photo(uuid,text,bigint,uuid),
  public.v1_preview_worker_records_import(jsonb), public.v1_import_worker_records(jsonb,uuid) from authenticated;
commit;
