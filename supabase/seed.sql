-- Dev-only seed data. Applied by `supabase db reset` (never by `db push` /
-- `migration up` against a real project — this file is not a migration).
-- No real credentials, no personal emails: everything below is fictitious.
--
-- As of Fase 1.1, `modules`, the four system roles, the core permissions,
-- and their role_permissions grants are bootstrapped by migration 0009 —
-- not here (see that migration's header for why: a real, hosted project
-- never applies seed.sql, so anything the RLS policies actually depend on
-- to function has to live in a migration). This file only adds demo/dev
-- data on top: organizations, properties, entitlement combinations, a
-- couple of illustrative module-specific permissions, and — once you
-- complete the manual step below — five test staff accounts.
--
-- Everything below that references modules/roles looks them up by slug,
-- never by a hardcoded id — 0009 doesn't pin fixed ids either, precisely so
-- nothing downstream has to guess them.
--
-- Builds:
--   Organization A
--       +-- Property A1  (guest_requests ON, transfers OFF, shifts ON)
--       +-- Property A2  (guest_requests OFF, transfers ON, shifts ON)
--   Organization B
--       +-- Property B1  (guest_requests ON, transfers ON, shifts OFF)

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
-- property_modules — three different entitlement combinations on purpose,
-- so "does this property have this module?" is actually exercised three
-- different ways, not just ON/ON/ON everywhere. Modules themselves come
-- from migration 0009; looked up here by slug.
-- ---------------------------------------------------------------------------
insert into property_modules (property_id, module_id, enabled)
select v.property_id, m.id, v.enabled
from (values
  ('a1000000-0000-0000-0000-000000000001'::uuid, 'guest_requests', true),   -- A1: guest_requests ON
  ('a1000000-0000-0000-0000-000000000001'::uuid, 'transfers', false),        -- A1: transfers OFF
  ('a1000000-0000-0000-0000-000000000001'::uuid, 'shifts', true),            -- A1: shifts ON
  ('a1000000-0000-0000-0000-000000000002'::uuid, 'guest_requests', false),  -- A2: guest_requests OFF
  ('a1000000-0000-0000-0000-000000000002'::uuid, 'transfers', true),         -- A2: transfers ON
  ('a1000000-0000-0000-0000-000000000002'::uuid, 'shifts', true),            -- A2: shifts ON
  ('a1000000-0000-0000-0000-000000000003'::uuid, 'guest_requests', true),   -- B1: guest_requests ON
  ('a1000000-0000-0000-0000-000000000003'::uuid, 'transfers', true),         -- B1: transfers ON
  ('a1000000-0000-0000-0000-000000000003'::uuid, 'shifts', false)            -- B1: shifts OFF
) as v(property_id, module_slug, enabled)
join modules m on m.slug = v.module_slug;

-- ---------------------------------------------------------------------------
-- Illustrative module-specific permissions — NOT part of the system
-- baseline (0009 only bootstraps core.* permissions). These exist purely so
-- the demo role_permissions below can exercise entitlement + permission
-- together; a real module defines its own permission slugs when it
-- actually migrates (see docs/module-integration.md), these are stand-ins.
-- ---------------------------------------------------------------------------
insert into permissions (slug, module_id)
select 'shifts.use', id from modules where slug = 'shifts'
union all
select 'transfers.use', id from modules where slug = 'transfers'
union all
select 'guest_requests.view', id from modules where slug = 'guest_requests'
on conflict (slug) do nothing;

-- role_permissions for these demo permissions — the four system roles
-- already have their core.* grants from migration 0009; this only adds the
-- module-specific ones on top.
-- organization_admin / property_admin / manager: every module.
-- receptionist: transfers + guest_requests only, no shifts
--   ("Receptionist -> puo usare Transfers -> puo vedere Guest Requests ->
--   non puo modificare configurazione hotel").
insert into role_permissions (role_id, permission_id)
select r.id, p.id from roles r, permissions p
where (r.slug, p.slug) in (
  ('organization_admin', 'shifts.use'),
  ('organization_admin', 'transfers.use'),
  ('organization_admin', 'guest_requests.view'),
  ('property_admin', 'shifts.use'),
  ('property_admin', 'transfers.use'),
  ('property_admin', 'guest_requests.view'),
  ('manager', 'shifts.use'),
  ('manager', 'transfers.use'),
  ('manager', 'guest_requests.view'),
  ('receptionist', 'transfers.use'),
  ('receptionist', 'guest_requests.view')
)
on conflict (role_id, permission_id) do nothing;

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
-- insert into memberships (profile_id, organization_id, role_id, status)
-- select '00000000-0000-0000-0000-0000000a0001', 'a0000000-0000-0000-0000-000000000001', id, 'active'
-- from roles where slug = 'organization_admin';
--
-- insert into memberships (profile_id, property_id, role_id, status)
-- select v.profile_id, v.property_id, r.id, v.status
-- from (values
--   ('00000000-0000-0000-0000-0000000a0002'::uuid, 'a1000000-0000-0000-0000-000000000001'::uuid, 'receptionist', 'active'),
--   ('00000000-0000-0000-0000-0000000a0002'::uuid, 'a1000000-0000-0000-0000-000000000002'::uuid, 'receptionist', 'active'),
--   ('00000000-0000-0000-0000-0000000a0003'::uuid, 'a1000000-0000-0000-0000-000000000001'::uuid, 'manager', 'active'),
--   ('00000000-0000-0000-0000-0000000a0004'::uuid, 'a1000000-0000-0000-0000-000000000003'::uuid, 'receptionist', 'active'),
--   ('00000000-0000-0000-0000-0000000a0005'::uuid, 'a1000000-0000-0000-0000-000000000001'::uuid, 'receptionist', 'suspended')
-- ) as v(profile_id, property_id, role_slug, status)
-- join roles r on r.slug = v.role_slug;
