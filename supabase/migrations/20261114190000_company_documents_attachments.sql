-- Company documents: an Attachments section on every company record
-- (owner decision, 14 November 2026; PRODUCT_DECISIONS section 48).
--
-- Holders of company_documents.manage (PR, Admin and the Accountant by
-- default) attach the files of a record's documents: the trade licence, an
-- establishment card, a vehicle registration (mulkiya), an Asateel permit,
-- a CICPA pass or LOA, an insurance policy, a certificate. A file may say
-- which of the record's documents it is a copy of. Everyone who may read
-- Company documents (company_documents.view) sees and opens them; no one
-- else can, whatever path they know.
--
-- Files live in the private bucket yorks-company-files at
-- company/<record id>/<attachment id>.<ext>. A stored file is never
-- overwritten or deleted: removing an attachment hides it with a reason and
-- keeps the file, the row and the history.
--
-- Data preservation: additive (one bucket, one table, functions, two
-- storage policies; the record history accepts attachment entries).
-- Rollback: drop the two storage policies and revoke the four commands;
-- keep the bucket, the table and every file.

begin;

-- ---------------------------------------------------------------------------
-- 1. Storage and table.
-- ---------------------------------------------------------------------------

insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
values (
  'yorks-company-files', 'yorks-company-files', false, 20971520,
  array[
    'application/pdf', 'image/jpeg', 'image/png',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  ]
)
on conflict (id) do nothing;

create table if not exists public.v1_company_docs_attachments (
  id uuid primary key,
  record_id uuid not null
    references public.v1_company_docs_records (id) on delete restrict,
  -- The record's document this file is a copy of, if any.
  document_id uuid references public.v1_company_docs_documents (id)
    on delete restrict,
  title text check (
    title is null or (btrim(title) <> '' and char_length(title) <= 120)
  ),
  file_name text not null check (
    btrim(file_name) <> '' and char_length(file_name) <= 200
  ),
  content_type text not null check (content_type in (
    'application/pdf', 'image/jpeg', 'image/png',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  )),
  size_bytes bigint not null check (size_bytes > 0 and size_bytes <= 20971520),
  object_path text not null unique,
  uploaded_by_auth_user_id uuid not null
    references public.v1_profiles (auth_user_id) on delete restrict,
  uploaded_by_role text not null check (btrim(uploaded_by_role) <> ''),
  uploaded_at timestamptz not null default clock_timestamp(),
  removed_at timestamptz,
  removed_by_auth_user_id uuid
    references public.v1_profiles (auth_user_id) on delete restrict,
  removed_reason text check (
    removed_reason is null
    or (btrim(removed_reason) <> '' and char_length(removed_reason) <= 500)
  ),
  check ((removed_at is null) = (removed_by_auth_user_id is null)),
  check ((removed_at is null) = (removed_reason is null))
);
create index if not exists v1_company_docs_attachments_record_idx
  on public.v1_company_docs_attachments (record_id, uploaded_at desc)
  where removed_at is null;

drop trigger if exists v1_company_docs_attachments_no_delete
  on public.v1_company_docs_attachments;
create trigger v1_company_docs_attachments_no_delete
  before delete on public.v1_company_docs_attachments
  for each row execute function public.v1_company_docs_block_history_change();

alter table public.v1_company_docs_attachments enable row level security;
revoke all on table public.v1_company_docs_attachments
  from public, anon, authenticated;

-- The record's history records attachments too.
alter table public.v1_company_docs_revisions
  drop constraint if exists v1_company_docs_revisions_entity_check;
alter table public.v1_company_docs_revisions
  add constraint v1_company_docs_revisions_entity_check
  check (entity in ('record', 'document', 'attachment'));
alter table public.v1_company_docs_revisions
  drop constraint if exists v1_company_docs_revisions_action_check;
alter table public.v1_company_docs_revisions
  add constraint v1_company_docs_revisions_action_check
  check (action in (
    'created', 'updated', 'renewed', 'ended', 'imported', 'archived',
    'restored', 'added', 'removed'
  ));

-- ---------------------------------------------------------------------------
-- 2. Storage authorization: by capability and recorded attachment, never by
--    knowledge of a path.
-- ---------------------------------------------------------------------------

create or replace function public.v1_company_file_path_record_id(
  p_bucket_id text,
  p_object_path text
)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select case
    when p_bucket_id = 'yorks-company-files'
      and p_object_path ~ '^company/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(pdf|jpg|png|docx|xlsx)$'
    then split_part(p_object_path, '/', 2)::uuid
    else null
  end;
$$;

-- Readable: a recorded, current attachment, for company_documents.view.
create or replace function public.v1_company_file_readable(
  p_bucket_id text,
  p_object_path text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.v1_company_file_path_record_id(p_bucket_id, p_object_path)
      is not null
    and exists (
      select 1 from public.v1_company_docs_attachments attachment
      where attachment.object_path = p_object_path
        and attachment.removed_at is null
    )
    and public.v1_current_user_has_capability('company_documents.view', null);
$$;

-- Writable: a new file for an existing record, for company_documents.manage.
-- A recorded file is never replaced.
create or replace function public.v1_company_file_writable(
  p_bucket_id text,
  p_object_path text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
      select 1 from public.v1_company_docs_records record
      where record.id = public.v1_company_file_path_record_id(
        p_bucket_id, p_object_path
      )
    )
    and not exists (
      select 1 from public.v1_company_docs_attachments attachment
      where attachment.object_path = p_object_path
    )
    and public.v1_current_user_has_capability('company_documents.manage', null);
$$;

drop policy if exists v1_company_file_select on storage.objects;
create policy v1_company_file_select
on storage.objects for select to authenticated
using (public.v1_company_file_readable(bucket_id, name));

drop policy if exists v1_company_file_insert on storage.objects;
create policy v1_company_file_insert
on storage.objects for insert to authenticated
with check (public.v1_company_file_writable(bucket_id, name));

-- ---------------------------------------------------------------------------
-- 3. Projections.
-- ---------------------------------------------------------------------------

create or replace function public.v1_company_docs_attachments_json(
  p_record_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'schema_version', 'yorks.company.attachments.v1',
    'record_id', p_record_id,
    'can_manage', public.v1_current_user_has_capability(
      'company_documents.manage', null
    ),
    'attachments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', attachment.id,
        'document_id', attachment.document_id,
        'document_kind', document.kind,
        'document_label', document.label,
        'document_number', document.document_number,
        'document_current', document.is_current,
        'title', attachment.title,
        'file_name', attachment.file_name,
        'content_type', attachment.content_type,
        'size_bytes', attachment.size_bytes,
        'object_path', attachment.object_path,
        'uploaded_by', public.v1_wf_display_name(
          attachment.uploaded_by_auth_user_id
        ),
        'uploaded_by_role', attachment.uploaded_by_role,
        'uploaded_at', attachment.uploaded_at
      ) order by attachment.uploaded_at desc, attachment.id)
      from public.v1_company_docs_attachments attachment
      left join public.v1_company_docs_documents document
        on document.id = attachment.document_id
      where attachment.record_id = p_record_id
        and attachment.removed_at is null
    ), '[]'::jsonb)
  );
$$;

-- ---------------------------------------------------------------------------
-- 4. Reads.
-- ---------------------------------------------------------------------------

create or replace function public.v1_company_docs_list_attachments(
  p_record_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform public.v1_company_docs_assert('company_documents.view');
  if not exists (
    select 1 from public.v1_company_docs_records record
    where record.id = p_record_id
  ) then
    raise exception 'V1_COMPANY_DOCS_NOT_FOUND' using errcode = 'P0002';
  end if;
  return public.v1_company_docs_attachments_json(p_record_id);
end;
$$;

-- How many files each record has, for the paperclip in the registers.
create or replace function public.v1_company_docs_attachment_counts()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform public.v1_company_docs_assert('company_documents.view');
  return jsonb_build_object(
    'schema_version', 'yorks.company.attachment_counts.v1',
    'counts', coalesce((
      select jsonb_object_agg(counts.record_id, counts.total)
      from (
        select attachment.record_id, count(*)::integer as total
        from public.v1_company_docs_attachments attachment
        where attachment.removed_at is null
        group by attachment.record_id
      ) counts
    ), '{}'::jsonb)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Writes.
-- ---------------------------------------------------------------------------

-- Records a file already stored at company/<record>/<attachment>.<ext>.
-- Size and type are read from storage, not trusted from the caller.
create or replace function public.v1_company_docs_add_attachment(
  p_record_id uuid,
  p_payload jsonb,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.v1_company_docs_assert('company_documents.manage');
  v_role text := public.v1_current_exact_role();
  v_existing jsonb;
  v_path text := btrim(coalesce(p_payload ->> 'object_path', ''));
  v_name text := btrim(coalesce(p_payload ->> 'file_name', ''));
  v_title text := nullif(btrim(coalesce(p_payload ->> 'title', '')), '');
  v_document uuid;
  v_kind text;
  v_type text;
  v_size bigint;
  v_id uuid;
begin
  if p_idempotency_key is null or p_record_id is null
    or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'V1_COMPANY_DOCS_ATTACHMENT_INVALID' using errcode = '22023';
  end if;
  perform public.v1_assert_object_keys(
    p_payload,
    array['object_path', 'file_name', 'document_id', 'title'],
    'company_attachment_payload'
  );
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_company_docs_add_attachment', p_idempotency_key,
    jsonb_build_object('record', p_record_id, 'payload', p_payload)
  );
  if v_existing is not null then
    return public.v1_company_docs_attachments_json(p_record_id);
  end if;

  begin
    v_document := nullif(p_payload ->> 'document_id', '')::uuid;
  exception when others then
    raise exception 'V1_COMPANY_DOCS_ATTACHMENT_INVALID' using errcode = '22023';
  end;
  if public.v1_company_file_path_record_id('yorks-company-files', v_path)
      is distinct from p_record_id
    or v_name = '' or char_length(v_name) > 200
    or (v_title is not null and char_length(v_title) > 120) then
    raise exception 'V1_COMPANY_DOCS_ATTACHMENT_INVALID' using errcode = '22023';
  end if;

  -- The file must already be stored there.
  select object.metadata ->> 'mimetype',
    nullif(object.metadata ->> 'size', '')::bigint
  into v_type, v_size
  from storage.objects object
  where object.bucket_id = 'yorks-company-files' and object.name = v_path;
  if not found then
    raise exception 'V1_COMPANY_DOCS_ATTACHMENT_NOT_STORED'
      using errcode = '22023';
  end if;
  if v_type is null or v_type not in (
      'application/pdf', 'image/jpeg', 'image/png',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    )
    or v_size is null or v_size <= 0 or v_size > 20971520 then
    raise exception 'V1_COMPANY_DOCS_ATTACHMENT_INVALID' using errcode = '22023';
  end if;

  perform 1 from public.v1_company_docs_records record
  where record.id = p_record_id for update;
  if not found then
    raise exception 'V1_COMPANY_DOCS_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_document is not null then
    select document.kind into v_kind
    from public.v1_company_docs_documents document
    where document.id = v_document and document.record_id = p_record_id;
    if not found then
      raise exception 'V1_COMPANY_DOCS_ATTACHMENT_INVALID'
        using errcode = '22023';
    end if;
  end if;

  v_id := split_part(split_part(v_path, '/', 3), '.', 1)::uuid;
  insert into public.v1_company_docs_attachments (
    id, record_id, document_id, title, file_name, content_type, size_bytes,
    object_path, uploaded_by_auth_user_id, uploaded_by_role
  ) values (
    v_id, p_record_id, v_document, v_title, v_name, v_type, v_size, v_path,
    v_actor, v_role
  )
  on conflict (object_path) do nothing;
  if found then
    perform public.v1_company_docs_revision(
      p_record_id, 'attachment', v_id, 'added', null,
      jsonb_build_object(
        'file_name', v_name, 'title', v_title, 'kind', v_kind,
        'document_id', v_document
      ),
      null, v_actor, v_role, p_idempotency_key
    );
  end if;
  perform public.v1_complete_idempotency(
    'v1_company_docs_add_attachment', p_idempotency_key,
    jsonb_build_object('attachment_id', v_id)
  );
  return public.v1_company_docs_attachments_json(p_record_id);
end;
$$;

-- Hides an attachment with a reason. The file, the row and the history stay.
create or replace function public.v1_company_docs_remove_attachment(
  p_attachment_id uuid,
  p_reason text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.v1_company_docs_assert('company_documents.manage');
  v_role text := public.v1_current_exact_role();
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_existing jsonb;
  v_attachment public.v1_company_docs_attachments%rowtype;
begin
  if p_idempotency_key is null or p_attachment_id is null then
    raise exception 'V1_COMPANY_DOCS_ATTACHMENT_INVALID' using errcode = '22023';
  end if;
  if v_reason is null or char_length(v_reason) > 500 then
    raise exception 'V1_COMPANY_DOCS_REASON_REQUIRED' using errcode = '22023';
  end if;
  select * into v_attachment
  from public.v1_company_docs_attachments attachment
  where attachment.id = p_attachment_id
  for update;
  if not found then
    raise exception 'V1_COMPANY_DOCS_NOT_FOUND' using errcode = 'P0002';
  end if;
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_company_docs_remove_attachment', p_idempotency_key,
    jsonb_build_object('attachment', p_attachment_id, 'reason', v_reason)
  );
  if v_existing is not null or v_attachment.removed_at is not null then
    return public.v1_company_docs_attachments_json(v_attachment.record_id);
  end if;
  update public.v1_company_docs_attachments
  set removed_at = clock_timestamp(),
      removed_by_auth_user_id = v_actor,
      removed_reason = v_reason
  where id = p_attachment_id;
  perform public.v1_company_docs_revision(
    v_attachment.record_id, 'attachment', p_attachment_id, 'removed',
    jsonb_build_object(
      'file_name', v_attachment.file_name, 'title', v_attachment.title
    ),
    jsonb_build_object(
      'file_name', v_attachment.file_name, 'title', v_attachment.title,
      'kind', (
        select document.kind from public.v1_company_docs_documents document
        where document.id = v_attachment.document_id
      )
    ),
    v_reason, v_actor, v_role, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_company_docs_remove_attachment', p_idempotency_key,
    jsonb_build_object('attachment_id', p_attachment_id)
  );
  return public.v1_company_docs_attachments_json(v_attachment.record_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Grants.
-- ---------------------------------------------------------------------------

revoke all on function public.v1_company_file_path_record_id(text, text)
  from public, anon;
revoke all on function public.v1_company_file_readable(text, text)
  from public, anon;
revoke all on function public.v1_company_file_writable(text, text)
  from public, anon;
revoke all on function public.v1_company_docs_attachments_json(uuid)
  from public, anon, authenticated;

do $grants$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'v1_company_docs_list_attachments(uuid)',
    'v1_company_docs_attachment_counts()',
    'v1_company_docs_add_attachment(uuid,jsonb,uuid)',
    'v1_company_docs_remove_attachment(uuid,text,uuid)'
  ] loop
    execute format(
      'revoke all on function public.%s from public, anon', v_signature
    );
    execute format(
      'grant execute on function public.%s to authenticated', v_signature
    );
  end loop;
end;
$grants$;

commit;

notify pgrst, 'reload schema';
