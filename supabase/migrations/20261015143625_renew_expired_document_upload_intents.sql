-- Renew the original immutable upload only after server-confirmed expiry.
-- Preservation: no intent, object, key, document/version or metadata is replaced.
-- The existing finalizer takes this same row lock before checking finalized_at
-- and expiry. Competing resumers/finalizers therefore converge on one version.
-- Rollback: stop calling this additive RPC; retain intents and all upload history.

create or replace function public.v1_resume_document_upload(
  p_upload_intent_id uuid,
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
  v_intent public.v1_document_upload_intents%rowtype;
begin
  if v_actor is null or v_role = '' or not public.v1_current_actor_is_active() then
    raise exception 'V1_ACTIVE_ACTOR_REQUIRED' using errcode = '42501';
  end if;
  select * into v_intent
  from public.v1_document_upload_intents
  where id = p_upload_intent_id and actor_auth_user_id = v_actor
    and idempotency_key = p_idempotency_key
  for update;
  if not found or v_intent.actor_role <> v_role then
    raise exception 'V1_DOCUMENT_UPLOAD_INTENT_RESUME_DENIED' using errcode = '42501';
  end if;

  if v_intent.finalized_at is not null then
    -- A finalizer may have won the lock while this request was in flight.
    -- Its exact receipt is authoritative even after the old deadline.
    if not public.v1_document_readable(v_intent.finalized_document_id) then
      raise exception 'V1_DOCUMENT_UPLOAD_INTENT_RESUME_DENIED' using errcode = '42501';
    end if;
  else
    -- Recheck today's target/classification/record authority, including supplier,
    -- rental and Accounts scope. Owning an old intent never grants new access.
    if not public.v1_document_target_writable(
      v_intent.target_entity_type, v_intent.target_entity_id, v_intent.classification
    ) or (v_intent.document_id is not null and
      not public.v1_document_writable(v_intent.document_id)) then
      raise exception 'V1_DOCUMENT_UPLOAD_INTENT_RESUME_DENIED' using errcode = '42501';
    end if;
    if v_intent.document_id is not null and exists (
      select 1 from public.v1_document_versions
      where document_id = v_intent.document_id
        and revision_number >= v_intent.planned_revision_number
    ) then
      -- Another separately reviewed replacement already owns that revision.
      -- Do not renew or silently append a different version under this key.
      raise exception 'V1_DOCUMENT_UPLOAD_VERSION_CONFLICT' using errcode = '40001';
    end if;
    if v_intent.expires_at <= clock_timestamp() then
      update public.v1_document_upload_intents
      set expires_at = clock_timestamp() + interval '15 minutes'
      where id = v_intent.id
      returning * into v_intent;
    end if;
  end if;

  return jsonb_build_object(
    'upload_intent_id', v_intent.id,
    'bucket_id', v_intent.bucket_id,
    'object_path', v_intent.object_path,
    'mime_type', v_intent.mime_type,
    'byte_size', v_intent.byte_size,
    'expires_at', v_intent.expires_at,
    'planned_revision_number', v_intent.planned_revision_number,
    'finalized_document_id', v_intent.finalized_document_id,
    'finalized_version_id', v_intent.finalized_version_id
  );
end;
$$;

revoke all on function public.v1_resume_document_upload(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.v1_resume_document_upload(uuid, uuid)
  to authenticated;
