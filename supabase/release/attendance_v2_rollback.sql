-- Rollback: Workforce attendance V2 (keeps every table and row).
-- Turn YORKS_V1_WORKFORCE_ATTENDANCE_V2 off first, then apply by hand:
--   npx supabase@latest db query --remote=<ref> --yes -f supabase/release/attendance_v2_rollback.sql
-- Restores the previous notification wrappers and stops every attendance V2
-- command. Attendance tables, rows and history stay in place for a fix
-- forward; nothing is dropped or deleted. The PR role is not rolled back.

begin;

do $restore$ begin
  if to_regprocedure('public.v1_notification_module_route_before_attendance(public.v1_notifications)') is not null then
    drop function public.v1_push_notification_entity_allowed(public.v1_notifications);
    drop function public.v1_notification_module_route(public.v1_notifications);
    drop function public.v1_notification_record_label(public.v1_notifications);
    alter function public.v1_push_notification_entity_allowed_before_attendance(public.v1_notifications) rename to v1_push_notification_entity_allowed;
    alter function public.v1_notification_module_route_before_attendance(public.v1_notifications) rename to v1_notification_module_route;
    alter function public.v1_notification_record_label_before_attendance(public.v1_notifications) rename to v1_notification_record_label;
  end if;
end; $restore$;

do $revoke$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'v1_wf_list_crews()', 'v1_wf_get_crew(uuid)', 'v1_wf_get_overview(date)',
    'v1_wf_get_day(uuid,date)', 'v1_wf_get_month_sheet(uuid,date)',
    'v1_wf_list_workers()', 'v1_wf_list_public_holidays(integer)',
    'v1_wf_save_crew(jsonb,bigint,uuid)',
    'v1_wf_set_crew_members(uuid,uuid[],uuid[],uuid)',
    'v1_wf_save_public_holiday(date,text,boolean)',
    'v1_wf_save_day(uuid,date,jsonb,bigint,text,uuid)',
    'v1_wf_ask_day(uuid,date,text,uuid)',
    'v1_wf_answer_day(uuid,date,text,uuid)',
    'v1_wf_confirm_month(uuid,date,uuid)',
    'v1_wf_reopen_month(uuid,date,text,uuid)'
  ] loop
    execute format(
      'revoke execute on function public.%s from authenticated', v_signature
    );
  end loop;
end;
$revoke$;

commit;

notify pgrst, 'reload schema';
