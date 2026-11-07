-- R39 Accounts Workspace V2 — easy to reverse, easy to edit (client money)
--
-- Owner decision of 7 November 2026: mistakes must be easy to reverse and edit,
-- across almost every scenario. History stays append-only: a correction adds
-- entries and never rewrites one, and each one needs a reason and is audited.
--
--   Cheque     edit details; step back; re-present after a bounce; restore a
--              cancelled one; undo clearing, which reverses its receipt.
--   Payment    edit in one step; reversal reference is optional; reversing a
--              cheque's receipt also moves the cheque, so the two always agree.
--   Certified  can be lowered or undone, but never below money received or
--              cheques in hand.
--   Invoice    can be cancelled once everything on it has been undone.
--
-- A reversed reference, or a reversed cheque receipt, may be entered again. Two
-- entries in force can still never share one; the unique indexes enforce that.

alter table public.v1_accounts_client_payments
  add column if not exists reference_sequence integer not null default 1
    check (reference_sequence > 0),
  add column if not exists pdc_clear_sequence integer not null default 1
    check (pdc_clear_sequence > 0);

drop index if exists public.v1_accounts_payment_reference_project_uq;
create unique index if not exists v1_accounts_payment_reference_sequence_uq
  on public.v1_accounts_client_payments (
    project_id, lower(btrim(payment_reference)), reference_sequence
  );

drop index if exists public.v1_accounts_one_pdc_payment_uq;
create unique index if not exists v1_accounts_one_pdc_clearing_uq
  on public.v1_accounts_client_payments (pdc_id, pdc_clear_sequence)
  where pdc_id is not null and entry_kind = 'receipt';

-- Picks the next sequence only when the latest entry was reversed. Otherwise it
-- reuses the same one, so the unique index refuses the duplicate. A race between
-- two writers computes the same value and fails the same way.
create or replace function public.v1_accounts_client_payment_sequences()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_latest public.v1_accounts_client_payments%rowtype;
begin
  select * into v_latest
  from public.v1_accounts_client_payments payment
  where payment.project_id = new.project_id
    and lower(btrim(payment.payment_reference))
      = lower(btrim(new.payment_reference))
  order by payment.reference_sequence desc
  limit 1;
  if found then
    new.reference_sequence := v_latest.reference_sequence + case
      when v_latest.entry_kind = 'receipt' and exists (
        select 1 from public.v1_accounts_client_payments reversal
        where reversal.original_payment_id = v_latest.id
      ) then 1 else 0 end;
  end if;

  if new.pdc_id is not null and new.entry_kind = 'receipt' then
    select * into v_latest
    from public.v1_accounts_client_payments payment
    where payment.pdc_id = new.pdc_id and payment.entry_kind = 'receipt'
    order by payment.pdc_clear_sequence desc
    limit 1;
    if found then
      new.pdc_clear_sequence := v_latest.pdc_clear_sequence + case
        when exists (
          select 1 from public.v1_accounts_client_payments reversal
          where reversal.original_payment_id = v_latest.id
        ) then 1 else 0 end;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists v1_accounts_payment_sequences
  on public.v1_accounts_client_payments;
create trigger v1_accounts_payment_sequences
  before insert on public.v1_accounts_client_payments
  for each row execute function public.v1_accounts_client_payment_sequences();

create or replace function public.v1_accounts_client_reversal_reference(
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
    select 1 from public.v1_accounts_client_payments payment
    where payment.project_id = p_project_id
      and lower(btrim(payment.payment_reference)) = lower(v_candidate)
  ) loop
    v_attempt := v_attempt + 1;
    v_candidate := v_base || '-' || v_attempt::text;
  end loop;
  return v_candidate;
end;
$$;

create or replace function public.v1_accounts_transition_invoice(
  p_command text,p_project_id uuid,p_invoice_id uuid,p_expected_version integer,p_target text,p_reason text,p_idempotency_key uuid
)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_invoice public.v1_accounts_client_invoices%rowtype; v_payload jsonb; v_existing jsonb; v_before jsonb; v_response jsonb; v_now timestamptz:=clock_timestamp();
begin
  perform public.v1_accounts_require_capability(p_project_id,'manage_client_invoices');
  if nullif(btrim(p_reason),'') is null then raise exception 'R39_ACCOUNTS_REASON_REQUIRED' using errcode='22023'; end if;
  v_payload:=jsonb_build_object('project_id',p_project_id,'invoice_id',p_invoice_id,'expected_version',p_expected_version,'target_status',p_target,'reason',btrim(p_reason));
  v_existing:=public.v1_idempotency_get_or_claim(p_command,p_idempotency_key,v_payload);
  if v_existing is not null then return v_existing||jsonb_build_object('replayed',true); end if;
  select * into v_invoice from public.v1_accounts_client_invoices where id=p_invoice_id and project_id=p_project_id for update;
  if not found then raise exception 'R39_ACCOUNTS_INVOICE_NOT_FOUND' using errcode='P0002'; end if;
  if v_invoice.record_version<>p_expected_version then raise exception 'R39_ACCOUNTS_VERSION_CONFLICT' using errcode='40001'; end if;
  if p_target='under_certification' and v_invoice.status<>'submitted' then raise exception 'R39_ACCOUNTS_INVALID_INVOICE_TRANSITION' using errcode='55000'; end if;
  if p_target='returned' and v_invoice.status not in ('submitted','under_certification') then raise exception 'R39_ACCOUNTS_INVALID_INVOICE_TRANSITION' using errcode='55000'; end if;
  if p_target='cancelled' then
    if v_invoice.status in ('cancelled','paid') or public.v1_accounts_invoice_certified_ex_vat(p_invoice_id)<>0
      or public.v1_accounts_invoice_paid_amount(p_invoice_id)<>0
      or exists(select 1 from public.v1_accounts_client_pdcs where invoice_id=p_invoice_id and status in ('expected','received','deposited','cleared')) then
      raise exception 'R39_ACCOUNTS_INVOICE_HAS_DOWNSTREAM_FACTS' using errcode='55000'; end if;
  end if;
  v_before:=public.v1_accounts_invoice_snapshot(p_invoice_id);
  update public.v1_accounts_client_invoices set status=p_target,record_version=record_version+1,updated_at=v_now,
    returned_at=case when p_target='returned' then v_now else returned_at end,
    returned_by_auth_user_id=case when p_target='returned' then auth.uid() else returned_by_auth_user_id end,
    return_reason=case when p_target='returned' then btrim(p_reason) else return_reason end,
    cancelled_at=case when p_target='cancelled' then v_now else cancelled_at end,
    cancelled_by_auth_user_id=case when p_target='cancelled' then auth.uid() else cancelled_by_auth_user_id end,
    cancellation_reason=case when p_target='cancelled' then btrim(p_reason) else cancellation_reason end where id=p_invoice_id;
  if p_target='cancelled' then
    update public.v1_accounts_client_claims set status='cancelled',record_version=record_version+1,cancelled_at=v_now,
      cancelled_by_auth_user_id=auth.uid(),cancellation_reason=btrim(p_reason),updated_at=v_now where id=v_invoice.claim_id;
  end if;
  perform public.v1_write_audit_event('accounts.client_invoice.'||p_target,'accounts_client_invoice',p_invoice_id,p_project_id,v_before,public.v1_accounts_invoice_snapshot(p_invoice_id),btrim(p_reason),p_idempotency_key);
  v_response:=jsonb_build_object('schema_version',3,'replayed',false,'project_id',p_project_id,'entity_id',p_invoice_id,'invoice_id',p_invoice_id,'record_version',p_expected_version+1,'status',p_target,'updated_at',v_now);
  perform public.v1_complete_idempotency(p_command,p_idempotency_key,v_response); return v_response;
end;
$$;

create or replace function public.v1_accounts_receivables_commands(
  p_project_id uuid
)
returns jsonb
language sql stable security definer set search_path=''
as $$
  select jsonb_build_object(
    'create_claim_draft', public.v1_current_user_has_capability('prepare_client_claim',p_project_id)
      and public.v1_current_user_has_capability('view_project_commercial_values',p_project_id),
    'edit_claim_draft', public.v1_current_user_has_capability('prepare_client_claim',p_project_id),
    'submit_claim_to_accounts', public.v1_current_user_has_capability('prepare_client_claim',p_project_id),
    'cancel_claim', public.v1_current_user_has_capability('prepare_client_claim',p_project_id)
      or public.v1_current_user_has_capability('manage_client_invoices',p_project_id),
    'create_invoice_draft', public.v1_current_user_has_capability('manage_client_invoices',p_project_id),
    'submit_invoice', public.v1_current_user_has_capability('manage_client_invoices',p_project_id),
    'return_invoice', public.v1_current_user_has_capability('manage_client_invoices',p_project_id),
    'cancel_invoice', public.v1_current_user_has_capability('manage_client_invoices',p_project_id),
    'record_certification', public.v1_current_user_has_capability('record_client_certification',p_project_id),
    'record_payment', public.v1_current_user_has_capability('record_client_payment',p_project_id),
    'reverse_payment', public.v1_current_user_has_capability('record_client_payment',p_project_id),
    'create_pdc', public.v1_current_user_has_capability('manage_pdc',p_project_id),
    'transition_pdc', public.v1_current_user_has_capability('manage_pdc',p_project_id),
    'replace_pdc', public.v1_current_user_has_capability('manage_pdc',p_project_id),
    'edit_pdc', public.v1_current_user_has_capability('manage_pdc',p_project_id),
    'correct_payment', public.v1_current_user_has_capability('record_client_payment',p_project_id),
    'correct_certification', public.v1_current_user_has_capability('record_client_certification',p_project_id)
  );
$$;

-- Every step of a cheque can now be walked back. Moving backwards needs a reason.
create or replace function public.v1_transition_client_pdc(
  p_project_id uuid,p_pdc_id uuid,p_expected_version integer,p_new_status text,
  p_action_date date,p_reason text,p_clearance_payment_reference text,p_idempotency_key uuid
)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_actor uuid:=auth.uid();v_role text:=public.v1_current_role();v_exact text;
  v_pdc public.v1_accounts_client_pdcs%rowtype;v_invoice public.v1_accounts_client_invoices%rowtype;
  v_original public.v1_accounts_client_payments%rowtype;
  v_payment_id uuid;v_event_id uuid;v_allowed boolean:=false;v_backward boolean:=false;v_payload jsonb;v_existing jsonb;v_response jsonb;
  v_now timestamptz:=clock_timestamp();v_status text;v_payable numeric;
begin
  v_exact:=public.v1_accounts_require_capability(p_project_id,'manage_pdc');
  if p_action_date is null or p_new_status not in ('expected','received','deposited','cleared','returned','bounced','cancelled') then
    raise exception 'R39_ACCOUNTS_INVALID_PDC_TRANSITION' using errcode='22023';end if;
  if p_new_status in ('returned','bounced','cancelled') and nullif(btrim(p_reason),'') is null then raise exception 'R39_ACCOUNTS_REASON_REQUIRED' using errcode='22023';end if;
  if p_new_status='cleared' and nullif(btrim(p_clearance_payment_reference),'') is null then raise exception 'R39_ACCOUNTS_CLEARANCE_REFERENCE_REQUIRED' using errcode='22023';end if;
  v_payload:=jsonb_build_object('project_id',p_project_id,'pdc_id',p_pdc_id,'expected_version',p_expected_version,'new_status',p_new_status,
    'action_date',p_action_date,'reason',nullif(btrim(p_reason),''),'clearance_payment_reference',nullif(btrim(p_clearance_payment_reference),''));
  v_existing:=public.v1_idempotency_get_or_claim('v1_transition_client_pdc',p_idempotency_key,v_payload);
  if v_existing is not null then return v_existing||jsonb_build_object('replayed',true);end if;
  select * into v_pdc from public.v1_accounts_client_pdcs where id=p_pdc_id and project_id=p_project_id for update;
  if not found then raise exception 'R39_ACCOUNTS_PDC_NOT_FOUND' using errcode='P0002';end if;
  if v_pdc.record_version<>p_expected_version then raise exception 'R39_ACCOUNTS_VERSION_CONFLICT' using errcode='40001';end if;
  v_allowed:=case v_pdc.status
    when 'expected' then p_new_status in ('received','cancelled')
    when 'received' then p_new_status in ('deposited','returned','bounced','cancelled','expected')
    when 'deposited' then p_new_status in ('cleared','returned','bounced','received')
    when 'cleared' then p_new_status in ('deposited','returned','bounced')
    when 'returned' then p_new_status in ('received','cancelled')
    when 'bounced' then p_new_status in ('received','cancelled')
    when 'cancelled' then p_new_status='expected'
    else false end;
  if not v_allowed then raise exception 'R39_ACCOUNTS_INVALID_PDC_TRANSITION' using errcode='55000';end if;
  v_backward:=(v_pdc.status='received' and p_new_status='expected') or (v_pdc.status='deposited' and p_new_status='received')
    or v_pdc.status in ('cleared','returned','bounced','cancelled');
  if v_backward and nullif(btrim(p_reason),'') is null then raise exception 'R39_ACCOUNTS_REASON_REQUIRED' using errcode='22023';end if;
  select * into v_invoice from public.v1_accounts_client_invoices where id=v_pdc.invoice_id for update;
  v_payable:=public.v1_accounts_invoice_certified_incl_vat(v_invoice.id)-v_invoice.retention_snapshot-public.v1_accounts_invoice_paid_amount(v_invoice.id);
  -- A cheque coming back into play must still fit what is left to collect.
  if v_pdc.status in ('returned','bounced','cancelled') and p_new_status in ('expected','received') then
    if v_invoice.status in ('draft','returned','cancelled','paid') then raise exception 'R39_ACCOUNTS_INVOICE_NOT_PAYABLE' using errcode='55000';end if;
    if v_pdc.amount>greatest(v_payable-public.v1_accounts_invoice_pdc_exposure(v_invoice.id),0) then
      raise exception 'R39_ACCOUNTS_PDC_EXPOSURE_CAP_EXCEEDED' using errcode='23514';end if;
  end if;
  if p_new_status='cleared' then
    if not public.v1_current_user_has_capability('record_client_payment',p_project_id) then raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode='42501';end if;
    if v_pdc.amount>v_payable then raise exception 'R39_ACCOUNTS_PAYMENT_CAP_EXCEEDED' using errcode='23514';end if;
    v_payment_id:=gen_random_uuid();
    insert into public.v1_accounts_client_payments(id,project_id,invoice_id,entry_kind,pdc_id,payment_date,payment_method,payment_reference,amount,reason,
      actor_auth_user_id,actor_role,actor_exact_role,idempotency_key,created_at)
    values(v_payment_id,p_project_id,v_invoice.id,'receipt',p_pdc_id,p_action_date,'PDC',btrim(p_clearance_payment_reference),v_pdc.amount,
      coalesce(nullif(btrim(p_reason),''),'PDC cleared'),v_actor,v_role,v_exact,p_idempotency_key,v_now);
    update public.v1_accounts_client_invoices set record_version=record_version+1,updated_at=v_now where id=v_invoice.id;
    v_status:=public.v1_accounts_refresh_invoice_status(v_invoice.id);
  elsif v_pdc.status='cleared' then
    -- Undo clearing: the money it brought in comes back out in the same step.
    if not public.v1_current_user_has_capability('record_client_payment',p_project_id) then raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode='42501';end if;
    select payment.* into v_original from public.v1_accounts_client_payments payment
    where payment.pdc_id=p_pdc_id and payment.entry_kind='receipt'
      and not exists(select 1 from public.v1_accounts_client_payments reversal where reversal.original_payment_id=payment.id)
    order by payment.pdc_clear_sequence desc limit 1 for update;
    if not found then raise exception 'R39_ACCOUNTS_PAYMENT_NOT_REVERSIBLE' using errcode='55000';end if;
    v_payment_id:=gen_random_uuid();
    insert into public.v1_accounts_client_payments(id,project_id,invoice_id,entry_kind,original_payment_id,payment_date,payment_method,payment_reference,amount,reason,
      actor_auth_user_id,actor_role,actor_exact_role,idempotency_key,created_at)
    values(v_payment_id,p_project_id,v_invoice.id,'reversal',v_original.id,p_action_date,'reversal',
      public.v1_accounts_client_reversal_reference(p_project_id,v_original.payment_reference),v_original.amount,btrim(p_reason),v_actor,v_role,v_exact,p_idempotency_key,v_now);
    update public.v1_accounts_client_invoices set record_version=record_version+1,updated_at=v_now where id=v_invoice.id;
    v_status:=public.v1_accounts_refresh_invoice_status(v_invoice.id);
  else v_status:=v_invoice.status;end if;
  update public.v1_accounts_client_pdcs set status=p_new_status,record_version=record_version+1,updated_at=v_now,
    received_date=case when p_new_status='expected' then null
      when p_new_status='received' and v_pdc.status<>'deposited' then p_action_date else received_date end,
    action_required=p_new_status in ('returned','bounced'),last_action_reason=case when p_new_status in ('returned','bounced') then btrim(p_reason) else null end where id=p_pdc_id;
  v_event_id:=public.v1_accounts_append_pdc_event(p_pdc_id,v_pdc.status,p_new_status,p_action_date,p_reason,v_payment_id,p_idempotency_key);
  perform public.v1_write_audit_event('accounts.client_pdc.'||p_new_status,'accounts_client_pdc',p_pdc_id,p_project_id,
    jsonb_build_object('status',v_pdc.status,'record_version',v_pdc.record_version),jsonb_build_object('status',p_new_status,'record_version',p_expected_version+1,'event_id',v_event_id,'linked_payment_id',v_payment_id),nullif(btrim(p_reason),''),p_idempotency_key);
  v_response:=jsonb_build_object('schema_version',3,'replayed',false,'project_id',p_project_id,'entity_id',p_pdc_id,'pdc_id',p_pdc_id,'invoice_id',v_invoice.id,
    'record_version',p_expected_version+1,'status',p_new_status,'linked_payment_id',v_payment_id,'invoice_status',v_status,'updated_at',v_now);
  perform public.v1_complete_idempotency('v1_transition_client_pdc',p_idempotency_key,v_response);return v_response;
exception when unique_violation then raise exception 'R39_ACCOUNTS_DUPLICATE_PAYMENT_REFERENCE' using errcode='23505';
end;
$$;

-- The reference becomes optional and the cheque stays in step with its receipt.
drop function if exists public.v1_reverse_client_payment(uuid,uuid,integer,uuid,date,text,text,uuid);
create or replace function public.v1_reverse_client_payment(
  p_project_id uuid,p_invoice_id uuid,p_expected_version integer,p_original_payment_id uuid,
  p_reversal_date date,p_reversal_reference text,p_reason text,p_idempotency_key uuid,
  p_cheque_outcome text default null
)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_actor uuid:=auth.uid();v_role text:=public.v1_current_role();v_exact text;
  v_invoice public.v1_accounts_client_invoices%rowtype;v_original public.v1_accounts_client_payments%rowtype;v_pdc public.v1_accounts_client_pdcs%rowtype;
  v_pdc_id uuid;v_outcome text:=coalesce(nullif(btrim(p_cheque_outcome),''),'deposited');
  v_payment_id uuid:=gen_random_uuid();v_payload jsonb;v_existing jsonb;v_before jsonb;v_response jsonb;v_status text;v_now timestamptz:=clock_timestamp();
begin
  v_exact:=public.v1_accounts_require_capability(p_project_id,'record_client_payment');
  if p_reversal_date is null or nullif(btrim(p_reason),'') is null then
    raise exception 'R39_ACCOUNTS_PAYMENT_REVERSAL_FIELDS_REQUIRED' using errcode='22023';end if;
  if v_outcome not in ('deposited','returned','bounced') then raise exception 'R39_ACCOUNTS_INVALID_PDC_TRANSITION' using errcode='22023';end if;
  v_payload:=jsonb_build_object('project_id',p_project_id,'invoice_id',p_invoice_id,'expected_version',p_expected_version,
    'original_payment_id',p_original_payment_id,'reversal_date',p_reversal_date,'reversal_reference',nullif(btrim(p_reversal_reference),''),'reason',btrim(p_reason),'cheque_outcome',v_outcome);
  v_existing:=public.v1_idempotency_get_or_claim('v1_reverse_client_payment',p_idempotency_key,v_payload);
  if v_existing is not null then return v_existing||jsonb_build_object('replayed',true);end if;
  -- Cheque first, then invoice: the same order the cheque command locks them in.
  select payment.pdc_id into v_pdc_id from public.v1_accounts_client_payments payment where payment.id=p_original_payment_id and payment.project_id=p_project_id;
  if v_pdc_id is not null then select * into v_pdc from public.v1_accounts_client_pdcs where id=v_pdc_id for update;end if;
  select * into v_invoice from public.v1_accounts_client_invoices where id=p_invoice_id and project_id=p_project_id for update;
  if not found then raise exception 'R39_ACCOUNTS_INVOICE_NOT_FOUND' using errcode='P0002';end if;
  if v_invoice.record_version<>p_expected_version then raise exception 'R39_ACCOUNTS_VERSION_CONFLICT' using errcode='40001';end if;
  select * into v_original from public.v1_accounts_client_payments where id=p_original_payment_id and project_id=p_project_id and invoice_id=p_invoice_id and entry_kind='receipt' for update;
  if not found or exists(select 1 from public.v1_accounts_client_payments where original_payment_id=p_original_payment_id) then
    raise exception 'R39_ACCOUNTS_PAYMENT_NOT_REVERSIBLE' using errcode='55000';end if;
  if v_pdc_id is not null and v_outcome in ('returned','bounced') and not public.v1_current_user_has_capability('manage_pdc',p_project_id) then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode='42501';end if;
  v_before:=public.v1_accounts_invoice_snapshot(p_invoice_id);
  insert into public.v1_accounts_client_payments(id,project_id,invoice_id,entry_kind,original_payment_id,payment_date,payment_method,payment_reference,amount,reason,
    actor_auth_user_id,actor_role,actor_exact_role,idempotency_key,created_at)
  values(v_payment_id,p_project_id,p_invoice_id,'reversal',p_original_payment_id,p_reversal_date,'reversal',
    coalesce(nullif(btrim(p_reversal_reference),''),public.v1_accounts_client_reversal_reference(p_project_id,v_original.payment_reference)),
    v_original.amount,btrim(p_reason),v_actor,v_role,v_exact,p_idempotency_key,v_now);
  update public.v1_accounts_client_invoices set record_version=record_version+1,updated_at=v_now where id=p_invoice_id;
  v_status:=public.v1_accounts_refresh_invoice_status(p_invoice_id);
  if v_pdc_id is not null and v_pdc.status='cleared' then
    update public.v1_accounts_client_pdcs set status=v_outcome,record_version=record_version+1,updated_at=v_now,
      action_required=v_outcome in ('returned','bounced'),last_action_reason=case when v_outcome in ('returned','bounced') then btrim(p_reason) else null end where id=v_pdc_id;
    perform public.v1_accounts_append_pdc_event(v_pdc_id,'cleared',v_outcome,p_reversal_date,p_reason,v_payment_id,p_idempotency_key);
  end if;
  perform public.v1_write_audit_event('accounts.client_payment.reversed','accounts_client_payment',v_payment_id,p_project_id,v_before,public.v1_accounts_invoice_snapshot(p_invoice_id),btrim(p_reason),p_idempotency_key);
  v_response:=jsonb_build_object('schema_version',3,'replayed',false,'project_id',p_project_id,'entity_id',v_payment_id,'payment_id',v_payment_id,'original_payment_id',p_original_payment_id,
    'invoice_id',p_invoice_id,'invoice_record_version',p_expected_version+1,'status',v_status,'amount',v_original.amount::text,'pdc_id',v_pdc_id,'updated_at',v_now);
  perform public.v1_complete_idempotency('v1_reverse_client_payment',p_idempotency_key,v_response);return v_response;
exception when unique_violation then raise exception 'R39_ACCOUNTS_DUPLICATE_PAYMENT_REFERENCE' using errcode='23505';
end;
$$;

-- Edit a payment: one reversal and one new receipt, together or not at all.
create or replace function public.v1_correct_client_payment(
  p_project_id uuid,p_invoice_id uuid,p_expected_version integer,p_original_payment_id uuid,
  p_payment_date date,p_payment_method text,p_payment_reference text,p_amount text,p_reason text,p_idempotency_key uuid
)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_actor uuid:=auth.uid();v_role text:=public.v1_current_role();v_exact text;
  v_invoice public.v1_accounts_client_invoices%rowtype;v_original public.v1_accounts_client_payments%rowtype;v_pdc public.v1_accounts_client_pdcs%rowtype;
  v_pdc_id uuid;v_amount numeric;v_method text;v_reversal_id uuid:=gen_random_uuid();v_payment_id uuid:=gen_random_uuid();
  v_payload jsonb;v_existing jsonb;v_before jsonb;v_response jsonb;v_status text;v_now timestamptz:=clock_timestamp();
begin
  v_exact:=public.v1_accounts_require_capability(p_project_id,'record_client_payment');
  if p_payment_date is null or nullif(btrim(p_payment_method),'') is null or nullif(btrim(p_payment_reference),'') is null then
    raise exception 'R39_ACCOUNTS_PAYMENT_IDENTITY_REQUIRED' using errcode='22023';end if;
  if nullif(btrim(p_reason),'') is null then raise exception 'R39_ACCOUNTS_REASON_REQUIRED' using errcode='22023';end if;
  v_amount:=public.v1_accounts_parse_money_text(p_amount);if v_amount<=0 then raise exception 'R39_ACCOUNTS_INVALID_PAYMENT_AMOUNT' using errcode='22023';end if;
  v_payload:=jsonb_build_object('project_id',p_project_id,'invoice_id',p_invoice_id,'expected_version',p_expected_version,'original_payment_id',p_original_payment_id,
    'payment_date',p_payment_date,'payment_method',btrim(p_payment_method),'payment_reference',btrim(p_payment_reference),'amount',v_amount::text,'reason',btrim(p_reason));
  v_existing:=public.v1_idempotency_get_or_claim('v1_correct_client_payment',p_idempotency_key,v_payload);
  if v_existing is not null then return v_existing||jsonb_build_object('replayed',true);end if;
  select payment.pdc_id into v_pdc_id from public.v1_accounts_client_payments payment where payment.id=p_original_payment_id and payment.project_id=p_project_id;
  if v_pdc_id is not null then select * into v_pdc from public.v1_accounts_client_pdcs where id=v_pdc_id for update;end if;
  select * into v_invoice from public.v1_accounts_client_invoices where id=p_invoice_id and project_id=p_project_id for update;
  if not found then raise exception 'R39_ACCOUNTS_INVOICE_NOT_FOUND' using errcode='P0002';end if;
  if v_invoice.record_version<>p_expected_version then raise exception 'R39_ACCOUNTS_VERSION_CONFLICT' using errcode='40001';end if;
  select * into v_original from public.v1_accounts_client_payments where id=p_original_payment_id and project_id=p_project_id and invoice_id=p_invoice_id and entry_kind='receipt' for update;
  if not found or exists(select 1 from public.v1_accounts_client_payments where original_payment_id=p_original_payment_id) then
    raise exception 'R39_ACCOUNTS_PAYMENT_NOT_REVERSIBLE' using errcode='55000';end if;
  -- A cheque's receipt is for exactly the cheque; change the cheque to change it.
  v_method:=btrim(p_payment_method);
  if v_pdc_id is not null then
    v_method:=v_original.payment_method;
    if v_amount<>v_pdc.amount then raise exception 'R39_ACCOUNTS_PAYMENT_MUST_MATCH_CHEQUE' using errcode='23514';end if;
  end if;
  if public.v1_accounts_invoice_paid_amount(p_invoice_id)-v_original.amount+v_amount
      >public.v1_accounts_invoice_certified_incl_vat(p_invoice_id)-v_invoice.retention_snapshot then
    raise exception 'R39_ACCOUNTS_PAYMENT_CAP_EXCEEDED' using errcode='23514';end if;
  v_before:=public.v1_accounts_invoice_snapshot(p_invoice_id);
  insert into public.v1_accounts_client_payments(id,project_id,invoice_id,entry_kind,original_payment_id,payment_date,payment_method,payment_reference,amount,reason,
    actor_auth_user_id,actor_role,actor_exact_role,idempotency_key,created_at)
  values(v_reversal_id,p_project_id,p_invoice_id,'reversal',p_original_payment_id,p_payment_date,'reversal',
    public.v1_accounts_client_reversal_reference(p_project_id,v_original.payment_reference),v_original.amount,btrim(p_reason),v_actor,v_role,v_exact,p_idempotency_key,v_now);
  insert into public.v1_accounts_client_payments(id,project_id,invoice_id,entry_kind,pdc_id,payment_date,payment_method,payment_reference,amount,reason,
    actor_auth_user_id,actor_role,actor_exact_role,idempotency_key,created_at)
  values(v_payment_id,p_project_id,p_invoice_id,'receipt',v_pdc_id,p_payment_date,v_method,btrim(p_payment_reference),v_amount,btrim(p_reason),v_actor,v_role,v_exact,p_idempotency_key,v_now);
  update public.v1_accounts_client_invoices set record_version=record_version+1,updated_at=v_now where id=p_invoice_id;
  v_status:=public.v1_accounts_refresh_invoice_status(p_invoice_id);
  perform public.v1_write_audit_event('accounts.client_payment.corrected','accounts_client_payment',v_payment_id,p_project_id,v_before,public.v1_accounts_invoice_snapshot(p_invoice_id),btrim(p_reason),p_idempotency_key);
  v_response:=jsonb_build_object('schema_version',3,'replayed',false,'project_id',p_project_id,'entity_id',v_payment_id,'payment_id',v_payment_id,'reversal_id',v_reversal_id,
    'original_payment_id',p_original_payment_id,'invoice_id',p_invoice_id,'invoice_record_version',p_expected_version+1,'status',v_status,'amount',v_amount::text,'updated_at',v_now);
  perform public.v1_complete_idempotency('v1_correct_client_payment',p_idempotency_key,v_response);return v_response;
exception when unique_violation then raise exception 'R39_ACCOUNTS_DUPLICATE_PAYMENT_REFERENCE' using errcode='23505';
end;
$$;

-- Edit a certification. Zero undoes it. It may not drop below money already in.
create or replace function public.v1_correct_client_certification(
  p_project_id uuid,p_invoice_id uuid,p_expected_version integer,
  p_certification_reference text,p_certification_date date,p_certified_ex_vat text,p_reason text,p_idempotency_key uuid
)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_actor uuid:=auth.uid();v_role text:=public.v1_current_role();v_exact text;
  v_invoice public.v1_accounts_client_invoices%rowtype;v_amount numeric;v_vat numeric;v_total numeric;v_revision integer;v_cert_id uuid:=gen_random_uuid();
  v_payload jsonb;v_existing jsonb;v_before jsonb;v_response jsonb;v_status text;v_now timestamptz:=clock_timestamp();
begin
  v_exact:=public.v1_accounts_require_capability(p_project_id,'record_client_certification');
  if nullif(btrim(p_certification_reference),'') is null or p_certification_date is null then
    raise exception 'R39_ACCOUNTS_CERTIFICATION_IDENTITY_REQUIRED' using errcode='22023';end if;
  if nullif(btrim(p_reason),'') is null then raise exception 'R39_ACCOUNTS_REASON_REQUIRED' using errcode='22023';end if;
  v_amount:=public.v1_accounts_parse_money_text(p_certified_ex_vat);
  if v_amount<0 then raise exception 'R39_ACCOUNTS_INVALID_CERTIFICATION_AMOUNT' using errcode='22023';end if;
  v_payload:=jsonb_build_object('project_id',p_project_id,'invoice_id',p_invoice_id,'expected_version',p_expected_version,
    'certification_reference',btrim(p_certification_reference),'certification_date',p_certification_date,'certified_ex_vat',v_amount::text,'reason',btrim(p_reason));
  v_existing:=public.v1_idempotency_get_or_claim('v1_correct_client_certification',p_idempotency_key,v_payload);
  if v_existing is not null then return v_existing||jsonb_build_object('replayed',true);end if;
  select * into v_invoice from public.v1_accounts_client_invoices where id=p_invoice_id and project_id=p_project_id for update;
  if not found then raise exception 'R39_ACCOUNTS_INVOICE_NOT_FOUND' using errcode='P0002';end if;
  if v_invoice.status in ('draft','returned','cancelled') then raise exception 'R39_ACCOUNTS_INVOICE_NOT_CERTIFIABLE' using errcode='55000';end if;
  if v_invoice.record_version<>p_expected_version then raise exception 'R39_ACCOUNTS_VERSION_CONFLICT' using errcode='40001';end if;
  if not exists(select 1 from public.v1_accounts_client_certifications where invoice_id=p_invoice_id) then
    raise exception 'R39_ACCOUNTS_CERTIFICATION_NOT_FOUND' using errcode='P0002';end if;
  if v_amount>v_invoice.claimed_ex_vat then raise exception 'R39_ACCOUNTS_CERTIFICATION_CAP_INVALID' using errcode='23514';end if;
  select coalesce(max(revision_number),0)+1 into v_revision from public.v1_accounts_client_certifications where invoice_id=p_invoice_id;
  v_vat:=round(v_amount*v_invoice.vat_rate_percent_snapshot/100,2);v_total:=v_amount+v_vat;
  if public.v1_accounts_invoice_paid_amount(p_invoice_id)+public.v1_accounts_invoice_pdc_exposure(p_invoice_id)>greatest(v_total-v_invoice.retention_snapshot,0) then
    raise exception 'R39_ACCOUNTS_CERTIFICATION_BELOW_RECEIVED' using errcode='23514';end if;
  v_before:=public.v1_accounts_invoice_snapshot(p_invoice_id);
  insert into public.v1_accounts_client_certifications(id,project_id,invoice_id,revision_number,certification_reference,
    certification_date,certified_ex_vat,certified_vat,certified_incl_vat,difference_reason,
    actor_auth_user_id,actor_role,actor_exact_role,idempotency_key,created_at)
  values(v_cert_id,p_project_id,p_invoice_id,v_revision,btrim(p_certification_reference),p_certification_date,
    v_amount,v_vat,v_total,btrim(p_reason),v_actor,v_role,v_exact,p_idempotency_key,v_now);
  update public.v1_accounts_client_invoices set record_version=record_version+1,updated_at=v_now where id=p_invoice_id;
  v_status:=public.v1_accounts_refresh_invoice_status(p_invoice_id);
  perform public.v1_write_audit_event('accounts.client_certification.corrected','accounts_client_certification',v_cert_id,p_project_id,v_before,public.v1_accounts_invoice_snapshot(p_invoice_id),btrim(p_reason),p_idempotency_key);
  v_response:=jsonb_build_object('schema_version',3,'replayed',false,'project_id',p_project_id,'entity_id',v_cert_id,'certification_id',v_cert_id,'invoice_id',p_invoice_id,
    'revision_number',v_revision,'invoice_record_version',p_expected_version+1,'status',v_status,'certified_ex_vat',v_amount::text,'updated_at',v_now);
  perform public.v1_complete_idempotency('v1_correct_client_certification',p_idempotency_key,v_response);return v_response;
end;
$$;

-- Edit a cheque's details. A cleared cheque has its clearing undone first.
create or replace function public.v1_update_client_pdc(
  p_project_id uuid,p_pdc_id uuid,p_expected_version integer,p_cheque_number text,
  p_cheque_date date,p_amount text,p_bank_name text,p_reason text,p_idempotency_key uuid
)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_old public.v1_accounts_client_pdcs%rowtype;v_invoice public.v1_accounts_client_invoices%rowtype;
  v_amount numeric;v_payload jsonb;v_existing jsonb;v_response jsonb;v_now timestamptz:=clock_timestamp();
begin
  perform public.v1_accounts_require_capability(p_project_id,'manage_pdc');
  if nullif(btrim(p_cheque_number),'') is null or p_cheque_date is null then raise exception 'R39_ACCOUNTS_PDC_REPLACEMENT_FIELDS_REQUIRED' using errcode='22023';end if;
  if nullif(btrim(p_reason),'') is null then raise exception 'R39_ACCOUNTS_REASON_REQUIRED' using errcode='22023';end if;
  v_amount:=public.v1_accounts_parse_money_text(p_amount);if v_amount<=0 then raise exception 'R39_ACCOUNTS_INVALID_PDC_AMOUNT' using errcode='22023';end if;
  v_payload:=jsonb_build_object('project_id',p_project_id,'pdc_id',p_pdc_id,'expected_version',p_expected_version,'cheque_number',btrim(p_cheque_number),
    'cheque_date',p_cheque_date,'amount',v_amount::text,'bank_name',nullif(btrim(p_bank_name),''),'reason',btrim(p_reason));
  v_existing:=public.v1_idempotency_get_or_claim('v1_update_client_pdc',p_idempotency_key,v_payload);
  if v_existing is not null then return v_existing||jsonb_build_object('replayed',true);end if;
  select * into v_old from public.v1_accounts_client_pdcs where id=p_pdc_id and project_id=p_project_id for update;
  if not found then raise exception 'R39_ACCOUNTS_PDC_NOT_FOUND' using errcode='P0002';end if;
  if v_old.record_version<>p_expected_version then raise exception 'R39_ACCOUNTS_VERSION_CONFLICT' using errcode='40001';end if;
  if v_old.status not in ('expected','received','deposited','returned','bounced','cancelled') then raise exception 'R39_ACCOUNTS_PDC_NOT_EDITABLE' using errcode='55000';end if;
  select * into v_invoice from public.v1_accounts_client_invoices where id=v_old.invoice_id for update;
  if v_old.status in ('expected','received','deposited') and v_amount>greatest(public.v1_accounts_invoice_certified_incl_vat(v_old.invoice_id)-v_invoice.retention_snapshot
      -public.v1_accounts_invoice_paid_amount(v_old.invoice_id)-public.v1_accounts_invoice_pdc_exposure(v_old.invoice_id)+v_old.amount,0) then
    raise exception 'R39_ACCOUNTS_PDC_EXPOSURE_CAP_EXCEEDED' using errcode='23514';end if;
  update public.v1_accounts_client_pdcs set cheque_number=btrim(p_cheque_number),cheque_date=p_cheque_date,amount=v_amount,bank_name=nullif(btrim(p_bank_name),''),
    record_version=record_version+1,updated_at=v_now where id=p_pdc_id;
  perform public.v1_accounts_append_pdc_event(p_pdc_id,v_old.status,v_old.status,v_now::date,p_reason,null,p_idempotency_key);
  perform public.v1_write_audit_event('accounts.client_pdc.edited','accounts_client_pdc',p_pdc_id,p_project_id,
    jsonb_build_object('cheque_number',v_old.cheque_number,'cheque_date',v_old.cheque_date,'amount',v_old.amount::text,'bank_name',v_old.bank_name,'record_version',v_old.record_version),
    jsonb_build_object('cheque_number',btrim(p_cheque_number),'cheque_date',p_cheque_date,'amount',v_amount::text,'bank_name',nullif(btrim(p_bank_name),''),'record_version',p_expected_version+1),btrim(p_reason),p_idempotency_key);
  v_response:=jsonb_build_object('schema_version',3,'replayed',false,'project_id',p_project_id,'entity_id',p_pdc_id,'pdc_id',p_pdc_id,'invoice_id',v_old.invoice_id,
    'record_version',p_expected_version+1,'status',v_old.status,'amount',v_amount::text,'updated_at',v_now);
  perform public.v1_complete_idempotency('v1_update_client_pdc',p_idempotency_key,v_response);return v_response;
exception when unique_violation then raise exception 'R39_ACCOUNTS_DUPLICATE_PDC_REFERENCE' using errcode='23505';
end;
$$;

revoke all on function public.v1_accounts_client_payment_sequences() from public,anon,authenticated;
revoke all on function public.v1_accounts_client_reversal_reference(uuid,text) from public,anon,authenticated;
revoke all on function public.v1_reverse_client_payment(uuid,uuid,integer,uuid,date,text,text,uuid,text) from public,anon;
revoke all on function public.v1_correct_client_payment(uuid,uuid,integer,uuid,date,text,text,text,text,uuid) from public,anon;
revoke all on function public.v1_correct_client_certification(uuid,uuid,integer,text,date,text,text,uuid) from public,anon;
revoke all on function public.v1_update_client_pdc(uuid,uuid,integer,text,date,text,text,text,uuid) from public,anon;
grant execute on function public.v1_reverse_client_payment(uuid,uuid,integer,uuid,date,text,text,uuid,text) to authenticated;
grant execute on function public.v1_correct_client_payment(uuid,uuid,integer,uuid,date,text,text,text,text,uuid) to authenticated;
grant execute on function public.v1_correct_client_certification(uuid,uuid,integer,text,date,text,text,uuid) to authenticated;
grant execute on function public.v1_update_client_pdc(uuid,uuid,integer,text,date,text,text,text,uuid) to authenticated;
