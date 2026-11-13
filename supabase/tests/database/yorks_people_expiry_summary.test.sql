begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- Local personas: SE ...0002, Admin ...0004, PR ...0014. Fictional fixtures.

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

select ok(
  not has_function_privilege('authenticated',
    'public.v1_people_send_expiry_summary()', 'execute')
  and not has_function_privilege('anon',
    'public.v1_people_send_expiry_summary()', 'execute')
  and not has_table_privilege('authenticated',
    'public.v1_people_expiry_digests', 'select'),
  'Only the schedule sends the summary; digests are not readable'
);
select is(
  (select schedule from cron.job where jobname = 'yorks-people-expiry-summary'),
  '15 4 * * *', 'The summary runs every morning at 08:15 in Dubai'
);
select ok(
  (select array_agg(id) from public.v1_people_expiry_recipients() id)
    @> array['10000000-0000-4000-8000-000000000004',
      '10000000-0000-4000-8000-000000000014']::uuid[]
  and not exists (
    select 1 from public.v1_people_expiry_recipients() id
    where id = '10000000-0000-4000-8000-000000000002'
  ),
  'PR and Admin receive it; a Site Engineer does not'
);
select is(
  public.v1_people_send_expiry_summary(), 0,
  'Nothing expiring sends nothing'
);

-- A visa that ends in 30 days.
select set_config('exp.today', public.v1_wf_today()::text, true);
select set_config('exp.recipients',
  (select count(*)::text from public.v1_people_expiry_recipients()), true);
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000014', 'pr');
select set_config('exp.person', (
  public.v1_people_save_person(jsonb_build_object(
      'full_name', 'Test Expiry One', 'employer_company', 'Example Co',
      'category', 'labour'),
    0, '9e300000-0000-4000-8000-000000000001') ->> 'id'), true);
select set_config('exp.visa', (
  public.v1_people_save_document(jsonb_build_object(
      'worker_id', current_setting('exp.person'), 'kind', 'visa',
      'expiry_date', (current_setting('exp.today')::date + 30)::text),
    0, '9e300000-0000-4000-8000-000000000002') -> 'documents' -> 0 ->> 'id'),
  true);
reset role;

select is(
  public.v1_people_send_expiry_summary(),
  current_setting('exp.recipients')::integer,
  'Every PR and Admin gets one summary'
);
select is(
  (select array_agg(distinct event_code) from public.v1_notifications
   where entity_type = 'people_expiry_digest'),
  array['people_documents_due'],
  'Nothing has expired, so the summary is not urgent'
);
select is(
  public.v1_people_send_expiry_summary(), 0,
  'At most one summary per person per day'
);

-- The next morning, with nothing changed.
update public.v1_people_expiry_digests set sent_on = sent_on - 1;
select is(
  public.v1_people_send_expiry_summary(), 0,
  'Nothing changed since the last summary sends nothing'
);

-- A passport that expired three days ago is a change, and urgent.
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000014', 'pr');
select public.v1_people_save_document(jsonb_build_object(
    'worker_id', current_setting('exp.person'), 'kind', 'passport',
    'number', 'TP-EXPIRY-1',
    'expiry_date', (current_setting('exp.today')::date - 3)::text),
  0, '9e300000-0000-4000-8000-000000000003');
reset role;
select is(
  public.v1_people_send_expiry_summary(),
  current_setting('exp.recipients')::integer,
  'A newly expired document sends a new summary'
);
select is(
  (select array_agg(distinct notification.event_code)
   from public.v1_notifications notification
   join public.v1_people_expiry_digests digest
     on digest.id = notification.entity_id
   where notification.entity_type = 'people_expiry_digest'
     and digest.sent_on = current_setting('exp.today')::date),
  array['people_documents_overdue'],
  'Something has expired, so the summary is urgent'
);
select is(
  (select expired_count || '/' || expiring_count || '/' || people_count
     || '/' || company_count
   from public.v1_people_expiry_digests
   where recipient_auth_user_id = '10000000-0000-4000-8000-000000000004'
     and sent_on = current_setting('exp.today')::date),
  '1/1/2/0', 'The summary counts one expired and one expiring document'
);

-- A renewal is a change too.
update public.v1_people_expiry_digests set sent_on = sent_on - 1;
set local role authenticated;
select pg_temp.act('10000000-0000-4000-8000-000000000014', 'pr');
select public.v1_people_save_document(jsonb_build_object(
    'worker_id', current_setting('exp.person'),
    'document_id', current_setting('exp.visa'), 'renew', true,
    'expiry_date', (current_setting('exp.today')::date + 700)::text),
  1, '9e300000-0000-4000-8000-000000000004');
reset role;
select is(
  public.v1_people_send_expiry_summary(),
  current_setting('exp.recipients')::integer,
  'A renewal changes what needs attention and sends a new summary'
);

-- Link, label and delivery, as the recipient.
select set_config('exp.notification', (
  select id::text from public.v1_notifications
  where recipient_auth_user_id = '10000000-0000-4000-8000-000000000004'
    and entity_type = 'people_expiry_digest'
  order by created_at desc limit 1), true);
-- The link functions run inside the notification reads, not as app RPCs, so
-- they are called here with the reader's claims.
select pg_temp.act('10000000-0000-4000-8000-000000000004', 'admin');
select is(
  (select public.v1_notification_module_route(n) from public.v1_notifications n
   where n.id = current_setting('exp.notification')::uuid),
  '/yorks/people', 'The summary opens People'
);
select is(
  (select public.v1_notification_record_label(n) from public.v1_notifications n
   where n.id = current_setting('exp.notification')::uuid),
  '1', 'Its label is how many documents need attention'
);
select pg_temp.act('10000000-0000-4000-8000-000000000014', 'pr');
select is(
  (select public.v1_notification_record_label(n) from public.v1_notifications n
   where n.id = current_setting('exp.notification')::uuid),
  null, 'Nobody else reads another person''s summary label'
);
select ok(
  (select public.v1_push_notification_entity_allowed(n)
   from public.v1_notifications n
   where n.id = current_setting('exp.notification')::uuid),
  'The summary is delivered as a push'
);

-- Only company documents need attention: it opens Company documents.
insert into public.v1_people_expiry_digests (
  id, recipient_auth_user_id, sent_on, expired_count, expiring_count,
  people_count, company_count, fingerprint
) values (
  '9e300000-0000-4000-8000-000000000010',
  '10000000-0000-4000-8000-000000000004',
  current_setting('exp.today')::date - 30, 0, 1, 0, 1, md5('company')
);
insert into public.v1_notifications (
  id, recipient_auth_user_id, event_code, entity_type, entity_id
) values (
  '9e300000-0000-4000-8000-000000000011',
  '10000000-0000-4000-8000-000000000004', 'people_documents_due',
  'people_expiry_digest', '9e300000-0000-4000-8000-000000000010'
);
select is(
  (select public.v1_notification_module_route(n) from public.v1_notifications n
   where n.id = '9e300000-0000-4000-8000-000000000011'),
  '/yorks/company-documents',
  'Company documents alone open Company documents'
);
select throws_ok(
  $$delete from public.v1_people_expiry_digests$$, '55000', null,
  'Sent summaries are kept'
);

-- Other notifications still use the earlier link.
select is(
  public.v1_notification_module_route(row(
    gen_random_uuid(), '10000000-0000-4000-8000-000000000004',
    'workforce_crew_request_overdue', 'workforce_crew_request_digest',
    gen_random_uuid(), null, now(), null
  )::public.v1_notifications),
  '/yorks/workforce?view=requests',
  'Crew request summaries keep their own link'
);

select * from finish();
rollback;
