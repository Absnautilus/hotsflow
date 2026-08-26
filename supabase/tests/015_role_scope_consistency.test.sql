-- H: role.scope must match which column the membership itself has set —
-- an organization-scoped role on a property-scoped membership fails, and
-- vice versa. Enforced by the trigger from migration 0008.
begin;
create extension if not exists pgtap;
select plan(2);

insert into organizations (id, name, slug) values
  ('00000015-0000-0000-0000-000000000001', 'Test Org', 'test-015-org');
insert into properties (id, organization_id, name, slug) values
  ('00000015-0000-0000-0000-000000000011', '00000015-0000-0000-0000-000000000001', 'Property A1', 'a1');

insert into auth.users (id) values ('00000015-0000-0000-0000-000000000041');
insert into profiles (id, full_name) values ('00000015-0000-0000-0000-000000000041', 'Test User');

-- organization_admin (scope='organization') on a property-scoped membership
select throws_ok(
  $$
    insert into memberships (profile_id, property_id, role_id, status)
    select '00000015-0000-0000-0000-000000000041', '00000015-0000-0000-0000-000000000011', id, 'active'
    from roles where slug = 'organization_admin'
  $$,
  '23514',
  null,
  'an organization-scoped role cannot be assigned to a property-scoped membership'
);

-- receptionist (scope='property') on an organization-scoped membership
select throws_ok(
  $$
    insert into memberships (profile_id, organization_id, role_id, status)
    select '00000015-0000-0000-0000-000000000041', '00000015-0000-0000-0000-000000000001', id, 'active'
    from roles where slug = 'receptionist'
  $$,
  '23514',
  null,
  'a property-scoped role cannot be assigned to an organization-scoped membership'
);

select * from finish();
rollback;
