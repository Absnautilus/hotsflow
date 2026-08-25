-- A staff member with memberships on two properties in the same
-- organization can access both.
begin;
create extension if not exists pgtap;
select plan(1);

insert into organizations (id, name, slug) values
  ('00000002-0000-0000-0000-000000000001', 'Test Org A', 'test-002-org-a');

insert into properties (id, organization_id, name, slug) values
  ('00000002-0000-0000-0000-000000000011', '00000002-0000-0000-0000-000000000001', 'Property A1', 'a1'),
  ('00000002-0000-0000-0000-000000000012', '00000002-0000-0000-0000-000000000001', 'Property A2', 'a2');

insert into roles (id, slug, display_name, scope) values
  ('00000002-0000-0000-0000-000000000021', 'test_002_role', 'Test Role', 'property');

insert into auth.users (id) values ('00000002-0000-0000-0000-000000000041');
insert into profiles (id, full_name) values ('00000002-0000-0000-0000-000000000041', 'User Multi');
insert into memberships (profile_id, property_id, role_id, status) values
  ('00000002-0000-0000-0000-000000000041', '00000002-0000-0000-0000-000000000011', '00000002-0000-0000-0000-000000000021', 'active'),
  ('00000002-0000-0000-0000-000000000041', '00000002-0000-0000-0000-000000000012', '00000002-0000-0000-0000-000000000021', 'active');

set local role authenticated;
set local request.jwt.claim.sub = '00000002-0000-0000-0000-000000000041';

select set_eq(
  $$ select slug from properties $$,
  ARRAY['a1', 'a2'],
  'a user with memberships on A1 and A2 sees both properties'
);

select * from finish();
rollback;
