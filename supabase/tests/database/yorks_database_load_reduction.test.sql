begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(8);

-- Chat policies look up the caller once per statement, not once per row.
select ok(
  (select bool_and(qual like '%( SELECT auth.uid()%')
   from pg_policies
   where schemaname = 'public'
     and policyname in (
       'v1_chat_conversations_select_member',
       'v1_chat_members_select_self_conversation',
       'v1_chat_messages_select_member',
       'v1_chat_acknowledgements_select_member',
       'v1_chat_pins_select_member'
     )),
  'Chat read policies hoist auth.uid() into an InitPlan'
);
select is(
  (select count(*)::integer from pg_policies
   where schemaname = 'public'
     and tablename like 'v1_chat_%'
     and policyname like 'v1_chat_%select%'),
  5,
  'All five chat read policies still exist'
);
select ok(
  (select bool_and(cmd = 'SELECT' and roles = '{authenticated}')
   from pg_policies
   where schemaname = 'public'
     and tablename like 'v1_chat_%'
     and policyname like 'v1_chat_%select%'),
  'Chat read policies keep their command and role'
);

-- Run history retention is scheduled and restricted.
select is(
  (select schedule from cron.job
   where jobname = 'yorks-cron-run-history-retention'),
  '17 3 * * *',
  'Cron run history retention runs daily'
);
select ok(
  not has_function_privilege(
    'authenticated', 'public.v1_purge_cron_run_history()', 'execute'
  ),
  'Signed-in users cannot run the purge'
);
select ok(
  not has_function_privilege(
    'anon', 'public.v1_purge_cron_run_history()', 'execute'
  ),
  'Anonymous callers cannot run the purge'
);

-- The purge removes only history older than seven days.
insert into cron.job_run_details (
  jobid, runid, job_pid, database, username, command, status,
  return_message, start_time, end_time
) values
  (1, -910001, 0, 'postgres', 'postgres', 'select 1', 'succeeded', '1',
   now() - interval '9 days', now() - interval '9 days'),
  (1, -910002, 0, 'postgres', 'postgres', 'select 1', 'succeeded', '1',
   now() - interval '1 day', now() - interval '1 day');
select public.v1_purge_cron_run_history();
select ok(
  not exists (select 1 from cron.job_run_details where runid = -910001),
  'History older than seven days is removed'
);
select ok(
  exists (select 1 from cron.job_run_details where runid = -910002),
  'Recent history is kept'
);

select * from finish();
rollback;
