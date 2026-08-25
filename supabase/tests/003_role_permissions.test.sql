-- A receptionist (no core.property.manage) cannot update a property.
-- A property admin (has core.property.manage) can.
begin;
create extension if not exists pgtap;
select plan(2);

insert into organizations (id, name, slug) values
  ('00000003-0000-0000-0000-000000000001', 'Test Org A', 'test-003-org-a');

insert into properties (id, organization_id, name, slug) values
  ('00000003-0000-0000-0000-000000000011', '00000003-0000-0000-0000-000000000001', 'Property A1', 'a1');

insert into roles (id, slug, display_name, scope) values
  ('00000003-0000-0000-0000-000000000021', 'test_003_receptionist', 'Receptionist', 'property'),
  ('00000003-0000-0000-0000-000000000022', 'test_003_property_admin', 'Property Admin', 'property');

-- The properties_update RLS policy (migration 0007) hardcodes the real
-- 'core.property.manage' slug, so this test grants that exact permission
-- rather than inventing a test-scoped one — looked up by slug, not by
-- seed.sql's id, so this doesn't care exactly how seed.sql built it.
-- Only property_admin gets the grant; receptionist gets nothing.
insert into role_permissions (role_id, permission_id)
select '00000003-0000-0000-0000-000000000022', id from permissions where slug = 'core.property.manage';

insert into auth.users (id) values
  ('00000003-0000-0000-0000-000000000041'),
  ('00000003-0000-0000-0000-000000000042');
insert into profiles (id, full_name) values
  ('00000003-0000-0000-0000-000000000041', 'Receptionist User'),
  ('00000003-0000-0000-0000-000000000042', 'Property Admin User');

insert into memberships (profile_id, property_id, role_id, status) values
  ('00000003-0000-0000-0000-000000000041', '00000003-0000-0000-0000-000000000011', '00000003-0000-0000-0000-000000000021', 'active'),
  ('00000003-0000-0000-0000-000000000042', '00000003-0000-0000-0000-000000000011', '00000003-0000-0000-0000-000000000022', 'active');

set local role authenticated;
set local request.jwt.claim.sub = '00000003-0000-0000-0000-000000000041';

update properties set name = 'Hacked' where id = '00000003-0000-0000-0000-000000000011';
select is(
  (select count(*)::int from properties where id = '00000003-0000-0000-0000-000000000011' and name = 'Hacked'),
  0,
  'a receptionist without core.property.manage cannot update the property'
);

set local request.jwt.claim.sub = '00000003-0000-0000-0000-000000000042';

update properties set name = 'Renamed by admin' where id = '00000003-0000-0000-0000-000000000011';
select is(
  (select count(*)::int from properties where id = '00000003-0000-0000-0000-000000000011' and name = 'Renamed by admin'),
  1,
  'a property admin with core.property.manage can update the property'
);

select * from finish();
rollback;
