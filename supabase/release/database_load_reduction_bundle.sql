-- =============================================================================
-- Database load reduction (10 Nov 2026) — bundled apply script
-- =============================================================================
-- Concatenation of:
--   supabase/migrations/20261110090000_chat_rls_single_auth_lookup.sql
--   supabase/migrations/20261110090100_cron_run_history_retention.sql
--
-- Both are additive and repeatable. No table, row, grant or business record
-- is changed; the only data removed is pg_cron run history older than 7 days,
-- starting at the first scheduled run (03:17 UTC).
--
-- BEFORE YOU RUN THIS:
--   1. Run it on STAGING first in the SQL editor and confirm it succeeds.
--   2. Then run the identical script on PRODUCTION.
--   3. Do NOT run `supabase db push` or `supabase migration repair`.
--
-- ROLLBACK: re-run the five chat policies from
-- 20260814114626_yorks_r38_5_team_chat.sql and
-- select cron.unschedule('yorks-cron-run-history-retention');
-- =============================================================================

begin;

-- Team Chat read policies called auth.uid() once per row. Postgres evaluates a
-- bare function call in a policy for every candidate row; wrapping it in a
-- scalar sub-select makes it a single InitPlan per statement. Realtime runs
-- these policies for every subscriber on every chat change, so this matters
-- most on a small database (Supabase Performance Advisor "Auth RLS
-- Initialization Plan", 10 Nov 2026).
--
-- Decision-preserving: same policy names, commands, roles and membership
-- predicate. Only the caller lookup is hoisted. Additive and repeatable; no
-- table, row or grant changes. Rollback: re-run the five policy definitions
-- from 20260814114626_yorks_r38_5_team_chat.sql.

drop policy if exists v1_chat_conversations_select_member
  on public.v1_chat_conversations;
create policy v1_chat_conversations_select_member
on public.v1_chat_conversations for select to authenticated
using (public.v1_chat_is_active_member(id, (select auth.uid())));

drop policy if exists v1_chat_members_select_self_conversation
  on public.v1_chat_members;
create policy v1_chat_members_select_self_conversation
on public.v1_chat_members for select to authenticated
using (public.v1_chat_is_active_member(conversation_id, (select auth.uid())));

drop policy if exists v1_chat_messages_select_member
  on public.v1_chat_messages;
create policy v1_chat_messages_select_member
on public.v1_chat_messages for select to authenticated
using (public.v1_chat_is_active_member(conversation_id, (select auth.uid())));

drop policy if exists v1_chat_acknowledgements_select_member
  on public.v1_chat_message_acknowledgements;
create policy v1_chat_acknowledgements_select_member
on public.v1_chat_message_acknowledgements for select to authenticated
using (exists (
  select 1 from public.v1_chat_messages message
  where message.id = message_id
    and public.v1_chat_is_active_member(
      message.conversation_id, (select auth.uid())
    )
));

drop policy if exists v1_chat_pins_select_member
  on public.v1_chat_message_pins;
create policy v1_chat_pins_select_member
on public.v1_chat_message_pins for select to authenticated
using (public.v1_chat_is_active_member(conversation_id, (select auth.uid())));

-- pg_cron keeps a row in cron.job_run_details for every run and never purges
-- it. Two jobs run every minute (push outbox, MR recovery archival), so this
-- history had grown to about 29 MB, the largest object in a 150 MB database
-- whose server has roughly 400 MB of RAM.
--
-- Keep seven days of run history for diagnosis; delete older rows once a day.
-- This is operational scheduler metadata only: no application record, audit
-- event or idempotency key is touched. Additive and repeatable (named
-- schedule). Rollback: select cron.unschedule('yorks-cron-run-history-retention').

create or replace function public.v1_purge_cron_run_history()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted integer;
begin
  delete from cron.job_run_details
  where end_time < now() - interval '7 days';
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke all on function public.v1_purge_cron_run_history()
from public, anon, authenticated;
grant execute on function public.v1_purge_cron_run_history() to service_role;

do $$
begin
  -- Named schedule is idempotent. 03:17 UTC avoids the top of the hour, when
  -- the hourly rental notifications job runs.
  perform cron.schedule(
    'yorks-cron-run-history-retention', '17 3 * * *',
    'select public.v1_purge_cron_run_history();');
end;
$$;

commit;
