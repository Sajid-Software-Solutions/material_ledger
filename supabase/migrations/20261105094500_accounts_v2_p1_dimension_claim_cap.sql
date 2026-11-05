-- R39 Accounts Workspace V2 — P1: dimension claim cap and single eligible source
--
-- Fixes the P0 correctness defect (plan R2): the claim cap and consumed-amount
-- helpers keyed "already claimed" on a single progress_entry_id, which is
-- per-baseline-revision. Claims made on revision N's progress rows did not
-- count against revision N+1's new rows, so after a contract revision plus
-- re-confirmation, already-invoiced work for the same building x stage became
-- claimable again.
--
-- This migration introduces one source of truth for eligible and already-claimed
-- amounts and routes the claim cap and the consumed helper through it. The
-- stable billing dimension is (project_id, project_scope_id, stage_key) — it is
-- preserved across baseline revisions even though each revision materializes new
-- progress rows. Claim lines already snapshot project_scope_id and stage_key, so
-- the dimension total can be summed directly from the claim-line table.
--
-- Behaviour for percent-mode rows is unchanged in the common single-revision
-- case (dimension-wide == per-row when every claim points at the current
-- revision's rows). It changes only to be correct across revisions, which is the
-- point. Item-quantity mode does not exist yet (added in P2); the eligible helper
-- is extended for items mode there.
--
-- Additive and idempotent. No table, row or existing status changes. See
-- docs/yorks-v1/R39_ACCOUNTS_WORKSPACE_V2_INTEGRATION_PLAN.md section 8.1 and
-- PRODUCT_DECISIONS.md section 32.

-- ---------------------------------------------------------------------------
-- Single source of "eligible" for a progress row.
-- Percent mode only in P1: round(stage value x confirmed percent / 100, 2),
-- byte-identical to the previous inline computation. Returns NULL for a missing
-- progress row (callers never pass one).
-- ---------------------------------------------------------------------------
create or replace function public.v1_accounts_progress_eligible_amount(
  p_progress_entry_id uuid
)
returns numeric(20,2)
language sql
stable
security definer
set search_path = ''
as $$
  select round(
    public.v1_accounts_stage_value(progress.id) * progress.confirmed_percent / 100,
    2
  )::numeric(20,2)
  from public.v1_accounts_billing_progress progress
  where progress.id = p_progress_entry_id;
$$;

-- ---------------------------------------------------------------------------
-- Single source of "already claimed" for a stable billing dimension, summed
-- across ALL baseline revisions. Excludes released claims (cancelled; and
-- superseded once P3 adds that status — the literal is harmless now because the
-- status column is text and no row carries it yet) and an optional claim under
-- edit (the successor/draft being validated).
-- ---------------------------------------------------------------------------
create or replace function public.v1_accounts_dimension_claimed_amount(
  p_project_id uuid,
  p_project_scope_id uuid,
  p_stage_key text,
  p_excluded_claim_id uuid default null
)
returns numeric(20,2)
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(line.claimed_amount), 0)::numeric(20,2)
  from public.v1_accounts_client_claim_lines line
  join public.v1_accounts_client_claims claim on claim.id = line.claim_id
  where line.project_id = p_project_id
    and line.project_scope_id = p_project_scope_id
    and line.stage_key = p_stage_key
    and claim.status not in ('cancelled', 'superseded')
    and claim.id is distinct from p_excluded_claim_id;
$$;

-- ---------------------------------------------------------------------------
-- Re-create the consumed helper to be dimension-wide. Resolving the dimension
-- from the progress row and delegating to the dimension helper means every
-- consumer that already calls this (v1_list_billing_progress per-row and totals,
-- v1_confirm_billing_progress's returned availability, and the
-- confirmed-below-claimed reduce guard) becomes correct across revisions with no
-- further change. Returns 0 when the progress row or its claims are absent,
-- preserving the previous semantics.
-- ---------------------------------------------------------------------------
create or replace function public.v1_accounts_consumed_claim_amount(
  p_progress_entry_id uuid
)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select public.v1_accounts_dimension_claimed_amount(
      progress.project_id, progress.project_scope_id, progress.stage_key, null
    )
    from public.v1_accounts_billing_progress progress
    where progress.id = p_progress_entry_id
  ), 0)::numeric;
$$;

-- ---------------------------------------------------------------------------
-- Re-create the claim-line validator so the cap uses the single eligible source
-- and the dimension-wide claimed total (excluding the claim under edit). This is
-- the money-integrity fix: a line can claim at most
-- max(eligible(current row) - claimed(dimension across all revisions), 0).
-- Body is reproduced verbatim from T03 (20260825194513) with only the eligible
-- and consumed computations swapped to the helpers.
-- ---------------------------------------------------------------------------
create or replace function public.v1_accounts_validate_claim_lines(
  p_project_id uuid,
  p_baseline_revision_id uuid,
  p_lines jsonb,
  p_excluded_claim_id uuid default null,
  p_allow_admin_exception boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_line jsonb;
  v_keys text[];
  v_progress public.v1_accounts_billing_progress%rowtype;
  v_progress_revision_id uuid;
  v_stage_value numeric;
  v_eligible numeric;
  v_consumed numeric;
  v_claim numeric;
  v_evidence text;
  v_result jsonb := '[]'::jsonb;
  v_seen uuid[] := '{}';
begin
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'R39_ACCOUNTS_CLAIM_LINES_REQUIRED' using errcode = '22023';
  end if;
  for v_line in select value from jsonb_array_elements(p_lines) loop
    if jsonb_typeof(v_line) <> 'object' then
      raise exception 'R39_ACCOUNTS_INVALID_CLAIM_LINE' using errcode = '22023';
    end if;
    select coalesce(array_agg(key order by key), '{}') into v_keys
    from jsonb_object_keys(v_line) key;
    if v_keys <> array['claimed_amount','evidence_reference','progress_entry_id']::text[] then
      raise exception 'R39_ACCOUNTS_INVALID_CLAIM_LINE' using errcode = '22023';
    end if;
    begin
      select * into strict v_progress from public.v1_accounts_billing_progress
      where id = (v_line ->> 'progress_entry_id')::uuid for update;
    exception when no_data_found or invalid_text_representation then
      raise exception 'R39_ACCOUNTS_INVALID_CLAIM_LINE' using errcode = '22023';
    end;
    if v_progress.id = any(v_seen) or v_progress.project_id <> p_project_id
      or v_progress.baseline_revision_id <> p_baseline_revision_id
      or v_progress.confirmed_percent <= 0
      or v_progress.review_status not in ('not_required','approved') then
      raise exception 'R39_ACCOUNTS_INVALID_CLAIM_LINE' using errcode = '22023';
    end if;
    v_seen := array_append(v_seen, v_progress.id);
    v_claim := public.v1_accounts_parse_money_text(v_line ->> 'claimed_amount');
    if v_claim <= 0 then
      raise exception 'R39_ACCOUNTS_INVALID_CLAIM_AMOUNT' using errcode = '22023';
    end if;
    v_stage_value := public.v1_accounts_stage_value(v_progress.id);
    -- P1: single eligible source, and dimension-wide claimed across all revisions.
    v_eligible := public.v1_accounts_progress_eligible_amount(v_progress.id);
    v_consumed := public.v1_accounts_dimension_claimed_amount(
      v_progress.project_id, v_progress.project_scope_id, v_progress.stage_key,
      p_excluded_claim_id
    );
    if v_claim > greatest(v_eligible - v_consumed, 0)
      and not p_allow_admin_exception then
      raise exception 'R39_ACCOUNTS_CLAIM_CAP_EXCEEDED' using errcode = '23514';
    end if;
    select revision.id into v_progress_revision_id
    from public.v1_accounts_billing_progress_revisions revision
    where revision.progress_entry_id = v_progress.id
    order by revision.revision_number desc
    limit 1;
    if v_progress_revision_id is null then
      raise exception 'R39_ACCOUNTS_PROGRESS_SNAPSHOT_MISSING' using errcode = '55000';
    end if;
    v_evidence := nullif(btrim(v_line ->> 'evidence_reference'), '');
    v_result := v_result || jsonb_build_array(jsonb_build_object(
      'progress_entry_id', v_progress.id,
      'progress_revision_id', v_progress_revision_id,
      'progress_record_version', v_progress.record_version,
      'project_scope_id', v_progress.project_scope_id,
      'stage_key', v_progress.stage_key,
      'stage_value_snapshot', v_stage_value::text,
      'confirmed_percent_snapshot', v_progress.confirmed_percent::text,
      'eligible_amount_snapshot', v_eligible::text,
      'previously_claimed_amount_snapshot', v_consumed::text,
      'claimed_amount', v_claim::text,
      'evidence_reference', v_evidence
    ));
  end loop;
  return v_result;
end;
$$;

-- Internal helpers are never Data API surfaces.
revoke all on function public.v1_accounts_progress_eligible_amount(uuid)
  from public, anon, authenticated;
revoke all on function public.v1_accounts_dimension_claimed_amount(uuid, uuid, text, uuid)
  from public, anon, authenticated;
revoke all on function public.v1_accounts_consumed_claim_amount(uuid)
  from public, anon, authenticated;
revoke all on function public.v1_accounts_validate_claim_lines(uuid, uuid, jsonb, uuid, boolean)
  from public, anon, authenticated;
