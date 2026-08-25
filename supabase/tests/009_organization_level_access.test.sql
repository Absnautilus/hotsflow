-- An org-wide membership (organization_id set, property_id null) grants
-- access to every property under that organization, with no per-property
-- membership row, and its role's permissions apply the same way.
begin;
create extension if not exists pgtap;
select plan(2);

insert into organizations (id, name, slug) values
  ('00000009-0000-0000-0000-000000000001', 'Test Org A', 'test-009-org-a');

insert into properties (id, organization_id, name, slug) values
  ('00000009-0000-0000-0000-000000000011', '00000009-0000-0000-0000-000000000001', 'Property A1', 'a1'),
  ('00000009-0000-0000-0000-000000000012', '00000009-0000-0000-0000-000000000001', 'Property A2', 'a2');

insert into roles (id, slug, display_name, scope) values
  ('00000009-0000-0000-0000-000000000021', 'test_009_org_admin', 'Organization Admin', 'organization');

-- Grants the real 'core.property.manage' permission seed.sql ships (looked
-- up by slug, not duplicated — see 003's own comment on why: the
-- properties_update RLS policy hardcodes this exact slug).
insert into role_permissions (role_id, permission_id)
select '00000009-0000-0000-0000-000000000021', id from permissions where slug = 'core.property.manage';

insert into auth.users (id) values ('00000009-0000-0000-0000-000000000041');
insert into profiles (id, full_name) values ('00000009-0000-0000-0000-000000000041', 'Org Admin User');

-- organization-wide membership: property_id is null, organization_id is set
insert into memberships (profile_id, organization_id, role_id, status) values
  ('00000009-0000-0000-0000-000000000041', '00000009-0000-0000-0000-000000000001', '00000009-0000-0000-0000-000000000021', 'active');

set local role authenticated;
set local request.jwt.claim.sub = '00000009-0000-0000-0000-000000000041';

select set_eq(
  $$ select slug from properties $$,
  ARRAY['a1', 'a2'],
  'an org-wide membership sees every property under the organization without a per-property row'
);

update properties set name = 'Renamed by org admin' where id = '00000009-0000-0000-0000-000000000012';
select is(
  (select count(*)::int from properties where id = '00000009-0000-0000-0000-000000000012' and name = 'Renamed by org admin'),
  1,
  'the org-wide membership''s role_permissions apply to a specific property too, via has_permission'
);

select * from finish();
rollback;
