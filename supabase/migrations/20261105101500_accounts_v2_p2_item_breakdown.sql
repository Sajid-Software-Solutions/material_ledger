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
