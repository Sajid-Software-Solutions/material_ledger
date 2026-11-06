-- =============================================================================
-- R39 Accounts Workspace V2 — bundled migration apply script
-- =============================================================================
-- Generated from the 22 V2 migration files, concatenated in dependency order.
-- Purpose: apply all V2 database objects in ONE paste in the Supabase SQL
-- editor, instead of running the files by hand.
--
-- BEFORE YOU RUN THIS:
--   1. TAKE A BACKUP of this database first (dashboard -> Database -> Backups,
--      or pg_dump). The backup is the real safety net.
--   2. Run on STAGING first. Confirm it succeeds, walk the app, THEN run the
--      identical script on PRODUCTION.
--   3. Do NOT run `supabase db push` or `supabase migration repair` — the live
--      DB has ~30 migrations not in git; leave them alone. This script only
--      ADDS the V2 objects and does not touch them.
--
-- SAFETY:
--   * Additive & idempotent (CREATE ... IF NOT EXISTS / OR REPLACE, ADD COLUMN
--     IF NOT EXISTS). The one DROP FUNCTION (contract-references, recreated with
--     a retention parameter) is a V2 function replacement, not a data change.
--     Re-running the whole script is harmless.
--   * Wrapped in a single BEGIN/COMMIT: if ANY statement fails, the entire
--     script rolls back and the database is left exactly as it was. Fix the
--     cause and re-run.
--
-- NOTE: this applies the objects but does NOT insert rows into
--   supabase_migrations.schema_migrations (you are running it by hand). That is
--   expected and fine for enabling V2; reconciling the git<->DB ledger is a
--   separate drift cleanup, not a release step.
--
-- AFTER THIS SUCCEEDS: run supabase/preflight/accounts_v2_p1_preflight.sql
--   (read-only; it needs v1_accounts_progress_eligible_amount, which THIS
--   script creates, so it only works after this has run). Zero rows = proceed.
-- =============================================================================

BEGIN;


-- #############################################################################
-- FILE 1 / 22 : 20261105094500_accounts_v2_p1_dimension_claim_cap.sql
-- #############################################################################

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


-- #############################################################################
-- FILE 2 / 22 : 20261105101500_accounts_v2_p2_item_breakdown.sql
-- #############################################################################

-- R39 Accounts Workspace V2 — P2 (part 1): item-quantity billing foundation
--
-- Adds the per-stage item breakdown the prototype's "Item quantities" stages
-- depend on: a measurement mode on each stage, the stage-item catalogue, the
-- item-level progress tables, a largest-remainder item value (so item values
-- sum to the building x stage value to the fil), and an items-aware extension of
-- the single eligible source added in P1.
--
-- This part is additive and dormant: no command writes the new tables yet (the
-- v1_save_project_commercial_setup writer and carry-forward arrive in P2 part 2),
-- every stage defaults to the existing 'percent' mode, and percent-mode eligible
-- is byte-identical to P1. See
-- docs/yorks-v1/R39_ACCOUNTS_WORKSPACE_V2_INTEGRATION_PLAN.md section 8.2 and
-- PRODUCT_DECISIONS.md section 32 (D3).

-- ---------------------------------------------------------------------------
-- Measurement mode per stage: percent (lump sum) or items (quantities).
-- ---------------------------------------------------------------------------
alter table public.v1_accounts_baseline_stage_allocations
  add column if not exists measurement_mode text not null default 'percent'
  check (measurement_mode in ('percent', 'items'));

-- ---------------------------------------------------------------------------
-- Stage-item catalogue. Items belong to a (baseline revision, building scope,
-- stage). item_key is stable across revisions so carry-forward can match.
-- Weight is % of the TOTAL contract; the server rule (enforced by the P2 part-2
-- setup command) is that the items of a (revision, scope, items-stage) sum to
-- building% x stage% / 100 within 0.000005.
-- ---------------------------------------------------------------------------
create table if not exists public.v1_accounts_baseline_stage_items (
  id uuid primary key default gen_random_uuid(),
  baseline_revision_id uuid not null
    references public.v1_accounts_baseline_revisions (id) on delete restrict,
  project_id uuid not null
    references public.v1_projects (id) on delete restrict,
  project_scope_id uuid not null
    references public.v1_project_scopes (id) on delete restrict,
  stage_key text not null check (stage_key ~ '^[a-z][a-z0-9_]*$'),
  item_key text not null check (item_key ~ '^[a-z0-9][a-z0-9_-]{0,63}$'),
  item_label text not null check (btrim(item_label) <> ''),
  display_order integer not null check (display_order > 0),
  quantity numeric(18,4) not null check (quantity::text <> 'NaN' and quantity > 0),
  unit_code text not null check (btrim(unit_code) <> ''),
  weight_percent_of_contract numeric(9,6) not null check (
    weight_percent_of_contract::text <> 'NaN'
    and weight_percent_of_contract > 0 and weight_percent_of_contract <= 100
  ),
  created_at timestamptz not null default clock_timestamp(),
  unique (baseline_revision_id, project_scope_id, stage_key, item_key),
  unique (baseline_revision_id, project_scope_id, stage_key, display_order)
);

create index if not exists v1_accounts_stage_items_cell_idx
  on public.v1_accounts_baseline_stage_items
    (baseline_revision_id, project_scope_id, stage_key, display_order);

-- ---------------------------------------------------------------------------
-- Item-level progress for items-mode cells. One row per (progress entry, item).
-- confirmed_qty is 0..item quantity; confirmed_evidence is the typed evidence
-- array (P2 part 2 / 8.4). needs_review is set by carry-forward when a new
-- quantity is below the confirmed quantity.
-- ---------------------------------------------------------------------------
create table if not exists public.v1_accounts_billing_item_progress (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null
    references public.v1_projects (id) on delete restrict,
  baseline_revision_id uuid not null
    references public.v1_accounts_baseline_revisions (id) on delete restrict,
  progress_entry_id uuid not null
    references public.v1_accounts_billing_progress (id) on delete restrict,
  stage_item_id uuid not null
    references public.v1_accounts_baseline_stage_items (id) on delete restrict,
  project_scope_id uuid not null
    references public.v1_project_scopes (id) on delete restrict,
  stage_key text not null check (stage_key ~ '^[a-z][a-z0-9_]*$'),
  item_key text not null check (item_key ~ '^[a-z0-9][a-z0-9_-]{0,63}$'),
  suggested_qty numeric(18,4) not null default 0 check (
    suggested_qty::text <> 'NaN' and suggested_qty >= 0
  ),
  confirmed_qty numeric(18,4) not null default 0 check (
    confirmed_qty::text <> 'NaN' and confirmed_qty >= 0
  ),
  confirmed_evidence jsonb not null default '[]'::jsonb,
  needs_review boolean not null default false,
  record_version integer not null default 1 check (record_version > 0),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (baseline_revision_id, stage_item_id),
  unique (progress_entry_id, stage_item_id)
);

create index if not exists v1_accounts_item_progress_entry_idx
  on public.v1_accounts_billing_item_progress (progress_entry_id);

-- Append-only item-progress history (suggested / confirmed / carried forward).
create table if not exists public.v1_accounts_billing_item_progress_revisions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null
    references public.v1_projects (id) on delete restrict,
  item_progress_id uuid not null
    references public.v1_accounts_billing_item_progress (id) on delete restrict,
  baseline_revision_id uuid not null
    references public.v1_accounts_baseline_revisions (id) on delete restrict,
  revision_number integer not null check (revision_number > 0),
  action text not null check (action in ('suggested', 'confirmed', 'carried_forward')),
  previous_suggested_qty numeric(18,4) not null check (previous_suggested_qty >= 0),
  new_suggested_qty numeric(18,4) not null check (new_suggested_qty >= 0),
  previous_confirmed_qty numeric(18,4) not null check (previous_confirmed_qty >= 0),
  new_confirmed_qty numeric(18,4) not null check (new_confirmed_qty >= 0),
  evidence jsonb not null default '[]'::jsonb,
  reason text not null check (btrim(reason) <> ''),
  actor_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  actor_exact_role text not null check (actor_exact_role in (
    'project_engineer', 'site_engineer', 'senior_mechanical_engineer',
    'project_manager', 'workshop_in_charge', 'document_controller',
    'procurement', 'accountant', 'admin'
  )),
  idempotency_key uuid not null,
  occurred_at timestamptz not null default clock_timestamp(),
  unique (item_progress_id, revision_number)
);

create index if not exists v1_accounts_item_progress_revisions_project_idx
  on public.v1_accounts_billing_item_progress_revisions (project_id, occurred_at desc);

-- Direct Data API access is denied; access is only through security-definer
-- projections and commands (consistent with every other accounts relation).
alter table public.v1_accounts_baseline_stage_items enable row level security;
alter table public.v1_accounts_billing_item_progress enable row level security;
alter table public.v1_accounts_billing_item_progress_revisions enable row level security;

-- ---------------------------------------------------------------------------
-- Item value: largest-remainder distribution of the building x stage value
-- across that cell's items by weight, so the item values sum to the stage value
-- to the fil (the prototype's "Item value = contract x item weight %").
-- ---------------------------------------------------------------------------
create or replace function public.v1_accounts_stage_item_value(
  p_stage_item_id uuid
)
returns numeric(20,2)
language sql
stable
security definer
set search_path = ''
as $$
  with target as (
    select si.baseline_revision_id, si.project_scope_id, si.stage_key
    from public.v1_accounts_baseline_stage_items si
    where si.id = p_stage_item_id
  ),
  cell as (
    select bp.id as progress_id
    from public.v1_accounts_billing_progress bp
    join target t on t.baseline_revision_id = bp.baseline_revision_id
      and t.project_scope_id = bp.project_scope_id
      and t.stage_key = bp.stage_key
  ),
  pool as (
    select round(public.v1_accounts_stage_value((select progress_id from cell)) * 100)::bigint as cents
  ),
  siblings as (
    select si.id, si.display_order, si.weight_percent_of_contract as w
    from public.v1_accounts_baseline_stage_items si
    join target t on t.baseline_revision_id = si.baseline_revision_id
      and t.project_scope_id = si.project_scope_id
      and t.stage_key = si.stage_key
  ),
  based as (
    select s.id, s.display_order,
      pg_catalog.floor(
        (select cents from pool) * s.w / nullif((select sum(w) from siblings), 0)
      )::bigint as base_cents,
      ((select cents from pool) * s.w / nullif((select sum(w) from siblings), 0))
        - pg_catalog.floor(
            (select cents from pool) * s.w / nullif((select sum(w) from siblings), 0)
          ) as frac
    from siblings s
  ),
  ranked as (
    select b.*,
      pg_catalog.row_number() over (order by frac desc, display_order, id) as rnk,
      (select cents from pool) - pg_catalog.sum(base_cents) over () as residual
    from based b
  )
  select round((base_cents + case when rnk <= residual then 1 else 0 end)::numeric / 100, 2)
  from ranked
  where id = p_stage_item_id;
$$;

-- ---------------------------------------------------------------------------
-- Extend the single eligible source for items mode. Percent mode is unchanged
-- (byte-identical to P1). Items mode: round(sum(item value x confirmed qty /
-- quantity), 2) over the cell's item-progress rows.
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
  with cell as (
    select bp.id, bp.baseline_revision_id, bp.stage_key, bp.confirmed_percent,
      stage.measurement_mode
    from public.v1_accounts_billing_progress bp
    join public.v1_accounts_baseline_stage_allocations stage
      on stage.baseline_revision_id = bp.baseline_revision_id
      and stage.stage_key = bp.stage_key
    where bp.id = p_progress_entry_id
  )
  select case
    when (select measurement_mode from cell) = 'items' then
      coalesce((
        select round(sum(
          public.v1_accounts_stage_item_value(ip.stage_item_id)
            * ip.confirmed_qty / nullif(item.quantity, 0)
        ), 2)
        from public.v1_accounts_billing_item_progress ip
        join public.v1_accounts_baseline_stage_items item on item.id = ip.stage_item_id
        where ip.progress_entry_id = p_progress_entry_id
      ), 0)::numeric(20,2)
    else
      round(
        public.v1_accounts_stage_value((select id from cell))
          * (select confirmed_percent from cell) / 100,
        2
      )::numeric(20,2)
  end;
$$;

-- Internal helpers are never Data API surfaces.
revoke all on function public.v1_accounts_stage_item_value(uuid)
  from public, anon, authenticated;
revoke all on function public.v1_accounts_progress_eligible_amount(uuid)
  from public, anon, authenticated;


-- #############################################################################
-- FILE 3 / 22 : 20261105103000_accounts_v2_p2_save_setup.sql
-- #############################################################################

-- R39 Accounts Workspace V2 — P2 (part 2): save-setup command with carry-forward
--
-- Fixes R1 ("editing the contract wipes progress"). v1_save_project_commercial_setup
-- is the V2 contract writer: it delegates the validated baseline/allocation/
-- materialize work to the existing, tested initialize/revise commands, then adds
-- the V2 layer those commands do not know about — per-stage measurement mode,
-- the stage-item catalogue, and carry-forward of confirmed/suggested progress and
-- item quantities by stable keys (building scope + stage_key [+ item_key]). A new
-- quantity below the confirmed quantity is capped and flagged needs_review, never
-- silently dropped; removed dimensions are reported.
--
-- The legacy v1_initialize/revise commands are unchanged (the V1 screens keep
-- using them). Additive and idempotent. See
-- docs/yorks-v1/R39_ACCOUNTS_WORKSPACE_V2_INTEGRATION_PLAN.md section 8.3 and
-- PRODUCT_DECISIONS.md section 32 (D2). Change-detection (unchanged -> no
-- revision) and invoice settings are added in P3.

-- Allow carry-forward as a billing-progress revision action (superset; no row
-- changes).
alter table public.v1_accounts_billing_progress_revisions
  drop constraint if exists v1_accounts_billing_progress_revisions_action_check;
alter table public.v1_accounts_billing_progress_revisions
  add constraint v1_accounts_billing_progress_revisions_action_check
  check (action in ('suggested', 'confirmed', 'reviewed', 'carried_forward'));

create or replace function public.v1_save_project_commercial_setup(
  p_project_id uuid,
  p_expected_profile_version integer,
  p_setup jsonb,
  p_note text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_exact_role text;
  v_actor_role text;
  v_profile public.v1_accounts_project_commercial_profiles%rowtype;
  v_has_profile boolean;
  v_buildings jsonb;
  v_stages jsonb;
  v_existing jsonb;
  v_derived_key uuid;
  v_base jsonb;
  v_new_baseline_id uuid;
  v_old_baseline_id uuid;
  v_old_revision integer;
  v_stage jsonb;
  v_scope uuid;
  v_need numeric;
  v_have numeric;
  v_carried integer := 0;
  v_needs_review integer := 0;
  v_removed jsonb := '[]'::jsonb;
  v_response jsonb;
begin
  v_exact_role := public.v1_accounts_require_capability(
    p_project_id, 'configure_project_commercials'
  );
  v_actor_role := public.v1_current_role();
  if p_setup is null or jsonb_typeof(p_setup) <> 'object'
    or jsonb_typeof(p_setup -> 'buildings') <> 'array'
    or jsonb_typeof(p_setup -> 'stages') <> 'array' then
    raise exception 'R39_ACCOUNTS_SETUP_REQUIRED' using errcode = '22023';
  end if;

  v_existing := public.v1_idempotency_get_or_claim(
    'v1_save_project_commercial_setup', p_idempotency_key, p_setup
  );
  if v_existing is not null then
    return v_existing || jsonb_build_object('replayed', true);
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('r39_accounts_baseline|' || p_project_id::text, 0)
  );

  select * into v_profile
  from public.v1_accounts_project_commercial_profiles
  where project_id = p_project_id for update;
  v_has_profile := found;

  -- Buildings and stages in the shape the delegated commands expect (no mode or
  -- items; those are the V2 layer applied afterward).
  v_buildings := p_setup -> 'buildings';
  v_stages := (
    select coalesce(jsonb_agg(jsonb_build_object(
      'stage_key', s ->> 'stage_key',
      'stage_label', s ->> 'stage_label',
      'allocation_percent', s ->> 'allocation_percent',
      'position', (s ->> 'position')::integer
    ) order by (s ->> 'position')::integer), '[]'::jsonb)
    from jsonb_array_elements(p_setup -> 'stages') s
  );

  -- Deterministic derived key so the delegated baseline command replays safely
  -- under its own idempotency namespace.
  v_derived_key := md5(p_idempotency_key::text || ':setup_baseline')::uuid;

  if not v_has_profile then
    v_base := public.v1_initialize_project_commercial_baseline(
      p_project_id, p_setup ->> 'contract_value', p_setup ->> 'currency_code',
      p_setup ->> 'vat_rate_percent',
      nullif(p_setup ->> 'payment_terms_days', '')::integer,
      nullif(p_setup ->> 'reminder_lead_days', '')::integer,
      v_buildings, v_stages,
      coalesce(p_setup -> 'management_review_policy', '{}'::jsonb),
      coalesce(nullif(btrim(p_note), ''), 'Commercial setup saved'),
      v_derived_key
    );
    v_old_baseline_id := null;
  else
    if p_expected_profile_version is null or p_expected_profile_version <= 0 then
      raise exception 'R39_ACCOUNTS_EXPECTED_VERSION_REQUIRED' using errcode = '22023';
    end if;
    v_old_baseline_id := v_profile.current_baseline_revision_id;
    select revision_number into v_old_revision
    from public.v1_accounts_baseline_revisions where id = v_old_baseline_id;
    v_base := public.v1_revise_project_commercial_baseline(
      p_project_id, p_expected_profile_version,
      p_setup ->> 'contract_value', p_setup ->> 'currency_code',
      p_setup ->> 'vat_rate_percent',
      nullif(p_setup ->> 'payment_terms_days', '')::integer,
      nullif(p_setup ->> 'reminder_lead_days', '')::integer,
      v_buildings, v_stages,
      coalesce(p_setup -> 'management_review_policy', '{}'::jsonb),
      coalesce(nullif(btrim(p_note), ''), 'Commercial setup revised'),
      v_derived_key
    );
  end if;
  v_new_baseline_id := (v_base ->> 'baseline_revision_id')::uuid;

  -- V2 layer: measurement mode + stage items for each items-mode stage, applied
  -- to every building scope (the "same items in all buildings" convenience).
  for v_stage in select value from jsonb_array_elements(p_setup -> 'stages') loop
    if coalesce(v_stage ->> 'measurement_mode', 'percent') = 'items' then
      update public.v1_accounts_baseline_stage_allocations
      set measurement_mode = 'items'
      where baseline_revision_id = v_new_baseline_id
        and stage_key = v_stage ->> 'stage_key';

      for v_scope in
        select project_scope_id from public.v1_accounts_baseline_building_allocations
        where baseline_revision_id = v_new_baseline_id
      loop
        insert into public.v1_accounts_baseline_stage_items(
          baseline_revision_id, project_id, project_scope_id, stage_key, item_key,
          item_label, display_order, quantity, unit_code, weight_percent_of_contract
        )
        select v_new_baseline_id, p_project_id, v_scope, v_stage ->> 'stage_key',
          it ->> 'item_key', it ->> 'item_label', (it ->> 'display_order')::integer,
          (it ->> 'quantity')::numeric, it ->> 'unit_code',
          (it ->> 'weight_percent_of_contract')::numeric
        from jsonb_array_elements(coalesce(v_stage -> 'items', '[]'::jsonb)) it;

        -- Items of a (scope, items-stage) must sum to building% x stage% / 100.
        select (building.allocation_percent * stage.allocation_percent / 100)
        into v_need
        from public.v1_accounts_baseline_building_allocations building
        join public.v1_accounts_baseline_stage_allocations stage
          on stage.baseline_revision_id = v_new_baseline_id
          and stage.stage_key = v_stage ->> 'stage_key'
        where building.baseline_revision_id = v_new_baseline_id
          and building.project_scope_id = v_scope;
        select coalesce(sum(weight_percent_of_contract), 0) into v_have
        from public.v1_accounts_baseline_stage_items
        where baseline_revision_id = v_new_baseline_id
          and project_scope_id = v_scope and stage_key = v_stage ->> 'stage_key';
        if abs(v_have - v_need) > 0.000005 then
          raise exception 'R39_ACCOUNTS_INVALID_STAGE_ITEMS'
            using errcode = '23514',
            detail = jsonb_build_object('stage_key', v_stage ->> 'stage_key',
              'scope', v_scope, 'needed', v_need::text, 'have', v_have::text)::text;
        end if;
      end loop;
    end if;
  end loop;

  -- Carry forward from the superseded revision (revise path only).
  if v_old_baseline_id is not null then
    -- Percent / confirmed progress by (scope, stage_key).
    update public.v1_accounts_billing_progress np set
      suggested_percent = op.suggested_percent,
      suggested_evidence_summary = op.suggested_evidence_summary,
      suggested_evidence_document_ids = op.suggested_evidence_document_ids,
      suggested_by_auth_user_id = op.suggested_by_auth_user_id,
      suggested_by_exact_role = op.suggested_by_exact_role,
      suggested_at = op.suggested_at,
      confirmed_percent = op.confirmed_percent,
      confirmed_evidence_summary = op.confirmed_evidence_summary,
      confirmed_evidence_document_ids = op.confirmed_evidence_document_ids,
      confirmed_by_auth_user_id = op.confirmed_by_auth_user_id,
      confirmed_by_exact_role = op.confirmed_by_exact_role,
      confirmed_at = op.confirmed_at,
      updated_at = clock_timestamp()
    from public.v1_accounts_billing_progress op
    where np.baseline_revision_id = v_new_baseline_id
      and op.baseline_revision_id = v_old_baseline_id
      and op.project_scope_id = np.project_scope_id
      and op.stage_key = np.stage_key
      and (op.confirmed_percent > 0 or op.suggested_percent > 0);

    insert into public.v1_accounts_billing_progress_revisions(
      project_id, progress_entry_id, baseline_revision_id, revision_number, action,
      previous_suggested_percent, new_suggested_percent,
      previous_confirmed_percent, new_confirmed_percent,
      previous_review_status, new_review_status,
      evidence_summary, evidence_document_ids, reason,
      actor_auth_user_id, actor_role, actor_exact_role, idempotency_key
    )
    select p_project_id, np.id, v_new_baseline_id, 1, 'carried_forward',
      0, np.suggested_percent, 0, np.confirmed_percent,
      'not_required', np.review_status,
      np.confirmed_evidence_summary, np.confirmed_evidence_document_ids,
      'Carried forward from revision ' || v_old_revision,
      v_actor, v_actor_role, v_exact_role, v_derived_key
    from public.v1_accounts_billing_progress np
    where np.baseline_revision_id = v_new_baseline_id
      and (np.confirmed_percent > 0 or np.suggested_percent > 0);
    get diagnostics v_carried = row_count;

    -- Item quantities by (scope, stage_key, item_key); cap below the new
    -- quantity and flag needs_review rather than dropping.
    insert into public.v1_accounts_billing_item_progress(
      project_id, baseline_revision_id, progress_entry_id, stage_item_id,
      project_scope_id, stage_key, item_key, suggested_qty, confirmed_qty,
      confirmed_evidence, needs_review
    )
    select p_project_id, v_new_baseline_id, np.id, ni.id,
      ni.project_scope_id, ni.stage_key, ni.item_key,
      least(oip.suggested_qty, ni.quantity), least(oip.confirmed_qty, ni.quantity),
      oip.confirmed_evidence, (oip.confirmed_qty > ni.quantity)
    from public.v1_accounts_baseline_stage_items ni
    join public.v1_accounts_billing_progress np
      on np.baseline_revision_id = v_new_baseline_id
      and np.project_scope_id = ni.project_scope_id and np.stage_key = ni.stage_key
    join public.v1_accounts_baseline_stage_items oi
      on oi.baseline_revision_id = v_old_baseline_id
      and oi.project_scope_id = ni.project_scope_id
      and oi.stage_key = ni.stage_key and oi.item_key = ni.item_key
    join public.v1_accounts_billing_item_progress oip on oip.stage_item_id = oi.id
    where ni.baseline_revision_id = v_new_baseline_id
      and (oip.confirmed_qty > 0 or oip.suggested_qty > 0);

    insert into public.v1_accounts_billing_item_progress_revisions(
      project_id, item_progress_id, baseline_revision_id, revision_number, action,
      previous_suggested_qty, new_suggested_qty,
      previous_confirmed_qty, new_confirmed_qty,
      evidence, reason, actor_auth_user_id, actor_exact_role, idempotency_key
    )
    select p_project_id, ip.id, v_new_baseline_id, 1, 'carried_forward',
      0, ip.suggested_qty, 0, ip.confirmed_qty, ip.confirmed_evidence,
      'Carried forward from revision ' || v_old_revision,
      v_actor, v_exact_role, v_derived_key
    from public.v1_accounts_billing_item_progress ip
    where ip.baseline_revision_id = v_new_baseline_id;

    select count(*) into v_needs_review
    from public.v1_accounts_billing_item_progress
    where baseline_revision_id = v_new_baseline_id and needs_review;

    select coalesce(jsonb_agg(jsonb_build_object(
      'project_scope_id', o.project_scope_id, 'stage_key', o.stage_key)), '[]'::jsonb)
    into v_removed
    from public.v1_accounts_billing_progress o
    where o.baseline_revision_id = v_old_baseline_id
      and not exists (
        select 1 from public.v1_accounts_billing_progress n
        where n.baseline_revision_id = v_new_baseline_id
          and n.project_scope_id = o.project_scope_id and n.stage_key = o.stage_key);
  end if;

  v_response := v_base || jsonb_build_object(
    'replayed', false,
    'carried_forward_progress_rows', v_carried,
    'items_needs_review', v_needs_review,
    'removed_dimensions', v_removed
  );
  perform public.v1_complete_idempotency(
    'v1_save_project_commercial_setup', p_idempotency_key, v_response
  );
  return v_response;
end;
$$;

grant execute on function public.v1_save_project_commercial_setup(uuid, integer, jsonb, text, uuid)
  to authenticated;


-- #############################################################################
-- FILE 4 / 22 : 20261105110000_accounts_v2_p3_claim_workbench_read.sql
-- #############################################################################

-- R39 Accounts Workspace V2 — P3 (part 1): claim workbench read + reopen
--
-- The claim workbench is the Progress & claims screen's single round trip. This
-- part adds the read-only projection v1_get_claim_workbench (every building x
-- stage cell for the current baseline, with items, role-safe values, dimension
-- claimed and available, plus the current open draft claim) and the small
-- v1_reopen_client_claim command ("Back to draft"). The save command, invoice
-- issue/revise/snapshot and the superseded status arrive in P3 part 2.
--
-- Additive and accounts-only. Reuses the P1/P2 helpers (eligible, dimension
-- claimed, stage item value) and the existing receivables/progress capability
-- envelopes. See docs/yorks-v1/R39_ACCOUNTS_WORKSPACE_V2_INTEGRATION_PLAN.md
-- sections 8.5 and 8.6.

-- ---------------------------------------------------------------------------
-- Read: one round trip for the workbench. Monetary keys are omitted (not
-- zeroed) without view_project_commercial_values (AT-SEC-001/008).
-- ---------------------------------------------------------------------------
create or replace function public.v1_get_claim_workbench(
  p_project_id uuid,
  p_claim_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_can_values boolean;
  v_profile public.v1_accounts_project_commercial_profiles%rowtype;
  v_baseline public.v1_accounts_baseline_revisions%rowtype;
  v_cells jsonb := '[]'::jsonb;
  v_claim jsonb := null;
  v_claim_id uuid;
begin
  perform public.v1_accounts_require_capability(p_project_id, 'view_project_accounts');
  v_can_values := public.v1_current_user_has_capability(
    'view_project_commercial_values', p_project_id
  );

  select * into v_profile
  from public.v1_accounts_project_commercial_profiles where project_id = p_project_id;
  if not found or v_profile.current_baseline_revision_id is null then
    return jsonb_build_object(
      'schema_version', 1, 'project_id', p_project_id,
      'baseline_revision_id', null, 'cells', '[]'::jsonb, 'claim', null,
      'capabilities', public.v1_accounts_capability_envelope(p_project_id),
      'commands', public.v1_accounts_receivables_commands(p_project_id)
    );
  end if;
  select * into v_baseline
  from public.v1_accounts_baseline_revisions where id = v_profile.current_baseline_revision_id;

  select coalesce(jsonb_agg(cell order by ord, bname), '[]'::jsonb) into v_cells
  from (
    select sa.display_order as ord, scope.name as bname,
      jsonb_build_object(
        'progress_entry_id', bp.id,
        'building_scope_id', bp.project_scope_id,
        'building_name', scope.name,
        'stage_key', bp.stage_key,
        'stage_label', sa.stage_name,
        'stage_position', sa.display_order,
        'measurement_mode', sa.measurement_mode,
        'confirmed_percent', bp.confirmed_percent::text,
        'review_status', bp.review_status,
        'record_version', bp.record_version
      )
      || case when v_can_values then jsonb_build_object(
          'stage_value', public.v1_accounts_stage_value(bp.id)::text,
          'eligible', public.v1_accounts_progress_eligible_amount(bp.id)::text,
          'claimed', public.v1_accounts_dimension_claimed_amount(
            bp.project_id, bp.project_scope_id, bp.stage_key, null)::text,
          'available', greatest(
            public.v1_accounts_progress_eligible_amount(bp.id)
              - public.v1_accounts_dimension_claimed_amount(
                  bp.project_id, bp.project_scope_id, bp.stage_key, null), 0)::text,
          'over_claimed', public.v1_accounts_dimension_claimed_amount(
              bp.project_id, bp.project_scope_id, bp.stage_key, null)
            > public.v1_accounts_progress_eligible_amount(bp.id)
        ) else '{}'::jsonb end
      || case when sa.measurement_mode = 'items' then jsonb_build_object('items', (
          select coalesce(jsonb_agg(
            jsonb_build_object(
              'stage_item_id', si.id, 'item_key', si.item_key,
              'item_label', si.item_label, 'display_order', si.display_order,
              'quantity', si.quantity::text, 'unit_code', si.unit_code,
              'confirmed_qty', coalesce(ip.confirmed_qty, 0)::text,
              'needs_review', coalesce(ip.needs_review, false)
            )
            || case when v_can_values then jsonb_build_object(
                'item_value', public.v1_accounts_stage_item_value(si.id)::text)
              else '{}'::jsonb end
            order by si.display_order), '[]'::jsonb)
          from public.v1_accounts_baseline_stage_items si
          left join public.v1_accounts_billing_item_progress ip
            on ip.stage_item_id = si.id and ip.progress_entry_id = bp.id
          where si.baseline_revision_id = v_baseline.id
            and si.project_scope_id = bp.project_scope_id
            and si.stage_key = bp.stage_key
        )) else '{}'::jsonb end
      as cell
    from public.v1_accounts_billing_progress bp
    join public.v1_accounts_baseline_stage_allocations sa
      on sa.baseline_revision_id = bp.baseline_revision_id and sa.stage_key = bp.stage_key
    join public.v1_project_scopes scope on scope.id = bp.project_scope_id
    where bp.baseline_revision_id = v_baseline.id
  ) rows;

  select id into v_claim_id
  from public.v1_accounts_client_claims
  where project_id = p_project_id
    and (
      (p_claim_id is not null and id = p_claim_id)
      or (p_claim_id is null and status in ('draft', 'ready_for_accounts'))
    )
  order by (status = 'draft') desc, updated_at desc
  limit 1;
  if v_claim_id is not null then
    v_claim := public.v1_accounts_claim_snapshot(v_claim_id);
  end if;

  return jsonb_build_object(
    'schema_version', 1, 'project_id', p_project_id,
    'baseline_revision_id', v_baseline.id,
    'baseline_revision_number', v_baseline.revision_number,
    'cells', v_cells, 'claim', v_claim,
    'capabilities', public.v1_accounts_capability_envelope(p_project_id),
    'commands', public.v1_accounts_receivables_commands(p_project_id)
  );
end;
$$;

grant execute on function public.v1_get_claim_workbench(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- "Back to draft": ready_for_accounts -> draft while no invoice exists. Mirrors
-- v1_submit_client_claim_to_accounts in reverse.
-- ---------------------------------------------------------------------------
create or replace function public.v1_reopen_client_claim(
  p_project_id uuid,
  p_claim_id uuid,
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
  v_claim public.v1_accounts_client_claims%rowtype;
  v_payload jsonb; v_existing jsonb; v_before jsonb; v_response jsonb;
  v_now timestamptz := clock_timestamp();
begin
  perform public.v1_accounts_require_capability(p_project_id, 'prepare_client_claim');
  if nullif(btrim(p_reason), '') is null then
    raise exception 'R39_ACCOUNTS_REASON_REQUIRED' using errcode = '22023';
  end if;
  v_payload := jsonb_build_object('project_id', p_project_id, 'claim_id', p_claim_id,
    'expected_version', p_expected_version, 'reason', btrim(p_reason));
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_reopen_client_claim', p_idempotency_key, v_payload);
  if v_existing is not null then return v_existing || jsonb_build_object('replayed', true); end if;

  select * into v_claim from public.v1_accounts_client_claims
  where id = p_claim_id and project_id = p_project_id for update;
  if not found then raise exception 'R39_ACCOUNTS_CLAIM_NOT_FOUND' using errcode = 'P0002'; end if;
  if v_claim.status <> 'ready_for_accounts' then
    raise exception 'R39_ACCOUNTS_CLAIM_NOT_REOPENABLE' using errcode = '55000'; end if;
  if exists (
    select 1 from public.v1_accounts_client_invoices i
    where i.claim_id = p_claim_id and i.status <> 'cancelled'
  ) then
    raise exception 'R39_ACCOUNTS_CLAIM_NOT_REOPENABLE' using errcode = '55000'; end if;
  if v_claim.created_by_auth_user_id <> auth.uid()
    and public.v1_permission_exact_role(auth.uid()) <> 'admin' then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501'; end if;
  if v_claim.record_version <> p_expected_version then
    raise exception 'R39_ACCOUNTS_VERSION_CONFLICT' using errcode = '40001'; end if;

  v_before := public.v1_accounts_claim_snapshot(p_claim_id);
  update public.v1_accounts_client_claims
  set status = 'draft', record_version = record_version + 1,
    ready_for_accounts_at = null, ready_for_accounts_by_auth_user_id = null,
    updated_at = v_now
  where id = p_claim_id;
  perform public.v1_write_audit_event(
    'accounts.client_claim.reopened', 'accounts_client_claim', p_claim_id,
    p_project_id, v_before, public.v1_accounts_claim_snapshot(p_claim_id),
    btrim(p_reason), p_idempotency_key);
  v_response := jsonb_build_object('schema_version', 3, 'replayed', false,
    'project_id', p_project_id, 'entity_id', p_claim_id, 'claim_id', p_claim_id,
    'record_version', p_expected_version + 1, 'status', 'draft', 'updated_at', v_now);
  perform public.v1_complete_idempotency('v1_reopen_client_claim', p_idempotency_key, v_response);
  return v_response;
end;
$$;

grant execute on function public.v1_reopen_client_claim(uuid, uuid, integer, text, uuid)
  to authenticated;


-- #############################################################################
-- FILE 5 / 22 : 20261105113000_accounts_v2_p3_invoice_issue.sql
-- #############################################################################

-- R39 Accounts Workspace V2 — P3 (part 2a): invoice numbering, issue, document
--
-- Adds per-project invoice numbering settings, the frozen printable document
-- snapshot, and v1_issue_client_invoice (allocate number, create + submit the
-- invoice via the existing commands, freeze the document model in one
-- transaction) plus preview and read of that document model. The invoice R.n
-- revision and the superseded status arrive in the next increment; the
-- company letterhead/bank settings (D9) layer into the document model later.
--
-- Additive, accounts-only. See
-- docs/yorks-v1/R39_ACCOUNTS_WORKSPACE_V2_INTEGRATION_PLAN.md sections 8.6, 9.

create table if not exists public.v1_accounts_project_invoice_settings (
  project_id uuid primary key references public.v1_projects (id) on delete restrict,
  invoice_prefix text not null check (btrim(invoice_prefix) <> ''),
  next_sequence integer not null default 1 check (next_sequence > 0),
  scope_line text,
  bill_to_party_id uuid,
  attention_name text,
  record_version integer not null default 1 check (record_version > 0),
  created_by_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);

create table if not exists public.v1_accounts_client_invoice_documents (
  invoice_id uuid primary key
    references public.v1_accounts_client_invoices (id) on delete restrict,
  project_id uuid not null references public.v1_projects (id) on delete restrict,
  document_snapshot jsonb not null,
  snapshot_sha256 text not null check (snapshot_sha256 ~ '^[0-9a-f]{64}$'),
  controlled_document_id uuid references public.v1_documents (id) on delete restrict,
  created_at timestamptz not null default clock_timestamp()
);

alter table public.v1_accounts_project_invoice_settings enable row level security;
alter table public.v1_accounts_client_invoice_documents enable row level security;

-- ---------------------------------------------------------------------------
-- Build the printable document model from a claim (used by issue and preview).
-- It stores the exact amounts and the building x stage breakdown; amount-in-
-- words and letterhead/bank are rendered/added downstream.
-- ---------------------------------------------------------------------------
create or replace function public.v1_accounts_build_invoice_document(
  p_project_id uuid,
  p_claim_id uuid,
  p_invoice_reference text,
  p_invoice_date date,
  p_submission_date date,
  p_due_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_claim public.v1_accounts_client_claims%rowtype;
  v_baseline public.v1_accounts_baseline_revisions%rowtype;
  v_project public.v1_projects%rowtype;
  v_settings public.v1_accounts_project_invoice_settings%rowtype;
  v_ex_vat numeric(20,2);
  v_vat numeric(20,2);
  v_lines jsonb;
begin
  select * into v_claim from public.v1_accounts_client_claims where id = p_claim_id and project_id = p_project_id;
  if not found then raise exception 'R39_ACCOUNTS_CLAIM_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into v_baseline from public.v1_accounts_baseline_revisions where id = v_claim.baseline_revision_id;
  select * into v_project from public.v1_projects where id = p_project_id;
  select * into v_settings from public.v1_accounts_project_invoice_settings where project_id = p_project_id;

  select coalesce(sum(line.claimed_amount), 0)::numeric(20,2) into v_ex_vat
  from public.v1_accounts_client_claim_lines line where line.claim_id = p_claim_id;
  v_vat := round(v_ex_vat * v_baseline.vat_rate_percent / 100, 2);

  select coalesce(jsonb_agg(jsonb_build_object(
      'building_scope_id', line.project_scope_id,
      'building_name', scope.name,
      'stage_key', line.stage_key,
      'stage_label', stage.stage_name,
      'amount', line.amount::text
    ) order by stage.display_order, scope.name), '[]'::jsonb) into v_lines
  from (
    select l.project_scope_id, l.stage_key, sum(l.claimed_amount) as amount
    from public.v1_accounts_client_claim_lines l where l.claim_id = p_claim_id
    group by l.project_scope_id, l.stage_key
  ) line
  join public.v1_project_scopes scope on scope.id = line.project_scope_id
  left join public.v1_accounts_baseline_stage_allocations stage
    on stage.baseline_revision_id = v_claim.baseline_revision_id and stage.stage_key = line.stage_key;

  return jsonb_build_object(
    'schema_version', 1,
    'invoice_reference', p_invoice_reference,
    'invoice_date', p_invoice_date,
    'submission_date', p_submission_date,
    'due_date', p_due_date,
    'payment_terms_days', v_baseline.payment_terms_days,
    'currency_code', v_baseline.currency_code,
    'project', jsonb_build_object('project_id', v_project.id, 'project_ref', v_project.project_ref, 'name', v_project.name),
    'claim', jsonb_build_object('claim_id', v_claim.id, 'claim_reference', v_claim.claim_reference,
      'period_start', v_claim.claim_period_start, 'period_end', v_claim.claim_period_end),
    'settings', jsonb_build_object('invoice_prefix', v_settings.invoice_prefix,
      'scope_line', v_settings.scope_line, 'attention_name', v_settings.attention_name,
      'bill_to_party_id', v_settings.bill_to_party_id),
    'amounts', jsonb_build_object('ex_vat', v_ex_vat::text,
      'vat_rate_percent', v_baseline.vat_rate_percent::text, 'vat', v_vat::text,
      'total_incl_vat', (v_ex_vat + v_vat)::text),
    'lines', v_lines
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Per-project invoice settings (prefix, scope line, attention, bill-to).
-- ---------------------------------------------------------------------------
create or replace function public.v1_save_project_invoice_settings(
  p_project_id uuid,
  p_invoice_prefix text,
  p_scope_line text,
  p_bill_to_party_id uuid,
  p_attention_name text,
  p_expected_version integer,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_row public.v1_accounts_project_invoice_settings%rowtype;
  v_payload jsonb; v_existing jsonb; v_response jsonb; v_now timestamptz := clock_timestamp();
begin
  perform public.v1_accounts_require_capability(p_project_id, 'manage_client_invoices');
  if nullif(btrim(p_invoice_prefix), '') is null then
    raise exception 'R39_ACCOUNTS_INVOICE_PREFIX_REQUIRED' using errcode = '22023'; end if;
  v_payload := jsonb_build_object('project_id', p_project_id, 'invoice_prefix', btrim(p_invoice_prefix),
    'scope_line', nullif(btrim(p_scope_line), ''), 'bill_to_party_id', p_bill_to_party_id,
    'attention_name', nullif(btrim(p_attention_name), ''), 'expected_version', p_expected_version);
  v_existing := public.v1_idempotency_get_or_claim('v1_save_project_invoice_settings', p_idempotency_key, v_payload);
  if v_existing is not null then return v_existing || jsonb_build_object('replayed', true); end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('r39_accounts_invoice_settings|' || p_project_id::text, 0));
  select * into v_row from public.v1_accounts_project_invoice_settings where project_id = p_project_id for update;
  if not found then
    insert into public.v1_accounts_project_invoice_settings(project_id, invoice_prefix, scope_line, bill_to_party_id, attention_name, created_by_auth_user_id)
    values (p_project_id, btrim(p_invoice_prefix), nullif(btrim(p_scope_line), ''), p_bill_to_party_id, nullif(btrim(p_attention_name), ''), v_actor)
    returning * into v_row;
  else
    if v_row.record_version <> coalesce(p_expected_version, v_row.record_version) then
      raise exception 'R39_ACCOUNTS_VERSION_CONFLICT' using errcode = '40001'; end if;
    update public.v1_accounts_project_invoice_settings
    set invoice_prefix = btrim(p_invoice_prefix), scope_line = nullif(btrim(p_scope_line), ''),
      bill_to_party_id = p_bill_to_party_id, attention_name = nullif(btrim(p_attention_name), ''),
      record_version = record_version + 1, updated_at = v_now
    where project_id = p_project_id returning * into v_row;
  end if;
  v_response := jsonb_build_object('schema_version', 1, 'replayed', false, 'project_id', p_project_id,
    'invoice_prefix', v_row.invoice_prefix, 'next_sequence', v_row.next_sequence, 'record_version', v_row.record_version);
  perform public.v1_complete_idempotency('v1_save_project_invoice_settings', p_idempotency_key, v_response);
  return v_response;
end;
$$;

grant execute on function public.v1_save_project_invoice_settings(uuid, text, text, uuid, text, integer, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Issue: allocate the number, create + submit the invoice, freeze the document.
-- ---------------------------------------------------------------------------
create or replace function public.v1_issue_client_invoice(
  p_project_id uuid,
  p_claim_id uuid,
  p_expected_claim_version integer,
  p_invoice_reference text,
  p_invoice_date date,
  p_submission_date date,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claim public.v1_accounts_client_claims%rowtype;
  v_settings public.v1_accounts_project_invoice_settings%rowtype;
  v_reference text;
  v_invoice_id uuid;
  v_draft jsonb; v_submit jsonb;
  v_document jsonb; v_sha text;
  v_payload jsonb; v_existing jsonb; v_response jsonb;
begin
  perform public.v1_accounts_require_capability(p_project_id, 'manage_client_invoices');
  if p_submission_date is null or p_invoice_date is null then
    raise exception 'R39_ACCOUNTS_INVOICE_DATE_REQUIRED' using errcode = '22023'; end if;
  v_payload := jsonb_build_object('project_id', p_project_id, 'claim_id', p_claim_id,
    'expected_claim_version', p_expected_claim_version, 'invoice_reference', nullif(btrim(p_invoice_reference), ''),
    'invoice_date', p_invoice_date, 'submission_date', p_submission_date);
  v_existing := public.v1_idempotency_get_or_claim('v1_issue_client_invoice', p_idempotency_key, v_payload);
  if v_existing is not null then return v_existing || jsonb_build_object('replayed', true); end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('r39_accounts_invoice_settings|' || p_project_id::text, 0));
  select * into v_claim from public.v1_accounts_client_claims where id = p_claim_id and project_id = p_project_id for update;
  if not found then raise exception 'R39_ACCOUNTS_CLAIM_NOT_FOUND' using errcode = 'P0002'; end if;
  if p_expected_claim_version is not null and v_claim.record_version <> p_expected_claim_version then
    raise exception 'R39_ACCOUNTS_VERSION_CONFLICT' using errcode = '40001'; end if;

  -- Allocate the reference: explicit override, else prefix + 2-digit sequence.
  if nullif(btrim(p_invoice_reference), '') is not null then
    v_reference := btrim(p_invoice_reference);
  else
    select * into v_settings from public.v1_accounts_project_invoice_settings where project_id = p_project_id for update;
    if not found then raise exception 'R39_ACCOUNTS_INVOICE_SETTINGS_REQUIRED' using errcode = '55000'; end if;
    v_reference := v_settings.invoice_prefix || lpad(v_settings.next_sequence::text, 2, '0');
    update public.v1_accounts_project_invoice_settings
    set next_sequence = next_sequence + 1, record_version = record_version + 1, updated_at = clock_timestamp()
    where project_id = p_project_id;
  end if;

  v_draft := public.v1_create_client_invoice_draft(
    p_project_id, p_claim_id, v_reference, null, md5(p_idempotency_key::text || ':create')::uuid);
  v_invoice_id := (v_draft ->> 'invoice_id')::uuid;
  v_submit := public.v1_submit_client_invoice(
    p_project_id, v_invoice_id, 1, p_submission_date, null, md5(p_idempotency_key::text || ':submit')::uuid);

  v_document := public.v1_accounts_build_invoice_document(
    p_project_id, p_claim_id, v_reference, p_invoice_date, p_submission_date,
    (v_submit ->> 'due_date')::date);
  v_sha := encode(pg_catalog.sha256(pg_catalog.convert_to(v_document::text, 'UTF8')), 'hex');
  insert into public.v1_accounts_client_invoice_documents(invoice_id, project_id, document_snapshot, snapshot_sha256)
  values (v_invoice_id, p_project_id, v_document, v_sha);

  v_response := v_submit || jsonb_build_object('replayed', false,
    'invoice_reference', v_reference, 'document_snapshot_sha256', v_sha);
  perform public.v1_complete_idempotency('v1_issue_client_invoice', p_idempotency_key, v_response);
  return v_response;
end;
$$;

grant execute on function public.v1_issue_client_invoice(uuid, uuid, integer, text, date, date, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Read the frozen document; preview the live model for a ready draft claim.
-- ---------------------------------------------------------------------------
create or replace function public.v1_get_client_invoice_document(p_project_id uuid, p_invoice_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_doc public.v1_accounts_client_invoice_documents%rowtype;
begin
  perform public.v1_accounts_require_capability(p_project_id, 'view_project_accounts');
  select * into v_doc from public.v1_accounts_client_invoice_documents where invoice_id = p_invoice_id and project_id = p_project_id;
  if not found then raise exception 'R39_ACCOUNTS_INVOICE_DOCUMENT_NOT_FOUND' using errcode = 'P0002'; end if;
  return jsonb_build_object('schema_version', 1, 'project_id', p_project_id, 'invoice_id', p_invoice_id,
    'snapshot_sha256', v_doc.snapshot_sha256, 'controlled_document_id', v_doc.controlled_document_id,
    'document', v_doc.document_snapshot);
end;
$$;

create or replace function public.v1_preview_client_invoice_document(p_project_id uuid, p_claim_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_claim public.v1_accounts_client_claims%rowtype; v_baseline public.v1_accounts_baseline_revisions%rowtype;
  v_prefix text; v_ref text; v_due date;
begin
  perform public.v1_accounts_require_capability(p_project_id, 'view_project_accounts');
  if not public.v1_current_user_has_capability('view_project_commercial_values', p_project_id) then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501'; end if;
  select * into v_claim from public.v1_accounts_client_claims where id = p_claim_id and project_id = p_project_id;
  if not found then raise exception 'R39_ACCOUNTS_CLAIM_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into v_baseline from public.v1_accounts_baseline_revisions where id = v_claim.baseline_revision_id;
  select invoice_prefix || lpad(next_sequence::text, 2, '0') into v_ref
  from public.v1_accounts_project_invoice_settings where project_id = p_project_id;
  v_due := clock_timestamp()::date + v_baseline.payment_terms_days;
  return jsonb_build_object('schema_version', 1, 'project_id', p_project_id, 'preview', true,
    'document', public.v1_accounts_build_invoice_document(
      p_project_id, p_claim_id, v_ref, clock_timestamp()::date, clock_timestamp()::date, v_due));
end;
$$;

grant execute on function public.v1_get_client_invoice_document(uuid, uuid) to authenticated;
grant execute on function public.v1_preview_client_invoice_document(uuid, uuid) to authenticated;
revoke all on function public.v1_accounts_build_invoice_document(uuid, uuid, text, date, date, date) from public, anon, authenticated;


-- #############################################################################
-- FILE 6 / 22 : 20261105120000_accounts_v2_p3_invoice_revise.sql
-- #############################################################################

-- R39 Accounts Workspace V2 — P3 (part 2b): invoice revision (R.n)
--
-- Adds v1_revise_client_invoice. Revising an issued invoice (only before any
-- certification, payment or active PDC) clones its claim into a successor draft
-- claim; issuing that successor numbers it base||'R.'||n, links it to the
-- predecessor, and retires the predecessor claim and invoice.
--
-- Modelling note (refines PRODUCT_DECISIONS section 32 / D7): a superseded
-- predecessor is retired by the existing terminal `cancelled` status plus a
-- `supersedes_invoice_id` link and a "Superseded by ..." reason — not a new
-- `superseded` status value. Every commercial reader already excludes
-- `cancelled` (and v1_accounts_dimension_claimed_amount already excludes
-- cancelled claims from P1), so the predecessor stops contributing to invoiced
-- sums, open/overdue counts, reminders and claim capacity with no change to
-- those readers. The supersedes link distinguishes a supersession from a manual
-- cancellation for display. Revision is only allowed before any money fact
-- exists, which is consistent with the frozen rule that an invoice cannot be
-- cancelled after certification, payment or PDC.
--
-- Additive, accounts-only. See R39_ACCOUNTS_WORKSPACE_V2_INTEGRATION_PLAN.md 8.6.

-- Revision-link columns (no status-value or constraint changes).
alter table public.v1_accounts_client_claims
  add column if not exists supersedes_claim_id uuid
  references public.v1_accounts_client_claims (id) on delete restrict;
alter table public.v1_accounts_client_invoices
  add column if not exists supersedes_invoice_id uuid
  references public.v1_accounts_client_invoices (id) on delete restrict;
alter table public.v1_accounts_client_invoices
  add column if not exists base_reference text;
alter table public.v1_accounts_client_invoices
  add column if not exists revision_number integer not null default 0
  check (revision_number >= 0);

-- ---------------------------------------------------------------------------
-- Revise: clone the invoice's claim into a successor draft claim.
-- ---------------------------------------------------------------------------
create or replace function public.v1_revise_client_invoice(
  p_project_id uuid,
  p_invoice_id uuid,
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
  v_actor uuid := auth.uid();
  v_role text := public.v1_current_role();
  v_exact text;
  v_invoice public.v1_accounts_client_invoices%rowtype;
  v_claim public.v1_accounts_client_claims%rowtype;
  v_new_claim_id uuid := gen_random_uuid();
  v_new_reference text;
  v_payload jsonb; v_existing jsonb; v_response jsonb;
begin
  v_exact := public.v1_accounts_require_capability(p_project_id, 'manage_client_invoices');
  if nullif(btrim(p_reason), '') is null then
    raise exception 'R39_ACCOUNTS_REASON_REQUIRED' using errcode = '22023'; end if;
  v_payload := jsonb_build_object('project_id', p_project_id, 'invoice_id', p_invoice_id,
    'expected_version', p_expected_version, 'reason', btrim(p_reason));
  v_existing := public.v1_idempotency_get_or_claim('v1_revise_client_invoice', p_idempotency_key, v_payload);
  if v_existing is not null then return v_existing || jsonb_build_object('replayed', true); end if;

  select * into v_invoice from public.v1_accounts_client_invoices
  where id = p_invoice_id and project_id = p_project_id for update;
  if not found then raise exception 'R39_ACCOUNTS_INVOICE_NOT_FOUND' using errcode = 'P0002'; end if;
  if v_invoice.record_version <> p_expected_version then
    raise exception 'R39_ACCOUNTS_VERSION_CONFLICT' using errcode = '40001'; end if;
  if v_invoice.status not in ('submitted', 'under_certification') then
    raise exception 'R39_ACCOUNTS_INVOICE_NOT_REVISABLE' using errcode = '55000'; end if;
  if exists (select 1 from public.v1_accounts_client_certifications where invoice_id = p_invoice_id)
    or public.v1_accounts_invoice_paid_amount(p_invoice_id) > 0
    or public.v1_accounts_invoice_pdc_exposure(p_invoice_id) > 0 then
    raise exception 'R39_ACCOUNTS_INVOICE_NOT_REVISABLE' using errcode = '55000'; end if;
  if exists (
    select 1 from public.v1_accounts_client_claims c
    where c.supersedes_claim_id = v_invoice.claim_id and c.status <> 'cancelled'
  ) then
    raise exception 'R39_ACCOUNTS_REVISION_ALREADY_OPEN' using errcode = '55000'; end if;

  select * into v_claim from public.v1_accounts_client_claims where id = v_invoice.claim_id for update;
  v_new_reference := v_claim.claim_reference || '-R' || (coalesce(v_invoice.revision_number, 0) + 1)::text;

  insert into public.v1_accounts_client_claims(
    id, project_id, baseline_revision_id, claim_reference, claim_period_start,
    claim_period_end, status, notes, supersedes_claim_id,
    created_by_auth_user_id, created_by_role, created_by_exact_role, idempotency_key)
  values (v_new_claim_id, p_project_id, v_claim.baseline_revision_id, v_new_reference,
    v_claim.claim_period_start, v_claim.claim_period_end, 'draft', v_claim.notes, v_claim.id,
    v_actor, v_role, v_exact, p_idempotency_key);
  insert into public.v1_accounts_client_claim_lines(
    claim_id, project_id, progress_entry_id, baseline_revision_id, progress_revision_id,
    progress_record_version, project_scope_id, stage_key, stage_value_snapshot,
    confirmed_percent_snapshot, eligible_amount_snapshot, previously_claimed_amount_snapshot,
    claimed_amount, evidence_reference)
  select v_new_claim_id, project_id, progress_entry_id, baseline_revision_id, progress_revision_id,
    progress_record_version, project_scope_id, stage_key, stage_value_snapshot,
    confirmed_percent_snapshot, eligible_amount_snapshot, previously_claimed_amount_snapshot,
    claimed_amount, evidence_reference
  from public.v1_accounts_client_claim_lines where claim_id = v_claim.id;

  perform public.v1_write_audit_event('accounts.client_invoice.revision_started',
    'accounts_client_invoice', p_invoice_id, p_project_id,
    public.v1_accounts_invoice_snapshot(p_invoice_id),
    jsonb_build_object('successor_claim_id', v_new_claim_id, 'successor_claim_reference', v_new_reference),
    btrim(p_reason), p_idempotency_key);

  v_response := jsonb_build_object('schema_version', 1, 'replayed', false, 'project_id', p_project_id,
    'invoice_id', p_invoice_id, 'successor_claim_id', v_new_claim_id,
    'successor_claim_reference', v_new_reference, 'status', 'draft');
  perform public.v1_complete_idempotency('v1_revise_client_invoice', p_idempotency_key, v_response);
  return v_response;
end;
$$;

grant execute on function public.v1_revise_client_invoice(uuid, uuid, integer, text, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Re-create issue to handle successor issuance: R.n numbering + retire the
-- predecessor (cancelled + supersedes link).
-- ---------------------------------------------------------------------------
create or replace function public.v1_issue_client_invoice(
  p_project_id uuid,
  p_claim_id uuid,
  p_expected_claim_version integer,
  p_invoice_reference text,
  p_invoice_date date,
  p_submission_date date,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_claim public.v1_accounts_client_claims%rowtype;
  v_pred_claim public.v1_accounts_client_claims%rowtype;
  v_pred_invoice public.v1_accounts_client_invoices%rowtype;
  v_settings public.v1_accounts_project_invoice_settings%rowtype;
  v_reference text;
  v_base text;
  v_rev integer := 0;
  v_invoice_id uuid;
  v_draft jsonb; v_submit jsonb;
  v_document jsonb; v_sha text;
  v_payload jsonb; v_existing jsonb; v_response jsonb; v_now timestamptz := clock_timestamp();
begin
  perform public.v1_accounts_require_capability(p_project_id, 'manage_client_invoices');
  if p_submission_date is null or p_invoice_date is null then
    raise exception 'R39_ACCOUNTS_INVOICE_DATE_REQUIRED' using errcode = '22023'; end if;
  v_payload := jsonb_build_object('project_id', p_project_id, 'claim_id', p_claim_id,
    'expected_claim_version', p_expected_claim_version, 'invoice_reference', nullif(btrim(p_invoice_reference), ''),
    'invoice_date', p_invoice_date, 'submission_date', p_submission_date);
  v_existing := public.v1_idempotency_get_or_claim('v1_issue_client_invoice', p_idempotency_key, v_payload);
  if v_existing is not null then return v_existing || jsonb_build_object('replayed', true); end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('r39_accounts_invoice_settings|' || p_project_id::text, 0));
  select * into v_claim from public.v1_accounts_client_claims where id = p_claim_id and project_id = p_project_id for update;
  if not found then raise exception 'R39_ACCOUNTS_CLAIM_NOT_FOUND' using errcode = 'P0002'; end if;
  if p_expected_claim_version is not null and v_claim.record_version <> p_expected_claim_version then
    raise exception 'R39_ACCOUNTS_VERSION_CONFLICT' using errcode = '40001'; end if;

  if v_claim.supersedes_claim_id is not null then
    select * into v_pred_claim from public.v1_accounts_client_claims where id = v_claim.supersedes_claim_id for update;
    select * into v_pred_invoice from public.v1_accounts_client_invoices where claim_id = v_pred_claim.id for update;
    v_base := coalesce(v_pred_invoice.base_reference, v_pred_invoice.invoice_reference);
    v_rev := coalesce(v_pred_invoice.revision_number, 0) + 1;
    v_reference := coalesce(nullif(btrim(p_invoice_reference), ''), v_base || 'R.' || v_rev::text);
  elsif nullif(btrim(p_invoice_reference), '') is not null then
    v_reference := btrim(p_invoice_reference);
  else
    select * into v_settings from public.v1_accounts_project_invoice_settings where project_id = p_project_id for update;
    if not found then raise exception 'R39_ACCOUNTS_INVOICE_SETTINGS_REQUIRED' using errcode = '55000'; end if;
    v_reference := v_settings.invoice_prefix || lpad(v_settings.next_sequence::text, 2, '0');
    update public.v1_accounts_project_invoice_settings
    set next_sequence = next_sequence + 1, record_version = record_version + 1, updated_at = v_now
    where project_id = p_project_id;
  end if;

  v_draft := public.v1_create_client_invoice_draft(
    p_project_id, p_claim_id, v_reference, null, md5(p_idempotency_key::text || ':create')::uuid);
  v_invoice_id := (v_draft ->> 'invoice_id')::uuid;
  v_submit := public.v1_submit_client_invoice(
    p_project_id, v_invoice_id, 1, p_submission_date, null, md5(p_idempotency_key::text || ':submit')::uuid);

  if v_claim.supersedes_claim_id is not null then
    update public.v1_accounts_client_invoices
    set base_reference = v_base, revision_number = v_rev, supersedes_invoice_id = v_pred_invoice.id
    where id = v_invoice_id;
    -- Retire the predecessor: cancelled + supersedes link ("Superseded by R.n").
    update public.v1_accounts_client_invoices
    set status = 'cancelled', cancelled_at = v_now, cancelled_by_auth_user_id = v_actor,
      cancellation_reason = 'Superseded by ' || v_reference,
      record_version = record_version + 1, updated_at = v_now
    where id = v_pred_invoice.id;
    update public.v1_accounts_client_claims
    set status = 'cancelled', cancelled_at = v_now, cancelled_by_auth_user_id = v_actor,
      cancellation_reason = 'Superseded by ' || v_reference,
      record_version = record_version + 1, updated_at = v_now
    where id = v_pred_claim.id;
    perform public.v1_write_audit_event('accounts.client_invoice.superseded',
      'accounts_client_invoice', v_pred_invoice.id, p_project_id,
      jsonb_build_object('superseded_by_invoice_id', v_invoice_id, 'reference', v_reference),
      null, 'Superseded by ' || v_reference, p_idempotency_key);
  end if;

  v_document := public.v1_accounts_build_invoice_document(
    p_project_id, p_claim_id, v_reference, p_invoice_date, p_submission_date, (v_submit ->> 'due_date')::date);
  v_sha := encode(pg_catalog.sha256(pg_catalog.convert_to(v_document::text, 'UTF8')), 'hex');
  insert into public.v1_accounts_client_invoice_documents(invoice_id, project_id, document_snapshot, snapshot_sha256)
  values (v_invoice_id, p_project_id, v_document, v_sha);

  v_response := v_submit || jsonb_build_object('replayed', false,
    'invoice_reference', v_reference, 'revision_number', v_rev, 'document_snapshot_sha256', v_sha);
  perform public.v1_complete_idempotency('v1_issue_client_invoice', p_idempotency_key, v_response);
  return v_response;
end;
$$;


-- #############################################################################
-- FILE 7 / 22 : 20261105130000_accounts_v2_p3_save_workbench.sql
-- #############################################################################

-- R39 Accounts Workspace V2 — P3 (part 2c): save claim workbench
--
-- v1_save_claim_workbench is the Progress & claims screen's one-shot write: it
-- confirms the entered to-date progress (percent rows delegate to the existing
-- v1_confirm_billing_progress; item quantities are confirmed inline against the
-- P2 item-progress tables) and then rebuilds the single open draft claim with
-- claimed = available(dimension) for every current cell with something to claim.
-- The server never trusts client arithmetic: available comes from the P1/P2
-- helpers, and the cap is re-checked by the existing create-claim path.
--
-- v1 scope: requires prepare_client_claim + view_project_commercial_values +
-- confirm_billing_progress (the Project Engineer path), document evidence, and
-- rebuilds (delete + recreate) the single draft. Deferred: the Site-Engineer
-- "record as suggestion only" fallback, the typed receipt-review/DO/note
-- evidence kinds (D5), and a separate v1_rebuild_client_claim_draft (save is the
-- rebuild). Additive, accounts-only.

create or replace function public.v1_save_claim_workbench(
  p_project_id uuid,
  p_claim_reference text,
  p_period_start date,
  p_period_end date,
  p_entries jsonb,
  p_evidence_document_ids uuid[],
  p_reason text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_exact text;
  v_baseline uuid;
  v_entry jsonb;
  v_progress public.v1_accounts_billing_progress%rowtype;
  v_item public.v1_accounts_baseline_stage_items%rowtype;
  v_ip public.v1_accounts_billing_item_progress%rowtype;
  v_cell_progress uuid;
  v_new_qty numeric(18,4);
  v_evidence jsonb;
  v_rev integer;
  v_old_pct numeric(7,4);
  v_derived numeric(7,4);
  v_prog_rev integer;
  v_confirmed integer := 0;
  v_lines jsonb;
  v_claim jsonb := null;
  v_existing jsonb; v_payload jsonb; v_response jsonb;
  v_now timestamptz := clock_timestamp();
begin
  v_exact := public.v1_accounts_require_capability(p_project_id, 'prepare_client_claim');
  if not public.v1_current_user_has_capability('view_project_commercial_values', p_project_id)
    or not public.v1_current_user_has_capability('confirm_billing_progress', p_project_id) then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_entries, '[]'::jsonb)) <> 'array' then
    raise exception 'R39_ACCOUNTS_INVALID_WORKBENCH_ENTRY' using errcode = '22023'; end if;
  v_payload := jsonb_build_object('project_id', p_project_id,
    'claim_reference', nullif(btrim(coalesce(p_claim_reference, '')), ''),
    'period_start', p_period_start, 'period_end', p_period_end, 'entries', p_entries);
  v_existing := public.v1_idempotency_get_or_claim('v1_save_claim_workbench', p_idempotency_key, v_payload);
  if v_existing is not null then return v_existing || jsonb_build_object('replayed', true); end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('r39_accounts_claim_workbench|' || p_project_id::text, 0));

  select current_baseline_revision_id into v_baseline
  from public.v1_accounts_project_commercial_profiles where project_id = p_project_id;
  if v_baseline is null then raise exception 'R39_ACCOUNTS_BASELINE_NOT_FOUND' using errcode = 'P0002'; end if;

  v_evidence := (select coalesce(jsonb_agg(jsonb_build_object('kind', 'document', 'id', d)), '[]'::jsonb)
    from unnest(coalesce(p_evidence_document_ids, '{}'::uuid[])) d);

  for v_entry in select value from jsonb_array_elements(coalesce(p_entries, '[]'::jsonb)) loop
    if v_entry ? 'progress_entry_id' then
      select * into v_progress from public.v1_accounts_billing_progress
      where id = (v_entry ->> 'progress_entry_id')::uuid and project_id = p_project_id
        and baseline_revision_id = v_baseline;
      if not found then raise exception 'R39_ACCOUNTS_INVALID_WORKBENCH_ENTRY' using errcode = '22023'; end if;
      if (v_entry ->> 'confirmed_percent_to_date')::numeric(7,4) <> v_progress.confirmed_percent then
        perform public.v1_confirm_billing_progress(
          p_project_id, v_progress.id, v_progress.record_version,
          v_entry ->> 'confirmed_percent_to_date', nullif(btrim(p_reason), ''),
          coalesce(p_evidence_document_ids, '{}'::uuid[]),
          coalesce(nullif(btrim(p_reason), ''), 'Workbench confirmation'),
          md5(p_idempotency_key::text || ':c:' || v_progress.id::text)::uuid);
        v_confirmed := v_confirmed + 1;
      end if;
    elsif v_entry ? 'stage_item_id' then
      select * into v_item from public.v1_accounts_baseline_stage_items
      where id = (v_entry ->> 'stage_item_id')::uuid and project_id = p_project_id
        and baseline_revision_id = v_baseline;
      if not found then raise exception 'R39_ACCOUNTS_INVALID_WORKBENCH_ENTRY' using errcode = '22023'; end if;
      v_new_qty := (v_entry ->> 'confirmed_qty_to_date')::numeric(18,4);
      if v_new_qty < 0 or v_new_qty > v_item.quantity then
        raise exception 'R39_ACCOUNTS_INVALID_WORKBENCH_ENTRY' using errcode = '22023'; end if;
      select id into v_cell_progress from public.v1_accounts_billing_progress
      where baseline_revision_id = v_baseline and project_scope_id = v_item.project_scope_id
        and stage_key = v_item.stage_key;
      select * into v_ip from public.v1_accounts_billing_item_progress where stage_item_id = v_item.id;
      if not found then
        if v_new_qty > 0 and coalesce(array_length(p_evidence_document_ids, 1), 0) = 0 then
          raise exception 'R39_ACCOUNTS_EVIDENCE_REQUIRED' using errcode = '23514'; end if;
        insert into public.v1_accounts_billing_item_progress(
          project_id, baseline_revision_id, progress_entry_id, stage_item_id,
          project_scope_id, stage_key, item_key, confirmed_qty, confirmed_evidence)
        values (p_project_id, v_baseline, v_cell_progress, v_item.id, v_item.project_scope_id,
          v_item.stage_key, v_item.item_key, v_new_qty, v_evidence)
        returning * into v_ip;
        insert into public.v1_accounts_billing_item_progress_revisions(
          project_id, item_progress_id, baseline_revision_id, revision_number, action,
          previous_suggested_qty, new_suggested_qty, previous_confirmed_qty, new_confirmed_qty,
          evidence, reason, actor_auth_user_id, actor_exact_role, idempotency_key)
        values (p_project_id, v_ip.id, v_baseline, 1, 'confirmed', 0, 0, 0, v_new_qty,
          v_evidence, coalesce(nullif(btrim(p_reason), ''), 'Workbench item confirmation'),
          v_actor, v_exact, md5(p_idempotency_key::text || ':i:' || v_item.id::text)::uuid);
        v_confirmed := v_confirmed + 1;
      elsif v_new_qty <> v_ip.confirmed_qty then
        if v_new_qty > v_ip.confirmed_qty and coalesce(array_length(p_evidence_document_ids, 1), 0) = 0 then
          raise exception 'R39_ACCOUNTS_EVIDENCE_REQUIRED' using errcode = '23514'; end if;
        select coalesce(max(revision_number), 0) + 1 into v_rev
        from public.v1_accounts_billing_item_progress_revisions where item_progress_id = v_ip.id;
        insert into public.v1_accounts_billing_item_progress_revisions(
          project_id, item_progress_id, baseline_revision_id, revision_number, action,
          previous_suggested_qty, new_suggested_qty, previous_confirmed_qty, new_confirmed_qty,
          evidence, reason, actor_auth_user_id, actor_exact_role, idempotency_key)
        values (p_project_id, v_ip.id, v_baseline, v_rev, 'confirmed', 0, 0,
          v_ip.confirmed_qty, v_new_qty, v_evidence,
          coalesce(nullif(btrim(p_reason), ''), 'Workbench item confirmation'),
          v_actor, v_exact, md5(p_idempotency_key::text || ':i:' || v_item.id::text)::uuid);
        update public.v1_accounts_billing_item_progress
        set confirmed_qty = v_new_qty, confirmed_evidence = v_evidence,
          record_version = record_version + 1, updated_at = v_now
        where id = v_ip.id;
        v_confirmed := v_confirmed + 1;
      end if;
      -- Keep the items-mode cell's confirmed_percent as the derived display
      -- value (eligible / stage value) so existing readers and the claim
      -- validator (confirmed_percent > 0 plus a progress revision) see the
      -- confirmation. Append a confirmed progress revision when it changes.
      select confirmed_percent into v_old_pct
      from public.v1_accounts_billing_progress where id = v_cell_progress;
      v_derived := round(
        case when public.v1_accounts_stage_value(v_cell_progress) > 0
          then public.v1_accounts_progress_eligible_amount(v_cell_progress)
            / public.v1_accounts_stage_value(v_cell_progress) * 100
          else 0 end, 4);
      if v_derived <> v_old_pct then
        select coalesce(max(revision_number), 0) + 1 into v_prog_rev
        from public.v1_accounts_billing_progress_revisions where progress_entry_id = v_cell_progress;
        insert into public.v1_accounts_billing_progress_revisions(
          project_id, progress_entry_id, baseline_revision_id, revision_number, action,
          previous_suggested_percent, new_suggested_percent,
          previous_confirmed_percent, new_confirmed_percent,
          previous_review_status, new_review_status, evidence_summary,
          evidence_document_ids, reason, actor_auth_user_id, actor_role, actor_exact_role,
          idempotency_key)
        select p_project_id, v_cell_progress, v_baseline, v_prog_rev, 'confirmed',
          bp.suggested_percent, bp.suggested_percent, v_old_pct, v_derived,
          bp.review_status, bp.review_status, nullif(btrim(p_reason), ''),
          coalesce(p_evidence_document_ids, '{}'::uuid[]),
          coalesce(nullif(btrim(p_reason), ''), 'Workbench item confirmation'),
          v_actor, public.v1_current_role(), v_exact,
          md5(p_idempotency_key::text || ':ip:' || v_cell_progress::text || ':' || v_prog_rev::text)::uuid
        from public.v1_accounts_billing_progress bp where bp.id = v_cell_progress;
        update public.v1_accounts_billing_progress
        set confirmed_percent = v_derived, confirmed_by_auth_user_id = v_actor,
          confirmed_by_exact_role = v_exact, confirmed_at = v_now,
          record_version = record_version + 1, updated_at = v_now
        where id = v_cell_progress;
      end if;
    else
      raise exception 'R39_ACCOUNTS_INVALID_WORKBENCH_ENTRY' using errcode = '22023';
    end if;
  end loop;

  -- Rebuild the single open workbench draft from current availability. A revise
  -- successor draft (supersedes_claim_id set) is a different, in-flight claim and
  -- must never be deleted here.
  delete from public.v1_accounts_client_claims
  where project_id = p_project_id and status = 'draft' and supersedes_claim_id is null;

  select coalesce(jsonb_agg(jsonb_build_object(
      'progress_entry_id', line.id,
      'claimed_amount', line.avail::text,
      'evidence_reference', coalesce(nullif(btrim(p_reason), ''), 'Prepared from workbench'))), '[]'::jsonb)
  into v_lines
  from (
    select bp.id,
      greatest(public.v1_accounts_progress_eligible_amount(bp.id)
        - public.v1_accounts_dimension_claimed_amount(
            bp.project_id, bp.project_scope_id, bp.stage_key, null), 0) as avail
    from public.v1_accounts_billing_progress bp
    where bp.baseline_revision_id = v_baseline
  ) line
  where line.avail > 0;

  if jsonb_array_length(v_lines) > 0 then
    v_claim := public.v1_create_client_claim_draft(
      p_project_id,
      coalesce(nullif(btrim(p_claim_reference), ''), 'WB-' || to_char(v_now, 'YYYYMMDDHH24MISS')),
      p_period_start, p_period_end, v_lines, nullif(btrim(p_reason), ''),
      md5(p_idempotency_key::text || ':claim')::uuid);
  end if;

  v_response := jsonb_build_object('schema_version', 1, 'replayed', false,
    'project_id', p_project_id, 'confirmed_rows', v_confirmed, 'claim', v_claim);
  perform public.v1_complete_idempotency('v1_save_claim_workbench', p_idempotency_key, v_response);
  return v_response;
end;
$$;

grant execute on function public.v1_save_claim_workbench(uuid, text, date, date, jsonb, uuid[], text, uuid)
  to authenticated;


-- #############################################################################
-- FILE 8 / 22 : 20261105140000_accounts_v2_p4_company_settings.sql
-- #############################################################################

-- R39 Accounts Workspace V2 — P4 (part a): company letterhead/bank settings (D9)
--
-- Seeds the Admin-managed company letterhead and bank settings into the existing
-- Configuration Centre allowlist (area company_regional), and wires a frozen
-- `company` block into the invoice document model so an issued invoice reprints
-- identically. Additive; existing company.* keys are untouched.
-- See R39_ACCOUNTS_WORKSPACE_V2_INTEGRATION_PLAN.md 6.9 / 9, PRODUCT_DECISIONS 32 (D9).

insert into public.v1_configuration_settings (
  setting_key, area, value_type, default_value, published_value, display_order
)
values
  ('company.trn', 'company_regional', 'string',
    to_jsonb('100026741700003'::text), to_jsonb('100026741700003'::text), 120),
  ('company.address', 'company_regional', 'string',
    to_jsonb('P.O. Box 4757, Abu Dhabi, U.A.E'::text),
    to_jsonb('P.O. Box 4757, Abu Dhabi, U.A.E'::text), 130),
  ('company.phone', 'company_regional', 'string',
    to_jsonb('02-5509788'::text), to_jsonb('02-5509788'::text), 140),
  ('company.fax', 'company_regional', 'string',
    to_jsonb('02-5509688'::text), to_jsonb('02-5509688'::text), 150),
  ('company.email', 'company_regional', 'string',
    to_jsonb('yorks_sk@yorks.ae'::text), to_jsonb('yorks_sk@yorks.ae'::text), 160),
  ('company.bank_name', 'company_regional', 'string',
    to_jsonb(''::text), to_jsonb(''::text), 170),
  ('company.bank_iban', 'company_regional', 'string',
    to_jsonb(''::text), to_jsonb(''::text), 180),
  ('company.bank_account_name', 'company_regional', 'string',
    to_jsonb(''::text), to_jsonb(''::text), 190)
on conflict (setting_key) do nothing;

-- ---------------------------------------------------------------------------
-- Re-create the invoice document builder to freeze the published company block.
-- ---------------------------------------------------------------------------
create or replace function public.v1_accounts_build_invoice_document(
  p_project_id uuid,
  p_claim_id uuid,
  p_invoice_reference text,
  p_invoice_date date,
  p_submission_date date,
  p_due_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_claim public.v1_accounts_client_claims%rowtype;
  v_baseline public.v1_accounts_baseline_revisions%rowtype;
  v_project public.v1_projects%rowtype;
  v_settings public.v1_accounts_project_invoice_settings%rowtype;
  v_ex_vat numeric(20,2);
  v_vat numeric(20,2);
  v_lines jsonb;
  v_company jsonb;
begin
  select * into v_claim from public.v1_accounts_client_claims where id = p_claim_id and project_id = p_project_id;
  if not found then raise exception 'R39_ACCOUNTS_CLAIM_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into v_baseline from public.v1_accounts_baseline_revisions where id = v_claim.baseline_revision_id;
  select * into v_project from public.v1_projects where id = p_project_id;
  select * into v_settings from public.v1_accounts_project_invoice_settings where project_id = p_project_id;

  select coalesce(sum(line.claimed_amount), 0)::numeric(20,2) into v_ex_vat
  from public.v1_accounts_client_claim_lines line where line.claim_id = p_claim_id;
  v_vat := round(v_ex_vat * v_baseline.vat_rate_percent / 100, 2);

  select coalesce(jsonb_agg(jsonb_build_object(
      'building_scope_id', line.project_scope_id,
      'building_name', scope.name,
      'stage_key', line.stage_key,
      'stage_label', stage.stage_name,
      'amount', line.amount::text
    ) order by stage.display_order, scope.name), '[]'::jsonb) into v_lines
  from (
    select l.project_scope_id, l.stage_key, sum(l.claimed_amount) as amount
    from public.v1_accounts_client_claim_lines l where l.claim_id = p_claim_id
    group by l.project_scope_id, l.stage_key
  ) line
  join public.v1_project_scopes scope on scope.id = line.project_scope_id
  left join public.v1_accounts_baseline_stage_allocations stage
    on stage.baseline_revision_id = v_claim.baseline_revision_id and stage.stage_key = line.stage_key;

  -- Frozen published company letterhead/bank block.
  select coalesce(jsonb_object_agg(replace(setting_key, 'company.', ''), published_value), '{}'::jsonb)
  into v_company
  from public.v1_configuration_settings where setting_key like 'company.%';

  return jsonb_build_object(
    'schema_version', 1,
    'invoice_reference', p_invoice_reference,
    'invoice_date', p_invoice_date,
    'submission_date', p_submission_date,
    'due_date', p_due_date,
    'payment_terms_days', v_baseline.payment_terms_days,
    'currency_code', v_baseline.currency_code,
    'company', v_company,
    'project', jsonb_build_object('project_id', v_project.id, 'project_ref', v_project.project_ref, 'name', v_project.name),
    'claim', jsonb_build_object('claim_id', v_claim.id, 'claim_reference', v_claim.claim_reference,
      'period_start', v_claim.claim_period_start, 'period_end', v_claim.claim_period_end),
    'settings', jsonb_build_object('invoice_prefix', v_settings.invoice_prefix,
      'scope_line', v_settings.scope_line, 'attention_name', v_settings.attention_name,
      'bill_to_party_id', v_settings.bill_to_party_id),
    'amounts', jsonb_build_object('ex_vat', v_ex_vat::text,
      'vat_rate_percent', v_baseline.vat_rate_percent::text, 'vat', v_vat::text,
      'total_incl_vat', (v_ex_vat + v_vat)::text),
    'lines', v_lines
  );
end;
$$;


-- #############################################################################
-- FILE 9 / 22 : 20261105150000_accounts_v2_p4_workspace.sql
-- #############################################################################

-- R39 Accounts Workspace V2 — P4 (part b): Summary workspace projection
--
-- v1_get_project_accounts_workspace is the one call behind the V2 Summary tab:
-- the 4-step strip, the ex-VAT money-flow bar, KPIs, a server-derived attention
-- list, the building x stage invoiced heatmap, and the cash position. Monetary
-- keys are omitted (not zeroed) without view_project_commercial_values; supplier
-- and cash keys need view_supplier_costs (AT-SEC-001/008). It reuses the same
-- invoice/supplier filters as v1_get_project_accounts_overview, so the retired
-- (cancelled) superseded predecessors drop out automatically.
--
-- Additive, accounts-only, read-only. The advisory site-record suggestions
-- (6.8) ship with their mapping UI in P8. See
-- R39_ACCOUNTS_WORKSPACE_V2_INTEGRATION_PLAN.md 6.7.

create or replace function public.v1_get_project_accounts_workspace(
  p_project_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_can_view boolean;
  v_can_values boolean;
  v_can_supplier boolean;
  v_project public.v1_projects%rowtype;
  v_profile public.v1_accounts_project_commercial_profiles%rowtype;
  v_baseline public.v1_accounts_baseline_revisions%rowtype;
  v_contract numeric(20,2) := 0;
  v_vatf numeric := 1;
  v_invoiced numeric := 0;
  v_received numeric := 0;
  v_certified numeric := 0;
  v_pdc numeric := 0;
  v_still_due numeric := 0;
  v_draft numeric := 0;
  v_bills_total numeric := 0;
  v_bills_paid numeric := 0;
  v_bills_open numeric := 0;
  v_bills_overdue integer := 0;
  v_open_claim_id uuid;
  v_open_claim_gross numeric := 0;
  v_progress_any boolean := false;
  v_invoice_any boolean := false;
  v_paid_ex numeric := 0;
  v_heatmap jsonb := '[]'::jsonb;
  v_attention jsonb := '[]'::jsonb;
  v_result jsonb;
begin
  if auth.uid() is null or p_project_id is null or not public.v1_current_actor_is_active() then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501'; end if;
  v_can_view := public.v1_current_user_has_capability('view_project_accounts', p_project_id);
  v_can_values := public.v1_current_user_has_capability('view_project_commercial_values', p_project_id);
  v_can_supplier := public.v1_current_user_has_capability('view_supplier_costs', p_project_id);
  if not v_can_view and not v_can_supplier then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501'; end if;
  select * into v_project from public.v1_projects where id = p_project_id;
  if not found then raise exception 'R39_ACCOUNTS_PROJECT_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into v_profile from public.v1_accounts_project_commercial_profiles where project_id = p_project_id;
  if found and v_profile.current_baseline_revision_id is not null then
    select * into v_baseline from public.v1_accounts_baseline_revisions where id = v_profile.current_baseline_revision_id;
    v_contract := coalesce(v_baseline.contract_value, 0);
    v_vatf := 1 + coalesce(v_baseline.vat_rate_percent, 0) / 100;
    v_progress_any := exists (select 1 from public.v1_accounts_billing_progress
      where baseline_revision_id = v_baseline.id and confirmed_percent > 0);
  end if;

  select coalesce(sum(case when i.status not in ('draft','returned','cancelled') then i.claimed_ex_vat else 0 end), 0),
         coalesce(sum(case when i.status <> 'cancelled' then public.v1_accounts_invoice_paid_amount(i.id) else 0 end), 0),
         coalesce(sum(case when i.status <> 'cancelled' then public.v1_accounts_invoice_certified_incl_vat(i.id) else 0 end), 0),
         coalesce(sum(case when i.status <> 'cancelled' then public.v1_accounts_invoice_pdc_exposure(i.id) else 0 end), 0),
         greatest(coalesce(sum(case when i.status <> 'cancelled'
           then public.v1_accounts_invoice_certified_incl_vat(i.id) - public.v1_accounts_invoice_paid_amount(i.id)
           else 0 end), 0), 0),
         bool_or(i.status not in ('draft','cancelled'))
    into v_invoiced, v_received, v_certified, v_pdc, v_still_due, v_invoice_any
  from public.v1_accounts_client_invoices i where i.project_id = p_project_id;
  v_invoice_any := coalesce(v_invoice_any, false);

  select coalesce(sum(l.claimed_amount), 0) into v_draft
  from public.v1_accounts_client_claim_lines l
  join public.v1_accounts_client_claims c on c.id = l.claim_id
  where c.project_id = p_project_id and c.status in ('draft', 'ready_for_accounts');

  select c.id, coalesce((select sum(l.claimed_amount) from public.v1_accounts_client_claim_lines l where l.claim_id = c.id), 0)
    into v_open_claim_id, v_open_claim_gross
  from public.v1_accounts_client_claims c
  where c.project_id = p_project_id and c.status = 'draft'
  order by c.updated_at desc limit 1;

  if v_can_supplier then
    select coalesce(sum(case when b.status <> 'cancelled' then b.total_incl_vat else 0 end), 0),
           coalesce(sum(case when b.status <> 'cancelled' then public.v1_accounts_supplier_paid_amount(b.id) else 0 end), 0),
           coalesce(sum(case when b.status <> 'cancelled' then greatest(b.total_incl_vat - public.v1_accounts_supplier_paid_amount(b.id), 0) else 0 end), 0),
           count(*) filter (where b.status <> 'cancelled' and b.due_date < current_date
             and public.v1_accounts_supplier_paid_amount(b.id) < b.total_incl_vat)
      into v_bills_total, v_bills_paid, v_bills_open, v_bills_overdue
    from public.v1_accounts_supplier_bills b where b.project_id = p_project_id;
  end if;

  v_paid_ex := round(least(v_received / v_vatf, v_invoiced), 2);

  -- Heatmap: invoiced % per current building x stage cell.
  if v_can_view and v_can_values and v_baseline.id is not null then
    select coalesce(jsonb_agg(cell order by ord, bname), '[]'::jsonb) into v_heatmap from (
      select sa.display_order as ord, scope.name as bname,
        jsonb_build_object('building_scope_id', bp.project_scope_id, 'building_name', scope.name,
          'stage_key', bp.stage_key, 'stage_label', sa.stage_name,
          'stage_value', public.v1_accounts_stage_value(bp.id)::text,
          'invoiced_amount', inv.amount::text,
          'invoiced_percent', case when public.v1_accounts_stage_value(bp.id) > 0
            then round(inv.amount / public.v1_accounts_stage_value(bp.id) * 100, 1) else 0 end::text) as cell
      from public.v1_accounts_billing_progress bp
      join public.v1_accounts_baseline_stage_allocations sa
        on sa.baseline_revision_id = bp.baseline_revision_id and sa.stage_key = bp.stage_key
      join public.v1_project_scopes scope on scope.id = bp.project_scope_id
      left join lateral (
        select coalesce(sum(l.claimed_amount), 0) as amount
        from public.v1_accounts_client_claim_lines l
        join public.v1_accounts_client_claims c on c.id = l.claim_id
        where c.project_id = p_project_id and c.status = 'invoiced'
          and l.project_scope_id = bp.project_scope_id and l.stage_key = bp.stage_key
      ) inv on true
      where bp.baseline_revision_id = v_baseline.id
    ) cells;
  end if;

  -- Attention (server-derived).
  if v_baseline.id is null then
    v_attention := v_attention || jsonb_build_array(jsonb_build_object(
      'severity', 'bad', 'kind', 'setup_incomplete', 'action_key', 'open_contract',
      'target_type', 'project', 'target_id', p_project_id));
  elsif v_can_values then
    v_attention := v_attention || coalesce((select jsonb_agg(jsonb_build_object(
        'severity', 'bad', 'kind', 'invoice_overdue', 'action_key', 'open_invoice',
        'target_type', 'invoice', 'target_id', i.id))
      from public.v1_accounts_client_invoices i where i.project_id = p_project_id
        and i.status not in ('draft','returned','cancelled','paid') and i.due_date < current_date), '[]'::jsonb);
    v_attention := v_attention || coalesce((select jsonb_agg(jsonb_build_object(
        'severity', 'pri', 'kind', 'awaiting_certification', 'action_key', 'certify',
        'target_type', 'invoice', 'target_id', i.id))
      from public.v1_accounts_client_invoices i where i.project_id = p_project_id and i.status = 'submitted'
        and not exists (select 1 from public.v1_accounts_client_certifications c where c.invoice_id = i.id)), '[]'::jsonb);
    if v_open_claim_id is not null and v_open_claim_gross > 0 then
      v_attention := v_attention || jsonb_build_array(jsonb_build_object('severity','ok','kind','claim_ready',
        'action_key','open_claim','target_type','claim','target_id',v_open_claim_id));
    elsif v_open_claim_id is not null then
      v_attention := v_attention || jsonb_build_array(jsonb_build_object('severity','pri','kind','claim_empty',
        'action_key','open_claim','target_type','claim','target_id',v_open_claim_id));
    elsif v_contract > 0 then
      v_attention := v_attention || jsonb_build_array(jsonb_build_object('severity','pri','kind','no_claim',
        'action_key','start_claim','target_type','project','target_id',p_project_id));
    end if;
    if v_pdc > 0 then
      v_attention := v_attention || jsonb_build_array(jsonb_build_object('severity','pri','kind','cheques_in_hand',
        'action_key','open_invoices','target_type','project','target_id',p_project_id));
    end if;
  end if;
  if v_can_supplier and v_bills_overdue > 0 then
    v_attention := v_attention || jsonb_build_array(jsonb_build_object('severity','warn','kind','supplier_overdue',
      'action_key','open_supplier_bills','target_type','project','target_id',p_project_id,
      'params', jsonb_build_object('count', v_bills_overdue)));
  end if;

  v_result := jsonb_build_object(
    'schema_version', 1, 'project_id', v_project.id,
    'project_reference', v_project.project_ref, 'project_name', v_project.name,
    'has_baseline', v_baseline.id is not null,
    'capabilities', jsonb_build_object('view_project_accounts', v_can_view,
      'view_project_commercial_values', v_can_values, 'view_supplier_costs', v_can_supplier),
    'steps', jsonb_build_array(
      jsonb_build_object('key','setup', 'state', case when v_baseline.id is not null then 'done' else 'current' end),
      jsonb_build_object('key','progress', 'state', case when v_progress_any then 'done' when v_baseline.id is not null then 'current' else '' end),
      jsonb_build_object('key','invoice', 'state', case when v_invoice_any then 'done' when v_progress_any then 'current' else '' end),
      jsonb_build_object('key','paid', 'state', case when v_received > 0 and v_still_due <= 0 and v_invoice_any then 'done' when v_invoice_any then 'current' else '' end)),
    'attention', v_attention);

  if v_can_values then
    v_result := v_result || jsonb_build_object(
      'money_flow', jsonb_build_object(
        'paid', v_paid_ex::text,
        'invoiced_waiting', greatest(v_invoiced - v_paid_ex, 0)::text,
        'done_not_invoiced', v_draft::text,
        'remaining', greatest(v_contract - v_invoiced - v_draft, 0)::text),
      'kpis', jsonb_build_object(
        'contract_value', v_contract::text,
        'contract_incl_vat', round(v_contract * v_vatf, 2)::text,
        'invoiced', v_invoiced::text,
        'received', v_received::text,
        'certified', v_certified::text,
        'outstanding', v_still_due::text,
        'cheques_in_hand', v_pdc::text,
        'done_not_invoiced', v_draft::text),
      'heatmap', v_heatmap);
  end if;
  if v_can_supplier then
    v_result := v_result || jsonb_build_object(
      'supplier', jsonb_build_object('billed', v_bills_total::text, 'paid', v_bills_paid::text,
        'unpaid', v_bills_open::text, 'overdue_count', v_bills_overdue),
      'cash', jsonb_build_object('received', v_received::text, 'paid_to_suppliers', v_bills_paid::text,
        'net', (v_received - v_bills_paid)::text));
  end if;
  return v_result;
end;
$$;

revoke all on function public.v1_get_project_accounts_workspace(uuid) from public, anon;
grant execute on function public.v1_get_project_accounts_workspace(uuid) to authenticated, service_role;


-- #############################################################################
-- FILE 10 / 22 : 20261105160000_accounts_v2_p6_commercial_setup_read.sql
-- #############################################################################

-- R39 Accounts Workspace V2 — P6 (part a): commercial-setup read
--
-- v1_get_project_commercial_setup seeds the V2 Contract tab: the contract
-- header (value, VAT, terms, currency), per-project invoice numbering settings,
-- the building split (name, share %, value), the billing stages (name, share %,
-- measurement mode, value) and, for items-mode stages, the per-building item
-- breakdown (qty, unit, weight %, value). Values reuse the existing billing
-- value helpers so a displayed amount equals the amount billing uses.
--
-- The Contract surface is commercial: it requires view_project_accounts, and
-- without view_project_commercial_values it returns only capabilities and the
-- has_baseline flag — no amounts and no split (AT-SEC-001/008). Amounts are
-- decimal strings; percentages and quantities are structural, not currency.
--
-- Additive, accounts-only, read-only. No table or policy changes. The client
-- fields, work-order/contract references, retention and variations shown in the
-- prototype have no backing columns in the V1 schema and are out of scope here.

create or replace function public.v1_get_project_commercial_setup(
  p_project_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_can_view boolean;
  v_can_values boolean;
  v_can_configure boolean;
  v_project public.v1_projects%rowtype;
  v_profile public.v1_accounts_project_commercial_profiles%rowtype;
  v_baseline public.v1_accounts_baseline_revisions%rowtype;
  v_settings public.v1_accounts_project_invoice_settings%rowtype;
  v_contract numeric(20,2) := 0;
  v_buildings jsonb := '[]'::jsonb;
  v_stages jsonb := '[]'::jsonb;
  v_items jsonb := '[]'::jsonb;
  v_result jsonb;
begin
  if auth.uid() is null or p_project_id is null
     or not public.v1_current_actor_is_active() then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
  end if;
  v_can_view := public.v1_current_user_has_capability(
    'view_project_accounts', p_project_id);
  if not v_can_view then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
  end if;
  v_can_values := public.v1_current_user_has_capability(
    'view_project_commercial_values', p_project_id);
  v_can_configure := public.v1_current_user_has_capability(
    'configure_project_commercials', p_project_id);

  select * into v_project from public.v1_projects where id = p_project_id;
  if not found then
    raise exception 'R39_ACCOUNTS_PROJECT_NOT_FOUND' using errcode = 'P0002';
  end if;

  select * into v_profile
  from public.v1_accounts_project_commercial_profiles
  where project_id = p_project_id;
  if found and v_profile.current_baseline_revision_id is not null then
    select * into v_baseline from public.v1_accounts_baseline_revisions
    where id = v_profile.current_baseline_revision_id;
    v_contract := coalesce(v_baseline.contract_value, 0);
  end if;

  v_result := jsonb_build_object(
    'schema_version', 1,
    'project_id', v_project.id,
    'project_reference', v_project.project_ref,
    'project_name', v_project.name,
    'has_baseline', v_baseline.id is not null,
    'capabilities', jsonb_build_object(
      'view_project_accounts', v_can_view,
      'view_project_commercial_values', v_can_values,
      'configure_project_commercials', v_can_configure),
    'can_configure', v_can_configure);

  -- Commercial surface: no amounts or split without commercial-value access.
  if not v_can_values then
    return v_result;
  end if;

  select * into v_settings
  from public.v1_accounts_project_invoice_settings
  where project_id = p_project_id;

  if v_baseline.id is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
        'project_scope_id', b.project_scope_id,
        'name', s.name,
        'scope_kind', s.scope_kind,
        'allocation_percent', b.allocation_percent::text,
        'value', round(v_contract * b.allocation_percent / 100, 2)::text
      ) order by s.scope_kind, s.name), '[]'::jsonb)
      into v_buildings
    from public.v1_accounts_baseline_building_allocations b
    join public.v1_project_scopes s on s.id = b.project_scope_id
    where b.baseline_revision_id = v_baseline.id;

    select coalesce(jsonb_agg(jsonb_build_object(
        'stage_key', st.stage_key,
        'stage_name', st.stage_name,
        'display_order', st.display_order,
        'measurement_mode', st.measurement_mode,
        'allocation_percent', st.allocation_percent::text,
        'value', round(v_contract * st.allocation_percent / 100, 2)::text
      ) order by st.display_order), '[]'::jsonb)
      into v_stages
    from public.v1_accounts_baseline_stage_allocations st
    where st.baseline_revision_id = v_baseline.id;

    select coalesce(jsonb_agg(jsonb_build_object(
        'project_scope_id', it.project_scope_id,
        'building_name', s.name,
        'stage_key', it.stage_key,
        'item_key', it.item_key,
        'item_label', it.item_label,
        'display_order', it.display_order,
        'quantity', it.quantity::text,
        'unit_code', it.unit_code,
        'weight_percent_of_contract', it.weight_percent_of_contract::text,
        'value', public.v1_accounts_stage_item_value(it.id)::text
      ) order by s.name, it.stage_key, it.display_order), '[]'::jsonb)
      into v_items
    from public.v1_accounts_baseline_stage_items it
    join public.v1_project_scopes s on s.id = it.project_scope_id
    where it.baseline_revision_id = v_baseline.id;

    v_result := v_result || jsonb_build_object(
      'profile_version', v_profile.record_version,
      'revision_number', v_baseline.revision_number,
      'currency_code', v_baseline.currency_code,
      'contract_value', v_contract::text,
      'contract_incl_vat',
        round(v_contract * (1 + v_baseline.vat_rate_percent / 100), 2)::text,
      'vat_rate_percent', v_baseline.vat_rate_percent::text,
      'payment_terms_days', v_baseline.payment_terms_days,
      'reminder_lead_days', v_baseline.reminder_lead_days,
      'buildings', v_buildings,
      'stages', v_stages,
      'items', v_items);
  else
    v_result := v_result || jsonb_build_object(
      'profile_version',
        case when v_profile.project_id is not null
          then v_profile.record_version else null end,
      'currency_code', null,
      'buildings', '[]'::jsonb,
      'stages', '[]'::jsonb,
      'items', '[]'::jsonb);
  end if;

  if v_settings.project_id is not null then
    v_result := v_result || jsonb_build_object(
      'invoice_settings', jsonb_build_object(
        'invoice_prefix', v_settings.invoice_prefix,
        'next_sequence', v_settings.next_sequence,
        'scope_line', v_settings.scope_line,
        'attention_name', v_settings.attention_name,
        'bill_to_party_id', v_settings.bill_to_party_id,
        'record_version', v_settings.record_version));
  else
    v_result := v_result || jsonb_build_object('invoice_settings', null);
  end if;

  return v_result;
end;
$$;

revoke all on function public.v1_get_project_commercial_setup(uuid)
  from public, anon;
grant execute on function public.v1_get_project_commercial_setup(uuid)
  to authenticated, service_role;


-- #############################################################################
-- FILE 11 / 22 : 20261105170000_accounts_v2_p8_pdc_register.sql
-- #############################################################################

-- R39 Accounts Workspace V2 — P8: project-wide cheque (PDC) register read
--
-- v1_list_project_client_pdcs returns every client post-dated cheque for a
-- project (one row per cheque, current state) joined to its invoice reference,
-- so the Invoices & payments tab can render a standalone cheque register with
-- the In-hand -> Deposited -> Cleared/Bounced lifecycle. The PDC lifecycle
-- transitions themselves reuse the existing v1_transition_client_pdc command.
--
-- Cheques are commercial, so this requires view_project_commercial_values
-- (and view_project_accounts); amounts are decimal strings. Additive,
-- accounts-only, read-only.

create or replace function public.v1_list_project_client_pdcs(p_project_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_project public.v1_projects%rowtype;
  v_pdcs jsonb;
begin
  if auth.uid() is null or p_project_id is null
     or not public.v1_current_actor_is_active() then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
  end if;
  if not public.v1_current_user_has_capability('view_project_accounts', p_project_id)
     or not public.v1_current_user_has_capability(
       'view_project_commercial_values', p_project_id) then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
  end if;
  select * into v_project from public.v1_projects where id = p_project_id;
  if not found then
    raise exception 'R39_ACCOUNTS_PROJECT_NOT_FOUND' using errcode = 'P0002';
  end if;

  select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'pdc_id', pdc.id,
          'invoice_id', pdc.invoice_id,
          'invoice_reference', inv.invoice_reference,
          'cheque_number', pdc.cheque_number,
          'cheque_date', pdc.cheque_date,
          'received_date', pdc.received_date,
          'bank_name', pdc.bank_name,
          'amount', pdc.amount::text,
          'status', pdc.status,
          'action_required', pdc.action_required,
          'record_version', pdc.record_version
        )
        order by pdc.cheque_date desc, pdc.created_at desc
      ),
      '[]'::jsonb
    )
    into v_pdcs
  from public.v1_accounts_client_pdcs pdc
  join public.v1_accounts_client_invoices inv on inv.id = pdc.invoice_id
  where pdc.project_id = p_project_id;

  return jsonb_build_object(
    'schema_version', 1,
    'project_id', v_project.id,
    'pdcs', v_pdcs
  );
end;
$$;

revoke all on function public.v1_list_project_client_pdcs(uuid) from public, anon;
grant execute on function public.v1_list_project_client_pdcs(uuid)
  to authenticated, service_role;


-- #############################################################################
-- FILE 12 / 22 : 20261106120000_accounts_v2_p7_invoice_document_pages.sql
-- #############################################################################

-- R39 Accounts Workspace V2 — P7 (part b): invoice document summary pages
--
-- The tax-invoice PDF so far rendered only the stage-level invoice page. Yorks'
-- real invoice (and the approved prototype) also carry a Main Summary matrix
-- (per stage: contract / till-previous / this-month / total completion) and a
-- per-building breakdown. All of it is derivable from what the claim already
-- snapshots per building x stage (stage_value_snapshot, previously_claimed and
-- claimed), so this re-creates v1_accounts_build_invoice_document to add two
-- additive blocks — `summary` and `buildings` — without touching the existing
-- keys or the frozen amounts. Every figure uses the same round-each-cell model
-- as the invoice total (D4 / Option A), so the per-building lines sum exactly to
-- the printed gross.
--
-- Additive, accounts-only, read-only shape change (a wider document snapshot).

create or replace function public.v1_accounts_build_invoice_document(
  p_project_id uuid,
  p_claim_id uuid,
  p_invoice_reference text,
  p_invoice_date date,
  p_submission_date date,
  p_due_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_claim public.v1_accounts_client_claims%rowtype;
  v_baseline public.v1_accounts_baseline_revisions%rowtype;
  v_project public.v1_projects%rowtype;
  v_settings public.v1_accounts_project_invoice_settings%rowtype;
  v_ex_vat numeric(20,2);
  v_vat numeric(20,2);
  v_prev_total numeric(20,2);
  v_lines jsonb;
  v_company jsonb;
  v_summary_stages jsonb;
  v_buildings jsonb;
begin
  select * into v_claim from public.v1_accounts_client_claims where id = p_claim_id and project_id = p_project_id;
  if not found then raise exception 'R39_ACCOUNTS_CLAIM_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into v_baseline from public.v1_accounts_baseline_revisions where id = v_claim.baseline_revision_id;
  select * into v_project from public.v1_projects where id = p_project_id;
  select * into v_settings from public.v1_accounts_project_invoice_settings where project_id = p_project_id;

  select coalesce(sum(line.claimed_amount), 0)::numeric(20,2) into v_ex_vat
  from public.v1_accounts_client_claim_lines line where line.claim_id = p_claim_id;
  v_vat := round(v_ex_vat * v_baseline.vat_rate_percent / 100, 2);
  select coalesce(sum(line.previously_claimed_amount_snapshot), 0)::numeric(20,2)
  into v_prev_total
  from public.v1_accounts_client_claim_lines line where line.claim_id = p_claim_id;

  select coalesce(jsonb_agg(jsonb_build_object(
      'building_scope_id', line.project_scope_id,
      'building_name', scope.name,
      'stage_key', line.stage_key,
      'stage_label', stage.stage_name,
      'amount', line.amount::text
    ) order by stage.display_order, scope.name), '[]'::jsonb) into v_lines
  from (
    select l.project_scope_id, l.stage_key, sum(l.claimed_amount) as amount
    from public.v1_accounts_client_claim_lines l where l.claim_id = p_claim_id
    group by l.project_scope_id, l.stage_key
  ) line
  join public.v1_project_scopes scope on scope.id = line.project_scope_id
  left join public.v1_accounts_baseline_stage_allocations stage
    on stage.baseline_revision_id = v_claim.baseline_revision_id and stage.stage_key = line.stage_key;

  -- Full building x stage grid for the claim's baseline (every cell, including
  -- the ones not claimed this invoice), with the claim's previous/this amounts
  -- left-joined in. Cell value uses the engine's stage-value distribution.
  with grid as (
    select
      bp.project_scope_id,
      scope.name as building_name,
      ba.allocation_percent as building_pct,
      bp.stage_key,
      sa.stage_name,
      sa.display_order,
      sa.allocation_percent as stage_pct,
      public.v1_accounts_stage_value(bp.id)::numeric(20,2) as stage_value,
      coalesce(cl.previously_claimed_amount_snapshot, 0)::numeric(20,2) as prev_amt,
      coalesce(cl.claimed_amount, 0)::numeric(20,2) as this_amt
    from public.v1_accounts_billing_progress bp
    join public.v1_project_scopes scope on scope.id = bp.project_scope_id
    join public.v1_accounts_baseline_building_allocations ba
      on ba.baseline_revision_id = bp.baseline_revision_id
      and ba.project_scope_id = bp.project_scope_id
    join public.v1_accounts_baseline_stage_allocations sa
      on sa.baseline_revision_id = bp.baseline_revision_id
      and sa.stage_key = bp.stage_key
    left join public.v1_accounts_client_claim_lines cl
      on cl.claim_id = p_claim_id
      and cl.project_scope_id = bp.project_scope_id
      and cl.stage_key = bp.stage_key
    where bp.baseline_revision_id = v_claim.baseline_revision_id
  )
  select
    (
      select coalesce(jsonb_agg(jsonb_build_object(
          'stage_key', s.stage_key,
          'stage_label', s.stage_name,
          'contract_percent', s.stage_pct::text,
          'contract_amount', s.cval::text,
          'previous_amount', s.prev::text,
          'this_amount', s.this::text,
          'total_amount', (s.prev + s.this)::text
        ) order by s.display_order), '[]'::jsonb)
      from (
        select g.stage_key, g.stage_name, g.display_order, g.stage_pct,
          sum(g.stage_value) as cval, sum(g.prev_amt) as prev, sum(g.this_amt) as this
        from grid g
        group by g.stage_key, g.stage_name, g.display_order, g.stage_pct
      ) s
    ),
    (
      select coalesce(jsonb_agg(jsonb_build_object(
          'building_scope_id', b.project_scope_id,
          'name', b.building_name,
          'share_percent', b.building_pct::text,
          'building_value', b.bval::text,
          'previous_amount', b.prev::text,
          'this_amount', b.this::text,
          'total_amount', (b.prev + b.this)::text,
          'stages', b.stages
        ) order by b.building_name), '[]'::jsonb)
      from (
        select g.project_scope_id, g.building_name, g.building_pct,
          sum(g.stage_value) as bval, sum(g.prev_amt) as prev, sum(g.this_amt) as this,
          jsonb_agg(jsonb_build_object(
            'stage_key', g.stage_key,
            'stage_label', g.stage_name,
            'stage_value', g.stage_value::text,
            'previous_amount', g.prev_amt::text,
            'this_amount', g.this_amt::text,
            'total_amount', (g.prev_amt + g.this_amt)::text
          ) order by g.display_order) as stages
        from grid g
        group by g.project_scope_id, g.building_name, g.building_pct
      ) b
    )
  into v_summary_stages, v_buildings;

  -- Frozen published company letterhead/bank block.
  select coalesce(jsonb_object_agg(replace(setting_key, 'company.', ''), published_value), '{}'::jsonb)
  into v_company
  from public.v1_configuration_settings where setting_key like 'company.%';

  return jsonb_build_object(
    'schema_version', 2,
    'invoice_reference', p_invoice_reference,
    'invoice_date', p_invoice_date,
    'submission_date', p_submission_date,
    'due_date', p_due_date,
    'payment_terms_days', v_baseline.payment_terms_days,
    'currency_code', v_baseline.currency_code,
    'company', v_company,
    'project', jsonb_build_object('project_id', v_project.id, 'project_ref', v_project.project_ref, 'name', v_project.name),
    'claim', jsonb_build_object('claim_id', v_claim.id, 'claim_reference', v_claim.claim_reference,
      'period_start', v_claim.claim_period_start, 'period_end', v_claim.claim_period_end),
    'settings', jsonb_build_object('invoice_prefix', v_settings.invoice_prefix,
      'scope_line', v_settings.scope_line, 'attention_name', v_settings.attention_name,
      'bill_to_party_id', v_settings.bill_to_party_id),
    'amounts', jsonb_build_object('ex_vat', v_ex_vat::text,
      'vat_rate_percent', v_baseline.vat_rate_percent::text, 'vat', v_vat::text,
      'total_incl_vat', (v_ex_vat + v_vat)::text),
    'contract_value', v_baseline.contract_value::text,
    'summary', jsonb_build_object(
      'contract_total', v_baseline.contract_value::text,
      'previous_total', v_prev_total::text,
      'this_total', v_ex_vat::text,
      'total_total', (v_prev_total + v_ex_vat)::text,
      'stages', coalesce(v_summary_stages, '[]'::jsonb)
    ),
    'buildings', coalesce(v_buildings, '[]'::jsonb),
    'lines', v_lines
  );
end;
$$;


-- #############################################################################
-- FILE 13 / 22 : 20261106140000_accounts_v2_p4_workspace_step_detail.sql
-- #############################################################################

-- R39 Accounts Workspace V2 — P4 (part c): enrich the Summary workspace steps
--
-- The prototype's four-step strip shows a second line of status + figures under
-- each step ("AED 17,192,000 · 4 buildings · 5 stages", "Claim #03 in progress ·
-- AED 27,507", "2 issued · latest YRA32202R.1", "AED 1,805,160 in · … to come").
-- v1_get_project_accounts_workspace previously returned only {key,state} per step,
-- so the client could not render those. This CREATE OR REPLACE adds a per-step
-- `detail` object and a small `badges` object (open-draft-claim flag, overdue
-- supplier-bill count) for the tab badges.
--
-- Additive, accounts-only, read-only. No table, row, status or existing-key
-- change — every key the prior version returned is returned unchanged, so the
-- V1 schema_version-1 readers keep working. Monetary step figures stay gated by
-- view_project_commercial_values exactly like the KPIs: without it the steps are
-- label-only (no `detail`). The draft-claim badge is a workflow flag, not a
-- commercial value, so it is always present; the supplier badge needs
-- view_supplier_costs. See R39_ACCOUNTS_WORKSPACE_V2_INTEGRATION_PLAN.md 6.7 and
-- PRODUCT_DECISIONS.md.

create or replace function public.v1_get_project_accounts_workspace(
  p_project_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_can_view boolean;
  v_can_values boolean;
  v_can_supplier boolean;
  v_project public.v1_projects%rowtype;
  v_profile public.v1_accounts_project_commercial_profiles%rowtype;
  v_baseline public.v1_accounts_baseline_revisions%rowtype;
  v_contract numeric(20,2) := 0;
  v_vatf numeric := 1;
  v_invoiced numeric := 0;
  v_received numeric := 0;
  v_certified numeric := 0;
  v_pdc numeric := 0;
  v_still_due numeric := 0;
  v_draft numeric := 0;
  v_bills_total numeric := 0;
  v_bills_paid numeric := 0;
  v_bills_open numeric := 0;
  v_bills_overdue integer := 0;
  v_open_claim_id uuid;
  v_open_claim_ref text;
  v_open_claim_gross numeric := 0;
  v_building_count integer := 0;
  v_stage_count integer := 0;
  v_invoice_count integer := 0;
  v_latest_invoice_ref text;
  v_progress_any boolean := false;
  v_invoice_any boolean := false;
  v_paid_ex numeric := 0;
  v_setup_state text;
  v_progress_state text;
  v_invoice_state text;
  v_paid_state text;
  v_steps jsonb;
  v_heatmap jsonb := '[]'::jsonb;
  v_attention jsonb := '[]'::jsonb;
  v_result jsonb;
begin
  if auth.uid() is null or p_project_id is null or not public.v1_current_actor_is_active() then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501'; end if;
  v_can_view := public.v1_current_user_has_capability('view_project_accounts', p_project_id);
  v_can_values := public.v1_current_user_has_capability('view_project_commercial_values', p_project_id);
  v_can_supplier := public.v1_current_user_has_capability('view_supplier_costs', p_project_id);
  if not v_can_view and not v_can_supplier then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501'; end if;
  select * into v_project from public.v1_projects where id = p_project_id;
  if not found then raise exception 'R39_ACCOUNTS_PROJECT_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into v_profile from public.v1_accounts_project_commercial_profiles where project_id = p_project_id;
  if found and v_profile.current_baseline_revision_id is not null then
    select * into v_baseline from public.v1_accounts_baseline_revisions where id = v_profile.current_baseline_revision_id;
    v_contract := coalesce(v_baseline.contract_value, 0);
    v_vatf := 1 + coalesce(v_baseline.vat_rate_percent, 0) / 100;
    v_progress_any := exists (select 1 from public.v1_accounts_billing_progress
      where baseline_revision_id = v_baseline.id and confirmed_percent > 0);
    select count(distinct project_scope_id), count(distinct stage_key)
      into v_building_count, v_stage_count
    from public.v1_accounts_billing_progress where baseline_revision_id = v_baseline.id;
  end if;

  select coalesce(sum(case when i.status not in ('draft','returned','cancelled') then i.claimed_ex_vat else 0 end), 0),
         coalesce(sum(case when i.status <> 'cancelled' then public.v1_accounts_invoice_paid_amount(i.id) else 0 end), 0),
         coalesce(sum(case when i.status <> 'cancelled' then public.v1_accounts_invoice_certified_incl_vat(i.id) else 0 end), 0),
         coalesce(sum(case when i.status <> 'cancelled' then public.v1_accounts_invoice_pdc_exposure(i.id) else 0 end), 0),
         greatest(coalesce(sum(case when i.status <> 'cancelled'
           then public.v1_accounts_invoice_certified_incl_vat(i.id) - public.v1_accounts_invoice_paid_amount(i.id)
           else 0 end), 0), 0),
         bool_or(i.status not in ('draft','cancelled')),
         count(*) filter (where i.status not in ('draft','cancelled'))
    into v_invoiced, v_received, v_certified, v_pdc, v_still_due, v_invoice_any, v_invoice_count
  from public.v1_accounts_client_invoices i where i.project_id = p_project_id;
  v_invoice_any := coalesce(v_invoice_any, false);
  v_invoice_count := coalesce(v_invoice_count, 0);

  select i.invoice_reference into v_latest_invoice_ref
  from public.v1_accounts_client_invoices i
  where i.project_id = p_project_id and i.status not in ('draft','cancelled')
  order by i.created_at desc limit 1;

  select coalesce(sum(l.claimed_amount), 0) into v_draft
  from public.v1_accounts_client_claim_lines l
  join public.v1_accounts_client_claims c on c.id = l.claim_id
  where c.project_id = p_project_id and c.status in ('draft', 'ready_for_accounts');

  select c.id, c.claim_reference,
         coalesce((select sum(l.claimed_amount) from public.v1_accounts_client_claim_lines l where l.claim_id = c.id), 0)
    into v_open_claim_id, v_open_claim_ref, v_open_claim_gross
  from public.v1_accounts_client_claims c
  where c.project_id = p_project_id and c.status = 'draft'
  order by c.updated_at desc limit 1;

  if v_can_supplier then
    select coalesce(sum(case when b.status <> 'cancelled' then b.total_incl_vat else 0 end), 0),
           coalesce(sum(case when b.status <> 'cancelled' then public.v1_accounts_supplier_paid_amount(b.id) else 0 end), 0),
           coalesce(sum(case when b.status <> 'cancelled' then greatest(b.total_incl_vat - public.v1_accounts_supplier_paid_amount(b.id), 0) else 0 end), 0),
           count(*) filter (where b.status <> 'cancelled' and b.due_date < current_date
             and public.v1_accounts_supplier_paid_amount(b.id) < b.total_incl_vat)
      into v_bills_total, v_bills_paid, v_bills_open, v_bills_overdue
    from public.v1_accounts_supplier_bills b where b.project_id = p_project_id;
  end if;

  v_paid_ex := round(least(v_received / v_vatf, v_invoiced), 2);

  -- Heatmap: invoiced % per current building x stage cell.
  if v_can_view and v_can_values and v_baseline.id is not null then
    select coalesce(jsonb_agg(cell order by ord, bname), '[]'::jsonb) into v_heatmap from (
      select sa.display_order as ord, scope.name as bname,
        jsonb_build_object('building_scope_id', bp.project_scope_id, 'building_name', scope.name,
          'stage_key', bp.stage_key, 'stage_label', sa.stage_name,
          'stage_value', public.v1_accounts_stage_value(bp.id)::text,
          'invoiced_amount', inv.amount::text,
          'invoiced_percent', case when public.v1_accounts_stage_value(bp.id) > 0
            then round(inv.amount / public.v1_accounts_stage_value(bp.id) * 100, 1) else 0 end::text) as cell
      from public.v1_accounts_billing_progress bp
      join public.v1_accounts_baseline_stage_allocations sa
        on sa.baseline_revision_id = bp.baseline_revision_id and sa.stage_key = bp.stage_key
      join public.v1_project_scopes scope on scope.id = bp.project_scope_id
      left join lateral (
        select coalesce(sum(l.claimed_amount), 0) as amount
        from public.v1_accounts_client_claim_lines l
        join public.v1_accounts_client_claims c on c.id = l.claim_id
        where c.project_id = p_project_id and c.status = 'invoiced'
          and l.project_scope_id = bp.project_scope_id and l.stage_key = bp.stage_key
      ) inv on true
      where bp.baseline_revision_id = v_baseline.id
    ) cells;
  end if;

  -- Attention (server-derived).
  if v_baseline.id is null then
    v_attention := v_attention || jsonb_build_array(jsonb_build_object(
      'severity', 'bad', 'kind', 'setup_incomplete', 'action_key', 'open_contract',
      'target_type', 'project', 'target_id', p_project_id));
  elsif v_can_values then
    v_attention := v_attention || coalesce((select jsonb_agg(jsonb_build_object(
        'severity', 'bad', 'kind', 'invoice_overdue', 'action_key', 'open_invoice',
        'target_type', 'invoice', 'target_id', i.id))
      from public.v1_accounts_client_invoices i where i.project_id = p_project_id
        and i.status not in ('draft','returned','cancelled','paid') and i.due_date < current_date), '[]'::jsonb);
    v_attention := v_attention || coalesce((select jsonb_agg(jsonb_build_object(
        'severity', 'pri', 'kind', 'awaiting_certification', 'action_key', 'certify',
        'target_type', 'invoice', 'target_id', i.id))
      from public.v1_accounts_client_invoices i where i.project_id = p_project_id and i.status = 'submitted'
        and not exists (select 1 from public.v1_accounts_client_certifications c where c.invoice_id = i.id)), '[]'::jsonb);
    if v_open_claim_id is not null and v_open_claim_gross > 0 then
      v_attention := v_attention || jsonb_build_array(jsonb_build_object('severity','ok','kind','claim_ready',
        'action_key','open_claim','target_type','claim','target_id',v_open_claim_id));
    elsif v_open_claim_id is not null then
      v_attention := v_attention || jsonb_build_array(jsonb_build_object('severity','pri','kind','claim_empty',
        'action_key','open_claim','target_type','claim','target_id',v_open_claim_id));
    elsif v_contract > 0 then
      v_attention := v_attention || jsonb_build_array(jsonb_build_object('severity','pri','kind','no_claim',
        'action_key','start_claim','target_type','project','target_id',p_project_id));
    end if;
    if v_pdc > 0 then
      v_attention := v_attention || jsonb_build_array(jsonb_build_object('severity','pri','kind','cheques_in_hand',
        'action_key','open_invoices','target_type','project','target_id',p_project_id));
    end if;
  end if;
  if v_can_supplier and v_bills_overdue > 0 then
    v_attention := v_attention || jsonb_build_array(jsonb_build_object('severity','warn','kind','supplier_overdue',
      'action_key','open_supplier_bills','target_type','project','target_id',p_project_id,
      'params', jsonb_build_object('count', v_bills_overdue)));
  end if;

  v_setup_state := case when v_baseline.id is not null then 'done' else 'current' end;
  v_progress_state := case when v_progress_any then 'done' when v_baseline.id is not null then 'current' else '' end;
  v_invoice_state := case when v_invoice_any then 'done' when v_progress_any then 'current' else '' end;
  v_paid_state := case when v_received > 0 and v_still_due <= 0 and v_invoice_any then 'done' when v_invoice_any then 'current' else '' end;

  -- Steps. Monetary figures (`detail`) only with commercial access; the
  -- state/label shape is identical for every actor.
  if v_can_values then
    v_steps := jsonb_build_array(
      jsonb_build_object('key','setup','state',v_setup_state,'detail',
        jsonb_build_object('contract_value', v_contract::text,
          'building_count', v_building_count, 'stage_count', v_stage_count)),
      jsonb_build_object('key','progress','state',v_progress_state,'detail',
        case when v_open_claim_id is not null
          then jsonb_build_object('claim_reference', v_open_claim_ref, 'claim_gross', v_open_claim_gross::text)
          else null end),
      jsonb_build_object('key','invoice','state',v_invoice_state,'detail',
        case when v_invoice_count > 0
          then jsonb_build_object('issued_count', v_invoice_count, 'latest_reference', v_latest_invoice_ref)
          else null end),
      jsonb_build_object('key','paid','state',v_paid_state,'detail',
        jsonb_build_object('received', v_received::text,
          'to_come', greatest(round(v_contract * v_vatf, 2) - v_received, 0)::text)));
  else
    v_steps := jsonb_build_array(
      jsonb_build_object('key','setup','state',v_setup_state),
      jsonb_build_object('key','progress','state',v_progress_state),
      jsonb_build_object('key','invoice','state',v_invoice_state),
      jsonb_build_object('key','paid','state',v_paid_state));
  end if;

  v_result := jsonb_build_object(
    'schema_version', 1, 'project_id', v_project.id,
    'project_reference', v_project.project_ref, 'project_name', v_project.name,
    'has_baseline', v_baseline.id is not null,
    'capabilities', jsonb_build_object('view_project_accounts', v_can_view,
      'view_project_commercial_values', v_can_values, 'view_supplier_costs', v_can_supplier),
    'steps', v_steps,
    'badges', jsonb_build_object(
      'claims_draft', v_open_claim_id is not null,
      'supplier_count', case when v_can_supplier then v_bills_overdue else null end),
    'attention', v_attention);

  if v_can_values then
    v_result := v_result || jsonb_build_object(
      'money_flow', jsonb_build_object(
        'paid', v_paid_ex::text,
        'invoiced_waiting', greatest(v_invoiced - v_paid_ex, 0)::text,
        'done_not_invoiced', v_draft::text,
        'remaining', greatest(v_contract - v_invoiced - v_draft, 0)::text),
      'kpis', jsonb_build_object(
        'contract_value', v_contract::text,
        'contract_incl_vat', round(v_contract * v_vatf, 2)::text,
        'invoiced', v_invoiced::text,
        'received', v_received::text,
        'certified', v_certified::text,
        'outstanding', v_still_due::text,
        'cheques_in_hand', v_pdc::text,
        'done_not_invoiced', v_draft::text),
      'heatmap', v_heatmap);
  end if;
  if v_can_supplier then
    v_result := v_result || jsonb_build_object(
      'supplier', jsonb_build_object('billed', v_bills_total::text, 'paid', v_bills_paid::text,
        'unpaid', v_bills_open::text, 'overdue_count', v_bills_overdue),
      'cash', jsonb_build_object('received', v_received::text, 'paid_to_suppliers', v_bills_paid::text,
        'net', (v_received - v_bills_paid)::text));
  end if;
  return v_result;
end;
$$;

revoke all on function public.v1_get_project_accounts_workspace(uuid) from public, anon;
grant execute on function public.v1_get_project_accounts_workspace(uuid) to authenticated, service_role;


-- #############################################################################
-- FILE 14 / 22 : 20261106150000_accounts_v2_p3_claim_payable.sql
-- #############################################################################

-- R39 Accounts Workspace V2 — P3 (part c): claim payable figures
--
-- The prototype claim side panel shows Gross / VAT / Net payable and the claim's
-- share of the contract. The workbench's claim object (from
-- v1_accounts_claim_snapshot) carries only the ex-VAT gross, and the client
-- cannot derive VAT or net (exact decimal arithmetic is server-side only). This
-- CREATE OR REPLACE of v1_get_claim_workbench merges server-computed
-- vat_amount, net_payable (incl VAT), contract_value and this_claim_percent into
-- the claim object.
--
-- Additive and accounts-only. The merged figures are monetary, so they are added
-- only with view_project_commercial_values (AT-SEC-001/008); the claim object is
-- otherwise unchanged, and every other key the prior version returned is
-- returned unchanged. No table, row or status change. VAT uses the baseline's
-- own vat_rate_percent and rounds once to fils.

create or replace function public.v1_get_claim_workbench(
  p_project_id uuid,
  p_claim_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_can_values boolean;
  v_profile public.v1_accounts_project_commercial_profiles%rowtype;
  v_baseline public.v1_accounts_baseline_revisions%rowtype;
  v_cells jsonb := '[]'::jsonb;
  v_claim jsonb := null;
  v_claim_id uuid;
  v_claim_gross numeric := 0;
  v_claim_vat numeric := 0;
begin
  perform public.v1_accounts_require_capability(p_project_id, 'view_project_accounts');
  v_can_values := public.v1_current_user_has_capability(
    'view_project_commercial_values', p_project_id
  );

  select * into v_profile
  from public.v1_accounts_project_commercial_profiles where project_id = p_project_id;
  if not found or v_profile.current_baseline_revision_id is null then
    return jsonb_build_object(
      'schema_version', 1, 'project_id', p_project_id,
      'baseline_revision_id', null, 'cells', '[]'::jsonb, 'claim', null,
      'capabilities', public.v1_accounts_capability_envelope(p_project_id),
      'commands', public.v1_accounts_receivables_commands(p_project_id)
    );
  end if;
  select * into v_baseline
  from public.v1_accounts_baseline_revisions where id = v_profile.current_baseline_revision_id;

  select coalesce(jsonb_agg(cell order by ord, bname), '[]'::jsonb) into v_cells
  from (
    select sa.display_order as ord, scope.name as bname,
      jsonb_build_object(
        'progress_entry_id', bp.id,
        'building_scope_id', bp.project_scope_id,
        'building_name', scope.name,
        'stage_key', bp.stage_key,
        'stage_label', sa.stage_name,
        'stage_position', sa.display_order,
        'measurement_mode', sa.measurement_mode,
        'confirmed_percent', bp.confirmed_percent::text,
        'review_status', bp.review_status,
        'record_version', bp.record_version
      )
      || case when v_can_values then jsonb_build_object(
          'stage_value', public.v1_accounts_stage_value(bp.id)::text,
          'eligible', public.v1_accounts_progress_eligible_amount(bp.id)::text,
          'claimed', public.v1_accounts_dimension_claimed_amount(
            bp.project_id, bp.project_scope_id, bp.stage_key, null)::text,
          'available', greatest(
            public.v1_accounts_progress_eligible_amount(bp.id)
              - public.v1_accounts_dimension_claimed_amount(
                  bp.project_id, bp.project_scope_id, bp.stage_key, null), 0)::text,
          'over_claimed', public.v1_accounts_dimension_claimed_amount(
              bp.project_id, bp.project_scope_id, bp.stage_key, null)
            > public.v1_accounts_progress_eligible_amount(bp.id)
        ) else '{}'::jsonb end
      || case when sa.measurement_mode = 'items' then jsonb_build_object('items', (
          select coalesce(jsonb_agg(
            jsonb_build_object(
              'stage_item_id', si.id, 'item_key', si.item_key,
              'item_label', si.item_label, 'display_order', si.display_order,
              'quantity', si.quantity::text, 'unit_code', si.unit_code,
              'confirmed_qty', coalesce(ip.confirmed_qty, 0)::text,
              'needs_review', coalesce(ip.needs_review, false)
            )
            || case when v_can_values then jsonb_build_object(
                'item_value', public.v1_accounts_stage_item_value(si.id)::text)
              else '{}'::jsonb end
            order by si.display_order), '[]'::jsonb)
          from public.v1_accounts_baseline_stage_items si
          left join public.v1_accounts_billing_item_progress ip
            on ip.stage_item_id = si.id and ip.progress_entry_id = bp.id
          where si.baseline_revision_id = v_baseline.id
            and si.project_scope_id = bp.project_scope_id
            and si.stage_key = bp.stage_key
        )) else '{}'::jsonb end
      as cell
    from public.v1_accounts_billing_progress bp
    join public.v1_accounts_baseline_stage_allocations sa
      on sa.baseline_revision_id = bp.baseline_revision_id and sa.stage_key = bp.stage_key
    join public.v1_project_scopes scope on scope.id = bp.project_scope_id
    where bp.baseline_revision_id = v_baseline.id
  ) rows;

  select id into v_claim_id
  from public.v1_accounts_client_claims
  where project_id = p_project_id
    and (
      (p_claim_id is not null and id = p_claim_id)
      or (p_claim_id is null and status in ('draft', 'ready_for_accounts'))
    )
  order by (status = 'draft') desc, updated_at desc
  limit 1;
  if v_claim_id is not null then
    v_claim := public.v1_accounts_claim_snapshot(v_claim_id);
    -- Payable figures: gross (ex VAT) + VAT at the baseline rate = net payable
    -- (incl VAT), plus this claim's share of the contract. Commercial only.
    if v_can_values then
      v_claim_gross := coalesce((select sum(claimed_amount)
        from public.v1_accounts_client_claim_lines where claim_id = v_claim_id), 0);
      v_claim_vat := round(v_claim_gross * coalesce(v_baseline.vat_rate_percent, 0) / 100, 2);
      v_claim := v_claim || jsonb_build_object(
        'vat_amount', v_claim_vat::text,
        'net_payable', (v_claim_gross + v_claim_vat)::text,
        'contract_value', v_baseline.contract_value::text,
        'this_claim_percent', case when v_baseline.contract_value > 0
          then round(v_claim_gross / v_baseline.contract_value * 100, 1)
          else 0 end::text);
    end if;
  end if;

  return jsonb_build_object(
    'schema_version', 1, 'project_id', p_project_id,
    'baseline_revision_id', v_baseline.id,
    'baseline_revision_number', v_baseline.revision_number,
    'cells', v_cells, 'claim', v_claim,
    'capabilities', public.v1_accounts_capability_envelope(p_project_id),
    'commands', public.v1_accounts_receivables_commands(p_project_id)
  );
end;
$$;

grant execute on function public.v1_get_claim_workbench(uuid, uuid) to authenticated;


-- #############################################################################
-- FILE 15 / 22 : 20261106160000_accounts_v2_p6_commercial_parties.sql
-- #############################################################################

-- R39 Accounts Workspace V2 — P6 (part b): contract parties on the setup read
--
-- The prototype Contract card shows the client / main contractor, their address
-- and contact. These already exist as project parties (v1_project_parties,
-- captured in the project setup flow), so this CREATE OR REPLACE of
-- v1_get_project_commercial_setup surfaces them read-only in a `parties` block
-- (client + main_contractor: name, address, contact). They are edited in project
-- setup, not here.
--
-- Additive, accounts-only, read-only. Party details are project metadata, not
-- commercial amounts, but the block is added inside the commercial section (the
-- Contract card only renders with view_project_commercial_values), so the
-- response shape is unchanged for non-commercial actors. Still deferred (no
-- backing columns): client TRN, work-order no/date and contract no. No table
-- change.

create or replace function public.v1_get_project_commercial_setup(
  p_project_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_can_view boolean;
  v_can_values boolean;
  v_can_configure boolean;
  v_project public.v1_projects%rowtype;
  v_profile public.v1_accounts_project_commercial_profiles%rowtype;
  v_baseline public.v1_accounts_baseline_revisions%rowtype;
  v_settings public.v1_accounts_project_invoice_settings%rowtype;
  v_contract numeric(20,2) := 0;
  v_buildings jsonb := '[]'::jsonb;
  v_stages jsonb := '[]'::jsonb;
  v_items jsonb := '[]'::jsonb;
  v_result jsonb;
begin
  if auth.uid() is null or p_project_id is null
     or not public.v1_current_actor_is_active() then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
  end if;
  v_can_view := public.v1_current_user_has_capability(
    'view_project_accounts', p_project_id);
  if not v_can_view then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
  end if;
  v_can_values := public.v1_current_user_has_capability(
    'view_project_commercial_values', p_project_id);
  v_can_configure := public.v1_current_user_has_capability(
    'configure_project_commercials', p_project_id);

  select * into v_project from public.v1_projects where id = p_project_id;
  if not found then
    raise exception 'R39_ACCOUNTS_PROJECT_NOT_FOUND' using errcode = 'P0002';
  end if;

  select * into v_profile
  from public.v1_accounts_project_commercial_profiles
  where project_id = p_project_id;
  if found and v_profile.current_baseline_revision_id is not null then
    select * into v_baseline from public.v1_accounts_baseline_revisions
    where id = v_profile.current_baseline_revision_id;
    v_contract := coalesce(v_baseline.contract_value, 0);
  end if;

  v_result := jsonb_build_object(
    'schema_version', 1,
    'project_id', v_project.id,
    'project_reference', v_project.project_ref,
    'project_name', v_project.name,
    'has_baseline', v_baseline.id is not null,
    'capabilities', jsonb_build_object(
      'view_project_accounts', v_can_view,
      'view_project_commercial_values', v_can_values,
      'configure_project_commercials', v_can_configure),
    'can_configure', v_can_configure);

  -- Commercial surface: no amounts or split without commercial-value access.
  if not v_can_values then
    return v_result;
  end if;

  select * into v_settings
  from public.v1_accounts_project_invoice_settings
  where project_id = p_project_id;

  if v_baseline.id is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
        'project_scope_id', b.project_scope_id,
        'name', s.name,
        'scope_kind', s.scope_kind,
        'allocation_percent', b.allocation_percent::text,
        'value', round(v_contract * b.allocation_percent / 100, 2)::text
      ) order by s.scope_kind, s.name), '[]'::jsonb)
      into v_buildings
    from public.v1_accounts_baseline_building_allocations b
    join public.v1_project_scopes s on s.id = b.project_scope_id
    where b.baseline_revision_id = v_baseline.id;

    select coalesce(jsonb_agg(jsonb_build_object(
        'stage_key', st.stage_key,
        'stage_name', st.stage_name,
        'display_order', st.display_order,
        'measurement_mode', st.measurement_mode,
        'allocation_percent', st.allocation_percent::text,
        'value', round(v_contract * st.allocation_percent / 100, 2)::text
      ) order by st.display_order), '[]'::jsonb)
      into v_stages
    from public.v1_accounts_baseline_stage_allocations st
    where st.baseline_revision_id = v_baseline.id;

    select coalesce(jsonb_agg(jsonb_build_object(
        'project_scope_id', it.project_scope_id,
        'building_name', s.name,
        'stage_key', it.stage_key,
        'item_key', it.item_key,
        'item_label', it.item_label,
        'display_order', it.display_order,
        'quantity', it.quantity::text,
        'unit_code', it.unit_code,
        'weight_percent_of_contract', it.weight_percent_of_contract::text,
        'value', public.v1_accounts_stage_item_value(it.id)::text
      ) order by s.name, it.stage_key, it.display_order), '[]'::jsonb)
      into v_items
    from public.v1_accounts_baseline_stage_items it
    join public.v1_project_scopes s on s.id = it.project_scope_id
    where it.baseline_revision_id = v_baseline.id;

    v_result := v_result || jsonb_build_object(
      'profile_version', v_profile.record_version,
      'revision_number', v_baseline.revision_number,
      'currency_code', v_baseline.currency_code,
      'contract_value', v_contract::text,
      'contract_incl_vat',
        round(v_contract * (1 + v_baseline.vat_rate_percent / 100), 2)::text,
      'vat_rate_percent', v_baseline.vat_rate_percent::text,
      'payment_terms_days', v_baseline.payment_terms_days,
      'reminder_lead_days', v_baseline.reminder_lead_days,
      'buildings', v_buildings,
      'stages', v_stages,
      'items', v_items);
  else
    v_result := v_result || jsonb_build_object(
      'profile_version',
        case when v_profile.project_id is not null
          then v_profile.record_version else null end,
      'currency_code', null,
      'buildings', '[]'::jsonb,
      'stages', '[]'::jsonb,
      'items', '[]'::jsonb);
  end if;

  if v_settings.project_id is not null then
    v_result := v_result || jsonb_build_object(
      'invoice_settings', jsonb_build_object(
        'invoice_prefix', v_settings.invoice_prefix,
        'next_sequence', v_settings.next_sequence,
        'scope_line', v_settings.scope_line,
        'attention_name', v_settings.attention_name,
        'bill_to_party_id', v_settings.bill_to_party_id,
        'record_version', v_settings.record_version));
  else
    v_result := v_result || jsonb_build_object('invoice_settings', null);
  end if;

  -- Contract parties (client + main contractor) from the project setup. The
  -- first party of each kind by order; read-only (edited in project setup).
  v_result := v_result || jsonb_build_object(
    'parties', coalesce((
      select jsonb_object_agg(party_kind, party)
      from (
        select distinct on (party_kind) party_kind,
          jsonb_build_object(
            'name', party_name,
            'address', address,
            'contact_name', contact_name,
            'contact_phone', contact_phone,
            'contact_email', contact_email) as party
        from public.v1_project_parties
        where project_id = p_project_id
          and party_kind in ('client', 'main_contractor')
        order by party_kind, party_order
      ) p
    ), '{}'::jsonb));

  return v_result;
end;
$$;

revoke all on function public.v1_get_project_commercial_setup(uuid)
  from public, anon;
grant execute on function public.v1_get_project_commercial_setup(uuid)
  to authenticated, service_role;


-- #############################################################################
-- FILE 16 / 22 : 20261106170000_accounts_v2_p6_contract_references.sql
-- #############################################################################

-- R39 Accounts Workspace V2 — P6 (part c): editable contract references
--
-- The prototype Contract card carries the client TRN, work-order number/date and
-- contract number. These have no V1 home, so this migration adds them to the
-- project-level commercial profile (not the versioned baseline), returns them in
-- the setup read, and adds a focused, idempotent write command to edit them.
--
-- Additive: ADD COLUMN IF NOT EXISTS (nullable), a new CREATE OR REPLACE write
-- function (no existing signature changes), and a CREATE OR REPLACE of the setup
-- read that returns a `references` block (commercial-gated, like the rest of the
-- Contract surface). No table drop, no row change.

alter table public.v1_accounts_project_commercial_profiles
  add column if not exists client_trn text;
alter table public.v1_accounts_project_commercial_profiles
  add column if not exists work_order_number text;
alter table public.v1_accounts_project_commercial_profiles
  add column if not exists work_order_date date;
alter table public.v1_accounts_project_commercial_profiles
  add column if not exists contract_number text;

-- Write: edit the four references on the profile. Capability + optimistic-lock
-- version check + idempotency, following the invoice-settings save pattern.
create or replace function public.v1_save_accounts_contract_references(
  p_project_id uuid,
  p_client_trn text,
  p_work_order_number text,
  p_work_order_date date,
  p_contract_number text,
  p_expected_version integer,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.v1_accounts_project_commercial_profiles%rowtype;
  v_payload jsonb; v_existing jsonb; v_response jsonb;
begin
  perform public.v1_accounts_require_capability(p_project_id, 'configure_project_commercials');
  v_payload := jsonb_build_object('project_id', p_project_id,
    'client_trn', nullif(btrim(coalesce(p_client_trn, '')), ''),
    'work_order_number', nullif(btrim(coalesce(p_work_order_number, '')), ''),
    'work_order_date', p_work_order_date,
    'contract_number', nullif(btrim(coalesce(p_contract_number, '')), ''),
    'expected_version', p_expected_version);
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_save_accounts_contract_references', p_idempotency_key, v_payload);
  if v_existing is not null then
    return v_existing || jsonb_build_object('replayed', true); end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('r39_accounts_contract_refs|' || p_project_id::text, 0));
  select * into v_row from public.v1_accounts_project_commercial_profiles
    where project_id = p_project_id for update;
  if not found then
    raise exception 'R39_ACCOUNTS_PROFILE_NOT_FOUND' using errcode = 'P0002'; end if;
  if v_row.record_version <> coalesce(p_expected_version, v_row.record_version) then
    raise exception 'R39_ACCOUNTS_VERSION_CONFLICT' using errcode = '40001'; end if;

  update public.v1_accounts_project_commercial_profiles set
    client_trn = nullif(btrim(coalesce(p_client_trn, '')), ''),
    work_order_number = nullif(btrim(coalesce(p_work_order_number, '')), ''),
    work_order_date = p_work_order_date,
    contract_number = nullif(btrim(coalesce(p_contract_number, '')), ''),
    record_version = record_version + 1
  where project_id = p_project_id returning * into v_row;

  v_response := jsonb_build_object('schema_version', 1, 'replayed', false,
    'project_id', p_project_id, 'record_version', v_row.record_version);
  perform public.v1_complete_idempotency(
    'v1_save_accounts_contract_references', p_idempotency_key, v_response);
  return v_response;
end;
$$;

revoke all on function public.v1_save_accounts_contract_references(
  uuid, text, text, date, text, integer, uuid) from public, anon;
grant execute on function public.v1_save_accounts_contract_references(
  uuid, text, text, date, text, integer, uuid) to authenticated;

-- Read: return the references block (and keep the parties block from part b).
create or replace function public.v1_get_project_commercial_setup(
  p_project_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_can_view boolean;
  v_can_values boolean;
  v_can_configure boolean;
  v_project public.v1_projects%rowtype;
  v_profile public.v1_accounts_project_commercial_profiles%rowtype;
  v_baseline public.v1_accounts_baseline_revisions%rowtype;
  v_settings public.v1_accounts_project_invoice_settings%rowtype;
  v_contract numeric(20,2) := 0;
  v_buildings jsonb := '[]'::jsonb;
  v_stages jsonb := '[]'::jsonb;
  v_items jsonb := '[]'::jsonb;
  v_result jsonb;
begin
  if auth.uid() is null or p_project_id is null
     or not public.v1_current_actor_is_active() then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
  end if;
  v_can_view := public.v1_current_user_has_capability(
    'view_project_accounts', p_project_id);
  if not v_can_view then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
  end if;
  v_can_values := public.v1_current_user_has_capability(
    'view_project_commercial_values', p_project_id);
  v_can_configure := public.v1_current_user_has_capability(
    'configure_project_commercials', p_project_id);

  select * into v_project from public.v1_projects where id = p_project_id;
  if not found then
    raise exception 'R39_ACCOUNTS_PROJECT_NOT_FOUND' using errcode = 'P0002';
  end if;

  select * into v_profile
  from public.v1_accounts_project_commercial_profiles
  where project_id = p_project_id;
  if found and v_profile.current_baseline_revision_id is not null then
    select * into v_baseline from public.v1_accounts_baseline_revisions
    where id = v_profile.current_baseline_revision_id;
    v_contract := coalesce(v_baseline.contract_value, 0);
  end if;

  v_result := jsonb_build_object(
    'schema_version', 1,
    'project_id', v_project.id,
    'project_reference', v_project.project_ref,
    'project_name', v_project.name,
    'has_baseline', v_baseline.id is not null,
    'capabilities', jsonb_build_object(
      'view_project_accounts', v_can_view,
      'view_project_commercial_values', v_can_values,
      'configure_project_commercials', v_can_configure),
    'can_configure', v_can_configure);

  if not v_can_values then
    return v_result;
  end if;

  select * into v_settings
  from public.v1_accounts_project_invoice_settings
  where project_id = p_project_id;

  if v_baseline.id is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
        'project_scope_id', b.project_scope_id,
        'name', s.name,
        'scope_kind', s.scope_kind,
        'allocation_percent', b.allocation_percent::text,
        'value', round(v_contract * b.allocation_percent / 100, 2)::text
      ) order by s.scope_kind, s.name), '[]'::jsonb)
      into v_buildings
    from public.v1_accounts_baseline_building_allocations b
    join public.v1_project_scopes s on s.id = b.project_scope_id
    where b.baseline_revision_id = v_baseline.id;

    select coalesce(jsonb_agg(jsonb_build_object(
        'stage_key', st.stage_key,
        'stage_name', st.stage_name,
        'display_order', st.display_order,
        'measurement_mode', st.measurement_mode,
        'allocation_percent', st.allocation_percent::text,
        'value', round(v_contract * st.allocation_percent / 100, 2)::text
      ) order by st.display_order), '[]'::jsonb)
      into v_stages
    from public.v1_accounts_baseline_stage_allocations st
    where st.baseline_revision_id = v_baseline.id;

    select coalesce(jsonb_agg(jsonb_build_object(
        'project_scope_id', it.project_scope_id,
        'building_name', s.name,
        'stage_key', it.stage_key,
        'item_key', it.item_key,
        'item_label', it.item_label,
        'display_order', it.display_order,
        'quantity', it.quantity::text,
        'unit_code', it.unit_code,
        'weight_percent_of_contract', it.weight_percent_of_contract::text,
        'value', public.v1_accounts_stage_item_value(it.id)::text
      ) order by s.name, it.stage_key, it.display_order), '[]'::jsonb)
      into v_items
    from public.v1_accounts_baseline_stage_items it
    join public.v1_project_scopes s on s.id = it.project_scope_id
    where it.baseline_revision_id = v_baseline.id;

    v_result := v_result || jsonb_build_object(
      'profile_version', v_profile.record_version,
      'revision_number', v_baseline.revision_number,
      'currency_code', v_baseline.currency_code,
      'contract_value', v_contract::text,
      'contract_incl_vat',
        round(v_contract * (1 + v_baseline.vat_rate_percent / 100), 2)::text,
      'vat_rate_percent', v_baseline.vat_rate_percent::text,
      'payment_terms_days', v_baseline.payment_terms_days,
      'reminder_lead_days', v_baseline.reminder_lead_days,
      'buildings', v_buildings,
      'stages', v_stages,
      'items', v_items);
  else
    v_result := v_result || jsonb_build_object(
      'profile_version',
        case when v_profile.project_id is not null
          then v_profile.record_version else null end,
      'currency_code', null,
      'buildings', '[]'::jsonb,
      'stages', '[]'::jsonb,
      'items', '[]'::jsonb);
  end if;

  if v_settings.project_id is not null then
    v_result := v_result || jsonb_build_object(
      'invoice_settings', jsonb_build_object(
        'invoice_prefix', v_settings.invoice_prefix,
        'next_sequence', v_settings.next_sequence,
        'scope_line', v_settings.scope_line,
        'attention_name', v_settings.attention_name,
        'bill_to_party_id', v_settings.bill_to_party_id,
        'record_version', v_settings.record_version));
  else
    v_result := v_result || jsonb_build_object('invoice_settings', null);
  end if;

  v_result := v_result || jsonb_build_object(
    'parties', coalesce((
      select jsonb_object_agg(party_kind, party)
      from (
        select distinct on (party_kind) party_kind,
          jsonb_build_object(
            'name', party_name,
            'address', address,
            'contact_name', contact_name,
            'contact_phone', contact_phone,
            'contact_email', contact_email) as party
        from public.v1_project_parties
        where project_id = p_project_id
          and party_kind in ('client', 'main_contractor')
        order by party_kind, party_order
      ) p
    ), '{}'::jsonb));

  -- Editable contract references from the project profile.
  v_result := v_result || jsonb_build_object(
    'references', jsonb_build_object(
      'client_trn', v_profile.client_trn,
      'work_order_number', v_profile.work_order_number,
      'work_order_date', v_profile.work_order_date,
      'contract_number', v_profile.contract_number));

  return v_result;
end;
$$;

revoke all on function public.v1_get_project_commercial_setup(uuid)
  from public, anon;
grant execute on function public.v1_get_project_commercial_setup(uuid)
  to authenticated, service_role;


-- #############################################################################
-- FILE 17 / 22 : 20261106180000_accounts_v2_p6_retention.sql
-- #############################################################################

-- R39 Accounts Workspace V2 — P6 (part d): retention percent (display only)
--
-- The prototype Contract card shows a retention %. Per the approved decision it
-- is display-only: it is stored and shown but does NOT reduce the net payable or
-- touch any claim/invoice math (that would be a separate, later decision). It is
-- a project-level contract term, so it lives on the commercial profile next to
-- the contract references and is edited through the same references command.
--
-- Additive: ADD COLUMN IF NOT EXISTS (nullable), the references read gains a
-- retention field, and the references write command gains a retention parameter.
-- Adding a parameter changes the function signature, so the (V2-only, just-added)
-- v1_save_accounts_contract_references is dropped and recreated — a function
-- replacement, not a data change. No table or row change.

alter table public.v1_accounts_project_commercial_profiles
  add column if not exists retention_percent numeric(7,4)
  check (retention_percent is null
    or (retention_percent::text <> 'NaN' and retention_percent between 0 and 100));

drop function if exists public.v1_save_accounts_contract_references(
  uuid, text, text, date, text, integer, uuid);

create or replace function public.v1_save_accounts_contract_references(
  p_project_id uuid,
  p_client_trn text,
  p_work_order_number text,
  p_work_order_date date,
  p_contract_number text,
  p_retention_percent numeric,
  p_expected_version integer,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.v1_accounts_project_commercial_profiles%rowtype;
  v_payload jsonb; v_existing jsonb; v_response jsonb;
begin
  perform public.v1_accounts_require_capability(p_project_id, 'configure_project_commercials');
  if p_retention_percent is not null
     and (p_retention_percent < 0 or p_retention_percent > 100) then
    raise exception 'R39_ACCOUNTS_INVALID_RETENTION' using errcode = '22023'; end if;
  v_payload := jsonb_build_object('project_id', p_project_id,
    'client_trn', nullif(btrim(coalesce(p_client_trn, '')), ''),
    'work_order_number', nullif(btrim(coalesce(p_work_order_number, '')), ''),
    'work_order_date', p_work_order_date,
    'contract_number', nullif(btrim(coalesce(p_contract_number, '')), ''),
    'retention_percent', p_retention_percent,
    'expected_version', p_expected_version);
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_save_accounts_contract_references', p_idempotency_key, v_payload);
  if v_existing is not null then
    return v_existing || jsonb_build_object('replayed', true); end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('r39_accounts_contract_refs|' || p_project_id::text, 0));
  select * into v_row from public.v1_accounts_project_commercial_profiles
    where project_id = p_project_id for update;
  if not found then
    raise exception 'R39_ACCOUNTS_PROFILE_NOT_FOUND' using errcode = 'P0002'; end if;
  if v_row.record_version <> coalesce(p_expected_version, v_row.record_version) then
    raise exception 'R39_ACCOUNTS_VERSION_CONFLICT' using errcode = '40001'; end if;

  update public.v1_accounts_project_commercial_profiles set
    client_trn = nullif(btrim(coalesce(p_client_trn, '')), ''),
    work_order_number = nullif(btrim(coalesce(p_work_order_number, '')), ''),
    work_order_date = p_work_order_date,
    contract_number = nullif(btrim(coalesce(p_contract_number, '')), ''),
    retention_percent = p_retention_percent,
    record_version = record_version + 1
  where project_id = p_project_id returning * into v_row;

  v_response := jsonb_build_object('schema_version', 1, 'replayed', false,
    'project_id', p_project_id, 'record_version', v_row.record_version);
  perform public.v1_complete_idempotency(
    'v1_save_accounts_contract_references', p_idempotency_key, v_response);
  return v_response;
end;
$$;

revoke all on function public.v1_save_accounts_contract_references(
  uuid, text, text, date, text, numeric, integer, uuid) from public, anon;
grant execute on function public.v1_save_accounts_contract_references(
  uuid, text, text, date, text, numeric, integer, uuid) to authenticated;

-- Read: add retention_percent to the references block.
create or replace function public.v1_get_project_commercial_setup(
  p_project_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_can_view boolean;
  v_can_values boolean;
  v_can_configure boolean;
  v_project public.v1_projects%rowtype;
  v_profile public.v1_accounts_project_commercial_profiles%rowtype;
  v_baseline public.v1_accounts_baseline_revisions%rowtype;
  v_settings public.v1_accounts_project_invoice_settings%rowtype;
  v_contract numeric(20,2) := 0;
  v_buildings jsonb := '[]'::jsonb;
  v_stages jsonb := '[]'::jsonb;
  v_items jsonb := '[]'::jsonb;
  v_result jsonb;
begin
  if auth.uid() is null or p_project_id is null
     or not public.v1_current_actor_is_active() then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
  end if;
  v_can_view := public.v1_current_user_has_capability(
    'view_project_accounts', p_project_id);
  if not v_can_view then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
  end if;
  v_can_values := public.v1_current_user_has_capability(
    'view_project_commercial_values', p_project_id);
  v_can_configure := public.v1_current_user_has_capability(
    'configure_project_commercials', p_project_id);

  select * into v_project from public.v1_projects where id = p_project_id;
  if not found then
    raise exception 'R39_ACCOUNTS_PROJECT_NOT_FOUND' using errcode = 'P0002';
  end if;

  select * into v_profile
  from public.v1_accounts_project_commercial_profiles
  where project_id = p_project_id;
  if found and v_profile.current_baseline_revision_id is not null then
    select * into v_baseline from public.v1_accounts_baseline_revisions
    where id = v_profile.current_baseline_revision_id;
    v_contract := coalesce(v_baseline.contract_value, 0);
  end if;

  v_result := jsonb_build_object(
    'schema_version', 1,
    'project_id', v_project.id,
    'project_reference', v_project.project_ref,
    'project_name', v_project.name,
    'has_baseline', v_baseline.id is not null,
    'capabilities', jsonb_build_object(
      'view_project_accounts', v_can_view,
      'view_project_commercial_values', v_can_values,
      'configure_project_commercials', v_can_configure),
    'can_configure', v_can_configure);

  if not v_can_values then
    return v_result;
  end if;

  select * into v_settings
  from public.v1_accounts_project_invoice_settings
  where project_id = p_project_id;

  if v_baseline.id is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
        'project_scope_id', b.project_scope_id,
        'name', s.name,
        'scope_kind', s.scope_kind,
        'allocation_percent', b.allocation_percent::text,
        'value', round(v_contract * b.allocation_percent / 100, 2)::text
      ) order by s.scope_kind, s.name), '[]'::jsonb)
      into v_buildings
    from public.v1_accounts_baseline_building_allocations b
    join public.v1_project_scopes s on s.id = b.project_scope_id
    where b.baseline_revision_id = v_baseline.id;

    select coalesce(jsonb_agg(jsonb_build_object(
        'stage_key', st.stage_key,
        'stage_name', st.stage_name,
        'display_order', st.display_order,
        'measurement_mode', st.measurement_mode,
        'allocation_percent', st.allocation_percent::text,
        'value', round(v_contract * st.allocation_percent / 100, 2)::text
      ) order by st.display_order), '[]'::jsonb)
      into v_stages
    from public.v1_accounts_baseline_stage_allocations st
    where st.baseline_revision_id = v_baseline.id;

    select coalesce(jsonb_agg(jsonb_build_object(
        'project_scope_id', it.project_scope_id,
        'building_name', s.name,
        'stage_key', it.stage_key,
        'item_key', it.item_key,
        'item_label', it.item_label,
        'display_order', it.display_order,
        'quantity', it.quantity::text,
        'unit_code', it.unit_code,
        'weight_percent_of_contract', it.weight_percent_of_contract::text,
        'value', public.v1_accounts_stage_item_value(it.id)::text
      ) order by s.name, it.stage_key, it.display_order), '[]'::jsonb)
      into v_items
    from public.v1_accounts_baseline_stage_items it
    join public.v1_project_scopes s on s.id = it.project_scope_id
    where it.baseline_revision_id = v_baseline.id;

    v_result := v_result || jsonb_build_object(
      'profile_version', v_profile.record_version,
      'revision_number', v_baseline.revision_number,
      'currency_code', v_baseline.currency_code,
      'contract_value', v_contract::text,
      'contract_incl_vat',
        round(v_contract * (1 + v_baseline.vat_rate_percent / 100), 2)::text,
      'vat_rate_percent', v_baseline.vat_rate_percent::text,
      'payment_terms_days', v_baseline.payment_terms_days,
      'reminder_lead_days', v_baseline.reminder_lead_days,
      'buildings', v_buildings,
      'stages', v_stages,
      'items', v_items);
  else
    v_result := v_result || jsonb_build_object(
      'profile_version',
        case when v_profile.project_id is not null
          then v_profile.record_version else null end,
      'currency_code', null,
      'buildings', '[]'::jsonb,
      'stages', '[]'::jsonb,
      'items', '[]'::jsonb);
  end if;

  if v_settings.project_id is not null then
    v_result := v_result || jsonb_build_object(
      'invoice_settings', jsonb_build_object(
        'invoice_prefix', v_settings.invoice_prefix,
        'next_sequence', v_settings.next_sequence,
        'scope_line', v_settings.scope_line,
        'attention_name', v_settings.attention_name,
        'bill_to_party_id', v_settings.bill_to_party_id,
        'record_version', v_settings.record_version));
  else
    v_result := v_result || jsonb_build_object('invoice_settings', null);
  end if;

  v_result := v_result || jsonb_build_object(
    'parties', coalesce((
      select jsonb_object_agg(party_kind, party)
      from (
        select distinct on (party_kind) party_kind,
          jsonb_build_object(
            'name', party_name,
            'address', address,
            'contact_name', contact_name,
            'contact_phone', contact_phone,
            'contact_email', contact_email) as party
        from public.v1_project_parties
        where project_id = p_project_id
          and party_kind in ('client', 'main_contractor')
        order by party_kind, party_order
      ) p
    ), '{}'::jsonb));

  v_result := v_result || jsonb_build_object(
    'references', jsonb_build_object(
      'client_trn', v_profile.client_trn,
      'work_order_number', v_profile.work_order_number,
      'work_order_date', v_profile.work_order_date,
      'contract_number', v_profile.contract_number,
      'retention_percent',
        case when v_profile.retention_percent is null then null
          else v_profile.retention_percent::text end));

  return v_result;
end;
$$;

revoke all on function public.v1_get_project_commercial_setup(uuid)
  from public, anon;
grant execute on function public.v1_get_project_commercial_setup(uuid)
  to authenticated, service_role;


-- #############################################################################
-- FILE 18 / 22 : 20261106190000_accounts_v2_p6_variations.sql
-- #############################################################################

-- R39 Accounts Workspace V2 — P6 (part e): variations (VO) register
--
-- The prototype Contract tab lists variation orders (VO no., description, amount,
-- status). Per the approved decision this is a REGISTER ONLY: variations are
-- tracked but do NOT change the contract value or any building/stage/claim math
-- (that would be a separate, later decision). This adds the table, a gated list
-- read and an idempotent upsert write (create or edit a VO).
--
-- Additive, accounts-only. The table uses the V2 pattern: RLS enabled with no
-- policies (deny-all direct access); all reads/writes go through the
-- security-definer RPCs below. Amounts are decimal strings.

create table if not exists public.v1_accounts_contract_variations (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.v1_projects (id) on delete restrict,
  vo_number text not null check (btrim(vo_number) <> ''),
  description text,
  amount numeric(20,2) not null default 0 check (amount::text <> 'NaN'),
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  record_version integer not null default 1 check (record_version > 0),
  created_by_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (project_id, vo_number)
);
alter table public.v1_accounts_contract_variations enable row level security;

-- Read: the project's variations (commercial — needs view_project_commercial_values).
create or replace function public.v1_list_accounts_variations(p_project_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_rows jsonb;
begin
  perform public.v1_accounts_require_capability(p_project_id, 'view_project_commercial_values');
  select coalesce(jsonb_agg(jsonb_build_object(
      'variation_id', id, 'vo_number', vo_number, 'description', description,
      'amount', amount::text, 'status', status, 'record_version', record_version
    ) order by created_at, id), '[]'::jsonb) into v_rows
  from public.v1_accounts_contract_variations where project_id = p_project_id;
  return jsonb_build_object('schema_version', 1, 'project_id', p_project_id,
    'variations', v_rows,
    'can_configure', public.v1_current_user_has_capability(
      'configure_project_commercials', p_project_id));
end;
$$;

revoke all on function public.v1_list_accounts_variations(uuid) from public, anon;
grant execute on function public.v1_list_accounts_variations(uuid) to authenticated, service_role;

-- Write: create (variation_id null) or edit a variation. Idempotent; edits are
-- version-checked. Register only — no contract-value side effects.
create or replace function public.v1_save_accounts_variation(
  p_project_id uuid,
  p_variation_id uuid,
  p_vo_number text,
  p_description text,
  p_amount numeric,
  p_status text,
  p_expected_version integer,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_row public.v1_accounts_contract_variations%rowtype;
  v_payload jsonb; v_existing jsonb; v_response jsonb;
begin
  perform public.v1_accounts_require_capability(p_project_id, 'configure_project_commercials');
  if nullif(btrim(coalesce(p_vo_number, '')), '') is null then
    raise exception 'R39_ACCOUNTS_VO_NUMBER_REQUIRED' using errcode = '22023'; end if;
  if p_status is not null and p_status not in ('pending', 'approved', 'rejected') then
    raise exception 'R39_ACCOUNTS_INVALID_VO_STATUS' using errcode = '22023'; end if;
  v_payload := jsonb_build_object('project_id', p_project_id, 'variation_id', p_variation_id,
    'vo_number', btrim(p_vo_number), 'description', nullif(btrim(coalesce(p_description, '')), ''),
    'amount', p_amount, 'status', coalesce(p_status, 'pending'), 'expected_version', p_expected_version);
  v_existing := public.v1_idempotency_get_or_claim('v1_save_accounts_variation', p_idempotency_key, v_payload);
  if v_existing is not null then return v_existing || jsonb_build_object('replayed', true); end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('r39_accounts_variation|' || p_project_id::text, 0));
  if p_variation_id is null then
    insert into public.v1_accounts_contract_variations(
      project_id, vo_number, description, amount, status, created_by_auth_user_id)
    values (p_project_id, btrim(p_vo_number), nullif(btrim(coalesce(p_description, '')), ''),
      coalesce(p_amount, 0), coalesce(p_status, 'pending'), v_actor)
    returning * into v_row;
  else
    select * into v_row from public.v1_accounts_contract_variations
      where id = p_variation_id and project_id = p_project_id for update;
    if not found then
      raise exception 'R39_ACCOUNTS_VARIATION_NOT_FOUND' using errcode = 'P0002'; end if;
    if v_row.record_version <> coalesce(p_expected_version, v_row.record_version) then
      raise exception 'R39_ACCOUNTS_VERSION_CONFLICT' using errcode = '40001'; end if;
    update public.v1_accounts_contract_variations set
      vo_number = btrim(p_vo_number),
      description = nullif(btrim(coalesce(p_description, '')), ''),
      amount = coalesce(p_amount, 0), status = coalesce(p_status, 'pending'),
      record_version = record_version + 1, updated_at = clock_timestamp()
    where id = p_variation_id returning * into v_row;
  end if;

  v_response := jsonb_build_object('schema_version', 1, 'replayed', false,
    'project_id', p_project_id, 'variation_id', v_row.id, 'record_version', v_row.record_version);
  perform public.v1_complete_idempotency('v1_save_accounts_variation', p_idempotency_key, v_response);
  return v_response;
end;
$$;

revoke all on function public.v1_save_accounts_variation(
  uuid, uuid, text, text, numeric, text, integer, uuid) from public, anon;
grant execute on function public.v1_save_accounts_variation(
  uuid, uuid, text, text, numeric, text, integer, uuid) to authenticated;


-- #############################################################################
-- FILE 19 / 22 : 20261106200000_accounts_v2_p6_retention_payable.sql
-- #############################################################################

-- R39 Accounts Workspace V2 — P6 (part f): retention hold-back on payable
--
-- Implements PRODUCT_DECISIONS.md section 28 (RESOLVED 2026-11-06): retention
-- reduces what the client still owes. Owner choice: only invoices issued AFTER
-- the rule is set are affected, via a per-invoice `retention_snapshot` frozen at
-- issue from the profile's retention %. Existing invoices keep retention 0, so
-- their due is unchanged. Release of retention is out of scope.
--
-- Invariant: still_due = max(certified_incl_vat - retention_snapshot - paid, 0),
-- everywhere, through the per-invoice snapshot. The payment cap uses the same
-- reduced due. Additive: ADD COLUMN IF NOT EXISTS (default 0) + CREATE OR
-- REPLACE of the receivables readers, the payment command and the issue command.
-- The Accountant office (t05) and exports (t06) still read certified - paid; they
-- are out of the V2 scope and, with retention 0 on existing invoices, show no
-- regression — they move to the retention figure when the office is next revised.

alter table public.v1_accounts_client_invoices
  add column if not exists retention_snapshot numeric(20,2) not null default 0
  check (retention_snapshot >= 0);

-- The frozen retention held back on an invoice (0 for pre-rule invoices).
create or replace function public.v1_accounts_invoice_retention(p_invoice_id uuid)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select retention_snapshot
    from public.v1_accounts_client_invoices where id = p_invoice_id), 0);
$$;

-- Invoice snapshot: add retention and reduce still_due by it.
create or replace function public.v1_accounts_invoice_snapshot(
  p_invoice_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_invoice public.v1_accounts_client_invoices%rowtype;
begin
  select * into v_invoice from public.v1_accounts_client_invoices where id=p_invoice_id;
  if not found then return null; end if;
  return jsonb_build_object(
    'invoice_id',v_invoice.id,'project_id',v_invoice.project_id,
    'claim_id',v_invoice.claim_id,'invoice_reference',v_invoice.invoice_reference,
    'status',v_invoice.status,'claimed_ex_vat',v_invoice.claimed_ex_vat::text,
    'vat_rate_percent_snapshot',v_invoice.vat_rate_percent_snapshot::text,
    'vat_amount_snapshot',v_invoice.vat_amount_snapshot::text,
    'total_incl_vat_snapshot',v_invoice.total_incl_vat_snapshot::text,
    'payment_terms_days_snapshot',v_invoice.payment_terms_days_snapshot,
    'reminder_lead_days_snapshot',v_invoice.reminder_lead_days_snapshot,
    'submission_date',v_invoice.submission_date,'due_date',v_invoice.due_date,
    'admin_exception_reason',v_invoice.admin_exception_reason,'notes',v_invoice.notes,
    'record_version',v_invoice.record_version,
    'certified_ex_vat',public.v1_accounts_invoice_certified_ex_vat(v_invoice.id)::text,
    'certified_incl_vat',public.v1_accounts_invoice_certified_incl_vat(v_invoice.id)::text,
    'retention_snapshot',v_invoice.retention_snapshot::text,
    'paid_amount',public.v1_accounts_invoice_paid_amount(v_invoice.id)::text,
    'amount_paid_till_date',public.v1_accounts_invoice_paid_amount(v_invoice.id)::text,
    'still_due',greatest(public.v1_accounts_invoice_certified_incl_vat(v_invoice.id)
      - v_invoice.retention_snapshot - public.v1_accounts_invoice_paid_amount(v_invoice.id),0)::text,
    'pdc_exposure',public.v1_accounts_invoice_pdc_exposure(v_invoice.id)::text,
    'created_by_auth_user_id',v_invoice.created_by_auth_user_id,
    'created_by_role',v_invoice.created_by_role,
    'created_by_exact_role',v_invoice.created_by_exact_role,
    'created_at',v_invoice.created_at,'updated_at',v_invoice.updated_at
  );
end;
$$;

-- Record payment: the cap and the returned still_due use the retention-reduced due.
create or replace function public.v1_record_client_payment(
  p_project_id uuid,p_invoice_id uuid,p_expected_version integer,p_payment_date date,
  p_payment_method text,p_payment_reference text,p_amount text,p_reason text,p_idempotency_key uuid
)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_actor uuid:=auth.uid();v_role text:=public.v1_current_role();v_exact text;
  v_invoice public.v1_accounts_client_invoices%rowtype;v_amount numeric;v_certified numeric;v_paid numeric;v_retention numeric;
  v_payment_id uuid:=gen_random_uuid();v_payload jsonb;v_existing jsonb;v_before jsonb;v_response jsonb;v_status text;v_now timestamptz:=clock_timestamp();
begin
  v_exact:=public.v1_accounts_require_capability(p_project_id,'record_client_payment');
  if p_payment_date is null or nullif(btrim(p_payment_method),'') is null or nullif(btrim(p_payment_reference),'') is null then
    raise exception 'R39_ACCOUNTS_PAYMENT_IDENTITY_REQUIRED' using errcode='22023';end if;
  v_amount:=public.v1_accounts_parse_money_text(p_amount);if v_amount<=0 then raise exception 'R39_ACCOUNTS_INVALID_PAYMENT_AMOUNT' using errcode='22023';end if;
  v_payload:=jsonb_build_object('project_id',p_project_id,'invoice_id',p_invoice_id,'expected_version',p_expected_version,
    'payment_date',p_payment_date,'payment_method',btrim(p_payment_method),'payment_reference',btrim(p_payment_reference),
    'amount',v_amount::text,'reason',nullif(btrim(p_reason),''));
  v_existing:=public.v1_idempotency_get_or_claim('v1_record_client_payment',p_idempotency_key,v_payload);
  if v_existing is not null then return v_existing||jsonb_build_object('replayed',true);end if;
  select * into v_invoice from public.v1_accounts_client_invoices where id=p_invoice_id and project_id=p_project_id for update;
  if not found then raise exception 'R39_ACCOUNTS_INVOICE_NOT_FOUND' using errcode='P0002';end if;
  if v_invoice.status in ('draft','returned','cancelled') then raise exception 'R39_ACCOUNTS_INVOICE_NOT_PAYABLE' using errcode='55000';end if;
  if v_invoice.record_version<>p_expected_version then raise exception 'R39_ACCOUNTS_VERSION_CONFLICT' using errcode='40001';end if;
  v_certified:=public.v1_accounts_invoice_certified_incl_vat(p_invoice_id);v_paid:=public.v1_accounts_invoice_paid_amount(p_invoice_id);
  v_retention:=v_invoice.retention_snapshot;
  if v_certified<=0 or v_paid+v_amount>v_certified-v_retention then raise exception 'R39_ACCOUNTS_PAYMENT_CAP_EXCEEDED' using errcode='23514';end if;
  v_before:=public.v1_accounts_invoice_snapshot(p_invoice_id);
  insert into public.v1_accounts_client_payments(id,project_id,invoice_id,entry_kind,payment_date,payment_method,payment_reference,amount,reason,
    actor_auth_user_id,actor_role,actor_exact_role,idempotency_key,created_at)
  values(v_payment_id,p_project_id,p_invoice_id,'receipt',p_payment_date,btrim(p_payment_method),btrim(p_payment_reference),v_amount,
    nullif(btrim(p_reason),''),v_actor,v_role,v_exact,p_idempotency_key,v_now);
  update public.v1_accounts_client_invoices set record_version=record_version+1,updated_at=v_now where id=p_invoice_id;
  v_status:=public.v1_accounts_refresh_invoice_status(p_invoice_id);
  perform public.v1_write_audit_event('accounts.client_payment.recorded','accounts_client_payment',v_payment_id,p_project_id,v_before,public.v1_accounts_invoice_snapshot(p_invoice_id),nullif(btrim(p_reason),''),p_idempotency_key);
  v_response:=jsonb_build_object('schema_version',3,'replayed',false,'project_id',p_project_id,'entity_id',v_payment_id,'payment_id',v_payment_id,
    'invoice_id',p_invoice_id,'invoice_record_version',p_expected_version+1,'status',v_status,'amount',v_amount::text,
    'amount_paid_till_date',(v_paid+v_amount)::text,'still_due',greatest(v_certified-v_retention-v_paid-v_amount,0)::text,'updated_at',v_now);
  perform public.v1_complete_idempotency('v1_record_client_payment',p_idempotency_key,v_response);return v_response;
exception when unique_violation then raise exception 'R39_ACCOUNTS_DUPLICATE_PAYMENT_REFERENCE' using errcode='23505';
end;
$$;

-- Invoice list: still_due subtracts retention.
create or replace function public.v1_list_client_invoices(
  p_project_id uuid,p_status text default null,p_due_state text default null,
  p_before_updated_at timestamptz default null,p_before_id uuid default null,p_limit integer default 50
)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_rows jsonb;v_next_time timestamptz;v_next_id uuid;v_limit integer:=least(greatest(coalesce(p_limit,50),1),100);
begin
  perform public.v1_accounts_require_capability(p_project_id,'manage_client_invoices');
  if p_status is not null and p_status not in ('draft','submitted','under_certification','partially_certified','certified','partially_paid','paid','returned','cancelled') then raise exception 'R39_ACCOUNTS_INVALID_INVOICE_STATUS' using errcode='22023';end if;
  if p_due_state is not null and p_due_state not in ('on_track','due_soon','due_today','overdue') then raise exception 'R39_ACCOUNTS_INVALID_DUE_STATE' using errcode='22023';end if;
  with derived as (select invoice.*,public.v1_accounts_invoice_certified_ex_vat(invoice.id) certified_ex,
      public.v1_accounts_invoice_certified_incl_vat(invoice.id) certified_total,public.v1_accounts_invoice_paid_amount(invoice.id) paid,
      public.v1_accounts_invoice_pdc_exposure(invoice.id) exposure,
      public.v1_accounts_invoice_due_state(invoice.status,invoice.due_date,invoice.reminder_lead_days_snapshot) due_state
    from public.v1_accounts_client_invoices invoice where invoice.project_id=p_project_id),
  page as (select * from derived where (p_status is null or status=p_status) and (p_due_state is null or due_state=p_due_state)
    and (p_before_updated_at is null or (updated_at,id)<(p_before_updated_at,coalesce(p_before_id,'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
    order by updated_at desc,id desc limit v_limit)
  select coalesce(jsonb_agg(jsonb_build_object('invoice_id',id,'claim_id',claim_id,'invoice_reference',invoice_reference,'status',status,
    'claimed_ex_vat',claimed_ex_vat::text,'certified_ex_vat',certified_ex::text,'total_incl_vat',total_incl_vat_snapshot::text,
    'retention_snapshot',retention_snapshot::text,
    'amount_paid_till_date',paid::text,'still_due',greatest(certified_total-retention_snapshot-paid,0)::text,'pdc_exposure',exposure::text,
    'submission_date',submission_date,'due_date',due_date,'due_state',due_state,'record_version',record_version,'updated_at',updated_at)
    order by updated_at desc,id desc),'[]'::jsonb),min(updated_at),(array_agg(id order by updated_at asc,id asc))[1]
  into v_rows,v_next_time,v_next_id from page;
  return jsonb_build_object('schema_version',3,'project_id',p_project_id,'invoices',v_rows,
    'next_cursor',case when jsonb_array_length(v_rows)=v_limit then jsonb_build_object('before_updated_at',v_next_time,'before_id',v_next_id) else null end,
    'capabilities',public.v1_accounts_receivables_capabilities(p_project_id),
    'commands',public.v1_accounts_receivables_commands(p_project_id));
end;
$$;

-- Issue: freeze the retention held back on the new invoice from the profile %.
-- NOTE: this recreation preserves the full supersession behaviour added by
-- 20261105120000_accounts_v2_p3_invoice_revise.sql (R.n numbering + predecessor
-- retirement). It ONLY adds the retention freeze after submit. Keep the two in
-- sync if the revise migration's issue body changes.
create or replace function public.v1_issue_client_invoice(
  p_project_id uuid,
  p_claim_id uuid,
  p_expected_claim_version integer,
  p_invoice_reference text,
  p_invoice_date date,
  p_submission_date date,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_claim public.v1_accounts_client_claims%rowtype;
  v_pred_claim public.v1_accounts_client_claims%rowtype;
  v_pred_invoice public.v1_accounts_client_invoices%rowtype;
  v_settings public.v1_accounts_project_invoice_settings%rowtype;
  v_reference text;
  v_base text;
  v_rev integer := 0;
  v_invoice_id uuid;
  v_draft jsonb; v_submit jsonb;
  v_document jsonb; v_sha text;
  v_payload jsonb; v_existing jsonb; v_response jsonb; v_now timestamptz := clock_timestamp();
begin
  perform public.v1_accounts_require_capability(p_project_id, 'manage_client_invoices');
  if p_submission_date is null or p_invoice_date is null then
    raise exception 'R39_ACCOUNTS_INVOICE_DATE_REQUIRED' using errcode = '22023'; end if;
  v_payload := jsonb_build_object('project_id', p_project_id, 'claim_id', p_claim_id,
    'expected_claim_version', p_expected_claim_version, 'invoice_reference', nullif(btrim(p_invoice_reference), ''),
    'invoice_date', p_invoice_date, 'submission_date', p_submission_date);
  v_existing := public.v1_idempotency_get_or_claim('v1_issue_client_invoice', p_idempotency_key, v_payload);
  if v_existing is not null then return v_existing || jsonb_build_object('replayed', true); end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('r39_accounts_invoice_settings|' || p_project_id::text, 0));
  select * into v_claim from public.v1_accounts_client_claims where id = p_claim_id and project_id = p_project_id for update;
  if not found then raise exception 'R39_ACCOUNTS_CLAIM_NOT_FOUND' using errcode = 'P0002'; end if;
  if p_expected_claim_version is not null and v_claim.record_version <> p_expected_claim_version then
    raise exception 'R39_ACCOUNTS_VERSION_CONFLICT' using errcode = '40001'; end if;

  if v_claim.supersedes_claim_id is not null then
    select * into v_pred_claim from public.v1_accounts_client_claims where id = v_claim.supersedes_claim_id for update;
    select * into v_pred_invoice from public.v1_accounts_client_invoices where claim_id = v_pred_claim.id for update;
    v_base := coalesce(v_pred_invoice.base_reference, v_pred_invoice.invoice_reference);
    v_rev := coalesce(v_pred_invoice.revision_number, 0) + 1;
    v_reference := coalesce(nullif(btrim(p_invoice_reference), ''), v_base || 'R.' || v_rev::text);
  elsif nullif(btrim(p_invoice_reference), '') is not null then
    v_reference := btrim(p_invoice_reference);
  else
    select * into v_settings from public.v1_accounts_project_invoice_settings where project_id = p_project_id for update;
    if not found then raise exception 'R39_ACCOUNTS_INVOICE_SETTINGS_REQUIRED' using errcode = '55000'; end if;
    v_reference := v_settings.invoice_prefix || lpad(v_settings.next_sequence::text, 2, '0');
    update public.v1_accounts_project_invoice_settings
    set next_sequence = next_sequence + 1, record_version = record_version + 1, updated_at = v_now
    where project_id = p_project_id;
  end if;

  v_draft := public.v1_create_client_invoice_draft(
    p_project_id, p_claim_id, v_reference, null, md5(p_idempotency_key::text || ':create')::uuid);
  v_invoice_id := (v_draft ->> 'invoice_id')::uuid;
  v_submit := public.v1_submit_client_invoice(
    p_project_id, v_invoice_id, 1, p_submission_date, null, md5(p_idempotency_key::text || ':submit')::uuid);

  -- Freeze retention held back (section 28): retention% x claim gross ex-VAT.
  update public.v1_accounts_client_invoices i
  set retention_snapshot = round(i.claimed_ex_vat * coalesce(
      (select retention_percent from public.v1_accounts_project_commercial_profiles
       where project_id = p_project_id), 0) / 100, 2)
  where i.id = v_invoice_id;

  if v_claim.supersedes_claim_id is not null then
    update public.v1_accounts_client_invoices
    set base_reference = v_base, revision_number = v_rev, supersedes_invoice_id = v_pred_invoice.id
    where id = v_invoice_id;
    -- Retire the predecessor: cancelled + supersedes link ("Superseded by R.n").
    update public.v1_accounts_client_invoices
    set status = 'cancelled', cancelled_at = v_now, cancelled_by_auth_user_id = v_actor,
      cancellation_reason = 'Superseded by ' || v_reference,
      record_version = record_version + 1, updated_at = v_now
    where id = v_pred_invoice.id;
    update public.v1_accounts_client_claims
    set status = 'cancelled', cancelled_at = v_now, cancelled_by_auth_user_id = v_actor,
      cancellation_reason = 'Superseded by ' || v_reference,
      record_version = record_version + 1, updated_at = v_now
    where id = v_pred_claim.id;
    perform public.v1_write_audit_event('accounts.client_invoice.superseded',
      'accounts_client_invoice', v_pred_invoice.id, p_project_id,
      jsonb_build_object('superseded_by_invoice_id', v_invoice_id, 'reference', v_reference),
      null, 'Superseded by ' || v_reference, p_idempotency_key);
  end if;

  v_document := public.v1_accounts_build_invoice_document(
    p_project_id, p_claim_id, v_reference, p_invoice_date, p_submission_date,
    (v_submit ->> 'due_date')::date);
  v_sha := encode(pg_catalog.sha256(pg_catalog.convert_to(v_document::text, 'UTF8')), 'hex');
  insert into public.v1_accounts_client_invoice_documents(invoice_id, project_id, document_snapshot, snapshot_sha256)
  values (v_invoice_id, p_project_id, v_document, v_sha);

  v_response := v_submit || jsonb_build_object('replayed', false,
    'invoice_reference', v_reference, 'revision_number', v_rev, 'document_snapshot_sha256', v_sha);
  perform public.v1_complete_idempotency('v1_issue_client_invoice', p_idempotency_key, v_response);
  return v_response;
end;
$$;

grant execute on function public.v1_issue_client_invoice(uuid, uuid, integer, text, date, date, uuid) to authenticated;
revoke all on function public.v1_accounts_invoice_retention(uuid) from public, anon;
grant execute on function public.v1_accounts_invoice_retention(uuid) to authenticated, service_role;

-- Summary workspace: the 'client still owes' (outstanding) KPI and the
-- paid-step state subtract retention per invoice, matching the Invoices tab.
create or replace function public.v1_get_project_accounts_workspace(
  p_project_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_can_view boolean;
  v_can_values boolean;
  v_can_supplier boolean;
  v_project public.v1_projects%rowtype;
  v_profile public.v1_accounts_project_commercial_profiles%rowtype;
  v_baseline public.v1_accounts_baseline_revisions%rowtype;
  v_contract numeric(20,2) := 0;
  v_vatf numeric := 1;
  v_invoiced numeric := 0;
  v_received numeric := 0;
  v_certified numeric := 0;
  v_pdc numeric := 0;
  v_still_due numeric := 0;
  v_draft numeric := 0;
  v_bills_total numeric := 0;
  v_bills_paid numeric := 0;
  v_bills_open numeric := 0;
  v_bills_overdue integer := 0;
  v_open_claim_id uuid;
  v_open_claim_ref text;
  v_open_claim_gross numeric := 0;
  v_building_count integer := 0;
  v_stage_count integer := 0;
  v_invoice_count integer := 0;
  v_latest_invoice_ref text;
  v_progress_any boolean := false;
  v_invoice_any boolean := false;
  v_paid_ex numeric := 0;
  v_setup_state text;
  v_progress_state text;
  v_invoice_state text;
  v_paid_state text;
  v_steps jsonb;
  v_heatmap jsonb := '[]'::jsonb;
  v_attention jsonb := '[]'::jsonb;
  v_result jsonb;
begin
  if auth.uid() is null or p_project_id is null or not public.v1_current_actor_is_active() then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501'; end if;
  v_can_view := public.v1_current_user_has_capability('view_project_accounts', p_project_id);
  v_can_values := public.v1_current_user_has_capability('view_project_commercial_values', p_project_id);
  v_can_supplier := public.v1_current_user_has_capability('view_supplier_costs', p_project_id);
  if not v_can_view and not v_can_supplier then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501'; end if;
  select * into v_project from public.v1_projects where id = p_project_id;
  if not found then raise exception 'R39_ACCOUNTS_PROJECT_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into v_profile from public.v1_accounts_project_commercial_profiles where project_id = p_project_id;
  if found and v_profile.current_baseline_revision_id is not null then
    select * into v_baseline from public.v1_accounts_baseline_revisions where id = v_profile.current_baseline_revision_id;
    v_contract := coalesce(v_baseline.contract_value, 0);
    v_vatf := 1 + coalesce(v_baseline.vat_rate_percent, 0) / 100;
    v_progress_any := exists (select 1 from public.v1_accounts_billing_progress
      where baseline_revision_id = v_baseline.id and confirmed_percent > 0);
    select count(distinct project_scope_id), count(distinct stage_key)
      into v_building_count, v_stage_count
    from public.v1_accounts_billing_progress where baseline_revision_id = v_baseline.id;
  end if;

  select coalesce(sum(case when i.status not in ('draft','returned','cancelled') then i.claimed_ex_vat else 0 end), 0),
         coalesce(sum(case when i.status <> 'cancelled' then public.v1_accounts_invoice_paid_amount(i.id) else 0 end), 0),
         coalesce(sum(case when i.status <> 'cancelled' then public.v1_accounts_invoice_certified_incl_vat(i.id) else 0 end), 0),
         coalesce(sum(case when i.status <> 'cancelled' then public.v1_accounts_invoice_pdc_exposure(i.id) else 0 end), 0),
         greatest(coalesce(sum(case when i.status <> 'cancelled'
           then public.v1_accounts_invoice_certified_incl_vat(i.id) - i.retention_snapshot - public.v1_accounts_invoice_paid_amount(i.id)
           else 0 end), 0), 0),
         bool_or(i.status not in ('draft','cancelled')),
         count(*) filter (where i.status not in ('draft','cancelled'))
    into v_invoiced, v_received, v_certified, v_pdc, v_still_due, v_invoice_any, v_invoice_count
  from public.v1_accounts_client_invoices i where i.project_id = p_project_id;
  v_invoice_any := coalesce(v_invoice_any, false);
  v_invoice_count := coalesce(v_invoice_count, 0);

  select i.invoice_reference into v_latest_invoice_ref
  from public.v1_accounts_client_invoices i
  where i.project_id = p_project_id and i.status not in ('draft','cancelled')
  order by i.created_at desc limit 1;

  select coalesce(sum(l.claimed_amount), 0) into v_draft
  from public.v1_accounts_client_claim_lines l
  join public.v1_accounts_client_claims c on c.id = l.claim_id
  where c.project_id = p_project_id and c.status in ('draft', 'ready_for_accounts');

  select c.id, c.claim_reference,
         coalesce((select sum(l.claimed_amount) from public.v1_accounts_client_claim_lines l where l.claim_id = c.id), 0)
    into v_open_claim_id, v_open_claim_ref, v_open_claim_gross
  from public.v1_accounts_client_claims c
  where c.project_id = p_project_id and c.status = 'draft'
  order by c.updated_at desc limit 1;

  if v_can_supplier then
    select coalesce(sum(case when b.status <> 'cancelled' then b.total_incl_vat else 0 end), 0),
           coalesce(sum(case when b.status <> 'cancelled' then public.v1_accounts_supplier_paid_amount(b.id) else 0 end), 0),
           coalesce(sum(case when b.status <> 'cancelled' then greatest(b.total_incl_vat - public.v1_accounts_supplier_paid_amount(b.id), 0) else 0 end), 0),
           count(*) filter (where b.status <> 'cancelled' and b.due_date < current_date
             and public.v1_accounts_supplier_paid_amount(b.id) < b.total_incl_vat)
      into v_bills_total, v_bills_paid, v_bills_open, v_bills_overdue
    from public.v1_accounts_supplier_bills b where b.project_id = p_project_id;
  end if;

  v_paid_ex := round(least(v_received / v_vatf, v_invoiced), 2);

  -- Heatmap: invoiced % per current building x stage cell.
  if v_can_view and v_can_values and v_baseline.id is not null then
    select coalesce(jsonb_agg(cell order by ord, bname), '[]'::jsonb) into v_heatmap from (
      select sa.display_order as ord, scope.name as bname,
        jsonb_build_object('building_scope_id', bp.project_scope_id, 'building_name', scope.name,
          'stage_key', bp.stage_key, 'stage_label', sa.stage_name,
          'stage_value', public.v1_accounts_stage_value(bp.id)::text,
          'invoiced_amount', inv.amount::text,
          'invoiced_percent', case when public.v1_accounts_stage_value(bp.id) > 0
            then round(inv.amount / public.v1_accounts_stage_value(bp.id) * 100, 1) else 0 end::text) as cell
      from public.v1_accounts_billing_progress bp
      join public.v1_accounts_baseline_stage_allocations sa
        on sa.baseline_revision_id = bp.baseline_revision_id and sa.stage_key = bp.stage_key
      join public.v1_project_scopes scope on scope.id = bp.project_scope_id
      left join lateral (
        select coalesce(sum(l.claimed_amount), 0) as amount
        from public.v1_accounts_client_claim_lines l
        join public.v1_accounts_client_claims c on c.id = l.claim_id
        where c.project_id = p_project_id and c.status = 'invoiced'
          and l.project_scope_id = bp.project_scope_id and l.stage_key = bp.stage_key
      ) inv on true
      where bp.baseline_revision_id = v_baseline.id
    ) cells;
  end if;

  -- Attention (server-derived).
  if v_baseline.id is null then
    v_attention := v_attention || jsonb_build_array(jsonb_build_object(
      'severity', 'bad', 'kind', 'setup_incomplete', 'action_key', 'open_contract',
      'target_type', 'project', 'target_id', p_project_id));
  elsif v_can_values then
    v_attention := v_attention || coalesce((select jsonb_agg(jsonb_build_object(
        'severity', 'bad', 'kind', 'invoice_overdue', 'action_key', 'open_invoice',
        'target_type', 'invoice', 'target_id', i.id))
      from public.v1_accounts_client_invoices i where i.project_id = p_project_id
        and i.status not in ('draft','returned','cancelled','paid') and i.due_date < current_date), '[]'::jsonb);
    v_attention := v_attention || coalesce((select jsonb_agg(jsonb_build_object(
        'severity', 'pri', 'kind', 'awaiting_certification', 'action_key', 'certify',
        'target_type', 'invoice', 'target_id', i.id))
      from public.v1_accounts_client_invoices i where i.project_id = p_project_id and i.status = 'submitted'
        and not exists (select 1 from public.v1_accounts_client_certifications c where c.invoice_id = i.id)), '[]'::jsonb);
    if v_open_claim_id is not null and v_open_claim_gross > 0 then
      v_attention := v_attention || jsonb_build_array(jsonb_build_object('severity','ok','kind','claim_ready',
        'action_key','open_claim','target_type','claim','target_id',v_open_claim_id));
    elsif v_open_claim_id is not null then
      v_attention := v_attention || jsonb_build_array(jsonb_build_object('severity','pri','kind','claim_empty',
        'action_key','open_claim','target_type','claim','target_id',v_open_claim_id));
    elsif v_contract > 0 then
      v_attention := v_attention || jsonb_build_array(jsonb_build_object('severity','pri','kind','no_claim',
        'action_key','start_claim','target_type','project','target_id',p_project_id));
    end if;
    if v_pdc > 0 then
      v_attention := v_attention || jsonb_build_array(jsonb_build_object('severity','pri','kind','cheques_in_hand',
        'action_key','open_invoices','target_type','project','target_id',p_project_id));
    end if;
  end if;
  if v_can_supplier and v_bills_overdue > 0 then
    v_attention := v_attention || jsonb_build_array(jsonb_build_object('severity','warn','kind','supplier_overdue',
      'action_key','open_supplier_bills','target_type','project','target_id',p_project_id,
      'params', jsonb_build_object('count', v_bills_overdue)));
  end if;

  v_setup_state := case when v_baseline.id is not null then 'done' else 'current' end;
  v_progress_state := case when v_progress_any then 'done' when v_baseline.id is not null then 'current' else '' end;
  v_invoice_state := case when v_invoice_any then 'done' when v_progress_any then 'current' else '' end;
  v_paid_state := case when v_received > 0 and v_still_due <= 0 and v_invoice_any then 'done' when v_invoice_any then 'current' else '' end;

  -- Steps. Monetary figures (`detail`) only with commercial access; the
  -- state/label shape is identical for every actor.
  if v_can_values then
    v_steps := jsonb_build_array(
      jsonb_build_object('key','setup','state',v_setup_state,'detail',
        jsonb_build_object('contract_value', v_contract::text,
          'building_count', v_building_count, 'stage_count', v_stage_count)),
      jsonb_build_object('key','progress','state',v_progress_state,'detail',
        case when v_open_claim_id is not null
          then jsonb_build_object('claim_reference', v_open_claim_ref, 'claim_gross', v_open_claim_gross::text)
          else null end),
      jsonb_build_object('key','invoice','state',v_invoice_state,'detail',
        case when v_invoice_count > 0
          then jsonb_build_object('issued_count', v_invoice_count, 'latest_reference', v_latest_invoice_ref)
          else null end),
      jsonb_build_object('key','paid','state',v_paid_state,'detail',
        jsonb_build_object('received', v_received::text,
          'to_come', greatest(round(v_contract * v_vatf, 2) - v_received, 0)::text)));
  else
    v_steps := jsonb_build_array(
      jsonb_build_object('key','setup','state',v_setup_state),
      jsonb_build_object('key','progress','state',v_progress_state),
      jsonb_build_object('key','invoice','state',v_invoice_state),
      jsonb_build_object('key','paid','state',v_paid_state));
  end if;

  v_result := jsonb_build_object(
    'schema_version', 1, 'project_id', v_project.id,
    'project_reference', v_project.project_ref, 'project_name', v_project.name,
    'has_baseline', v_baseline.id is not null,
    'capabilities', jsonb_build_object('view_project_accounts', v_can_view,
      'view_project_commercial_values', v_can_values, 'view_supplier_costs', v_can_supplier),
    'steps', v_steps,
    'badges', jsonb_build_object(
      'claims_draft', v_open_claim_id is not null,
      'supplier_count', case when v_can_supplier then v_bills_overdue else null end),
    'attention', v_attention);

  if v_can_values then
    v_result := v_result || jsonb_build_object(
      'money_flow', jsonb_build_object(
        'paid', v_paid_ex::text,
        'invoiced_waiting', greatest(v_invoiced - v_paid_ex, 0)::text,
        'done_not_invoiced', v_draft::text,
        'remaining', greatest(v_contract - v_invoiced - v_draft, 0)::text),
      'kpis', jsonb_build_object(
        'contract_value', v_contract::text,
        'contract_incl_vat', round(v_contract * v_vatf, 2)::text,
        'invoiced', v_invoiced::text,
        'received', v_received::text,
        'certified', v_certified::text,
        'outstanding', v_still_due::text,
        'cheques_in_hand', v_pdc::text,
        'done_not_invoiced', v_draft::text),
      'heatmap', v_heatmap);
  end if;
  if v_can_supplier then
    v_result := v_result || jsonb_build_object(
      'supplier', jsonb_build_object('billed', v_bills_total::text, 'paid', v_bills_paid::text,
        'unpaid', v_bills_open::text, 'overdue_count', v_bills_overdue),
      'cash', jsonb_build_object('received', v_received::text, 'paid_to_suppliers', v_bills_paid::text,
        'net', (v_received - v_bills_paid)::text));
  end if;
  return v_result;
end;
$$;

revoke all on function public.v1_get_project_accounts_workspace(uuid) from public, anon;
grant execute on function public.v1_get_project_accounts_workspace(uuid) to authenticated, service_role;


-- ---------------------------------------------------------------------------
-- Section 28 R-5: the retention hold-back reduces outstanding/Still-Due in the
-- Accountant-office portfolio, the project overview, the office register and
-- the register exports too (not only the per-project Invoices tab). Each
-- function below is the latest committed body with the retention term added to
-- its due math; everything else is unchanged. CREATE OR REPLACE preserves the
-- existing grants. Default retention_snapshot = 0 keeps every current figure.
-- ---------------------------------------------------------------------------

create or replace function public.v1_get_accounts_portfolio(
  p_project_id uuid default null,
  p_client text default null,
  p_commercial_state text default null,
  p_due_state text default null,
  p_payment_state text default null,
  p_pdc_state text default null,
  p_supplier_match_state text default null,
  p_search text default null,
  p_before_activity_at timestamptz default null,
  p_before_project_id uuid default null,
  p_limit integer default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_exact_role text := public.v1_permission_exact_role(auth.uid());
  v_rows jsonb;
  v_totals jsonb;
  v_actions jsonb;
  v_next jsonb;
  v_authorized_count integer;
  v_filtered_count integer;
begin
  if v_actor is null or not public.v1_accounts_portfolio_role_allowed() then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
  end if;
  if p_limit < 1 or p_limit > 100
    or (p_before_activity_at is null) <> (p_before_project_id is null)
    or (p_commercial_state is not null and p_commercial_state not in (
      'active', 'not_initialized', 'action_required'
    ))
    or (p_due_state is not null and p_due_state not in (
      'current', 'due_soon', 'overdue'
    ))
    or (p_payment_state is not null and p_payment_state not in (
      'unpaid', 'partially_paid', 'paid'
    ))
    or (p_pdc_state is not null and p_pdc_state not in (
      'expected', 'received', 'deposited', 'cleared', 'returned',
      'bounced', 'replaced', 'cancelled'
    ))
    or (p_supplier_match_state is not null
      and p_supplier_match_state not in ('blocked', 'review', 'matched')) then
    raise exception 'R39_ACCOUNTS_INVALID_PORTFOLIO_FILTER'
      using errcode = '22023';
  end if;

  with authorized as materialized (
    select project.id, project.project_ref, project.name, project.project_site,
      project.state, project.updated_at as project_updated_at,
      client.party_name as client_name,
      public.v1_current_user_has_capability(
        'view_project_commercial_values', project.id
      ) as can_view_values,
      public.v1_current_user_has_capability(
        'view_supplier_costs', project.id
      ) as can_view_supplier_costs
    from public.v1_projects project
    left join lateral (
      select party.party_name
      from public.v1_project_parties party
      where party.project_id = project.id and party.party_kind = 'client'
      order by party.created_at, party.id
      limit 1
    ) client on true
    where public.v1_current_user_has_capability(
      'view_project_accounts', project.id
    )
      and public.v1_current_user_has_capability(
        'view_project_commercial_values', project.id
      )
      and (p_project_id is null or project.id = p_project_id)
  ), facts as materialized (
    select authorized.*,
      baseline.id as baseline_revision_id,
      baseline.revision_number as baseline_revision_number,
      baseline.currency_code,
      coalesce(baseline.contract_value, 0) as contract_value,
      coalesce(progress.confirmed_eligible, 0) as confirmed_eligible,
      greatest(
        coalesce(progress.confirmed_eligible, 0)
          - coalesce(claims.claimed_reserved, 0), 0
      ) as available_to_claim,
      coalesce(invoices.claimed, 0) as claimed,
      coalesce(invoices.certified, 0) as certified,
      coalesce(invoices.paid, 0) as paid,
      coalesce(invoices.retention, 0) as retention,
      greatest(coalesce(invoices.certified, 0)
        - coalesce(invoices.retention, 0)
        - coalesce(invoices.paid, 0), 0) as still_due,
      coalesce(invoices.pdc_exposure, 0) as pdc_exposure,
      coalesce(progress.confirmed_percent, 0) as confirmed_percent,
      coalesce(invoices.overdue_count, 0) as overdue_count,
      coalesce(invoices.due_soon_count, 0) as due_soon_count,
      coalesce(invoices.open_invoice_count, 0) as open_invoice_count,
      coalesce(invoices.returned_invoice_count, 0)
        + coalesce(claims.returned_claim_count, 0) as returned_count,
      coalesce(pdcs.action_pdc_count, 0) as action_pdc_count,
      coalesce(suppliers.review_count, 0) as supplier_review_count,
      coalesce(suppliers.open_amount, 0) as supplier_open_amount,
      greatest(
        authorized.project_updated_at,
        coalesce(baseline.created_at, '-infinity'::timestamptz),
        coalesce(progress.latest_at, '-infinity'::timestamptz),
        coalesce(claims.latest_at, '-infinity'::timestamptz),
        coalesce(invoices.latest_at, '-infinity'::timestamptz),
        coalesce(pdcs.latest_at, '-infinity'::timestamptz),
        coalesce(suppliers.latest_at, '-infinity'::timestamptz)
      ) as latest_activity_at,
      case
        when coalesce(invoices.overdue_count, 0) > 0 then 'overdue'
        when coalesce(invoices.due_soon_count, 0) > 0 then 'due_soon'
        else 'current'
      end as due_state,
      case
        when coalesce(invoices.certified, 0) > 0
          and coalesce(invoices.paid, 0)
            >= invoices.certified - coalesce(invoices.retention, 0) then 'paid'
        when coalesce(invoices.paid, 0) > 0 then 'partially_paid'
        else 'unpaid'
      end as payment_state
    from authorized
    left join public.v1_accounts_project_commercial_profiles profile
      on profile.project_id = authorized.id
    left join public.v1_accounts_baseline_revisions baseline
      on baseline.id = profile.current_baseline_revision_id
    left join lateral (
      select
        coalesce(sum(round(
          baseline.contract_value
          * building.allocation_percent / 100
          * stage.allocation_percent / 100
          * entry.confirmed_percent / 100, 2
        )), 0) as confirmed_eligible,
        case when coalesce(sum(
          building.allocation_percent * stage.allocation_percent
        ), 0) = 0 then 0 else round(
          sum(building.allocation_percent * stage.allocation_percent
            * entry.confirmed_percent)
          / sum(building.allocation_percent * stage.allocation_percent), 2
        ) end as confirmed_percent,
        max(entry.updated_at) as latest_at
      from public.v1_accounts_billing_progress entry
      join public.v1_accounts_baseline_building_allocations building
        on building.id = entry.building_allocation_id
      join public.v1_accounts_baseline_stage_allocations stage
        on stage.id = entry.stage_allocation_id
      where entry.project_id = authorized.id
        and entry.baseline_revision_id = baseline.id
        and entry.review_status <> 'returned'
    ) progress on true
    left join lateral (
      select coalesce(sum(case when claim.status <> 'cancelled'
          then line.claimed_amount else 0 end), 0) as claimed_reserved,
        count(*) filter (where claim.status = 'draft'
          and claim.is_stale) as returned_claim_count,
        max(claim.updated_at) as latest_at
      from public.v1_accounts_client_claims claim
      left join public.v1_accounts_client_claim_lines line
        on line.claim_id = claim.id
      where claim.project_id = authorized.id
    ) claims on true
    left join lateral (
      select coalesce(sum(case when invoice.status not in (
          'draft', 'returned', 'cancelled'
        ) then invoice.claimed_ex_vat else 0 end), 0) as claimed,
        coalesce(sum(case when invoice.status <> 'cancelled'
          then public.v1_accounts_invoice_certified_incl_vat(invoice.id)
          else 0 end), 0) as certified,
        coalesce(sum(case when invoice.status <> 'cancelled'
          then public.v1_accounts_invoice_paid_amount(invoice.id)
          else 0 end), 0) as paid,
        coalesce(sum(case when invoice.status <> 'cancelled'
          then public.v1_accounts_invoice_retention(invoice.id)
          else 0 end), 0) as retention,
        coalesce(sum(case when invoice.status <> 'cancelled'
          then public.v1_accounts_invoice_pdc_exposure(invoice.id)
          else 0 end), 0) as pdc_exposure,
        count(*) filter (where invoice.due_date < current_date
          and invoice.status not in ('draft','returned','cancelled','paid'))
          as overdue_count,
        count(*) filter (where invoice.due_date >= current_date
          and invoice.due_date <= current_date
            + invoice.reminder_lead_days_snapshot
          and invoice.status not in ('draft','returned','cancelled','paid'))
          as due_soon_count,
        count(*) filter (where invoice.status not in ('cancelled','paid'))
          as open_invoice_count,
        count(*) filter (where invoice.status = 'returned')
          as returned_invoice_count,
        max(invoice.updated_at) as latest_at
      from public.v1_accounts_client_invoices invoice
      where invoice.project_id = authorized.id
    ) invoices on true
    left join lateral (
      select count(*) filter (where pdc.action_required) as action_pdc_count,
        max(pdc.updated_at) as latest_at
      from public.v1_accounts_client_pdcs pdc
      where pdc.project_id = authorized.id
    ) pdcs on true
    left join lateral (
      select count(*) filter (where bill.status <> 'cancelled'
          and public.v1_accounts_supplier_match_status(bill.id) <> 'matched')
          as review_count,
        coalesce(sum(case when bill.status <> 'cancelled' then greatest(
          bill.total_incl_vat
            - public.v1_accounts_supplier_paid_amount(bill.id), 0
        ) else 0 end), 0) as open_amount,
        max(bill.updated_at) as latest_at
      from public.v1_accounts_supplier_bills bill
      where bill.project_id = authorized.id
        and authorized.can_view_supplier_costs
    ) suppliers on true
  ), matched as materialized (
    select facts.* from facts
    where (p_client is null or facts.client_name ilike '%'||btrim(p_client)||'%')
      and (p_search is null or btrim(p_search) = ''
        or facts.project_ref ilike '%'||btrim(p_search)||'%'
        or facts.name ilike '%'||btrim(p_search)||'%'
        or coalesce(facts.client_name, '') ilike '%'||btrim(p_search)||'%')
      and (p_commercial_state is null or case p_commercial_state
        when 'not_initialized' then facts.baseline_revision_id is null
        when 'active' then facts.baseline_revision_id is not null
          and facts.overdue_count + facts.due_soon_count + facts.returned_count
            + facts.action_pdc_count + facts.supplier_review_count = 0
        when 'action_required' then facts.overdue_count + facts.due_soon_count
          + facts.returned_count + facts.action_pdc_count
          + facts.supplier_review_count > 0 end)
      and (p_due_state is null or facts.due_state = p_due_state)
      and (p_payment_state is null or facts.payment_state = p_payment_state)
      and (p_pdc_state is null or exists (
        select 1 from public.v1_accounts_client_pdcs pdc
        where pdc.project_id = facts.id and pdc.status = p_pdc_state
      ))
      and (p_supplier_match_state is null or (
        facts.can_view_supplier_costs and exists (
          select 1 from public.v1_accounts_supplier_bills bill
          where bill.project_id = facts.id and bill.status <> 'cancelled'
            and public.v1_accounts_supplier_match_status(bill.id)
              = p_supplier_match_state
        )
      ))
  ), filtered as materialized (
    select matched.* from matched
    where p_before_activity_at is null
      or (matched.latest_activity_at, matched.id)
        < (p_before_activity_at, p_before_project_id)
  ), page as materialized (
    select * from filtered
    order by latest_activity_at desc, id desc limit p_limit + 1
  )
  select
    (select count(*) from authorized),
    (select count(*) from matched),
    coalesce((select jsonb_agg(
      jsonb_build_object(
        'project_id', page.id,
        'project_reference', page.project_ref,
        'project_name', page.name,
        'project_site', page.project_site,
        'project_state', page.state,
        'client_name', page.client_name,
        'baseline_revision_number', page.baseline_revision_number,
        'currency_code', page.currency_code,
        'contract_baseline', page.contract_value::text,
        'confirmed_eligible', page.confirmed_eligible::text,
        'available_to_claim', page.available_to_claim::text,
        'claimed', page.claimed::text,
        'certified', page.certified::text,
        'amount_paid_till_date', page.paid::text,
        'still_due', page.still_due::text,
        'pdc_exposure', page.pdc_exposure::text,
        'confirmed_percent', page.confirmed_percent::text,
        'due_state', page.due_state,
        'payment_state', page.payment_state,
        'action_count', page.overdue_count + page.due_soon_count
          + page.returned_count + page.action_pdc_count
          + page.supplier_review_count,
        'latest_activity_at', page.latest_activity_at
      ) || case when page.can_view_supplier_costs then jsonb_build_object(
        'supplier_review_count', page.supplier_review_count,
        'supplier_open_amount', page.supplier_open_amount::text
      ) else '{}'::jsonb end
      order by page.latest_activity_at desc, page.id desc
    ) from (select * from page limit p_limit) page), '[]'::jsonb),
    (select jsonb_build_object(
      'project_count', count(*),
      'contract_baseline', coalesce(sum(contract_value),0)::text,
      'confirmed_eligible', coalesce(sum(confirmed_eligible),0)::text,
      'available_to_claim', coalesce(sum(available_to_claim),0)::text,
      'claimed', coalesce(sum(claimed),0)::text,
      'certified', coalesce(sum(certified),0)::text,
      'amount_paid_till_date', coalesce(sum(paid),0)::text,
      'still_due', coalesce(sum(still_due),0)::text,
      'pdc_exposure', coalesce(sum(pdc_exposure),0)::text,
      'action_count', coalesce(sum(overdue_count + due_soon_count
        + returned_count + action_pdc_count + supplier_review_count),0)
    ) from facts),
    (select coalesce(jsonb_agg(action order by
      (action->>'severity_rank')::integer, action->>'occurred_at' desc
    ), '[]'::jsonb) from (
      select jsonb_build_object(
        'project_id', facts.id,
        'project_reference', facts.project_ref,
        'project_name', facts.name,
        'code', case
          when facts.overdue_count > 0 then 'overdue_invoice'
          when facts.action_pdc_count > 0 then 'pdc_action_required'
          when facts.supplier_review_count > 0 then 'supplier_match_review'
          when facts.returned_count > 0 then 'returned_for_correction'
          else 'due_soon_invoice' end,
        'owner_role', case
          when facts.supplier_review_count > 0 then 'procurement'
          when facts.returned_count > 0 then 'project_engineer'
          else 'accountant' end,
        'severity', case when facts.overdue_count > 0
          or facts.action_pdc_count > 0 then 'critical'
          when facts.supplier_review_count > 0
            or facts.returned_count > 0 then 'high' else 'medium' end,
        'severity_rank', case when facts.overdue_count > 0
          or facts.action_pdc_count > 0 then 1
          when facts.supplier_review_count > 0
            or facts.returned_count > 0 then 2 else 3 end,
        'count', greatest(facts.overdue_count, facts.action_pdc_count,
          facts.supplier_review_count, facts.returned_count,
          facts.due_soon_count),
        'occurred_at', facts.latest_activity_at
      ) as action
      from facts
      where facts.overdue_count + facts.due_soon_count + facts.returned_count
        + facts.action_pdc_count + facts.supplier_review_count > 0
      order by case when facts.overdue_count > 0
        or facts.action_pdc_count > 0 then 1
        when facts.supplier_review_count > 0
          or facts.returned_count > 0 then 2 else 3 end,
        facts.latest_activity_at desc
      limit 12
    ) queue),
    (select case when count(*) > p_limit then (
      select jsonb_build_object(
        'before_activity_at', cursor_row.latest_activity_at,
        'before_project_id', cursor_row.id
      )
      from page cursor_row
      order by cursor_row.latest_activity_at desc, cursor_row.id desc
      offset greatest(p_limit - 1, 0) limit 1
    ) else null end from page)
  into v_authorized_count, v_filtered_count, v_rows, v_totals, v_actions, v_next;

  return jsonb_build_object(
    'schema_version', 2,
    'scope', 'portfolio',
    'actor_exact_role', v_exact_role,
    'can_export', public.v1_current_user_has_capability(
      'export_accounts_registers', null
    ),
    'authorized_project_count', v_authorized_count,
    'filtered_project_count', v_filtered_count,
    'totals', v_totals,
    'projects', v_rows,
    'action_queue', v_actions,
    'next_cursor', v_next
  );
end;
$$;

create or replace function public.v1_get_project_accounts_overview(
  p_project_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_exact_role text := public.v1_permission_exact_role(auth.uid());
  v_can_view boolean;
  v_can_values boolean;
  v_can_supplier boolean;
  v_project public.v1_projects%rowtype;
  v_profile public.v1_accounts_project_commercial_profiles%rowtype;
  v_baseline public.v1_accounts_baseline_revisions%rowtype;
  v_progress jsonb;
  v_invoices jsonb;
  v_supplier jsonb;
  v_result jsonb;
begin
  if auth.uid() is null or p_project_id is null
    or not public.v1_current_actor_is_active() then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
  end if;
  v_can_view := public.v1_current_user_has_capability(
    'view_project_accounts', p_project_id
  );
  v_can_values := public.v1_current_user_has_capability(
    'view_project_commercial_values', p_project_id
  );
  v_can_supplier := public.v1_current_user_has_capability(
    'view_supplier_costs', p_project_id
  );
  if not v_can_view and not v_can_supplier then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
  end if;
  select * into v_project from public.v1_projects where id = p_project_id;
  if not found then
    raise exception 'R39_ACCOUNTS_PROJECT_NOT_FOUND' using errcode = 'P0002';
  end if;
  select * into v_profile from public.v1_accounts_project_commercial_profiles
    where project_id = p_project_id;
  if found and v_profile.current_baseline_revision_id is not null then
    select * into v_baseline from public.v1_accounts_baseline_revisions
      where id = v_profile.current_baseline_revision_id;
  end if;

  if v_can_view then
    select jsonb_build_object(
      'confirmed_percent', coalesce(case when sum(
        building.allocation_percent * stage.allocation_percent
      ) = 0 then 0 else round(sum(
        building.allocation_percent * stage.allocation_percent
          * entry.confirmed_percent
      ) / sum(building.allocation_percent * stage.allocation_percent),2) end,0)::text,
      'suggested_percent', coalesce(case when sum(
        building.allocation_percent * stage.allocation_percent
      ) = 0 then 0 else round(sum(
        building.allocation_percent * stage.allocation_percent
          * entry.suggested_percent
      ) / sum(building.allocation_percent * stage.allocation_percent),2) end,0)::text,
      'pending_review_count', count(*) filter (
        where entry.review_status = 'pending'
      ),
      'building_position', coalesce(jsonb_agg(jsonb_build_object(
        'building_scope_id', scope.id,
        'building_name', scope.name,
        'confirmed_percent', entry.confirmed_percent::text,
        'suggested_percent', entry.suggested_percent::text,
        'stage_key', entry.stage_key,
        'stage_name', stage.stage_name,
        'review_status', entry.review_status,
        'action_owner', case
          when entry.review_status = 'pending' then 'management'
          when entry.suggested_percent > entry.confirmed_percent
            then 'project_engineer' else 'none' end,
        'updated_at', entry.updated_at
      ) order by scope.scope_code, stage.display_order), '[]'::jsonb)
    ) || case when v_can_values then jsonb_build_object(
      'confirmed_eligible', coalesce(sum(round(
        v_baseline.contract_value
        * building.allocation_percent / 100
        * stage.allocation_percent / 100
        * entry.confirmed_percent / 100, 2
      )),0)::text
    ) else '{}'::jsonb end
    into v_progress
    from public.v1_accounts_billing_progress entry
    join public.v1_accounts_baseline_building_allocations building
      on building.id = entry.building_allocation_id
    join public.v1_accounts_baseline_stage_allocations stage
      on stage.id = entry.stage_allocation_id
    join public.v1_project_scopes scope on scope.id = entry.project_scope_id
    where entry.project_id = p_project_id
      and entry.baseline_revision_id = v_baseline.id
      and entry.review_status <> 'returned';
  end if;

  if v_can_values then
    select jsonb_build_object(
      'claimed', coalesce(sum(case when invoice.status not in (
        'draft','returned','cancelled'
      ) then invoice.claimed_ex_vat else 0 end),0)::text,
      'certified', coalesce(sum(case when invoice.status <> 'cancelled'
        then public.v1_accounts_invoice_certified_incl_vat(invoice.id)
        else 0 end),0)::text,
      'amount_paid_till_date', coalesce(sum(case
        when invoice.status <> 'cancelled'
        then public.v1_accounts_invoice_paid_amount(invoice.id)
        else 0 end),0)::text,
      'still_due', greatest(coalesce(sum(case
        when invoice.status <> 'cancelled'
        then public.v1_accounts_invoice_certified_incl_vat(invoice.id)
          - public.v1_accounts_invoice_retention(invoice.id)
          - public.v1_accounts_invoice_paid_amount(invoice.id)
        else 0 end),0),0)::text,
      'pdc_exposure', coalesce(sum(case when invoice.status <> 'cancelled'
        then public.v1_accounts_invoice_pdc_exposure(invoice.id)
        else 0 end),0)::text,
      'recent_invoices', coalesce(jsonb_agg(jsonb_build_object(
        'invoice_id', invoice.id,
        'invoice_reference', invoice.invoice_reference,
        'status', invoice.status,
        'claimed_ex_vat', invoice.claimed_ex_vat::text,
        'certified_incl_vat',
          public.v1_accounts_invoice_certified_incl_vat(invoice.id)::text,
        'amount_paid_till_date',
          public.v1_accounts_invoice_paid_amount(invoice.id)::text,
        'still_due', greatest(
          public.v1_accounts_invoice_certified_incl_vat(invoice.id)
          - public.v1_accounts_invoice_retention(invoice.id)
          - public.v1_accounts_invoice_paid_amount(invoice.id),0
        )::text,
        'due_date', invoice.due_date,
        'updated_at', invoice.updated_at
      ) order by invoice.updated_at desc) filter (
        where invoice.id in (select recent.id from (
          select item.id from public.v1_accounts_client_invoices item
          where item.project_id = p_project_id
          order by item.updated_at desc, item.id desc limit 5
        ) recent)
      ), '[]'::jsonb)
    ) into v_invoices
    from public.v1_accounts_client_invoices invoice
    where invoice.project_id = p_project_id;
  end if;

  if v_can_supplier then
    select jsonb_build_object(
      'total_bills', count(*) filter (where bill.status <> 'cancelled'),
      'needs_review', count(*) filter (where bill.status <> 'cancelled'
        and public.v1_accounts_supplier_match_status(bill.id) <> 'matched'),
      'commitments', coalesce(sum(case when bill.status <> 'cancelled'
        then bill.total_incl_vat else 0 end),0)::text,
      'paid', coalesce(sum(case when bill.status <> 'cancelled'
        then public.v1_accounts_supplier_paid_amount(bill.id) else 0 end),0)::text,
      'open_amount', coalesce(sum(case when bill.status <> 'cancelled'
        then greatest(bill.total_incl_vat
          - public.v1_accounts_supplier_paid_amount(bill.id),0)
        else 0 end),0)::text
    ) into v_supplier
    from public.v1_accounts_supplier_bills bill
    where bill.project_id = p_project_id;
  end if;

  v_result := jsonb_build_object(
    'schema_version', 2,
    'project_id', v_project.id,
    'project_reference', v_project.project_ref,
    'project_name', v_project.name,
    'project_site', v_project.project_site,
    'project_state', v_project.state,
    'client_name', (select party.party_name
      from public.v1_project_parties party
      where party.project_id = p_project_id and party.party_kind = 'client'
      limit 1),
    'actor_exact_role', v_exact_role,
    'capabilities', jsonb_build_object(
      'view_project_accounts', v_can_view,
      'view_project_commercial_values', v_can_values,
      'view_supplier_costs', v_can_supplier,
      'suggest_billing_progress', public.v1_current_user_has_capability(
        'suggest_billing_progress', p_project_id
      ),
      'confirm_billing_progress', public.v1_current_user_has_capability(
        'confirm_billing_progress', p_project_id
      ),
      'prepare_client_claim', public.v1_current_user_has_capability(
        'prepare_client_claim', p_project_id
      ),
      'manage_client_invoices', public.v1_current_user_has_capability(
        'manage_client_invoices', p_project_id
      ),
      'manage_supplier_bills', public.v1_current_user_has_capability(
        'manage_supplier_bills', p_project_id
      ),
      'approve_supplier_bill_payment', public.v1_current_user_has_capability(
        'approve_supplier_bill_payment', p_project_id
      ),
      'export_accounts_registers', public.v1_current_user_has_capability(
        'export_accounts_registers', p_project_id
      )
    )
  );
  if v_can_view then
    v_result := v_result || jsonb_build_object(
      'progress', coalesce(v_progress, jsonb_build_object(
        'confirmed_percent','0','suggested_percent','0',
        'pending_review_count',0,'building_position','[]'::jsonb
      ))
    );
    if v_baseline.id is not null then
      v_result := v_result || jsonb_build_object(
        'baseline', jsonb_build_object(
          'revision_id', v_baseline.id,
          'revision_number', v_baseline.revision_number,
          'status', v_baseline.status,
          'effective_at', v_baseline.effective_at
        ) || case when v_can_values then jsonb_build_object(
          'contract_value', v_baseline.contract_value::text,
          'currency_code', v_baseline.currency_code,
          'payment_terms_days', v_baseline.payment_terms_days,
          'reminder_lead_days', v_baseline.reminder_lead_days
        ) else '{}'::jsonb end
      );
    else
      v_result := v_result || jsonb_build_object('baseline', null);
    end if;
  end if;
  if v_can_values then
    v_result := v_result || jsonb_build_object(
      'receivables', coalesce(v_invoices, jsonb_build_object(
        'claimed','0','certified','0','amount_paid_till_date','0',
        'still_due','0','pdc_exposure','0','recent_invoices','[]'::jsonb
      ))
    );
  end if;
  if v_can_supplier then
    v_result := v_result || jsonb_build_object(
      'supplier', coalesce(v_supplier, jsonb_build_object(
        'total_bills',0,'needs_review',0,'commitments','0',
        'paid','0','open_amount','0'
      ))
    );
  end if;
  return v_result;
end;
$$;

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
    (select coalesce(sum(amount), 0) from filtered),
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

create or replace function public.v1_get_accounts_export(
  p_export_kind text,
  p_project_id uuid default null,
  p_idempotency_key uuid default gen_random_uuid()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_role text := public.v1_permission_exact_role(auth.uid());
  v_project public.v1_projects%rowtype;
  v_columns jsonb;
  v_rows jsonb;
  v_result jsonb;
  v_existing jsonb;
  v_payload jsonb;
begin
  if p_export_kind not in (
    'portfolio', 'project_summary', 'commercial_baseline',
    'building_allocations', 'stage_allocations', 'billing_progress',
    'progress_history', 'client_claims', 'claim_lines', 'client_invoices',
    'certifications', 'client_receipts', 'pdc_register', 'pdc_events',
    'supplier_bills', 'supplier_payments', 'accounts_documents',
    'accounts_activity'
  ) then
    raise exception 'R39_ACCOUNTS_EXPORT_KIND_INVALID' using errcode = '22023';
  end if;

  if p_export_kind = 'portfolio' then
    if v_role not in (
      'accountant', 'admin', 'senior_mechanical_engineer', 'project_manager'
    ) then
      raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
    end if;
  elsif p_project_id is null or not public.v1_current_user_has_capability(
    'export_accounts_registers', p_project_id
  ) then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
  end if;

  if p_export_kind in (
    'project_summary', 'commercial_baseline', 'building_allocations',
    'stage_allocations', 'progress_history', 'client_claims', 'claim_lines',
    'client_invoices', 'certifications', 'client_receipts', 'pdc_register',
    'pdc_events', 'accounts_documents', 'accounts_activity'
  ) and not public.v1_current_user_has_capability(
    'view_project_commercial_values', p_project_id
  ) then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
  end if;

  if p_export_kind in ('supplier_bills', 'supplier_payments')
    and not public.v1_current_user_has_capability(
      'view_supplier_costs', p_project_id
    ) then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
  end if;

  v_payload := jsonb_build_object(
    'export_kind', p_export_kind,
    'project_id', p_project_id
  );
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_get_accounts_export', p_idempotency_key, v_payload
  );
  if v_existing is not null then
    return v_existing;
  end if;

  if p_project_id is not null then
    select * into v_project
    from public.v1_projects
    where id = p_project_id;
    if not found then
      raise exception 'R39_ACCOUNTS_PROJECT_NOT_FOUND' using errcode = 'P0002';
    end if;
  end if;

  case p_export_kind
    when 'portfolio' then
      v_columns := '["Project","Client","Contract","Confirmed work","Claimed","Certified","Paid","Still due","Progress %"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        project.project_ref,
        coalesce(client.party_name, ''),
        baseline.contract_value::text,
        coalesce(progress.confirmed, 0)::text,
        coalesce(invoice.claimed, 0)::text,
        coalesce(invoice.certified, 0)::text,
        coalesce(invoice.paid, 0)::text,
        greatest(
          coalesce(invoice.certified, 0)
          - coalesce(invoice.retention, 0)
          - coalesce(invoice.paid, 0), 0
        )::text,
        coalesce(progress.percent, 0)::text
      ) order by project.project_ref), '[]'::jsonb)
      into v_rows
      from public.v1_projects project
      join public.v1_accounts_project_commercial_profiles profile
        on profile.project_id = project.id
      join public.v1_accounts_baseline_revisions baseline
        on baseline.id = profile.current_baseline_revision_id
      left join lateral (
        select party_name
        from public.v1_project_parties
        where project_id = project.id and party_kind = 'client'
        order by created_at, id
        limit 1
      ) client on true
      left join lateral (
        select
          coalesce(sum(round(
            baseline.contract_value * building.allocation_percent / 100
            * stage.allocation_percent / 100
            * progress_entry.confirmed_percent / 100, 2
          )), 0) confirmed,
          case
            when coalesce(sum(
              building.allocation_percent * stage.allocation_percent
            ), 0) = 0 then 0
            else round(sum(
              building.allocation_percent * stage.allocation_percent
              * progress_entry.confirmed_percent
            ) / sum(
              building.allocation_percent * stage.allocation_percent
            ), 2)
          end percent
        from public.v1_accounts_billing_progress progress_entry
        join public.v1_accounts_baseline_building_allocations building
          on building.id = progress_entry.building_allocation_id
        join public.v1_accounts_baseline_stage_allocations stage
          on stage.id = progress_entry.stage_allocation_id
        where progress_entry.project_id = project.id
          and progress_entry.review_status <> 'returned'
      ) progress on true
      left join lateral (
        select
          coalesce(sum(invoice_record.claimed_ex_vat), 0) claimed,
          coalesce(sum(
            public.v1_accounts_invoice_certified_incl_vat(invoice_record.id)
          ), 0) certified,
          coalesce(sum(
            public.v1_accounts_invoice_paid_amount(invoice_record.id)
          ), 0) paid,
          coalesce(sum(
            public.v1_accounts_invoice_retention(invoice_record.id)
          ), 0) retention
        from public.v1_accounts_client_invoices invoice_record
        where invoice_record.project_id = project.id
          and invoice_record.status <> 'cancelled'
      ) invoice on true
      where public.v1_current_user_has_capability(
        'export_accounts_registers', project.id
      ) and public.v1_current_user_has_capability(
        'view_project_commercial_values', project.id
      );

    when 'project_summary' then
      v_columns := '["Project Reference","Project Name","Site","Client","Contract Value","Confirmed Eligible","Available to Claim","Claimed","Certified","Paid","Still Due","Active PDC","Commercial Progress %"]'::jsonb;
      select jsonb_agg(jsonb_build_array(
        v_project.project_ref,
        v_project.name,
        v_project.project_site,
        coalesce(client.party_name, ''),
        baseline.contract_value::text,
        coalesce(progress.confirmed, 0)::text,
        greatest(
          coalesce(progress.confirmed, 0) - coalesce(claims.claimed, 0), 0
        )::text,
        coalesce(invoice.claimed, 0)::text,
        coalesce(invoice.certified, 0)::text,
        coalesce(invoice.paid, 0)::text,
        greatest(
          coalesce(invoice.certified, 0)
          - coalesce(invoice.retention, 0)
          - coalesce(invoice.paid, 0), 0
        )::text,
        coalesce(pdc.exposure, 0)::text,
        coalesce(progress.percent, 0)::text
      ))
      into v_rows
      from public.v1_accounts_project_commercial_profiles profile
      join public.v1_accounts_baseline_revisions baseline
        on baseline.id = profile.current_baseline_revision_id
      left join lateral (
        select party_name
        from public.v1_project_parties
        where project_id = p_project_id and party_kind = 'client'
        order by created_at, id
        limit 1
      ) client on true
      left join lateral (
        select
          coalesce(sum(round(
            baseline.contract_value * building.allocation_percent / 100
            * stage.allocation_percent / 100
            * progress_entry.confirmed_percent / 100, 2
          )), 0) confirmed,
          case
            when coalesce(sum(
              building.allocation_percent * stage.allocation_percent
            ), 0) = 0 then 0
            else round(sum(
              building.allocation_percent * stage.allocation_percent
              * progress_entry.confirmed_percent
            ) / sum(
              building.allocation_percent * stage.allocation_percent
            ), 2)
          end percent
        from public.v1_accounts_billing_progress progress_entry
        join public.v1_accounts_baseline_building_allocations building
          on building.id = progress_entry.building_allocation_id
        join public.v1_accounts_baseline_stage_allocations stage
          on stage.id = progress_entry.stage_allocation_id
        where progress_entry.project_id = p_project_id
          and progress_entry.review_status <> 'returned'
      ) progress on true
      left join lateral (
        select coalesce(sum(line.claimed_amount), 0) claimed
        from public.v1_accounts_client_claim_lines line
        join public.v1_accounts_client_claims claim on claim.id = line.claim_id
        where claim.project_id = p_project_id and claim.status <> 'cancelled'
      ) claims on true
      left join lateral (
        select
          coalesce(sum(invoice_record.claimed_ex_vat), 0) claimed,
          coalesce(sum(
            public.v1_accounts_invoice_certified_incl_vat(invoice_record.id)
          ), 0) certified,
          coalesce(sum(
            public.v1_accounts_invoice_paid_amount(invoice_record.id)
          ), 0) paid,
          coalesce(sum(
            public.v1_accounts_invoice_retention(invoice_record.id)
          ), 0) retention
        from public.v1_accounts_client_invoices invoice_record
        where invoice_record.project_id = p_project_id
          and invoice_record.status <> 'cancelled'
      ) invoice on true
      left join lateral (
        select coalesce(sum(pdc_record.amount), 0) exposure
        from public.v1_accounts_client_pdcs pdc_record
        where pdc_record.project_id = p_project_id
          and pdc_record.status in ('expected', 'received', 'deposited')
      ) pdc on true
      where profile.project_id = p_project_id;

    when 'commercial_baseline' then
      v_columns := '["Revision","Status","Contract Value","Currency","VAT %","Payment Terms Days","Reminder Lead Days","Effective At","Reason","Approved By","Approved Role"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        baseline.revision_number::text,
        baseline.status,
        baseline.contract_value::text,
        baseline.currency_code,
        baseline.vat_rate_percent::text,
        baseline.payment_terms_days::text,
        baseline.reminder_lead_days::text,
        baseline.effective_at::text,
        baseline.reason,
        public.v1_safe_profile_display_name(
          approver.display_name, approver.auth_user_id
        ),
        baseline.approved_by_exact_role
      ) order by baseline.revision_number desc), '[]'::jsonb)
      into v_rows
      from public.v1_accounts_baseline_revisions baseline
      join public.v1_profiles approver
        on approver.auth_user_id = baseline.approved_by_auth_user_id
      where baseline.project_id = p_project_id;

    when 'building_allocations' then
      v_columns := '["Baseline Revision","Baseline Status","Building Code","Building","Allocation %","Allocated Value"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        baseline.revision_number::text,
        baseline.status,
        scope.scope_code,
        scope.name,
        allocation.allocation_percent::text,
        round(
          baseline.contract_value * allocation.allocation_percent / 100, 2
        )::text
      ) order by baseline.revision_number desc, scope.scope_code), '[]'::jsonb)
      into v_rows
      from public.v1_accounts_baseline_building_allocations allocation
      join public.v1_accounts_baseline_revisions baseline
        on baseline.id = allocation.baseline_revision_id
      join public.v1_project_scopes scope
        on scope.id = allocation.project_scope_id
      where allocation.project_id = p_project_id;

    when 'stage_allocations' then
      v_columns := '["Baseline Revision","Baseline Status","Stage Key","Stage","Display Order","Contract %","Contract Value"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        baseline.revision_number::text,
        baseline.status,
        stage.stage_key,
        stage.stage_name,
        stage.display_order::text,
        stage.allocation_percent::text,
        round(
          baseline.contract_value * stage.allocation_percent / 100, 2
        )::text
      ) order by baseline.revision_number desc, stage.display_order), '[]'::jsonb)
      into v_rows
      from public.v1_accounts_baseline_stage_allocations stage
      join public.v1_accounts_baseline_revisions baseline
        on baseline.id = stage.baseline_revision_id
      where stage.project_id = p_project_id;

    when 'billing_progress' then
      v_columns := '["Building","Stage","Building Allocation %","Stage Allocation %","Stage Value","Suggested %","Confirmed %","Eligible Amount","Review Status","Suggested Evidence","Confirmed Evidence","Evidence Files","Suggested By","Suggested At","Confirmed By","Confirmed At","Reviewed By","Reviewed At","Updated At","Version"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        scope.name,
        stage.stage_name,
        building.allocation_percent::text,
        stage.allocation_percent::text,
        round(
          baseline.contract_value * building.allocation_percent / 100
          * stage.allocation_percent / 100, 2
        )::text,
        entry.suggested_percent::text,
        entry.confirmed_percent::text,
        round(
          baseline.contract_value * building.allocation_percent / 100
          * stage.allocation_percent / 100
          * entry.confirmed_percent / 100, 2
        )::text,
        entry.review_status,
        coalesce(entry.suggested_evidence_summary, ''),
        coalesce(entry.confirmed_evidence_summary, ''),
        (
          cardinality(entry.suggested_evidence_document_ids)
          + cardinality(entry.confirmed_evidence_document_ids)
        )::text,
        case when suggested.auth_user_id is null then '' else
          public.v1_safe_profile_display_name(
            suggested.display_name, suggested.auth_user_id
          ) end,
        coalesce(entry.suggested_at::text, ''),
        case when confirmed.auth_user_id is null then '' else
          public.v1_safe_profile_display_name(
            confirmed.display_name, confirmed.auth_user_id
          ) end,
        coalesce(entry.confirmed_at::text, ''),
        case when reviewed.auth_user_id is null then '' else
          public.v1_safe_profile_display_name(
            reviewed.display_name, reviewed.auth_user_id
          ) end,
        coalesce(entry.reviewed_at::text, ''),
        entry.updated_at::text,
        entry.record_version::text
      ) order by scope.scope_kind, scope.scope_code, stage.display_order), '[]'::jsonb)
      into v_rows
      from public.v1_accounts_billing_progress entry
      join public.v1_accounts_baseline_revisions baseline
        on baseline.id = entry.baseline_revision_id
      join public.v1_accounts_baseline_building_allocations building
        on building.id = entry.building_allocation_id
      join public.v1_project_scopes scope on scope.id = entry.project_scope_id
      join public.v1_accounts_baseline_stage_allocations stage
        on stage.id = entry.stage_allocation_id
      left join public.v1_profiles suggested
        on suggested.auth_user_id = entry.suggested_by_auth_user_id
      left join public.v1_profiles confirmed
        on confirmed.auth_user_id = entry.confirmed_by_auth_user_id
      left join public.v1_profiles reviewed
        on reviewed.auth_user_id = entry.reviewed_by_auth_user_id
      where entry.project_id = p_project_id;

    when 'progress_history' then
      v_columns := '["Building","Stage","Revision","Action","Previous Suggested %","New Suggested %","Previous Confirmed %","New Confirmed %","Previous Review","New Review","Evidence","Evidence Files","Reason","Actor","Role","Occurred At"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        scope.name,
        stage.stage_name,
        revision.revision_number::text,
        revision.action,
        revision.previous_suggested_percent::text,
        revision.new_suggested_percent::text,
        revision.previous_confirmed_percent::text,
        revision.new_confirmed_percent::text,
        revision.previous_review_status,
        revision.new_review_status,
        coalesce(revision.evidence_summary, ''),
        cardinality(revision.evidence_document_ids)::text,
        revision.reason,
        public.v1_safe_profile_display_name(
          actor.display_name, actor.auth_user_id
        ),
        revision.actor_exact_role,
        revision.occurred_at::text
      ) order by revision.occurred_at desc, revision.id desc), '[]'::jsonb)
      into v_rows
      from public.v1_accounts_billing_progress_revisions revision
      join public.v1_accounts_billing_progress progress
        on progress.id = revision.progress_entry_id
      join public.v1_project_scopes scope
        on scope.id = progress.project_scope_id
      join public.v1_accounts_baseline_stage_allocations stage
        on stage.id = progress.stage_allocation_id
      join public.v1_profiles actor
        on actor.auth_user_id = revision.actor_auth_user_id
      where revision.project_id = p_project_id;

    when 'client_claims' then
      v_columns := '["Claim","Status","Period Start","Period End","Baseline Revision","Claimed Amount","Line Count","Stale","Stale Reason","Notes","Created By","Created Role","Created At","Ready For Accounts At","Cancelled At","Cancellation Reason","Version"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        claim.claim_reference,
        claim.status,
        claim.claim_period_start::text,
        claim.claim_period_end::text,
        baseline.revision_number::text,
        coalesce(lines.amount, 0)::text,
        coalesce(lines.line_count, 0)::text,
        claim.is_stale::text,
        coalesce(claim.stale_reason, ''),
        coalesce(claim.notes, ''),
        public.v1_safe_profile_display_name(
          creator.display_name, creator.auth_user_id
        ),
        claim.created_by_exact_role,
        claim.created_at::text,
        coalesce(claim.ready_for_accounts_at::text, ''),
        coalesce(claim.cancelled_at::text, ''),
        coalesce(claim.cancellation_reason, ''),
        claim.record_version::text
      ) order by claim.updated_at desc, claim.id desc), '[]'::jsonb)
      into v_rows
      from public.v1_accounts_client_claims claim
      join public.v1_accounts_baseline_revisions baseline
        on baseline.id = claim.baseline_revision_id
      join public.v1_profiles creator
        on creator.auth_user_id = claim.created_by_auth_user_id
      left join lateral (
        select sum(line.claimed_amount) amount, count(*) line_count
        from public.v1_accounts_client_claim_lines line
        where line.claim_id = claim.id
      ) lines on true
      where claim.project_id = p_project_id;

    when 'claim_lines' then
      v_columns := '["Claim","Claim Status","Building","Stage","Stage Value","Confirmed %","Eligible Amount","Previously Claimed","This Claim","Evidence Reference","Progress Revision","Progress Version","Created At"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        claim.claim_reference,
        claim.status,
        scope.name,
        stage.stage_name,
        line.stage_value_snapshot::text,
        line.confirmed_percent_snapshot::text,
        line.eligible_amount_snapshot::text,
        line.previously_claimed_amount_snapshot::text,
        line.claimed_amount::text,
        coalesce(line.evidence_reference, ''),
        progress_revision.revision_number::text,
        line.progress_record_version::text,
        line.created_at::text
      ) order by claim.claim_reference, scope.scope_code, stage.display_order), '[]'::jsonb)
      into v_rows
      from public.v1_accounts_client_claim_lines line
      join public.v1_accounts_client_claims claim on claim.id = line.claim_id
      join public.v1_project_scopes scope on scope.id = line.project_scope_id
      join public.v1_accounts_baseline_stage_allocations stage
        on stage.baseline_revision_id = line.baseline_revision_id
        and stage.stage_key = line.stage_key
      join public.v1_accounts_billing_progress_revisions progress_revision
        on progress_revision.id = line.progress_revision_id
      where line.project_id = p_project_id;

    when 'client_invoices' then
      v_columns := '["Invoice","Claim","Status","Claimed ex VAT","VAT %","VAT Amount","Total incl VAT","Certified incl VAT","Paid","Still Due","Payment Terms Days","Reminder Lead Days","Submitted","Due","Returned At","Return Reason","Cancelled At","Cancellation Reason","Notes","Created By","Created At","Updated At","Version"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        invoice.invoice_reference,
        claim.claim_reference,
        invoice.status,
        invoice.claimed_ex_vat::text,
        invoice.vat_rate_percent_snapshot::text,
        invoice.vat_amount_snapshot::text,
        invoice.total_incl_vat_snapshot::text,
        public.v1_accounts_invoice_certified_incl_vat(invoice.id)::text,
        public.v1_accounts_invoice_paid_amount(invoice.id)::text,
        greatest(
          public.v1_accounts_invoice_certified_incl_vat(invoice.id)
          - public.v1_accounts_invoice_retention(invoice.id)
          - public.v1_accounts_invoice_paid_amount(invoice.id), 0
        )::text,
        invoice.payment_terms_days_snapshot::text,
        invoice.reminder_lead_days_snapshot::text,
        coalesce(invoice.submission_date::text, ''),
        coalesce(invoice.due_date::text, ''),
        coalesce(invoice.returned_at::text, ''),
        coalesce(invoice.return_reason, ''),
        coalesce(invoice.cancelled_at::text, ''),
        coalesce(invoice.cancellation_reason, ''),
        coalesce(invoice.notes, ''),
        public.v1_safe_profile_display_name(
          creator.display_name, creator.auth_user_id
        ),
        invoice.created_at::text,
        invoice.updated_at::text,
        invoice.record_version::text
      ) order by invoice.updated_at desc, invoice.id desc), '[]'::jsonb)
      into v_rows
      from public.v1_accounts_client_invoices invoice
      join public.v1_accounts_client_claims claim on claim.id = invoice.claim_id
      join public.v1_profiles creator
        on creator.auth_user_id = invoice.created_by_auth_user_id
      where invoice.project_id = p_project_id;

    when 'certifications' then
      v_columns := '["Certification","Invoice","Revision","Certification Date","Certified ex VAT","Certified VAT","Certified incl VAT","Difference Reason","Actor","Role","Created At"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        certification.certification_reference,
        invoice.invoice_reference,
        certification.revision_number::text,
        certification.certification_date::text,
        certification.certified_ex_vat::text,
        certification.certified_vat::text,
        certification.certified_incl_vat::text,
        coalesce(certification.difference_reason, ''),
        public.v1_safe_profile_display_name(
          actor.display_name, actor.auth_user_id
        ),
        certification.actor_exact_role,
        certification.created_at::text
      ) order by certification.certification_date desc,
          certification.created_at desc, certification.id desc), '[]'::jsonb)
      into v_rows
      from public.v1_accounts_client_certifications certification
      join public.v1_accounts_client_invoices invoice
        on invoice.id = certification.invoice_id
      join public.v1_profiles actor
        on actor.auth_user_id = certification.actor_auth_user_id
      where certification.project_id = p_project_id;

    when 'client_receipts' then
      v_columns := '["Payment Reference","Invoice","Entry Kind","Original Reference","PDC Cheque","Payment Date","Payment Method","Amount","Reason","Actor","Role","Created At"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        payment.payment_reference,
        invoice.invoice_reference,
        payment.entry_kind,
        coalesce(original.payment_reference, ''),
        coalesce(pdc.cheque_number, ''),
        payment.payment_date::text,
        payment.payment_method,
        payment.amount::text,
        coalesce(payment.reason, ''),
        public.v1_safe_profile_display_name(
          actor.display_name, actor.auth_user_id
        ),
        payment.actor_exact_role,
        payment.created_at::text
      ) order by payment.payment_date desc, payment.created_at desc,
          payment.id desc), '[]'::jsonb)
      into v_rows
      from public.v1_accounts_client_payments payment
      join public.v1_accounts_client_invoices invoice
        on invoice.id = payment.invoice_id
      left join public.v1_accounts_client_payments original
        on original.id = payment.original_payment_id
      left join public.v1_accounts_client_pdcs pdc on pdc.id = payment.pdc_id
      join public.v1_profiles actor
        on actor.auth_user_id = payment.actor_auth_user_id
      where payment.project_id = p_project_id;

    when 'pdc_register' then
      v_columns := '["Cheque","Invoice","Bank","Cheque Date","Received Date","Amount","Status","Replaces Cheque","Replaced By Cheque","Action Required","Last Action Reason","Created By","Created Role","Created At","Updated At","Version"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        pdc.cheque_number,
        invoice.invoice_reference,
        coalesce(pdc.bank_name, ''),
        pdc.cheque_date::text,
        coalesce(pdc.received_date::text, ''),
        pdc.amount::text,
        pdc.status,
        coalesce(replaces.cheque_number, ''),
        coalesce(replaced_by.cheque_number, ''),
        pdc.action_required::text,
        coalesce(pdc.last_action_reason, ''),
        public.v1_safe_profile_display_name(
          creator.display_name, creator.auth_user_id
        ),
        pdc.created_by_exact_role,
        pdc.created_at::text,
        pdc.updated_at::text,
        pdc.record_version::text
      ) order by pdc.cheque_date, pdc.id), '[]'::jsonb)
      into v_rows
      from public.v1_accounts_client_pdcs pdc
      join public.v1_accounts_client_invoices invoice
        on invoice.id = pdc.invoice_id
      left join public.v1_accounts_client_pdcs replaces
        on replaces.id = pdc.replaces_pdc_id
      left join public.v1_accounts_client_pdcs replaced_by
        on replaced_by.id = pdc.replaced_by_pdc_id
      join public.v1_profiles creator
        on creator.auth_user_id = pdc.created_by_auth_user_id
      where pdc.project_id = p_project_id;

    when 'pdc_events' then
      v_columns := '["Cheque","Invoice","Sequence","From Status","To Status","Action Date","Linked Receipt","Reason","Actor","Role","Occurred At"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        pdc.cheque_number,
        invoice.invoice_reference,
        event.sequence_number::text,
        coalesce(event.from_status, ''),
        event.to_status,
        event.action_date::text,
        coalesce(payment.payment_reference, ''),
        coalesce(event.reason, ''),
        public.v1_safe_profile_display_name(
          actor.display_name, actor.auth_user_id
        ),
        event.actor_exact_role,
        event.occurred_at::text
      ) order by event.occurred_at desc, event.id desc), '[]'::jsonb)
      into v_rows
      from public.v1_accounts_client_pdc_events event
      join public.v1_accounts_client_pdcs pdc on pdc.id = event.pdc_id
      join public.v1_accounts_client_invoices invoice
        on invoice.id = event.invoice_id
      left join public.v1_accounts_client_payments payment
        on payment.id = event.linked_payment_id
      join public.v1_profiles actor
        on actor.auth_user_id = event.actor_auth_user_id
      where event.project_id = p_project_id;

    when 'supplier_bills' then
      v_columns := '["Supplier Invoice","Supplier","Bill Status","Match Status","Payment Status","PO/LPO","Invoice Date","Due Date","Ex VAT","VAT %","VAT Amount","Total incl VAT","Paid","Outstanding","Delivery Reference","Mismatch Reason","Admin Approval Reason","Notes","Approved At","Approved By","Cancelled At","Cancellation Reason","Created By","Created Role","Created At","Updated At","Version"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        bill.supplier_invoice_reference,
        bill.supplier_name_snapshot,
        bill.status,
        public.v1_accounts_supplier_match_status(bill.id),
        public.v1_accounts_supplier_payment_status(bill.id),
        coalesce(bill.po_lpo_reference, ''),
        bill.invoice_date::text,
        bill.due_date::text,
        bill.ex_vat_amount::text,
        bill.vat_rate_percent::text,
        bill.vat_amount::text,
        bill.total_incl_vat::text,
        public.v1_accounts_supplier_paid_amount(bill.id)::text,
        greatest(
          bill.total_incl_vat
          - public.v1_accounts_supplier_paid_amount(bill.id), 0
        )::text,
        coalesce(bill.accepted_delivery_reference, ''),
        coalesce(bill.explicit_mismatch_reason, ''),
        coalesce(bill.approval_admin_exception_reason, ''),
        coalesce(bill.notes, ''),
        coalesce(bill.approved_at::text, ''),
        case when approver.auth_user_id is null then '' else
          public.v1_safe_profile_display_name(
            approver.display_name, approver.auth_user_id
          ) end,
        coalesce(bill.cancelled_at::text, ''),
        coalesce(bill.cancellation_reason, ''),
        public.v1_safe_profile_display_name(
          creator.display_name, creator.auth_user_id
        ),
        bill.created_by_exact_role,
        bill.created_at::text,
        bill.updated_at::text,
        bill.record_version::text
      ) order by bill.updated_at desc, bill.id desc), '[]'::jsonb)
      into v_rows
      from public.v1_accounts_supplier_bills bill
      join public.v1_profiles creator
        on creator.auth_user_id = bill.created_by_auth_user_id
      left join public.v1_profiles approver
        on approver.auth_user_id = bill.approved_by_auth_user_id
      where bill.project_id = p_project_id;

    when 'supplier_payments' then
      v_columns := '["Payment Reference","Supplier Invoice","Supplier","Entry Kind","Original Reference","Payment Date","Payment Method","Amount","Reason","Admin Exception Reason","Actor","Role","Created At"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        payment.payment_reference,
        bill.supplier_invoice_reference,
        bill.supplier_name_snapshot,
        payment.entry_kind,
        coalesce(original.payment_reference, ''),
        payment.payment_date::text,
        payment.payment_method,
        payment.amount::text,
        coalesce(payment.reason, ''),
        coalesce(payment.admin_exception_reason, ''),
        public.v1_safe_profile_display_name(
          actor.display_name, actor.auth_user_id
        ),
        payment.actor_exact_role,
        payment.created_at::text
      ) order by payment.payment_date desc, payment.created_at desc,
          payment.id desc), '[]'::jsonb)
      into v_rows
      from public.v1_accounts_supplier_payments payment
      join public.v1_accounts_supplier_bills bill
        on bill.id = payment.supplier_bill_id
      left join public.v1_accounts_supplier_payments original
        on original.id = payment.original_payment_id
      join public.v1_profiles actor
        on actor.auth_user_id = payment.actor_auth_user_id
      where payment.project_id = p_project_id;

    when 'accounts_documents' then
      v_columns := '["Document Type","File Name","Classification","Revision","MIME Type","Size Bytes","SHA256","Origin","Source Entity Type","Source Entity ID","Linked Records","Archived","Created At","Uploaded At","Uploaded By","Uploaded Role"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        metadata.document_type,
        version_record.original_file_name,
        document_record.classification,
        version_record.revision_number::text,
        version_record.mime_type,
        version_record.byte_size::text,
        version_record.sha256,
        version_record.origin,
        coalesce(version_record.source_entity_type, ''),
        coalesce(version_record.source_entity_id::text, ''),
        coalesce(links.targets, ''),
        (metadata.archived_at is not null)::text,
        document_record.created_at::text,
        version_record.uploaded_at::text,
        public.v1_safe_profile_display_name(
          uploader.display_name, uploader.auth_user_id
        ),
        version_record.uploaded_by_role
      ) order by version_record.uploaded_at desc, document_record.id), '[]'::jsonb)
      into v_rows
      from public.v1_accounts_document_metadata metadata
      join public.v1_documents document_record
        on document_record.id = metadata.document_id
      join public.v1_document_versions version_record
        on version_record.document_id = document_record.id
      join public.v1_profiles uploader
        on uploader.auth_user_id = version_record.uploaded_by_auth_user_id
      left join lateral (
        select string_agg(
          link.entity_type || ':' || link.entity_id::text, ', '
          order by link.linked_at, link.id
        ) targets
        from public.v1_document_links link
        where link.document_id = document_record.id
          and link.project_id = p_project_id
          and link.removed_at is null
      ) links on true
      where exists (
        select 1
        from public.v1_document_links project_link
        where project_link.document_id = document_record.id
          and project_link.project_id = p_project_id
          and project_link.removed_at is null
      ) and public.v1_document_readable(document_record.id);

    when 'accounts_activity' then
      v_columns := '["Occurred At","Event","Entity Type","Entity ID","Actor","Role","Reason","Idempotency Key","Before","After"]'::jsonb;
      select coalesce(jsonb_agg(jsonb_build_array(
        audit.occurred_at::text,
        audit.event_type,
        audit.entity_type,
        audit.entity_id::text,
        public.v1_safe_profile_display_name(
          actor.display_name, actor.auth_user_id
        ),
        coalesce(audit.actor_exact_role, audit.actor_role),
        coalesce(audit.reason, ''),
        coalesce(audit.idempotency_key::text, ''),
        coalesce(audit.before_data::text, ''),
        coalesce(audit.after_data::text, '')
      ) order by audit.occurred_at desc, audit.id desc), '[]'::jsonb)
      into v_rows
      from public.v1_audit_events audit
      join public.v1_profiles actor
        on actor.auth_user_id = audit.actor_auth_user_id
      where audit.project_id = p_project_id
        and (
          audit.event_type like 'accounts.%'
          or audit.entity_type like 'accounts_%'
        );
  end case;

  v_result := jsonb_build_object(
    'schema_version', 7,
    'report_kind', p_export_kind,
    'project_id', p_project_id,
    'project_reference', v_project.project_ref,
    'project_name', v_project.name,
    'currency', 'AED',
    'access_context', v_role,
    'generated_at', clock_timestamp(),
    'generated_by_auth_user_id', v_actor,
    'generated_by_display_name', (
      select public.v1_safe_profile_display_name(
        profile.display_name, profile.auth_user_id
      )
      from public.v1_profiles profile
      where profile.auth_user_id = v_actor
    ),
    'columns', v_columns,
    'rows', coalesce(v_rows, '[]'::jsonb)
  );

  perform public.v1_write_audit_event(
    'accounts.export.generated',
    'accounts_export',
    p_idempotency_key,
    p_project_id,
    null,
    jsonb_build_object(
      'report_kind', p_export_kind,
      'row_count', jsonb_array_length(coalesce(v_rows, '[]'::jsonb))
    ),
    null,
    p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_get_accounts_export', p_idempotency_key, v_result
  );
  return v_result;
end;
$$;


-- #############################################################################
-- FILE 20 / 22 : 20261106210000_accounts_v2_p6_claim_retention_preview.sql
-- #############################################################################

-- R39 Accounts Workspace V2 — P6 (part g): claim side-panel retention preview
--
-- Section 28 R-4/R-5 surfaces the retention hold-back on issued invoices. While
-- a claim is still being drafted no invoice exists yet, so the claim side panel
-- shows a *preview* of the retention that would be withheld — and the resulting
-- net-after-retention payable — using the profile's CURRENT retention percent.
-- The preview uses the same formula the issue freeze uses
-- (round(claim gross ex-VAT * retention% / 100, 2), §28 R-1), so the previewed
-- figure equals the retention that will later be frozen onto the invoice.
--
-- This CREATE OR REPLACE of v1_get_claim_workbench is a copy of the canonical
-- part-c body (20261106150000_accounts_v2_p3_claim_payable.sql) PLUS three
-- additive keys on the claim object: retention_percent, retention_preview and
-- net_payable_after_retention. Keep this body in sync with the part-c migration
-- if its claim-payable block ever changes.
--
-- Additive and accounts-only. The new figures are monetary / commercial, so they
-- are added only with view_project_commercial_values (AT-SEC-001/008); every
-- other key the prior version returned is returned unchanged. No table, row or
-- status change. Retention rounds once to fils at the baseline currency scale.

create or replace function public.v1_get_claim_workbench(
  p_project_id uuid,
  p_claim_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_can_values boolean;
  v_profile public.v1_accounts_project_commercial_profiles%rowtype;
  v_baseline public.v1_accounts_baseline_revisions%rowtype;
  v_cells jsonb := '[]'::jsonb;
  v_claim jsonb := null;
  v_claim_id uuid;
  v_claim_gross numeric := 0;
  v_claim_vat numeric := 0;
  v_claim_retention numeric := 0;
begin
  perform public.v1_accounts_require_capability(p_project_id, 'view_project_accounts');
  v_can_values := public.v1_current_user_has_capability(
    'view_project_commercial_values', p_project_id
  );

  select * into v_profile
  from public.v1_accounts_project_commercial_profiles where project_id = p_project_id;
  if not found or v_profile.current_baseline_revision_id is null then
    return jsonb_build_object(
      'schema_version', 1, 'project_id', p_project_id,
      'baseline_revision_id', null, 'cells', '[]'::jsonb, 'claim', null,
      'capabilities', public.v1_accounts_capability_envelope(p_project_id),
      'commands', public.v1_accounts_receivables_commands(p_project_id)
    );
  end if;
  select * into v_baseline
  from public.v1_accounts_baseline_revisions where id = v_profile.current_baseline_revision_id;

  select coalesce(jsonb_agg(cell order by ord, bname), '[]'::jsonb) into v_cells
  from (
    select sa.display_order as ord, scope.name as bname,
      jsonb_build_object(
        'progress_entry_id', bp.id,
        'building_scope_id', bp.project_scope_id,
        'building_name', scope.name,
        'stage_key', bp.stage_key,
        'stage_label', sa.stage_name,
        'stage_position', sa.display_order,
        'measurement_mode', sa.measurement_mode,
        'confirmed_percent', bp.confirmed_percent::text,
        'review_status', bp.review_status,
        'record_version', bp.record_version
      )
      || case when v_can_values then jsonb_build_object(
          'stage_value', public.v1_accounts_stage_value(bp.id)::text,
          'eligible', public.v1_accounts_progress_eligible_amount(bp.id)::text,
          'claimed', public.v1_accounts_dimension_claimed_amount(
            bp.project_id, bp.project_scope_id, bp.stage_key, null)::text,
          'available', greatest(
            public.v1_accounts_progress_eligible_amount(bp.id)
              - public.v1_accounts_dimension_claimed_amount(
                  bp.project_id, bp.project_scope_id, bp.stage_key, null), 0)::text,
          'over_claimed', public.v1_accounts_dimension_claimed_amount(
              bp.project_id, bp.project_scope_id, bp.stage_key, null)
            > public.v1_accounts_progress_eligible_amount(bp.id)
        ) else '{}'::jsonb end
      || case when sa.measurement_mode = 'items' then jsonb_build_object('items', (
          select coalesce(jsonb_agg(
            jsonb_build_object(
              'stage_item_id', si.id, 'item_key', si.item_key,
              'item_label', si.item_label, 'display_order', si.display_order,
              'quantity', si.quantity::text, 'unit_code', si.unit_code,
              'confirmed_qty', coalesce(ip.confirmed_qty, 0)::text,
              'needs_review', coalesce(ip.needs_review, false)
            )
            || case when v_can_values then jsonb_build_object(
                'item_value', public.v1_accounts_stage_item_value(si.id)::text)
              else '{}'::jsonb end
            order by si.display_order), '[]'::jsonb)
          from public.v1_accounts_baseline_stage_items si
          left join public.v1_accounts_billing_item_progress ip
            on ip.stage_item_id = si.id and ip.progress_entry_id = bp.id
          where si.baseline_revision_id = v_baseline.id
            and si.project_scope_id = bp.project_scope_id
            and si.stage_key = bp.stage_key
        )) else '{}'::jsonb end
      as cell
    from public.v1_accounts_billing_progress bp
    join public.v1_accounts_baseline_stage_allocations sa
      on sa.baseline_revision_id = bp.baseline_revision_id and sa.stage_key = bp.stage_key
    join public.v1_project_scopes scope on scope.id = bp.project_scope_id
    where bp.baseline_revision_id = v_baseline.id
  ) rows;

  select id into v_claim_id
  from public.v1_accounts_client_claims
  where project_id = p_project_id
    and (
      (p_claim_id is not null and id = p_claim_id)
      or (p_claim_id is null and status in ('draft', 'ready_for_accounts'))
    )
  order by (status = 'draft') desc, updated_at desc
  limit 1;
  if v_claim_id is not null then
    v_claim := public.v1_accounts_claim_snapshot(v_claim_id);
    -- Payable figures: gross (ex VAT) + VAT at the baseline rate = net payable
    -- (incl VAT), plus this claim's share of the contract. Commercial only.
    if v_can_values then
      v_claim_gross := coalesce((select sum(claimed_amount)
        from public.v1_accounts_client_claim_lines where claim_id = v_claim_id), 0);
      v_claim_vat := round(v_claim_gross * coalesce(v_baseline.vat_rate_percent, 0) / 100, 2);
      -- §28 R-1 preview: retention the profile would currently withhold on this
      -- claim's gross ex-VAT, and the net payable once it is held back.
      v_claim_retention := round(
        v_claim_gross * coalesce(v_profile.retention_percent, 0) / 100, 2);
      v_claim := v_claim || jsonb_build_object(
        'vat_amount', v_claim_vat::text,
        'net_payable', (v_claim_gross + v_claim_vat)::text,
        'contract_value', v_baseline.contract_value::text,
        'this_claim_percent', case when v_baseline.contract_value > 0
          then round(v_claim_gross / v_baseline.contract_value * 100, 1)
          else 0 end::text,
        'retention_percent', coalesce(v_profile.retention_percent, 0)::text,
        'retention_preview', v_claim_retention::text,
        'net_payable_after_retention',
          (v_claim_gross + v_claim_vat - v_claim_retention)::text);
    end if;
  end if;

  return jsonb_build_object(
    'schema_version', 1, 'project_id', p_project_id,
    'baseline_revision_id', v_baseline.id,
    'baseline_revision_number', v_baseline.revision_number,
    'cells', v_cells, 'claim', v_claim,
    'capabilities', public.v1_accounts_capability_envelope(p_project_id),
    'commands', public.v1_accounts_receivables_commands(p_project_id)
  );
end;
$$;

grant execute on function public.v1_get_claim_workbench(uuid, uuid) to authenticated;
-- =============================================================================

-- #############################################################################
-- FILE 21 / 22 : 20261107100000_accounts_v2_p4_workspace_attention.sql
-- #############################################################################

-- R39 Accounts Workspace V2 — P4: what the workspace says needs attention
--
-- Three things the live walkthrough showed were wrong:
--   * a claim checked and waiting for its invoice was ignored, so the workspace
--     said "No claim is in progress" with one ready;
--   * an unchecked draft was already announced as "ready to invoice";
--   * an Accountant, who cannot start a claim, was told to start one.
-- `claim_ready` now means checked, the new `claim_draft` means waiting to be
-- checked, and `claim_empty` / `no_claim` go only to those who can act on them.
--
-- Additive: CREATE OR REPLACE of the read projection only. No table or row
-- changes. Rollback: re-apply the function from
-- 20261106200000_accounts_v2_p6_retention_payable.sql.

create or replace function public.v1_get_project_accounts_workspace(
  p_project_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_can_view boolean;
  v_can_values boolean;
  v_can_supplier boolean;
  v_project public.v1_projects%rowtype;
  v_profile public.v1_accounts_project_commercial_profiles%rowtype;
  v_baseline public.v1_accounts_baseline_revisions%rowtype;
  v_contract numeric(20,2) := 0;
  v_vatf numeric := 1;
  v_invoiced numeric := 0;
  v_received numeric := 0;
  v_certified numeric := 0;
  v_pdc numeric := 0;
  v_still_due numeric := 0;
  v_draft numeric := 0;
  v_bills_total numeric := 0;
  v_bills_paid numeric := 0;
  v_bills_open numeric := 0;
  v_bills_overdue integer := 0;
  v_open_claim_id uuid;
  v_open_claim_ref text;
  v_open_claim_gross numeric := 0;
  v_open_claim_status text;
  v_can_prepare boolean := false;
  v_building_count integer := 0;
  v_stage_count integer := 0;
  v_invoice_count integer := 0;
  v_latest_invoice_ref text;
  v_progress_any boolean := false;
  v_invoice_any boolean := false;
  v_paid_ex numeric := 0;
  v_setup_state text;
  v_progress_state text;
  v_invoice_state text;
  v_paid_state text;
  v_steps jsonb;
  v_heatmap jsonb := '[]'::jsonb;
  v_attention jsonb := '[]'::jsonb;
  v_result jsonb;
begin
  if auth.uid() is null or p_project_id is null or not public.v1_current_actor_is_active() then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501'; end if;
  v_can_view := public.v1_current_user_has_capability('view_project_accounts', p_project_id);
  v_can_values := public.v1_current_user_has_capability('view_project_commercial_values', p_project_id);
  v_can_supplier := public.v1_current_user_has_capability('view_supplier_costs', p_project_id);
  v_can_prepare := public.v1_current_user_has_capability('prepare_client_claim', p_project_id);
  if not v_can_view and not v_can_supplier then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501'; end if;
  select * into v_project from public.v1_projects where id = p_project_id;
  if not found then raise exception 'R39_ACCOUNTS_PROJECT_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into v_profile from public.v1_accounts_project_commercial_profiles where project_id = p_project_id;
  if found and v_profile.current_baseline_revision_id is not null then
    select * into v_baseline from public.v1_accounts_baseline_revisions where id = v_profile.current_baseline_revision_id;
    v_contract := coalesce(v_baseline.contract_value, 0);
    v_vatf := 1 + coalesce(v_baseline.vat_rate_percent, 0) / 100;
    v_progress_any := exists (select 1 from public.v1_accounts_billing_progress
      where baseline_revision_id = v_baseline.id and confirmed_percent > 0);
    select count(distinct project_scope_id), count(distinct stage_key)
      into v_building_count, v_stage_count
    from public.v1_accounts_billing_progress where baseline_revision_id = v_baseline.id;
  end if;

  select coalesce(sum(case when i.status not in ('draft','returned','cancelled') then i.claimed_ex_vat else 0 end), 0),
         coalesce(sum(case when i.status <> 'cancelled' then public.v1_accounts_invoice_paid_amount(i.id) else 0 end), 0),
         coalesce(sum(case when i.status <> 'cancelled' then public.v1_accounts_invoice_certified_incl_vat(i.id) else 0 end), 0),
         coalesce(sum(case when i.status <> 'cancelled' then public.v1_accounts_invoice_pdc_exposure(i.id) else 0 end), 0),
         greatest(coalesce(sum(case when i.status <> 'cancelled'
           then public.v1_accounts_invoice_certified_incl_vat(i.id) - i.retention_snapshot - public.v1_accounts_invoice_paid_amount(i.id)
           else 0 end), 0), 0),
         bool_or(i.status not in ('draft','cancelled')),
         count(*) filter (where i.status not in ('draft','cancelled'))
    into v_invoiced, v_received, v_certified, v_pdc, v_still_due, v_invoice_any, v_invoice_count
  from public.v1_accounts_client_invoices i where i.project_id = p_project_id;
  v_invoice_any := coalesce(v_invoice_any, false);
  v_invoice_count := coalesce(v_invoice_count, 0);

  select i.invoice_reference into v_latest_invoice_ref
  from public.v1_accounts_client_invoices i
  where i.project_id = p_project_id and i.status not in ('draft','cancelled')
  order by i.created_at desc limit 1;

  select coalesce(sum(l.claimed_amount), 0) into v_draft
  from public.v1_accounts_client_claim_lines l
  join public.v1_accounts_client_claims c on c.id = l.claim_id
  where c.project_id = p_project_id and c.status in ('draft', 'ready_for_accounts');

  -- The claim in hand: a checked claim waiting for its invoice comes first.
  select c.id, c.claim_reference, c.status,
         coalesce((select sum(l.claimed_amount) from public.v1_accounts_client_claim_lines l where l.claim_id = c.id), 0)
    into v_open_claim_id, v_open_claim_ref, v_open_claim_status, v_open_claim_gross
  from public.v1_accounts_client_claims c
  where c.project_id = p_project_id and c.status in ('draft', 'ready_for_accounts')
  order by (c.status = 'ready_for_accounts') desc, c.updated_at desc limit 1;

  if v_can_supplier then
    select coalesce(sum(case when b.status <> 'cancelled' then b.total_incl_vat else 0 end), 0),
           coalesce(sum(case when b.status <> 'cancelled' then public.v1_accounts_supplier_paid_amount(b.id) else 0 end), 0),
           coalesce(sum(case when b.status <> 'cancelled' then greatest(b.total_incl_vat - public.v1_accounts_supplier_paid_amount(b.id), 0) else 0 end), 0),
           count(*) filter (where b.status <> 'cancelled' and b.due_date < current_date
             and public.v1_accounts_supplier_paid_amount(b.id) < b.total_incl_vat)
      into v_bills_total, v_bills_paid, v_bills_open, v_bills_overdue
    from public.v1_accounts_supplier_bills b where b.project_id = p_project_id;
  end if;

  v_paid_ex := round(least(v_received / v_vatf, v_invoiced), 2);

  -- Heatmap: invoiced % per current building x stage cell.
  if v_can_view and v_can_values and v_baseline.id is not null then
    select coalesce(jsonb_agg(cell order by ord, bname), '[]'::jsonb) into v_heatmap from (
      select sa.display_order as ord, scope.name as bname,
        jsonb_build_object('building_scope_id', bp.project_scope_id, 'building_name', scope.name,
          'stage_key', bp.stage_key, 'stage_label', sa.stage_name,
          'stage_value', public.v1_accounts_stage_value(bp.id)::text,
          'invoiced_amount', inv.amount::text,
          'invoiced_percent', case when public.v1_accounts_stage_value(bp.id) > 0
            then round(inv.amount / public.v1_accounts_stage_value(bp.id) * 100, 1) else 0 end::text) as cell
      from public.v1_accounts_billing_progress bp
      join public.v1_accounts_baseline_stage_allocations sa
        on sa.baseline_revision_id = bp.baseline_revision_id and sa.stage_key = bp.stage_key
      join public.v1_project_scopes scope on scope.id = bp.project_scope_id
      left join lateral (
        select coalesce(sum(l.claimed_amount), 0) as amount
        from public.v1_accounts_client_claim_lines l
        join public.v1_accounts_client_claims c on c.id = l.claim_id
        where c.project_id = p_project_id and c.status = 'invoiced'
          and l.project_scope_id = bp.project_scope_id and l.stage_key = bp.stage_key
      ) inv on true
      where bp.baseline_revision_id = v_baseline.id
    ) cells;
  end if;

  -- Attention (server-derived).
  if v_baseline.id is null then
    v_attention := v_attention || jsonb_build_array(jsonb_build_object(
      'severity', 'bad', 'kind', 'setup_incomplete', 'action_key', 'open_contract',
      'target_type', 'project', 'target_id', p_project_id));
  elsif v_can_values then
    v_attention := v_attention || coalesce((select jsonb_agg(jsonb_build_object(
        'severity', 'bad', 'kind', 'invoice_overdue', 'action_key', 'open_invoice',
        'target_type', 'invoice', 'target_id', i.id))
      from public.v1_accounts_client_invoices i where i.project_id = p_project_id
        and i.status not in ('draft','returned','cancelled','paid') and i.due_date < current_date), '[]'::jsonb);
    v_attention := v_attention || coalesce((select jsonb_agg(jsonb_build_object(
        'severity', 'pri', 'kind', 'awaiting_certification', 'action_key', 'certify',
        'target_type', 'invoice', 'target_id', i.id))
      from public.v1_accounts_client_invoices i where i.project_id = p_project_id and i.status = 'submitted'
        and not exists (select 1 from public.v1_accounts_client_certifications c where c.invoice_id = i.id)), '[]'::jsonb);
    if v_open_claim_status = 'ready_for_accounts' then
      v_attention := v_attention || jsonb_build_array(jsonb_build_object('severity','ok','kind','claim_ready',
        'action_key','open_claim','target_type','claim','target_id',v_open_claim_id));
    elsif v_open_claim_id is not null and v_open_claim_gross > 0 then
      v_attention := v_attention || jsonb_build_array(jsonb_build_object('severity','pri','kind','claim_draft',
        'action_key','open_claim','target_type','claim','target_id',v_open_claim_id));
    elsif v_open_claim_id is not null and v_can_prepare then
      v_attention := v_attention || jsonb_build_array(jsonb_build_object('severity','pri','kind','claim_empty',
        'action_key','open_claim','target_type','claim','target_id',v_open_claim_id));
    elsif v_open_claim_id is null and v_contract > v_invoiced and v_can_prepare then
      -- Only someone who can start a claim is asked to start one.
      v_attention := v_attention || jsonb_build_array(jsonb_build_object('severity','pri','kind','no_claim',
        'action_key','start_claim','target_type','project','target_id',p_project_id));
    end if;
    if v_pdc > 0 then
      v_attention := v_attention || jsonb_build_array(jsonb_build_object('severity','pri','kind','cheques_in_hand',
        'action_key','open_invoices','target_type','project','target_id',p_project_id));
    end if;
  end if;
  if v_can_supplier and v_bills_overdue > 0 then
    v_attention := v_attention || jsonb_build_array(jsonb_build_object('severity','warn','kind','supplier_overdue',
      'action_key','open_supplier_bills','target_type','project','target_id',p_project_id,
      'params', jsonb_build_object('count', v_bills_overdue)));
  end if;

  v_setup_state := case when v_baseline.id is not null then 'done' else 'current' end;
  v_progress_state := case when v_progress_any then 'done' when v_baseline.id is not null then 'current' else '' end;
  v_invoice_state := case when v_invoice_any then 'done' when v_progress_any then 'current' else '' end;
  v_paid_state := case when v_received > 0 and v_still_due <= 0 and v_invoice_any then 'done' when v_invoice_any then 'current' else '' end;

  -- Steps. Monetary figures (`detail`) only with commercial access; the
  -- state/label shape is identical for every actor.
  if v_can_values then
    v_steps := jsonb_build_array(
      jsonb_build_object('key','setup','state',v_setup_state,'detail',
        jsonb_build_object('contract_value', v_contract::text,
          'building_count', v_building_count, 'stage_count', v_stage_count)),
      jsonb_build_object('key','progress','state',v_progress_state,'detail',
        case when v_open_claim_id is not null
          then jsonb_build_object('claim_reference', v_open_claim_ref, 'claim_gross', v_open_claim_gross::text)
          else null end),
      jsonb_build_object('key','invoice','state',v_invoice_state,'detail',
        case when v_invoice_count > 0
          then jsonb_build_object('issued_count', v_invoice_count, 'latest_reference', v_latest_invoice_ref)
          else null end),
      jsonb_build_object('key','paid','state',v_paid_state,'detail',
        jsonb_build_object('received', v_received::text,
          'to_come', greatest(round(v_contract * v_vatf, 2) - v_received, 0)::text)));
  else
    v_steps := jsonb_build_array(
      jsonb_build_object('key','setup','state',v_setup_state),
      jsonb_build_object('key','progress','state',v_progress_state),
      jsonb_build_object('key','invoice','state',v_invoice_state),
      jsonb_build_object('key','paid','state',v_paid_state));
  end if;

  v_result := jsonb_build_object(
    'schema_version', 1, 'project_id', v_project.id,
    'project_reference', v_project.project_ref, 'project_name', v_project.name,
    'has_baseline', v_baseline.id is not null,
    'capabilities', jsonb_build_object('view_project_accounts', v_can_view,
      'view_project_commercial_values', v_can_values, 'view_supplier_costs', v_can_supplier),
    'steps', v_steps,
    'badges', jsonb_build_object(
      'claims_draft', v_open_claim_status = 'draft',
      'supplier_count', case when v_can_supplier then v_bills_overdue else null end),
    'attention', v_attention);

  if v_can_values then
    v_result := v_result || jsonb_build_object(
      'money_flow', jsonb_build_object(
        'paid', v_paid_ex::text,
        'invoiced_waiting', greatest(v_invoiced - v_paid_ex, 0)::text,
        'done_not_invoiced', v_draft::text,
        'remaining', greatest(v_contract - v_invoiced - v_draft, 0)::text),
      'kpis', jsonb_build_object(
        'contract_value', v_contract::text,
        'contract_incl_vat', round(v_contract * v_vatf, 2)::text,
        'invoiced', v_invoiced::text,
        'received', v_received::text,
        'certified', v_certified::text,
        'outstanding', v_still_due::text,
        'cheques_in_hand', v_pdc::text,
        'done_not_invoiced', v_draft::text),
      'heatmap', v_heatmap);
  end if;
  if v_can_supplier then
    v_result := v_result || jsonb_build_object(
      'supplier', jsonb_build_object('billed', v_bills_total::text, 'paid', v_bills_paid::text,
        'unpaid', v_bills_open::text, 'overdue_count', v_bills_overdue),
      'cash', jsonb_build_object('received', v_received::text, 'paid_to_suppliers', v_bills_paid::text,
        'net', (v_received - v_bills_paid)::text));
  end if;
  return v_result;
end;
$$;

-- #############################################################################
-- FILE 22 / 22 : 20261107103000_accounts_v2_p5_supplier_delivery_options.sql
-- #############################################################################

-- R39 Accounts Workspace V2 — P5: confirmed deliveries a supplier bill can cite
--
-- A supplier bill's three-way match needs a confirmed receipt review, and the
-- form could only ask for its database ID, which nobody can know. This read lists
-- the ones v1_accounts_supplier_delivery_snapshot would accept, so the form can
-- offer them by delivery reference.
--
-- It returns delivery references, dates and good quantities only, no commercial
-- value, to the same actors who may write a supplier bill draft.
--
-- Additive: one new read function. No table or row changes.
-- Rollback: drop function public.v1_list_supplier_bill_delivery_options(uuid).

create or replace function public.v1_list_supplier_bill_delivery_options(
  p_project_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_exact text;
  v_items jsonb;
begin
  v_exact := public.v1_accounts_require_capability(
    p_project_id, 'manage_supplier_bills'
  );
  if v_exact not in ('procurement', 'accountant', 'admin')
    or not public.v1_current_user_has_capability(
      'view_supplier_costs', p_project_id
    ) then
    raise exception 'R39_ACCOUNTS_ACCESS_DENIED' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(option.snapshot order by option.reviewed_at desc), '[]'::jsonb)
    into v_items
  from (
    select review.reviewed_at,
      public.v1_accounts_supplier_delivery_snapshot(p_project_id, review.id) as snapshot
    from public.v1_receipt_reviews review
    join public.v1_material_dispatches dispatch on dispatch.id = review.dispatch_id
    where dispatch.project_id = p_project_id
      and review.state = 'confirmed'
    order by review.reviewed_at desc
    limit 200
  ) option
  where option.snapshot is not null;

  return jsonb_build_object(
    'schema_version', 1,
    'project_id', p_project_id,
    'deliveries', v_items
  );
end;
$$;

revoke all on function public.v1_list_supplier_bill_delivery_options(uuid)
  from public, anon;
grant execute on function public.v1_list_supplier_bill_delivery_options(uuid)
  to authenticated, service_role;

COMMIT;
-- End of bundle. If COMMIT succeeded, all V2 migrations are applied.
-- Next: run the P1 pre-flight (read-only). Zero rows = safe to enable the flag.
-- =============================================================================
