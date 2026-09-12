-- reservations: schema-only scaffolding ahead of a future PMS integration.
-- Checks the constraints (departure after arrival, confirmation_code
-- unique per hotel but reusable across hotels), the default-hotel trigger,
-- and that RLS scopes it to front desk at the caller's own hotel, mirroring
-- stays' own policies exactly.
begin;
create extension if not exists pgtap;
select plan(6);

insert into hotels (id, name, timezone, active) values
  ('00000045-0000-0000-0000-0000000000a1', 'Test 045 Hotel A', 'Europe/Rome', true),
  ('00000045-0000-0000-0000-0000000000b1', 'Test 045 Hotel B', 'Europe/Rome', true);

select backfill_legacy_property_mapping();
select backfill_guest_requests_entitlement();

create temporary table t045_property_ids (
  key text primary key,
  property_id uuid not null
);
insert into t045_property_ids (key, property_id)
select case m.legacy_hotel_id
    when '00000045-0000-0000-0000-0000000000a1'::uuid then 'a'
    when '00000045-0000-0000-0000-0000000000b1'::uuid then 'b'
  end,
  m.platform_property_id
from legacy_property_mapping m
where m.legacy_hotel_id in ('00000045-0000-0000-0000-0000000000a1', '00000045-0000-0000-0000-0000000000b1');

insert into auth.users (id) values
  ('00000045-0000-0000-0000-000000000041'),
  ('00000045-0000-0000-0000-000000000043');
insert into profiles (id, full_name) values
  ('00000045-0000-0000-0000-000000000041', 'Admin A'),
  ('00000045-0000-0000-0000-000000000043', 'Admin B');

insert into staff_profiles (id, hotel_id, auth_user_id, name, role, department, login_username) values
  ('00000045-0000-0000-0000-000000000051', '00000045-0000-0000-0000-0000000000a1', '00000045-0000-0000-0000-000000000041', 'Admin A', 'admin', null, null),
  ('00000045-0000-0000-0000-000000000053', '00000045-0000-0000-0000-0000000000b1', '00000045-0000-0000-0000-000000000043', 'Admin B', 'admin', null, null);

insert into memberships (profile_id, property_id, role_id, status)
select '00000045-0000-0000-0000-000000000041', (select property_id from t045_property_ids where key = 'a'), r.id, 'active'
from roles r where r.slug = 'property_admin';
insert into memberships (profile_id, property_id, role_id, status)
select '00000045-0000-0000-0000-000000000043', (select property_id from t045_property_ids where key = 'b'), r.id, 'active'
from roles r where r.slug = 'property_admin';

-- ### constraint: departure must be after arrival ###
set local role authenticated;
set local request.jwt.claim.sub = '00000045-0000-0000-0000-000000000041';
select throws_ok(
  $$ insert into reservations (hotel_id, guest_last_name, confirmation_code, arrival_date, departure_date)
     values ('00000045-0000-0000-0000-0000000000a1', 'Bad Dates', 'RES-BAD', '2026-10-05', '2026-10-01') $$,
  '23514', null,
  'a reservation with departure before arrival is rejected'
);

-- ### authorized front-desk staff can create + see their own hotel's reservation ###
insert into reservations (hotel_id, guest_last_name, confirmation_code, arrival_date, departure_date) values
  ('00000045-0000-0000-0000-0000000000a1', 'Rossi', 'RES-001', '2026-10-10', '2026-10-15');
select is(
  (select count(*)::int from reservations where confirmation_code = 'RES-001'),
  1,
  'front desk at the reservation''s own hotel can create and see it'
);

-- ### default_hotel_id_from_staff: omitting hotel_id still resolves it from
-- the caller's own staff context ###
insert into reservations (guest_last_name, confirmation_code, arrival_date, departure_date) values
  ('Bianchi', 'RES-002', '2026-10-20', '2026-10-22');
select is(
  (select hotel_id from reservations where confirmation_code = 'RES-002'),
  '00000045-0000-0000-0000-0000000000a1'::uuid,
  'omitting hotel_id on insert still resolves it from the caller''s own staff_profiles row'
);

reset role;

-- ### a different hotel's front desk cannot see it ###
set local role authenticated;
set local request.jwt.claim.sub = '00000045-0000-0000-0000-000000000043';
select is(
  (select count(*)::int from reservations where confirmation_code = 'RES-001'),
  0,
  'a different hotel''s front desk cannot see another hotel''s reservation'
);

-- ### the same confirmation_code is fine at a DIFFERENT hotel -- uniqueness
-- is per-hotel, not global ###
insert into reservations (hotel_id, guest_last_name, confirmation_code, arrival_date, departure_date) values
  ('00000045-0000-0000-0000-0000000000b1', 'Verdi', 'RES-001', '2026-11-01', '2026-11-03');
select is(
  (select count(*)::int from reservations where confirmation_code = 'RES-001'),
  1,
  'the same confirmation_code is reusable at a different hotel'
);
reset role;

-- ### duplicating a confirmation_code within the SAME hotel fails ###
set local role authenticated;
set local request.jwt.claim.sub = '00000045-0000-0000-0000-000000000041';
select throws_ok(
  $$ insert into reservations (hotel_id, guest_last_name, confirmation_code, arrival_date, departure_date)
     values ('00000045-0000-0000-0000-0000000000a1', 'Duplicate', 'RES-001', '2026-12-01', '2026-12-03') $$,
  '23505', null,
  'a duplicate confirmation_code within the same hotel is rejected'
);
reset role;

select * from finish();
rollback;
