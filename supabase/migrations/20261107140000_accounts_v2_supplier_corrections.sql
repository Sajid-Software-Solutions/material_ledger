-- R39 Accounts Workspace V2 — easy to reverse, easy to edit (supplier bills)
--
-- Owner decision of 7 November 2026. An approved or cancelled bill can return to
-- draft for editing once no money is left on it, and a payment can be edited in
-- one step. The ledger stays append-only and each correction needs a reason. The
-- approved-by rules and supplier match are unchanged: a reopened bill is approved
-- again through the normal command.

alter table public.v1_accounts_supplier_payments
  add column if not exists reference_sequence integer not null default 1
    check (reference_sequence > 0);

drop index if exists public.v1_accounts_supplier_payment_reference_uq;
create unique index if not exists v1_accounts_supplier_payment_reference_sequence_uq
  on public.v1_accounts_supplier_payments (
    project_id, lower(btrim(payment_reference)), reference_sequence
  );

create or replace function public.v1_accounts_supplier_payment_sequences()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_latest public.v1_accounts_supplier_payments%rowtype;
begin
  select * into v_latest
  from public.v1_accounts_supplier_payments payment
  where payment.project_id = new.project_id
    and lower(btrim(payment.payment_reference))
      = lower(btrim(new.payment_reference))
  order by payment.reference_sequence desc
  limit 1;
  if found then
    new.reference_sequence := v_latest.reference_sequence + case
      when v_latest.entry_kind = 'payment' and exists (
        select 1 from public.v1_accounts_supplier_payments reversal
        where reversal.original_payment_id = v_latest.id
      ) then 1 else 0 end;
  end if;
  return new;
end;
$$;

drop trigger if exists v1_accounts_supplier_payment_sequences
  on public.v1_accounts_supplier_payments;
create trigger v1_accounts_supplier_payment_sequences
  before insert on public.v1_accounts_supplier_payments
  for each row execute function public.v1_accounts_supplier_payment_sequences();

create or replace function public.v1_accounts_supplier_reversal_reference(
  p_project_id uuid,
  p_original_reference text
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_base text := 'REV-' || left(btrim(p_original_reference), 170);
  v_candidate text := v_base;
  v_attempt integer := 1;
begin
  while exists (
    select 1 from public.v1_accounts_supplier_payments payment
    where payment.project_id = p_project_id
      and lower(btrim(payment.payment_reference)) = lower(v_candidate)
  ) loop
    v_attempt := v_attempt + 1;
    v_candidate := v_base || '-' || v_attempt::text;
  end loop;
  return v_candidate;
end;
$$;

create or replace function public.v1_reverse_supplier_payment(
  p_project_id uuid,
  p_supplier_bill_id uuid,
  p_expected_version integer,
  p_original_payment_id uuid,
  p_reversal_date date,
  p_reversal_reference text,
  p_reason text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_exact text;
  v_role text := public.v1_current_role();
  v_bill public.v1_accounts_supplier_bills%rowtype;
  v_original public.v1_accounts_supplier_payments%rowtype;
  v_reversal_id uuid := gen_random_uuid();
  v_payload jsonb;
  v_existing jsonb;
  v_before jsonb;
  v_response jsonb;
  v_now timestamptz := clock_timestamp();
begin
  v_exact := public.v1_accounts_require_capability(
    p_project_id, 'approve_supplier_bill_payment'
  );
  if v_exact not in ('accountant', 'admin')
    or not public.v1_current_user_has_capability(
      'view_supplier_costs', p_project_id
    ) then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode='42501';
  end if;
  if p_reversal_date is null
    or nullif(btrim(p_reason), '') is null then
    raise exception 'R39_ACCOUNTS_REVERSAL_IDENTITY_REQUIRED'
      using errcode='22023';
  end if;
  v_payload := jsonb_build_object(
    'project_id', p_project_id,
    'supplier_bill_id', p_supplier_bill_id,
    'expected_version', p_expected_version,
    'original_payment_id', p_original_payment_id,
    'reversal_date', p_reversal_date,
    'reversal_reference', nullif(btrim(p_reversal_reference), ''),
    'reason', btrim(p_reason)
  );
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_reverse_supplier_payment', p_idempotency_key, v_payload
  );
  if v_existing is not null then
    return v_existing || jsonb_build_object('replayed', true);
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'r39_supplier_bill|' || p_supplier_bill_id::text, 0
    )
  );
  select * into v_bill
  from public.v1_accounts_supplier_bills
  where id = p_supplier_bill_id and project_id = p_project_id
  for update;
  if not found then
    raise exception 'R39_ACCOUNTS_SUPPLIER_BILL_NOT_FOUND'
      using errcode='P0002';
  end if;
  if v_bill.record_version <> p_expected_version then
    raise exception 'R39_ACCOUNTS_VERSION_CONFLICT' using errcode='40001';
  end if;
  select * into v_original
  from public.v1_accounts_supplier_payments
  where id = p_original_payment_id
    and project_id = p_project_id
    and supplier_bill_id = p_supplier_bill_id
    and entry_kind = 'payment'
  for update;
  if not found then
    raise exception 'R39_ACCOUNTS_SUPPLIER_PAYMENT_NOT_FOUND'
      using errcode='P0002';
  end if;
  if exists (
    select 1 from public.v1_accounts_supplier_payments reversal
    where reversal.original_payment_id = p_original_payment_id
      and reversal.entry_kind = 'reversal'
  ) then
    raise exception 'R39_ACCOUNTS_SUPPLIER_PAYMENT_ALREADY_REVERSED'
      using errcode='55000';
  end if;
  v_before := public.v1_accounts_supplier_bill_snapshot(p_supplier_bill_id);
  insert into public.v1_accounts_supplier_payments (
    id, project_id, supplier_bill_id, entry_kind, original_payment_id,
    payment_date, payment_method, payment_reference, amount, reason,
    actor_auth_user_id, actor_role, actor_exact_role,
    idempotency_key, created_at
  ) values (
    v_reversal_id, p_project_id, p_supplier_bill_id, 'reversal',
    p_original_payment_id, p_reversal_date, 'reversal',
    coalesce(
      nullif(btrim(p_reversal_reference), ''),
      public.v1_accounts_supplier_reversal_reference(
        p_project_id, v_original.payment_reference
      )
    ), v_original.amount, btrim(p_reason),
    auth.uid(), v_role, v_exact, p_idempotency_key, v_now
  );
  update public.v1_accounts_supplier_bills
  set record_version = record_version + 1, updated_at = v_now
  where id = p_supplier_bill_id;
  perform public.v1_write_audit_event(
    'accounts.supplier_payment.reversed', 'accounts_supplier_payment',
    v_reversal_id, p_project_id, v_before,
    public.v1_accounts_supplier_bill_snapshot(p_supplier_bill_id),
    btrim(p_reason), p_idempotency_key
  );
  v_response := jsonb_build_object(
    'schema_version', 4, 'replayed', false,
    'project_id', p_project_id, 'entity_id', v_reversal_id,
    'reversal_id', v_reversal_id,
    'original_payment_id', p_original_payment_id,
    'supplier_bill_id', p_supplier_bill_id,
    'supplier_bill_record_version', p_expected_version + 1,
    'amount', v_original.amount::text,
    'payment_status', public.v1_accounts_supplier_payment_status(
      p_supplier_bill_id
    ), 'updated_at', v_now
  );
  perform public.v1_complete_idempotency(
    'v1_reverse_supplier_payment', p_idempotency_key, v_response
  );
  return v_response;
exception when unique_violation then
  raise exception 'R39_ACCOUNTS_DUPLICATE_PAYMENT_REFERENCE'
    using errcode='23505';
end;
$$;

create or replace function public.v1_accounts_supplier_commands(
  p_project_id uuid,
  p_supplier_bill_id uuid default null
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'create_bill', public.v1_current_user_has_capability(
      'manage_supplier_bills', p_project_id
    ),
    'edit_bill', public.v1_current_user_has_capability(
      'manage_supplier_bills', p_project_id
    ) and (
      p_supplier_bill_id is null or exists (
        select 1 from public.v1_accounts_supplier_bills bill
        where bill.id = p_supplier_bill_id
          and bill.project_id = p_project_id and bill.status = 'draft'
      )
    ),
    'approve_bill', public.v1_current_user_has_capability(
      'approve_supplier_bill_payment', p_project_id
    ),
    'record_payment', public.v1_current_user_has_capability(
      'approve_supplier_bill_payment', p_project_id
    ),
    'reverse_payment', public.v1_current_user_has_capability(
      'approve_supplier_bill_payment', p_project_id
    ),
    'cancel_bill', public.v1_current_user_has_capability(
      'manage_supplier_bills', p_project_id
    ) or public.v1_current_user_has_capability(
      'approve_supplier_bill_payment', p_project_id
    ),
    'correct_payment', public.v1_current_user_has_capability(
      'approve_supplier_bill_payment', p_project_id
    ),
    'reopen_bill', public.v1_current_user_has_capability(
      'manage_supplier_bills', p_project_id
    ) or public.v1_current_user_has_capability(
      'approve_supplier_bill_payment', p_project_id
    )
  );
$$;

create or replace function public.v1_correct_supplier_payment(
  p_project_id uuid,
  p_supplier_bill_id uuid,
  p_expected_version integer,
  p_original_payment_id uuid,
  p_payment_date date,
  p_payment_method text,
  p_payment_reference text,
  p_amount text,
  p_reason text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_exact text;
  v_role text := public.v1_current_role();
  v_bill public.v1_accounts_supplier_bills%rowtype;
  v_original public.v1_accounts_supplier_payments%rowtype;
  v_amount numeric;
  v_reversal_id uuid := gen_random_uuid();
  v_payment_id uuid := gen_random_uuid();
  v_payload jsonb;
  v_existing jsonb;
  v_before jsonb;
  v_response jsonb;
  v_now timestamptz := clock_timestamp();
begin
  v_exact := public.v1_accounts_require_capability(
    p_project_id, 'approve_supplier_bill_payment'
  );
  if v_exact not in ('accountant', 'admin')
    or not public.v1_current_user_has_capability(
      'view_supplier_costs', p_project_id
    ) then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode='42501';
  end if;
  if p_payment_date is null
    or nullif(btrim(p_payment_method), '') is null
    or nullif(btrim(p_payment_reference), '') is null then
    raise exception 'R39_ACCOUNTS_PAYMENT_IDENTITY_REQUIRED'
      using errcode='22023';
  end if;
  if nullif(btrim(p_reason), '') is null then
    raise exception 'R39_ACCOUNTS_REASON_REQUIRED' using errcode='22023';
  end if;
  v_amount := public.v1_accounts_parse_money_text(p_amount);
  if v_amount <= 0 then
    raise exception 'R39_ACCOUNTS_INVALID_PAYMENT_AMOUNT'
      using errcode='22023';
  end if;
  v_payload := jsonb_build_object(
    'project_id', p_project_id,
    'supplier_bill_id', p_supplier_bill_id,
    'expected_version', p_expected_version,
    'original_payment_id', p_original_payment_id,
    'payment_date', p_payment_date,
    'payment_method', btrim(p_payment_method),
    'payment_reference', btrim(p_payment_reference),
    'amount', v_amount::text,
    'reason', btrim(p_reason)
  );
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_correct_supplier_payment', p_idempotency_key, v_payload
  );
  if v_existing is not null then
    return v_existing || jsonb_build_object('replayed', true);
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'r39_supplier_bill|' || p_supplier_bill_id::text, 0
    )
  );
  select * into v_bill
  from public.v1_accounts_supplier_bills
  where id = p_supplier_bill_id and project_id = p_project_id
  for update;
  if not found then
    raise exception 'R39_ACCOUNTS_SUPPLIER_BILL_NOT_FOUND'
      using errcode='P0002';
  end if;
  if v_bill.status <> 'approved' then
    raise exception 'R39_ACCOUNTS_SUPPLIER_BILL_NOT_PAYABLE'
      using errcode='55000';
  end if;
  if v_bill.record_version <> p_expected_version then
    raise exception 'R39_ACCOUNTS_VERSION_CONFLICT' using errcode='40001';
  end if;
  select * into v_original
  from public.v1_accounts_supplier_payments
  where id = p_original_payment_id
    and project_id = p_project_id
    and supplier_bill_id = p_supplier_bill_id
    and entry_kind = 'payment'
  for update;
  if not found then
    raise exception 'R39_ACCOUNTS_SUPPLIER_PAYMENT_NOT_FOUND'
      using errcode='P0002';
  end if;
  if exists (
    select 1 from public.v1_accounts_supplier_payments reversal
    where reversal.original_payment_id = p_original_payment_id
  ) then
    raise exception 'R39_ACCOUNTS_SUPPLIER_PAYMENT_ALREADY_REVERSED'
      using errcode='55000';
  end if;
  if public.v1_accounts_supplier_paid_amount(p_supplier_bill_id)
      - v_original.amount + v_amount > v_bill.total_incl_vat then
    raise exception 'R39_ACCOUNTS_PAYMENT_CAP_EXCEEDED' using errcode='23514';
  end if;
  v_before := public.v1_accounts_supplier_bill_snapshot(p_supplier_bill_id);
  insert into public.v1_accounts_supplier_payments (
    id, project_id, supplier_bill_id, entry_kind, original_payment_id,
    payment_date, payment_method, payment_reference, amount, reason,
    actor_auth_user_id, actor_role, actor_exact_role,
    idempotency_key, created_at
  ) values (
    v_reversal_id, p_project_id, p_supplier_bill_id, 'reversal',
    p_original_payment_id, p_payment_date, 'reversal',
    public.v1_accounts_supplier_reversal_reference(
      p_project_id, v_original.payment_reference
    ), v_original.amount, btrim(p_reason),
    auth.uid(), v_role, v_exact, p_idempotency_key, v_now
  );
  insert into public.v1_accounts_supplier_payments (
    id, project_id, supplier_bill_id, entry_kind,
    payment_date, payment_method, payment_reference, amount, reason,
    admin_exception_reason, actor_auth_user_id, actor_role, actor_exact_role,
    idempotency_key, created_at
  ) values (
    v_payment_id, p_project_id, p_supplier_bill_id, 'payment',
    p_payment_date, btrim(p_payment_method), btrim(p_payment_reference),
    v_amount, btrim(p_reason), v_original.admin_exception_reason,
    auth.uid(), v_role, v_exact, p_idempotency_key, v_now
  );
  update public.v1_accounts_supplier_bills
  set record_version = record_version + 1, updated_at = v_now
  where id = p_supplier_bill_id;
  perform public.v1_write_audit_event(
    'accounts.supplier_payment.corrected', 'accounts_supplier_payment',
    v_payment_id, p_project_id, v_before,
    public.v1_accounts_supplier_bill_snapshot(p_supplier_bill_id),
    btrim(p_reason), p_idempotency_key
  );
  v_response := jsonb_build_object(
    'schema_version', 4, 'replayed', false,
    'project_id', p_project_id, 'entity_id', v_payment_id,
    'payment_id', v_payment_id,
    'original_payment_id', p_original_payment_id,
    'supplier_bill_id', p_supplier_bill_id,
    'supplier_bill_record_version', p_expected_version + 1,
    'amount', v_amount::text,
    'payment_status', public.v1_accounts_supplier_payment_status(
      p_supplier_bill_id
    ), 'updated_at', v_now
  );
  perform public.v1_complete_idempotency(
    'v1_correct_supplier_payment', p_idempotency_key, v_response
  );
  return v_response;
exception when unique_violation then
  raise exception 'R39_ACCOUNTS_DUPLICATE_PAYMENT_REFERENCE'
    using errcode='23505';
end;
$$;

-- Back to draft for editing. Taking back an approval needs the approval
-- capability; a bill that was never approved only needs bill management.
create or replace function public.v1_reopen_supplier_bill(
  p_project_id uuid,
  p_supplier_bill_id uuid,
  p_expected_version integer,
  p_reason text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_bill public.v1_accounts_supplier_bills%rowtype;
  v_exact text := public.v1_permission_exact_role(auth.uid());
  v_payload jsonb;
  v_existing jsonb;
  v_before jsonb;
  v_response jsonb;
  v_now timestamptz := clock_timestamp();
begin
  if nullif(btrim(p_reason), '') is null then
    raise exception 'R39_ACCOUNTS_REASON_REQUIRED' using errcode='22023';
  end if;
  if not public.v1_current_user_has_capability(
    'view_supplier_costs', p_project_id
  ) then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode='42501';
  end if;
  v_payload := jsonb_build_object(
    'project_id', p_project_id,
    'supplier_bill_id', p_supplier_bill_id,
    'expected_version', p_expected_version,
    'reason', btrim(p_reason)
  );
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_reopen_supplier_bill', p_idempotency_key, v_payload
  );
  if v_existing is not null then
    return v_existing || jsonb_build_object('replayed', true);
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'r39_supplier_bill|' || p_supplier_bill_id::text, 0
    )
  );
  select * into v_bill
  from public.v1_accounts_supplier_bills
  where id = p_supplier_bill_id and project_id = p_project_id
  for update;
  if not found then
    raise exception 'R39_ACCOUNTS_SUPPLIER_BILL_NOT_FOUND'
      using errcode='P0002';
  end if;
  if v_bill.status = 'draft' then
    raise exception 'R39_ACCOUNTS_SUPPLIER_BILL_NOT_REOPENABLE'
      using errcode='55000';
  end if;
  if v_bill.approved_at is not null then
    perform public.v1_accounts_require_capability(
      p_project_id, 'approve_supplier_bill_payment'
    );
  else
    perform public.v1_accounts_require_capability(
      p_project_id, 'manage_supplier_bills'
    );
  end if;
  if v_exact not in ('procurement', 'accountant', 'admin') then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode='42501';
  end if;
  if v_bill.record_version <> p_expected_version then
    raise exception 'R39_ACCOUNTS_VERSION_CONFLICT' using errcode='40001';
  end if;
  if public.v1_accounts_supplier_paid_amount(p_supplier_bill_id) <> 0 then
    raise exception 'R39_ACCOUNTS_SUPPLIER_BILL_HAS_PAYMENTS'
      using errcode='55000';
  end if;
  v_before := public.v1_accounts_supplier_bill_snapshot(p_supplier_bill_id);
  update public.v1_accounts_supplier_bills
  set status = 'draft',
      approved_at = null, approved_by_auth_user_id = null,
      approved_by_exact_role = null, approval_admin_exception_reason = null,
      cancelled_at = null, cancelled_by_auth_user_id = null,
      cancellation_reason = null,
      record_version = record_version + 1, updated_at = v_now
  where id = p_supplier_bill_id;
  perform public.v1_write_audit_event(
    'accounts.supplier_bill.reopened', 'accounts_supplier_bill',
    p_supplier_bill_id, p_project_id, v_before,
    public.v1_accounts_supplier_bill_snapshot(p_supplier_bill_id),
    btrim(p_reason), p_idempotency_key
  );
  v_response := jsonb_build_object(
    'schema_version', 4, 'replayed', false,
    'project_id', p_project_id, 'entity_id', p_supplier_bill_id,
    'supplier_bill_id', p_supplier_bill_id,
    'record_version', p_expected_version + 1,
    'status', 'draft',
    'payment_status', public.v1_accounts_supplier_payment_status(
      p_supplier_bill_id
    ), 'updated_at', v_now
  );
  perform public.v1_complete_idempotency(
    'v1_reopen_supplier_bill', p_idempotency_key, v_response
  );
  return v_response;
end;
$$;

revoke all on function public.v1_accounts_supplier_payment_sequences() from public, anon, authenticated;
revoke all on function public.v1_accounts_supplier_reversal_reference(uuid, text) from public, anon, authenticated;
revoke all on function public.v1_correct_supplier_payment(uuid, uuid, integer, uuid, date, text, text, text, text, uuid) from public, anon;
revoke all on function public.v1_reopen_supplier_bill(uuid, uuid, integer, text, uuid) from public, anon;
grant execute on function public.v1_correct_supplier_payment(uuid, uuid, integer, uuid, date, text, text, text, text, uuid) to authenticated;
grant execute on function public.v1_reopen_supplier_bill(uuid, uuid, integer, text, uuid) to authenticated;
