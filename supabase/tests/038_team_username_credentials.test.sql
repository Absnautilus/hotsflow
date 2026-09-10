begin;
create extension if not exists pgtap;
select plan(6);

insert into organizations (id, name, slug) values
  ('00000038-0000-0000-0000-000000000001', 'Username Org A', 'test-038-org-a'),
  ('00000038-0000-0000-0000-000000000002', 'Username Org B', 'test-038-org-b');
insert into properties (id, organization_id, name, slug) values
  ('00000038-0000-0000-0000-000000000011', '00000038-0000-0000-0000-000000000001', 'Username Property A', 'username-a'),
  ('00000038-0000-0000-0000-000000000012', '00000038-0000-0000-0000-000000000002', 'Username Property B', 'username-b');

insert into auth.users (id) values
  ('00000038-0000-0000-0000-000000000041'),
  ('00000038-0000-0000-0000-000000000042'),
  ('00000038-0000-0000-0000-000000000043'),
  ('00000038-0000-0000-0000-000000000044'),
  ('00000038-0000-0000-0000-000000000045'),
  ('00000038-0000-0000-0000-000000000046');
insert into profiles (id, full_name) values
  ('00000038-0000-0000-0000-000000000041', 'Property A Staff One'),
  ('00000038-0000-0000-0000-000000000042', 'Property A Staff Two'),
  ('00000038-0000-0000-0000-000000000043', 'Property B Staff One'),
  ('00000038-0000-0000-0000-000000000044', 'Property A Staff Three'),
  ('00000038-0000-0000-0000-000000000045', 'Property A Staff Four'),
  ('00000038-0000-0000-0000-000000000046', 'Property A Staff Five');

-- Each insert below after the first uses a profile/property pair that has
-- never been used before in this test, on purpose: memberships already has
-- a one-row-per-(profile, property) unique index (0004_profiles_memberships.sql)
-- unrelated to username, and reusing a pair across test cases would make a
-- throws_ok assertion ambiguous about which constraint actually fired.

select lives_ok(
  $$ insert into memberships (profile_id, property_id, role_id, status, username)
     select '00000038-0000-0000-0000-000000000041', '00000038-0000-0000-0000-000000000011', id, 'active', 'mario'
     from roles where slug = 'receptionist' $$,
  'a credentials-based membership can be created with a username'
);

select throws_ok(
  $$ insert into memberships (profile_id, property_id, role_id, status, username)
     select '00000038-0000-0000-0000-000000000042', '00000038-0000-0000-0000-000000000011', id, 'active', 'mario'
     from roles where slug = 'receptionist' $$,
  '23505', null,
  'the same username cannot be reused within the same property'
);

select lives_ok(
  $$ insert into memberships (profile_id, property_id, role_id, status, username)
     select '00000038-0000-0000-0000-000000000043', '00000038-0000-0000-0000-000000000012', id, 'active', 'mario'
     from roles where slug = 'receptionist' $$,
  'the same username is allowed again at a different property'
);

select lives_ok(
  $$ insert into memberships (profile_id, property_id, role_id, status)
     select '00000038-0000-0000-0000-000000000044', '00000038-0000-0000-0000-000000000011', id, 'active'
     from roles where slug = 'manager' $$,
  'username stays optional -- an email-invited membership with no username still inserts fine'
);

select throws_ok(
  $$ insert into memberships (profile_id, property_id, role_id, status, username)
     select '00000038-0000-0000-0000-000000000045', '00000038-0000-0000-0000-000000000011', id, 'active', 'AB'
     from roles where slug = 'manager' $$,
  '23514', 'memberships_username_format',
  'a username shorter than 3 chars or with uppercase letters is rejected'
);

select throws_ok(
  $$ insert into memberships (profile_id, property_id, role_id, status, username)
     select '00000038-0000-0000-0000-000000000046', '00000038-0000-0000-0000-000000000011', id, 'active', 'ma rio!'
     from roles where slug = 'manager' $$,
  '23514', 'memberships_username_format',
  'a username with spaces or symbols outside [a-z0-9_-] is rejected'
);

select * from finish();
rollback;
