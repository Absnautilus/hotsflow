-- Fase 2 Step 9 pre-cutover gate — permanent regression coverage for the
-- staff_profiles.active gap found while fixing create-staff-account/
-- sync-pms-stays: guest_requests_staff_roster_visible(),
-- guest_requests_staff_manage_allowed(), get_pms_integration_status(),
-- save_pms_integration() all previously allowed a caller whose
-- memberships.status is still 'active' but whose staff_profiles.active is
-- false (the state left behind by the admin UI's deactivate toggle, which
-- never touches memberships) -- reproduced here exactly that way, not via
-- backfill_staff_identity() (which would set both consistently and never
-- exercise the drifted state real deactivation leaves behind).
begin;
create extension if not exists pgtap;
select plan(9);

-- --- fixtures ------------------------------------------------------------
insert into hotels (id, name, timezone, active) values
  ('00000030-0000-0000-0000-00000000ff01', 'Hotel Uno', 'Europe/Rome', true),
  ('00000030-0000-0000-0000-00000000ff02', 'Hotel Due', 'Europe/Rome', true);
select backfill_legacy_property_mapping();
select backfill_guest_requests_entitlement();

insert into auth.users (id) values
  ('00000030-0000-0000-0000-000000000a01'), -- property_admin, will be deactivated post-backfill
  ('00000030-0000-0000-0000-000000000a02'), -- property_admin, stays active (control)
  ('00000030-0000-0000-0000-000000000a03'); -- organization_admin, stays active (org-wide sanity)

insert into staff_profiles (id, hotel_id, auth_user_id, name, role, department, active, login_username) values
  ('00000030-0000-0000-0000-000000000101', '00000030-0000-0000-0000-00000000ff01', '00000030-0000-0000-0000-000000000a01', 'PA Uno (soon deactivated)', 'admin', null, true, null),
  ('00000030-0000-0000-0000-000000000102', '00000030-0000-0000-0000-00000000ff01', '00000030-0000-0000-0000-000000000a02', 'PA Uno (control)', 'admin', null, true, null),
  ('00000030-0000-0000-0000-000000000103', '00000030-0000-0000-0000-00000000ff01', '00000030-0000-0000-0000-000000000a03', 'Master Uno', 'master', null, true, null);
select backfill_staff_identity();

-- Real-world drift: deactivate via the SAME mechanism the admin UI uses
-- (a plain UPDATE on staff_profiles.active), never touching memberships --
-- this is the exact state left behind after using the dashboard's toggle,
-- confirmed by reading apps/web/src/lib/admin-api.ts (deactivateStaff()).
update staff_profiles set active = false where id = '00000030-0000-0000-0000-000000000101';

-- sanity: the membership itself is still active -- proves any failure
-- below is caused by the new staff_profiles.active check, not by an
-- already-suspended membership (which would be a different, already-
-- covered scenario, see 025_guest_requests_cross_tenant_compatibility_gate).
select is(
  (select m.status::text from memberships m
   join staff_profiles sp on sp.auth_user_id = m.profile_id
   where sp.id = '00000030-0000-0000-0000-000000000101'),
  'active',
  'sanity: the deactivated caller''s membership.status is still active (drift, not a suspended membership)'
);

-- =========================================================================
-- the drifted caller: DENIED everywhere the fix now applies
-- =========================================================================
set local role authenticated;
set local request.jwt.claim.sub = '00000030-0000-0000-0000-000000000a01';

select is(
  guest_requests_staff_roster_visible('00000030-0000-0000-0000-00000000ff01'),
  false,
  'staff_profiles.active=false + membership.status=active -> roster visibility DENIED'
);
select is(
  guest_requests_staff_manage_allowed('00000030-0000-0000-0000-00000000ff01'),
  false,
  'staff_profiles.active=false + membership.status=active -> staff management DENIED'
);
select throws_ok(
  $$ select * from get_pms_integration_status('00000030-0000-0000-0000-00000000ff01') $$,
  'P0001', 'not authorized',
  'staff_profiles.active=false + membership.status=active -> PMS status read DENIED'
);
select throws_ok(
  $$ select save_pms_integration('00000030-0000-0000-0000-00000000ff01', 'manual', null, null, null, null, null, null) $$,
  'P0001', 'not authorized',
  'staff_profiles.active=false + membership.status=active -> PMS save DENIED'
);
reset role;

-- =========================================================================
-- control: a genuinely active property_admin on the same hotel is
-- unaffected -- the fix denies the drifted caller specifically, not
-- everyone
-- =========================================================================
set local role authenticated;
set local request.jwt.claim.sub = '00000030-0000-0000-0000-000000000a02';
select is(
  guest_requests_staff_roster_visible('00000030-0000-0000-0000-00000000ff01'),
  true,
  'control: a genuinely active property_admin still sees the roster'
);
select is(
  guest_requests_staff_manage_allowed('00000030-0000-0000-0000-00000000ff01'),
  true,
  'control: a genuinely active property_admin can still manage staff'
);
select lives_ok(
  $$ select * from get_pms_integration_status('00000030-0000-0000-0000-00000000ff01') $$,
  'control: a genuinely active property_admin can still read PMS status (regression guard for 029)'
);
reset role;

-- =========================================================================
-- organization_admin sanity: org-wide reach to a non-home hotel in the
-- same org is preserved for a genuinely active caller -- the new
-- current_staff_active() check must not narrow scoping, only deny the
-- drifted case above
-- =========================================================================
set local role authenticated;
set local request.jwt.claim.sub = '00000030-0000-0000-0000-000000000a03';
select is(
  guest_requests_staff_manage_allowed('00000030-0000-0000-0000-00000000ff02'),
  true,
  'organization_admin: org-wide staff management to a non-home hotel in the same org still works'
);
reset role;

select * from finish();
rollback;
