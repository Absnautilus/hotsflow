-- Fase 2 Step 6 — guest_requests RLS wrapper / authoritative role source.
-- Covers: cross-property access, organization boundary (deliberately NOT
-- widened for the 6 operational tables, but IS org-wide for staff
-- management and PMS per the approved matrix), suspended membership, no
-- membership, entitlement disabled, department isolation (unchanged
-- composition, sanity check), PMS permission, staff management permission,
-- and that staff_profiles.role has no effect on any of it.
begin;
create extension if not exists pgtap;
select plan(24);

-- --- fixtures --------------------------------------------------------------
insert into hotels (id, name, timezone, active) values
  ('00000021-0000-0000-0000-00000000ff01', 'Hotel Uno', 'Europe/Rome', true),
  ('00000021-0000-0000-0000-00000000ff02', 'Hotel Due', 'Europe/Rome', true),
  ('00000021-0000-0000-0000-00000000ff03', 'Hotel Tre', 'Europe/Rome', true);
select backfill_legacy_property_mapping();
select backfill_guest_requests_entitlement();

insert into rooms (id, hotel_id, room_number) values
  ('00000021-0000-0000-0000-0000000fa001', '00000021-0000-0000-0000-00000000ff01', '101'),
  ('00000021-0000-0000-0000-0000000fa002', '00000021-0000-0000-0000-00000000ff02', '201');

insert into request_categories (id, hotel_id, name, department) values
  ('00000021-0000-0000-0000-000000000c01', '00000021-0000-0000-0000-00000000ff01', 'Housekeeping', 'housekeeping'),
  ('00000021-0000-0000-0000-000000000c02', '00000021-0000-0000-0000-00000000ff02', 'Housekeeping', 'housekeeping');

insert into auth.users (id) values
  ('00000021-0000-0000-0000-000000000a01'), -- property_admin @ H1
  ('00000021-0000-0000-0000-000000000a02'), -- receptionist @ H1, department housekeeping
  ('00000021-0000-0000-0000-000000000a03'), -- suspended operatore @ H1
  ('00000021-0000-0000-0000-000000000a04'), -- master, home hotel H1
  ('00000021-0000-0000-0000-000000000a05'); -- property_admin @ H2 (for cross-property checks)

insert into staff_profiles (id, hotel_id, auth_user_id, name, role, department, active, login_username) values
  ('00000021-0000-0000-0000-000000000101', '00000021-0000-0000-0000-00000000ff01', '00000021-0000-0000-0000-000000000a01', 'PA Uno', 'admin', null, true, null),
  ('00000021-0000-0000-0000-000000000102', '00000021-0000-0000-0000-00000000ff01', '00000021-0000-0000-0000-000000000a02', 'Rec Uno', 'operatore', 'housekeeping', true, 'test021.rec2'),
  ('00000021-0000-0000-0000-000000000103', '00000021-0000-0000-0000-00000000ff01', '00000021-0000-0000-0000-000000000a03', 'Sospeso Uno', 'operatore', 'housekeeping', false, 'test021.sosp3'),
  ('00000021-0000-0000-0000-000000000104', '00000021-0000-0000-0000-00000000ff01', '00000021-0000-0000-0000-000000000a04', 'Master Uno', 'master', null, true, null),
  ('00000021-0000-0000-0000-000000000105', '00000021-0000-0000-0000-00000000ff02', '00000021-0000-0000-0000-000000000a05', 'PA Due', 'admin', null, true, null);

select backfill_staff_identity();

-- 1. cross-property: property_admin @ H1 cannot resolve H2 as their hotel
set local role authenticated;
set local request.jwt.claim.sub = '00000021-0000-0000-0000-000000000a01';
select is(current_staff_hotel(), '00000021-0000-0000-0000-00000000ff01'::uuid,
  'property_admin resolves their own hotel via current_staff_hotel()');
select is(
  (select count(*)::int from rooms where hotel_id = '00000021-0000-0000-0000-00000000ff02'),
  0,
  'property_admin @ H1 sees 0 rooms of H2 (rooms_select_same_hotel gated by current_staff_hotel())'
);
select is(
  (select count(*)::int from rooms where hotel_id = '00000021-0000-0000-0000-00000000ff01'),
  1,
  'property_admin @ H1 sees their own hotel''s room'
);
reset role;

-- 3-4. master (organization_admin): own home hotel (H1) works, a DIFFERENT
-- hotel (H2) does NOT, even though master holds an organization_admin
-- membership covering H2's organization too (D2: one membership per every
-- existing org) — current_staff_hotel() never widens beyond
-- staff_profiles.hotel_id, by design.
set local role authenticated;
set local request.jwt.claim.sub = '00000021-0000-0000-0000-000000000a04';
select is(current_staff_hotel(), '00000021-0000-0000-0000-00000000ff01'::uuid,
  'master resolves their own (home) hotel via current_staff_hotel(), not org-wide');
select is(
  (select count(*)::int from rooms where hotel_id = '00000021-0000-0000-0000-00000000ff01'),
  1,
  'master sees rooms at their own home hotel'
);
select is(
  (select count(*)::int from rooms where hotel_id = '00000021-0000-0000-0000-00000000ff02'),
  0,
  'master does NOT see rooms at a different hotel, despite holding organization_admin on its org too'
);
reset role;

-- staff management (row 1, core.staff.manage) and roster visibility (7a)
-- ARE organization-wide for organization_admin, unlike the 6 operational
-- tables above — different, already-approved capability gate.
set local role authenticated;
set local request.jwt.claim.sub = '00000021-0000-0000-0000-000000000a04';
select is(
  (select count(*)::int from staff_profiles where hotel_id = '00000021-0000-0000-0000-00000000ff02'),
  1,
  'master (organization_admin) sees the H2 roster too — staff visibility is org-wide, not scoped to current_staff_hotel()'
);
select lives_ok(
  $$ update staff_profiles set name = 'PA Due (rinominato)' where id = '00000021-0000-0000-0000-000000000105' $$,
  'master can manage staff at H2 as well — core.staff.manage is organization-wide, unlike operational-table access'
);
reset role;

-- 5. suspended membership -> current_staff_hotel() resolves nothing
set local role authenticated;
set local request.jwt.claim.sub = '00000021-0000-0000-0000-000000000a03';
select is(current_staff_hotel(), null,
  'a suspended staff member (staff_profiles.active=false) resolves no hotel at all'
);
select is(
  (select count(*)::int from rooms where hotel_id = '00000021-0000-0000-0000-00000000ff01'),
  0,
  'a suspended staff member sees no rooms, even at their own nominal hotel'
);
reset role;

-- entitlement disabled -> current_staff_hotel() resolves nothing for staff
-- at that property, even though their membership is perfectly active
update property_modules set enabled = false
where property_id = (select platform_property_id from legacy_property_mapping where legacy_hotel_id = '00000021-0000-0000-0000-00000000ff02')
  and module_id = (select id from modules where slug = 'guest_requests');
set local role authenticated;
set local request.jwt.claim.sub = '00000021-0000-0000-0000-000000000a05';
select is(current_staff_hotel(), null,
  'guest_requests disabled for H2 -> property_admin @ H2 resolves no hotel, despite an active membership'
);
reset role;
update property_modules set enabled = true
where property_id = (select platform_property_id from legacy_property_mapping where legacy_hotel_id = '00000021-0000-0000-0000-00000000ff02')
  and module_id = (select id from modules where slug = 'guest_requests');

-- no membership at all (mapping + entitlement fine, but the core membership
-- itself is absent) -> current_staff_hotel() resolves nothing
delete from memberships where profile_id = '00000021-0000-0000-0000-000000000a05';
set local role authenticated;
set local request.jwt.claim.sub = '00000021-0000-0000-0000-000000000a05';
select is(current_staff_hotel(), null,
  'no core membership at all -> current_staff_hotel() resolves nothing, even with a mapped, entitled property'
);
reset role;
-- restore for the PMS test below
select backfill_staff_identity();

-- PMS: property_admin can manage their own hotel's PMS, not another's;
-- master CAN manage PMS at a hotel that isn't their home hotel (org-wide,
-- per the approved matrix, unlike the 6 operational tables)
set local role authenticated;
set local request.jwt.claim.sub = '00000021-0000-0000-0000-000000000a01';
select lives_ok(
  $$ select save_pms_integration('00000021-0000-0000-0000-00000000ff01', 'manual', null, null, null, null, null, null) $$,
  'property_admin can save PMS settings for their own hotel'
);
select throws_ok(
  $$ select save_pms_integration('00000021-0000-0000-0000-00000000ff02', 'manual', null, null, null, null, null, null) $$,
  'P0001',
  'not authorized',
  'property_admin cannot save PMS settings for a different hotel'
);
reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000021-0000-0000-0000-000000000a04';
select lives_ok(
  $$ select save_pms_integration('00000021-0000-0000-0000-00000000ff02', 'manual', null, null, null, null, null, null) $$,
  'master (organization_admin) CAN save PMS settings for a hotel that is not their own home hotel — guest_requests.pms.manage is org-wide'
);
reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000021-0000-0000-0000-000000000a02';
select throws_ok(
  $$ select get_pms_integration_status('00000021-0000-0000-0000-00000000ff01') $$,
  'P0001',
  'not authorized',
  'receptionist has no guest_requests.pms.manage — denied regardless of being active staff at that hotel'
);
reset role;

-- staff management permission: receptionist cannot manage staff even at
-- their own hotel (core.staff.manage, not held by receptionist) — the
-- column grant is table-wide for `authenticated`, so this is an RLS
-- no-match (silent 0-row update), not a grant-level error.
set local role authenticated;
set local request.jwt.claim.sub = '00000021-0000-0000-0000-000000000a02';
update staff_profiles set name = 'should not change' where id = '00000021-0000-0000-0000-000000000101';
select is(
  (select name from staff_profiles where id = '00000021-0000-0000-0000-000000000101'),
  'PA Uno',
  'receptionist''s UPDATE on another staff row matches nothing under RLS (guest_requests_staff_manage_allowed denies it) — the row is unchanged'
);
reset role;

-- department isolation composition sanity check (unchanged functions,
-- verifying the composition still holds through the redefined base wrappers)
set local role authenticated;
set local request.jwt.claim.sub = '00000021-0000-0000-0000-000000000a02';
select is(current_staff_department(), 'housekeeping'::department,
  'current_staff_department() is untouched and still reads staff_profiles.department directly'
);
reset role;

-- staff_profiles.role has no effect on authorization: flip it, confirm
-- current_staff_role()/current_staff_is_master() and real access are all
-- unchanged for both an admin and (more importantly) a master
-- 'admin' (not 'operatore') so as not to also trip the unrelated
-- staff_profiles_login_username_matches_role constraint — the point here
-- is purely that .role has no authorization effect, not to re-test the
-- department/login_username constraints already covered elsewhere.
update staff_profiles set role = 'admin' where id = '00000021-0000-0000-0000-000000000104'; -- master's row, artificially demoted
set local role authenticated;
set local request.jwt.claim.sub = '00000021-0000-0000-0000-000000000a04';
select is(current_staff_role(), 'master'::staff_role,
  'current_staff_role() still returns master after staff_profiles.role was artificially set to admin'
);
select ok(current_staff_is_master(), 'current_staff_is_master() is still true after the same artificial change');
select is(
  (select count(*)::int from rooms where hotel_id = '00000021-0000-0000-0000-00000000ff01'),
  1,
  'real row-level access (rooms at the home hotel) is unaffected by the artificial staff_profiles.role change'
);
reset role;
update staff_profiles set role = 'master' where id = '00000021-0000-0000-0000-000000000104'; -- restore

-- staff_profiles.role is no longer client-writable at all
set local role authenticated;
set local request.jwt.claim.sub = '00000021-0000-0000-0000-000000000a01';
select throws_ok(
  $$ update staff_profiles set role = 'master' where id = '00000021-0000-0000-0000-000000000101' $$,
  '42501',
  null,
  'staff_profiles.role cannot be written by authenticated at all, even by someone with core.staff.manage'
);
reset role;

-- static check: no authoritative function/policy still reads
-- staff_profiles.role, except Step 4's one-time backfill (not an ongoing
-- authorization check)
select is(
  (select count(*)::int from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.prosrc ~ 'staff_profiles\.role\M|\brole\s+from\s+staff_profiles\M'
     and p.proname <> 'backfill_staff_identity'),
  0,
  'no function other than the one-time backfill_staff_identity() reads staff_profiles.role'
);
select is(
  (select count(*)::int from pg_policies
   where schemaname = 'public'
     and (coalesce(qual,'') ~ 'staff_profiles\.role\M' or coalesce(with_check,'') ~ 'staff_profiles\.role\M')),
  0,
  'no RLS policy references staff_profiles.role'
);

select * from finish();
rollback;
