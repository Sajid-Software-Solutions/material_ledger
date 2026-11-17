-- Rollback: attendance terminals, the receiver and the punch log
-- (PRODUCT_DECISIONS.md section 64).
--
-- Switches the receiver off, takes the functions away from the service role
-- and removes the clean-up schedule. After this the Edge Function answers
-- every terminal with an error, so terminals keep their punches and send
-- them again if the receiver is restored.
--
-- Every table, terminal, punch and unread line stays. Nothing in attendance
-- was ever changed by this slice, so there is nothing to undo there.
-- To remove the address as well, delete the `attendance-terminal` Edge
-- Function and the terminals' Vercel project by hand.
--   npx supabase@latest db query --remote=<ref> --yes -f supabase/release/attendance_terminals_rollback.sql
-- Restore: apply supabase/release/attendance_terminals_bundle.sql again and
-- switch the receiver on.

begin;

update public.v1_workforce_terminal_settings
set receiver_enabled = false,
    updated_at = clock_timestamp()
where id;

revoke execute on function public.v1_wf_terminal_handshake(text, jsonb)
  from service_role;
revoke execute on function public.v1_wf_terminal_punches(text, text, jsonb, jsonb)
  from service_role;
revoke execute on function public.v1_wf_terminal_seen(text, text, text, jsonb)
  from service_role;
revoke execute on function public.v1_wf_terminal_receiver(boolean)
  from service_role;
revoke execute on function public.v1_wf_register_terminal(text, text, text)
  from service_role;
revoke execute on function public.v1_wf_set_terminal_active(text, boolean)
  from service_role;
revoke execute on function public.v1_wf_terminal_resend_all(text)
  from service_role;

do $unschedule$
begin
  perform cron.unschedule('yorks-workforce-terminal-request-retention');
exception
  when others then
    -- Not scheduled: nothing to remove.
    null;
end;
$unschedule$;

-- Self-check.
do $check$
begin
  if (select receiver_enabled from public.v1_workforce_terminal_settings)
    or has_function_privilege('service_role',
      'public.v1_wf_terminal_punches(text,text,jsonb,jsonb)', 'execute')
    or has_function_privilege('service_role',
      'public.v1_wf_terminal_handshake(text,jsonb)', 'execute')
    or exists (
      select 1 from cron.job
      where jobname = 'yorks-workforce-terminal-request-retention'
    ) then
    raise exception 'attendance terminals rollback self-check failed';
  end if;
end;
$check$;

commit;

notify pgrst, 'reload schema';
