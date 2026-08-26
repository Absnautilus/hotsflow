-- F: a manager on Property A cannot reassign the role of staff on
-- Property B, even in a different organization entirely — has_permission's
-- own property_id match already denies this before rank is considered.
begin;
create extension if not exists pgtap;
select plan(1);

insert into organizations (id, name, slug) values
  ('00000013-0000-0000-0000-000000000001', 'Test Org A', 'test-013-org-a'),
  ('00000013-0000-0000-0000-000000000002', 'Test Org B', 'test-013-org-b');
insert into properties (id, organization_id, name, slug) values
  ('00000013-0000-0000-0000-000000000011', '00000013-0000-0000-0000-000000000001', 'Property A', 'a1'),
  ('00000013-0000-0000-0000-000000000012', '00000013-0000-0000-0000-000000000002', 'Property B', 'b1');

insert into auth.users (id) values
  ('00000013-0000-0000-0000-000000000041'),
  ('00000013-0000-0000-0000-000000000042');
insert into profiles (id, full_name) values
  ('00000013-0000-0000-0000-000000000041', 'Manager on Property A'),
  ('00000013-0000-0000-0000-000000000042', 'Receptionist on Property B');

insert into memberships (id, profile_id, property_id, role_id, status)
select '00000013-0000-0000-0000-000000000051', '00000013-0000-0000-0000-000000000041', '00000013-0000-0000-0000-000000000011', id, 'active'
from roles where slug = 'manager';
insert into memberships (id, profile_id, property_id, role_id, status)
select '00000013-0000-0000-0000-000000000052', '00000013-0000-0000-0000-000000000042', '00000013-0000-0000-0000-000000000012', id, 'active'
from roles where slug = 'receptionist';

set local role authenticated;
set local request.jwt.claim.sub = '00000013-0000-0000-0000-000000000041';

select throws_ok(
  $$ select assign_membership_role('00000013-0000-0000-0000-000000000052', (select id from roles where slug = 'manager')) $$,
  '42501',
  'role_assignment_not_allowed',
  'a manager on Property A cannot reassign a role on unrelated Property B'
);

select * from finish();
rollback;
