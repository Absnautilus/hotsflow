-- Fase 2 Step 7 — DEPARTMENT ISOLATION.
-- Own department visible, a different department not, reception sees the
-- shared front-desk queue, property_admin/organization_admin bypass the
-- filter entirely (positive check, not just absence of denial), and the
-- documented "department NULL" case: structurally impossible for a
-- receptionist (staff_profiles_department_matches_role forbids it), and a
-- no-op for admin/master since they bypass the filter regardless of what
-- current_staff_department() returns for them.
begin;
create extension if not exists pgtap;
select plan(9);

insert into hotels (id, name, timezone, active) values
  ('00000026-0000-0000-0000-00000000ff01', 'Hotel Uno', 'Europe/Rome', true);
select backfill_legacy_property_mapping();
select backfill_guest_requests_entitlement();

insert into request_categories (id, hotel_id, name, department) values
  ('00000026-0000-0000-0000-000000000c01', '00000026-0000-0000-0000-00000000ff01', 'Housekeeping', 'housekeeping'),
  ('00000026-0000-0000-0000-000000000c02', '00000026-0000-0000-0000-00000000ff01', 'Maintenance', 'maintenance');
insert into request_types (id, category_id, name) values
  ('00000026-0000-0000-0000-0000000fee01', '00000026-0000-0000-0000-000000000c01', 'Asciugamani'),
  ('00000026-0000-0000-0000-0000000fee02', '00000026-0000-0000-0000-000000000c02', 'Riparazione');

insert into guest_requests (id, hotel_id, room_number, request_type_id, quantity, assigned_department, status) values
  ('00000026-0000-0000-0000-00000000ba01', '00000026-0000-0000-0000-00000000ff01', '101', '00000026-0000-0000-0000-0000000fee01', 1, 'housekeeping', 'requested'),
  ('00000026-0000-0000-0000-00000000ba02', '00000026-0000-0000-0000-00000000ff01', '102', '00000026-0000-0000-0000-0000000fee02', 1, 'maintenance', 'requested');

insert into auth.users (id) values
  ('00000026-0000-0000-0000-000000000a01'), -- receptionist, department=housekeeping
  ('00000026-0000-0000-0000-000000000a02'), -- receptionist, department=reception
  ('00000026-0000-0000-0000-000000000a03'); -- property_admin

insert into staff_profiles (id, hotel_id, auth_user_id, name, role, department, active, login_username) values
  ('00000026-0000-0000-0000-000000000101', '00000026-0000-0000-0000-00000000ff01', '00000026-0000-0000-0000-000000000a01', 'Rec Housekeeping', 'operatore', 'housekeeping', true, 'test026.rec1'),
  ('00000026-0000-0000-0000-000000000102', '00000026-0000-0000-0000-00000000ff01', '00000026-0000-0000-0000-000000000a02', 'Rec Reception', 'operatore', 'reception', true, 'test026.rec2'),
  ('00000026-0000-0000-0000-000000000103', '00000026-0000-0000-0000-00000000ff01', '00000026-0000-0000-0000-000000000a03', 'PA Uno', 'admin', null, true, null);
select backfill_staff_identity();

-- own department visible, a different department not
set local role authenticated;
set local request.jwt.claim.sub = '00000026-0000-0000-0000-000000000a01';
select is(
  (select count(*)::int from guest_requests where assigned_department = 'housekeeping'),
  1,
  'receptionist (department=housekeeping) sees the housekeeping request'
);
select is(
  (select count(*)::int from guest_requests where assigned_department = 'maintenance'),
  0,
  'the same receptionist does NOT see the maintenance request'
);
reset role;

-- reception sees the shared front-desk queue (both requests, via
-- current_staff_manages_front_desk()'s reception branch)
set local role authenticated;
set local request.jwt.claim.sub = '00000026-0000-0000-0000-000000000a02';
select is(
  (select count(*)::int from guest_requests),
  2,
  'a reception-department receptionist manages the front desk and sees both requests, regardless of department'
);
reset role;

-- property_admin bypasses the department filter entirely — positive check
set local role authenticated;
set local request.jwt.claim.sub = '00000026-0000-0000-0000-000000000a03';
select is(
  (select count(*)::int from guest_requests where assigned_department = 'housekeeping'),
  1,
  'property_admin (bypasses department filter) sees the housekeeping request'
);
select is(
  (select count(*)::int from guest_requests where assigned_department = 'maintenance'),
  1,
  'the same property_admin also sees the maintenance request — full bypass, not just "not denied"'
);
reset role;

-- department NULL: found while writing this test that
-- staff_profiles_department_matches_role does NOT actually forbid this —
-- `role = 'operatore' AND department IN (...)` evaluates to NULL (not
-- FALSE) when department IS NULL, and a CHECK constraint treats a NULL
-- result as satisfied (only an explicit FALSE is a violation). Confirmed
-- empirically below: the insert succeeds. This is a genuine, pre-existing
-- gap in the legacy constraint, not introduced by this migration — noted
-- here rather than silently assumed away, but NOT fixed (out of scope:
-- fixing a legacy CHECK constraint is a schema change to a table this
-- phase does not touch, and the row-level access behavior below shows the
-- actual authorization outcome is still correctly fail-closed regardless).
insert into auth.users (id) values ('00000026-0000-0000-0000-000000000a99');
select lives_ok(
  $$ insert into staff_profiles (hotel_id, auth_user_id, name, role, department, login_username)
     values ('00000026-0000-0000-0000-00000000ff01', '00000026-0000-0000-0000-000000000a99', 'Dept Nullo', 'operatore', null, 'test026.deptnull') $$,
  'staff_profiles_department_matches_role does NOT actually reject operatore+NULL department (three-valued CHECK logic) -- reachable, not impossible'
);
select backfill_staff_identity();
set local role authenticated;
set local request.jwt.claim.sub = '00000026-0000-0000-0000-000000000a99';
select is(
  (select count(*)::int from guest_requests),
  0,
  'a receptionist with department IS NULL sees 0 guest_requests rows -- fails closed via the same NULL-in-predicate semantics, not by the constraint'
);
reset role;

-- for admin/master, department IS null by constraint, but it's never
-- consulted — they bypass the filter via current_staff_manages_front_desk()
-- regardless of what current_staff_department() returns
set local role authenticated;
set local request.jwt.claim.sub = '00000026-0000-0000-0000-000000000a03';
select is(current_staff_department(), null, 'property_admin''s current_staff_department() is (legitimately) null');
select ok(
  current_staff_manages_front_desk(),
  'and current_staff_manages_front_desk() is still true for them regardless — the null department is never relied upon'
);
reset role;

select * from finish();
rollback;
