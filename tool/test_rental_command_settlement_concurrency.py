"""Actual independent-session rental recovery races on the disposable stack.

No remote URL is accepted. Creates committed synthetic fixtures and retains
their private audit/fence evidence for inspection; run before the isolated full
database reset, never against the developer's main or a remote project.
"""

import concurrent.futures
import json
import subprocess
import time
import uuid

CONTAINER = "supabase_db_yorks_rental_audit_20261020"
ADMIN = "10000000-0000-4000-8000-000000000004"
COMMAND = "v1_save_rental_property"
CLAIMS = json.dumps({"sub": ADMIN, "role": "authenticated", "app_metadata": {"role": "admin"}})


def sql_literal(value):
    return "'" + str(value).replace("'", "''") + "'"


def query(sql, check=True):
    result = subprocess.run(
        ["docker", "exec", CONTAINER, "psql", "-U", "postgres", "-d", "postgres",
         "-X", "-A", "-t", "-v", "ON_ERROR_STOP=1", "-c", sql],
        capture_output=True, text=True, timeout=15,
    )
    if check and result.returncode:
        raise AssertionError(result.stderr)
    return result


def actor_transaction(name, statement, hold=False):
    return (
        f"set application_name={sql_literal(name)}; begin; set local role authenticated; "
        f"select set_config('request.jwt.claims',{sql_literal(CLAIMS)},true); "
        f"{statement}; "
        + ("select pg_sleep(0.8); " if hold else "")
        + "commit;"
    )


def wait_for_command_lock(name, key):
    lock_text = f"{ADMIN}|{COMMAND}|{key}"
    deadline = time.monotonic() + 7
    while time.monotonic() < deadline:
        found = query(f"""select exists(
          select 1 from pg_catalog.pg_locks l join pg_catalog.pg_stat_activity a on a.pid=l.pid
          where a.application_name={sql_literal(name)} and l.locktype='advisory' and l.granted
            and l.classid=((hashtextextended({sql_literal(lock_text)},0)>>32)&4294967295)::oid
            and l.objid=(hashtextextended({sql_literal(lock_text)},0)&4294967295)::oid
            and l.objsubid=1);""").stdout.strip()
        if found == "t":
            return
        time.sleep(0.02)
    raise AssertionError("First transaction did not reach the shared command lock")


def result_state(result):
    return next(json.loads(line)["state"] for line in result.stdout.splitlines()
                if line.startswith("{") and '"state"' in line)


def race(first_is_settlement):
    key, property_id = str(uuid.uuid4()), str(uuid.uuid4())
    name = "rental_settle_review_" + key[:8]
    payload = json.dumps({"property_id": property_id, "unit_code": "SETTLE-RACE-" + key[:8],
                          "property_name": "Local settlement race fixture", "property_type": "shop",
                          "occupancy_state": "vacant"})
    save = f"select public.v1_save_rental_property({sql_literal(payload)}::jsonb,null,'{key}')"
    settle = f"select public.v1_settle_rental_command_intent('{COMMAND}','{key}')"
    first, second = (settle, save) if first_is_settlement else (save, settle)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        future = pool.submit(query, actor_transaction(name, first, hold=True))
        wait_for_command_lock(name, key)
        second_result = pool.submit(query, actor_transaction(name + "_second", second), False).result()
        first_result = future.result()
    evidence = json.loads(query(f"""select jsonb_build_object(
      'properties',(select count(*) from public.v1_rental_properties where id='{property_id}'),
      'abandonment_events',(select count(*) from public.v1_audit_events
        where actor_auth_user_id='{ADMIN}' and event_type='rental_command_intent_abandoned'
          and entity_id='{key}'),
      'fenced',(select request_hash='rental-abandoned:'||'{key}' from public.v1_idempotency_keys
        where actor_auth_user_id='{ADMIN}' and command_name='{COMMAND}' and idempotency_key='{key}'));
      """).stdout.strip())
    if first_is_settlement:
        assert result_state(first_result) == "abandoned", first_result.stdout
        assert second_result.returncode != 0, second_result.stdout
        assert "V1_IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD" in second_result.stderr
        assert evidence == {"properties": 0, "abandonment_events": 1, "fenced": True}, evidence
        print("PASS: settlement wins shared lock; delayed old save fails with no business record and one audit")
    else:
        assert second_result.returncode == 0, second_result.stderr
        assert result_state(second_result) == "confirmed", second_result.stdout
        assert evidence == {"properties": 1, "abandonment_events": 0, "fenced": False}, evidence
        print("PASS: old save wins shared lock; settlement waits and confirms exactly one committed property")


def main():
    if query("select operator_paused from public.v1_push_transport_control where id").stdout.strip() != "t":
        raise AssertionError("Pause push in the disposable local project before this test")
    if query(f"select public.v1_permission_exact_role('{ADMIN}')").stdout.strip() != "admin":
        raise AssertionError("The isolated test project needs its seeded active Admin")
    race(False)
    race(True)


if __name__ == "__main__":
    main()
