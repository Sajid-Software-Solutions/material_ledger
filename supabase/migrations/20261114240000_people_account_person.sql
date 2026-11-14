-- User Management shows and links the People record of an account
-- (PRODUCT_DECISIONS section 56; owner request, 14 November 2026).
--
-- User Management's old "HR employee record" linked a login to the legacy
-- employee list, which in V1 holds only placeholder rows. It is replaced by
-- the account's People record, linked and unlinked through the existing
-- v1_people_set_account (HR/PRO and Admin only).
--
--   * v1_people_account_person(app_user_id): for People viewers (PR,
--     Accountant, Admin and anyone granted people_records.view), the
--     account, the People record it is linked to (or null), and whether the
--     caller may link. The app user id is resolved to the auth account
--     server-side, as the other User Management commands do.
--
-- Data preservation: one read-only function; no table, row or grant on an
-- existing object changes. Legacy employee links on app users are kept and
-- simply no longer shown while People records are on.
-- Rollback: drop function public.v1_people_account_person(text).

begin;

create or replace function public.v1_people_account_person(
  p_app_user_id text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_auth_user_id uuid;
  v_worker_id uuid;
begin
  perform public.v1_people_assert('people_records.view');
  v_auth_user_id := public.v1_permission_target_auth_id(p_app_user_id);
  if v_auth_user_id is null then
    raise exception 'V1_PEOPLE_ACCOUNT_NOT_FOUND' using errcode = 'P0002';
  end if;
  select worker.id into v_worker_id
  from public.v1_workforce_workers worker
  where worker.linked_auth_user_id = v_auth_user_id;
  return jsonb_build_object(
    'account', public.v1_people_account_json(v_auth_user_id),
    'person', case
      when v_worker_id is null then null
      else public.v1_people_person_json(v_worker_id, false)
    end,
    'can_link', public.v1_people_may_link()
  );
end;
$$;

revoke all on function public.v1_people_account_person(text)
  from public, anon;
grant execute on function public.v1_people_account_person(text)
  to authenticated;

commit;

notify pgrst, 'reload schema';
