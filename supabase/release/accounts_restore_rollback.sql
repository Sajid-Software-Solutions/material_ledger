-- Rollback: R39 Accounts — restore a cancelled invoice or deleted claim
--
-- Removes the restore commands. Records already restored stay as they are
-- (cancel them again with the existing commands if needed); their cancel and
-- restore audit events remain. The app's Restore buttons then show the
-- generic refusal.

begin;

drop function if exists public.v1_restore_client_invoice(uuid, uuid, integer, text, uuid);
drop function if exists public.v1_restore_client_claim(uuid, uuid, integer, text, uuid);
drop function if exists public.v1_accounts_restore_check_claim(uuid, uuid);

commit;

notify pgrst, 'reload schema';
