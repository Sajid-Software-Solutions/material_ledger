-- R39 Accounts V2 — remove anonymous EXECUTE from nine Accounts RPCs.
--
-- Why: the Accounts V2 P2/P3 migrations of 5 November 2026 created these
-- functions and granted EXECUTE to `authenticated`, but never revoked the
-- grants every new function receives. PostgreSQL gives PUBLIC EXECUTE on a new
-- function, and Supabase's default privileges for `postgres` in `public` add
-- explicit EXECUTE for `anon`, `authenticated` and `service_role`. Later
-- `create or replace` redefinitions keep that ACL. So `anon` could call:
--
--   v1_save_project_commercial_setup     20261105103000_accounts_v2_p2_save_setup
--   v1_get_claim_workbench               20261105110000_accounts_v2_p3_claim_workbench_read
--   v1_reopen_client_claim               20261105110000_accounts_v2_p3_claim_workbench_read
--   v1_save_project_invoice_settings     20261105113000_accounts_v2_p3_invoice_issue
--   v1_issue_client_invoice              20261105113000_accounts_v2_p3_invoice_issue
--   v1_get_client_invoice_document       20261105113000_accounts_v2_p3_invoice_issue
--   v1_preview_client_invoice_document   20261105113000_accounts_v2_p3_invoice_issue
--   v1_revise_client_invoice             20261105120000_accounts_v2_p3_invoice_revise
--   v1_save_claim_workbench              20261105130000_accounts_v2_p3_save_workbench
--
-- Each one already rejects a caller without a signed-in active user
-- (`v1_accounts_require_capability` raises 42501), so this is defence in depth,
-- not a fix for an open hole. Anonymous callers keep getting SQLSTATE 42501;
-- only the message changes, to PostgreSQL's own "permission denied".
--
-- What changes: EXECUTE is revoked from PUBLIC and `anon` on exactly these
-- nine signatures. `authenticated` and `service_role` keep the explicit grants
-- they hold today; no function body, table, row, policy or capability changes.
--
-- Idempotent: revoking a privilege that is not held is a no-op, so the file
-- (and the release bundle that contains it) can be re-run. The closing check
-- rolls the whole transaction back if any of the nine is still callable by
-- `anon`, or if `authenticated` has lost EXECUTE on any of them.
--
-- Rollback (restores the previous ACL exactly; not recommended):
--   grant execute on function <signature> to public, anon;
-- for each signature below.

revoke execute on function public.v1_save_project_commercial_setup(uuid, integer, jsonb, text, uuid)
  from public, anon;
revoke execute on function public.v1_get_claim_workbench(uuid, uuid)
  from public, anon;
revoke execute on function public.v1_reopen_client_claim(uuid, uuid, integer, text, uuid)
  from public, anon;
revoke execute on function public.v1_save_project_invoice_settings(uuid, text, text, uuid, text, integer, uuid)
  from public, anon;
revoke execute on function public.v1_issue_client_invoice(uuid, uuid, integer, text, date, date, uuid)
  from public, anon;
revoke execute on function public.v1_get_client_invoice_document(uuid, uuid)
  from public, anon;
revoke execute on function public.v1_preview_client_invoice_document(uuid, uuid)
  from public, anon;
revoke execute on function public.v1_revise_client_invoice(uuid, uuid, integer, text, uuid)
  from public, anon;
revoke execute on function public.v1_save_claim_workbench(uuid, text, date, date, jsonb, uuid[], text, uuid)
  from public, anon;

do $$
declare
  v_signature text;
  v_oid oid;
begin
  foreach v_signature in array array[
    'public.v1_save_project_commercial_setup(uuid, integer, jsonb, text, uuid)',
    'public.v1_get_claim_workbench(uuid, uuid)',
    'public.v1_reopen_client_claim(uuid, uuid, integer, text, uuid)',
    'public.v1_save_project_invoice_settings(uuid, text, text, uuid, text, integer, uuid)',
    'public.v1_issue_client_invoice(uuid, uuid, integer, text, date, date, uuid)',
    'public.v1_get_client_invoice_document(uuid, uuid)',
    'public.v1_preview_client_invoice_document(uuid, uuid)',
    'public.v1_revise_client_invoice(uuid, uuid, integer, text, uuid)',
    'public.v1_save_claim_workbench(uuid, text, date, date, jsonb, uuid[], text, uuid)'
  ] loop
    v_oid := v_signature::regprocedure;
    if has_function_privilege('anon', v_oid, 'EXECUTE') then
      raise exception 'R39_ACCOUNTS_ANON_EXECUTE_REMAINS: %', v_signature;
    end if;
    if not has_function_privilege('authenticated', v_oid, 'EXECUTE') then
      raise exception 'R39_ACCOUNTS_AUTHENTICATED_EXECUTE_MISSING: %', v_signature;
    end if;
  end loop;
end;
$$;
