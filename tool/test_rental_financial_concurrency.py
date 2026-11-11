#!/usr/bin/env python3
"""Exercise rental financial races against the isolated seeded local test DB.

Only Docker containers named supabase_db_yorks_rental_audit_* are accepted.
No remote DB URL, credentials or production path is supported. Synthetic rows
and temporary triggers are removed in finally; audit/idempotency evidence stays
until the next local reset. Run after applying the tracked migrations.
"""
import argparse
import concurrent.futures
import json
import re
import subprocess
import time
import uuid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--container", required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"supabase_db_yorks_rental_audit_[a-zA-Z0-9_]+", args.container):
        parser.error("Use a separately created local rental-audit Supabase container")
    command = ["docker", "exec", "-i", args.container, "psql", "-U", "postgres", "-d", "postgres", "-X", "-At", "-v", "ON_ERROR_STOP=1"]
    claims = "set request.jwt.claims='{\"sub\":\"10000000-0000-4000-8000-000000000004\",\"role\":\"authenticated\",\"app_metadata\":{\"role\":\"admin\"}}';"

    def sql(statement):
        result = subprocess.run(command, input=claims+statement, capture_output=True, text=True, check=False)
        return {"code": result.returncode, "out": result.stdout.strip(), "error": result.stderr.strip()}

    def require_ok(statement):
        result = sql(statement)
        assert result["code"] == 0, result
        return result["out"].splitlines()[-1]

    def literal(value):
        return "'"+str(value).replace("'", "''")+"'"

    def payload(value):
        return literal(json.dumps(value))+"::jsonb"

    ids = [str(uuid.uuid4()) for _ in range(8)]
    token = uuid.uuid4().hex[:12]
    pause = "rental_financial_review_pause_"+token
    props = [ids[0], ids[2], ids[4], ids[6]]
    results = {}
    try:
        monthly = {"property_id": ids[0], "lease_id": ids[1], "unit_code": "FIN-RACE-"+token, "property_name": "Local financial concurrency fixture", "property_type": "office", "occupancy_state": "occupied", "monthly_rent": 100}
        require_ok("select v1_save_rental_property("+payload(monthly)+"||jsonb_build_object('lease_start',v1_rental_business_date(),'lease_end',v1_rental_business_date()+90,'billing_start',v1_rental_business_date()),null,gen_random_uuid());")
        period = require_ok("select id from v1_rental_periods where lease_id="+literal(ids[1])+" order by period_month limit 1;")
        require_ok("create function public."+pause+"() returns trigger language plpgsql as $$begin if new.property_id="+literal(ids[0])+"::uuid then perform pg_sleep(2); end if; return new; end$$;create trigger "+pause+" before insert on v1_rental_receipts for each row execute function public."+pause+"();")
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            payment = pool.submit(sql, "select v1_record_rent_payment("+literal(period)+",80,v1_rental_business_date(),'cash',null,null,gen_random_uuid());")
            time.sleep(.35)
            edit = pool.submit(sql, "select v1_save_rental_property(jsonb_build_object('property_id',"+literal(ids[0])+",'monthly_rent',50),1,gen_random_uuid());")
            payment_result, edit_result = payment.result(), edit.result()
        assert payment_result["code"] == 0, payment_result
        assert edit_result["code"] != 0 and "V1_RENTAL_PAID_SCHEDULE_CANNOT_BE_REBUILT" in edit_result["error"], edit_result
        balance = json.loads(require_ok("select jsonb_build_object('due',p.amount_due,'paid',sum(r.amount_received)) from v1_rental_periods p join v1_rental_receipts r on r.period_id=p.id where p.id="+literal(period)+" group by p.id;"))
        assert balance == {"due": 100, "paid": 80}, balance
        results["payment_vs_schedule_edit"] = {"receipt_committed": True, "financial_edit_rejected": True, **balance}
        require_ok("drop trigger "+pause+" on v1_rental_receipts;drop function public."+pause+"();")

        original = {key: None for key in ["Unit No", "Unit Type", "Tenant / Company", "Contract Start", "Contract End", "Annual Rent (AED)", "Status", "Security Cheque (AED)", "Contact", "Days to Expiry", "Expiry Flag"]}
        original.update({"Unit Type": "Store", "Tenant / Company": "Local source race "+token})
        source = {"source_format": "yorks_properties_tracker_v1", "original_values": original}
        require_ok("create function public."+pause+"() returns trigger language plpgsql as $$begin if new.unit_code like 'SRC-RACE-%"+token+"' then perform pg_sleep(1); end if; return new; end$$;create trigger "+pause+" before insert on v1_rental_properties for each row execute function public."+pause+"();")
        statements = []
        for index in [2, 4]:
            value = {"property_id": ids[index], "lease_id": ids[index+1], "unit_code": "SRC-RACE-"+str(index)+"-"+token, "property_name": "Local source concurrency fixture", "property_type": "store", "occupancy_state": "occupied", "billing_start": None, "source_metadata": source}
            statements.append("select v1_save_rental_property("+payload(value)+",null,gen_random_uuid());")
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            source_results = list(pool.map(sql, statements))
        assert sorted(result["code"] == 0 for result in source_results) == [False, True], source_results
        assert any("v1_rental_properties_tracker_source_unique_idx" in result["error"] or "V1_RENTAL_SOURCE_ALREADY_IMPORTED_USE_CURRENT_CODE" in result["error"] for result in source_results), source_results
        count = int(require_ok("select count(*) from v1_rental_properties where id in ("+literal(ids[2])+","+literal(ids[4])+");"))
        assert count == 1, count
        results["identical_source_different_codes"] = {"committed_properties": count, "duplicate_rejected": True}
        require_ok("drop trigger "+pause+" on v1_rental_properties;drop function public."+pause+"();")

        pending = {"property_id": ids[6], "lease_id": ids[7], "unit_code": "ARC-RACE-"+token, "property_name": "Local archive race fixture", "property_type": "office", "occupancy_state": "occupied", "billing_start": None}
        require_ok("select v1_save_rental_property("+payload(pending)+",null,gen_random_uuid());")
        cheque = {"property_id": ids[6], "lease_id": ids[7], "cheque_number": "LOCAL-"+token, "cheque_type": "pdc", "bank_name": "Local test bank", "amount": 100, "cheque_date": "2030-01-01"}
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            archive = pool.submit(sql, "begin;select v1_archive_rental_property("+literal(ids[6])+",1,'Local concurrency test',gen_random_uuid());select pg_sleep(1);commit;")
            time.sleep(.25)
            new_cheque = pool.submit(sql, "select v1_save_rental_cheque("+payload(cheque)+",null,gen_random_uuid());")
            archive_result, cheque_result = archive.result(), new_cheque.result()
        assert archive_result["code"] == 0, archive_result
        assert cheque_result["code"] != 0 and "V1_RENTAL_ARCHIVED_PROPERTY_READ_ONLY" in cheque_result["error"], cheque_result
        results["archive_vs_new_cheque"] = {"archive_committed": True, "new_obligation_rejected": True}
        print(json.dumps(results, indent=2))
    finally:
        # Fixed synthetic IDs generated by this run only; retained real/source
        # fixtures and other agents' records are never selected by the cleanup.
        clean = "drop trigger if exists "+pause+" on v1_rental_receipts;drop trigger if exists "+pause+" on v1_rental_properties;drop function if exists public."+pause+"();"
        predicate = " in ("+",".join(literal(value) for value in props)+")"
        clean += "delete from v1_rental_cheques where property_id"+predicate+";delete from v1_rental_receipts where property_id"+predicate+";delete from v1_rental_periods where lease_id in (select id from v1_rental_leases where property_id"+predicate+");delete from v1_rental_leases where property_id"+predicate+";delete from v1_rental_properties where id"+predicate+";"
        result = sql(clean)
        if result["code"]:
            raise RuntimeError("Local synthetic fixture cleanup failed: "+result["error"])


if __name__ == "__main__":
    main()
