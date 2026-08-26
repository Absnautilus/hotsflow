-- J: a property_admin — who does hold core.property.manage — still cannot
-- flip a property_modules.enabled flag. Entitlement is commercial, not a
-- staff-configurable setting (migration 0013).
begin;
create extension if not exists pgtap;
select plan(2);

insert into organizations (id, name, slug) values
  ('00000017-0000-0000-0000-000000000001', 'Test Org', 'test-017-org');
insert into properties (id, organization_id, name, slug) values
  ('00000017-0000-0000-0000-000000000011', '00000017-0000-0000-0000-000000000001', 'Property A1', 'a1');

insert into property_modules (id, property_id, module_id, enabled)
select '00000017-0000-0000-0000-000000000031', '00000017-0000-0000-0000-000000000011', id, false
from modules where slug = 'transfers';

insert into auth.users (id) values ('00000017-0000-0000-0000-000000000041');
insert into profiles (id, full_name) values ('00000017-0000-0000-0000-000000000041', 'Property Admin');
insert into memberships (profile_id, property_id, role_id, status)
select '00000017-0000-0000-0000-000000000041', '00000017-0000-0000-0000-000000000011', id, 'active'
from roles where slug = 'property_admin';

set local role authenticated;
set local request.jwt.claim.sub = '00000017-0000-0000-0000-000000000041';

-- The UPDATE grant itself was revoked in migration 0013 (not just the
-- policy) — this fails at the privilege check, before RLS is even
-- evaluated, so it's a hard error rather than a silent zero-row update.
select throws_ok(
  $$ update property_modules set enabled = true where id = '00000017-0000-0000-0000-000000000031' $$,
  '42501',
  null,
  'a property_admin cannot update property_modules at all — no grant exists'
);

select is(
  (select enabled from property_modules where id = '00000017-0000-0000-0000-000000000031'),
  false,
  'the row is unchanged'
);

select * from finish();
rollback;
