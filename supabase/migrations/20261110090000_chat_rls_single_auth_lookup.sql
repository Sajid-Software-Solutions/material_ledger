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
