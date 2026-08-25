-- property_modules correctly reports which modules are switched on for a
-- given property, independent of any staff permission.
begin;
create extension if not exists pgtap;
select plan(2);

insert into organizations (id, name, slug) values
  ('00000004-0000-0000-0000-000000000001', 'Test Org A', 'test-004-org-a');

insert into properties (id, organization_id, name, slug) values
  ('00000004-0000-0000-0000-000000000011', '00000004-0000-0000-0000-000000000001', 'Property A1', 'a1');

-- Test-scoped slugs, not the real 'guest_requests'/'transfers' seed.sql
-- ships — modules.slug is globally unique and seed data is present
-- whenever this runs as part of the real `supabase test db` flow. Safe to
-- rename here (unlike 003/009's permission slug): has_module() takes the
-- slug as a plain argument, nothing hardcodes these two specifically.
insert into modules (id, slug, display_name) values
  ('00000004-0000-0000-0000-000000000051', 'test_004_guest_requests', 'Guest Requests'),
  ('00000004-0000-0000-0000-000000000052', 'test_004_transfers', 'Transfers');

insert into property_modules (property_id, module_id, enabled) values
  ('00000004-0000-0000-0000-000000000011', '00000004-0000-0000-0000-000000000051', true),
  ('00000004-0000-0000-0000-000000000011', '00000004-0000-0000-0000-000000000052', false);

insert into roles (id, slug, display_name, scope) values
  ('00000004-0000-0000-0000-000000000021', 'test_004_role', 'Test Role', 'property');
insert into auth.users (id) values ('00000004-0000-0000-0000-000000000041');
insert into profiles (id, full_name) values ('00000004-0000-0000-0000-000000000041', 'User A1');
insert into memberships (profile_id, property_id, role_id, status) values
  ('00000004-0000-0000-0000-000000000041', '00000004-0000-0000-0000-000000000011', '00000004-0000-0000-0000-000000000021', 'active');

set local role authenticated;
set local request.jwt.claim.sub = '00000004-0000-0000-0000-000000000041';

select ok(
  has_module('00000004-0000-0000-0000-000000000011', 'test_004_guest_requests'),
  'guest_requests is enabled for property A1'
);
select ok(
  not has_module('00000004-0000-0000-0000-000000000011', 'test_004_transfers'),
  'transfers is disabled for property A1'
);

select * from finish();
rollback;
