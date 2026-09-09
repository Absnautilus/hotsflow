-- Cross-hotel foreign references must be rejected independently of RLS.
-- This protects both normal clients and privileged/background writers that
-- already know a valid UUID from another hotel.
begin;
create extension if not exists pgtap;
select plan(13);

insert into hotels (id, name) values
  ('00000037-0000-0000-0000-00000000ff01', 'Hotel Uno'),
  ('00000037-0000-0000-0000-00000000ff02', 'Hotel Due');

insert into rooms (id, hotel_id, room_number) values
  ('00000037-0000-0000-0000-00000000aa01', '00000037-0000-0000-0000-00000000ff01', '101'),
  ('00000037-0000-0000-0000-00000000aa02', '00000037-0000-0000-0000-00000000ff02', '201');

insert into request_categories (id, hotel_id, name, department) values
  ('00000037-0000-0000-0000-00000000bb01', '00000037-0000-0000-0000-00000000ff01', 'H1 Housekeeping', 'housekeeping'),
  ('00000037-0000-0000-0000-00000000bb02', '00000037-0000-0000-0000-00000000ff02', 'H2 Housekeeping', 'housekeeping');

insert into request_types (id, category_id, name) values
  ('00000037-0000-0000-0000-00000000cc01', '00000037-0000-0000-0000-00000000bb01', 'H1 Towels'),
  ('00000037-0000-0000-0000-00000000cc02', '00000037-0000-0000-0000-00000000bb02', 'H2 Towels');

insert into auth.users (id) values
  ('00000037-0000-0000-0000-00000000dd01'),
  ('00000037-0000-0000-0000-00000000dd02');

insert into staff_profiles (id, hotel_id, auth_user_id, name, role, department, login_username) values
  ('00000037-0000-0000-0000-00000000ee01', '00000037-0000-0000-0000-00000000ff01', '00000037-0000-0000-0000-00000000dd01', 'Staff Uno', 'operatore', 'housekeeping', 'staff-037-one'),
  ('00000037-0000-0000-0000-00000000ee02', '00000037-0000-0000-0000-00000000ff02', '00000037-0000-0000-0000-00000000dd02', 'Staff Due', 'operatore', 'housekeeping', 'staff-037-two');

select lives_ok(
  $$ insert into stays (id, hotel_id, room_id, guest_last_name, check_in_at, check_out_at, created_by)
     values ('00000037-0000-0000-0000-000000001001', '00000037-0000-0000-0000-00000000ff01',
       '00000037-0000-0000-0000-00000000aa01', 'Guest', now(), now() + interval '1 day',
       '00000037-0000-0000-0000-00000000ee01') $$,
  'a stay can reference a room and creator from its own hotel'
);

select throws_ok(
  $$ insert into stays (hotel_id, room_id, guest_last_name, check_in_at, check_out_at)
     values ('00000037-0000-0000-0000-00000000ff01', '00000037-0000-0000-0000-00000000aa02',
       'Guest', now(), now() + interval '1 day') $$,
  '23514', 'stays_room_hotel_mismatch',
  'a stay cannot reference a room from another hotel'
);

select throws_ok(
  $$ insert into stays (hotel_id, room_id, guest_last_name, check_in_at, check_out_at, created_by)
     values ('00000037-0000-0000-0000-00000000ff01', '00000037-0000-0000-0000-00000000aa01',
       'Guest', now(), now() + interval '1 day', '00000037-0000-0000-0000-00000000ee02') $$,
  '23514', 'stays_creator_hotel_mismatch',
  'a stay cannot reference a creator from another hotel'
);

select lives_ok(
  $$ insert into guest_requests
       (id, hotel_id, stay_id, room_number, request_type_id, created_by_staff, accepted_by, assigned_department)
     values ('00000037-0000-0000-0000-000000002001', '00000037-0000-0000-0000-00000000ff01',
       '00000037-0000-0000-0000-000000001001', '101', '00000037-0000-0000-0000-00000000cc01',
       '00000037-0000-0000-0000-00000000ee01', '00000037-0000-0000-0000-00000000ee01', 'housekeeping') $$,
  'a request can reference a stay, menu item, creator, and acceptor from its own hotel'
);

select throws_ok(
  $$ insert into guest_requests (hotel_id, stay_id, room_number, request_type_id, assigned_department)
     values ('00000037-0000-0000-0000-00000000ff02', '00000037-0000-0000-0000-000000001001',
       '101', '00000037-0000-0000-0000-00000000cc02', 'housekeeping') $$,
  '23514', 'guest_request_stay_hotel_mismatch',
  'a request cannot reference a stay from another hotel'
);

select throws_ok(
  $$ insert into guest_requests (hotel_id, room_number, request_type_id, assigned_department)
     values ('00000037-0000-0000-0000-00000000ff01', '101',
       '00000037-0000-0000-0000-00000000cc02', 'housekeeping') $$,
  '23514', 'guest_request_type_hotel_mismatch',
  'a request cannot reference a menu item from another hotel'
);

select throws_ok(
  $$ insert into guest_requests (hotel_id, room_number, request_type_id, created_by_staff, assigned_department)
     values ('00000037-0000-0000-0000-00000000ff01', '101',
       '00000037-0000-0000-0000-00000000cc01', '00000037-0000-0000-0000-00000000ee02', 'housekeeping') $$,
  '23514', 'guest_request_creator_hotel_mismatch',
  'a request cannot reference a creator from another hotel'
);

select throws_ok(
  $$ insert into guest_requests (hotel_id, room_number, request_type_id, accepted_by, assigned_department)
     values ('00000037-0000-0000-0000-00000000ff01', '101',
       '00000037-0000-0000-0000-00000000cc01', '00000037-0000-0000-0000-00000000ee02', 'housekeeping') $$,
  '23514', 'guest_request_acceptor_hotel_mismatch',
  'a request cannot reference an acceptor from another hotel'
);

select throws_ok(
  $$ insert into guest_requests (hotel_id, room_number, request_type_id, assigned_department)
     values ('00000037-0000-0000-0000-00000000ff01', '201',
       '00000037-0000-0000-0000-00000000cc01', 'housekeeping') $$,
  '23514', 'guest_request_room_hotel_mismatch',
  'a staff-created request cannot name a room from another hotel'
);

select throws_ok(
  $$ update guest_requests set request_type_id = '00000037-0000-0000-0000-00000000cc02'
     where id = '00000037-0000-0000-0000-000000002001' $$,
  '23514', 'guest_request_type_hotel_mismatch',
  'an existing request cannot be moved to another hotel menu item'
);

select throws_ok(
  $$ update guest_requests set accepted_by = '00000037-0000-0000-0000-00000000ee02'
     where id = '00000037-0000-0000-0000-000000002001' $$,
  '23514', 'guest_request_acceptor_hotel_mismatch',
  'an existing request cannot be assigned to another hotel staff profile'
);

select throws_ok(
  $$ update stays set room_id = '00000037-0000-0000-0000-00000000aa02'
     where id = '00000037-0000-0000-0000-000000001001' $$,
  '23514', 'stays_room_hotel_mismatch',
  'an existing stay cannot be moved to another hotel room'
);

-- Production may already contain a historical request with a foreign menu
-- reference. The migration deliberately does not scan or rewrite it, and
-- ordinary operational changes must remain possible until a separately
-- approved cleanup corrects that reference.
alter table guest_requests disable trigger guest_requests_tenant_integrity;
insert into guest_requests
  (id, hotel_id, room_number, request_type_id, assigned_department)
values
  ('00000037-0000-0000-0000-000000002099', '00000037-0000-0000-0000-00000000ff01',
   '101', '00000037-0000-0000-0000-00000000cc02', 'housekeeping');
alter table guest_requests enable trigger guest_requests_tenant_integrity;

select lives_ok(
  $$ update guest_requests
     set accepted_by = '00000037-0000-0000-0000-00000000ee01', status = 'in_progress'
     where id = '00000037-0000-0000-0000-000000002099' $$,
  'a historical mismatched request remains operable when unrelated fields change'
);

select * from finish();
rollback;
