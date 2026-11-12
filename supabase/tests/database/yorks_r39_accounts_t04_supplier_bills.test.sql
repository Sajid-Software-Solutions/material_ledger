begin;

create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();

select ok(
  (select count(*) from public.v1_capability_catalog capability
   where public.v1_accounts_is_capability_key(capability.capability_key)
     and capability.status='operational'
     and capability.authorization_mode='enforced'
     and capability.is_assignable)=15
  and (select count(*) from public.v1_capability_catalog capability
   where public.v1_accounts_is_capability_key(capability.capability_key)
     and capability.status='planned'
     and capability.authorization_mode='shadow'
     and not capability.is_assignable)=0,
  'T04 supplier-cost capabilities remain active after T06 export promotion'
);

select ok(
  (select bool_and(relrowsecurity) from pg_class where oid=any(array[
    'public.v1_accounts_supplier_bills'::regclass,
    'public.v1_accounts_supplier_payments'::regclass]))
  and not has_table_privilege(
    'authenticated','public.v1_accounts_supplier_bills','select'
  )
  and not has_table_privilege(
    'authenticated','public.v1_accounts_supplier_payments','insert'
  ),
  'Supplier costs and payments are unavailable through direct Data API tables'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.v1_create_supplier_bill_draft(uuid,uuid,text,text,date,date,text,text,text,uuid,uuid,uuid,text,text,uuid)',
    'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.v1_record_supplier_payment(uuid,uuid,integer,date,text,text,text,text,text,uuid)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated','public.v1_accounts_supplier_bill_snapshot(uuid)','execute'
  )
  and not has_function_privilege(
    'authenticated','public.v1_accounts_supplier_paid_amount(uuid)','execute'
  ),
  'Only protected T04 commands and projections are exposed'
);

insert into public.v1_projects(
  id,project_ref,name,state,current_action_owner_role,
  created_by_auth_user_id,created_by_role
) values
('39410000-0000-4000-8000-000000000001','R39-T04-001',
 'R39 Supplier Matching','active','project_engineer',
 '10000000-0000-4000-8000-000000000004','admin'),
('39410000-0000-4000-8000-000000000002','R39-T04-002',
 'R39 Supplier Isolation','active','project_engineer',
 '10000000-0000-4000-8000-000000000004','admin');

insert into public.v1_project_scopes(
  id,project_id,scope_kind,scope_code,name,is_immutable
) values
('39420000-0000-4000-8000-000000000001',
 '39410000-0000-4000-8000-000000000001','building','b01','Building 01',false),
('39420000-0000-4000-8000-000000000002',
 '39410000-0000-4000-8000-000000000002','building','b01','Building 01',false);

insert into public.v1_project_members(
  project_id,member_auth_user_id,project_role,effective_from,reason,
  assigned_by_auth_user_id,assigned_by_role
) values(
 '39410000-0000-4000-8000-000000000001',
 '10000000-0000-4000-8000-000000000001','project_engineer',
 clock_timestamp()-interval '1 day','T04 engineering isolation fixture',
 '10000000-0000-4000-8000-000000000004','admin'
);

-- Current commercial documents, linked to their owning projects.
insert into public.v1_documents(
  id,classification,created_by_auth_user_id,created_by_role
) values
('39430000-0000-4000-8000-000000000001','commercial',
 '10000000-0000-4000-8000-000000000004','admin'),
('39430000-0000-4000-8000-000000000002','commercial',
 '10000000-0000-4000-8000-000000000004','admin'),
('39430000-0000-4000-8000-000000000003','commercial',
 '10000000-0000-4000-8000-000000000004','admin');
insert into public.v1_document_versions(
  id,document_id,revision_number,object_path,original_file_name,mime_type,
  byte_size,sha256,origin,uploaded_by_auth_user_id,uploaded_by_role
) values
('39431000-0000-4000-8000-000000000001',
 '39430000-0000-4000-8000-000000000001',1,'r39/t04/po.pdf','po.pdf',
 'application/pdf',128,repeat('a',64),'uploaded',
 '10000000-0000-4000-8000-000000000004','admin'),
('39431000-0000-4000-8000-000000000002',
 '39430000-0000-4000-8000-000000000002',1,'r39/t04/invoice.pdf','invoice.pdf',
 'application/pdf',128,repeat('b',64),'uploaded',
 '10000000-0000-4000-8000-000000000004','admin'),
('39431000-0000-4000-8000-000000000003',
 '39430000-0000-4000-8000-000000000003',1,'r39/t04/cross.pdf','cross.pdf',
 'application/pdf',128,repeat('c',64),'uploaded',
 '10000000-0000-4000-8000-000000000004','admin');
update public.v1_documents set current_version_id=case id
  when '39430000-0000-4000-8000-000000000001' then '39431000-0000-4000-8000-000000000001'::uuid
  when '39430000-0000-4000-8000-000000000002' then '39431000-0000-4000-8000-000000000002'::uuid
  else '39431000-0000-4000-8000-000000000003'::uuid end
where id in(
 '39430000-0000-4000-8000-000000000001',
 '39430000-0000-4000-8000-000000000002',
 '39430000-0000-4000-8000-000000000003'
);
insert into public.v1_document_links(
  id,document_id,project_id,entity_type,entity_id,
  linked_by_auth_user_id,linked_by_role
) values
('39432000-0000-4000-8000-000000000001',
 '39430000-0000-4000-8000-000000000001',
 '39410000-0000-4000-8000-000000000001','project',
 '39410000-0000-4000-8000-000000000001',
 '10000000-0000-4000-8000-000000000004','admin'),
('39432000-0000-4000-8000-000000000002',
 '39430000-0000-4000-8000-000000000002',
 '39410000-0000-4000-8000-000000000001','project',
 '39410000-0000-4000-8000-000000000001',
 '10000000-0000-4000-8000-000000000004','admin'),
('39432000-0000-4000-8000-000000000003',
 '39430000-0000-4000-8000-000000000003',
 '39410000-0000-4000-8000-000000000002','project',
 '39410000-0000-4000-8000-000000000002',
 '10000000-0000-4000-8000-000000000004','admin');

-- Minimal existing operational chain for one trusted confirmed receipt.
insert into public.v1_material_requests(
  id,project_id,scope_id,request_number,title,timing,state,record_version,
  created_by_auth_user_id,requester_display_name,requester_project_role,
  current_action_owner_role,current_action_code,submitted_at,
  project_engineer_snapshot
) values(
 '39440000-0000-4000-8000-000000000001',
 '39410000-0000-4000-8000-000000000001',
 '39420000-0000-4000-8000-000000000001','R39-T04-001-MR001',
 'Supplier receipt evidence','normal','received',1,
 '10000000-0000-4000-8000-000000000002','Local Site Engineer','site_engineer',
 'project_engineer','material_request_close_review',clock_timestamp(),
 '[{"display_name":"Local Project Engineer"}]'::jsonb
);
insert into public.v1_material_request_lines(
  id,request_id,display_order,source_kind,item_description,brand_origin,
  requested_qty,unit
) values(
 '39441000-0000-4000-8000-000000000001',
 '39440000-0000-4000-8000-000000000001',1,'custom',
 'Copper pipe','UAE',5,'Mtr'
);
insert into public.v1_procurement_arrangements(
  id,request_id,arrangement_version,status,is_current,
  started_by_auth_user_id,saved_by_auth_user_id,saved_at
) values(
 '39442000-0000-4000-8000-000000000001',
 '39440000-0000-4000-8000-000000000001',1,'approved',true,
 '10000000-0000-4000-8000-000000000003',
 '10000000-0000-4000-8000-000000000003',clock_timestamp()
);
insert into public.v1_procurement_arrangement_lines(
  id,arrangement_id,request_line_id,source_kind,decision,arranged_qty
) values(
 '39443000-0000-4000-8000-000000000001',
 '39442000-0000-4000-8000-000000000001',
 '39441000-0000-4000-8000-000000000001','external_supplier','full',5
);
insert into public.v1_material_request_line_approvals(
  request_line_id,arrangement_line_id,arrangement_id,approved_qty,
  approved_by_auth_user_id
) values(
 '39441000-0000-4000-8000-000000000001',
 '39443000-0000-4000-8000-000000000001',
 '39442000-0000-4000-8000-000000000001',5,
 '10000000-0000-4000-8000-000000000001'
);
insert into public.v1_material_dispatches(
  id,request_id,project_id,dispatch_number,dispatch_date,delivery_reference,
  state,dispatched_by_auth_user_id,dispatched_by_role
) values(
 '39444000-0000-4000-8000-000000000001',
 '39440000-0000-4000-8000-000000000001',
 '39410000-0000-4000-8000-000000000001','R39-T04-DSP001',current_date,
 'DN-R39-T04-001','received','10000000-0000-4000-8000-000000000003',
 'procurement'
);
insert into public.v1_material_dispatch_lines(
  id,dispatch_id,request_line_id,arrangement_line_id,source_kind,
  external_supplier,item_description,brand_origin,unit,
  approved_qty_snapshot,dispatched_qty
) values(
 '39445000-0000-4000-8000-000000000001',
 '39444000-0000-4000-8000-000000000001',
 '39441000-0000-4000-8000-000000000001',
 '39443000-0000-4000-8000-000000000001','external_supplier',
 'Gulf Air Controls LLC','Copper pipe','UAE','Mtr',5,5
);
insert into public.v1_receipt_reviews(
  id,dispatch_id,request_id,reviewed_by_auth_user_id,reviewed_by_role
) values(
 '39446000-0000-4000-8000-000000000001',
 '39444000-0000-4000-8000-000000000001',
 '39440000-0000-4000-8000-000000000001',
 '10000000-0000-4000-8000-000000000002','site_engineer'
);
insert into public.v1_receipt_review_lines(
  id,receipt_review_id,dispatch_line_id,outcome,dispatched_qty_snapshot,
  good_qty,exception_qty
) values(
 '39447000-0000-4000-8000-000000000001',
 '39446000-0000-4000-8000-000000000001',
 '39445000-0000-4000-8000-000000000001','received',5,5,0
);

create temporary table v1_r39_t04_results(
  result_key text primary key,payload jsonb not null
);
grant select,insert,update on v1_r39_t04_results to authenticated;

set local role authenticated;
select set_config(
 'request.jwt.claims',
 '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer","app_user_id":"usr-local-project-engineer"}}',
 true
);
-- Owner decision of 11 November 2026: a PE member sees supplier costs.
select lives_ok(
 $sql$select public.v1_list_supplier_bills(
  '39410000-0000-4000-8000-000000000001',null,null,null,null,null,25
 )$sql$,
 'Project Engineer members may query supplier cost projections'
);

select set_config(
 'request.jwt.claims',
 '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement","app_user_id":"usr-local-procurement"}}',
 true
);
select throws_ok(
 $sql$select public.v1_create_supplier_bill_draft(
  '39410000-0000-4000-8000-000000000001',null,'Cross Project Supplier','X-001',
  date '2026-08-01',date '2026-08-31','1000.00','5.0000','PO-X',null,null,
  '39430000-0000-4000-8000-000000000003',null,null,
  '39490000-0000-4000-8000-000000000001'
 )$sql$,
 '22023','R39_ACCOUNTS_SUPPLIER_DOCUMENT_INVALID',
 'A document linked to another project cannot become supplier evidence'
);

insert into v1_r39_t04_results select 'blocked',
 public.v1_create_supplier_bill_draft(
  '39410000-0000-4000-8000-000000000001',null,'Gulf Air Controls LLC','SUP-100',
  date '2026-08-01',date '2026-08-31','1000.00','5.0000',null,null,null,null,
  null,'Invoice evidence is pending','39490000-0000-4000-8000-000000000002'
 );
select is(
 (select payload->>'match_status' from v1_r39_t04_results where result_key='blocked'),
 'blocked','Fewer than two evidence groups is server-derived as Blocked'
);
select throws_ok(
 $sql$select public.v1_create_supplier_bill_draft(
  '39410000-0000-4000-8000-000000000001',null,'gulf air controls llc','sup-100',
  date '2026-08-01',date '2026-08-31','1000.00','5.0000',null,null,null,null,
  null,null,'39490000-0000-4000-8000-000000000003'
 )$sql$,
 '23505','R39_ACCOUNTS_DUPLICATE_SUPPLIER_BILL',
 'Supplier and invoice reference are case-insensitively unique per project'
);

insert into v1_r39_t04_results select 'review',
 public.v1_create_supplier_bill_draft(
  '39410000-0000-4000-8000-000000000001',null,'MEP Trading LLC','SUP-101',
  date '2026-08-02',date '2026-09-01','200.00','5.0000','PO-101',
  '39430000-0000-4000-8000-000000000001',null,
  '39430000-0000-4000-8000-000000000002',null,null,
  '39490000-0000-4000-8000-000000000004'
 );
select is(
 (select payload->>'match_status' from v1_r39_t04_results where result_key='review'),
 'review','Two evidence groups is server-derived as Review'
);

insert into v1_r39_t04_results select 'matched',
 public.v1_create_supplier_bill_draft(
  '39410000-0000-4000-8000-000000000001',null,'Yorks Supplier LLC','SUP-102',
  date '2026-08-03',date '2026-09-02','1000.00','5.0000','PO-102',
  '39430000-0000-4000-8000-000000000001',
  '39446000-0000-4000-8000-000000000001',
  '39430000-0000-4000-8000-000000000002',null,'Trusted receipt match',
  '39490000-0000-4000-8000-000000000005'
 );
select is(
 (select payload->>'match_status' from v1_r39_t04_results where result_key='matched'),
 'matched','PO, accepted receipt and supplier invoice derive Matched'
);
select is(
 public.v1_get_supplier_bill(
  '39410000-0000-4000-8000-000000000001',
  (select (payload->>'supplier_bill_id')::uuid from v1_r39_t04_results where result_key='matched')
 )->'supplier_bill'->>'accepted_delivery_reference',
 'DN-R39-T04-001',
 'Delivery reference is copied only from the trusted confirmed receipt chain'
);
select ok(
 position('client_invoice' in public.v1_get_supplier_bill(
  '39410000-0000-4000-8000-000000000001',
  (select (payload->>'supplier_bill_id')::uuid from v1_r39_t04_results where result_key='matched')
 )::text)=0,
 'Procurement supplier projections contain no client-invoice response key'
);
select throws_ok(
 $sql$select public.v1_approve_supplier_bill(
  '39410000-0000-4000-8000-000000000001',
  (select (payload->>'supplier_bill_id')::uuid from v1_r39_t04_results where result_key='matched'),
  1,null,'39490000-0000-4000-8000-000000000006'
 )$sql$,
 '42501','R39_ACCOUNTS_ACCESS_DENIED',
 'Procurement cannot approve its own supplier evidence'
);

select set_config(
 'request.jwt.claims',
 '{"sub":"10000000-0000-4000-8000-000000000013","role":"authenticated","app_metadata":{"role":"accountant","app_user_id":"usr-local-accountant"}}',
 true
);
select throws_ok(
 $sql$select public.v1_approve_supplier_bill(
  '39410000-0000-4000-8000-000000000001',
  (select (payload->>'supplier_bill_id')::uuid from v1_r39_t04_results where result_key='blocked'),
  1,null,'39490000-0000-4000-8000-000000000007'
 )$sql$,
 '23514','R39_ACCOUNTS_SUPPLIER_INVOICE_DOCUMENT_REQUIRED',
 'A current supplier-invoice document is mandatory for approval'
);
select throws_ok(
 $sql$select public.v1_approve_supplier_bill(
  '39410000-0000-4000-8000-000000000001',
  (select (payload->>'supplier_bill_id')::uuid from v1_r39_t04_results where result_key='review'),
  1,null,'39490000-0000-4000-8000-000000000008'
 )$sql$,
 '23514','R39_ACCOUNTS_SUPPLIER_BILL_NOT_MATCHED',
 'Accountant cannot approve Review or Blocked evidence'
);
insert into v1_r39_t04_results select 'matched_approved',
 public.v1_approve_supplier_bill(
  '39410000-0000-4000-8000-000000000001',
  (select (payload->>'supplier_bill_id')::uuid from v1_r39_t04_results where result_key='matched'),
  1,null,'39490000-0000-4000-8000-000000000009'
 );
select is(
 (select payload->>'payment_status' from v1_r39_t04_results where result_key='matched_approved'),
 'approved','Matched supplier evidence becomes payable only after Accounts approval'
);
insert into v1_r39_t04_results select 'payment_1',
 public.v1_record_supplier_payment(
  '39410000-0000-4000-8000-000000000001',
  (select (payload->>'supplier_bill_id')::uuid from v1_r39_t04_results where result_key='matched'),
  2,date '2026-08-10','bank_transfer','PAY-102-A','600.00','First instalment',null,
  '39490000-0000-4000-8000-000000000010'
 );
select is(
 (select payload->>'payment_status' from v1_r39_t04_results where result_key='payment_1'),
 'partially_paid','Partial supplier payments remain explicitly visible'
);
select is(
 public.v1_record_supplier_payment(
  '39410000-0000-4000-8000-000000000001',
  (select (payload->>'supplier_bill_id')::uuid from v1_r39_t04_results where result_key='matched'),
  2,date '2026-08-10','bank_transfer','PAY-102-A','600.00','First instalment',null,
  '39490000-0000-4000-8000-000000000010'
 )->>'replayed','true','Payment retries replay instead of duplicating money'
);
select throws_ok(
 $sql$select public.v1_record_supplier_payment(
  '39410000-0000-4000-8000-000000000001',
  (select (payload->>'supplier_bill_id')::uuid from v1_r39_t04_results where result_key='matched'),
  3,date '2026-08-11','bank_transfer','PAY-102-OVER','500.00',null,null,
  '39490000-0000-4000-8000-000000000011'
 )$sql$,
 '23514','R39_ACCOUNTS_SUPPLIER_PAYMENT_CAP_EXCEEDED',
 'Supplier payments cannot exceed the remaining total including VAT'
);
insert into v1_r39_t04_results select 'payment_2',
 public.v1_record_supplier_payment(
  '39410000-0000-4000-8000-000000000001',
  (select (payload->>'supplier_bill_id')::uuid from v1_r39_t04_results where result_key='matched'),
  3,date '2026-08-11','bank_transfer','PAY-102-B','450.00','Final instalment',null,
  '39490000-0000-4000-8000-000000000012'
 );
select is(
 (select payload->>'payment_status' from v1_r39_t04_results where result_key='payment_2'),
 'paid','The final capped instalment derives Paid'
);
insert into v1_r39_t04_results select 'reversal',
 public.v1_reverse_supplier_payment(
  '39410000-0000-4000-8000-000000000001',
  (select (payload->>'supplier_bill_id')::uuid from v1_r39_t04_results where result_key='matched'),
  4,(select (payload->>'payment_id')::uuid from v1_r39_t04_results where result_key='payment_1'),
  date '2026-08-12','REV-102-A','Bank recalled first transfer',
  '39490000-0000-4000-8000-000000000013'
 );
select is(
 (select payload->>'payment_status' from v1_r39_t04_results where result_key='reversal'),
 'partially_paid','A linked append-only reversal recomputes the paid state'
);
select throws_ok(
 $sql$select public.v1_reverse_supplier_payment(
  '39410000-0000-4000-8000-000000000001',
  (select (payload->>'supplier_bill_id')::uuid from v1_r39_t04_results where result_key='matched'),
  5,(select (payload->>'payment_id')::uuid from v1_r39_t04_results where result_key='payment_1'),
  date '2026-08-13','REV-102-A2','Second reversal must fail',
  '39490000-0000-4000-8000-000000000014'
 )$sql$,
 '55000','R39_ACCOUNTS_SUPPLIER_PAYMENT_ALREADY_REVERSED',
 'The same supplier payment cannot be reversed twice'
);
select throws_ok(
 $sql$select public.v1_cancel_supplier_bill(
  '39410000-0000-4000-8000-000000000001',
  (select (payload->>'supplier_bill_id')::uuid from v1_r39_t04_results where result_key='matched'),
  5,'Cannot cancel money history','39490000-0000-4000-8000-000000000015'
 )$sql$,
 '55000','R39_ACCOUNTS_SUPPLIER_BILL_HAS_PAYMENTS',
 'A bill with net supplier payments cannot be cancelled'
);

select set_config(
 'request.jwt.claims',
 '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin","app_user_id":"usr-local-admin"}}',
 true
);
select throws_ok(
 $sql$select public.v1_approve_supplier_bill(
  '39410000-0000-4000-8000-000000000001',
  (select (payload->>'supplier_bill_id')::uuid from v1_r39_t04_results where result_key='review'),
  1,null,'39490000-0000-4000-8000-000000000016'
 )$sql$,
 '22023','R39_ACCOUNTS_ADMIN_EXCEPTION_REASON_REQUIRED',
 'Admin cannot bypass matching without an explicit reason'
);
insert into v1_r39_t04_results select 'review_approved',
 public.v1_approve_supplier_bill(
  '39410000-0000-4000-8000-000000000001',
  (select (payload->>'supplier_bill_id')::uuid from v1_r39_t04_results where result_key='review'),
  1,'Approved pending delivery reference during controlled adoption',
  '39490000-0000-4000-8000-000000000017'
 );
select is(
 public.v1_get_supplier_bill(
  '39410000-0000-4000-8000-000000000001',
  (select (payload->>'supplier_bill_id')::uuid from v1_r39_t04_results where result_key='review')
 )->'supplier_bill'->>'approval_admin_exception_reason',
 'Approved pending delivery reference during controlled adoption',
 'Admin exception reason is retained in the protected bill projection'
);
select throws_ok(
 $sql$select public.v1_record_supplier_payment(
  '39410000-0000-4000-8000-000000000001',
  (select (payload->>'supplier_bill_id')::uuid from v1_r39_t04_results where result_key='review'),
  2,date '2026-08-14','bank_transfer','PAY-101-A','100.00',null,null,
  '39490000-0000-4000-8000-000000000018'
 )$sql$,
 '22023','R39_ACCOUNTS_ADMIN_EXCEPTION_REASON_REQUIRED',
 'Every unmatched payment requires its own current Admin exception reason'
);
insert into v1_r39_t04_results select 'review_payment',
 public.v1_record_supplier_payment(
  '39410000-0000-4000-8000-000000000001',
  (select (payload->>'supplier_bill_id')::uuid from v1_r39_t04_results where result_key='review'),
  2,date '2026-08-14','bank_transfer','PAY-101-A','100.00',null,
  'Payment approved while accepted delivery remains pending',
  '39490000-0000-4000-8000-000000000019'
 );
select is(
 (select payload->>'payment_status' from v1_r39_t04_results where result_key='review_payment'),
 'partially_paid','Admin can make an audited unmatched partial payment exception'
);

reset role;
select throws_ok(
 $sql$update public.v1_accounts_supplier_payments
 set amount=amount+1
 where id=(select (payload->>'payment_id')::uuid from v1_r39_t04_results where result_key='payment_2')$sql$,
 '42501','R39_ACCOUNTS_APPEND_ONLY_FACT',
 'Supplier payment facts are append-only even for privileged SQL callers'
);
select ok(
 exists(
  select 1 from public.v1_audit_events
  where event_type='accounts.supplier_bill.approved'
    and reason='Approved pending delivery reference during controlled adoption'
 ) and exists(
  select 1 from public.v1_audit_events
  where event_type='accounts.supplier_payment.recorded'
    and reason='Payment approved while accepted delivery remains pending'
 ),
 'Admin supplier-bill and payment exceptions retain trusted audit reasons'
);

select * from finish();
rollback;
