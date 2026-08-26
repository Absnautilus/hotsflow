-- D: a property_admin can assign manager (rank 20 < 30).
-- E: a property_admin cannot assign organization_admin — not just because
-- of rank (40 > 30), but because organization_admin is organization-scoped
-- and this membership is property-scoped: role_assignment_allowed rejects
-- the scope mismatch before rank is even compared. Both reasons hold; the
-- test only checks the (correct) end result.
begin;
create extension if not exists pgtap;
select plan(2);

insert into organizations (id, name, slug) values
  ('00000012-0000-0000-0000-000000000001', 'Test Org', 'test-012-org');
insert into properties (id, organization_id, name, slug) values
  ('00000012-0000-0000-0000-000000000011', '00000012-0000-0000-0000-000000000001', 'Property A1', 'a1');

insert into auth.users (id) values
  ('00000012-0000-0000-0000-000000000041'),
  ('00000012-0000-0000-0000-000000000042'),
  ('00000012-0000-0000-0000-000000000043');
insert into profiles (id, full_name) values
  ('00000012-0000-0000-0000-000000000041', 'Property Admin'),
  ('00000012-0000-0000-0000-000000000042', 'Receptionist (for D)'),
  ('00000012-0000-0000-0000-000000000043', 'Receptionist (for E)');

insert into memberships (id, profile_id, property_id, role_id, status)
select '00000012-0000-0000-0000-000000000051', '00000012-0000-0000-0000-000000000041', '00000012-0000-0000-0000-000000000011', id, 'active'
from roles where slug = 'property_admin';
insert into memberships (id, profile_id, property_id, role_id, status)
select '00000012-0000-0000-0000-000000000052', '00000012-0000-0000-0000-000000000042', '00000012-0000-0000-0000-000000000011', id, 'active'
from roles where slug = 'receptionist';
insert into memberships (id, profile_id, property_id, role_id, status)
select '00000012-0000-0000-0000-000000000053', '00000012-0000-0000-0000-000000000043', '00000012-0000-0000-0000-000000000011', id, 'active'
from roles where slug = 'receptionist';

set local role authenticated;
set local request.jwt.claim.sub = '00000012-0000-0000-0000-000000000041';

-- D
select lives_ok(
  $$ select assign_membership_role('00000012-0000-0000-0000-000000000052', (select id from roles where slug = 'manager')) $$,
  'a property_admin can assign manager to a receptionist'
);

-- E
select throws_ok(
  $$ select assign_membership_role('00000012-0000-0000-0000-000000000053', (select id from roles where slug = 'organization_admin')) $$,
  '42501',
  'role_assignment_not_allowed',
  'a property_admin cannot assign organization_admin'
);

select * from finish();
rollback;
