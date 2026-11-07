-- R39 Accounts Workspace V2 — office: Receipts & PDC total counts money once
--
-- The Receipts & PDC summary added up every listed row, so a cleared cheque was
-- counted again as the receipt it became, reversals added instead of subtracted,
-- and bounced or cancelled cheques counted too. An invoice paid AED 1,805,160 with
-- a AED 1,000,000 cheque showed AED 2,805,160.
--
-- This is a copy of the body in 20261106200000_accounts_v2_p6_retention_payable.sql
-- changing only that summary. Rows and every other section are unchanged.
-- Additive: CREATE OR REPLACE of one read. No table or row changes.
-- Rollback: re-apply the function from that migration.

create or replace function public.v1_get_accounts_office_register(
  p_section text,
  p_search text default null,
  p_status text default null,
  p_limit integer default 25,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_section text := lower(btrim(coalesce(p_section, '')));
  v_search text := nullif(btrim(p_search), '');
  v_status text := nullif(lower(btrim(p_status)), '');
  v_total integer;
  v_amount numeric;
  v_secondary numeric;
  v_balance numeric;
  v_action_count integer;
  v_items jsonb;
begin
  if not public.v1_accounts_portfolio_role_allowed() then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
  end if;
  if v_section not in (
    'claims', 'client_payments', 'supplier_bills',
    'due_schedule', 'documents', 'activity'
  ) then
    raise exception 'R39_ACCOUNTS_OFFICE_SECTION_INVALID'
      using errcode = '22023';
  end if;
  if p_limit not between 1 and 100 or p_offset < 0 then
    raise exception 'R39_ACCOUNTS_OFFICE_PAGE_INVALID'
      using errcode = '22023';
  end if;

  with project_context as materialized (
    select project.id,
      project.project_ref,
      project.name,
      project.project_site,
      baseline.currency_code,
      client.party_name as client_name,
      public.v1_current_user_has_capability(
        'view_project_accounts', project.id
      ) as can_view_accounts,
      public.v1_current_user_has_capability(
        'view_project_commercial_values', project.id
      ) as can_view_values,
      public.v1_current_user_has_capability(
        'view_supplier_costs', project.id
      ) as can_view_supplier
    from public.v1_projects project
    left join public.v1_accounts_project_commercial_profiles profile
      on profile.project_id = project.id
    left join public.v1_accounts_baseline_revisions baseline
      on baseline.id = profile.current_baseline_revision_id
    left join lateral (
      select party.party_name
      from public.v1_project_parties party
      where party.project_id = project.id and party.party_kind = 'client'
      order by party.party_order, party.created_at, party.id
      limit 1
    ) client on true
    where project.state <> 'archived'
  ), office_rows as materialized (
    -- Claims and their latest client invoice/certification/payment position.
    select 'claims'::text as section,
      claim.id as record_id,
      claim.project_id,
      project.project_ref as project_reference,
      project.name as project_name,
      project.client_name as party,
      claim.claim_reference as reference,
      invoice.invoice_reference as secondary_reference,
      coalesce(invoice.status, claim.status) as status,
      coalesce(lines.claimed_amount, 0)::numeric as amount,
      coalesce(invoice.certified_amount, 0)::numeric as secondary_amount,
      greatest(
        coalesce(lines.claimed_amount, 0) - coalesce(invoice.certified_amount, 0),
        0
      )::numeric as balance_amount,
      claim.claim_period_end as event_date,
      invoice.due_date,
      greatest(claim.updated_at, coalesce(invoice.updated_at, claim.updated_at)) as occurred_at,
      (
        claim.status = 'ready_for_accounts'
        or coalesce(invoice.status in (
          'submitted', 'under_certification', 'partially_certified', 'returned'
        ), false)
      ) as action_required,
      'claim'::text as record_kind,
      project.currency_code,
      jsonb_build_object(
        'claim_period_start', claim.claim_period_start,
        'claim_period_end', claim.claim_period_end,
        'is_stale', claim.is_stale,
        'record_version', claim.record_version
      ) as metadata
    from public.v1_accounts_client_claims claim
    join project_context project on project.id = claim.project_id
    left join lateral (
      select sum(line.claimed_amount) as claimed_amount
      from public.v1_accounts_client_claim_lines line
      where line.claim_id = claim.id
    ) lines on true
    left join lateral (
      select string_agg(item.invoice_reference, ', ' order by item.created_at) as invoice_reference,
        (array_agg(item.status order by item.updated_at desc, item.id desc))[1] as status,
        sum(public.v1_accounts_invoice_certified_incl_vat(item.id)) as certified_amount,
        max(item.due_date) as due_date,
        max(item.updated_at) as updated_at
      from public.v1_accounts_client_invoices item
      where item.claim_id = claim.id and item.status <> 'cancelled'
    ) invoice on true
    where v_section = 'claims'
      and project.can_view_accounts
      and project.can_view_values

    union all

    -- Append-only client receipts.
    select 'client_payments', payment.id, payment.project_id,
      project.project_ref, project.name, project.client_name,
      payment.payment_reference,
      invoice.invoice_reference,
      case when payment.entry_kind = 'reversal' then 'reversed' else 'received' end,
      payment.amount,
      null::numeric,
      null::numeric,
      payment.payment_date,
      null::date,
      payment.created_at,
      false,
      'client_payment',
      project.currency_code,
      jsonb_build_object(
        'entry_kind', payment.entry_kind,
        'payment_method', payment.payment_method,
        'reason', payment.reason
      )
    from public.v1_accounts_client_payments payment
    join project_context project on project.id = payment.project_id
    join public.v1_accounts_client_invoices invoice on invoice.id = payment.invoice_id
    where v_section = 'client_payments'
      and project.can_view_accounts
      and project.can_view_values

    union all

    -- Post-dated cheque register; this is not a bank-reconciliation ledger.
    select 'client_payments', pdc.id, pdc.project_id,
      project.project_ref, project.name, project.client_name,
      pdc.cheque_number,
      invoice.invoice_reference,
      pdc.status,
      pdc.amount,
      null::numeric,
      null::numeric,
      pdc.received_date,
      pdc.cheque_date,
      pdc.updated_at,
      pdc.action_required,
      'pdc',
      project.currency_code,
      jsonb_build_object(
        'bank_name', pdc.bank_name,
        'last_action_reason', pdc.last_action_reason,
        'record_version', pdc.record_version
      )
    from public.v1_accounts_client_pdcs pdc
    join project_context project on project.id = pdc.project_id
    join public.v1_accounts_client_invoices invoice on invoice.id = pdc.invoice_id
    where v_section = 'client_payments'
      and project.can_view_accounts
      and project.can_view_values

    union all

    -- Supplier bills require both Accounts admission and the distinct
    -- supplier-cost capability for this same project.
    select 'supplier_bills', bill.id, bill.project_id,
      project.project_ref, project.name, bill.supplier_name_snapshot,
      bill.supplier_invoice_reference,
      coalesce(bill.po_lpo_reference, bill.accepted_delivery_reference),
      case
        when bill.status = 'cancelled' then 'cancelled'
        when public.v1_accounts_supplier_paid_amount(bill.id) >= bill.total_incl_vat then 'paid'
        when public.v1_accounts_supplier_paid_amount(bill.id) > 0 then 'partially_paid'
        when bill.status = 'approved' then 'approved'
        when bill.explicit_mismatch_reason is not null then 'review'
        else 'draft'
      end,
      bill.total_incl_vat,
      public.v1_accounts_supplier_paid_amount(bill.id),
      greatest(
        bill.total_incl_vat - public.v1_accounts_supplier_paid_amount(bill.id),
        0
      ),
      bill.invoice_date,
      bill.due_date,
      bill.updated_at,
      (
        bill.status <> 'cancelled'
        and (
          bill.status <> 'approved'
          or public.v1_accounts_supplier_paid_amount(bill.id) < bill.total_incl_vat
            and bill.due_date <= current_date + 7
        )
      ),
      'supplier_bill',
      project.currency_code,
      jsonb_build_object(
        'match_status', public.v1_accounts_supplier_match_status(bill.id),
        'vat_amount', bill.vat_amount::text,
        'record_version', bill.record_version
      )
    from public.v1_accounts_supplier_bills bill
    join project_context project on project.id = bill.project_id
    where v_section = 'supplier_bills'
      and project.can_view_accounts
      and project.can_view_supplier

    union all

    -- Client receivable due facts.
    select 'due_schedule', invoice.id, invoice.project_id,
      project.project_ref, project.name, project.client_name,
      invoice.invoice_reference,
      claim.claim_reference,
      case
        when invoice.due_date < current_date then 'overdue'
        when invoice.due_date = current_date then 'due_today'
        when invoice.due_date <= current_date + 7 then 'due_soon'
        else 'current'
      end,
      public.v1_accounts_invoice_certified_incl_vat(invoice.id),
      public.v1_accounts_invoice_paid_amount(invoice.id),
      greatest(
        public.v1_accounts_invoice_certified_incl_vat(invoice.id)
          - public.v1_accounts_invoice_retention(invoice.id)
          - public.v1_accounts_invoice_paid_amount(invoice.id),
        0
      ),
      invoice.submission_date,
      invoice.due_date,
      invoice.updated_at,
      invoice.due_date <= current_date + invoice.reminder_lead_days_snapshot,
      'client_invoice_due',
      project.currency_code,
      jsonb_build_object('invoice_status', invoice.status)
    from public.v1_accounts_client_invoices invoice
    join project_context project on project.id = invoice.project_id
    join public.v1_accounts_client_claims claim on claim.id = invoice.claim_id
    where v_section = 'due_schedule'
      and invoice.status not in ('draft', 'returned', 'cancelled', 'paid')
      and invoice.due_date is not null
      and public.v1_accounts_invoice_certified_incl_vat(invoice.id)
        - public.v1_accounts_invoice_retention(invoice.id)
        > public.v1_accounts_invoice_paid_amount(invoice.id)
      and project.can_view_accounts
      and project.can_view_values

    union all

    -- PDC maturity due facts.
    select 'due_schedule', pdc.id, pdc.project_id,
      project.project_ref, project.name, project.client_name,
      pdc.cheque_number,
      invoice.invoice_reference,
      case
        when pdc.cheque_date < current_date then 'overdue'
        when pdc.cheque_date = current_date then 'due_today'
        when pdc.cheque_date <= current_date + 7 then 'due_soon'
        else 'current'
      end,
      pdc.amount,
      null::numeric,
      pdc.amount,
      pdc.received_date,
      pdc.cheque_date,
      pdc.updated_at,
      pdc.action_required or pdc.cheque_date <= current_date + 7,
      'pdc_due',
      project.currency_code,
      jsonb_build_object('pdc_status', pdc.status, 'bank_name', pdc.bank_name)
    from public.v1_accounts_client_pdcs pdc
    join project_context project on project.id = pdc.project_id
    join public.v1_accounts_client_invoices invoice on invoice.id = pdc.invoice_id
    where v_section = 'due_schedule'
      and pdc.status in ('expected', 'received', 'deposited')
      and project.can_view_accounts
      and project.can_view_values

    union all

    -- Supplier payable due facts require the same project's Accounts and
    -- supplier-cost capabilities.
    select 'due_schedule', bill.id, bill.project_id,
      project.project_ref, project.name, bill.supplier_name_snapshot,
      bill.supplier_invoice_reference,
      coalesce(bill.po_lpo_reference, bill.accepted_delivery_reference),
      case
        when bill.due_date < current_date then 'overdue'
        when bill.due_date = current_date then 'due_today'
        when bill.due_date <= current_date + 7 then 'due_soon'
        else 'current'
      end,
      bill.total_incl_vat,
      public.v1_accounts_supplier_paid_amount(bill.id),
      greatest(
        bill.total_incl_vat - public.v1_accounts_supplier_paid_amount(bill.id),
        0
      ),
      bill.invoice_date,
      bill.due_date,
      bill.updated_at,
      bill.due_date <= current_date + 7,
      'supplier_bill_due',
      project.currency_code,
      jsonb_build_object('bill_status', bill.status)
    from public.v1_accounts_supplier_bills bill
    join project_context project on project.id = bill.project_id
    where v_section = 'due_schedule'
      and bill.status <> 'cancelled'
      and bill.due_date is not null
      and bill.total_incl_vat > public.v1_accounts_supplier_paid_amount(bill.id)
      and project.can_view_accounts
      and project.can_view_supplier

    union all

    -- Controlled Accounts documents. v1_document_readable repeats storage
    -- classification and entity-access checks for every row.
    select 'documents', document.id, link.project_id,
      project.project_ref, project.name, project.client_name,
      version.original_file_name,
      metadata.document_type,
      case when metadata.archived_at is null then 'active' else 'archived' end,
      null::numeric,
      null::numeric,
      null::numeric,
      version.uploaded_at::date,
      null::date,
      version.uploaded_at,
      false,
      'document',
      project.currency_code,
      jsonb_build_object(
        'classification', document.classification,
        'mime_type', version.mime_type,
        'byte_size', version.byte_size,
        'revision_number', version.revision_number,
        'entity_type', link.entity_type,
        'entity_id', link.entity_id,
        'uploader', public.v1_safe_profile_display_name(
          uploader.display_name, uploader.auth_user_id
        )
      )
    from public.v1_accounts_document_metadata metadata
    join public.v1_documents document on document.id = metadata.document_id
    join public.v1_document_versions version on version.id = document.current_version_id
    join lateral (
      select distinct on (candidate.project_id)
        candidate.project_id,
        candidate.entity_type,
        candidate.entity_id
      from public.v1_document_links candidate
      where candidate.document_id = document.id
        and candidate.removed_at is null
        and candidate.project_id is not null
      order by
        candidate.project_id,
        candidate.linked_at,
        candidate.id
    ) link on true
    join project_context project on project.id = link.project_id
    join public.v1_profiles uploader
      on uploader.auth_user_id = version.uploaded_by_auth_user_id
    where v_section = 'documents'
      and project.can_view_accounts
      and public.v1_document_readable(document.id)

    union all

    -- Portfolio-wide append-only Accounts activity. Commercial before/after
    -- payloads deliberately remain in the existing project-scoped inspector.
    select 'activity', audit.id, audit.project_id,
      project.project_ref, project.name,
      public.v1_safe_profile_display_name(actor.display_name, actor.auth_user_id),
      audit.event_type,
      audit.entity_type,
      'recorded',
      null::numeric,
      null::numeric,
      null::numeric,
      audit.occurred_at::date,
      null::date,
      audit.occurred_at,
      false,
      'activity',
      project.currency_code,
      jsonb_build_object(
        'actor_exact_role', coalesce(audit.actor_exact_role, audit.actor_role),
        'reason', audit.reason,
        'entity_id', audit.entity_id
      )
    from public.v1_audit_events audit
    join project_context project on project.id = audit.project_id
    join public.v1_profiles actor on actor.auth_user_id = audit.actor_auth_user_id
    where v_section = 'activity'
      and (audit.event_type like 'accounts.%' or audit.entity_type like 'accounts_%')
      and project.can_view_accounts
      and (
        audit.entity_type not in ('accounts_supplier_bill', 'accounts_supplier_payment')
        or project.can_view_supplier
      )
  ), filtered as materialized (
    select *
    from office_rows row_item
    where (v_status is null or lower(row_item.status) = v_status)
      and (
        v_search is null
        or row_item.project_reference ilike '%' || v_search || '%'
        or row_item.project_name ilike '%' || v_search || '%'
        or coalesce(row_item.party, '') ilike '%' || v_search || '%'
        or row_item.reference ilike '%' || v_search || '%'
        or coalesce(row_item.secondary_reference, '') ilike '%' || v_search || '%'
      )
  ), page as (
    select *
    from filtered
    order by
      case when v_section = 'due_schedule' then due_date end asc nulls last,
      occurred_at desc,
      record_id desc
    limit p_limit offset p_offset
  )
  select
    (select count(*) from filtered),
    -- With no status filter, Receipts & PDC lists a cleared cheque beside the
    -- receipt it became, and a reversal beside the payment it undoes. Count each
    -- sum of money once. A filtered list is one kind of row, so it simply adds up.
    (select coalesce(sum(case
        when v_section <> 'client_payments' or v_status is not null then amount
        when status = 'reversed' then -amount
        when status in ('cleared', 'replaced', 'returned', 'bounced', 'cancelled') then 0
        else amount
      end), 0) from filtered),
    (select coalesce(sum(secondary_amount), 0) from filtered),
    (select coalesce(sum(balance_amount), 0) from filtered),
    (select count(*) from filtered where action_required),
    coalesce(jsonb_agg(jsonb_build_object(
      'record_id', page.record_id,
      'project_id', page.project_id,
      'project_reference', page.project_reference,
      'project_name', page.project_name,
      'party', page.party,
      'reference', page.reference,
      'secondary_reference', page.secondary_reference,
      'status', page.status,
      'amount', case when page.amount is null then null else page.amount::text end,
      'secondary_amount', case
        when page.secondary_amount is null then null
        else page.secondary_amount::text
      end,
      'balance_amount', case
        when page.balance_amount is null then null
        else page.balance_amount::text
      end,
      'event_date', page.event_date,
      'due_date', page.due_date,
      'occurred_at', page.occurred_at,
      'action_required', page.action_required,
      'record_kind', page.record_kind,
      'currency_code', coalesce(page.currency_code, 'AED'),
      'metadata', page.metadata
    ) order by
      case when v_section = 'due_schedule' then page.due_date end asc nulls last,
      page.occurred_at desc,
      page.record_id desc), '[]'::jsonb)
  into v_total, v_amount, v_secondary, v_balance, v_action_count, v_items
  from page;

  return jsonb_build_object(
    'schema_version', 8,
    'section', v_section,
    'total', v_total,
    'limit', p_limit,
    'offset', p_offset,
    'summary', jsonb_build_object(
      'amount', v_amount::text,
      'secondary_amount', v_secondary::text,
      'balance_amount', v_balance::text,
      'action_count', v_action_count
    ),
    'items', v_items
  );
end;
$$;
