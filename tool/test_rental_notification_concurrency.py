"""Two real sessions exercise the producer against the disposable local stack.

Never accepts a remote database URL. The local push transport must be paused.
The committed test fixture and only the notifications introduced by this test
are removed afterward; existing rental and notification history is retained.
Run while no other local notification test/producer is executing.
"""

import concurrent.futures
import json
import subprocess
import uuid

CONTAINER = "supabase_db_yorks_rental_audit_20261020"


def query(sql):
    result = subprocess.run(
        ["docker", "exec", CONTAINER, "psql", "-U", "postgres", "-d", "postgres",
         "-X", "-A", "-t", "-v", "ON_ERROR_STOP=1", "-c", sql],
        check=True, capture_output=True, text=True,
    )
    return result.stdout.strip()


def scalar(sql):
    return query(sql).splitlines()[-1]


def main():
    if scalar("select operator_paused from public.v1_push_transport_control where id") != "t":
        raise RuntimeError("Pause the disposable local push transport before running this test")
    control = scalar("select to_jsonb(c) from public.v1_rental_notification_control c where id")
    # Restore the full scheduler checkpoint as well as enablement. The fixture
    # must not mark an otherwise uninitialized local producer as initialized.
    control_literal = control.replace("'", "''")
    baseline = set(query("select notification_id from public.v1_rental_notification_events").splitlines())
    property_id, lease_id = str(uuid.uuid4()), str(uuid.uuid4())
    admin = scalar("select auth_user_id from public.v1_profiles where public.v1_permission_exact_role(auth_user_id)='admin' order by auth_user_id limit 1")
    if not admin:
        raise RuntimeError("The disposable local stack needs an active Admin fixture")
    try:
        query(f"""begin;
        insert into public.v1_rental_properties(id,unit_code,property_name,property_type,location,
          occupancy_state,created_by_auth_user_id,updated_by_auth_user_id)
        values('{property_id}','RACE-{property_id[:8]}','Local race fixture','shop','Dubai','occupied','{admin}','{admin}');
        insert into public.v1_rental_leases(id,property_id,contract_number,contract_type,contract_status,
          tenant_name,lease_start,lease_end,monthly_rent,billing_start,created_by_auth_user_id,updated_by_auth_user_id)
        values('{lease_id}','{property_id}','RACE-{lease_id}','lease','active','Local fixture',
          public.v1_rental_business_date()-30,public.v1_rental_business_date()+10,100,null,'{admin}','{admin}');
        update public.v1_rental_notification_control set enabled=true where id;
        commit;""")

        def run():
            output = query("begin; select public.v1_run_rental_notifications(); select pg_sleep(0.3); commit;")
            return next(json.loads(line) for line in output.splitlines() if line.startswith("{"))

        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda _: run(), range(2)))
        if not any(row["emitted"] > 0 for row in results) or sum(row["emitted"] == 0 for row in results) != 1:
            raise AssertionError(f"Concurrent sessions did not serialize one producer result: {results}")
        recipients = int(scalar("select count(*) from public.v1_profiles where public.v1_permission_exact_role(auth_user_id)='admin'"))
        emitted = int(scalar(f"select count(*) from public.v1_rental_notification_events where obligation_id='{lease_id}' and event_code='rental_lease_notice_due'"))
        if emitted != recipients:
            raise AssertionError(f"Expected one milestone per Admin, got {emitted}/{recipients}")
        print(f"PASS: two independent sessions, emissions {[r['emitted'] for r in results]}, one lease milestone per {recipients} Admin(s)")
    finally:
        current = set(query("select notification_id from public.v1_rental_notification_events").splitlines())
        created = current - baseline
        ids = ",".join("'" + str(uuid.UUID(value)) + "'" for value in created)
        cleanup = ""
        if ids:
            cleanup = f"delete from public.v1_rental_notification_events where notification_id in({ids}); delete from public.v1_notifications where id in({ids});"
        query(f"""begin; {cleanup}
          delete from public.v1_rental_leases where id='{lease_id}';
          delete from public.v1_rental_properties where id='{property_id}';
          update public.v1_rental_notification_control c
          set (enabled,external_push_enabled,last_success_at,last_business_date,
               last_emitted_count,initial_evaluation_complete)=(
            select r.enabled,r.external_push_enabled,r.last_success_at,r.last_business_date,
              r.last_emitted_count,r.initial_evaluation_complete
            from jsonb_populate_record(null::public.v1_rental_notification_control,
              '{control_literal}'::jsonb) r
          ) where c.id;
          commit;""")


if __name__ == "__main__":
    main()
