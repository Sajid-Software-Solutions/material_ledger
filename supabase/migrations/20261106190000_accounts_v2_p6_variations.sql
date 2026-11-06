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
