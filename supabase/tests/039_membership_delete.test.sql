-- The Team page's "remove" action deletes a direct, property-scoped
-- membership. Mirrors memberships_update's own restrictions (core.staff.
-- manage on the row's property/organization, never your own row) plus one
-- more: an org-wide membership (property_id null) can't be deleted this
-- way, since it reaches every property in the organization and removing it
-- from a single property's Team page would deactivate that person
-- everywhere -- an organization-level decision, out of scope here.
begin;
create extension if not exists pgtap;
select plan(5);

insert into organizations (id, name, slug) values
  ('00000039-0000-0000-0000-000000000001', 'Test Org A', 'test-039-org-a'),
  ('00000039-0000-0000-0000-000000000002', 'Test Org B', 'test-039-org-b');
insert into properties (id, organization_id, name, slug) values
  ('00000039-0000-0000-0000-000000000011', '00000039-0000-0000-0000-000000000001', 'Property A', 'a1'),
  ('00000039-0000-0000-0000-000000000012', '00000039-0000-0000-0000-000000000002', 'Property B', 'b1');

insert into auth.users (id) values
  ('00000039-0000-0000-0000-000000000041'),
  ('00000039-0000-0000-0000-000000000042'),
  ('00000039-0000-0000-0000-000000000043'),
  ('00000039-0000-0000-0000-000000000044'),
  ('00000039-0000-0000-0000-000000000045');
insert into profiles (id, full_name) values
  ('00000039-0000-0000-0000-000000000041', 'Property A Admin'),
  ('00000039-0000-0000-0000-000000000042', 'Property A Receptionist'),
  ('00000039-0000-0000-0000-000000000043', 'Property B Admin'),
  ('00000039-0000-0000-0000-000000000044', 'Org-wide Admin'),
  ('00000039-0000-0000-0000-000000000045', 'Property A Receptionist Two');

insert into memberships (id, profile_id, property_id, role_id, status)
select v.membership_id, v.profile_id, v.property_id, r.id, 'active'
from (values
  ('00000039-0000-0000-0000-000000000051'::uuid, '00000039-0000-0000-0000-000000000041'::uuid, '00000039-0000-0000-0000-000000000011'::uuid, 'property_admin'),
  ('00000039-0000-0000-0000-000000000052'::uuid, '00000039-0000-0000-0000-000000000042'::uuid, '00000039-0000-0000-0000-000000000011'::uuid, 'receptionist'),
  ('00000039-0000-0000-0000-000000000053'::uuid, '00000039-0000-0000-0000-000000000043'::uuid, '00000039-0000-0000-0000-000000000012'::uuid, 'property_admin'),
  ('00000039-0000-0000-0000-000000000055'::uuid, '00000039-0000-0000-0000-000000000045'::uuid, '00000039-0000-0000-0000-000000000011'::uuid, 'receptionist')
) as v(membership_id, profile_id, property_id, role_slug)
join roles r on r.slug = v.role_slug;

-- org-wide membership: property_id is null, organization_id is set
insert into memberships (id, profile_id, organization_id, role_id, status)
select '00000039-0000-0000-0000-000000000054', '00000039-0000-0000-0000-000000000044', '00000039-0000-0000-0000-000000000001', id, 'active'
from roles where slug = 'organization_admin';

set local role authenticated;
set local request.jwt.claim.sub = '00000039-0000-0000-0000-000000000041';

delete from memberships where id = '00000039-0000-0000-0000-000000000052';
select is(
  (select count(*)::int from memberships where id = '00000039-0000-0000-0000-000000000052'),
  0,
  'a property admin can remove a direct membership on their own property'
);

delete from memberships where id = '00000039-0000-0000-0000-000000000051';
select is(
  (select count(*)::int from memberships where id = '00000039-0000-0000-0000-000000000051'),
  1,
  'a property admin cannot remove their own membership'
);

delete from memberships where id = '00000039-0000-0000-0000-000000000054';
select is(
  (select count(*)::int from memberships where id = '00000039-0000-0000-0000-000000000054'),
  1,
  'an org-wide membership cannot be removed from a single property''s Team page'
);

delete from memberships where id = '00000039-0000-0000-0000-000000000053';
select is(
  (select count(*)::int from memberships where id = '00000039-0000-0000-0000-000000000053'),
  1,
  'a property admin on Property A cannot remove a membership on unrelated Property B'
);

set local request.jwt.claim.sub = '00000039-0000-0000-0000-000000000045';
delete from memberships where id = '00000039-0000-0000-0000-000000000051';
select is(
  (select count(*)::int from memberships where id = '00000039-0000-0000-0000-000000000051'),
  1,
  'a receptionist without core.staff.manage cannot remove another membership'
);

select * from finish();
rollback;
