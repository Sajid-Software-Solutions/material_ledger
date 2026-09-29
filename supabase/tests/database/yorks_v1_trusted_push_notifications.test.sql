begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(29);

select ok(
  (select relrowsecurity from pg_class
   where oid = 'public.v1_push_device_tokens'::regclass)
  and (select relrowsecurity from pg_class
   where oid = 'public.v1_notification_push_outbox'::regclass),
  'Push token and delivery outbox tables enforce RLS'
);

select ok(
  not has_table_privilege(
    'authenticated', 'public.v1_push_device_tokens', 'select'
  )
  and not has_table_privilege(
    'authenticated', 'public.v1_notification_push_outbox', 'select'
  )
  and has_function_privilege(
    'authenticated', 'public.v1_register_push_device(text,text)', 'execute'
  )
  and has_function_privilege(
    'authenticated', 'public.v1_list_my_notifications(integer)', 'execute'
  )
  and has_function_privilege(
    'authenticated', 'public.v1_mark_all_notifications_seen()', 'execute'
  )
  and not has_function_privilege(
    'anon', 'public.v1_mark_all_notifications_seen()', 'execute'
  ),
  'Clients use narrow token and notification RPCs, never protected tables'
);

select ok(
  not has_function_privilege(
    'authenticated', 'public.v1_claim_notification_push(uuid)', 'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.v1_finish_notification_push(uuid,text,integer,text)',
    'execute'
  ),
  'Only the service worker can claim or finish push deliveries'
);

select ok(
  exists (
    select 1 from pg_trigger
    where tgname = 'v1_material_returns_notify_decision' and not tgisinternal
  )
  and exists (
    select 1 from pg_trigger
    where tgname = 'v1_material_requests_notify_cancelled' and not tgisinternal
  )
  and exists (
    select 1 from pg_trigger
    where tgname = 'v1_project_members_notify_insert' and not tgisinternal
  ),
  'Trusted workflow and membership transitions own their notification triggers'
);

select ok(
  not has_function_privilege(
    'authenticated', 'public.v1_notify_material_return_decision()', 'execute'
  )
  and not has_function_privilege(
    'authenticated', 'public.v1_notify_material_request_cancelled()', 'execute'
  )
  and not has_function_privilege(
    'authenticated', 'public.v1_notify_project_membership_change()', 'execute'
  ),
  'Authenticated clients cannot invoke server notification fan-out functions'
);

set local role postgres;
select is(
  public.v1_validate_push_webhook_secret('not-the-server-secret'),
  false,
  'A forged webhook secret is rejected'
);

select is(
  public.v1_validate_push_webhook_secret(
    (select decrypted_secret from vault.decrypted_secrets
     where name = 'yorks_push_webhook_secret')
  ),
  true,
  'The database-generated webhook secret validates server calls'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);

select lives_ok(
  $$select public.v1_register_push_device(
    'test-fcm-token-procurement-00000000000000000001', 'web'
  )$$,
  'An active Procurement user registers an owner-bound web token'
);

set local role postgres;
select is(
  (select auth_user_id from public.v1_push_device_tokens
   where token = 'test-fcm-token-procurement-00000000000000000001'),
  '10000000-0000-4000-8000-000000000003'::uuid,
  'Token ownership comes from auth.uid rather than client metadata'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);

select throws_ok(
  $$select * from public.v1_push_device_tokens$$,
  '42501', null,
  'A Site Engineer cannot read protected device tokens'
);

select is(
  public.v1_unregister_push_device(
    'test-fcm-token-procurement-00000000000000000001'
  ),
  false,
  'A different user cannot unregister Procurement device tokens'
);

set local role postgres;
insert into public.v1_notifications (
  id, recipient_auth_user_id, event_code, entity_type, entity_id, created_at
) values
  (
    '91000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000003',
    'material_request_submitted', 'material_request',
    '92000000-0000-4000-8000-000000000001', clock_timestamp()
  ),
  (
    '91000000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000002',
    'receipt_review_required', 'material_dispatch',
    '92000000-0000-4000-8000-000000000002', clock_timestamp()
  );

insert into public.v1_notifications (
  id, recipient_auth_user_id, event_code, entity_type, entity_id, created_at
) values (
  '91000000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-000000000001',
  'material_request_updated_for_approval', 'material_request',
  '92000000-0000-4000-8000-000000000003', clock_timestamp()
);

select is(
  (select count(*) from public.v1_notifications
   where event_code = 'material_request_updated_for_approval'
     and entity_id = '92000000-0000-4000-8000-000000000003'
     and recipient_auth_user_id in (
       '10000000-0000-4000-8000-000000000009',
       '10000000-0000-4000-8000-000000000010'
     )),
  2::bigint,
  'Approval edits notify both organization-wide Project Engineer roles'
);

select is(
  (select count(*) from public.v1_notification_push_outbox
   where notification_id in (
     select id from public.v1_notifications
     where event_code = 'material_request_updated_for_approval'
       and entity_id = '92000000-0000-4000-8000-000000000003'
   )),
  3::bigint,
  'Each approval-edit recipient receives one durable push command'
);

select is(
  (select count(*) from public.v1_notification_push_outbox
   where notification_id in (
     '91000000-0000-4000-8000-000000000001',
     '91000000-0000-4000-8000-000000000002'
   )),
  2::bigint,
  'Every authoritative notification creates one durable push command'
);

select is(
  (select count(*) from public.v1_notifications
   where event_code = 'receipt_review_required'
     and entity_id = '92000000-0000-4000-8000-000000000002'
     and recipient_auth_user_id in (
       '10000000-0000-4000-8000-000000000009',
       '10000000-0000-4000-8000-000000000010'
     )),
  2::bigint,
  'Senior Mechanical Engineer and Project Manager receive global PE work'
);

select is(
  (select count(*) from public.v1_notification_push_outbox
   where notification_id in (
     select id from public.v1_notifications
     where event_code = 'receipt_review_required'
       and entity_id = '92000000-0000-4000-8000-000000000002'
   )),
  3::bigint,
  'Expanded global recipients each receive an independent delivery command'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);

select is(
  (select count(*) from public.v1_list_my_notifications(100)
   where notification_id = '91000000-0000-4000-8000-000000000001'),
  1::bigint,
  'Personal notification list includes the recipient-owned fixture notification'
);

select is(
  (select request_id from public.v1_list_my_notifications(100)
   where notification_id = '91000000-0000-4000-8000-000000000001'),
  '92000000-0000-4000-8000-000000000001'::uuid,
  'Notification projection resolves the safe Material Request deep link'
);

select lives_ok(
  $$select public.v1_mark_notification_seen(
    '91000000-0000-4000-8000-000000000001'
  )$$,
  'Recipient can idempotently acknowledge their own notification'
);

select ok(
  (select seen_at is not null from public.v1_list_my_notifications(100)
   where notification_id = '91000000-0000-4000-8000-000000000001'),
  'Acknowledgement is visible in the authoritative projection'
);

set local role postgres;
update public.v1_notifications set seen_at = null
where id = '91000000-0000-4000-8000-000000000001';
insert into public.v1_notifications (
  id, recipient_auth_user_id, event_code, entity_type, entity_id, created_at
) values (
  '91000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000003',
  'material_request_mentioned', 'material_request',
  '92000000-0000-4000-8000-000000000001', clock_timestamp()
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);
with unread_for_recipient as materialized (
  select count(*)::integer as expected
  from public.v1_list_my_notifications(200)
  where seen_at is null
)
select is(
  public.v1_mark_all_notifications_seen(),
  (select expected from unread_for_recipient),
  'Recipient acknowledges every currently unread owned notification atomically'
);

set local role postgres;
select ok(
  not exists (
    select 1 from public.v1_notifications
    where recipient_auth_user_id = '10000000-0000-4000-8000-000000000003'
      and seen_at is null
  )
  and exists (
    select 1 from public.v1_notifications
    where id = '91000000-0000-4000-8000-000000000002'
      and seen_at is null
  ),
  'Bulk acknowledgement cannot alter another recipient notification'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer","app_user_id":"usr-local-site-engineer"}}',
  true
);

select throws_ok(
  $$select public.v1_mark_notification_seen(
    '91000000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'V1_NOTIFICATION_SEEN_DENIED',
  'Another recipient cannot acknowledge Procurement notifications'
);

set local role postgres;
update public.v1_notifications set seen_at = null
where id = '91000000-0000-4000-8000-000000000001';
update public.v1_notification_push_outbox
set status = 'no_devices', completed_at = clock_timestamp()
where notification_id = '91000000-0000-4000-8000-000000000001';

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
  true
);
select lives_ok(
  $$select public.v1_register_push_device(
    'test-fcm-token-procurement-00000000000000000002', 'android'
  )$$,
  'A later device registration succeeds without replaying history'
);

set local role postgres;
select is(
  (select status from public.v1_notification_push_outbox
   where notification_id = '91000000-0000-4000-8000-000000000001'),
  'no_devices',
  'Enrollment does not replay historical no-device notifications'
);

insert into public.v1_notifications(id,recipient_auth_user_id,event_code,entity_type,entity_id)
values('91000000-0000-4000-8000-000000000009','10000000-0000-4000-8000-000000000003',
'material_request_submitted','material_request','92000000-0000-4000-8000-000000000009');
update public.v1_push_transport_control set operator_paused = false where id;
update public.v1_notification_push_outbox
set dispatch_lease_until = clock_timestamp() + interval '2 minutes'
where notification_id = '91000000-0000-4000-8000-000000000009';

select is(
  (public.v1_claim_notification_push(
    '91000000-0000-4000-8000-000000000009'
  ) ->> 'recipientAuthUserId'),
  '10000000-0000-4000-8000-000000000003',
  'Service claim derives recipient identity from the notification row'
);

select lives_ok(
  $$select public.v1_finish_notification_push(
    '91000000-0000-4000-8000-000000000009',
    (select claim_id from public.v1_notification_push_outbox
     where notification_id = '91000000-0000-4000-8000-000000000009'),
    'sent', 2, null, null
  )$$,
  'Service records the transport result'
);

select ok(
  (select status = 'sent' and sent_device_count = 2
     and completed_at is not null and lease_until is null
   from public.v1_notification_push_outbox
   where notification_id = '91000000-0000-4000-8000-000000000009'),
  'Completed delivery is terminal and retains its device count'
);

select is(
  public.v1_claim_notification_push(
    '91000000-0000-4000-8000-000000000009'
  ),
  null::jsonb,
  'A sent outbox command cannot be claimed twice'
);

select * from finish();
rollback;
