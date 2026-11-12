-- Rollback: Workforce month-end reminders (keeps every table and row).
-- Stops the daily job and the in-app list; reminders already sent stay.
--   npx supabase@latest db query --remote=<ref> --yes -f supabase/release/attendance_month_end_reminders_rollback.sql

begin;

do $unschedule$
begin
  if exists (
    select 1 from cron.job where jobname = 'yorks-workforce-month-end-reminders'
  ) then
    perform cron.unschedule('yorks-workforce-month-end-reminders');
  end if;
end;
$unschedule$;

revoke execute on function public.v1_wf_get_confirmations_due()
  from authenticated;

commit;

notify pgrst, 'reload schema';
