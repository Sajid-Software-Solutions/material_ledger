-- Workforce: a status-only view of crew members' documents for the people
-- who run the crew (owner decision, 13 November 2026; PRODUCT_DECISIONS
-- section 45).
--
-- Engineers who can see a crew (the Project and Site Engineers on its
-- project, the organization-wide engineers, the Accountant, PR and Admin;
-- `v1_wf_crew_access`) learn, for each worker on it, only whether that
-- person's documents are OK, expiring within 60 days, or expired. No
-- document kind, number, date, date of birth or other People field is
-- returned, and no `people_records.*` capability is needed or granted.
--
-- The workers covered are the crew's current members and anyone who worked
-- on the crew in the last 31 days (a worker borrowed from another crew).
-- A worker with no dated document has no status.
--
-- Data preservation: one new read-only function. Rollback: drop it.

begin;

create or replace function public.v1_wf_crew_document_status(p_team_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_today date := public.v1_wf_today();
begin
  if not coalesce(
    (public.v1_wf_crew_access(p_team_id) ->> 'view')::boolean, false
  ) then
    raise exception 'V1_WORKFORCE_CREW_ACCESS_DENIED' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'schema_version', 'yorks.workforce.crew_document_status.v1',
    'today', v_today,
    'statuses', coalesce((
      select jsonb_object_agg(statuses.worker_id, statuses.status)
      from (
        select document.worker_id,
          case
            when bool_or(document.expiry_date < v_today) then 'expired'
            when bool_or(document.expiry_date <= v_today + 60) then 'expiring'
            else 'ok'
          end as status
        from public.v1_people_documents document
        where document.is_current
          and document.expiry_date is not null
          and document.worker_id in (
            select member.worker_id
            from public.v1_workforce_crew_members member
            where member.team_id = p_team_id and member.removed_at is null
            union
            select day_row.worker_id
            from public.v1_workforce_day_rows day_row
            where day_row.team_id = p_team_id
              and day_row.work_date >= v_today - 31
          )
        group by document.worker_id
      ) statuses
    ), '{}'::jsonb)
  );
end;
$$;

revoke all on function public.v1_wf_crew_document_status(uuid)
  from public, anon;
grant execute on function public.v1_wf_crew_document_status(uuid)
  to authenticated;

commit;

notify pgrst, 'reload schema';
