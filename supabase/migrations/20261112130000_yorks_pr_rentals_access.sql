-- Yorks PR role: full Rentals (owner decision, 12 November 2026,
-- PRODUCT_DECISIONS.md section 37).
--
-- Rentals was an exact-Admin workspace. PR now operates it in full: the
-- portfolio, properties, tenants, leases, rent payments, cheques, the
-- workbook import/export, documents and rental reminders. Admin keeps every
-- right it had. No other role gains anything.
--
-- Data preservation: one strict-superset CHECK and function-body rewrites
-- that only widen an `admin` test to `admin` or `pr`. No row is rewritten.
-- Rollback: re-run the previous definitions from
-- 20261020105617_yorks_rental_record_integrity.sql and the rental
-- notification migrations; the CHECK may stay wider.

begin;

create or replace function public.v1_rental_assert_admin()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
begin
  -- Rentals operators: Admin and PR. The name is retained so every existing
  -- rental command keeps calling the same guard.
  if v_actor is null
    or public.v1_current_role() not in ('admin', 'pr')
    or not public.v1_current_actor_is_active() then
    raise exception 'V1_RENTAL_ADMIN_REQUIRED' using errcode = '42501';
  end if;
  return v_actor;
end;
$$;

-- Same guarded rewrite helper as the PR foundation migration.
create or replace function pg_temp.v1_pr_rewrite(
  p_function regprocedure,
  p_anchor text,
  p_replacement text,
  p_marker text
)
returns void
language plpgsql
as $$
declare
  v_definition text := pg_get_functiondef(p_function);
  v_updated text;
begin
  if position(p_marker in v_definition) > 0 then
    return;
  end if;
  v_updated := replace(v_definition, p_anchor, p_replacement);
  if v_updated = v_definition then
    raise exception 'V1_PR_RENTALS_REWRITE_ANCHOR_MISSING: %', p_function;
  end if;
  execute v_updated;
end;
$$;

-- Rental documents: read and upload.
select pg_temp.v1_pr_rewrite(
  'public.v1_document_target_readable(text,uuid)'::regprocedure,
  'public.v1_current_role()=''admin''
      and exists(select 1 from public.v1_rental_properties',
  'public.v1_current_role() in (''admin'',''pr'')
      and exists(select 1 from public.v1_rental_properties',
  'public.v1_current_role() in (''admin'',''pr'')'
);
select pg_temp.v1_pr_rewrite(
  (select p.oid::regprocedure from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'v1_prepare_rental_document_upload'),
  'v_role <> ''admin''',
  'v_role not in (''admin'', ''pr'')',
  'v_role not in (''admin'', ''pr'')'
);

-- Rental reminders reach PR as well as Admin.
select pg_temp.v1_pr_rewrite(
  'public.v1_run_rental_notifications()'::regprocedure,
  'public.v1_permission_exact_role(p.auth_user_id)=''admin''',
  'public.v1_permission_exact_role(p.auth_user_id) in (''admin'',''pr'')',
  'public.v1_permission_exact_role(p.auth_user_id) in (''admin'',''pr'')'
);
select pg_temp.v1_pr_rewrite(
  'public.v1_rental_notification_matches(public.v1_notifications)'::regprocedure,
  'public.v1_permission_exact_role(n.recipient_auth_user_id)=''admin''',
  'public.v1_permission_exact_role(n.recipient_auth_user_id) in (''admin'',''pr'')',
  'in (''admin'',''pr'')'
);

-- Rent receipts record PR as the actor.
alter table public.v1_rental_receipts
  drop constraint if exists v1_rental_receipts_recorded_by_role_check;
alter table public.v1_rental_receipts
  add constraint v1_rental_receipts_recorded_by_role_check
  check (recorded_by_role in ('admin', 'pr'));

notify pgrst, 'reload schema';

commit;
