-- Task 01: bounded, role-safe discovery of operational progress evidence.
-- Additive read contract. Existing document, progress and revision IDs remain
-- unchanged. Only the current finalized version is returned; no version is
-- pinned by the existing progress command, which stores document IDs.
create or replace function public.v1_accounts_search_progress_evidence(
  p_project_id uuid,
  p_query text default null,
  p_selected_document_ids uuid[] default '{}'::uuid[],
  p_limit integer default 20
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_query text := nullif(btrim(p_query), '');
  v_hits jsonb;
  v_selected jsonb;
begin
  perform public.v1_accounts_require_capability(
    p_project_id, 'view_project_accounts'
  );
  if p_limit is null or p_limit not between 1 and 20
     or length(coalesce(v_query, '')) > 120
     or cardinality(coalesce(p_selected_document_ids, '{}'::uuid[])) > 256
     or array_position(p_selected_document_ids, null) is not null then
    raise exception 'R39_ACCOUNTS_EVIDENCE_SEARCH_INVALID'
      using errcode = '22023';
  end if;

  -- The predicate is evaluated on the server before LIMIT. In particular,
  -- an inaccessible cross-linked document never enters a client response.
  select coalesce(jsonb_agg(hit.item order by hit.uploaded_at desc, hit.id),
                  '[]'::jsonb)
    into v_hits
  from (
    select document.id, version.uploaded_at,
      jsonb_build_object(
        'id', document.id,
        'file_name', version.original_file_name,
        'reference', version.source_revision,
        'current_version_id', version.id,
        'revision_number', version.revision_number,
        'uploaded_at', version.uploaded_at,
        'mime_type', version.mime_type,
        'bucket_id', version.bucket_id,
        'object_path', version.object_path
      ) as item
    from public.v1_documents document
    join public.v1_document_versions version
      on version.id = document.current_version_id
    left join public.v1_accounts_document_metadata metadata
      on metadata.document_id = document.id
    where document.classification = 'operational'
      and metadata.archived_at is null
      and exists (
        select 1 from public.v1_document_links link
        where link.document_id = document.id
          and link.project_id = p_project_id
          and link.removed_at is null
      )
      and public.v1_document_readable(document.id)
      and (v_query is null
        or version.original_file_name ilike '%' || v_query || '%'
        or version.source_revision ilike '%' || v_query || '%')
    order by version.uploaded_at desc, document.id
    limit p_limit + 1
  ) hit;

  select coalesce(jsonb_agg(hit.item order by hit.uploaded_at desc, hit.id),
                  '[]'::jsonb)
    into v_selected
  from (
    select document.id, version.uploaded_at,
      jsonb_build_object(
        'id', document.id,
        'file_name', version.original_file_name,
        'reference', version.source_revision,
        'current_version_id', version.id,
        'revision_number', version.revision_number,
        'uploaded_at', version.uploaded_at,
        'mime_type', version.mime_type,
        'bucket_id', version.bucket_id,
        'object_path', version.object_path
      ) as item
    from public.v1_documents document
    join public.v1_document_versions version
      on version.id = document.current_version_id
    left join public.v1_accounts_document_metadata metadata
      on metadata.document_id = document.id
    where document.id = any(coalesce(p_selected_document_ids, '{}'::uuid[]))
      and document.classification = 'operational'
      and metadata.archived_at is null
      and exists (
        select 1 from public.v1_document_links link
        where link.document_id = document.id
          and link.project_id = p_project_id
          and link.removed_at is null
      )
      and public.v1_document_readable(document.id)
    order by version.uploaded_at desc, document.id
    limit 256
  ) hit;

  return jsonb_build_object(
    'project_id', p_project_id,
    'documents', (select coalesce(jsonb_agg(item), '[]'::jsonb)
      from jsonb_array_elements(v_hits) with ordinality as result(item, index)
      where index <= p_limit),
    'has_more', jsonb_array_length(v_hits) > p_limit,
    'selected', v_selected
  );
end;
$$;

revoke all on function public.v1_accounts_search_progress_evidence(
  uuid, text, uuid[], integer
) from public, anon, authenticated;
grant execute on function public.v1_accounts_search_progress_evidence(
  uuid, text, uuid[], integer
) to authenticated;

-- Progress commands must apply the same all-links document authorization as
-- discovery and Storage. A project link alone cannot make a document safe.
create or replace function public.v1_accounts_validate_evidence_documents(
  p_project_id uuid,
  p_document_ids uuid[]
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_ids uuid[] := public.v1_accounts_canonical_evidence_ids(p_document_ids);
begin
  if cardinality(v_ids) = 0 then return; end if;
  if (
    select count(*)
    from public.v1_documents document
    left join public.v1_accounts_document_metadata metadata
      on metadata.document_id = document.id
    where document.id = any(v_ids)
      and document.current_version_id is not null
      and document.classification = 'operational'
      and metadata.archived_at is null
      and exists (
        select 1 from public.v1_document_links link
        where link.document_id = document.id
          and link.project_id = p_project_id
          and link.removed_at is null
      )
      and public.v1_document_readable(document.id)
  ) <> cardinality(v_ids) then
    raise exception 'R39_ACCOUNTS_EVIDENCE_DOCUMENT_INVALID'
      using errcode = '22023';
  end if;
end;
$$;

revoke all on function public.v1_accounts_validate_evidence_documents(uuid,uuid[])
  from public, anon, authenticated;
