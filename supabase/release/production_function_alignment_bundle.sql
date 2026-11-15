-- Release bundle: align production's public functions with main
-- (docs/yorks-v1/PRODUCTION_FUNCTION_DRIFT_2026-11-15.md).
--
-- A read-only comparison on 15 Nov 2026 of every public function between
-- production (czykuksmlwswjsgotrpo) and a fresh reset of main 849affb found 19
-- that differ. This bundle installs main's exact definitions:
--   * the three 28 Oct 2026 reliability migrations, which were applied to
--     staging only (20261028125701, 20261028131620, 20261028133155);
--   * the return-confirmation rule of 20260803224536, recorded as applied on
--     production on 5 Aug 2026 but never installed there;
--   * the JWT helpers, legacy helpers and execute grants of the legacy
--     baseline 20260724000000, recorded on production on 5 Aug but never run;
--   * four functions whose production text is a compacted copy of main's
--     (same tokens, no behaviour change), so fingerprints match again.
-- Functions and their execute grants only: no table, row, policy or
-- migration-ledger change. Re-running it is harmless.
--
-- 1. Read-only preflight; continue only when ready_to_apply is true:
--      npx supabase@latest db query --remote=<ref> --read-only -f supabase/preflight/production_function_alignment_preflight.sql
-- 2. Apply by hand, staging first, then production, each with the owner's OK:
--      npx supabase@latest db query --remote=<ref> --yes -f supabase/release/production_function_alignment_bundle.sql
-- 3. Re-run the preflight; already_applied must be true.
-- The guard stops before any change if one of these functions has a definition
-- other than production's of 15 Nov 2026 or main's. Fingerprint:
--   md5(prosrc || coalesce(proconfig::text, '') || provolatile::text || prosecdef::text)
-- Rollback: supabase/release/production_function_alignment_rollback.sql

begin;

do $guard$
declare
  v_allowed constant jsonb := jsonb_build_object(
    'v1_material_search_normalize(text)', jsonb_build_array('absent', '351a0430756a5e2cb730ac22091901ee'),
    'v1_material_search_synonyms(text)', jsonb_build_array('absent', '664152d721f94a1fcaeda2216f92462f'),
    'v1_material_search_one_edit(text,text)', jsonb_build_array('absent', 'da4e7a95947adcd0d7af32e6b790bf83'),
    'v1_search_material_request_candidates(uuid,uuid,text,integer)', jsonb_build_array('c64083a914330a7aa5c353dae5af6963', '1f177e9087dee103fd7eb74b97649b58'),
    'v1_search_company_material_request_candidates(uuid,uuid,text,integer)', jsonb_build_array('23c23e4227f368f14e4856d90e7c2aa0', '9d0e9f3888b285cd9bffa2f797de5780'),
    'v1_material_request_overview(integer)', jsonb_build_array('5c6b96e54bcc884e19b8381816e7df8f', '83e9d3c1227b0baa191b966d8b8b95c5'),
    'v1_material_request_submission_diagnostic(uuid,uuid,uuid)', jsonb_build_array('absent', 'd4c4af385dd1ac080362dc15a04779ba'),
    'v1_can_confirm_material_return(uuid)', jsonb_build_array('f22a335dcb7a7143cd4da6f16174866a', '99b6cbc8dcec9fb5272703afb5692b38'),
    'app_role()', jsonb_build_array('0bc9a3e2215721f357a3333f6cc66b83', 'fe73549c0b069d7287eefe83082cc20d'),
    'app_user_id()', jsonb_build_array('f3d905b9020548149ccfeadca7d1e2fe', 'e27089640fe1db6cd8203b747aa6e387'),
    'notification_visible_to_caller(jsonb)', jsonb_build_array('937c030c5fe6e9288c67816938ab9f40', 'f5f29d8967430dd7aff95c03b079659d'),
    'app_legacy_project_readable(jsonb)', jsonb_build_array('absent', '868de3343460e5f23dd2b6fb91cacb97'),
    'app_legacy_project_writable(jsonb)', jsonb_build_array('absent', '2f9886f3dc5d8e9569ac11b1c983582e'),
    'app_legacy_plan_readable(jsonb)', jsonb_build_array('absent', '4c419e9288ed298eea5958a05c222fd5'),
    'app_legacy_plan_writable(jsonb)', jsonb_build_array('absent', '1bfe72c4ef608cfd9601b7a5cca8206d'),
    'project_progress_definitions(jsonb)', jsonb_build_array('839096d402ff865fd30f88c536d2c34f', '2669c15d30544e6d11170d8eb9abe73f'),
    'project_require_approved_phase1()', jsonb_build_array('5728a75dc73870bc046a28629f02ca75', '84228975d49436cb8d8b677d6749f2e4'),
    'v1_create_document_version(uuid,text,bigint,text)', jsonb_build_array('33c32837d5a32331c9cca1a1cdea4a8d', '468a0043e2754c640ddf4af5bea0e6c6'),
    'v1_import_boq_worksheet(jsonb,uuid)', jsonb_build_array('181ada5a87b31b7a6aab12421f652df6', '6578655c386d24a1c22a84b3dfdeb173'),
    'app_has_cap(text)', jsonb_build_array('52a353bc83eefc45e5ac91afb93a7acb'),
    'app_touch_updated_at()', jsonb_build_array('76377695287d53f3bc550b0b8beb0a9c')
  );
  v_signature text;
  v_fingerprints jsonb;
  v_fingerprint text;
  v_missing text;
begin
  for v_signature, v_fingerprints in
    select key, value from jsonb_each(v_allowed)
  loop
    select md5(p.prosrc || coalesce(p.proconfig::text, '') || p.provolatile::text || p.prosecdef::text)
    into v_fingerprint
    from pg_catalog.pg_proc p
    where p.oid = to_regprocedure('public.' || v_signature);
    if not v_fingerprints ? coalesce(v_fingerprint, 'absent') then
      raise exception
        'function alignment: public.% has an unreviewed definition (%)',
        v_signature, coalesce(v_fingerprint, 'absent');
    end if;
  end loop;

  -- Everything the new bodies call or read must already exist.
  select coalesce(string_agg(missing.name, ', ' order by missing.name), '')
  into v_missing
  from (
    select dependency.name
    from unnest(array[
      'v1_assert_object_keys', 'v1_boq_group_projection',
      'v1_can_create_material_request', 'v1_can_edit_boq_project',
      'v1_can_edit_material_request_before_approval',
      'v1_can_manage_inventory',
      'v1_company_material_request_active_authorization',
      'v1_complete_idempotency', 'v1_current_actor_is_active',
      'v1_current_exact_role', 'v1_current_role',
      'v1_current_user_has_capability', 'v1_has_capability',
      'v1_idempotency_get_or_claim', 'v1_material_register_permission_map',
      'v1_material_request_published_policy_boolean',
      'v1_material_request_readable', 'v1_project_readable',
      'v1_required_boq_commercial_canonical', 'v1_save_boq_worksheet',
      'v1_write_audit_event'
    ]) as dependency(name)
    where not exists (
      select 1 from pg_catalog.pg_proc p
      where p.pronamespace = 'public'::regnamespace
        and p.proname = dependency.name
    )
    union all
    select dependency.name
    from unnest(array[
      'phase1_plans', 'projects', 'v1_audit_events', 'v1_boq_columns',
      'v1_boq_groups', 'v1_boq_rows',
      'v1_company_material_request_categories',
      'v1_company_material_request_units', 'v1_document_links',
      'v1_document_upload_intents', 'v1_document_versions', 'v1_documents',
      'v1_idempotency_keys', 'v1_inventory_items',
      'v1_material_request_lines',
      'v1_material_request_private_draft_retirements',
      'v1_material_requests', 'v1_permission_revisions',
      'v1_procurement_arrangements', 'v1_profiles', 'v1_project_members',
      'v1_project_scopes', 'v1_projects'
    ]) as dependency(name)
    where to_regclass('public.' || quote_ident(dependency.name)) is null
  ) missing;
  if v_missing <> '' then
    raise exception 'function alignment: missing dependencies: %', v_missing;
  end if;
end;
$guard$;

-- ---------------------------------------------------------------------------
-- Material search quality: 20261028125701_reliability_material_search_quality.sql.
-- Punctuation-insensitive tokens, a few unambiguous synonyms (GI, SS, AHU,
-- FCU, VCD, NRV), one typo in the last word, and match_path on each
-- result. Same authorization, same non-commercial fields; the live app
-- ignores match_path. The three helpers are private (service_role only).

CREATE OR REPLACE FUNCTION public.v1_material_search_normalize(p_value text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE STRICT
 SET search_path TO ''
AS $function$
  select btrim(lower(regexp_replace(p_value,'[^[:alnum:]]+',' ','g')));
$function$;

CREATE OR REPLACE FUNCTION public.v1_material_search_synonyms(p_value text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE PARALLEL SAFE STRICT
 SET search_path TO ''
AS $function$
declare result text := p_value;
begin
  -- Only unambiguous material phrases; no brand guessing or physical-unit conversion.
  if strpos(result,'galvan')>0 then
    result:=regexp_replace(result,'\mgalvani[sz]ed iron\M','gi','g');
  end if;
  if strpos(result,'stainless')>0 then result:=replace(result,'stainless steel','ss'); end if;
  if strpos(result,'handling')>0 then result:=regexp_replace(result,'\mair handling units?\M','ahu','g'); end if;
  if strpos(result,'coil')>0 then result:=regexp_replace(result,'\mfan coil units?\M','fcu','g'); end if;
  if strpos(result,'volume')>0 then result:=regexp_replace(result,'\mvolume control dampers?\M','vcd','g'); end if;
  if strpos(result,'return')>0 then result:=regexp_replace(result,'\mnon ?return valves?\M','nrv','g'); end if;
  if strpos(result,'g i')>0 then result:=regexp_replace(result,'\mg i\M','gi','g'); end if;
  if strpos(result,'s s')>0 then result:=regexp_replace(result,'\ms s\M','ss','g'); end if;
  if strpos(result,'f c u')>0 then result:=regexp_replace(result,'\mf c u\M','fcu','g'); end if;
  if strpos(result,'a h u')>0 then result:=regexp_replace(result,'\ma h u\M','ahu','g'); end if;
  return result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.v1_material_search_one_edit(p_left text, p_right text)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE PARALLEL SAFE STRICT
 SET search_path TO ''
AS $function$
declare i integer:=1; j integer:=1; edits integer:=0;
  left_length integer:=char_length(p_left); right_length integer:=char_length(p_right);
begin
  if p_left=p_right then return true; end if;
  if greatest(left_length,right_length)>64 or abs(left_length-right_length)>1 then return false; end if;
  while i<=left_length and j<=right_length loop
    if substr(p_left,i,1)=substr(p_right,j,1) then i:=i+1; j:=j+1;
    else
      edits:=edits+1;
      if edits>1 then return false; end if;
      if left_length=right_length and i<left_length and j<right_length
        and substr(p_left,i,1)=substr(p_right,j+1,1)
        and substr(p_left,i+1,1)=substr(p_right,j,1) then i:=i+2;j:=j+2;
      elsif left_length>right_length then i:=i+1;
      elsif right_length>left_length then j:=j+1;
      else i:=i+1;j:=j+1;end if;
    end if;
  end loop;
  return edits+(left_length-i+1)+(right_length-j+1)<=1;
end;
$function$;

CREATE OR REPLACE FUNCTION public.v1_search_material_request_candidates(p_project_id uuid, p_scope_id uuid, p_query text, p_limit integer DEFAULT 18)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_query text:=lower(regexp_replace(btrim(coalesce(p_query,'')),'\s+',' ','g'));
  v_normalized text:=public.v1_material_search_normalize(coalesce(p_query,''));
  v_synonyms text;
  v_tokens text[];
  v_typo_possible boolean;
  v_limit integer:=least(greatest(coalesce(p_limit,18),1),30);
  v_last text;
begin
  if auth.uid() is null or not public.v1_current_actor_is_active()
    or not coalesce(public.v1_project_readable(p_project_id),false) then
    raise exception 'V1_MATERIAL_REQUEST_CANDIDATE_SEARCH_DENIED' using errcode='42501';
  end if;
  if length(v_query)<2 or not exists(select 1 from public.v1_project_scopes s
    where s.id=p_scope_id and s.project_id=p_project_id and s.is_active) then
    raise exception 'V1_MATERIAL_REQUEST_CANDIDATE_SEARCH_INVALID' using errcode='22023';
  end if;

  if length(v_normalized)<2 then return '[]'::jsonb; end if;
  v_synonyms:=public.v1_material_search_synonyms(v_normalized);
  v_last:=regexp_replace(v_synonyms,'^.* ','');
  v_tokens:=string_to_array(v_synonyms,' ');
  v_typo_possible:=length(v_normalized)>=5 and length(v_last)>=5 and length(v_normalized)<=120;
  return coalesce((
    with candidates as materialized (

      select
        row_record.id,
        case when group_record.scope_id = p_scope_id
          then 'scope_boq' else 'project_boq' end as source_kind,
        case when group_record.scope_id = p_scope_id then 0 else 1 end
          as source_priority,
        null::text as item_code,
        nullif(btrim(row_record.canonical_values ->> 'description'), '')
          as item_description,
        nullif(btrim(row_record.canonical_values ->> 'brand_origin'), '')
          as brand_origin,
        nullif(btrim(row_record.canonical_values ->> 'size'), '') as size_text,
        coalesce(
          nullif(btrim(row_record.canonical_values ->> 'model'), ''),
          nullif(btrim(row_record.canonical_values ->> 'planning_model_tag'), '')
        ) as model_reference,
        nullif(btrim(row_record.canonical_values ->> 'equipment_tag'), '')
          as equipment_tag,
        nullif(btrim(row_record.canonical_values ->> 'unit'), '') as unit,
        group_record.id as source_boq_group_id,
        row_record.id as source_boq_row_id,
        group_record.scope_id as source_scope_id,
        scope_record.name as source_scope_name,
        group_record.worksheet_title as source_group_name,
        lower(concat_ws(' ',
          row_record.canonical_values ->> 'description',
          row_record.canonical_values ->> 'brand_origin',
          row_record.canonical_values ->> 'size',
          row_record.canonical_values ->> 'model',
          row_record.canonical_values ->> 'planning_model_tag',
          row_record.canonical_values ->> 'equipment_tag',
          group_record.worksheet_title,
          scope_record.name
        )) as searchable_text
      from public.v1_boq_rows row_record
      join public.v1_boq_groups group_record
        on group_record.id = row_record.group_id
      left join public.v1_project_scopes scope_record
        on scope_record.id = group_record.scope_id
      where group_record.project_id = p_project_id
        and not group_record.is_archived
        and not row_record.is_archived
        and (scope_record.id is null or scope_record.is_active)
        and nullif(btrim(row_record.canonical_values ->> 'description'), '')
          is not null
        and nullif(btrim(row_record.canonical_values ->> 'unit'), '') is not null

      union all

      select
        item.id,
        'inventory'::text as source_kind,
        2 as source_priority,
        item.item_code,
        item.item_description,
        item.brand_origin,
        item.size_text,
        item.model_reference,
        null::text as equipment_tag,
        item.unit,
        null::uuid as source_boq_group_id,
        null::uuid as source_boq_row_id,
        null::uuid as source_scope_id,
        null::text as source_scope_name,
        null::text as source_group_name,
        lower(concat_ws(' ',
          item.item_code, item.item_description, item.brand_origin,
          item.size_text, item.model_reference, item.unit
        )) as searchable_text
      from public.v1_inventory_items item
      where item.is_active

    ), prepared as materialized (
      select candidate.* from candidates candidate
      -- Normalization only replaces punctuation with spaces, so each
      -- normalized query token must already occur in the lowercased raw text.
      -- Filter before the three per-row regular-expression normalizations.
      where not exists(select 1 from unnest(string_to_array(v_normalized,' ')) token
        where strpos(candidate.searchable_text,token)=0)
    ), fast_ranked as (
      select candidate.*,
        case when lower(coalesce(item_code,''))=v_query or lower(item_description)=v_query then 0
          -- Single ASCII words with an alphanumeric start retain their
          -- prefix after normalization. Resolve their rank without running
          -- regular-expression replacement across every matching row.
          when v_normalized ~ '^[a-z0-9]+$'
            and (coalesce(item_description,'')='' or item_description ~ '^[[:alnum:]]')
            and (coalesce(item_code,'')='' or item_code ~ '^[[:alnum:]]') then
              case
                when (strpos(lower(item_description),v_normalized)=1
                    and substr(lower(item_description),length(v_normalized)+1) !~ '[[:alnum:]]')
                  or (strpos(lower(coalesce(item_code,'')),v_normalized)=1
                    and substr(lower(coalesce(item_code,'')),length(v_normalized)+1) !~ '[[:alnum:]]') then 0
                when strpos(lower(item_description),v_normalized)=1
                  or strpos(lower(coalesce(item_code,'')),v_normalized)=1 then 1
                else 2 end
          when public.v1_material_search_normalize(item_description)=v_normalized
            or public.v1_material_search_normalize(coalesce(item_code,''))=v_normalized then 0
          when public.v1_material_search_normalize(item_description) like v_normalized||'%'
            or public.v1_material_search_normalize(coalesce(item_code,'')) like v_normalized||'%'
            then 1
          when not exists(select 1 from unnest(string_to_array(v_normalized,' ')) token
            where strpos(public.v1_material_search_normalize(searchable_text),token)=0) then 2 else 99 end as match_rank
      from prepared candidate
    ), fast_matches as materialized (
      select candidate.*,case when match_rank=0 then 'exact_normalized' else 'prefix_token' end as match_path
      from fast_ranked candidate where match_rank<99
      -- Later stages run only if no fast match exists, so applying the same
      -- final ordering and limit here cannot remove a visible result.
      order by source_priority,match_rank,lower(item_description),id limit v_limit
    ), synonym_candidates as materialized (
      select candidate.* from candidates candidate
      where not exists(select 1 from fast_matches)
        -- An absent token may cross an alias boundary, for example `s3`
        -- inside `ss304` after expanding `stainless steel304`. Keep every
        -- token sharing any character with an explicit alias; false positives
        -- are intentional here, because this filter must not remove matches.
        -- Invariant: when v1_material_search_synonyms gains an alias, include
        -- every new alias character in both guards below and both RPCs.
        and not exists(
          select 1 from unnest(v_tokens) with ordinality q(token,position)
          where (not v_typo_possible or q.position<cardinality(v_tokens))
            and strpos(candidate.searchable_text,q.token)=0
            and q.token !~ '[gisahufcvdnr]')
        -- For typo-eligible queries that cannot overlap a generated alias,
        -- the first character must begin a normalized word.
        and (not v_typo_possible or strpos(candidate.searchable_text,v_last)>0
          or v_last ~ '[gisahufcvdnr]'
          or candidate.searchable_text ~ ('(^|[^[:alnum:]])'||left(v_last,1)))
    ), synonym_prepared as materialized (
      select candidate.*,
        public.v1_material_search_normalize(candidate.searchable_text) as normalized_text
      from synonym_candidates candidate
    ), synonym_seed as materialized (
      select candidate.*,normalized_text||' '||public.v1_material_search_synonyms(normalized_text) as synonym_text
      from synonym_prepared candidate
    ), synonym_matches as materialized (
      select candidate.id,candidate.source_kind,candidate.source_priority,candidate.item_code,
        candidate.item_description,candidate.brand_origin,candidate.size_text,candidate.model_reference,
        candidate.equipment_tag,candidate.unit,candidate.source_boq_group_id,candidate.source_boq_row_id,
        candidate.source_scope_id,candidate.source_scope_name,candidate.source_group_name,candidate.searchable_text,
        3 as match_rank,'synonym'::text as match_path
      from synonym_seed candidate
      where not exists(select 1 from unnest(string_to_array(v_synonyms,' ')) token
        where strpos(candidate.synonym_text,token)=0)
    ), first_matches as materialized (
      select * from fast_matches union all select * from synonym_matches
    ), typo_seed as materialized (
      -- The expensive comparison never runs on the normal fast path. Limit
      -- candidate rows before token/edit checks, and compare at most one typo.
      select candidate.* from synonym_seed candidate
      where not exists(select 1 from first_matches)
        and length(v_normalized)>=5 and length(v_last)>=5 and length(v_normalized)<=120
        and strpos(' '||candidate.synonym_text,' '||left(v_last,1))>0
        and not exists(select 1 from unnest(string_to_array(v_synonyms,' ')) with ordinality q(token,position)
          where q.position<cardinality(string_to_array(v_synonyms,' '))
            and strpos(candidate.synonym_text,q.token)=0)
      order by candidate.source_priority,candidate.id limit 200
    ), typo_matches as (
      select candidate.id,candidate.source_kind,candidate.source_priority,candidate.item_code,
        candidate.item_description,candidate.brand_origin,candidate.size_text,candidate.model_reference,
        candidate.equipment_tag,candidate.unit,candidate.source_boq_group_id,candidate.source_boq_row_id,
        candidate.source_scope_id,candidate.source_scope_name,candidate.source_group_name,candidate.searchable_text,
        4 as match_rank,'typo'::text as match_path
      from typo_seed candidate where exists(
        select 1 from unnest(string_to_array(candidate.synonym_text,' ')) word
        where abs(length(word)-length(v_last))<=1
          and left(word,1)=left(v_last,1)
          and public.v1_material_search_one_edit(v_last,word))
    ), limited as (
      select * from (select * from first_matches union all select * from typo_matches) matched
      order by source_priority,match_rank,lower(item_description),id limit v_limit
    )
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'id',limited.id,'source_kind',limited.source_kind,'item_code',limited.item_code,
      'item_description',limited.item_description,'brand_origin',limited.brand_origin,
      'size',limited.size_text,'model',limited.model_reference,'equipment_tag',limited.equipment_tag,
      'unit',limited.unit,'source_boq_group_id',limited.source_boq_group_id,
      'source_boq_row_id',limited.source_boq_row_id,'source_scope_id',limited.source_scope_id,
      'source_scope_name',limited.source_scope_name,'source_group_name',limited.source_group_name,
      'match_path',limited.match_path
    )) order by limited.source_priority,limited.match_rank,lower(limited.item_description),limited.id)
    from limited
  ),'[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION public.v1_search_company_material_request_candidates(p_category_id uuid, p_responsible_unit_id uuid, p_query text, p_limit integer DEFAULT 18)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid:=auth.uid();
  v_query text:=lower(regexp_replace(btrim(coalesce(p_query,'')),'\s+',' ','g'));
  v_normalized text:=public.v1_material_search_normalize(coalesce(p_query,''));
  v_synonyms text;
  v_tokens text[];
  v_typo_possible boolean;
  v_limit integer:=least(greatest(coalesce(p_limit,18),1),30);
  v_last text;
begin
  if v_actor is null or not public.v1_current_actor_is_active()
    or not public.v1_company_material_request_active_authorization(
      v_actor,p_category_id,p_responsible_unit_id,'requester') then
    raise exception 'V1_COMPANY_MATERIAL_SEARCH_DENIED' using errcode='42501';
  end if;
  if length(v_query)<2 or length(v_query)>200 or not exists(
    select 1 from public.v1_company_material_request_categories c
    join public.v1_company_material_request_units u on u.id=p_responsible_unit_id
    where c.id=p_category_id and c.is_active and u.is_active) then
    raise exception 'V1_COMPANY_MATERIAL_SEARCH_INVALID' using errcode='22023';
  end if;

  if length(v_normalized)<2 then return '[]'::jsonb; end if;
  v_synonyms:=public.v1_material_search_synonyms(v_normalized);
  v_last:=regexp_replace(v_synonyms,'^.* ','');
  v_tokens:=string_to_array(v_synonyms,' ');
  v_typo_possible:=length(v_normalized)>=5 and length(v_last)>=5 and length(v_normalized)<=120;
  return coalesce((
    with candidates as materialized (

      select item.id,'inventory'::text as source_kind,0 as source_priority,
        item.item_code,item.item_description,item.brand_origin,item.size_text,
        item.model_reference,null::text as equipment_tag,item.unit,
        null::uuid as source_boq_group_id,null::uuid as source_boq_row_id,
        null::uuid as source_scope_id,null::text as source_scope_name,
        null::text as source_group_name,
        lower(concat_ws(' ',item.item_code,item.item_description,item.brand_origin,
          item.size_text,item.model_reference,item.unit)) as searchable_text
      from public.v1_inventory_items item where item.is_active

    ), prepared as materialized (
      select candidate.* from candidates candidate
      -- Normalization only replaces punctuation with spaces, so each
      -- normalized query token must already occur in the lowercased raw text.
      -- Filter before the three per-row regular-expression normalizations.
      where not exists(select 1 from unnest(string_to_array(v_normalized,' ')) token
        where strpos(candidate.searchable_text,token)=0)
    ), fast_ranked as (
      select candidate.*,
        case when lower(coalesce(item_code,''))=v_query or lower(item_description)=v_query then 0
          -- Single ASCII words with an alphanumeric start retain their
          -- prefix after normalization. Resolve their rank without running
          -- regular-expression replacement across every matching row.
          when v_normalized ~ '^[a-z0-9]+$'
            and (coalesce(item_description,'')='' or item_description ~ '^[[:alnum:]]')
            and (coalesce(item_code,'')='' or item_code ~ '^[[:alnum:]]') then
              case
                when (strpos(lower(item_description),v_normalized)=1
                    and substr(lower(item_description),length(v_normalized)+1) !~ '[[:alnum:]]')
                  or (strpos(lower(coalesce(item_code,'')),v_normalized)=1
                    and substr(lower(coalesce(item_code,'')),length(v_normalized)+1) !~ '[[:alnum:]]') then 0
                when strpos(lower(item_description),v_normalized)=1
                  or strpos(lower(coalesce(item_code,'')),v_normalized)=1 then 1
                else 2 end
          when public.v1_material_search_normalize(item_description)=v_normalized
            or public.v1_material_search_normalize(coalesce(item_code,''))=v_normalized then 0
          when public.v1_material_search_normalize(item_description) like v_normalized||'%'
            or public.v1_material_search_normalize(coalesce(item_code,'')) like v_normalized||'%'
            then 1
          when not exists(select 1 from unnest(string_to_array(v_normalized,' ')) token
            where strpos(public.v1_material_search_normalize(searchable_text),token)=0) then 2 else 99 end as match_rank
      from prepared candidate
    ), fast_matches as materialized (
      select candidate.*,case when match_rank=0 then 'exact_normalized' else 'prefix_token' end as match_path
      from fast_ranked candidate where match_rank<99
      -- Later stages run only if no fast match exists, so applying the same
      -- final ordering and limit here cannot remove a visible result.
      order by source_priority,match_rank,lower(item_description),id limit v_limit
    ), synonym_candidates as materialized (
      select candidate.* from candidates candidate
      where not exists(select 1 from fast_matches)
        -- An absent token may cross an alias boundary, for example `s3`
        -- inside `ss304` after expanding `stainless steel304`. Keep every
        -- token sharing any character with an explicit alias; false positives
        -- are intentional here, because this filter must not remove matches.
        -- Invariant: when v1_material_search_synonyms gains an alias, include
        -- every new alias character in both guards below and both RPCs.
        and not exists(
          select 1 from unnest(v_tokens) with ordinality q(token,position)
          where (not v_typo_possible or q.position<cardinality(v_tokens))
            and strpos(candidate.searchable_text,q.token)=0
            and q.token !~ '[gisahufcvdnr]')
        -- For typo-eligible queries that cannot overlap a generated alias,
        -- the first character must begin a normalized word.
        and (not v_typo_possible or strpos(candidate.searchable_text,v_last)>0
          or v_last ~ '[gisahufcvdnr]'
          or candidate.searchable_text ~ ('(^|[^[:alnum:]])'||left(v_last,1)))
    ), synonym_prepared as materialized (
      select candidate.*,
        public.v1_material_search_normalize(candidate.searchable_text) as normalized_text
      from synonym_candidates candidate
    ), synonym_seed as materialized (
      select candidate.*,normalized_text||' '||public.v1_material_search_synonyms(normalized_text) as synonym_text
      from synonym_prepared candidate
    ), synonym_matches as materialized (
      select candidate.id,candidate.source_kind,candidate.source_priority,candidate.item_code,
        candidate.item_description,candidate.brand_origin,candidate.size_text,candidate.model_reference,
        candidate.equipment_tag,candidate.unit,candidate.source_boq_group_id,candidate.source_boq_row_id,
        candidate.source_scope_id,candidate.source_scope_name,candidate.source_group_name,candidate.searchable_text,
        3 as match_rank,'synonym'::text as match_path
      from synonym_seed candidate
      where not exists(select 1 from unnest(string_to_array(v_synonyms,' ')) token
        where strpos(candidate.synonym_text,token)=0)
    ), first_matches as materialized (
      select * from fast_matches union all select * from synonym_matches
    ), typo_seed as materialized (
      -- The expensive comparison never runs on the normal fast path. Limit
      -- candidate rows before token/edit checks, and compare at most one typo.
      select candidate.* from synonym_seed candidate
      where not exists(select 1 from first_matches)
        and length(v_normalized)>=5 and length(v_last)>=5 and length(v_normalized)<=120
        and strpos(' '||candidate.synonym_text,' '||left(v_last,1))>0
        and not exists(select 1 from unnest(string_to_array(v_synonyms,' ')) with ordinality q(token,position)
          where q.position<cardinality(string_to_array(v_synonyms,' '))
            and strpos(candidate.synonym_text,q.token)=0)
      order by candidate.source_priority,candidate.id limit 200
    ), typo_matches as (
      select candidate.id,candidate.source_kind,candidate.source_priority,candidate.item_code,
        candidate.item_description,candidate.brand_origin,candidate.size_text,candidate.model_reference,
        candidate.equipment_tag,candidate.unit,candidate.source_boq_group_id,candidate.source_boq_row_id,
        candidate.source_scope_id,candidate.source_scope_name,candidate.source_group_name,candidate.searchable_text,
        4 as match_rank,'typo'::text as match_path
      from typo_seed candidate where exists(
        select 1 from unnest(string_to_array(candidate.synonym_text,' ')) word
        where abs(length(word)-length(v_last))<=1
          and left(word,1)=left(v_last,1)
          and public.v1_material_search_one_edit(v_last,word))
    ), limited as (
      select * from (select * from first_matches union all select * from typo_matches) matched
      order by source_priority,match_rank,lower(item_description),id limit v_limit
    )
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'id',limited.id,'source_kind',limited.source_kind,'item_code',limited.item_code,
      'item_description',limited.item_description,'brand_origin',limited.brand_origin,
      'size',limited.size_text,'model',limited.model_reference,'equipment_tag',limited.equipment_tag,
      'unit',limited.unit,'source_boq_group_id',limited.source_boq_group_id,
      'source_boq_row_id',limited.source_boq_row_id,'source_scope_id',limited.source_scope_id,
      'source_scope_name',limited.source_scope_name,'source_group_name',limited.source_group_name,
      'match_path',limited.match_path
    )) order by limited.source_priority,limited.match_rank,lower(limited.item_description),limited.id)
    from limited
  ),'[]'::jsonb);
end;
$function$;

revoke all on function public.v1_material_search_normalize(text),
  public.v1_material_search_synonyms(text),
  public.v1_material_search_one_edit(text, text)
  from public, anon, authenticated;
grant execute on function public.v1_material_search_normalize(text),
  public.v1_material_search_synonyms(text),
  public.v1_material_search_one_edit(text, text)
  to service_role;
revoke all on function
  public.v1_search_material_request_candidates(uuid, uuid, text, integer),
  public.v1_search_company_material_request_candidates(uuid, uuid, text, integer)
  from public, anon;
grant execute on function
  public.v1_search_material_request_candidates(uuid, uuid, text, integer),
  public.v1_search_company_material_request_candidates(uuid, uuid, text, integer)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Launch-card overview: 20261028131620_reliability_overview_setwise_actions.sql.
-- Works out "needs my action" for all cards in one pass instead of calling
-- v1_material_request_actor_has_current_action per request (that helper is
-- unchanged since 20260901220449). Same response shape.

CREATE OR REPLACE FUNCTION public.v1_material_request_overview(p_limit integer DEFAULT 6)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 6), 1), 15);
  v_actor uuid := auth.uid();
  v_exact_role text := public.v1_current_exact_role();
  v_result jsonb;
  v_role text := public.v1_current_role();
  v_global boolean := v_exact_role in ('senior_mechanical_engineer','project_manager','workshop_in_charge','document_controller');
  v_allow_self boolean := public.v1_material_request_published_policy_boolean('requests.allow_authorized_creator_self_approval',true);
begin
  if v_actor is null or not public.v1_current_actor_is_active() then
    raise exception 'V1_MATERIAL_REQUEST_OVERVIEW_DENIED'
      using errcode = '42501';
  end if;

  with active_memberships as materialized (
    select member.project_id,true as has_membership,
      bool_or(member.project_role='project_engineer') as is_project_engineer,
      bool_or(member.project_role='site_engineer') as is_site_engineer
    from public.v1_project_members member
    where member.member_auth_user_id=v_actor
      and member.effective_from<=clock_timestamp()
      and (member.effective_to is null or member.effective_to>clock_timestamp())
    group by member.project_id
  ), project_maps as materialized (
    -- Reuse the already-parity-tested statement-local dependency resolver.
    -- No authority result survives this call or changes command authorization.
    select project.id as project_id,project.state as project_state,
      coalesce(m.has_membership,false) as has_active_membership,
      coalesce(m.is_project_engineer,false) as is_project_engineer,
      coalesce(m.is_site_engineer,false) as is_site_engineer,
      public.v1_material_register_permission_map(v_actor,project.id,
        array['material_requests.view','material_requests.edit',
          'material_requests.approve','material_requests.return_for_changes',
          'procurement.arrange','dispatch.create','receipts.confirm','material_requests.close']) as permissions
    from public.v1_projects project
    left join active_memberships m on m.project_id=project.id
    where exists(select 1 from public.v1_material_requests r where r.project_id=project.id)
  ), project_access as materialized (
    select project_maps.*,
      coalesce((permissions->>'material_requests.view')::boolean,false) as can_view
    from project_maps
  ), has_arrangement as materialized (
    select distinct request_id from public.v1_procurement_arrangements
  ), readable as materialized (
    -- This case expression is the set-based equivalent of
    -- v1_material_request_participant(request.id, v_actor). Keep its ordering:
    -- Admin can read drafts; every other role can read a draft only when it is
    -- their own; global engineers then receive organization-wide submitted
    -- work; project roles require dated membership; Procurement receives only
    -- the established procurement lifecycle states.
    select request.*, access.project_state,access.permissions,
      access.has_active_membership,access.is_project_engineer,access.is_site_engineer,
      arrangement.request_id is not null as has_arrangement,
      project.project_ref,
      project.name as project_name, project.job_contract_reference,
      scope.name as scope_name
    from public.v1_material_requests request
    join project_access access on access.project_id = request.project_id
    join public.v1_projects project on project.id = request.project_id
    join public.v1_project_scopes scope on scope.id = request.scope_id
    left join has_arrangement arrangement on arrangement.request_id=request.id
    where access.can_view
      and case
        when v_exact_role = 'admin' then true
        when request.state = 'draft'
          then request.created_by_auth_user_id = v_actor
        when v_exact_role in (
          'senior_mechanical_engineer', 'project_manager',
          'workshop_in_charge', 'document_controller'
        ) then true
        when v_exact_role in ('project_engineer', 'site_engineer')
          then access.has_active_membership
        when v_exact_role = 'procurement' then request.state in (
          'submitted', 'approved_for_arrangement', 'arranging',
          'awaiting_approval', 'approved', 'partially_dispatched',
          'dispatched', 'partially_received', 'received', 'closed',
          'cancelled'
        )
        else false
      end
  ), scored as materialized (
    -- Set-based equivalent of the unchanged actor_has_current_action helper.
    -- Keep its branch order, ownership, exact roles, state gates and policies.
    select readable.*,
      case
        when state in ('closed','cancelled') then false
        when state='draft' then created_by_auth_user_id=v_actor
        when state in ('submitted','awaiting_request_approval') then
          (v_exact_role='admin' or v_global or (v_exact_role='project_engineer' and is_project_engineer))
          and (v_allow_self or created_by_auth_user_id<>v_actor)
          and (coalesce((permissions->>'material_requests.approve')::boolean,false)
            or coalesce((permissions->>'material_requests.return_for_changes')::boolean,false))
        when state='changes_requested' and post_approval_amendment_pending then
          public.v1_can_edit_material_request_before_approval(id)
        when state='changes_requested' then not has_arrangement
          and (created_by_auth_user_id=v_actor or v_exact_role='admin' or v_global
            or (v_exact_role='project_engineer' and is_project_engineer))
          and coalesce((permissions->>'material_requests.edit')::boolean,false)
        when state in ('approved_for_arrangement','arranging') then
          v_exact_role in ('procurement','admin') and project_state in ('active','on_hold')
          and coalesce((permissions->>'procurement.arrange')::boolean,false)
        when state='awaiting_approval' then
          v_role in ('project_engineer','admin')
          and (v_exact_role='admin' or v_global or is_project_engineer)
        when current_action_code='receipt_review_required' or state='dispatched' then
          project_state in ('active','on_hold','completed')
          and (v_exact_role='admin' or v_global
            or (v_exact_role in ('project_engineer','site_engineer') and has_active_membership))
          and coalesce((permissions->>'receipts.confirm')::boolean,false)
        when current_action_code='material_request_close_review' or state='received' then
          (v_exact_role='admin' or v_global
            or (v_exact_role='project_engineer' and is_project_engineer)
            or (v_exact_role='site_engineer' and is_site_engineer))
          and coalesce((permissions->>'material_requests.close')::boolean,false)
        when state in ('approved','partially_dispatched','partially_received') then
          v_exact_role in ('procurement','admin') and project_state='active'
          and coalesce((permissions->>'dispatch.create')::boolean,false)
        else false
      end as actor_can_act
    from readable
  ), bounded as materialized (
    select * from scored
    order by updated_at desc, id
    limit v_limit
  )
  select jsonb_build_object(
    'items', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', bounded.id,
        'project_id', bounded.project_id,
        'project_ref', bounded.project_ref,
        'project_name', bounded.project_name,
        'job_contract_reference', bounded.job_contract_reference,
        'scope_id', bounded.scope_id,
        'scope_name', bounded.scope_name,
        'state', bounded.state,
        'record_version', bounded.record_version,
        'request_number', bounded.request_number,
        'title', bounded.title,
        'timing', bounded.timing,
        'scheduled_date', bounded.scheduled_date,
        'delivery_note', bounded.delivery_note,
        'requester_display_name', bounded.requester_display_name,
        'requester_project_role', bounded.requester_project_role,
        'requester_exact_role', bounded.requester_exact_role,
        'current_action_owner_role', bounded.current_action_owner_role,
        'current_action_code', bounded.current_action_code,
        'current_action_started_at', bounded.updated_at,
        'current_action_age_hours', greatest(
          extract(epoch from (clock_timestamp() - bounded.updated_at)) / 3600,
          0
        ),
        'required_on_site_overdue', bounded.timing = 'scheduled'
          and bounded.scheduled_date < current_date
          and bounded.state not in ('received', 'closed', 'cancelled'),
        'actor_can_act', bounded.actor_can_act,
        -- Exception, assignment and revision enrichment belong to the detail
        -- and register RPCs. Startup cards need identity/state only.
        'exception_codes', to_jsonb(array[]::text[]),
        'item_count', (
          select count(*)::integer
          from public.v1_material_request_lines line
          where line.request_id = bounded.id
        ),
        'work_assignment', jsonb_build_object(
          'request_id', bounded.id,
          'assignment_version', 0,
          'assignee_auth_user_id', null,
          'assignee_display_name', null,
          'assignee_exact_role', null,
          'assigned_at', null,
          'can_manage', false
        ),
        'change_summary', null,
        'submitted_at', bounded.submitted_at,
        'created_at', bounded.created_at,
        'updated_at', bounded.updated_at
      ) order by bounded.updated_at desc, bounded.id), '[]'::jsonb)
      from bounded
    ),
    'counts', (
      select jsonb_build_object(
        'total', count(*),
        'open', count(*) filter (where state not in (
          'draft', 'received', 'closed', 'cancelled'
        )),
        'needs_action', count(*) filter (where actor_can_act),
        'approvals', count(*) filter (where state in (
          'awaiting_request_approval', 'awaiting_approval'
        )),
        'delivery_exceptions', count(*) filter (where state in (
          'changes_requested', 'partially_dispatched', 'partially_received'
        )),
        'receipt_pending', count(*) filter (where state in (
          'dispatched', 'partially_received'
        )),
        'drafts_and_changes', count(*) filter (where state in (
          'draft', 'changes_requested'
        )),
        'received', count(*) filter (where state = 'received'),
        'closed', count(*) filter (where state = 'closed'),
        'dispatch_ready', count(*) filter (where state in (
          'approved', 'partially_dispatched'
        )),
        'new_to_arrange', count(*) filter (where state in (
          'approved_for_arrangement', 'arranging'
        ))
      )
      from scored
    )
  ) into v_result;

  return v_result;
end;
$function$;

revoke all on function public.v1_material_request_overview(integer)
  from public, anon, authenticated;
grant execute on function public.v1_material_request_overview(integer)
  to authenticated, service_role;
comment on function public.v1_material_request_overview(integer)
is 'Set-based bounded non-commercial launch cards with exact authorized counts.';

-- ---------------------------------------------------------------------------
-- Submission diagnostic: 20261028133155_reliability_submission_diagnostic.sql.
-- Read-only, additive RPC that explains a refused submission in coarse
-- terms. The live web (849affb) does not call it yet.

CREATE OR REPLACE FUNCTION public.v1_material_request_submission_diagnostic(p_project_id uuid, p_scope_id uuid, p_request_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid:=auth.uid();v_revision bigint;v_membership boolean:=false;
  v_scope_consistent boolean:=false;v_project_state text;v_reason text:='ready';
  v_request public.v1_material_requests%rowtype;v_request_exists boolean:=false;
begin
  if v_actor is null or not public.v1_current_actor_is_active() then
    raise exception 'V1_AUTHENTICATED_ROLE_REQUIRED' using errcode='42501';
  end if;
  select coalesce(max(revision),0) into v_revision from public.v1_permission_revisions where auth_user_id=v_actor;
  if p_project_id is null or not coalesce(public.v1_project_readable(p_project_id),false) then
    return jsonb_build_object('reason_code','project_unavailable','permission_revision',v_revision,
      'active_membership',null,'project_scope_consistent',null,'can_submit',false);
  end if;
  select state into v_project_state from public.v1_projects where id=p_project_id;
  select exists(select 1 from public.v1_project_members m join public.v1_profiles p
    on p.auth_user_id=m.member_auth_user_id and p.is_active
    where m.project_id=p_project_id and m.member_auth_user_id=v_actor
      and m.effective_from<=clock_timestamp() and (m.effective_to is null or m.effective_to>clock_timestamp())) into v_membership;
  select exists(select 1 from public.v1_project_scopes s where s.id=p_scope_id
    and s.project_id=p_project_id and s.is_active) into v_scope_consistent;
  if p_request_id is not null then
    select * into v_request from public.v1_material_requests where id=p_request_id;
    v_request_exists:=found;
    if not v_request_exists then
      if exists(select 1 from public.v1_material_request_private_draft_retirements
        where draft_id=p_request_id and owner_auth_user_id=v_actor) then
        return jsonb_build_object('reason_code','draft_retired','permission_revision',v_revision,
          'active_membership',v_membership,'project_scope_consistent',v_scope_consistent,'can_submit',false);
      end if;
      -- An unknown ID and another creator's private ID have the same shape.
      -- New/local-only drafts call with p_request_id=null for context review.
      return jsonb_build_object('reason_code','project_unavailable','permission_revision',v_revision,
        'active_membership',null,'project_scope_consistent',null,'can_submit',false);
    end if;
    if v_request_exists and (v_request.created_by_auth_user_id<>v_actor
        or not public.v1_material_request_readable(p_request_id)) then
      -- Do not reveal another creator's private draft/state or a revoked request.
      return jsonb_build_object('reason_code','project_unavailable','permission_revision',v_revision,
        'active_membership',null,'project_scope_consistent',null,'can_submit',false);
    end if;
  end if;
  if v_project_state<>'active' then v_reason:='project_not_active';
  elsif not v_scope_consistent then v_reason:='scope_unavailable';
  elsif v_request_exists and v_request.project_id<>p_project_id then v_reason:='request_context_changed';
  elsif v_request_exists and v_request.state<>'draft' then v_reason:='request_progressed';
  elsif not public.v1_can_create_material_request(p_project_id) then v_reason:='creation_not_allowed';
  elsif v_request_exists and not public.v1_current_user_has_capability('material_requests.edit',p_project_id)
    then v_reason:='editing_not_allowed';
  elsif not public.v1_current_user_has_capability('material_requests.submit',p_project_id)
    then v_reason:='submission_not_allowed';
  end if;
  return jsonb_build_object('reason_code',v_reason,'permission_revision',v_revision,
    'active_membership',v_membership,'project_scope_consistent',v_scope_consistent,'can_submit',v_reason='ready');
end;
$function$;

revoke all on function
  public.v1_material_request_submission_diagnostic(uuid, uuid, uuid)
  from public, anon;
grant execute on function
  public.v1_material_request_submission_diagnostic(uuid, uuid, uuid)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Return confirmation rule: 20260803224536_yorks_v1_p0_boq_document_delivery_order.sql.
-- Only an inventory manager (Procurement or Admin) on an active, on-hold or
-- completed project may confirm or reject a return, and only they see the
-- inventory links in v1_returns_documents_workspace_projection. Production
-- still has the 20260802050000 rule (anyone who may generate a Delivery
-- Order), so engineers also receive the confirm flags and inventory list.

CREATE OR REPLACE FUNCTION public.v1_can_confirm_material_return(p_request_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_project_state text;
begin
  if not public.v1_can_manage_inventory() then return false; end if;
  select project.state into v_project_state
  from public.v1_material_requests request_record
  join public.v1_projects project on project.id = request_record.project_id
  where request_record.id = p_request_id;
  return v_project_state in ('active', 'on_hold', 'completed');
end;
$function$;

-- ---------------------------------------------------------------------------
-- Legacy JWT helpers: 20260724000000_legacy_collection_prerequisites.sql.
-- Production still has the original hand-built helpers: app_role() falls
-- back to the top-level JWT role, broadcast notifications are visible to
-- callers without an app user id, and anon/PUBLIC may execute them. The
-- four app_legacy_* helpers are new on production and unused there until
-- the legacy collection policies are aligned (separate follow-up).

CREATE OR REPLACE FUNCTION public.app_role()
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '');
$function$;

CREATE OR REPLACE FUNCTION public.app_user_id()
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select coalesce(
    auth.jwt() -> 'app_metadata' ->> 'app_user_id',
    ''
  );
$function$;

CREATE OR REPLACE FUNCTION public.notification_visible_to_caller(p_data jsonb)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select public.app_role() = 'admin'
      or (
        coalesce(p_data ->> 'userId', '') <> ''
        and p_data ->> 'userId' = public.app_user_id()
      )
      or (
        coalesce(p_data ->> 'userId', '') = ''
        and public.app_user_id() <> ''
        and (
          coalesce(p_data ->> 'audience', '') = ''
          or p_data ->> 'audience' = public.app_role()
        )
      );
$function$;

CREATE OR REPLACE FUNCTION public.app_legacy_project_readable(p_data jsonb)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select public.app_has_cap('goods')
      or (
        public.app_role() = 'engineer'
        and public.app_user_id() <> ''
        and (
          p_data ->> 'assignedEngineerId' = public.app_user_id()
          or coalesce(
            p_data -> 'designEngineerUserIds',
            '[]'::jsonb
          ) ? public.app_user_id()
          or (
            coalesce(p_data ->> 'assignedEngineerId', '') = ''
            and coalesce(
              p_data -> 'designEngineerUserIds',
              '[]'::jsonb
            ) = '[]'::jsonb
          )
        )
      );
$function$;

CREATE OR REPLACE FUNCTION public.app_legacy_project_writable(p_data jsonb)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select public.app_has_cap('goods')
      or (
        public.app_role() = 'engineer'
        and public.app_user_id() <> ''
        and (
          p_data ->> 'assignedEngineerId' = public.app_user_id()
          or coalesce(
            p_data -> 'designEngineerUserIds',
            '[]'::jsonb
          ) ? public.app_user_id()
        )
      );
$function$;

CREATE OR REPLACE FUNCTION public.app_legacy_plan_readable(p_data jsonb)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select exists (
    select 1
    from public.projects project
    where project.id = p_data ->> 'projectId'
      and public.app_legacy_project_readable(project.data)
  );
$function$;

CREATE OR REPLACE FUNCTION public.app_legacy_plan_writable(p_data jsonb)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select exists (
    select 1
    from public.projects project
    where project.id = p_data ->> 'projectId'
      and public.app_legacy_project_writable(project.data)
  );
$function$;

revoke all on function public.app_touch_updated_at()
  from public, anon, authenticated;
revoke all on function public.app_role(), public.app_user_id(),
  public.app_has_cap(text)
  from public, anon, authenticated;
grant execute on function public.app_role(), public.app_user_id(),
  public.app_has_cap(text)
  to authenticated, service_role;
revoke all on function public.app_legacy_project_readable(jsonb),
  public.app_legacy_project_writable(jsonb),
  public.app_legacy_plan_readable(jsonb),
  public.app_legacy_plan_writable(jsonb),
  public.notification_visible_to_caller(jsonb)
  from public, anon;
grant execute on function public.app_legacy_project_readable(jsonb),
  public.app_legacy_project_writable(jsonb),
  public.app_legacy_plan_readable(jsonb),
  public.app_legacy_plan_writable(jsonb),
  public.notification_visible_to_caller(jsonb)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Formatting only (no behaviour change). Production holds compacted copies
-- of these bodies from the timestamp-shifted scripts of 24 Jul and 3 Aug
-- (PRODUCTION_MIGRATION_RECONCILIATION_2026-08-05.md); later migrations
-- patched the live text in place. Same tokens as main; the only other
-- difference is whitespace inside one JSON literal (same jsonb value).
--   project_progress_definitions, project_require_approved_phase1:
--     20260724050201_batch8_project_progress_invariants.sql
--   v1_create_document_version:
--     20260803211633_yorks_v1_document_replacement_version_link.sql
--   v1_import_boq_worksheet: 20260803192654_yorks_v1_boq_header_hierarchy.sql
--     as patched by 20260803224536, 20260808100023 and 20260809143000

CREATE OR REPLACE FUNCTION public.project_progress_definitions(p_data jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  with source as (
    select case
      when jsonb_typeof(p_data -> 'progressStages') = 'array'
        then coalesce(p_data -> 'progressStages', '[]'::jsonb)
      else '[]'::jsonb
    end as stages
  ),
  definitions as (
    select jsonb_agg(
      jsonb_build_object(
        'id', stage.value ->> 'id',
        'label', stage.value ->> 'label',
        'weightPercent', stage.value -> 'weightPercent'
      )
      order by stage.ordinality
    ) as value
    from source,
      jsonb_array_elements(source.stages) with ordinality as stage(value, ordinality)
  )
  select coalesce(
    definitions.value,
    '[
      {"id":"cooling-load-design","label":"Cooling Load Design","weightPercent":10},
      {"id":"material-supply","label":"Material Supply","weightPercent":50},
      {"id":"progress-installation","label":"Progress Installation","weightPercent":30},
      {"id":"commissioning-handover","label":"Commissioning & Handover","weightPercent":5},
      {"id":"energizing-substation","label":"Energizing Substation","weightPercent":5}
    ]'::jsonb
  )
  from definitions;
$function$;

CREATE OR REPLACE FUNCTION public.project_require_approved_phase1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  caller_role text := public.app_role();
  old_status text := case
    when tg_op = 'INSERT' then null
    else old.data ->> 'lifecycleStatus'
  end;
  new_status text := new.data ->> 'lifecycleStatus';
  old_stages jsonb := case
    when tg_op = 'INSERT' then '[]'::jsonb
    else coalesce(old.data -> 'progressStages', '[]'::jsonb)
  end;
  new_stages jsonb := coalesce(new.data -> 'progressStages', '[]'::jsonb);
  total_weight numeric;
begin
  if current_user in ('postgres', 'supabase_admin', 'service_role') then
    return new;
  end if;

  if new_status = 'active'
     and old_status is distinct from 'active'
     and not exists (
       select 1
       from public.phase1_plans plan
       where plan.project_id = new.id
         and plan.status = 'approved'
     ) then
    raise exception using
      errcode = '55000',
      message = 'A project requires an approved Phase 1 plan before activation.';
  end if;

  if new_stages is distinct from old_stages then
    if jsonb_typeof(new_stages) <> 'array'
       or jsonb_array_length(new_stages) = 0 then
      raise exception using
        errcode = '22023',
        message = 'Project progress stages must be a non-empty array.';
    end if;

    if exists (
      select 1
      from jsonb_array_elements(new_stages) stage
      where jsonb_typeof(stage) <> 'object'
        or btrim(coalesce(stage ->> 'id', '')) = ''
        or btrim(coalesce(stage ->> 'label', '')) = ''
        or jsonb_typeof(stage -> 'weightPercent') <> 'number'
        or (stage ->> 'weightPercent')::numeric <= 0
        or jsonb_typeof(stage -> 'progressPercent') <> 'number'
        or (stage ->> 'progressPercent')::numeric < 0
        or (stage ->> 'progressPercent')::numeric > 100
    ) then
      raise exception using
        errcode = '22023',
        message = 'Project progress stages contain invalid values.';
    end if;

    if exists (
      select 1
      from jsonb_array_elements(new_stages) stage
      group by stage ->> 'id'
      having count(*) > 1
    ) then
      raise exception using
        errcode = '22023',
        message = 'Project progress stage ids must be unique.';
    end if;

    select sum((stage ->> 'weightPercent')::numeric)
    into total_weight
    from jsonb_array_elements(new_stages) stage;
    if abs(total_weight - 100) > 0.01 then
      raise exception using
        errcode = '22023',
        message = 'Project progress weights must total 100.';
    end if;

    if caller_role = 'procurement' then
      raise exception using
        errcode = '42501',
        message = 'Procurement has read-only project progress access.';
    end if;
    if caller_role = 'engineer'
       and public.project_progress_definitions(old.data)
           is distinct from public.project_progress_definitions(new.data) then
      raise exception using
        errcode = '42501',
        message = 'Engineering can update progress but not stage definitions.';
    end if;
  end if;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.v1_create_document_version(p_upload_intent_id uuid, p_verified_sha256 text, p_verified_byte_size bigint, p_verified_mime_type text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_intent public.v1_document_upload_intents%rowtype;
  v_document_id uuid;
  v_version_id uuid;
  v_previous_version_id uuid;
  v_object storage.objects%rowtype;
  v_metadata_size bigint;
  v_metadata_mime text;
  v_request_hash text;
  v_response jsonb;
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'V1_DOCUMENT_FINALIZER_SERVICE_ONLY' using errcode = '42501';
  end if;
  select * into v_intent from public.v1_document_upload_intents
  where id = p_upload_intent_id for update;
  if not found then
    raise exception 'V1_DOCUMENT_UPLOAD_INTENT_NOT_FOUND' using errcode = '22023';
  end if;
  if v_intent.finalized_at is not null then
    return jsonb_build_object(
      'document_id', v_intent.finalized_document_id,
      'document_version_id', v_intent.finalized_version_id,
      'revision_number', v_intent.planned_revision_number
    );
  end if;
  if v_intent.expires_at <= clock_timestamp() then
    raise exception 'V1_DOCUMENT_UPLOAD_INTENT_EXPIRED' using errcode = '22023';
  end if;
  if lower(p_verified_sha256) <> v_intent.expected_sha256
    or p_verified_byte_size <> v_intent.byte_size
    or p_verified_mime_type <> v_intent.mime_type then
    raise exception 'V1_DOCUMENT_OBJECT_VERIFICATION_FAILED' using errcode = '22023';
  end if;

  select * into v_object from storage.objects
  where bucket_id = v_intent.bucket_id and name = v_intent.object_path;
  if not found or coalesce(v_object.owner_id, '') <> v_intent.actor_auth_user_id::text then
    raise exception 'V1_DOCUMENT_OBJECT_NOT_OWNED_BY_INTENT' using errcode = '42501';
  end if;
  v_metadata_size := nullif(v_object.metadata ->> 'size', '')::bigint;
  v_metadata_mime := coalesce(
    nullif(v_object.metadata ->> 'mimetype', ''),
    nullif(v_object.metadata ->> 'contentType', '')
  );
  if v_metadata_size <> v_intent.byte_size
    or v_metadata_mime <> v_intent.mime_type then
    raise exception 'V1_DOCUMENT_STORAGE_METADATA_MISMATCH' using errcode = '22023';
  end if;

  v_document_id := coalesce(v_intent.document_id, gen_random_uuid());
  if v_intent.document_id is null then
    insert into public.v1_documents (
      id, classification, created_by_auth_user_id, created_by_role
    ) values (
      v_document_id, v_intent.classification, v_intent.actor_auth_user_id,
      v_intent.actor_role
    );
  else
    select current_version_id into v_previous_version_id
    from public.v1_documents where id = v_document_id for update;
  end if;

  v_version_id := gen_random_uuid();
  insert into public.v1_document_versions (
    id, document_id, revision_number, bucket_id, object_path,
    original_file_name, mime_type, byte_size, sha256, origin,
    source_entity_type, source_entity_id, source_revision,
    uploaded_by_auth_user_id, uploaded_by_role, supersedes_version_id
  ) values (
    v_version_id, v_document_id, v_intent.planned_revision_number,
    v_intent.bucket_id, v_intent.object_path, v_intent.original_file_name,
    v_intent.mime_type, v_intent.byte_size, v_intent.expected_sha256,
    v_intent.origin, v_intent.source_entity_type, v_intent.source_entity_id,
    v_intent.source_revision, v_intent.actor_auth_user_id, v_intent.actor_role,
    v_previous_version_id
  );
  update public.v1_documents set current_version_id = v_version_id
  where id = v_document_id;

  -- A replacement keeps the original active link. Reinserting that link would
  -- violate v1_document_links_one_current_target_idx and leave the new version
  -- unfinalized. New documents still receive their initial immutable link.
  if v_intent.document_id is null then
    insert into public.v1_document_links (
      id, document_id, project_id, entity_type, entity_id,
      linked_by_auth_user_id, linked_by_role
    ) values (
      gen_random_uuid(), v_document_id, v_intent.project_id,
      v_intent.target_entity_type, v_intent.target_entity_id,
      v_intent.actor_auth_user_id, v_intent.actor_role
    );
  end if;
  update public.v1_document_upload_intents set
    finalized_document_id = v_document_id,
    finalized_version_id = v_version_id,
    finalized_at = clock_timestamp()
  where id = v_intent.id;

  v_response := jsonb_build_object(
    'document_id', v_document_id,
    'document_version_id', v_version_id,
    'revision_number', v_intent.planned_revision_number
  );
  update public.v1_idempotency_keys set
    response_json = response_json || v_response
  where actor_auth_user_id = v_intent.actor_auth_user_id
    and command_name = 'v1_prepare_document_upload'
    and idempotency_key = v_intent.idempotency_key;
  select request_hash into v_request_hash from public.v1_idempotency_keys
  where actor_auth_user_id = v_intent.actor_auth_user_id
    and command_name = 'v1_prepare_document_upload'
    and idempotency_key = v_intent.idempotency_key;
  insert into public.v1_audit_events (
    event_type, entity_type, entity_id, project_id, actor_auth_user_id,
    actor_role, occurred_at, idempotency_key, after_data, request_hash
  ) values (
    case when v_previous_version_id is null
      then 'document_version_created' else 'document_version_superseded' end,
    'document_version', v_version_id, v_intent.project_id,
    v_intent.actor_auth_user_id, v_intent.actor_role, clock_timestamp(),
    v_intent.idempotency_key,
    jsonb_build_object(
      'document_id', v_document_id,
      'revision_number', v_intent.planned_revision_number,
      'classification', v_intent.classification,
      'origin', v_intent.origin
    ),
    v_request_hash
  );
  return v_response;
end;
$function$;

CREATE OR REPLACE FUNCTION public.v1_import_boq_worksheet(p_payload jsonb, p_idempotency_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_group_id uuid;
  v_expected_version integer;
  v_title text;
  v_columns jsonb;
  v_rows jsonb;
  v_source jsonb;
  v_file_name text;
  v_sheet_name text;
  v_header_row_number integer;
  v_header_row_numbers jsonb;
  v_header_hierarchy jsonb;
  v_header_number_text text;
  v_header_number integer;
  v_previous_header_number integer := 0;
  v_header_path jsonb;
  v_header_label text;
  v_group public.v1_boq_groups%rowtype;
  v_existing_response jsonb;
  v_save_response jsonb;
  v_before jsonb;
  v_source_projection jsonb;
  v_column jsonb;
  v_heading text;
  v_canonical text;
begin
  perform public.v1_assert_object_keys(
    p_payload,
    array[
      'group_id', 'expected_version', 'worksheet_title', 'columns', 'rows',
      'source'
    ],
    'boq_workbook_import'
  );
  v_group_id := nullif(btrim(coalesce(p_payload ->> 'group_id', '')), '')::uuid;
  v_expected_version := nullif(p_payload ->> 'expected_version', '')::integer;
  v_title := nullif(btrim(coalesce(p_payload ->> 'worksheet_title', '')), '');
  v_columns := coalesce(p_payload -> 'columns', '[]'::jsonb);
  v_rows := coalesce(p_payload -> 'rows', '[]'::jsonb);
  v_source := p_payload -> 'source';
  if v_group_id is null or v_expected_version is null or v_expected_version < 1
    or v_title is null or jsonb_typeof(v_columns) <> 'array'
    or jsonb_typeof(v_rows) <> 'array' or jsonb_typeof(v_source) <> 'object' then
    raise exception 'V1_BOQ_IMPORT_PAYLOAD_INVALID' using errcode = '22023';
  end if;

  -- The two metadata keys are optional for pre-R35 clients. New clients send
  -- them for every import, while historical imports remain replayable.
  perform public.v1_assert_object_keys(
    v_source,
    array[
      'file_name', 'worksheet_name', 'header_row_number',
      'header_row_numbers', 'header_hierarchy'
    ],
    'boq_workbook_import_source'
  );
  v_file_name := nullif(btrim(coalesce(v_source ->> 'file_name', '')), '');
  v_sheet_name := nullif(btrim(coalesce(v_source ->> 'worksheet_name', '')), '');
  v_header_row_number := nullif(v_source ->> 'header_row_number', '')::integer;
  if v_file_name is null or char_length(v_file_name) > 255
    or v_sheet_name is null or char_length(v_sheet_name) > 128
    or v_header_row_number is null or v_header_row_number < 1 then
    raise exception 'V1_BOQ_IMPORT_SOURCE_INVALID' using errcode = '22023';
  end if;
  v_header_row_numbers := coalesce(
    v_source -> 'header_row_numbers', jsonb_build_array(v_header_row_number)
  );
  v_header_hierarchy := coalesce(v_source -> 'header_hierarchy', '[]'::jsonb);
  if jsonb_typeof(v_header_row_numbers) <> 'array'
    or jsonb_array_length(v_header_row_numbers) < 1
    or jsonb_array_length(v_header_row_numbers) > 2
    or jsonb_typeof(v_header_hierarchy) <> 'array' then
    raise exception 'V1_BOQ_IMPORT_SOURCE_INVALID' using errcode = '22023';
  end if;
  for v_header_number_text in
    select value from jsonb_array_elements_text(v_header_row_numbers)
  loop
    if v_header_number_text !~ '^[1-9][0-9]*$' then
      raise exception 'V1_BOQ_IMPORT_SOURCE_INVALID' using errcode = '22023';
    end if;
    v_header_number := v_header_number_text::integer;
    if v_header_number <= v_previous_header_number then
      raise exception 'V1_BOQ_IMPORT_SOURCE_INVALID' using errcode = '22023';
    end if;
    v_previous_header_number := v_header_number;
  end loop;
  if (v_header_row_numbers ->> 0)::integer <> v_header_row_number then
    raise exception 'V1_BOQ_IMPORT_SOURCE_INVALID' using errcode = '22023';
  end if;
  if jsonb_array_length(v_header_hierarchy) > 0
    and jsonb_array_length(v_header_hierarchy) <> jsonb_array_length(v_columns) then
    raise exception 'V1_BOQ_IMPORT_SOURCE_INVALID' using errcode = '22023';
  end if;
  for v_header_path in select value from jsonb_array_elements(v_header_hierarchy)
  loop
    perform public.v1_assert_object_keys(
      v_header_path, array['source_index', 'labels'], 'boq_header_path'
    );
    if jsonb_typeof(v_header_path -> 'source_index') <> 'number'
      or (v_header_path ->> 'source_index') !~ '^[0-9]+$'
      or jsonb_typeof(v_header_path -> 'labels') <> 'array'
      or jsonb_array_length(v_header_path -> 'labels') < 1
      or jsonb_array_length(v_header_path -> 'labels') > 2 then
      raise exception 'V1_BOQ_IMPORT_SOURCE_INVALID' using errcode = '22023';
    end if;
    if (v_header_path ->> 'source_index')::integer > 255 then
      raise exception 'V1_BOQ_IMPORT_SOURCE_INVALID' using errcode = '22023';
    end if;
    for v_header_label in
      select value from jsonb_array_elements_text(v_header_path -> 'labels')
    loop
      if nullif(btrim(v_header_label), '') is null
        or char_length(v_header_label) > 255 then
        raise exception 'V1_BOQ_IMPORT_SOURCE_INVALID' using errcode = '22023';
      end if;
    end loop;
  end loop;
  if exists (
    select 1
    from (
      select value ->> 'source_index' as source_index, count(*) as total
      from jsonb_array_elements(v_header_hierarchy)
      group by value ->> 'source_index'
    ) duplicated_source_index
    where duplicated_source_index.total > 1
  ) then
    raise exception 'V1_BOQ_IMPORT_SOURCE_INVALID' using errcode = '22023';
  end if;

  select * into v_group from public.v1_boq_groups group_record
  where group_record.id = v_group_id for update;
  if not found or v_group.scope_id is null or not public.v1_can_edit_boq_project(v_group.project_id) then
    raise exception 'V1_BOQ_IMPORT_DENIED' using errcode = '42501';
  end if;

  v_existing_response := public.v1_idempotency_get_or_claim(
    'v1_import_boq_worksheet', p_idempotency_key, p_payload
  );
  if v_existing_response is not null then return v_existing_response; end if;

  if v_group.is_archived
    or (select state from public.v1_projects where id = v_group.project_id)
      not in ('draft', 'active') then
    raise exception 'V1_BOQ_PROJECT_NOT_EDITABLE' using errcode = '42501';
  end if;
  if v_group.record_version <> v_expected_version then
    raise exception 'V1_BOQ_VERSION_CONFLICT' using errcode = '40001';
  end if;
  if exists (
    select 1 from public.v1_boq_columns column_record
    where column_record.group_id = v_group_id
      and not column_record.is_archived
      and column_record.is_commercial
  ) and not public.v1_has_capability('manage_commercials') then
    raise exception 'V1_BOQ_COMMERCIAL_IMPORT_DENIED' using errcode = '42501';
  end if;

  for v_column in select value from jsonb_array_elements(v_columns)
  loop
    perform public.v1_assert_object_keys(
      v_column,
      array['id', 'heading', 'display_order', 'canonical_field', 'is_commercial'],
      'boq_import_column'
    );
    v_heading := nullif(btrim(coalesce(v_column ->> 'heading', '')), '');
    v_canonical := nullif(btrim(coalesce(v_column ->> 'canonical_field', '')), '');
    if v_heading is null then
      raise exception 'V1_BOQ_IMPORT_COLUMN_INVALID' using errcode = '22023';
    end if;
    if public.v1_required_boq_commercial_canonical(v_heading) is not null
      and (
        v_canonical is distinct from
          public.v1_required_boq_commercial_canonical(v_heading)
        or not coalesce((v_column ->> 'is_commercial')::boolean, false)
      )
      and (
        not coalesce((v_column ->> 'is_commercial')::boolean, false)
        or public.v1_has_capability('manage_commercials')
      ) then
      raise exception 'V1_BOQ_COMMERCIAL_CANONICAL_REQUIRES_CLASSIFICATION'
        using errcode = '22023';
    end if;
    if v_canonical in ('unit_cost', 'total_cost')
      and not coalesce((v_column ->> 'is_commercial')::boolean, false) then
      raise exception 'V1_BOQ_COMMERCIAL_CANONICAL_REQUIRES_CLASSIFICATION'
        using errcode = '22023';
    end if;
    if coalesce((v_column ->> 'is_commercial')::boolean, false)
      and not public.v1_has_capability('manage_commercials') then
      raise exception 'V1_BOQ_COMMERCIAL_IMPORT_DENIED' using errcode = '42501';
    end if;
    if v_canonical is not null and v_canonical not in (
      'description', 'size', 'model', 'equipment_tag', 'brand_origin', 'quantity', 'unit', 'unit_cost', 'total_cost', 'planning_model_tag'
    ) then
      raise exception 'V1_BOQ_IMPORT_COLUMN_INVALID' using errcode = '22023';
    end if;
  end loop;
  if exists (
    select 1
    from (
      select lower(btrim(value ->> 'heading')) as heading, count(*) as total
      from jsonb_array_elements(v_columns)
      group by lower(btrim(value ->> 'heading'))
    ) duplicate_heading
    where duplicate_heading.total > 1
  ) or exists (
    select 1
    from (
      select nullif(value ->> 'canonical_field', '') as canonical_field,
        count(*) as total
      from jsonb_array_elements(v_columns)
      where nullif(value ->> 'canonical_field', '') is not null
      group by nullif(value ->> 'canonical_field', '')
    ) duplicate_canonical
    where duplicate_canonical.total > 1
  ) then
    raise exception 'V1_BOQ_IMPORT_COLUMN_MAPPING_DUPLICATE' using errcode = '22023';
  end if;

  v_before := public.v1_boq_group_projection(v_group_id);
  v_save_response := public.v1_save_boq_worksheet(
    jsonb_build_object(
      'group_id', v_group_id,
      'expected_version', v_expected_version,
      'worksheet_title', v_title,
      'columns', v_columns,
      'rows', v_rows,
      'reason', 'Reviewed XLSX workbook import'
    ),
    gen_random_uuid()
  );
  v_source_projection := jsonb_build_object(
    'file_name', v_file_name,
    'worksheet_name', v_sheet_name,
    'header_row_number', v_header_row_number,
    'header_row_numbers', v_header_row_numbers,
    'header_hierarchy', v_header_hierarchy
  );
  update public.v1_boq_groups
     set last_imported_at = clock_timestamp(),
         last_imported_by_auth_user_id = auth.uid(),
         last_import_source = v_source_projection,
         updated_at = clock_timestamp()
   where id = v_group_id;
  perform public.v1_write_audit_event(
    'boq_import_committed', 'boq_group', v_group_id, v_group.project_id,
    v_before,
    jsonb_build_object(
      'source', v_source_projection,
      'record_version', v_expected_version + 1,
      'column_count', jsonb_array_length(v_columns),
      'row_count', jsonb_array_length(v_rows)
    ),
    'Reviewed XLSX workbook import', p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_import_boq_worksheet', p_idempotency_key, v_save_response
  );
  return v_save_response;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Self-check: every function now has main's fingerprint and main's grants.
do $check$
declare
  v_fingerprint constant jsonb := jsonb_build_object(
    'v1_material_search_normalize(text)', '351a0430756a5e2cb730ac22091901ee',
    'v1_material_search_synonyms(text)', '664152d721f94a1fcaeda2216f92462f',
    'v1_material_search_one_edit(text,text)', 'da4e7a95947adcd0d7af32e6b790bf83',
    'v1_search_material_request_candidates(uuid,uuid,text,integer)', '1f177e9087dee103fd7eb74b97649b58',
    'v1_search_company_material_request_candidates(uuid,uuid,text,integer)', '9d0e9f3888b285cd9bffa2f797de5780',
    'v1_material_request_overview(integer)', '83e9d3c1227b0baa191b966d8b8b95c5',
    'v1_material_request_submission_diagnostic(uuid,uuid,uuid)', 'd4c4af385dd1ac080362dc15a04779ba',
    'v1_can_confirm_material_return(uuid)', '99b6cbc8dcec9fb5272703afb5692b38',
    'app_role()', 'fe73549c0b069d7287eefe83082cc20d',
    'app_user_id()', 'e27089640fe1db6cd8203b747aa6e387',
    'notification_visible_to_caller(jsonb)', 'f5f29d8967430dd7aff95c03b079659d',
    'app_legacy_project_readable(jsonb)', '868de3343460e5f23dd2b6fb91cacb97',
    'app_legacy_project_writable(jsonb)', '2f9886f3dc5d8e9569ac11b1c983582e',
    'app_legacy_plan_readable(jsonb)', '4c419e9288ed298eea5958a05c222fd5',
    'app_legacy_plan_writable(jsonb)', '1bfe72c4ef608cfd9601b7a5cca8206d',
    'project_progress_definitions(jsonb)', '2669c15d30544e6d11170d8eb9abe73f',
    'project_require_approved_phase1()', '84228975d49436cb8d8b677d6749f2e4',
    'v1_create_document_version(uuid,text,bigint,text)', '468a0043e2754c640ddf4af5bea0e6c6',
    'v1_import_boq_worksheet(jsonb,uuid)', '6578655c386d24a1c22a84b3dfdeb173',
    'app_has_cap(text)', '52a353bc83eefc45e5ac91afb93a7acb',
    'app_touch_updated_at()', '76377695287d53f3bc550b0b8beb0a9c'
  );
  v_execute constant jsonb := jsonb_build_object(
    'v1_material_search_normalize(text)', '{"anon": false, "authenticated": false, "service_role": true}'::jsonb,
    'v1_material_search_synonyms(text)', '{"anon": false, "authenticated": false, "service_role": true}'::jsonb,
    'v1_material_search_one_edit(text,text)', '{"anon": false, "authenticated": false, "service_role": true}'::jsonb,
    'v1_search_material_request_candidates(uuid,uuid,text,integer)', '{"anon": false, "authenticated": true, "service_role": true}'::jsonb,
    'v1_search_company_material_request_candidates(uuid,uuid,text,integer)', '{"anon": false, "authenticated": true, "service_role": true}'::jsonb,
    'v1_material_request_overview(integer)', '{"anon": false, "authenticated": true, "service_role": true}'::jsonb,
    'v1_material_request_submission_diagnostic(uuid,uuid,uuid)', '{"anon": false, "authenticated": true, "service_role": true}'::jsonb,
    'v1_can_confirm_material_return(uuid)', '{"anon": false, "authenticated": false, "service_role": true}'::jsonb,
    'app_role()', '{"anon": false, "authenticated": true, "service_role": true}'::jsonb,
    'app_user_id()', '{"anon": false, "authenticated": true, "service_role": true}'::jsonb,
    'notification_visible_to_caller(jsonb)', '{"anon": false, "authenticated": true, "service_role": true}'::jsonb,
    'app_legacy_project_readable(jsonb)', '{"anon": false, "authenticated": true, "service_role": true}'::jsonb,
    'app_legacy_project_writable(jsonb)', '{"anon": false, "authenticated": true, "service_role": true}'::jsonb,
    'app_legacy_plan_readable(jsonb)', '{"anon": false, "authenticated": true, "service_role": true}'::jsonb,
    'app_legacy_plan_writable(jsonb)', '{"anon": false, "authenticated": true, "service_role": true}'::jsonb,
    'project_progress_definitions(jsonb)', '{"anon": false, "authenticated": true, "service_role": true}'::jsonb,
    'project_require_approved_phase1()', '{"anon": false, "authenticated": false, "service_role": true}'::jsonb,
    'v1_create_document_version(uuid,text,bigint,text)', '{"anon": false, "authenticated": false, "service_role": true}'::jsonb,
    'v1_import_boq_worksheet(jsonb,uuid)', '{"anon": false, "authenticated": true, "service_role": true}'::jsonb,
    'app_has_cap(text)', '{"anon": false, "authenticated": true, "service_role": true}'::jsonb,
    'app_touch_updated_at()', '{"anon": false, "authenticated": false, "service_role": true}'::jsonb
  );
  v_signature text;
  v_procedure regprocedure;
  v_role text;
begin
  for v_signature in select key from jsonb_each(v_fingerprint) loop
    v_procedure := to_regprocedure('public.' || v_signature);
    if v_procedure is null or (
      select md5(p.prosrc || coalesce(p.proconfig::text, '') || p.provolatile::text || p.prosecdef::text)
      from pg_catalog.pg_proc p where p.oid = v_procedure
    ) <> v_fingerprint ->> v_signature then
      raise exception 'function alignment self-check: public.% differs from main',
        v_signature;
    end if;
    foreach v_role in array array['anon', 'authenticated', 'service_role'] loop
      if has_function_privilege(v_role, v_procedure, 'execute')
        <> (v_execute -> v_signature ->> v_role)::boolean then
        raise exception
          'function alignment self-check: % execute on public.% differs from main',
          v_role, v_signature;
      end if;
    end loop;
    if exists (
      select 1
      from pg_catalog.pg_proc p,
        aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) grant_row
      where p.oid = v_procedure and grant_row.grantee = 0
    ) then
      raise exception 'function alignment self-check: PUBLIC may execute public.%',
        v_signature;
    end if;
    -- Security definer bodies run as their owner; main's owner is postgres.
    if (
      select pg_get_userbyid(p.proowner)
      from pg_catalog.pg_proc p where p.oid = v_procedure
    ) <> 'postgres' then
      raise exception 'function alignment self-check: public.% is not owned by postgres',
        v_signature;
    end if;
  end loop;
end;
$check$;

commit;

notify pgrst, 'reload schema';
