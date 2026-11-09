begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();
select ok(not has_function_privilege('anon','public.v1_inventory_movement_page_v2(uuid,text,text,timestamptz,uuid,integer,timestamptz,timestamptz)','execute'),'Anonymous history denied');
insert into public.v1_inventory_items(id,item_description,unit,created_by_auth_user_id)
values('c8000000-0000-4000-8000-000000000001','History witness','Nos','10000000-0000-4000-8000-000000000003');
insert into public.v1_inventory_balances(inventory_item_id,on_hand_qty) values('c8000000-0000-4000-8000-000000000001',5);
insert into public.v1_inventory_movements(inventory_item_id,movement_type,quantity_delta,on_hand_after_qty,reason,actor_auth_user_id,created_at)
select 'c8000000-0000-4000-8000-000000000001','adjustment',case when n%2=0 then -1 else 1 end,1,'History witness '||n,
'10000000-0000-4000-8000-000000000003','2026-10-01'::timestamptz from generate_series(1,125) n;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"site_engineer"}}',true);
select throws_ok($$select public.v1_inventory_movement_page_v2()$$,'42501','V1_INVENTORY_WORKSPACE_DENIED','Site Engineer cannot read stock history');
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"role":"project_engineer"}}',true);
select throws_ok($$select public.v1_inventory_movement_page_v2()$$,'42501','V1_INVENTORY_WORKSPACE_DENIED','Project Engineer cannot read stock history');
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","app_metadata":{"role":"procurement"}}',true);
select is(jsonb_array_length(public.v1_inventory_movement_page_v2(p_item_id=>'c8000000-0000-4000-8000-000000000001', p_from_at=>'2026-10-01', p_until_at=>'2026-10-02', p_limit=>500)->'items'),125,'Start inclusive range includes all matching records');
select is(jsonb_array_length(public.v1_inventory_movement_page_v2(p_item_id=>'c8000000-0000-4000-8000-000000000001', p_until_at=>'2026-10-01')->'items'),0,'End exclusive range excludes boundary');
select throws_ok($$select public.v1_inventory_movement_page_v2(p_from_at=>'2026-10-02',p_until_at=>'2026-10-01')$$,'22023','V1_INVALID_INPUT','Inverted date range rejected');
create temporary table history_pages(page jsonb);
insert into history_pages select public.v1_inventory_movement_page_v2(p_item_id=>'c8000000-0000-4000-8000-000000000001');
select is((select jsonb_array_length(page->'items') from history_pages),50,'First page is bounded');
select is((select (page->>'has_more')::boolean from history_pages),true,'Older movements remain discoverable');
insert into history_pages select public.v1_inventory_movement_page_v2(p_item_id=>'c8000000-0000-4000-8000-000000000001',p_before_at=>(page#>>'{items,49,created_at}')::timestamptz,p_before_id=>(page#>>'{items,49,id}')::uuid) from history_pages;
select is((select count(distinct row->>'id')::integer from history_pages, lateral jsonb_array_elements(page->'items') row),100,'Equal timestamps paginate without repeats');
select is(jsonb_array_length(public.v1_inventory_movement_page_v2(p_item_id=>'c8000000-0000-4000-8000-000000000001',p_limit=>500)->'items'),125,'Export can read records beyond the old 100 cap');
select is(jsonb_array_length(public.v1_inventory_movement_page_v2(p_item_id=>'c8000000-0000-4000-8000-000000000001',p_kind=>'stockOut',p_limit=>500)->'items'),62,'Signed filtering uses database quantities');
select is(jsonb_array_length(public.v1_inventory_movement_page_v2(p_item_id=>'c8000000-0000-4000-8000-000000000001',p_search=>'witness 125')->'items'),1,'Server search includes older records');
select is(jsonb_array_length(public.v1_inventory_item_workspace_v2('c8000000-0000-4000-8000-000000000001')->'movements'),0,'Item summary no longer downloads unbounded history');
select ok(not (public.v1_inventory_movement_page_v2(p_limit=>1)::text ~ 'unit_cost|total_cost|valuation'),'History excludes commercial fields');
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{"role":"admin"}}',true);
select lives_ok($$select public.v1_inventory_movement_page_v2()$$,'Admin can read history');
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000009","role":"authenticated","app_metadata":{"role":"senior_mechanical_engineer"}}',true);
select lives_ok($$select public.v1_inventory_movement_page_v2()$$,'Senior Mechanical Engineer retains read-only history');
select throws_ok($$select public.v1_adjust_inventory_stock('{"inventory_item_id":"c8000000-0000-4000-8000-000000000001","expected_version":1,"action":"add","quantity":"1","reason":"Not allowed"}'::jsonb,'c8000000-0000-4000-8000-000000000002')$$,'42501','V1_INVENTORY_ADJUST_DENIED','History read does not grant stock writes');
select * from finish();
rollback;
