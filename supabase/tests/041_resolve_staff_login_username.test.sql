begin;
create extension if not exists pgtap;
select plan(6);

insert into organizations (id, name, slug) values
  ('00000041-0000-0000-0000-000000000001', 'Resolve Org A', 'test-041-org-a'),
  ('00000041-0000-0000-0000-000000000002', 'Resolve Org B', 'test-041-org-b');
insert into properties (id, organization_id, name, slug) values
  ('00000041-0000-0000-0000-000000000011', '00000041-0000-0000-0000-000000000001', 'Resolve Property A', 'resolve-a'),
  ('00000041-0000-0000-0000-000000000012', '00000041-0000-0000-0000-000000000002', 'Resolve Property B', 'resolve-b');

insert into auth.users (id) values
  ('00000041-0000-0000-0000-000000000041'),
  ('00000041-0000-0000-0000-000000000042'),
  ('00000041-0000-0000-0000-000000000043'),
  ('00000041-0000-0000-0000-000000000044');
insert into profiles (id, full_name) values
  ('00000041-0000-0000-0000-000000000041', 'Resolve Staff One'),
  ('00000041-0000-0000-0000-000000000042', 'Resolve Staff Two'),
  ('00000041-0000-0000-0000-000000000043', 'Resolve Staff Three'),
  ('00000041-0000-0000-0000-000000000044', 'Resolve Staff Four');

-- 'mario' exists at both properties (different, unrelated organizations) --
-- exactly the collision the function must surface as two identifiers, not
-- silently pick one.
insert into memberships (profile_id, property_id, role_id, status, username)
select '00000041-0000-0000-0000-000000000041', '00000041-0000-0000-0000-000000000011', id, 'active', 'mario'
from roles where slug = 'receptionist';
insert into memberships (profile_id, property_id, role_id, status, username)
select '00000041-0000-0000-0000-000000000043', '00000041-0000-0000-0000-000000000012', id, 'active', 'mario'
from roles where slug = 'receptionist';
insert into memberships (profile_id, property_id, role_id, status, username)
select '00000041-0000-0000-0000-000000000042', '00000041-0000-0000-0000-000000000012', id, 'active', 'giulia'
from roles where slug = 'receptionist';
-- Never touched by the rate-limit fixture below -- the control case proving
-- the throttle doesn't lock out lookups it was never asked about.
insert into memberships (profile_id, property_id, role_id, status, username)
select '00000041-0000-0000-0000-000000000044', '00000041-0000-0000-0000-000000000011', id, 'active', 'anna'
from roles where slug = 'receptionist';

set local role anon;

select results_eq(
  $$ select resolve_staff_login_identifier('giulia', null) $$,
  $$ values (array['giulia@resolve-b.test-041-org-b.staff.hotsflow.internal']) $$,
  'a username unique across the platform resolves to exactly one login identifier'
);

select is(
  (select array_length(resolve_staff_login_identifier('mario', null), 1)),
  2,
  'a username shared by two unrelated properties resolves to both login identifiers'
);

select results_eq(
  $$ select resolve_staff_login_identifier('does-not-exist', null) $$,
  $$ values (array[]::text[]) $$,
  'a username matching no membership resolves to an empty array, not an error'
);

reset role;

-- Rate limiting: insert enough prior attempts from the same IP to hit the
-- 20-per-15-minutes throttle (20260911100000's own limit), then verify even
-- a real, resolvable username comes back empty rather than revealing
-- anything -- same "can't distinguish throttled from not-found" property
-- guest_login already relies on.
insert into staff_login_lookup_attempts (ip_address, username_attempted)
select '203.0.113.5'::inet, 'giulia' from generate_series(1, 20);

set local role anon;

select results_eq(
  $$ select resolve_staff_login_identifier('giulia', '203.0.113.5'::inet) $$,
  $$ values (array[]::text[]) $$,
  'a throttled IP gets an empty result even for a username that really exists'
);

-- Deliberately keyed on IP *or* username (same shape as guest_login's own
-- throttle) -- hammering "giulia" from many different IPs is exactly the
-- distributed-guessing case this is meant to catch too, so a different IP
-- asking about "giulia" is still throttled. What must NOT be throttled is
-- an unrelated username/IP pair that was never actually hammered.
select results_eq(
  $$ select resolve_staff_login_identifier('giulia', '198.51.100.9'::inet) $$,
  $$ values (array[]::text[]) $$,
  'the same username is still throttled even from a different IP (distributed-guessing protection)'
);

select results_eq(
  $$ select resolve_staff_login_identifier('anna', '198.51.100.9'::inet) $$,
  $$ values (array['anna@resolve-a.test-041-org-a.staff.hotsflow.internal']) $$,
  'an unrelated username/IP pair that was never attempted is not throttled'
);

reset role;

select * from finish();
rollback;
