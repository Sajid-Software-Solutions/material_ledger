-- People records: the read functions run as ordinary (volatile) functions.
--
-- v1_people_overview, v1_people_list and v1_people_get were declared
-- STABLE. PostgREST runs a STABLE function in a read-only transaction, but
-- each one first calls v1_people_assert, which syncs the caller's profile
-- (v1_sync_profile_from_auth) and may write it. Through the API the read
-- therefore failed with "cannot execute INSERT in a read-only transaction"
-- (25006), and People showed "Something went wrong". Worker Records, which
-- performs the same sync, is volatile for the same reason.
--
-- Data preservation: no data changes; only function volatility. Rollback:
-- none needed (STABLE was the defect).

begin;

alter function public.v1_people_overview() volatile;
alter function public.v1_people_list(jsonb) volatile;
alter function public.v1_people_get(uuid) volatile;

commit;

notify pgrst, 'reload schema';
