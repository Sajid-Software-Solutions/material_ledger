begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- My Yorks from the People record (PRODUCT_DECISIONS section 54).
--
-- Local personas: PE ...0001, SE ...0002, Procurement ...0003,
-- Admin ...0004, Accountant ...0013, PR ...0014. Fictional fixtures only.

create function pg_temp.act(p_user uuid, p_role text)
returns void
language plpgsql
as $$
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', p_user, 'role', 'authenticated',
      'app_metadata', jsonb_build_object('role', p_role)
    )::text,
    true
  );
end;
$$;

-- Privileges ------------------------------------------------------------------

select ok(
  not has_table_privilege('authenticated', 'public.v1_people_notes', 'select')
  and not has_table_privilege('authenticated',
    'public.v1_people_my_reminders', 'select')
  and not has_function_privilege('authenticated',
    'public.v1_people_mine_json(uuid)', 'execute')
  and not has_function_privilege('authenticated',
    'public.v1_people_send_my_reminders()', 'execute')
  and not has_function_privilege('authenticated',
    'public.v1_people_account_json(uuid)', 'execute'),
  'Notes, reminders and the helpers are not reachable directly'
);
select ok(
  has_function_privilege('authenticated',
    'public.v1_people_get_mine()', 'execute')
  and has_function_privilege('authenticated',
    'public.v1_people_send_note(text, uuid)', 'execute')
  and has_function_privilege('authenticated',
    'public.v1_people_set_account(uuid, uuid, bigint, uuid)', 'execute')
  and not has_function_privilege('anon',
    'public.v1_people_get_mine()', 'execute')
  and not has_function_privilege('anon',
    'public.v1_people_set_account(uuid, uuid, bigint, uuid)', 'execute'),
  'Signed-in users call the commands; anonymous callers do not'
);
select is(
  (select schedule from cron.job where jobname = 'yorks-people-my-reminders'),
  '20 4 * * *', 'Personal reminders run every morning at 08:20 in Dubai'
);

-- A person with a visa ending in 30 days and a short passport number --------

select set_config('mine.today', public.v1_wf_today()::text, true);
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000014', 'pr');
select set_config('mine.person', (
  public.v1_people_save_person(jsonb_build_object(
    'full_name', 'Local Site Engineer',
    'employer_company', 'Example Contracting LLC',
    'designation', 'Site Engineer',
    'id_profession', 'Civil Engineer',
    'arabic_name', 'مهندس الموقع',
    'date_of_birth', '1990-01-02',
    'unified_number', '784199012345',
    'category', 'staff'
  ), 0, 'a2010000-0000-4000-8000-000000000001') ->> 'id'
), true);
select lives_ok(
  format($$select public.v1_people_save_document(jsonb_build_object(
    'worker_id', %L, 'kind', 'visa', 'number', 'V-123456789',
    'expiry_date', (current_setting('mine.today')::date + 30)::text
  ), 0, 'a2010000-0000-4000-8000-000000000002')$$,
  current_setting('mine.person')),
  'A visa ending in 30 days'
);
select lives_ok(
  format($$select public.v1_people_save_document(jsonb_build_object(
    'worker_id', %L, 'kind', 'passport', 'number', 'AB12',
    'expiry_date', (current_setting('mine.today')::date + 900)::text
  ), 0, 'a2010000-0000-4000-8000-000000000003')$$,
  current_setting('mine.person')),
  'A passport with a short number'
);
select set_config('mine.other', (
  public.v1_people_save_person(jsonb_build_object(
    'full_name', 'Test Welder Two',
    'employer_company', 'Example Contracting LLC',
    'designation', 'Welder',
    'category', 'labour'
  ), 0, 'a2010000-0000-4000-8000-000000000004') ->> 'id'
), true);

-- Not linked yet --------------------------------------------------------------

select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select is(
  public.v1_people_get_mine() ->> 'state', 'unlinked',
  'Before a link the Site Engineer has no record'
);
select is(
  jsonb_typeof(public.v1_people_get_mine() -> 'projects'), 'array',
  'and still sees their projects'
);
select throws_ok(
  $$select public.v1_people_send_note('Wrong visa date',
    'a2010000-0000-4000-8000-000000000010')$$,
  'P0002', 'V1_PEOPLE_NOT_LINKED',
  'Someone not linked cannot send a note'
);

-- Who may link ----------------------------------------------------------------

select throws_ok(
  format($$select public.v1_people_set_account(%L,
    '10000000-0000-4000-8000-000000000002', 1,
    'a2010000-0000-4000-8000-000000000011')$$,
  current_setting('mine.person')),
  '42501', null, 'A Site Engineer cannot link accounts'
);
select pg_temp.act('10000000-0000-4000-8000-000000000003', 'procurement');
select throws_ok(
  $$select public.v1_people_link_suggestions()$$,
  '42501', null, 'Procurement cannot see link suggestions'
);
select pg_temp.act('10000000-0000-4000-8000-000000000013', 'accountant');
select is(
  (public.v1_people_get(current_setting('mine.person')::uuid)
    ->> 'can_link')::boolean,
  false, 'The Accountant manages People but does not link accounts'
);
select throws_ok(
  format($$select public.v1_people_set_account(%L,
    '10000000-0000-4000-8000-000000000002', 1,
    'a2010000-0000-4000-8000-000000000012')$$,
  current_setting('mine.person')),
  '42501', null, 'so the Accountant cannot link'
);

select pg_temp.act('10000000-0000-4000-8000-000000000014', 'pr');
select is(
  (public.v1_people_get(current_setting('mine.person')::uuid)
    ->> 'can_link')::boolean,
  true, 'PR may link'
);
select ok(
  exists (
    select 1
    from jsonb_array_elements(
      public.v1_people_link_suggestions() -> 'accounts'
    ) account
    where account ->> 'auth_user_id' = '10000000-0000-4000-8000-000000000002'
      and account -> 'suggestions' -> 0 ->> 'worker_id'
        = current_setting('mine.person')
  ),
  'The Site Engineer''s account suggests the person with the same name'
);
select ok(
  not exists (
    select 1
    from jsonb_array_elements(
      public.v1_people_link_suggestions() -> 'accounts'
    ) account,
    jsonb_array_elements(account -> 'suggestions') suggestion
    where account ->> 'auth_user_id' = '10000000-0000-4000-8000-000000000002'
      and suggestion ->> 'worker_id' = current_setting('mine.other')
  ),
  'and not a person with a different name'
);

-- Linking ---------------------------------------------------------------------

select throws_ok(
  format($$select public.v1_people_set_account(%L,
    '10000000-0000-4000-8000-000000000002', 0,
    'a2010000-0000-4000-8000-000000000013')$$,
  current_setting('mine.person')),
  '40001', null, 'A stale record version is refused'
);
select lives_ok(
  format($$select public.v1_people_set_account(%L,
    '10000000-0000-4000-8000-000000000002', 1,
    'a2010000-0000-4000-8000-000000000014')$$,
  current_setting('mine.person')),
  'PR links the Site Engineer''s account'
);
select lives_ok(
  format($$select public.v1_people_set_account(%L,
    '10000000-0000-4000-8000-000000000002', 1,
    'a2010000-0000-4000-8000-000000000014')$$,
  current_setting('mine.person')),
  'A retry returns the same answer'
);
select is(
  public.v1_people_get(current_setting('mine.person')::uuid)
    -> 'account' ->> 'auth_user_id',
  '10000000-0000-4000-8000-000000000002',
  'The record shows its account'
);
select is(
  (public.v1_people_get(current_setting('mine.person')::uuid)
    ->> 'record_version')::integer,
  2, 'The link changes the record version once'
);
select throws_ok(
  format($$select public.v1_people_set_account(%L,
    '10000000-0000-4000-8000-000000000002', 1,
    'a2010000-0000-4000-8000-000000000015')$$,
  current_setting('mine.other')),
  '23505', 'V1_PEOPLE_ACCOUNT_TAKEN',
  'An account belongs to one person'
);
select throws_ok(
  format($$select public.v1_people_set_account(%L,
    'b2010000-0000-4000-8000-000000000099', 1,
    'a2010000-0000-4000-8000-000000000016')$$,
  current_setting('mine.other')),
  'P0002', 'V1_PEOPLE_ACCOUNT_NOT_FOUND',
  'An unknown account is refused'
);
reset role;
select is(
  (select count(*)::integer from public.v1_people_revisions revision
   where revision.worker_id = current_setting('mine.person')::uuid
     and revision.after_data ? 'account'
     and revision.after_data -> 'account' ->> 'auth_user_id'
       = '10000000-0000-4000-8000-000000000002'),
  1, 'The link is in the person''s history once'
);
select is(
  (select count(*)::integer from public.v1_audit_events event
   where event.event_type = 'people_account_linked'
     and event.entity_id = current_setting('mine.person')::uuid),
  1, 'and in the audit trail once'
);

-- My record -------------------------------------------------------------------

-- Two days this month on a crew sheet.
insert into public.v1_workforce_teams (
  id, team_code, team_name, valid_from, is_active,
  created_by_auth_user_id, updated_by_auth_user_id
) values (
  'b2020000-0000-4000-8000-000000000001', 'MINE-1', 'Example Crew',
  date_trunc('month', public.v1_wf_today())::date, true,
  '10000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000004'
);
insert into public.v1_workforce_day_sheets (
  id, team_id, work_date, entered_by_auth_user_id, entered_at,
  last_saved_by_auth_user_id, last_saved_at
) values (
  'b2030000-0000-4000-8000-000000000001',
  'b2020000-0000-4000-8000-000000000001',
  date_trunc('month', public.v1_wf_today())::date,
  '10000000-0000-4000-8000-000000000004', clock_timestamp(),
  '10000000-0000-4000-8000-000000000004', clock_timestamp()
);
insert into public.v1_workforce_day_rows (
  sheet_id, team_id, work_date, worker_id, attendance_status,
  start_minute, finish_minute, worked_minutes, regular_minutes,
  normal_overtime_minutes, updated_by_auth_user_id
) values (
  'b2030000-0000-4000-8000-000000000001',
  'b2020000-0000-4000-8000-000000000001',
  date_trunc('month', public.v1_wf_today())::date,
  current_setting('mine.person')::uuid, 'P', 390, 960, 570, 480, 90,
  '10000000-0000-4000-8000-000000000004'
);

set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select set_config('mine.json', public.v1_people_get_mine()::text, true);
select is(
  current_setting('mine.json')::jsonb ->> 'state', 'linked',
  'Once linked the Site Engineer reads their record'
);
select is(
  current_setting('mine.json')::jsonb -> 'person' ->> 'id',
  current_setting('mine.person'), 'their own'
);
select is(
  current_setting('mine.json')::jsonb -> 'person' ->> 'id_profession',
  'Civil Engineer', 'with the profession on their ID'
);
select is(
  current_setting('mine.json')::jsonb -> 'person' ->> 'attention',
  'expiring', 'and that a document is expiring'
);
select is(
  (select document ->> 'number_last4'
   from jsonb_array_elements(
     current_setting('mine.json')::jsonb -> 'person' -> 'documents'
   ) document where document ->> 'kind' = 'visa'),
  '6789', 'A document number shows only its last four'
);
select is(
  (select document ->> 'number_last4'
   from jsonb_array_elements(
     current_setting('mine.json')::jsonb -> 'person' -> 'documents'
   ) document where document ->> 'kind' = 'passport'),
  null, 'and a number of four or fewer is not shown at all'
);
select ok(
  position('123456789' in current_setting('mine.json')) = 0
  and position('AB12' in current_setting('mine.json')) = 0
  and position('784199012345' in current_setting('mine.json')) = 0
  and position('1990-01-02' in current_setting('mine.json')) = 0,
  'No whole number, unified number or date of birth leaves the server'
);
select is(
  (current_setting('mine.json')::jsonb -> 'person' -> 'attendance'
    ->> 'present_days')::integer,
  1, 'This month''s attendance counts the day present'
);
select is(
  (current_setting('mine.json')::jsonb -> 'person' -> 'attendance'
    ->> 'overtime_minutes')::integer,
  90, 'and its overtime'
);

select pg_temp.act('10000000-0000-4000-8000-000000000001', 'project_engineer');
select is(
  public.v1_people_get_mine() ->> 'state', 'unlinked',
  'Another user never sees the Site Engineer''s record'
);
select throws_ok(
  format($$select public.v1_people_get(%L)$$, current_setting('mine.person')),
  '42501', null, 'and still cannot open People'
);

-- A note to HR/PRO ------------------------------------------------------------

select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select throws_ok(
  $$select public.v1_people_send_note('   ',
    'a2010000-0000-4000-8000-000000000020')$$,
  '22023', 'V1_PEOPLE_INVALID', 'A blank note is refused'
);
select lives_ok(
  $$select public.v1_people_send_note('My visa expiry date is wrong',
    'a2010000-0000-4000-8000-000000000021')$$,
  'The Site Engineer sends HR/PRO a note'
);
select lives_ok(
  $$select public.v1_people_send_note('My visa expiry date is wrong',
    'a2010000-0000-4000-8000-000000000021')$$,
  'A retry sends nothing more'
);
select is(
  public.v1_people_get_mine() -> 'person' -> 'notes' -> 0 ->> 'message',
  'My visa expiry date is wrong', 'They see the note they sent'
);
reset role;
select is(
  (select count(*)::integer from public.v1_people_notes note
   where note.worker_id = current_setting('mine.person')::uuid),
  1, 'One note is kept'
);
select is(
  (select array_agg(distinct notification.recipient_auth_user_id::text
     order by notification.recipient_auth_user_id::text)
   from public.v1_notifications notification
   where notification.event_code = 'people_note_received'),
  array['10000000-0000-4000-8000-000000000004',
    '10000000-0000-4000-8000-000000000014'],
  'PR and Admin are told, once each'
);
select is(
  (select count(*)::integer from public.v1_notifications notification
   where notification.event_code = 'people_note_received'),
  2, 'and nobody else'
);
select is(
  (select public.v1_notification_module_route(notification)
   from public.v1_notifications notification
   where notification.event_code = 'people_note_received' limit 1),
  '/yorks/people/' || current_setting('mine.person'),
  'The notification opens the person''s record'
);
select ok(
  (select bool_and(public.v1_push_notification_entity_allowed(notification))
   from public.v1_notifications notification
   where notification.event_code = 'people_note_received'),
  'and may be pushed'
);
select is(
  (select count(*)::integer from public.v1_audit_events event
   where event.event_type = 'people_note_sent'
     and event.entity_id = current_setting('mine.person')::uuid
     and position('visa' in event.after_data::text) = 0),
  1, 'The audit trail records the note without its words'
);
select throws_ok(
  $$update public.v1_people_notes set message = 'changed'$$,
  '55000', 'V1_PEOPLE_HISTORY_IMMUTABLE', 'A note''s words never change'
);
select throws_ok(
  $$delete from public.v1_people_notes$$,
  '55000', 'V1_PEOPLE_HISTORY_IMMUTABLE', 'and a note is never deleted'
);

set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select lives_ok(
  $$select public.v1_people_send_note('Second', 'a2010000-0000-4000-8000-000000000022')$$,
  'Note 2'
);
select lives_ok(
  $$select public.v1_people_send_note('Third', 'a2010000-0000-4000-8000-000000000023')$$,
  'Note 3'
);
select lives_ok(
  $$select public.v1_people_send_note('Fourth', 'a2010000-0000-4000-8000-000000000024')$$,
  'Note 4'
);
select lives_ok(
  $$select public.v1_people_send_note('Fifth', 'a2010000-0000-4000-8000-000000000025')$$,
  'Note 5'
);
select throws_ok(
  $$select public.v1_people_send_note('Sixth', 'a2010000-0000-4000-8000-000000000026')$$,
  '22023', 'V1_PEOPLE_NOTE_LIMIT', 'A sixth note in a day is refused'
);

select set_config('mine.note', (
  public.v1_people_get_mine() -> 'person' -> 'notes' -> 0 ->> 'id'
), true);
select throws_ok(
  format($$select public.v1_people_note_done(%L,
    'a2010000-0000-4000-8000-000000000030')$$, current_setting('mine.note')),
  '42501', null, 'The author cannot mark their own note done'
);
select pg_temp.act('10000000-0000-4000-8000-000000000014', 'pr');
select is(
  jsonb_array_length(
    public.v1_people_get(current_setting('mine.person')::uuid) -> 'notes'
  ),
  5, 'PR reads the notes on the record'
);
select ok(
  public.v1_people_note_done(current_setting('mine.note')::uuid,
    'a2010000-0000-4000-8000-000000000031') -> 'notes' -> 0 ->> 'done_at'
    is not null,
  'PR marks a note done'
);

-- The personal reminder -------------------------------------------------------

reset role;
select is(
  public.v1_people_send_my_reminders(), 1,
  'The linked person is reminded about their visa'
);
select is(
  public.v1_people_send_my_reminders(), 0,
  'Nothing changed sends nothing more'
);
select is(
  (select notification.event_code from public.v1_notifications notification
   where notification.entity_type = 'people_my_reminder'),
  'people_my_documents_due', 'It is not urgent while nothing has expired'
);
select is(
  (select public.v1_notification_module_route(notification)
   from public.v1_notifications notification
   where notification.entity_type = 'people_my_reminder'),
  '/profile', 'and opens My Yorks'
);
select is(
  (select notification.recipient_auth_user_id::text
   from public.v1_notifications notification
   where notification.entity_type = 'people_my_reminder'),
  '10000000-0000-4000-8000-000000000002', 'It goes to the person only'
);

-- Unlinking -------------------------------------------------------------------

set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000004', 'admin');
select is(
  public.v1_people_set_account(current_setting('mine.person')::uuid, null, 2,
    'a2010000-0000-4000-8000-000000000040') -> 'account',
  'null'::jsonb, 'Admin unlinks the account'
);
select pg_temp.act('10000000-0000-4000-8000-000000000002', 'site_engineer');
select is(
  public.v1_people_get_mine() ->> 'state', 'unlinked',
  'and the Site Engineer no longer reads the record'
);

select * from finish();
rollback;
