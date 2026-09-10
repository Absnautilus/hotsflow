-- The Team page's "Rimuovi" action archives a direct, property-scoped
-- membership via archive_team_member() rather than deleting it -- the row
-- (and everything referencing it: job title, historical stays/requests,
-- audit log entries) stays intact, just hidden from the roster and moved
-- to 'suspended'. Mirrors memberships_update's own restrictions
-- (core.staff.manage on the row's property/organization, never your own
-- row) plus one more: an org-wide membership (property_id null) can't be
-- archived this way, since it reaches every property in the organization
-- and archiving it from a single property's Team page would deactivate
-- that person everywhere -- an organization-level decision, out of scope
-- here.
begin;
create extension if not exists pgtap;
select plan(6);

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

select lives_ok(
  $$ select archive_team_member('00000039-0000-0000-0000-000000000052') $$,
  'a property admin can archive a direct membership on their own property'
);
select ok(
  (select archived_at is not null and status = 'suspended' from memberships where id = '00000039-0000-0000-0000-000000000052'),
  'the archived membership is hidden and suspended, not deleted'
);

select throws_ok(
  $$ select archive_team_member('00000039-0000-0000-0000-000000000051') $$,
  '42501', 'cannot_archive_self',
  'a property admin cannot archive their own membership'
);

select throws_ok(
  $$ select archive_team_member('00000039-0000-0000-0000-000000000054') $$,
  '42501', 'cannot_archive_org_wide_membership',
  'an org-wide membership cannot be archived from a single property''s Team page'
);

select throws_ok(
  $$ select archive_team_member('00000039-0000-0000-0000-000000000053') $$,
  '42501', 'archive_not_allowed',
  'a property admin on Property A cannot archive a membership on unrelated Property B'
);

set local request.jwt.claim.sub = '00000039-0000-0000-0000-000000000045';
select throws_ok(
  $$ select archive_team_member('00000039-0000-0000-0000-000000000051') $$,
  '42501', 'archive_not_allowed',
  'a receptionist without core.staff.manage cannot archive another membership'
);

select * from finish();
rollback;
