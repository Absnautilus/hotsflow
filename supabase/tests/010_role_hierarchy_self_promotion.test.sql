-- A: a manager cannot promote themselves.
-- B: a manager cannot promote someone else above their own rank.
-- Uses the real system roles (migration 0009), not test-local ones — the
-- hierarchy rule depends on their actual seeded rank and role_permissions.
begin;
create extension if not exists pgtap;
select plan(2);

insert into organizations (id, name, slug) values
  ('00000010-0000-0000-0000-000000000001', 'Test Org', 'test-010-org');
insert into properties (id, organization_id, name, slug) values
  ('00000010-0000-0000-0000-000000000011', '00000010-0000-0000-0000-000000000001', 'Property A1', 'a1');

insert into auth.users (id) values
  ('00000010-0000-0000-0000-000000000041'),
  ('00000010-0000-0000-0000-000000000042');
insert into profiles (id, full_name) values
  ('00000010-0000-0000-0000-000000000041', 'Manager'),
  ('00000010-0000-0000-0000-000000000042', 'Receptionist');

insert into memberships (id, profile_id, property_id, role_id, status)
select '00000010-0000-0000-0000-000000000051', '00000010-0000-0000-0000-000000000041', '00000010-0000-0000-0000-000000000011', id, 'active'
from roles where slug = 'manager';
insert into memberships (id, profile_id, property_id, role_id, status)
select '00000010-0000-0000-0000-000000000052', '00000010-0000-0000-0000-000000000042', '00000010-0000-0000-0000-000000000011', id, 'active'
from roles where slug = 'receptionist';

set local role authenticated;
set local request.jwt.claim.sub = '00000010-0000-0000-0000-000000000041';

-- A
select throws_ok(
  $$ select assign_membership_role('00000010-0000-0000-0000-000000000051', (select id from roles where slug = 'property_admin')) $$,
  '42501',
  'role_assignment_not_allowed',
  'a manager cannot promote their own membership'
);

-- B
select throws_ok(
  $$ select assign_membership_role('00000010-0000-0000-0000-000000000052', (select id from roles where slug = 'property_admin')) $$,
  '42501',
  'role_assignment_not_allowed',
  'a manager cannot promote someone else above their own rank'
);

select * from finish();
rollback;
