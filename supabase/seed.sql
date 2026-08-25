-- Dev-only seed data. Applied by `supabase db reset` (never by `db push` /
-- `migration up` against a real project — this file is not a migration).
-- No real credentials, no personal emails: everything below is fictitious.
--
-- Builds:
--   Organization A
--       +-- Property A1  (guest_requests ON, transfers OFF, shifts ON)
--       +-- Property A2  (guest_requests OFF, transfers ON, shifts ON)
--   Organization B
--       +-- Property B1  (guest_requests ON, transfers ON, shifts OFF)
--
-- ...plus the 4 roles from the Architecture Proposal's own examples
-- (organization_admin, property_admin, manager, receptionist), the module
-- registry, and enough role_permissions to make module entitlement and
-- role-based access actually testable end to end.

-- ---------------------------------------------------------------------------
-- organizations / properties
-- ---------------------------------------------------------------------------
insert into organizations (id, name, slug) values
  ('a0000000-0000-0000-0000-000000000001', 'Organization A', 'org-a'),
  ('a0000000-0000-0000-0000-000000000002', 'Organization B', 'org-b');

insert into properties (id, organization_id, name, slug) values
  ('a1000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'Property A1', 'a1'),
  ('a1000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'Property A2', 'a2'),
  ('a1000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000002', 'Property B1', 'b1');

-- ---------------------------------------------------------------------------
-- modules / property_modules — three different entitlement combinations on
-- purpose, so "does this property have this module?" is actually exercised
-- three different ways, not just ON/ON/ON everywhere.
-- ---------------------------------------------------------------------------
insert into modules (id, slug, display_name) values
  ('a2000000-0000-0000-0000-000000000001', 'guest_requests', 'Guest Requests'),
  ('a2000000-0000-0000-0000-000000000002', 'transfers', 'Transfers'),
  ('a2000000-0000-0000-0000-000000000003', 'shifts', 'Shifts');

insert into property_modules (property_id, module_id, enabled) values
  ('a1000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001', true),   -- A1: guest_requests ON
  ('a1000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000002', false),  -- A1: transfers OFF
  ('a1000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000003', true),   -- A1: shifts ON
  ('a1000000-0000-0000-0000-000000000002', 'a2000000-0000-0000-0000-000000000001', false),  -- A2: guest_requests OFF
  ('a1000000-0000-0000-0000-000000000002', 'a2000000-0000-0000-0000-000000000002', true),   -- A2: transfers ON
  ('a1000000-0000-0000-0000-000000000002', 'a2000000-0000-0000-0000-000000000003', true),   -- A2: shifts ON
  ('a1000000-0000-0000-0000-000000000003', 'a2000000-0000-0000-0000-000000000001', true),   -- B1: guest_requests ON
  ('a1000000-0000-0000-0000-000000000003', 'a2000000-0000-0000-0000-000000000002', true),   -- B1: transfers ON
  ('a1000000-0000-0000-0000-000000000003', 'a2000000-0000-0000-0000-000000000003', false);  -- B1: shifts OFF

-- ---------------------------------------------------------------------------
-- roles / permissions / role_permissions
-- ---------------------------------------------------------------------------
insert into roles (id, slug, display_name, scope) values
  ('a3000000-0000-0000-0000-000000000001', 'organization_admin', 'Organization Admin', 'organization'),
  ('a3000000-0000-0000-0000-000000000002', 'property_admin', 'Property Admin', 'property'),
  ('a3000000-0000-0000-0000-000000000003', 'manager', 'Manager', 'property'),
  ('a3000000-0000-0000-0000-000000000004', 'receptionist', 'Receptionist', 'property');

insert into permissions (id, slug, module_id) values
  ('a4000000-0000-0000-0000-000000000001', 'core.organization.manage', null),
  ('a4000000-0000-0000-0000-000000000002', 'core.property.manage', null),
  ('a4000000-0000-0000-0000-000000000003', 'core.staff.manage', null),
  ('a4000000-0000-0000-0000-000000000004', 'shifts.use', 'a2000000-0000-0000-0000-000000000003'),
  ('a4000000-0000-0000-0000-000000000005', 'transfers.use', 'a2000000-0000-0000-0000-000000000002'),
  ('a4000000-0000-0000-0000-000000000006', 'guest_requests.view', 'a2000000-0000-0000-0000-000000000001');

-- organization_admin: everything.
-- property_admin: everything except organization-level administration.
-- manager: every module, no staff/property administration
--   (matches the Architecture Proposal's own example: "Manager -> puo usare
--   tutti i moduli -> puo gestire staff" — staff management included).
-- receptionist: transfers + guest_requests only, no configuration
--   ("Receptionist -> puo usare Transfers -> puo vedere Guest Requests ->
--   non puo modificare configurazione hotel").
insert into role_permissions (role_id, permission_id) values
  ('a3000000-0000-0000-0000-000000000001', 'a4000000-0000-0000-0000-000000000001'),
  ('a3000000-0000-0000-0000-000000000001', 'a4000000-0000-0000-0000-000000000002'),
  ('a3000000-0000-0000-0000-000000000001', 'a4000000-0000-0000-0000-000000000003'),
  ('a3000000-0000-0000-0000-000000000001', 'a4000000-0000-0000-0000-000000000004'),
  ('a3000000-0000-0000-0000-000000000001', 'a4000000-0000-0000-0000-000000000005'),
  ('a3000000-0000-0000-0000-000000000001', 'a4000000-0000-0000-0000-000000000006'),
  ('a3000000-0000-0000-0000-000000000002', 'a4000000-0000-0000-0000-000000000002'),
  ('a3000000-0000-0000-0000-000000000002', 'a4000000-0000-0000-0000-000000000003'),
  ('a3000000-0000-0000-0000-000000000002', 'a4000000-0000-0000-0000-000000000004'),
  ('a3000000-0000-0000-0000-000000000002', 'a4000000-0000-0000-0000-000000000005'),
  ('a3000000-0000-0000-0000-000000000002', 'a4000000-0000-0000-0000-000000000006'),
  ('a3000000-0000-0000-0000-000000000003', 'a4000000-0000-0000-0000-000000000003'),
  ('a3000000-0000-0000-0000-000000000003', 'a4000000-0000-0000-0000-000000000004'),
  ('a3000000-0000-0000-0000-000000000003', 'a4000000-0000-0000-0000-000000000005'),
  ('a3000000-0000-0000-0000-000000000003', 'a4000000-0000-0000-0000-000000000006'),
  ('a3000000-0000-0000-0000-000000000004', 'a4000000-0000-0000-0000-000000000005'),
  ('a3000000-0000-0000-0000-000000000004', 'a4000000-0000-0000-0000-000000000006');

-- ---------------------------------------------------------------------------
-- profiles / memberships — needs real auth.users rows first
-- ---------------------------------------------------------------------------
-- Deliberately NOT inserted via raw SQL here: auth.users is managed by
-- Supabase Auth (GoTrue) and has more invariants than a plain insert can
-- safely satisfy (this is the same reason guest_requests' own seed bootstraps
-- its first admin by hand through Studio rather than SQL — see its README).
--
-- Before running the block below:
--   1. `supabase start`
--   2. create 5 users (any fictitious @example.test email, any password,
--      "Auto Confirm User" on) — via Studio (Authentication -> Users) or:
--        npx supabase auth admin create-user --local \
--          --email org-admin@example.test --password 'test-password-only' \
--          --data '{}' | jq -r .id
--   3. replace the five placeholder UUIDs below with the real ids returned.
--
-- What this gives you, once run:
--   - org_admin:    org-wide membership on Organization A (no per-property row)
--   - multi_user:   receptionist on BOTH A1 and A2 (multi-property)
--   - a1_manager:   manager on A1 only
--   - b1_receptionist: receptionist on B1 only (a different organization)
--   - suspended_user: membership on A1 with status = 'suspended'

-- insert into profiles (id, full_name) values
--   ('00000000-0000-0000-0000-0000000a0001', 'Org Admin (seed)'),
--   ('00000000-0000-0000-0000-0000000a0002', 'Multi Property User (seed)'),
--   ('00000000-0000-0000-0000-0000000a0003', 'A1 Manager (seed)'),
--   ('00000000-0000-0000-0000-0000000a0004', 'B1 Receptionist (seed)'),
--   ('00000000-0000-0000-0000-0000000a0005', 'Suspended User (seed)');
--
-- insert into memberships (profile_id, organization_id, role_id, status) values
--   ('00000000-0000-0000-0000-0000000a0001', 'a0000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001', 'active');
--
-- insert into memberships (profile_id, property_id, role_id, status) values
--   ('00000000-0000-0000-0000-0000000a0002', 'a1000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000004', 'active'),
--   ('00000000-0000-0000-0000-0000000a0002', 'a1000000-0000-0000-0000-000000000002', 'a3000000-0000-0000-0000-000000000004', 'active'),
--   ('00000000-0000-0000-0000-0000000a0003', 'a1000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000003', 'active'),
--   ('00000000-0000-0000-0000-0000000a0004', 'a1000000-0000-0000-0000-000000000003', 'a3000000-0000-0000-0000-000000000004', 'active'),
--   ('00000000-0000-0000-0000-0000000a0005', 'a1000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000004', 'suspended');
