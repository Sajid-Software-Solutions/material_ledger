-- Additive material search quality. Existing request/scope/category authorization
-- and non-commercial response fields remain unchanged. No stock inference,
-- workflow data, RLS policy, timeout or commercial access changes.
-- Rollback: restore the two prior RPC bodies; keep private pure helpers until
-- all consumers are restored. New clients accept old responses without match_path.

create or replace function public.v1_material_search_normalize(p_value text)
returns text language sql immutable strict parallel safe set search_path='' as $$
  select btrim(lower(regexp_replace(p_value,'[^[:alnum:]]+',' ','g')));
$$;
create or replace function public.v1_material_search_synonyms(p_value text)
returns text language plpgsql immutable strict parallel safe set search_path='' as $$
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
$$;
create or replace function public.v1_material_search_one_edit(p_left text,p_right text)
returns boolean language plpgsql immutable strict parallel safe set search_path='' as $$
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
$$;
revoke all on function public.v1_material_search_normalize(text),
  public.v1_material_search_synonyms(text),public.v1_material_search_one_edit(text,text)
  from public,anon,authenticated;
grant execute on function public.v1_material_search_normalize(text),
  public.v1_material_search_synonyms(text),public.v1_material_search_one_edit(text,text) to service_role;
create or replace function public.v1_search_material_request_candidates(
  p_project_id uuid,p_scope_id uuid,p_query text,p_limit integer default 18
) returns jsonb language plpgsql stable security definer set search_path='' as $$
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
$$;
create or replace function public.v1_search_company_material_request_candidates(
  p_category_id uuid,p_responsible_unit_id uuid,p_query text,p_limit integer default 18
) returns jsonb language plpgsql stable security definer set search_path='' as $$
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
$$;
revoke all on function public.v1_search_material_request_candidates(uuid,uuid,text,integer),
  public.v1_search_company_material_request_candidates(uuid,uuid,text,integer) from public,anon;
grant execute on function public.v1_search_material_request_candidates(uuid,uuid,text,integer),
  public.v1_search_company_material_request_candidates(uuid,uuid,text,integer) to authenticated;
