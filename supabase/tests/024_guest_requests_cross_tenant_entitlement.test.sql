-- Fase 2 Step 7 — MODULE ENTITLEMENT.
-- Entitlement disabled even with a valid administrative role
-- (property_admin AND organization_admin), PMS denied too (has_permission
-- folds entitlement in automatically), re-enabling restores access without
-- touching membership/role, and entitlement is per-property (a second,
-- still-entitled property for the same organization_admin stays reachable).
begin;
create extension if not exists pgtap;
select plan(9);

insert into hotels (id, name, timezone, active) values
  ('00000024-0000-0000-0000-00000000ff01', 'Hotel Uno', 'Europe/Rome', true),
  ('00000024-0000-0000-0000-00000000ff02', 'Hotel Due', 'Europe/Rome', true);
select backfill_legacy_property_mapping();
select backfill_guest_requests_entitlement();

insert into auth.users (id) values
  ('00000024-0000-0000-0000-000000000a01'), -- property_admin @ H1
  ('00000024-0000-0000-0000-000000000a02'); -- master, home hotel H1 (organization_admin on both orgs)

insert into staff_profiles (id, hotel_id, auth_user_id, name, role, department, active, login_username) values
  ('00000024-0000-0000-0000-000000000101', '00000024-0000-0000-0000-00000000ff01', '00000024-0000-0000-0000-000000000a01', 'PA Uno', 'admin', null, true, null),
  ('00000024-0000-0000-0000-000000000102', '00000024-0000-0000-0000-00000000ff01', '00000024-0000-0000-0000-000000000a02', 'Master Uno', 'master', null, true, null);
select backfill_staff_identity();

-- disable guest_requests entitlement at H1 specifically
update property_modules set enabled = false
where property_id = (select platform_property_id from legacy_property_mapping where legacy_hotel_id = '00000024-0000-0000-0000-00000000ff01')
  and module_id = (select id from modules where slug = 'guest_requests');

-- property_admin: valid role, active membership, entitlement off -> denied
set local role authenticated;
set local request.jwt.claim.sub = '00000024-0000-0000-0000-000000000a01';
select is(current_staff_hotel(), null, 'property_admin @ H1: entitlement disabled -> current_staff_hotel() is null despite a valid, active membership');
select throws_ok(
  $$ select save_pms_integration('00000024-0000-0000-0000-00000000ff01', 'manual', null, null, null, null, null, null) $$,
  'P0001',
  'not authorized',
  'property_admin @ H1: PMS also denied while entitlement is off — has_permission() folds module entitlement in automatically'
);
reset role;

-- organization_admin (their own home hotel, otherwise the exact case that
-- works in Step 6's test): entitlement off overrides even that
set local role authenticated;
set local request.jwt.claim.sub = '00000024-0000-0000-0000-000000000a02';
select is(current_staff_hotel(), null, 'organization_admin @ home hotel H1: entitlement disabled -> current_staff_hotel() is null too');
-- staff_profiles roster visibility (has_organization_access-based, not
-- gated by module entitlement per the approved matrix) is UNAFFECTED —
-- confirms entitlement only gates the module's own operational data
select is(
  (select count(*)::int from staff_profiles where hotel_id = '00000024-0000-0000-0000-00000000ff01'),
  2,
  'organization_admin still sees the H1 roster (2 rows) — staff visibility was never gated by module entitlement'
);
reset role;

-- re-enable: access restored without touching membership/role at all
update property_modules set enabled = true
where property_id = (select platform_property_id from legacy_property_mapping where legacy_hotel_id = '00000024-0000-0000-0000-00000000ff01')
  and module_id = (select id from modules where slug = 'guest_requests');

set local role authenticated;
set local request.jwt.claim.sub = '00000024-0000-0000-0000-000000000a01';
select is(current_staff_hotel(), '00000024-0000-0000-0000-00000000ff01'::uuid,
  're-enabling entitlement alone restores current_staff_hotel() for property_admin, no membership/role change involved'
);
reset role;

-- entitlement is per-property: disable it again at H1 only, and confirm
-- organization_admin's OTHER (still-entitled) hotel stays fully reachable
update property_modules set enabled = false
where property_id = (select platform_property_id from legacy_property_mapping where legacy_hotel_id = '00000024-0000-0000-0000-00000000ff01')
  and module_id = (select id from modules where slug = 'guest_requests');

set local role authenticated;
set local request.jwt.claim.sub = '00000024-0000-0000-0000-000000000a02';
select is(current_staff_hotel(), null, 'organization_admin: H1 stays denied (entitlement off there)');
select lives_ok(
  $$ select save_pms_integration('00000024-0000-0000-0000-00000000ff02', 'manual', null, null, null, null, null, null) $$,
  'the same organization_admin CAN still manage PMS at H2, which is unaffected and still entitled'
);
reset role;

select is(
  (select enabled from property_modules pm
   join legacy_property_mapping m on m.platform_property_id = pm.property_id
   join modules mod on mod.id = pm.module_id and mod.slug = 'guest_requests'
   where m.legacy_hotel_id = '00000024-0000-0000-0000-00000000ff02'),
  true,
  'sanity: H2''s own entitlement was never touched by any of the H1 toggling above'
);
-- Scoped to this file's own two hotels via legacy_property_mapping, not a
-- raw count over all of property_modules: seed.sql's own demo properties
-- (A1, A2, B1) already carry 3 guest_requests rows of their own (A1 and B1
-- enabled, A2 explicitly disabled -- disabled still means a row exists),
-- so an unscoped count is never 2 against real seed data, only against an
-- empty database. The property-scoping property this test actually cares
-- about doesn't need a global count -- it only needs each of THIS test's
-- two properties to carry its own independent row, which the join below
-- proves directly.
select is(
  (select count(distinct pm.property_id)::int
   from property_modules pm
   join modules mod on mod.id = pm.module_id and mod.slug = 'guest_requests'
   join legacy_property_mapping m on m.platform_property_id = pm.property_id
   where m.legacy_hotel_id in ('00000024-0000-0000-0000-00000000ff01', '00000024-0000-0000-0000-00000000ff02')),
  2,
  'sanity: entitlement rows exist independently per property (2 total for this test''s own properties), not a single org-wide flag'
);

select * from finish();
rollback;
