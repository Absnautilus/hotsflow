-- Verifies the fix in 20260910150000_fix_guest_session_sync_permission.sql:
-- sync_guest_sessions_on_stay_change() must be SECURITY DEFINER, owned
-- consistently with the rest of this schema's privileged helpers, running
-- with an empty search_path, and callable by nobody directly (PUBLIC,
-- anon, authenticated all denied EXECUTE -- only the trigger manager
-- invokes it). It must also actually fix the three stays actions it
-- backs (extend checkout, anticipate checkout, deactivate) end to end,
-- without opening any RLS bypass on the stays table itself: an
-- unauthorized actor's blocked UPDATE must leave both the stay and its
-- guest session completely untouched (proven by re-SELECTing after every
-- mutation attempt, not by lives_ok/throws_ok alone).
--
-- current_staff_hotel() (Fase 2 tenant adapter, 20260827121800) now also
-- requires the legacy hotel to be mapped to a Core platform property with
-- has_property_access() and the guest_requests module enabled -- both
-- legacy staff_profiles rows and Core memberships/property mapping are
-- required for any of this to resolve, matching the pattern already used
-- by 033_guest_requests_runtime_mapping.test.sql.
begin;
create extension if not exists pgtap;
select plan(24);

select is(
  (select prosecdef from pg_proc where proname = 'sync_guest_sessions_on_stay_change' and pronamespace = 'public'::regnamespace),
  true,
  'sync_guest_sessions_on_stay_change is SECURITY DEFINER (prosecdef = true)'
);

select is(
  (select proowner from pg_proc where proname = 'sync_guest_sessions_on_stay_change' and pronamespace = 'public'::regnamespace),
  (select proowner from pg_proc where proname = 'current_staff_hotel' and pronamespace = 'public'::regnamespace),
  'owned by the same role as this schema''s other privileged helpers -- no ownership drift'
);

select is(
  (select array_to_string(proconfig, ',')
   from pg_proc where proname = 'sync_guest_sessions_on_stay_change' and pronamespace = 'public'::regnamespace),
  'search_path=""',
  'search_path is configured to exactly SET search_path = '''' (stored as search_path="") -- not merely "excludes public", the precise empty value'
);

select is(
  has_function_privilege('public', 'sync_guest_sessions_on_stay_change()', 'EXECUTE'),
  false,
  'PUBLIC has no EXECUTE on the trigger function'
);
select is(
  has_function_privilege('anon', 'sync_guest_sessions_on_stay_change()', 'EXECUTE'),
  false,
  'anon has no EXECUTE on the trigger function'
);
select is(
  has_function_privilege('authenticated', 'sync_guest_sessions_on_stay_change()', 'EXECUTE'),
  false,
  'authenticated has no EXECUTE on the trigger function'
);

-- ### fixture: two hotels, mapped to Core properties, front-desk and
-- housekeeping staff, one stay + session each ###
insert into hotels (id, name, timezone, active) values
  ('00000040-0000-0000-0000-0000000000a1', 'Test 040 Hotel A', 'Europe/Rome', true),
  ('00000040-0000-0000-0000-0000000000b1', 'Test 040 Hotel B', 'Europe/Rome', true);

select backfill_legacy_property_mapping();
select backfill_guest_requests_entitlement();

create temporary table t040_property_ids (
  key text primary key,
  property_id uuid not null
);
insert into t040_property_ids (key, property_id)
select case m.legacy_hotel_id
    when '00000040-0000-0000-0000-0000000000a1'::uuid then 'a'
    when '00000040-0000-0000-0000-0000000000b1'::uuid then 'b'
  end,
  m.platform_property_id
from legacy_property_mapping m
where m.legacy_hotel_id in ('00000040-0000-0000-0000-0000000000a1', '00000040-0000-0000-0000-0000000000b1');
grant select on t040_property_ids to authenticated;

insert into auth.users (id) values
  ('00000040-0000-0000-0000-000000000041'),
  ('00000040-0000-0000-0000-000000000042'),
  ('00000040-0000-0000-0000-000000000043');

insert into profiles (id, full_name) values
  ('00000040-0000-0000-0000-000000000041', 'Admin A'),
  ('00000040-0000-0000-0000-000000000042', 'Housekeeping A'),
  ('00000040-0000-0000-0000-000000000043', 'Admin B');

-- legacy identity: role/department drives current_staff_manages_front_desk()
insert into staff_profiles (id, hotel_id, auth_user_id, name, role, department, login_username) values
  ('00000040-0000-0000-0000-000000000051', '00000040-0000-0000-0000-0000000000a1', '00000040-0000-0000-0000-000000000041', 'Admin A', 'admin', null, null),
  ('00000040-0000-0000-0000-000000000052', '00000040-0000-0000-0000-0000000000a1', '00000040-0000-0000-0000-000000000042', 'Housekeeping A', 'operatore', 'housekeeping', 'test040-housekeeping-a'),
  ('00000040-0000-0000-0000-000000000053', '00000040-0000-0000-0000-0000000000b1', '00000040-0000-0000-0000-000000000043', 'Admin B', 'admin', null, null);

-- Core identity: has_property_access() requires an active membership on
-- the mapped platform property, AND current_staff_role() (Fase 2 tenant
-- adapter) no longer reads staff_profiles.role at all -- it derives the
-- legacy role entirely from current_actor_role_rank() on this same
-- membership (rank 30 = property_admin -> 'admin', rank 10 = receptionist
-- -> 'operatore'). The membership's role must therefore match the legacy
-- role each fixture actor is meant to have, not just exist.
insert into memberships (profile_id, property_id, role_id, status)
select '00000040-0000-0000-0000-000000000041', (select property_id from t040_property_ids where key = 'a'), r.id, 'active'
from roles r where r.slug = 'property_admin';
insert into memberships (profile_id, property_id, role_id, status)
select '00000040-0000-0000-0000-000000000042', (select property_id from t040_property_ids where key = 'a'), r.id, 'active'
from roles r where r.slug = 'receptionist';
insert into memberships (profile_id, property_id, role_id, status)
select '00000040-0000-0000-0000-000000000043', (select property_id from t040_property_ids where key = 'b'), r.id, 'active'
from roles r where r.slug = 'property_admin';

insert into rooms (id, hotel_id, room_number) values
  ('00000040-0000-0000-0000-000000000061', '00000040-0000-0000-0000-0000000000a1', 'A1'),
  ('00000040-0000-0000-0000-000000000062', '00000040-0000-0000-0000-0000000000b1', 'B1'),
  ('00000040-0000-0000-0000-000000000063', '00000040-0000-0000-0000-0000000000a1', 'A2'),
  ('00000040-0000-0000-0000-000000000064', '00000040-0000-0000-0000-0000000000a1', 'A3');

insert into stays (id, hotel_id, room_id, guest_last_name, check_in_at, check_out_at, status) values
  ('00000040-0000-0000-0000-000000000071', '00000040-0000-0000-0000-0000000000a1', '00000040-0000-0000-0000-000000000061', 'Rossi', now() - interval '1 day', now() + interval '1 day', 'active');

insert into guest_requests_guest_sessions (id, stay_id, token_hash, expires_at) values
  ('00000040-0000-0000-0000-000000000081', '00000040-0000-0000-0000-000000000071', 'test-token-hash-081', now() + interval '1 day');

set local role authenticated;
set local request.jwt.claim.sub = '00000040-0000-0000-0000-000000000041';

-- ### extend checkout (admin, own hotel) ###
select lives_ok(
  $$ update stays set check_out_at = now() + interval '2 days' where id = '00000040-0000-0000-0000-000000000071' $$,
  'an authorized admin can extend the checkout'
);
select ok(
  (select check_out_at > now() + interval '1 day' from stays where id = '00000040-0000-0000-0000-000000000071'),
  'the extended check_out_at was actually persisted (re-SELECT, not just lives_ok)'
);
-- guest_requests_guest_sessions has zero grants to authenticated by design
-- (reachable only through SECURITY DEFINER functions) -- verification
-- reads of it must run as the table owner, same lesson as memberships
-- earlier: checking through the acting staff member's own eyes would
-- itself fail with permission denied, proving nothing about the trigger.
reset role;
select is(
  (select expires_at from guest_requests_guest_sessions where id = '00000040-0000-0000-0000-000000000081'),
  (select check_out_at from stays where id = '00000040-0000-0000-0000-000000000071'),
  'the session''s expires_at exactly matches the extended stays.check_out_at -- not merely both greater than an arbitrary bound'
);
select ok(
  (select revoked_at is null from guest_requests_guest_sessions where id = '00000040-0000-0000-0000-000000000081'),
  'the session stays unrevoked after the extension'
);

-- ### anticipate checkout (admin, own hotel) -- expires_at was pushed past
-- the new, earlier check_out_at, so the session must now be revoked ###
set local role authenticated;
set local request.jwt.claim.sub = '00000040-0000-0000-0000-000000000041';
select lives_ok(
  $$ update stays set check_out_at = now() + interval '1 hour' where id = '00000040-0000-0000-0000-000000000071' $$,
  'an authorized admin can anticipate the checkout'
);
select ok(
  (select check_out_at < now() + interval '2 hours' from stays where id = '00000040-0000-0000-0000-000000000071'),
  'the anticipated check_out_at was actually persisted'
);
reset role;
select ok(
  (select revoked_at is not null from guest_requests_guest_sessions where id = '00000040-0000-0000-0000-000000000081'),
  'the now-invalid session was revoked as a result of anticipating checkout'
);

-- ### deactivation revokes sessions -- fresh stay + session, isolated from
-- the mutations above ###
insert into stays (id, hotel_id, room_id, guest_last_name, check_in_at, check_out_at, status) values
  ('00000040-0000-0000-0000-000000000072', '00000040-0000-0000-0000-0000000000a1', '00000040-0000-0000-0000-000000000063', 'Bianchi', now() - interval '3 hours', now() + interval '1 day', 'active');
insert into guest_requests_guest_sessions (id, stay_id, token_hash, expires_at) values
  ('00000040-0000-0000-0000-000000000082', '00000040-0000-0000-0000-000000000072', 'test-token-hash-082', now() + interval '1 day');

set local role authenticated;
set local request.jwt.claim.sub = '00000040-0000-0000-0000-000000000041';

select lives_ok(
  $$ update stays set status = 'cancelled' where id = '00000040-0000-0000-0000-000000000072' $$,
  'an authorized admin can deactivate (cancel) a stay'
);
select is(
  (select status::text from stays where id = '00000040-0000-0000-0000-000000000072'),
  'cancelled',
  'the cancelled status was actually persisted'
);
reset role;
select ok(
  (select revoked_at is not null from guest_requests_guest_sessions where id = '00000040-0000-0000-0000-000000000082'),
  'deactivating the stay revoked its still-active guest session'
);

-- ### no RLS bypass introduced: an unauthorized actor's blocked UPDATE
-- must leave both the stay AND its guest session completely untouched --
-- not just stays.check_out_at. Uses a fresh, isolated stay + active
-- (non-revoked) session, since the sessions mutated above were already
-- revoked by the earlier scenarios and so couldn't prove anything about
-- "unchanged". Both denied actors also fail to SELECT the stays row at
-- all (stays_select_front_desk shares the exact same predicate as the
-- write policy), so -- same lesson as guest_requests_guest_sessions above
-- -- every verification read below runs as the table owner, not through
-- the denied actor's own eyes. All four properties are re-checked after
-- EACH of the two denied attempts: the stay's check_out_at, the session's
-- expires_at, the session's revoked_at, and that no session was created
-- or deleted for this stay (count stays at exactly 1, same id). Since the
-- whole test runs inside a single transaction, now() is stable throughout,
-- so re-evaluating now() + interval '1 day' below is an exact comparison
-- against the fixture's original values, not an approximation. ###
insert into stays (id, hotel_id, room_id, guest_last_name, check_in_at, check_out_at, status) values
  ('00000040-0000-0000-0000-000000000073', '00000040-0000-0000-0000-0000000000a1', '00000040-0000-0000-0000-000000000064', 'Verdi', now() - interval '2 hours', now() + interval '1 day', 'active');
insert into guest_requests_guest_sessions (id, stay_id, token_hash, expires_at) values
  ('00000040-0000-0000-0000-000000000083', '00000040-0000-0000-0000-000000000073', 'test-token-hash-083', now() + interval '1 day');

set local role authenticated;
set local request.jwt.claim.sub = '00000040-0000-0000-0000-000000000043';
update stays set check_out_at = now() + interval '5 days' where id = '00000040-0000-0000-0000-000000000073';
reset role;
select is(
  (select check_out_at from stays where id = '00000040-0000-0000-0000-000000000073'),
  (select now() + interval '1 day'),
  'cross-hotel: stays.check_out_at is unchanged after the blocked update'
);
select is(
  (select expires_at from guest_requests_guest_sessions where id = '00000040-0000-0000-0000-000000000083'),
  (select now() + interval '1 day'),
  'cross-hotel: the session''s expires_at is unchanged -- the trigger never fired'
);
select ok(
  (select revoked_at is null from guest_requests_guest_sessions where id = '00000040-0000-0000-0000-000000000083'),
  'cross-hotel: the session remains unrevoked'
);
select is(
  (select count(*) from guest_requests_guest_sessions where stay_id = '00000040-0000-0000-0000-000000000073'),
  1::bigint,
  'cross-hotel: no session was created or deleted for this stay'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000040-0000-0000-0000-000000000042';
update stays set check_out_at = now() + interval '5 days' where id = '00000040-0000-0000-0000-000000000073';
reset role;
select is(
  (select check_out_at from stays where id = '00000040-0000-0000-0000-000000000073'),
  (select now() + interval '1 day'),
  'housekeeping operatore: stays.check_out_at is unchanged after the blocked update'
);
select is(
  (select expires_at from guest_requests_guest_sessions where id = '00000040-0000-0000-0000-000000000083'),
  (select now() + interval '1 day'),
  'housekeeping operatore: the session''s expires_at is unchanged -- the trigger never fired'
);
select ok(
  (select revoked_at is null from guest_requests_guest_sessions where id = '00000040-0000-0000-0000-000000000083'),
  'housekeeping operatore: the session remains unrevoked'
);
select is(
  (select count(*) from guest_requests_guest_sessions where stay_id = '00000040-0000-0000-0000-000000000073'),
  1::bigint,
  'housekeeping operatore: no session was created or deleted for this stay'
);

select * from finish();
rollback;
