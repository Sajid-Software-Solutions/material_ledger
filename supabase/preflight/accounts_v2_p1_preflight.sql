-- R39 Accounts Workspace V2 — P1 production pre-flight (READ-ONLY)
--
-- Run this against PRODUCTION (Supabase SQL editor / service role) BEFORE
-- enabling YORKS_V1_ACCOUNTS_WORKSPACE_V2. It only SELECTs — it changes nothing.
--
-- It looks for any building × stage dimension whose total claimed amount across
-- ALL baseline revisions exceeds the current eligible amount — i.e. a
-- cross-revision over-claim, the one data-integrity risk the P1 single-eligible-
-- source fix addresses. A contract revised DOWN below what was already invoiced
-- would show up here.
--
--   ZERO rows  -> safe to proceed.
--   Any row    -> STOP. Investigate that project/dimension before enabling V2;
--                 do not flip the flag until it is understood/resolved.

with claimed as (
  select cl.project_id, cl.project_scope_id, cl.stage_key,
         sum(cl.claimed_amount) as claimed_all_revisions
  from public.v1_accounts_client_claim_lines cl
  join public.v1_accounts_client_claims c on c.id = cl.claim_id
  where c.status <> 'cancelled'
  group by cl.project_id, cl.project_scope_id, cl.stage_key
),
current_cell as (
  select bp.project_id, bp.project_scope_id, bp.stage_key, bp.id as progress_id
  from public.v1_accounts_billing_progress bp
  join public.v1_accounts_baseline_revisions br on br.id = bp.baseline_revision_id
  where br.status = 'current'
)
select
  claimed.project_id,
  claimed.project_scope_id,
  claimed.stage_key,
  claimed.claimed_all_revisions,
  public.v1_accounts_progress_eligible_amount(current_cell.progress_id)
    as current_eligible,
  claimed.claimed_all_revisions
    - public.v1_accounts_progress_eligible_amount(current_cell.progress_id)
    as over_claimed_by
from claimed
join current_cell
  on current_cell.project_id = claimed.project_id
 and current_cell.project_scope_id = claimed.project_scope_id
 and current_cell.stage_key = claimed.stage_key
-- 0.005 tolerance so fil-level rounding never raises a false positive.
where claimed.claimed_all_revisions
      > public.v1_accounts_progress_eligible_amount(current_cell.progress_id) + 0.005
order by over_claimed_by desc;
