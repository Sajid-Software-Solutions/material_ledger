-- People: the profession on the visa and ID, apart from the position held
-- in the company (owner decision, 14 November 2026; PRODUCT_DECISIONS
-- section 53).
--
--   * A person keeps two: the profession written on their visa and Emirates
--     ID (`v1_people_profiles.id_profession`), and their position in the
--     company (the Workforce designation, used across Workforce). Example:
--     Mechanical Engineer on the ID, Project Engineer in the company.
--   * The staff tracker's Profession column is the one on the visa: an
--     import fills a blank profession on ID and never overwrites one kept
--     here. A "Position in Company" column, when the sheet has one, gives a
--     new person's designation.
--   * Saving a person from an older screen that does not send the
--     profession on ID keeps it.
--
-- Data preservation: no designation changes. Every People record's
-- profession on ID starts as its current designation, which until now was
-- the tracker's Profession (or what was typed as "Profession"), so nothing
-- is lost; a designation of "Not recorded" leaves it blank. Only the new
-- column is written; no history row or version changes.
-- Rollback: restore the three functions from 20261114120000; the column
-- may stay (nullable, unused).

begin;

alter table public.v1_people_profiles
  add column if not exists id_profession text;

do $schema$
begin
  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conname = 'v1_people_profiles_id_profession_check'
  ) then
    alter table public.v1_people_profiles
      add constraint v1_people_profiles_id_profession_check check (
        id_profession is null
        or (btrim(id_profession) <> '' and char_length(id_profession) <= 120)
      );
  end if;
end;
$schema$;

-- Every People record's profession on ID starts as its current designation.
update public.v1_people_profiles profile
set id_profession = left(btrim(worker.designation), 120)
from public.v1_workforce_workers worker
where worker.id = profile.worker_id
  and profile.id_profession is null
  and btrim(coalesce(worker.designation, '')) not in ('', 'Not recorded');

create or replace function public.v1_people_person_json(
  p_worker_id uuid,
  p_detail boolean
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with today as (select public.v1_wf_today() as day)
  select jsonb_build_object(
    'id', worker.id,
    'number', worker.worker_number,
    'name', worker.full_name,
    'company', worker.employer_company,
    'profession', worker.designation,
    'id_profession', profile.id_profession,
    'status', worker.current_status,
    'worker_type', worker.worker_type,
    'joining_date', worker.joining_date,
    'mobile', worker.mobile_number,
    'category', coalesce(profile.category, 'labour'),
    'has_profile', profile.worker_id is not null,
    'arabic_name', profile.arabic_name,
    'date_of_birth', profile.date_of_birth,
    'unified_number', profile.unified_number,
    'source_note', profile.source_note,
    'record_version', coalesce(profile.record_version, 0),
    'updated_at', greatest(worker.updated_at, profile.updated_at),
    'documents', coalesce((
      select jsonb_agg(
        public.v1_people_document_json(document, today.day)
        order by public.v1_people_kind_order(document.kind),
          document.expiry_date nulls last, document.created_at
      )
      from public.v1_people_documents document
      where document.worker_id = worker.id and document.is_current
    ), '[]'::jsonb),
    'attention', coalesce((
      select case
        when bool_or(document.expiry_date < today.day) then 'expired'
        when bool_or(document.expiry_date <= today.day + 60) then 'expiring'
        else 'ok'
      end
      from public.v1_people_documents document
      where document.worker_id = worker.id and document.is_current
        and document.expiry_date is not null
    ), 'ok'),
    'next_expiry', (
      select jsonb_build_object(
        'kind', document.kind, 'label', document.label,
        'expiry_date', document.expiry_date,
        'days_left', document.expiry_date - today.day
      )
      from public.v1_people_documents document
      where document.worker_id = worker.id and document.is_current
        and document.expiry_date is not null
      order by document.expiry_date
      limit 1
    ),
    'crew', (
      select jsonb_build_object('id', team.id, 'name', team.team_name)
      from public.v1_workforce_crew_members member
      join public.v1_workforce_teams team on team.id = member.team_id
      where member.worker_id = worker.id and member.removed_at is null
      limit 1
    ),
    'previous_documents', case when p_detail then coalesce((
      select jsonb_agg(
        public.v1_people_document_json(document, today.day)
        order by document.updated_at desc
      )
      from public.v1_people_documents document
      where document.worker_id = worker.id and not document.is_current
    ), '[]'::jsonb) end,
    'history', case when p_detail then coalesce((
      select jsonb_agg(item order by (item ->> 'id')::bigint desc)
      from (
        select jsonb_build_object(
          'id', revision.id,
          'entity', revision.entity,
          'action', revision.action,
          'kind', coalesce(
            revision.after_data ->> 'kind', revision.before_data ->> 'kind'
          ),
          'changed', (
            select coalesce(jsonb_agg(key order by key), '[]'::jsonb)
            from jsonb_object_keys(revision.after_data) key
            where key not in ('record_version', 'updated_at')
              and revision.after_data -> key
                is distinct from coalesce(revision.before_data, '{}'::jsonb)
                  -> key
          ),
          'reason', revision.reason,
          'actor_name', public.v1_wf_display_name(revision.actor_auth_user_id),
          'actor_role', revision.actor_role,
          'at', revision.created_at
        ) as item
        from public.v1_people_revisions revision
        where revision.worker_id = worker.id
        order by revision.id desc
        limit 100
      ) recent
    ), '[]'::jsonb) end
  )
  from public.v1_workforce_workers worker
  cross join today
  left join public.v1_people_profiles profile
    on profile.worker_id = worker.id
  where worker.id = p_worker_id;
$$;

create or replace function public.v1_people_save_person(
  p_payload jsonb,
  p_expected_version bigint,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.v1_people_assert('people_records.manage');
  v_role text := public.v1_current_exact_role();
  v_existing jsonb;
  v_worker_id uuid := nullif(p_payload ->> 'worker_id', '')::uuid;
  v_worker public.v1_workforce_workers%rowtype;
  v_profile public.v1_people_profiles%rowtype;
  v_name text := btrim(coalesce(p_payload ->> 'full_name', ''));
  v_company text := btrim(coalesce(p_payload ->> 'employer_company', ''));
  v_designation text := coalesce(
    nullif(btrim(coalesce(p_payload ->> 'designation', '')), ''),
    'Not recorded'
  );
  v_category text := coalesce(nullif(p_payload ->> 'category', ''), 'labour');
  v_arabic text := nullif(btrim(coalesce(p_payload ->> 'arabic_name', '')), '');
  v_dob date := nullif(p_payload ->> 'date_of_birth', '')::date;
  v_unified text := nullif(
    btrim(coalesce(p_payload ->> 'unified_number', '')), ''
  );
  v_mobile text := nullif(btrim(coalesce(p_payload ->> 'mobile_number', '')), '');
  v_joining date := coalesce(
    nullif(p_payload ->> 'joining_date', '')::date, public.v1_wf_today()
  );
  v_before jsonb;
  v_after jsonb;
  -- The profession written on the visa and ID; the designation is the
  -- position held in the company.
  v_id_profession text := nullif(
    btrim(coalesce(p_payload ->> 'id_profession', '')), ''
  );
begin
  v_existing := public.v1_idempotency_get_or_claim(
    'v1_people_save_person', p_idempotency_key,
    jsonb_build_object('payload', p_payload, 'expected', p_expected_version)
  );
  if v_existing is not null then
    return public.v1_people_person_json(
      (v_existing ->> 'worker_id')::uuid, true
    );
  end if;
  perform public.v1_assert_object_keys(
    p_payload,
    array['worker_id', 'full_name', 'employer_company', 'designation',
      'category', 'arabic_name', 'date_of_birth', 'unified_number',
      'mobile_number', 'joining_date', 'id_profession'],
    'people_person_payload'
  );
  if v_name = '' or char_length(v_name) > 180
    or v_company = '' or char_length(v_company) > 180
    or char_length(v_designation) > 120
    or char_length(coalesce(v_id_profession, '')) > 120
    or v_category not in ('staff', 'labour')
    or (v_dob is not null and v_dob > public.v1_wf_today()) then
    raise exception 'V1_PEOPLE_INVALID' using errcode = '22023';
  end if;

  if v_worker_id is null then
    if coalesce(p_expected_version, 0) <> 0 then
      perform public.v1_raise_version_conflict('V1_PEOPLE_VERSION_CONFLICT');
    end if;
    insert into public.v1_workforce_workers (
      worker_number, full_name, designation, employer_company, worker_type,
      mobile_number, joining_date, created_by_auth_user_id,
      updated_by_auth_user_id
    ) values (
      'WR-' || lpad(
        nextval('public.v1_worker_record_number_seq')::text, 6, '0'
      ),
      v_name, v_designation, v_company, 'yorks_employee', v_mobile,
      v_joining, v_actor, v_actor
    ) returning * into v_worker;
    v_worker_id := v_worker.id;
  else
    select worker.* into v_worker
    from public.v1_workforce_workers worker
    where worker.id = v_worker_id
    for update;
    if not found then
      raise exception 'V1_PEOPLE_NOT_FOUND' using errcode = 'P0002';
    end if;
    select profile.* into v_profile
    from public.v1_people_profiles profile
    where profile.worker_id = v_worker_id
    for update;
    if coalesce(p_expected_version, -1)
      <> coalesce(v_profile.record_version, 0) then
      perform public.v1_raise_version_conflict('V1_PEOPLE_VERSION_CONFLICT');
    end if;
    v_before := public.v1_people_person_json(v_worker_id, false)
      - 'documents' - 'attention' - 'next_expiry' - 'crew'
      - 'previous_documents' - 'history';
    update public.v1_workforce_workers set
      full_name = v_name,
      employer_company = v_company,
      designation = v_designation,
      mobile_number = v_mobile,
      record_version = record_version + 1,
      updated_by_auth_user_id = v_actor,
      updated_at = clock_timestamp()
    where id = v_worker_id;
  end if;

  insert into public.v1_people_profiles (
    worker_id, category, arabic_name, date_of_birth, unified_number,
    id_profession, created_by_auth_user_id, updated_by_auth_user_id,
    updated_by_role
  ) values (
    v_worker_id, v_category, v_arabic, v_dob, v_unified, v_id_profession,
    v_actor, v_actor, v_role
  )
  on conflict (worker_id) do update set
    category = excluded.category,
    arabic_name = excluded.arabic_name,
    date_of_birth = excluded.date_of_birth,
    unified_number = excluded.unified_number,
    -- An older form that does not send the profession on ID keeps it.
    id_profession = case when p_payload ? 'id_profession'
      then excluded.id_profession
      else public.v1_people_profiles.id_profession end,
    record_version = public.v1_people_profiles.record_version + 1,
    updated_by_auth_user_id = v_actor,
    updated_by_role = v_role,
    updated_at = clock_timestamp();

  v_after := public.v1_people_person_json(v_worker_id, false)
    - 'documents' - 'attention' - 'next_expiry' - 'crew'
    - 'previous_documents' - 'history';
  perform public.v1_people_revision(
    v_worker_id, 'person', v_worker_id,
    case when v_before is null then 'created' else 'updated' end,
    v_before, v_after, null, v_actor, v_role, p_idempotency_key
  );
  -- The audit trail names what changed, never an identity number.
  perform public.v1_write_audit_event(
    case when v_before is null then 'people_person_created'
      else 'people_person_updated' end,
    'people_person', v_worker_id, null,
    null,
    jsonb_build_object(
      'record_version', v_after -> 'record_version',
      'category', v_category
    ),
    null, p_idempotency_key
  );
  perform public.v1_complete_idempotency(
    'v1_people_save_person', p_idempotency_key,
    jsonb_build_object('worker_id', v_worker_id)
  );
  return public.v1_people_person_json(v_worker_id, true);
end;
$$;

create or replace function public.v1_people_import_plan(
  p_payload jsonb,
  p_commit boolean,
  p_actor uuid,
  p_role text,
  p_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := public.v1_wf_today();
  v_people jsonb := p_payload -> 'people';
  v_joining date := coalesce(
    nullif(p_payload ->> 'joining_date', '')::date, v_today
  );
  v_entry jsonb;
  v_document jsonb;
  v_rows jsonb := '[]'::jsonb;
  v_problems jsonb;
  v_changes jsonb;
  v_action text;
  v_name text;
  v_company text;
  v_category text;
  v_designation text;
  v_position text;
  v_matches uuid[];
  v_worker_id uuid;
  v_profile public.v1_people_profiles%rowtype;
  v_current public.v1_people_documents%rowtype;
  v_saved public.v1_people_documents%rowtype;
  v_kind text;
  v_number text;
  v_expiry date;
  v_sites text;
  v_doc_action text;
  v_counts jsonb := jsonb_build_object(
    'new', 0, 'update', 0, 'unchanged', 0, 'problem', 0,
    'documents_new', 0, 'documents_renewed', 0, 'documents_updated', 0
  );
  v_seen text[] := '{}';
  v_key text;
  v_row_number integer;
  v_dob date;
  v_arabic text;
  v_unified text;
begin
  if v_people is null or jsonb_typeof(v_people) <> 'array'
    or jsonb_array_length(v_people) not between 1 and 1000 then
    raise exception 'V1_PEOPLE_IMPORT_INVALID' using errcode = '22023';
  end if;

  for v_entry in select value from jsonb_array_elements(v_people) loop
    v_problems := '[]'::jsonb;
    v_changes := '[]'::jsonb;
    v_worker_id := null;
    v_profile := null;
    v_row_number := nullif(v_entry ->> 'row', '')::integer;
    v_name := btrim(regexp_replace(
      coalesce(v_entry ->> 'full_name', ''), '\s+', ' ', 'g'
    ));
    v_company := btrim(regexp_replace(
      coalesce(v_entry ->> 'employer_company', ''), '\s+', ' ', 'g'
    ));
    v_category := coalesce(nullif(v_entry ->> 'category', ''), 'labour');
    -- The tracker's Profession is the one on the visa and ID; a Position
    -- in Company column, when the sheet has one, is the designation.
    v_designation := nullif(btrim(coalesce(v_entry ->> 'designation', '')), '');
    v_position := nullif(btrim(coalesce(v_entry ->> 'position', '')), '');
    v_arabic := nullif(btrim(coalesce(v_entry ->> 'arabic_name', '')), '');
    v_unified := nullif(btrim(coalesce(v_entry ->> 'unified_number', '')), '');
    begin
      v_dob := nullif(v_entry ->> 'date_of_birth', '')::date;
    exception when others then
      v_dob := null;
      v_problems := v_problems || '"date_of_birth"'::jsonb;
    end;

    if v_name = '' or char_length(v_name) > 180 then
      v_problems := v_problems || '"name"'::jsonb;
    end if;
    if v_company = '' or char_length(v_company) > 180 then
      v_problems := v_problems || '"company"'::jsonb;
    end if;
    if v_category not in ('staff', 'labour') then
      v_problems := v_problems || '"category"'::jsonb;
    end if;
    v_key := public.v1_people_key(v_name) || '|' || public.v1_people_key(v_company);
    if v_key = any(v_seen) then
      v_problems := v_problems || '"repeated"'::jsonb;
    end if;
    v_seen := v_seen || v_key;

    if jsonb_array_length(v_problems) = 0 then
      select coalesce(array_agg(worker.id), '{}') into v_matches
      from public.v1_workforce_workers worker
      where public.v1_people_key(worker.full_name)
          = public.v1_people_key(v_name)
        and public.v1_people_key(worker.employer_company)
          = public.v1_people_key(v_company);
      if cardinality(v_matches) > 1 then
        v_problems := v_problems || '"ambiguous"'::jsonb;
      elsif cardinality(v_matches) = 1 then
        v_worker_id := v_matches[1];
      end if;
    end if;

    if jsonb_array_length(v_problems) > 0 then
      v_action := 'problem';
    elsif v_worker_id is null then
      v_action := 'new';
      if p_commit then
        insert into public.v1_workforce_workers (
          worker_number, full_name, designation, employer_company,
          worker_type, joining_date, created_by_auth_user_id,
          updated_by_auth_user_id
        ) values (
          'WR-' || lpad(
            nextval('public.v1_worker_record_number_seq')::text, 6, '0'
          ),
          v_name, coalesce(v_position, v_designation, 'Not recorded'),
          v_company,
          'yorks_employee', v_joining, p_actor, p_actor
        ) returning id into v_worker_id;
        insert into public.v1_people_profiles (
          worker_id, category, arabic_name, date_of_birth, unified_number,
          source_note, id_profession, created_by_auth_user_id, updated_by_auth_user_id,
          updated_by_role
        ) values (
          v_worker_id, v_category, v_arabic, v_dob, v_unified,
          nullif(btrim(coalesce(v_entry ->> 'source_note', '')), ''),
          v_designation,
          p_actor, p_actor, p_role
        );
      end if;
    else
      v_action := 'unchanged';
      select profile.* into v_profile
      from public.v1_people_profiles profile
      where profile.worker_id = v_worker_id
      for update;
      -- Profile: a filled cell that differs updates; a blank keeps.
      if v_profile.worker_id is null
        or (v_arabic is not null
          and v_arabic is distinct from v_profile.arabic_name)
        or (v_dob is not null
          and v_dob is distinct from v_profile.date_of_birth)
        or (v_unified is not null
          and v_unified is distinct from v_profile.unified_number)
        or (v_designation is not null and v_profile.id_profession is null)
      then
        v_action := 'update';
        v_changes := v_changes || '"profile"'::jsonb;
        if p_commit then
          insert into public.v1_people_profiles (
            worker_id, category, arabic_name, date_of_birth, unified_number,
            source_note, id_profession, created_by_auth_user_id, updated_by_auth_user_id,
            updated_by_role
          ) values (
            v_worker_id, v_category, v_arabic, v_dob, v_unified,
            nullif(btrim(coalesce(v_entry ->> 'source_note', '')), ''),
            v_designation,
            p_actor, p_actor, p_role
          )
          on conflict (worker_id) do update set
            arabic_name = coalesce(excluded.arabic_name,
              public.v1_people_profiles.arabic_name),
            date_of_birth = coalesce(excluded.date_of_birth,
              public.v1_people_profiles.date_of_birth),
            unified_number = coalesce(excluded.unified_number,
              public.v1_people_profiles.unified_number),
            -- A blank profession on ID is filled; one already kept stays.
            id_profession = coalesce(public.v1_people_profiles.id_profession,
              excluded.id_profession),
            record_version = public.v1_people_profiles.record_version + 1,
            updated_by_auth_user_id = p_actor,
            updated_by_role = p_role,
            updated_at = clock_timestamp();
        end if;
      end if;
      if coalesce(v_position, v_designation) is not null and exists (
        select 1 from public.v1_workforce_workers worker
        where worker.id = v_worker_id
          and worker.designation = 'Not recorded'
      ) then
        v_action := 'update';
        v_changes := v_changes || '"profession"'::jsonb;
        if p_commit then
          update public.v1_workforce_workers set
            designation = coalesce(v_position, v_designation),
            record_version = record_version + 1,
            updated_by_auth_user_id = p_actor,
            updated_at = clock_timestamp()
          where id = v_worker_id;
        end if;
      end if;
    end if;

    -- Documents.
    if v_action <> 'problem' then
      for v_document in
        select value from jsonb_array_elements(
          coalesce(v_entry -> 'documents', '[]'::jsonb)
        )
      loop
        v_kind := v_document ->> 'kind';
        v_number := nullif(btrim(coalesce(v_document ->> 'number', '')), '');
        v_sites := nullif(btrim(coalesce(v_document ->> 'sites', '')), '');
        begin
          v_expiry := nullif(v_document ->> 'expiry_date', '')::date;
        exception when others then
          v_problems := v_problems || '"document_date"'::jsonb;
          continue;
        end;
        if v_kind is null or v_kind not in (
            'visa', 'passport', 'labour_card', 'iloe', 'emirates_id',
            'cicpa_pass', 'cmw_pass'
          )
          or (v_number is null and v_expiry is null
            and not (v_kind in ('cicpa_pass', 'cmw_pass')
              and v_sites is not null))
          or char_length(coalesce(v_number, '')) > 60
          or char_length(coalesce(v_sites, '')) > 500 then
          v_problems := v_problems || '"document"'::jsonb;
          continue;
        end if;
        v_current := null;
        if v_worker_id is not null then
          if v_kind in ('cicpa_pass', 'cmw_pass') then
            select document.* into v_current
            from public.v1_people_documents document
            where document.worker_id = v_worker_id
              and document.kind = v_kind and document.is_current
              and (
                (v_number is not null and document.document_number = v_number)
                or (v_number is null and document.document_number is null
                  and public.v1_people_key(document.sites)
                    = public.v1_people_key(v_sites))
              )
            order by document.created_at
            limit 1
            for update;
          else
            select document.* into v_current
            from public.v1_people_documents document
            where document.worker_id = v_worker_id
              and document.kind = v_kind and document.is_current
            for update;
          end if;
        end if;

        if v_current.id is null then
          v_doc_action := 'new';
        elsif v_current.expiry_date is not distinct from v_expiry
          and (v_number is null
            or v_current.document_number is not distinct from v_number)
          and (v_sites is null
            or public.v1_people_key(v_current.sites)
              = public.v1_people_key(v_sites)) then
          v_doc_action := 'unchanged';
        elsif v_expiry is not null and v_current.expiry_date is not null
          and v_expiry < v_current.expiry_date then
          -- An older sheet never replaces a newer document.
          v_doc_action := 'unchanged';
        elsif v_expiry is not null
          and v_current.expiry_date is distinct from v_expiry
          and v_current.expiry_date is not null then
          v_doc_action := 'renewed';
        else
          v_doc_action := 'updated';
        end if;

        if v_doc_action <> 'unchanged' then
          if v_action = 'unchanged' then
            v_action := 'update';
          end if;
          v_changes := v_changes || to_jsonb(v_kind || ':' || v_doc_action);
          v_counts := jsonb_set(v_counts, array['documents_' || v_doc_action],
            to_jsonb((v_counts ->> ('documents_' || v_doc_action))::integer
              + 1));
        end if;

        if p_commit and v_doc_action <> 'unchanged' then
          if v_doc_action = 'new' then
            insert into public.v1_people_documents (
              worker_id, kind, document_number, expiry_date, sites,
              created_by_auth_user_id, updated_by_auth_user_id,
              updated_by_role
            ) values (
              v_worker_id, v_kind, v_number, v_expiry, v_sites, p_actor,
              p_actor, p_role
            ) returning * into v_saved;
          elsif v_doc_action = 'renewed' then
            update public.v1_people_documents set
              is_current = false, ended_at = clock_timestamp(),
              ended_reason = 'renewed',
              record_version = record_version + 1,
              updated_by_auth_user_id = p_actor, updated_by_role = p_role,
              updated_at = clock_timestamp()
            where id = v_current.id;
            insert into public.v1_people_documents (
              worker_id, kind, document_number, expiry_date, sites,
              created_by_auth_user_id, updated_by_auth_user_id,
              updated_by_role
            ) values (
              v_worker_id, v_kind,
              coalesce(v_number, v_current.document_number), v_expiry,
              coalesce(v_sites, v_current.sites), p_actor, p_actor, p_role
            ) returning * into v_saved;
            update public.v1_people_documents
            set replaced_by_document_id = v_saved.id
            where id = v_current.id;
          else
            update public.v1_people_documents set
              document_number = coalesce(v_number, document_number),
              expiry_date = coalesce(v_expiry, expiry_date),
              sites = coalesce(v_sites, sites),
              record_version = record_version + 1,
              updated_by_auth_user_id = p_actor, updated_by_role = p_role,
              updated_at = clock_timestamp()
            where id = v_current.id
            returning * into v_saved;
          end if;
        end if;
      end loop;
    end if;

    if jsonb_array_length(v_problems) > 0 then
      v_action := 'problem';
    end if;
    if p_commit and v_action in ('new', 'update') then
      perform public.v1_people_revision(
        v_worker_id, 'person', v_worker_id, 'imported', null,
        jsonb_build_object(
          'source', nullif(p_payload ->> 'source_name', ''),
          'row', v_row_number, 'changes', v_changes
        ),
        null, p_actor, p_role, p_key
      );
    end if;
    v_counts := jsonb_set(v_counts, array[v_action],
      to_jsonb((v_counts ->> v_action)::integer + 1));
    v_rows := v_rows || jsonb_build_object(
      'row', v_row_number,
      'name', v_name,
      'company', v_company,
      'category', v_category,
      'action', v_action,
      'worker_id', v_worker_id,
      'changes', v_changes,
      'problems', v_problems
    );
  end loop;

  return jsonb_build_object(
    'schema_version', 'yorks.people.import.v1',
    'counts', v_counts,
    'rows', v_rows
  );
end;
$$;

notify pgrst, 'reload schema';

commit;
