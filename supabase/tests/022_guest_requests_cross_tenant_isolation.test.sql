-- Fase 2 Step 7 — TENANT ISOLATION.
-- Cross-property SELECT/INSERT/UPDATE/DELETE by valid UUID, org-wide
-- membership vs. a different hotel's operational data, authenticated with
-- no membership at all, authenticated with a membership on a different
-- organization, missing property mapping, and a mapping pointing at an
-- unexpected organization (proving the wrapper follows the mapping table
-- itself, not a cached/hardcoded assumption).
begin;
create extension if not exists pgtap;
select plan(17);

insert into hotels (id, name, timezone, active) values
  ('00000022-0000-0000-0000-00000000ff01', 'Hotel Uno', 'Europe/Rome', true),
  ('00000022-0000-0000-0000-00000000ff02', 'Hotel Due', 'Europe/Rome', true);
select backfill_legacy_property_mapping();
select backfill_guest_requests_entitlement();

-- H3 is inserted only AFTER the backfill above ran, and
-- backfill_legacy_property_mapping() is never called again in this file —
-- it stays genuinely unmapped until the deliberate manual mapping later.
insert into hotels (id, name, timezone, active) values
  ('00000022-0000-0000-0000-00000000ff03', 'Hotel Tre (non mappato)', 'Europe/Rome', true);

insert into request_categories (id, hotel_id, name, department) values
  ('00000022-0000-0000-0000-000000000c01', '00000022-0000-0000-0000-00000000ff01', 'Housekeeping', 'housekeeping'),
  ('00000022-0000-0000-0000-000000000c02', '00000022-0000-0000-0000-00000000ff02', 'Housekeeping', 'housekeeping');
insert into request_types (id, category_id, name) values
  ('00000022-0000-0000-0000-0000000fee01', '00000022-0000-0000-0000-000000000c01', 'Asciugamani'),
  ('00000022-0000-0000-0000-0000000fee02', '00000022-0000-0000-0000-000000000c02', 'Asciugamani');

insert into rooms (id, hotel_id, room_number) values
  ('00000022-0000-0000-0000-0000000fa001', '00000022-0000-0000-0000-00000000ff01', '101'),
  ('00000022-0000-0000-0000-0000000fa002', '00000022-0000-0000-0000-00000000ff02', '201');

insert into guest_requests (id, hotel_id, room_number, request_type_id, quantity, assigned_department, status) values
  ('00000022-0000-0000-0000-00000000ba01', '00000022-0000-0000-0000-00000000ff01', '101', '00000022-0000-0000-0000-0000000fee01', 1, 'housekeeping', 'requested'),
  ('00000022-0000-0000-0000-00000000ba02', '00000022-0000-0000-0000-00000000ff02', '201', '00000022-0000-0000-0000-0000000fee02', 1, 'housekeeping', 'requested');

insert into auth.users (id) values
  ('00000022-0000-0000-0000-000000000a01'), -- property_admin @ H1
  ('00000022-0000-0000-0000-000000000a02'), -- property_admin @ H2
  ('00000022-0000-0000-0000-000000000a03'), -- staff_profiles row exists but no core membership
  ('00000022-0000-0000-0000-000000000a04'), -- has an active membership, but on an unrelated organization only
  ('00000022-0000-0000-0000-000000000a05'); -- @ H3 (unmapped hotel)

insert into staff_profiles (id, hotel_id, auth_user_id, name, role, department, active, login_username) values
  ('00000022-0000-0000-0000-000000000101', '00000022-0000-0000-0000-00000000ff01', '00000022-0000-0000-0000-000000000a01', 'PA Uno', 'admin', null, true, null),
  ('00000022-0000-0000-0000-000000000102', '00000022-0000-0000-0000-00000000ff02', '00000022-0000-0000-0000-000000000a02', 'PA Due', 'admin', null, true, null),
  ('00000022-0000-0000-0000-000000000103', '00000022-0000-0000-0000-00000000ff01', '00000022-0000-0000-0000-000000000a03', 'Nessuna Membership', 'admin', null, true, null),
  ('00000022-0000-0000-0000-000000000104', '00000022-0000-0000-0000-00000000ff01', '00000022-0000-0000-0000-000000000a04', 'Org Sbagliata', 'admin', null, true, null);

select backfill_staff_identity();

-- H3's staff row is inserted separately, AFTER the backfill above:
-- backfill_staff_identity() raises on any staff row whose hotel has no
-- mapping (Step 4's own fail-loud design), so it must never see this row.
-- Only its profiles row is created manually — no membership is possible
-- (or expected) for a genuinely unmapped hotel.
insert into staff_profiles (id, hotel_id, auth_user_id, name, role, department, active, login_username) values
  ('00000022-0000-0000-0000-000000000105', '00000022-0000-0000-0000-00000000ff03', '00000022-0000-0000-0000-000000000a05', 'Hotel Non Mappato', 'admin', null, true, null);
insert into profiles (id, full_name) values ('00000022-0000-0000-0000-000000000a05', 'Hotel Non Mappato');

-- profile 103 keeps no membership at all (simulates "authenticated senza membership")
delete from memberships where profile_id = '00000022-0000-0000-0000-000000000a03';

-- profile 104: give it an active organization_admin membership on a WHOLLY
-- UNRELATED organization (never touching H1/H2's), simulating "authenticated
-- con membership su altra organization" — its own real property-scoped
-- membership (created by the backfill above, on H1's org) is removed first.
delete from memberships where profile_id = '00000022-0000-0000-0000-000000000a04';
insert into organizations (id, name, slug) values ('00000022-0000-0000-0000-000000009999', 'Org Estranea', 'org-022-estranea');
insert into properties (id, organization_id, name, slug) values
  ('00000022-0000-0000-0000-000000009998', '00000022-0000-0000-0000-000000009999', 'Property Estranea', 'p-022-estranea');
insert into memberships (profile_id, organization_id, role_id, status)
select '00000022-0000-0000-0000-000000000a04', '00000022-0000-0000-0000-000000009999', id, 'active'
from roles where slug = 'organization_admin';

-- ### 1-4: cross-property SELECT/INSERT/UPDATE/DELETE by valid UUID ###
set local role authenticated;
set local request.jwt.claim.sub = '00000022-0000-0000-0000-000000000a01';

select is(
  (select count(*)::int from guest_requests where id = '00000022-0000-0000-0000-00000000ba02'),
  0,
  'staff @ H1: SELECT by the valid UUID of an H2 guest_requests row returns 0 rows'
);

update guest_requests set status = 'cancelled' where id = '00000022-0000-0000-0000-00000000ba02';
delete from guest_requests where id = '00000022-0000-0000-0000-00000000ba02';
reset role;
select is(
  (select status from guest_requests where id = '00000022-0000-0000-0000-00000000ba02'),
  'requested'::request_status,
  'staff @ H1: UPDATE by the valid UUID of an H2 row matched nothing (checked without RLS restriction) — H2''s row is unchanged'
);
select is(
  (select count(*)::int from guest_requests where id = '00000022-0000-0000-0000-00000000ba02'),
  1,
  'staff @ H1: DELETE by the valid UUID of an H2 row matched nothing — the row still exists'
);
set local role authenticated;
set local request.jwt.claim.sub = '00000022-0000-0000-0000-000000000a01';

select throws_ok(
  $$ insert into guest_requests (hotel_id, room_number, request_type_id, quantity, assigned_department, status)
     values ('00000022-0000-0000-0000-00000000ff02', '201', '00000022-0000-0000-0000-0000000fee02', 1, 'housekeeping', 'requested') $$,
  '42501',
  null,
  'staff @ H1: INSERT of a row explicitly targeting H2 is denied at the WITH CHECK / grant level'
);

select is(
  (select count(*)::int from rooms where hotel_id = '00000022-0000-0000-0000-00000000ff02'),
  0,
  'staff @ H1: SELECT on rooms of H2 returns 0 rows'
);
reset role;

-- ### authenticated senza membership ###
set local role authenticated;
set local request.jwt.claim.sub = '00000022-0000-0000-0000-000000000a03';
select is(current_staff_hotel(), null, 'active staff_profiles row but no core membership at all -> current_staff_hotel() is null');
select is(
  (select count(*)::int from guest_requests where hotel_id = '00000022-0000-0000-0000-00000000ff01'),
  0,
  'authenticated with no membership sees 0 guest_requests rows, even at their own nominal hotel'
);
reset role;

-- ### authenticated con membership su altra organization ###
set local role authenticated;
set local request.jwt.claim.sub = '00000022-0000-0000-0000-000000000a04';
select is(current_staff_hotel(), null, 'a membership on an unrelated organization does not resolve this caller''s own hotel');
select is(
  (select count(*)::int from guest_requests where hotel_id = '00000022-0000-0000-0000-00000000ff01'),
  0,
  'authenticated with a membership on a different organization sees 0 guest_requests rows at H1'
);
select is(
  (select count(*)::int from staff_profiles where hotel_id = '00000022-0000-0000-0000-00000000ff01'),
  0,
  'the same caller also sees 0 rows on the staff_profiles roster (org-wide check correctly excludes an unrelated org)'
);
reset role;

-- ### property mapping mancante (H3 was never mapped) ###
select is(
  (select count(*)::int from legacy_property_mapping where legacy_hotel_id = '00000022-0000-0000-0000-00000000ff03'),
  0,
  'H3 genuinely has no legacy_property_mapping row (fixture setup sanity check)'
);
set local role authenticated;
set local request.jwt.claim.sub = '00000022-0000-0000-0000-000000000a05';
select is(current_staff_hotel(), null, 'staff at an unmapped hotel resolve no hotel at all — fail closed');
select is(
  (select count(*)::int from staff_profiles where hotel_id = '00000022-0000-0000-0000-00000000ff03'),
  0,
  'staff at an unmapped hotel see 0 rows even on their own roster'
);
reset role;

-- ### mapping presente ma verso organization errata: point H3's mapping at
-- an existing property belonging to a DIFFERENT, unrelated organization,
-- and prove access follows that actual target, not any assumption ###
insert into legacy_property_mapping (legacy_hotel_id, platform_property_id)
select '00000022-0000-0000-0000-00000000ff03', p.id
from properties p where p.organization_id = '00000022-0000-0000-0000-000000009999'
limit 1;
insert into property_modules (property_id, module_id, enabled)
select (select platform_property_id from legacy_property_mapping where legacy_hotel_id = '00000022-0000-0000-0000-00000000ff03'),
  id, true from modules where slug = 'guest_requests'
on conflict (property_id, module_id) do update set enabled = true;

set local role authenticated;
-- a04 holds organization_admin specifically on org o999, which the mapping
-- now (deliberately, artificially) points H3 at
set local request.jwt.claim.sub = '00000022-0000-0000-0000-000000000a04';
select is(current_staff_hotel(), null,
  'a04''s own staff_profiles.hotel_id is still H1, not H3, so this mapping change does not grant them H3 access either'
);
reset role;

set local role authenticated;
-- a05 (@ H3) now resolves through the corrupted mapping to org o999's
-- property; they have NO membership on org o999 at all, so still denied —
-- proving the wrapper genuinely re-evaluates has_property_access() against
-- whatever the mapping says, rather than trusting the hotel/org pairing
-- implicitly
set local request.jwt.claim.sub = '00000022-0000-0000-0000-000000000a05';
select is(current_staff_hotel(), null,
  'staff @ H3, now mapped to org o999''s property: still denied, since they hold no membership on o999'
);
reset role;
-- grant a05 org-admin on o999 and confirm access now DOES follow the
-- (corrupted) mapping target, not H3's "intended" organization
insert into memberships (profile_id, organization_id, role_id, status)
select '00000022-0000-0000-0000-000000000a05', '00000022-0000-0000-0000-000000009999', id, 'active'
from roles where slug = 'organization_admin';
set local role authenticated;
set local request.jwt.claim.sub = '00000022-0000-0000-0000-000000000a05';
select is(current_staff_hotel(), '00000022-0000-0000-0000-00000000ff03'::uuid,
  'once a05 holds org_admin on o999, H3 (mapped to a property in o999) resolves — access strictly follows the mapping table itself'
);
reset role;

select is(
  (select count(*)::int from legacy_property_mapping),
  3,
  'sanity: 3 mapping rows exist in total (H1, H2 from the normal backfill, H3 from the deliberate corruption above)'
);

select * from finish();
rollback;
