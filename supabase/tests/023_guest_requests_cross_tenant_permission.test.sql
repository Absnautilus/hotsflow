-- Fase 2 Step 7 — PERMISSION BOUNDARIES.
-- staff_profiles.role manipulated toward master, anonymous caller on the
-- PMS RPCs, property_admin/organization_admin at their respective
-- boundaries (including a THIRD, wholly unrelated organization), staff
-- management permission, PMS permission, and role assignment working
-- correctly (and being correctly refused) on Step-4-derived memberships.
begin;
create extension if not exists pgtap;
select plan(12);

insert into hotels (id, name, timezone, active) values
  ('00000023-0000-0000-0000-00000000ff01', 'Hotel Uno', 'Europe/Rome', true),
  ('00000023-0000-0000-0000-00000000ff02', 'Hotel Due', 'Europe/Rome', true);
select backfill_legacy_property_mapping();
select backfill_guest_requests_entitlement();

insert into auth.users (id) values
  ('00000023-0000-0000-0000-000000000a01'), -- receptionist @ H1
  ('00000023-0000-0000-0000-000000000a02'), -- property_admin @ H1
  ('00000023-0000-0000-0000-000000000a03'); -- property_admin @ H2

insert into staff_profiles (id, hotel_id, auth_user_id, name, role, department, active, login_username) values
  ('00000023-0000-0000-0000-000000000101', '00000023-0000-0000-0000-00000000ff01', '00000023-0000-0000-0000-000000000a01', 'Rec Uno', 'operatore', 'housekeeping', true, 'test023.rec1'),
  ('00000023-0000-0000-0000-000000000102', '00000023-0000-0000-0000-00000000ff01', '00000023-0000-0000-0000-000000000a02', 'PA Uno', 'admin', null, true, null),
  ('00000023-0000-0000-0000-000000000103', '00000023-0000-0000-0000-00000000ff02', '00000023-0000-0000-0000-000000000a03', 'PA Due', 'admin', null, true, null);

select backfill_staff_identity();

-- ### staff_profiles.role manipulated toward master (from a receptionist) ###
-- department must go to NULL together with role, or staff_profiles_
-- department_matches_role rejects the row outright — an unrelated legacy
-- constraint, not part of what's being tested here.
update staff_profiles set role = 'master', department = null, login_username = null where id = '00000023-0000-0000-0000-000000000101';
set local role authenticated;
set local request.jwt.claim.sub = '00000023-0000-0000-0000-000000000a01';
select is(current_staff_role(), 'operatore'::staff_role,
  'a receptionist''s current_staff_role() stays operatore even after staff_profiles.role is manually set to master'
);
select ok(not current_staff_is_master(),
  'current_staff_is_master() stays false for the same caller — no elevation from the manipulated column'
);
select throws_ok(
  $$ select get_pms_integration_status(null) $$,
  'P0001',
  'not authorized',
  'the same caller, despite staff_profiles.role = master, still cannot reach PMS (no guest_requests.pms.manage membership)'
);
reset role;
update staff_profiles set role = 'operatore', department = 'housekeeping', login_username = 'test023.rec1' where id = '00000023-0000-0000-0000-000000000101'; -- restore

-- ### anonymous caller on the PMS RPCs ###
set local role anon;
select throws_ok(
  $$ select get_pms_integration_status('00000023-0000-0000-0000-00000000ff01') $$,
  '42501',
  null,
  'anon has no EXECUTE grant on get_pms_integration_status() at all'
);
select throws_ok(
  $$ select save_pms_integration('00000023-0000-0000-0000-00000000ff01', 'manual', null, null, null, null, null, null) $$,
  '42501',
  null,
  'anon has no EXECUTE grant on save_pms_integration() at all'
);
reset role;

-- ### property_admin boundary: own property works, another property (even
-- after being granted an org-wide role on a THIRD, unrelated org) doesn't ###
insert into organizations (id, name, slug) values ('00000023-0000-0000-0000-000000009999', 'Org Terza', 'org-023-terza');
insert into properties (id, organization_id, name, slug) values
  ('00000023-0000-0000-0000-000000009998', '00000023-0000-0000-0000-000000009999', 'Property Terza', 'p-023-terza');
insert into memberships (profile_id, property_id, role_id, status)
select '00000023-0000-0000-0000-000000000a02', '00000023-0000-0000-0000-000000009998', id, 'active'
from roles where slug = 'manager'; -- manager is property-scoped; no core.staff.manage/pms.manage even on this third org's own property

set local role authenticated;
set local request.jwt.claim.sub = '00000023-0000-0000-0000-000000000a02';
select lives_ok(
  $$ select save_pms_integration('00000023-0000-0000-0000-00000000ff01', 'manual', null, null, null, null, null, null) $$,
  'property_admin can manage PMS at their own property'
);
select throws_ok(
  $$ select save_pms_integration('00000023-0000-0000-0000-00000000ff02', 'manual', null, null, null, null, null, null) $$,
  'P0001',
  'not authorized',
  'property_admin cannot manage PMS at a different property, even holding an unrelated manager role elsewhere'
);
reset role;

-- ### organization_admin boundary on a wholly unrelated (third) org ###
delete from memberships where profile_id = '00000023-0000-0000-0000-000000000a02' and property_id = '00000023-0000-0000-0000-000000009998';
insert into memberships (profile_id, organization_id, role_id, status)
select '00000023-0000-0000-0000-000000000a02', '00000023-0000-0000-0000-000000009999', id, 'active'
from roles where slug = 'organization_admin'; -- now a genuine org_admin, but only on the THIRD org
set local role authenticated;
set local request.jwt.claim.sub = '00000023-0000-0000-0000-000000000a02';
select throws_ok(
  $$ select save_pms_integration('00000023-0000-0000-0000-00000000ff02', 'manual', null, null, null, null, null, null) $$,
  'P0001',
  'not authorized',
  'organization_admin on an unrelated third organization still cannot manage PMS at H2 (org2), which isn''t theirs'
);
select is(
  (select count(*)::int from staff_profiles where hotel_id = '00000023-0000-0000-0000-00000000ff02'),
  0,
  'the same third-org organization_admin sees 0 rows on H2''s (org2''s) staff roster too'
);
reset role;

-- ### role assignment on a Step-4-derived membership ###
-- property_admin (core.roles.assign, rank 30) promotes the receptionist
-- (rank 10) to manager (rank 20) — ordinary core mechanism, must work the
-- same on a migrated membership as on any other.
set local role authenticated;
set local request.jwt.claim.sub = '00000023-0000-0000-0000-000000000a02';
select lives_ok(
  $$ select assign_membership_role(
       (select id from memberships where profile_id = '00000023-0000-0000-0000-000000000a01'),
       (select id from roles where slug = 'manager')
     ) $$,
  'property_admin can promote the receptionist (Step-4-derived membership) to manager via assign_membership_role()'
);
reset role;

select is(
  (select r.slug from memberships m join roles r on r.id = m.role_id where m.profile_id = '00000023-0000-0000-0000-000000000a01'),
  'manager',
  'the promotion actually landed: the membership''s role is now manager'
);

-- the newly-promoted manager cannot then self-promote further, nor can a
-- manager assign a role >= their own rank (ordinary core rule, re-verified
-- here specifically on Step-4-derived data)
set local role authenticated;
set local request.jwt.claim.sub = '00000023-0000-0000-0000-000000000a01';
select throws_ok(
  $$ select assign_membership_role(
       (select id from memberships where profile_id = '00000023-0000-0000-0000-000000000a01'),
       (select id from roles where slug = 'property_admin')
     ) $$,
  null,
  null,
  'the promoted manager cannot self-promote to property_admin'
);
reset role;

select * from finish();
rollback;
