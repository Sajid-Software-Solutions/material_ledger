-- Procurement simplification: new Delivery Orders receive a trusted number.
-- Existing references, immutable revisions and optional supplier paperwork are
-- retained. Roll back the app first; keep this compatible function and counter
-- so issued numbers are never recycled. No historical row is rewritten.
-- Supplier paperwork is optional; Yorks still allocates the dispatch identity.
alter table public.v1_material_dispatches alter column delivery_reference drop not null;

create table if not exists public.v1_delivery_order_reference_counters (
  project_id uuid primary key references public.v1_projects(id) on delete restrict,
  next_sequence integer not null default 1 check (next_sequence > 0),
  updated_at timestamptz not null default clock_timestamp()
);
alter table public.v1_delivery_order_reference_counters enable row level security;
revoke all on public.v1_delivery_order_reference_counters from public, anon, authenticated;
grant all on public.v1_delivery_order_reference_counters to service_role;

-- Patch the effective functions so the later metadata, prepared-command and
-- capability hardening remain intact. Every patch fails closed on drift.
do $migration$
declare
  definition text;
  anchor text;
  replacement text;
begin
  definition := pg_get_functiondef('public.v1_dispatch_materials(jsonb,uuid)'::regprocedure);
  anchor := 'or v_dispatch_date is null or v_delivery_reference is null or jsonb_typeof(v_lines)';
  if position(anchor in definition) > 0 then
    execute replace(definition, anchor, 'or v_dispatch_date is null or jsonb_typeof(v_lines)');
  elsif position('or v_dispatch_date is null or jsonb_typeof(v_lines)' in definition) = 0 then
    raise exception 'V1_AUTOMATIC_DELIVERY_DISPATCH_ANCHOR_MISSING';
  end if;

  definition := pg_get_functiondef('public.v1_generate_delivery_order(jsonb,uuid)'::regprocedure);
  if position('v1_delivery_order_reference_counters' in definition) > 0 then return; end if;
  anchor := '  v_reference text;';
  if position(anchor in definition) = 0 then
    raise exception 'V1_AUTOMATIC_DELIVERY_DECLARATION_ANCHOR_MISSING';
  end if;
  definition := replace(definition, anchor, anchor || chr(10) || '  v_sequence integer;'
    || chr(10) || '  v_project_reference text;');
  anchor := '    or v_reference is null then';
  if position(anchor in definition) = 0 then
    raise exception 'V1_AUTOMATIC_DELIVERY_VALIDATION_ANCHOR_MISSING';
  end if;
  definition := replace(definition, anchor, '    then');
  anchor := $old$  if not found then
    insert into public.v1_delivery_orders (
      request_id, dispatch_id, project_id, delivery_order_reference,
      created_by_auth_user_id, created_by_role
    ) values (
      v_request.id, v_dispatch.id, v_request.project_id, v_reference,
      v_actor, v_role
    ) returning * into v_delivery_order;
  elsif v_delivery_order.delivery_order_reference <> v_reference then
    raise exception 'V1_DELIVERY_ORDER_REFERENCE_IMMUTABLE' using errcode = '22023';
  end if;$old$;
  replacement := $new$  if not found then
    if v_reference is null then
      select project.project_ref into v_project_reference
      from public.v1_projects project where project.id = v_request.project_id;
      loop
        insert into public.v1_delivery_order_reference_counters(project_id, next_sequence)
        values (v_request.project_id, 2)
        on conflict (project_id) do update set
          next_sequence = public.v1_delivery_order_reference_counters.next_sequence + 1,
          updated_at = clock_timestamp()
        returning next_sequence - 1 into v_sequence;
        v_reference := upper(v_project_reference) || '-DO' ||
          lpad(v_sequence::text, greatest(3, length(v_sequence::text)), '0');
        insert into public.v1_delivery_orders (
          request_id, dispatch_id, project_id, delivery_order_reference,
          created_by_auth_user_id, created_by_role
        ) values (
          v_request.id, v_dispatch.id, v_request.project_id, v_reference,
          v_actor, v_role
        ) on conflict (delivery_order_reference) do nothing
        returning * into v_delivery_order;
        exit when found;
      end loop;
    else
      -- Retained clients may still submit their official manual reference.
      insert into public.v1_delivery_orders (
        request_id, dispatch_id, project_id, delivery_order_reference,
        created_by_auth_user_id, created_by_role
      ) values (
        v_request.id, v_dispatch.id, v_request.project_id, v_reference,
        v_actor, v_role
      ) returning * into v_delivery_order;
    end if;
  elsif v_reference is not null and v_delivery_order.delivery_order_reference <> v_reference then
    raise exception 'V1_DELIVERY_ORDER_REFERENCE_IMMUTABLE' using errcode = '22023';
  end if;
  v_reference := v_delivery_order.delivery_order_reference;$new$;
  if position(anchor in definition) = 0 then
    raise exception 'V1_AUTOMATIC_DELIVERY_INSERT_ANCHOR_MISSING';
  end if;
  execute replace(definition, anchor, replacement);
end;
$migration$;
