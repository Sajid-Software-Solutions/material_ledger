-- Approval must not wait for an owner removing an obsolete recovery snapshot.
-- The committed normalized MR is the retirement fence: private sync obtains its
-- FOR SHARE lock before the private-row lock and rejects every normalized ID;
-- normalized Save locks the MR and rejects non-draft states; recovery reads/list
-- reject progressed records. Those guards are retained unchanged.
-- Normally archive synchronously. On a conflicting recovery lock, persist a
-- server-only cleanup job in the SAME transaction as progression. The worker
-- preserves the complete payload in the existing archive before deleting it.
-- Rollback: retain this queue, its worker and all history until jobs drain. Never
-- delete jobs or restore private snapshots to make a rollback look complete.

create table if not exists public.v1_material_request_recovery_archival_jobs (
  id uuid primary key default gen_random_uuid(),
  draft_id uuid not null,
  owner_auth_user_id uuid not null,
  enqueued_at timestamptz not null default clock_timestamp(),
  next_attempt_at timestamptz not null default clock_timestamp(),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  last_attempt_at timestamptz,
  last_error_code text check (length(last_error_code) <= 5)
);
create index if not exists v1_mr_recovery_archival_jobs_due_idx
on public.v1_material_request_recovery_archival_jobs
  (next_attempt_at, enqueued_at, id);
alter table public.v1_material_request_recovery_archival_jobs
  enable row level security;
revoke all on public.v1_material_request_recovery_archival_jobs
from public, anon, authenticated;
comment on table public.v1_material_request_recovery_archival_jobs is
'Server-only durable cleanup after MR progression. Contains no recovery payload. A normalized MR and its existing sync/read guards fence editing while cleanup is pending.';

create or replace function public.v1_retire_progressed_material_request_recovery()
returns trigger
language plpgsql security definer set search_path = ''
set lock_timeout = '100ms'
as $$
begin
  if new.state <> 'draft' then
    begin
      -- Save/sync acquire advisory -> request -> private, in that order. The
      -- trigger already owns the request lock, so it may only TRY the advisory
      -- lock; waiting here would invert that order. This also detects a private
      -- sync that began before an inserted normalized row became visible.
      if not pg_catalog.pg_try_advisory_xact_lock(
        pg_catalog.hashtextextended('v1_mr_private:' ||
          new.created_by_auth_user_id::text || ':' || new.id::text, 0)
      ) then
        raise exception 'V1_RECOVERY_ARCHIVAL_BUSY' using errcode = '55P03';
      end if;
      -- A legacy/direct writer may hold only the private row. Never wait for it.
      perform 1 from public.v1_material_request_private_drafts
      where draft_id = new.id
        and owner_auth_user_id = new.created_by_auth_user_id
      for update nowait;
      if found then
        perform public.v1_archive_material_request_recovery(
          new.id, new.created_by_auth_user_id, 'request_progressed');
      end if;
    exception when lock_not_available then
      -- A distinct job ID avoids waiting on a worker holding an earlier job for
      -- this MR. Duplicate jobs are safe: archival is row-locked and idempotent.
      insert into public.v1_material_request_recovery_archival_jobs
        (draft_id, owner_auth_user_id, last_error_code)
      values (new.id, new.created_by_auth_user_id, sqlstate);
    end;
  end if;
  return new;
end;
$$;
revoke all on function public.v1_retire_progressed_material_request_recovery()
from public, anon, authenticated;

create or replace function public.v1_process_material_request_recovery_archival(
  p_limit integer default 25
) returns jsonb
language plpgsql security definer set search_path = ''
set lock_timeout = '100ms'
as $$
declare
  v_job public.v1_material_request_recovery_archival_jobs%rowtype;
  v_started timestamptz := clock_timestamp();
  v_completed integer := 0;
  v_deferred integer := 0;
  v_error text;
begin
  -- Work per call and time spent between indexed jobs are bounded. No query in
  -- this worker waits on an employee's recovery row or another cleanup worker.
  for v_job in
    select * from public.v1_material_request_recovery_archival_jobs
    where next_attempt_at <= v_started
    order by next_attempt_at, enqueued_at, id
    limit least(greatest(coalesce(p_limit, 25), 1), 50)
    for update skip locked
  loop
    exit when clock_timestamp() - v_started > interval '1 second';
    begin
      -- Wait for no owner editor, including an absent-row sync which started
      -- before progression. TRY keeps job processing bounded and deadlock-free.
      if not pg_catalog.pg_try_advisory_xact_lock(
        pg_catalog.hashtextextended('v1_mr_private:' ||
          v_job.owner_auth_user_id::text || ':' || v_job.draft_id::text, 0)
      ) then
        raise exception 'V1_RECOVERY_ARCHIVAL_BUSY' using errcode = '55P03';
      end if;
      -- The queue grants no workflow authority. Recheck the committed fence,
      -- including the owner, before touching a complete recovery payload.
      if not exists (
        select 1 from public.v1_material_requests
        where id = v_job.draft_id
          and created_by_auth_user_id = v_job.owner_auth_user_id
          and state <> 'draft'
      ) then
        raise exception 'V1_RECOVERY_ARCHIVAL_FENCE_MISSING'
          using errcode = '55000';
      end if;
      perform 1 from public.v1_material_request_private_drafts
      where draft_id = v_job.draft_id
        and owner_auth_user_id = v_job.owner_auth_user_id
      for update nowait;
      if found then
        perform public.v1_archive_material_request_recovery(
          v_job.draft_id, v_job.owner_auth_user_id, 'request_progressed');
      end if;
      delete from public.v1_material_request_recovery_archival_jobs
      where id = v_job.id;
      v_completed := v_completed + 1;
    exception when others then
      -- Retain both the untouched recovery row and a durable retry obligation.
      -- Do not log business payloads or turn cleanup failure into workflow loss.
      get stacked diagnostics v_error = returned_sqlstate;
      update public.v1_material_request_recovery_archival_jobs
      set attempt_count = attempt_count + 1,
          last_attempt_at = clock_timestamp(),
          last_error_code = v_error,
          next_attempt_at = clock_timestamp() + make_interval(
            secs => least(300, 5 * (attempt_count + 1)))
      where id = v_job.id;
      v_deferred := v_deferred + 1;
    end;
  end loop;
  return jsonb_build_object('completed', v_completed, 'deferred', v_deferred);
end;
$$;
revoke all on function public.v1_process_material_request_recovery_archival(integer)
from public, anon, authenticated;
grant execute on function public.v1_process_material_request_recovery_archival(integer)
to service_role;

do $$
begin
  -- Named cron schedule is idempotent; installation never runs archival as a
  -- migration side effect. Existing user data is left intact for the worker.
  perform cron.schedule(
    'yorks-v1-mr-recovery-archival', '* * * * *',
    'select public.v1_process_material_request_recovery_archival(25);');
end;
$$;

notify pgrst, 'reload schema';
