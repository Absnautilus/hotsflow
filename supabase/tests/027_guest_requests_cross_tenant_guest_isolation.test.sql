-- Fase 2 Step 7 — GUEST ISOLATION.
-- A guest token only ever resolves its own stay/hotel (list_my_requests
-- never crosses into another property's requests), an expired token,
-- a revoked token, and direct access attempts against
-- guest_requests_guest_sessions (RLS enabled, zero policies — nobody
-- should reach it directly, staff included, not just anon).
begin;
create extension if not exists pgtap;
select plan(7);

insert into hotels (id, name, timezone, active) values
  ('00000027-0000-0000-0000-00000000ff01', 'Hotel Uno', 'Europe/Rome', true),
  ('00000027-0000-0000-0000-00000000ff02', 'Hotel Due', 'Europe/Rome', true);

insert into rooms (id, hotel_id, room_number) values
  ('00000027-0000-0000-0000-0000000fa001', '00000027-0000-0000-0000-00000000ff01', '101'),
  ('00000027-0000-0000-0000-0000000fa002', '00000027-0000-0000-0000-00000000ff02', '201');

insert into stays (id, hotel_id, room_id, guest_last_name, guest_pin, status, check_in_at, check_out_at) values
  ('00000027-0000-0000-0000-0000000ca001', '00000027-0000-0000-0000-00000000ff01', '00000027-0000-0000-0000-0000000fa001', 'Rossi', '1111', 'active', now() - interval '1 hour', now() + interval '1 day'),
  ('00000027-0000-0000-0000-0000000ca002', '00000027-0000-0000-0000-00000000ff02', '00000027-0000-0000-0000-0000000fa002', 'Bianchi', '2222', 'active', now() - interval '1 hour', now() + interval '1 day');

insert into request_categories (id, hotel_id, name, department) values
  ('00000027-0000-0000-0000-000000000c01', '00000027-0000-0000-0000-00000000ff01', 'Housekeeping', 'housekeeping'),
  ('00000027-0000-0000-0000-000000000c02', '00000027-0000-0000-0000-00000000ff02', 'Housekeeping', 'housekeeping');
insert into request_types (id, category_id, name) values
  ('00000027-0000-0000-0000-0000000fee01', '00000027-0000-0000-0000-000000000c01', 'Asciugamani'),
  ('00000027-0000-0000-0000-0000000fee02', '00000027-0000-0000-0000-000000000c02', 'Asciugamani');

-- ### cross-property: two valid tokens, two different hotels ###
select guest_login('00000027-0000-0000-0000-00000000ff01', '101', '1111', null) as token_a \gset
select guest_login('00000027-0000-0000-0000-00000000ff02', '201', '2222', null) as token_b \gset

select (create_guest_request(:'token_a', '00000027-0000-0000-0000-0000000fee01', 1, 'A')).id as req_a \gset
select (create_guest_request(:'token_b', '00000027-0000-0000-0000-0000000fee02', 1, 'B')).id as req_b \gset

select is(
  (select count(*)::int from list_my_requests(:'token_a') where id = :'req_b'),
  0,
  'token A''s list_my_requests() never returns hotel B''s request, even though both tokens are simultaneously valid'
);
select is(
  (select count(*)::int from list_my_requests(:'token_b') where id = :'req_a'),
  0,
  'token B''s list_my_requests() never returns hotel A''s request either'
);
-- psql does not substitute :'var' inside a $$ ... $$ block (it's designed
-- to leave dollar-quoted bodies alone) — build the statement with format()
-- instead, so the substitution happens in a plain, non-dollar-quoted
-- argument position.
select throws_ok(
  format('select cancel_my_request(%L, %L)', :'token_a', :'req_b'),
  '22023',
  null,
  'token A cannot cancel hotel B''s request by its valid UUID (stay_id mismatch inside cancel_my_request)'
);

-- ### expired token ###
update guest_requests_guest_sessions set expires_at = now() - interval '1 minute'
  where token_hash = encode(digest(:'token_a', 'sha256'), 'hex');
select throws_ok(
  format('select list_my_requests(%L)', :'token_a'),
  '28000',
  null,
  'an expired token is rejected'
);

-- ### revoked token ###
update guest_requests_guest_sessions set expires_at = now() + interval '1 day', revoked_at = now()
  where token_hash = encode(digest(:'token_a', 'sha256'), 'hex');
select throws_ok(
  format('select list_my_requests(%L)', :'token_a'),
  '28000',
  null,
  'a revoked token is rejected'
);

-- ### direct table access attempt on guest_requests_guest_sessions ###
set local role anon;
select throws_ok(
  $$ select * from guest_requests_guest_sessions $$,
  '42501',
  null,
  'anon has no grant on guest_requests_guest_sessions at all — direct SELECT is denied outright'
);
reset role;

insert into auth.users (id) values ('00000027-0000-0000-0000-000000000a01');
insert into staff_profiles (id, hotel_id, auth_user_id, name, role, department, active, login_username) values
  ('00000027-0000-0000-0000-000000000101', '00000027-0000-0000-0000-00000000ff01', '00000027-0000-0000-0000-000000000a01', 'PA Uno', 'admin', null, true, null);
select backfill_legacy_property_mapping();
select backfill_guest_requests_entitlement();
select backfill_staff_identity();
set local role authenticated;
set local request.jwt.claim.sub = '00000027-0000-0000-0000-000000000a01';
select throws_ok(
  $$ select * from guest_requests_guest_sessions $$,
  '42501',
  null,
  'even an active, entitled property_admin has no grant on guest_requests_guest_sessions — RLS-enabled, zero policies, reachable only through the guest RPCs'
);
reset role;

select * from finish();
rollback;
