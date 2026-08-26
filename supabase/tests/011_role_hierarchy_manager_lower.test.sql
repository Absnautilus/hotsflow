-- C: a manager CAN reassign between two roles both below their own rank.
-- Seed only ships one rank-10 role (receptionist) — this adds a second,
-- test-scoped one (rank 10, same as receptionist) purely for this fixture,
-- rather than adding a real operational role to the seed just for this.
begin;
create extension if not exists pgtap;
select plan(2);

insert into organizations (id, name, slug) values
  ('00000011-0000-0000-0000-000000000001', 'Test Org', 'test-011-org');
insert into properties (id, organization_id, name, slug) values
  ('00000011-0000-0000-0000-000000000011', '00000011-0000-0000-0000-000000000001', 'Property A1', 'a1');

insert into roles (id, slug, display_name, scope, rank) values
  ('00000011-0000-0000-0000-000000000021', 'test_011_concierge', 'Concierge (test)', 'property', 10);

insert into auth.users (id) values
  ('00000011-0000-0000-0000-000000000041'),
  ('00000011-0000-0000-0000-000000000042');
insert into profiles (id, full_name) values
  ('00000011-0000-0000-0000-000000000041', 'Manager'),
  ('00000011-0000-0000-0000-000000000042', 'Receptionist');

insert into memberships (id, profile_id, property_id, role_id, status)
select '00000011-0000-0000-0000-000000000051', '00000011-0000-0000-0000-000000000041', '00000011-0000-0000-0000-000000000011', id, 'active'
from roles where slug = 'manager';
insert into memberships (id, profile_id, property_id, role_id, status)
select '00000011-0000-0000-0000-000000000052', '00000011-0000-0000-0000-000000000042', '00000011-0000-0000-0000-000000000011', id, 'active'
from roles where slug = 'receptionist';

set local role authenticated;
set local request.jwt.claim.sub = '00000011-0000-0000-0000-000000000041';

select lives_ok(
  $$ select assign_membership_role('00000011-0000-0000-0000-000000000052', '00000011-0000-0000-0000-000000000021') $$,
  'a manager can reassign between two roles both below their own rank'
);

select is(
  (select role_id from memberships where id = '00000011-0000-0000-0000-000000000052'),
  '00000011-0000-0000-0000-000000000021'::uuid,
  'the membership actually carries the new role afterwards'
);

select * from finish();
rollback;
