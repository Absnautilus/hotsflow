-- G: staff on one property don't see the profile of unrelated staff on a
-- completely different property/organization — and still see their own.
begin;
create extension if not exists pgtap;
select plan(2);

insert into organizations (id, name, slug) values
  ('00000014-0000-0000-0000-000000000001', 'Test Org A', 'test-014-org-a'),
  ('00000014-0000-0000-0000-000000000002', 'Test Org B', 'test-014-org-b');
insert into properties (id, organization_id, name, slug) values
  ('00000014-0000-0000-0000-000000000011', '00000014-0000-0000-0000-000000000001', 'Property A', 'a1'),
  ('00000014-0000-0000-0000-000000000012', '00000014-0000-0000-0000-000000000002', 'Property B', 'b1');

insert into auth.users (id) values
  ('00000014-0000-0000-0000-000000000041'),
  ('00000014-0000-0000-0000-000000000042');
insert into profiles (id, full_name) values
  ('00000014-0000-0000-0000-000000000041', 'Staff on Property A'),
  ('00000014-0000-0000-0000-000000000042', 'Unrelated staff on Property B');

insert into memberships (profile_id, property_id, role_id, status)
select '00000014-0000-0000-0000-000000000041', '00000014-0000-0000-0000-000000000011', id, 'active'
from roles where slug = 'receptionist';
insert into memberships (profile_id, property_id, role_id, status)
select '00000014-0000-0000-0000-000000000042', '00000014-0000-0000-0000-000000000012', id, 'active'
from roles where slug = 'receptionist';

set local role authenticated;
set local request.jwt.claim.sub = '00000014-0000-0000-0000-000000000041';

select is(
  (select count(*)::int from profiles where id = '00000014-0000-0000-0000-000000000041'),
  1,
  'staff can always see their own profile'
);

select is(
  (select count(*)::int from profiles where id = '00000014-0000-0000-0000-000000000042'),
  0,
  'staff cannot see the profile of unrelated staff on a different property/organization'
);

select * from finish();
rollback;
