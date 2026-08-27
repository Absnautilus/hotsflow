-- Fase 2 Step 4 — guest_requests staff identity backfill (profiles/memberships).
-- Covers: idempotency, no duplicate/overwritten profile, no duplicate
-- membership, no silent correction of an incoherent pre-existing
-- membership, the (structurally impossible) null/invalid auth_user_id
-- case, master with N organizations, suspended staff losing effective
-- access, rank fidelity to the approved mapping, and scope coherence.
begin;
create extension if not exists pgtap;
select plan(19);

-- --- fixtures: 2 hotels (2 organizations after Step 3's backfill) --------
insert into hotels (id, name, timezone, active) values
  ('00000019-0000-0000-0000-00000000ff01', 'Hotel Uno', 'Europe/Rome', true),
  ('00000019-0000-0000-0000-00000000ff02', 'Hotel Due', 'Europe/Rome', true);
select backfill_legacy_property_mapping();

-- --- fixtures: staff (admin, operatore active, operatore suspended, master) ---
insert into auth.users (id) values
  ('00000019-0000-0000-0000-000000000a01'), -- admin @ H1
  ('00000019-0000-0000-0000-000000000a02'), -- operatore @ H1, active
  ('00000019-0000-0000-0000-000000000a03'), -- operatore @ H1, inactive (suspended)
  ('00000019-0000-0000-0000-000000000a04'), -- master
  ('00000019-0000-0000-0000-000000000a05'); -- for the "pre-existing profile" case

insert into staff_profiles (id, hotel_id, auth_user_id, name, role, department, active, login_username) values
  ('00000019-0000-0000-0000-000000000101', '00000019-0000-0000-0000-00000000ff01', '00000019-0000-0000-0000-000000000a01', 'Admin Uno', 'admin', null, true, null),
  ('00000019-0000-0000-0000-000000000102', '00000019-0000-0000-0000-00000000ff01', '00000019-0000-0000-0000-000000000a02', 'Operatore Attivo', 'operatore', 'housekeeping', true, 'test019.operatore2'),
  ('00000019-0000-0000-0000-000000000103', '00000019-0000-0000-0000-00000000ff01', '00000019-0000-0000-0000-000000000a03', 'Operatore Sospeso', 'operatore', 'reception', false, 'test019.operatore3'),
  ('00000019-0000-0000-0000-000000000104', '00000019-0000-0000-0000-00000000ff01', '00000019-0000-0000-0000-000000000a04', 'Master Uno', 'master', null, true, null);

-- case 2: a profiles row already exists for a to-be-migrated staff member,
-- with a name that deliberately differs from staff_profiles.name
insert into profiles (id, full_name) values ('00000019-0000-0000-0000-000000000a05', 'Pre-Existing Name');
insert into staff_profiles (id, hotel_id, auth_user_id, name, role, department, active, login_username) values
  ('00000019-0000-0000-0000-000000000105', '00000019-0000-0000-0000-00000000ff01', '00000019-0000-0000-0000-000000000a05', 'Operatore Cinque', 'operatore', 'housekeeping', true, 'test019.operatore5');

select backfill_staff_identity();

-- 1-2. idempotency: run again, counts for our fixtures must not change
select results_eq(
  $$ select count(*)::int from profiles where id in (
       '00000019-0000-0000-0000-000000000a01','00000019-0000-0000-0000-000000000a02',
       '00000019-0000-0000-0000-000000000a03','00000019-0000-0000-0000-000000000a04',
       '00000019-0000-0000-0000-000000000a05') $$,
  $$ values (5) $$,
  'all 5 fixture staff have a profile after the first backfill'
);
select backfill_staff_identity();
select results_eq(
  $$ select count(*)::int from profiles where id in (
       '00000019-0000-0000-0000-000000000a01','00000019-0000-0000-0000-000000000a02',
       '00000019-0000-0000-0000-000000000a03','00000019-0000-0000-0000-000000000a04',
       '00000019-0000-0000-0000-000000000a05') $$,
  $$ values (5) $$,
  'calling backfill_staff_identity() twice does not create extra profiles'
);
select results_eq(
  $$ select count(*)::int from memberships where profile_id in (
       '00000019-0000-0000-0000-000000000a01','00000019-0000-0000-0000-000000000a02',
       '00000019-0000-0000-0000-000000000a03') $$,
  $$ values (3) $$,
  'calling backfill_staff_identity() twice does not duplicate the 3 property-scoped memberships'
);

-- 2. pre-existing profile is not overwritten
select is(
  (select full_name from profiles where id = '00000019-0000-0000-0000-000000000a05'),
  'Pre-Existing Name',
  'a profile that already existed before the backfill keeps its original full_name'
);

-- 3. correct property, correct role for admin/operatore
select is(
  (select p.name from memberships mb
   join properties p on p.id = mb.property_id
   join roles r on r.id = mb.role_id
   where mb.profile_id = '00000019-0000-0000-0000-000000000a01' and r.slug = 'property_admin'),
  'Hotel Uno',
  'admin''s membership targets the property mapped to their own hotel (Hotel Uno), via property_admin'
);
select is(
  (select r.slug from memberships mb join roles r on r.id = mb.role_id
   where mb.profile_id = '00000019-0000-0000-0000-000000000a02'),
  'receptionist',
  'operatore (housekeeping department) still maps to receptionist, regardless of department'
);

-- 6. master gets exactly one membership per organization (2 hotels -> 2 orgs)
select is(
  (select count(*)::int from memberships where profile_id = '00000019-0000-0000-0000-000000000a04'),
  2,
  'master has exactly 2 memberships, one per existing organization'
);
select is(
  (select count(distinct organization_id)::int from memberships
   where profile_id = '00000019-0000-0000-0000-000000000a04'),
  2,
  'master''s 2 memberships target 2 distinct organizations'
);
select is(
  (select count(*)::int from memberships
   where profile_id = '00000019-0000-0000-0000-000000000a04' and property_id is not null),
  0,
  'none of master''s memberships are property-scoped'
);

-- 8. rank fidelity to the approved mapping
select is(
  (select r.rank::int from memberships mb join roles r on r.id = mb.role_id
   where mb.profile_id = '00000019-0000-0000-0000-000000000a01'),
  30,
  'admin -> property_admin carries rank 30, not higher'
);
select is(
  (select r.rank::int from memberships mb join roles r on r.id = mb.role_id
   where mb.profile_id = '00000019-0000-0000-0000-000000000a02'),
  10,
  'operatore -> receptionist carries rank 10, not higher'
);
select is(
  (select distinct r.rank::int from memberships mb join roles r on r.id = mb.role_id
   where mb.profile_id = '00000019-0000-0000-0000-000000000a04'),
  40,
  'master -> organization_admin carries rank 40 for every organization membership, not higher'
);

-- 9. scope coherence: property-scoped rows have organization_id null and
-- vice versa, for every membership this backfill created (also re-proves
-- the 0008 trigger never had to reject anything here)
select is(
  (select count(*)::int from memberships
   where profile_id in ('00000019-0000-0000-0000-000000000a01','00000019-0000-0000-0000-000000000a02','00000019-0000-0000-0000-000000000a03')
     and organization_id is not null),
  0,
  'property-scoped memberships (admin/operatore) never carry an organization_id'
);

-- 7. suspended staff: membership status is 'suspended' and the core helper
-- reports no effective access, even though the role itself is unchanged
select is(
  (select status from memberships where profile_id = '00000019-0000-0000-0000-000000000a03'),
  'suspended',
  'staff_profiles.active = false maps to membership.status = suspended'
);
select is(
  (select p.name from memberships mb join properties p on p.id = mb.property_id
   where mb.profile_id = '00000019-0000-0000-0000-000000000a03'),
  'Hotel Uno',
  'the suspended membership still targets the correct property (status alone marks it inactive)'
);
select m.platform_property_id as h1_property_id
  from legacy_property_mapping m where m.legacy_hotel_id = '00000019-0000-0000-0000-00000000ff01' \gset
set local role authenticated;
set local request.jwt.claim.sub = '00000019-0000-0000-0000-000000000a03';
select is(
  has_property_access(:'h1_property_id'),
  false,
  'a suspended membership grants no effective access via has_property_access()'
);
reset role;

-- 4. an incoherent pre-existing membership is never silently corrected.
-- No enclosing savepoint here: these are the last assertions in the file
-- (the whole transaction rolls back at the end regardless), and wrapping a
-- pgTAP assertion in a savepoint that's later rolled back also rolls back
-- pgTAP's own internal test counter, desyncing it from the "ok N" lines
-- already printed — throws_ok() already manages its own savepoint around
-- the statement it tests, which is all that's needed here.
insert into auth.users (id) values ('00000019-0000-0000-0000-000000000a06');
insert into staff_profiles (id, hotel_id, auth_user_id, name, role, department, active, login_username) values
  ('00000019-0000-0000-0000-000000000106', '00000019-0000-0000-0000-00000000ff01', '00000019-0000-0000-0000-000000000a06', 'Operatore Sei', 'operatore', 'housekeeping', true, 'test019.operatore6');
insert into profiles (id, full_name) values ('00000019-0000-0000-0000-000000000a06', 'Operatore Sei');
-- wrong role on purpose: property_admin instead of the receptionist this operatore should get
insert into memberships (profile_id, property_id, role_id, status)
select '00000019-0000-0000-0000-000000000a06', m.platform_property_id, r.id, 'active'
from legacy_property_mapping m, roles r
where m.legacy_hotel_id = '00000019-0000-0000-0000-00000000ff01' and r.slug = 'property_admin';

select throws_ok(
  $$ select backfill_staff_identity() $$,
  'P0001',
  null,
  'an incoherent pre-existing membership (wrong role) makes the whole backfill fail loud, not silently correct it'
);

-- 5. auth_user_id null/invalid is structurally impossible: the column
-- itself is `not null unique references auth.users(id)` (0001_init.sql) —
-- prove the database rejects both, rather than testing application code
-- for a case it can never actually receive.
select throws_ok(
  $$ insert into staff_profiles (hotel_id, auth_user_id, name, role) values
       ('00000019-0000-0000-0000-00000000ff01', null, 'No Auth User', 'admin') $$,
  '23502',
  null,
  'staff_profiles.auth_user_id cannot be null — enforced by the column itself, nothing to branch on here'
);

select throws_ok(
  $$ insert into staff_profiles (hotel_id, auth_user_id, name, role) values
       ('00000019-0000-0000-0000-00000000ff01', '00000019-0000-0000-0000-00000000dead', 'Ghost User', 'admin') $$,
  '23503',
  null,
  'staff_profiles.auth_user_id cannot reference a non-existent auth user — enforced by the FK itself'
);

select * from finish();
rollback;
