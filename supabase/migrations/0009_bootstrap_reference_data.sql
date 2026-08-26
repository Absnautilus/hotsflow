-- System reference data: the module registry, the four system roles, and
-- the CORE permissions that RLS policies and functions hardcode by slug
-- (e.g. 0007's properties_update policy literally checks
-- 'core.property.manage'). This data was previously only in
-- supabase/seed.sql, which — per Supabase's own convention — never runs
-- against a real project (only local `db reset`). That meant a hosted
-- project would have an empty permissions table forever, and every policy
-- that checks a core.* slug would silently deny everyone, permanently.
--
-- Idempotent via ON CONFLICT, so this migration converges to the same state
-- whether it's the first run or the tenth. seed.sql is updated separately to
-- stop inserting this same data (would otherwise collide on the unique
-- slugs) and to look up these ids by slug instead of assuming fixed uuids —
-- this migration deliberately does not hardcode ids either, for the same
-- reason.

-- ---------------------------------------------------------------------------
-- modules — the three real applications this platform core exists for
-- ---------------------------------------------------------------------------
insert into modules (slug, display_name, status) values
  ('guest_requests', 'Guest Requests', 'active'),
  ('transfers', 'Transfers', 'active'),
  ('shifts', 'Shifts', 'active')
on conflict (slug) do update set
  display_name = excluded.display_name,
  status = excluded.status;

-- ---------------------------------------------------------------------------
-- roles — the four system roles from the Architecture Proposal's own
-- examples, now carrying their rank (see 0008)
-- ---------------------------------------------------------------------------
insert into roles (slug, display_name, scope, is_system, rank) values
  ('receptionist', 'Receptionist', 'property', true, 10),
  ('manager', 'Manager', 'property', true, 20),
  ('property_admin', 'Property Admin', 'property', true, 30),
  ('organization_admin', 'Organization Admin', 'organization', true, 40)
on conflict (slug) do update set
  display_name = excluded.display_name,
  scope = excluded.scope,
  is_system = excluded.is_system,
  rank = excluded.rank;

-- ---------------------------------------------------------------------------
-- permissions — core (module_id null) only. Module-specific permissions
-- (e.g. a future 'guest_requests.manage') are that module's own concern to
-- create when it migrates — see docs/module-integration.md — not
-- pre-populated here speculatively.
-- ---------------------------------------------------------------------------
insert into permissions (slug, module_id) values
  ('core.organization.manage', null),
  ('core.property.manage', null),
  ('core.staff.manage', null),
  ('core.roles.assign', null)
on conflict (slug) do nothing;

-- ---------------------------------------------------------------------------
-- role_permissions — only the grants required for the system roles above to
-- actually function (see docs/permissions.md's hierarchy table for the
-- full reasoning). Composite PK, nothing to update on conflict.
-- ---------------------------------------------------------------------------
insert into role_permissions (role_id, permission_id)
select r.id, p.id from roles r, permissions p
where (r.slug, p.slug) in (
  ('organization_admin', 'core.organization.manage'),
  ('organization_admin', 'core.property.manage'),
  ('organization_admin', 'core.staff.manage'),
  ('organization_admin', 'core.roles.assign'),
  ('property_admin', 'core.property.manage'),
  ('property_admin', 'core.staff.manage'),
  ('property_admin', 'core.roles.assign'),
  ('manager', 'core.staff.manage'),
  ('manager', 'core.roles.assign')
)
on conflict (role_id, permission_id) do nothing;
