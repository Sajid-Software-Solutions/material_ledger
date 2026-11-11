-- LOCAL/STAGING SYNTHETIC PROFILING ONLY. All fixture writes roll back.
-- Run with psql -X -v ON_ERROR_STOP=1 against the seeded repair database.
-- Captures the exact indexed lock target and a 900 KB historical JSON snapshot.
begin;
insert into public.v1_material_request_private_drafts
  (draft_id,owner_auth_user_id,sync_version,draft_data,client_updated_at)
select gen_random_uuid(),'10000000-0000-4000-8000-000000000002',1,
  '{"title":"Local plan fixture","lines":[]}',now()
from generate_series(1,10000);
insert into public.v1_material_request_private_drafts
  (draft_id,owner_auth_user_id,sync_version,draft_data,client_updated_at)
values ('ad159999-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000002',11,
  jsonb_build_object('title','Large legacy payload',
    'unknown_future',repeat('x',900000),'lines','[]'::jsonb),now());
analyze public.v1_material_request_private_drafts;
explain (analyze,buffers)
select 1 from public.v1_material_request_private_drafts
where draft_id='ad159999-0000-4000-8000-000000000001'
  and owner_auth_user_id='10000000-0000-4000-8000-000000000002'
for update nowait;
do $$declare v_started timestamptz:=clock_timestamp(); begin
  perform public.v1_archive_material_request_recovery(
    'ad159999-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000002','request_progressed');
  raise notice 'archive_900KB_ms=%',
    round((extract(epoch from clock_timestamp()-v_started)*1000)::numeric,3);
end $$;
select octet_length(draft_data->>'unknown_future')=900000
  as unknown_payload_preserved
from public.v1_material_request_recovery_archive
where draft_id='ad159999-0000-4000-8000-000000000001';
rollback;
