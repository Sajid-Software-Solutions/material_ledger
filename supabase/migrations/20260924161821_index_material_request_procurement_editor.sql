-- Cover the optional Procurement editor FK without indexing default-off rows.
-- Data preservation: index-only change. Rollback: drop this index after
-- checking FK delete/update plans; no request data changes.
create index if not exists v1_material_requests_procurement_editor_idx
  on public.v1_material_requests (procurement_editor_auth_user_id)
  where procurement_editor_auth_user_id is not null;
