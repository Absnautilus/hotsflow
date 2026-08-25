-- A suspended membership grants no access at all, even though the row
-- itself still exists.
begin;
create extension if not exists pgtap;
select plan(1);

insert into organizations (id, name, slug) values
  ('00000005-0000-0000-0000-000000000001', 'Test Org A', 'test-005-org-a');

insert into properties (id, organization_id, name, slug) values
  ('00000005-0000-0000-0000-000000000011', '00000005-0000-0000-0000-000000000001', 'Property A1', 'a1');

insert into roles (id, slug, display_name, scope) values
  ('00000005-0000-0000-0000-000000000021', 'test_005_role', 'Test Role', 'property');

insert into auth.users (id) values ('00000005-0000-0000-0000-000000000041');
insert into profiles (id, full_name) values ('00000005-0000-0000-0000-000000000041', 'Suspended User');
insert into memberships (profile_id, property_id, role_id, status) values
  ('00000005-0000-0000-0000-000000000041', '00000005-0000-0000-0000-000000000011', '00000005-0000-0000-0000-000000000021', 'suspended');

set local role authenticated;
set local request.jwt.claim.sub = '00000005-0000-0000-0000-000000000041';

select is(
  (select count(*)::int from properties),
  0,
  'a suspended membership grants no visibility into its property'
);

select * from finish();
rollback;
