-- R39 Accounts Workspace V2 — P5: only offer records a person may attach a file to
--
-- v1_get_accounts_documents offered every record on the project as an upload
-- target, including ones the actor may not write to. An Accountant picking the
-- first one, the contract baseline, was refused only after choosing a file.
-- The list now holds what v1_prepare_accounts_document_upload would accept, using
-- the same rule, so nothing widens: this only removes choices that always failed.
--
-- Additive: CREATE OR REPLACE of one read. No table or row changes.
-- Rollback: re-apply the function from
-- 20260826150000_yorks_r39_accounts_t06_documents_audit_exports.sql.

create or replace function public.v1_get_accounts_documents(
  p_project_id uuid,
  p_search text default null,
  p_document_type text default null,
  p_include_archived boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_documents jsonb;
  v_targets jsonb;
begin
  perform public.v1_accounts_require_capability(p_project_id,'view_project_accounts');
  if p_document_type is not null and p_document_type not in (
    'contract','contract_variation','progress_evidence','client_claim',
    'client_invoice','client_certification','payment_certificate','pdc_copy',
    'payment_receipt','supplier_invoice','po_lpo','delivery_receipt',
    'payment_advice','commercial_correspondence','other'
  ) then raise exception 'R39_ACCOUNTS_DOCUMENT_TYPE_INVALID' using errcode='22023'; end if;
  select coalesce(jsonb_agg(item order by uploaded_at desc,document_id),'[]'::jsonb)
    into v_documents from (
    select document_record.id as document_id,version_record.uploaded_at,
      jsonb_build_object(
        'id',document_record.id,'classification',document_record.classification,
        'accounts_document_type',metadata.document_type,
        'created_at',document_record.created_at,
        'archived',metadata.archived_at is not null,
        'current_version',jsonb_build_object(
          'id',version_record.id,'revision_number',version_record.revision_number,
          'bucket_id',version_record.bucket_id,'object_path',version_record.object_path,
          'original_file_name',version_record.original_file_name,
          'mime_type',version_record.mime_type,'byte_size',version_record.byte_size,
          'sha256',version_record.sha256,'origin',version_record.origin,
          'source_entity_type',version_record.source_entity_type,
          'source_entity_id',version_record.source_entity_id,
          'source_revision',version_record.source_revision,
          'uploaded_at',version_record.uploaded_at,
          'uploaded_by_auth_user_id',version_record.uploaded_by_auth_user_id,
          'uploaded_by_role',version_record.uploaded_by_role,
          'uploaded_by_display_name',public.v1_safe_profile_display_name(
            uploader.display_name,uploader.auth_user_id
          )
        ),
        'versions',(select coalesce(jsonb_agg(jsonb_build_object(
          'id',history.id,'revision_number',history.revision_number,
          'bucket_id',history.bucket_id,'object_path',history.object_path,
          'original_file_name',history.original_file_name,'mime_type',history.mime_type,
          'byte_size',history.byte_size,'sha256',history.sha256,'origin',history.origin,
          'source_entity_type',history.source_entity_type,
          'source_entity_id',history.source_entity_id,
          'source_revision',history.source_revision,'uploaded_at',history.uploaded_at,
          'uploaded_by_auth_user_id',history.uploaded_by_auth_user_id,
          'uploaded_by_role',history.uploaded_by_role,
          'uploaded_by_display_name',public.v1_safe_profile_display_name(
            history_profile.display_name,history_profile.auth_user_id
          )) order by history.revision_number desc),'[]'::jsonb)
          from public.v1_document_versions history
          join public.v1_profiles history_profile
            on history_profile.auth_user_id=history.uploaded_by_auth_user_id
          where history.document_id=document_record.id),
        'links',(select coalesce(jsonb_agg(jsonb_build_object(
          'id',link.id,'project_id',link.project_id,'entity_type',link.entity_type,
          'entity_id',link.entity_id,'linked_at',link.linked_at,
          'cross_project_reason',link.cross_project_reason
        ) order by link.linked_at),'[]'::jsonb)
          from public.v1_document_links link where link.document_id=document_record.id
            and link.removed_at is null)
      ) as item
    from public.v1_accounts_document_metadata metadata
    join public.v1_documents document_record on document_record.id=metadata.document_id
    join public.v1_document_versions version_record
      on version_record.id=document_record.current_version_id
    join public.v1_profiles uploader
      on uploader.auth_user_id=version_record.uploaded_by_auth_user_id
    where (p_include_archived or metadata.archived_at is null)
      and (p_document_type is null or metadata.document_type=p_document_type)
      and (p_search is null or btrim(p_search)='' or
        version_record.original_file_name ilike '%'||btrim(p_search)||'%' or
        metadata.document_type ilike '%'||btrim(p_search)||'%')
      and exists(select 1 from public.v1_document_links link
        where link.document_id=document_record.id and link.project_id=p_project_id
          and link.removed_at is null)
      and public.v1_document_readable(document_record.id)
  ) visible;

  select coalesce(jsonb_agg(target order by target->>'label'),'[]'::jsonb)
    into v_targets from (
    select jsonb_build_object('entity_type','accounts_baseline_revision',
      'entity_id',baseline.id,'label','Baseline revision '||baseline.revision_number) target
    from public.v1_accounts_project_commercial_profiles profile
    join public.v1_accounts_baseline_revisions baseline
      on baseline.id=profile.current_baseline_revision_id
    where profile.project_id=p_project_id
    union all
    select jsonb_build_object('entity_type','accounts_client_claim','entity_id',id,
      'label','Claim · '||claim_reference)
    from public.v1_accounts_client_claims where project_id=p_project_id and status<>'cancelled'
    union all
    select jsonb_build_object('entity_type','accounts_client_invoice','entity_id',id,
      'label','Invoice · '||invoice_reference)
    from public.v1_accounts_client_invoices where project_id=p_project_id and status<>'cancelled'
    union all
    select jsonb_build_object('entity_type','accounts_client_pdc','entity_id',id,
      'label','PDC · '||cheque_number)
    from public.v1_accounts_client_pdcs where project_id=p_project_id and status<>'cancelled'
    union all
    select jsonb_build_object('entity_type','accounts_supplier_bill','entity_id',id,
      'label','Supplier invoice · '||supplier_invoice_reference)
    from public.v1_accounts_supplier_bills where project_id=p_project_id and status<>'cancelled'
  ) target_rows
  where public.v1_accounts_document_target_writable(
    target->>'entity_type',(target->>'entity_id')::uuid
  );
  return jsonb_build_object(
    'schema_version',6,'project_id',p_project_id,'documents',v_documents,
    'upload_targets',v_targets,
    'can_upload',exists(select 1 from jsonb_array_elements(v_targets) target
      where public.v1_accounts_document_target_writable(
        target->>'entity_type',(target->>'entity_id')::uuid
      ))
  );
end;
$$;
