-- A staff member with a membership on one property must not be able to see
-- a property belonging to a different, unrelated organization.
begin;
create extension if not exists pgtap;
select plan(1);

insert into organizations (id, name, slug) values
  ('00000001-0000-0000-0000-000000000001', 'Test Org A', 'test-001-org-a'),
  ('00000001-0000-0000-0000-000000000002', 'Test Org B', 'test-001-org-b');

insert into properties (id, organization_id, name, slug) values
  ('00000001-0000-0000-0000-000000000011', '00000001-0000-0000-0000-000000000001', 'Property A1', 'a1'),
  ('00000001-0000-0000-0000-000000000012', '00000001-0000-0000-0000-000000000002', 'Property B1', 'b1');

insert into roles (id, slug, display_name, scope) values
  ('00000001-0000-0000-0000-000000000021', 'test_001_role', 'Test Role', 'property');

insert into auth.users (id) values ('00000001-0000-0000-0000-000000000041');
insert into profiles (id, full_name) values ('00000001-0000-0000-0000-000000000041', 'User A1');
insert into memberships (profile_id, property_id, role_id, status) values
  ('00000001-0000-0000-0000-000000000041', '00000001-0000-0000-0000-000000000011', '00000001-0000-0000-0000-000000000021', 'active');

set local role authenticated;
set local request.jwt.claim.sub = '00000001-0000-0000-0000-000000000041';

select set_eq(
  $$ select slug from properties $$,
  ARRAY['a1'],
  'a user with a membership on property A1 only sees A1, never B1 from another organization'
);

select * from finish();
rollback;
