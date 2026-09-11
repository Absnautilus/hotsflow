-- guest_requests_staff_access_status: the read-only companion to
-- grant-housekeeping-access, letting the Team UI show a member's current
-- Housekeeping access before rendering a toggle.
begin;
create extension if not exists pgtap;
select plan(4);

insert into organizations (id, name, slug) values
  ('00000042-0000-0000-0000-000000000001', 'Status Org', 'test-042-org');
insert into properties (id, organization_id, name, slug) values
  ('00000042-0000-0000-0000-000000000002', '00000042-0000-0000-0000-000000000001', 'Status Property', 'test-042-prop');
insert into auth.users (id) values
  ('00000042-0000-0000-0000-000000000003'),
  ('00000042-0000-0000-0000-000000000007');
insert into profiles (id, full_name) values
  ('00000042-0000-0000-0000-000000000003', 'Status Admin'),
  ('00000042-0000-0000-0000-000000000007', 'Status Staff');
insert into memberships (id, profile_id, property_id, role_id, status) values
  ('00000042-0000-0000-0000-000000000005', '00000042-0000-0000-0000-000000000003', '00000042-0000-0000-0000-000000000002', (select id from roles where slug = 'property_admin'), 'active'),
  ('00000042-0000-0000-0000-000000000008', '00000042-0000-0000-0000-000000000007', '00000042-0000-0000-0000-000000000002', (select id from roles where slug = 'receptionist'), 'active');
insert into property_modules (property_id, module_id, enabled)
select '00000042-0000-0000-0000-000000000002', id, true from modules where slug = 'guest_requests';
insert into hotels (id, name, timezone, active) values
  ('00000042-0000-0000-0000-000000000006', 'Status Legacy Hotel', 'Europe/Rome', true);
insert into legacy_property_mapping (platform_property_id, legacy_hotel_id) values
  ('00000042-0000-0000-0000-000000000002', '00000042-0000-0000-0000-000000000006');

-- staff_profiles has no direct grant to `authenticated` (only reachable
-- via the SECURITY DEFINER Edge Function / this function in real usage),
-- so every fixture write below runs as the unrestricted test role;
-- only the guest_requests_staff_access_status() calls themselves run as
-- `authenticated`, matching how the real RPC is actually invoked.

set local role authenticated;
set local request.jwt.claim.sub = '00000042-0000-0000-0000-000000000003';

select is(
  guest_requests_staff_access_status('00000042-0000-0000-0000-000000000008'),
  false,
  'no staff_profiles row yet -- status is false, not null or an error'
);

reset role;
insert into staff_profiles (hotel_id, auth_user_id, name, role, active) values
  ('00000042-0000-0000-0000-000000000006', '00000042-0000-0000-0000-000000000007', 'Status Staff', 'admin', true);
set local role authenticated;
set local request.jwt.claim.sub = '00000042-0000-0000-0000-000000000003';

select is(
  guest_requests_staff_access_status('00000042-0000-0000-0000-000000000008'),
  true,
  'active staff_profiles row at the property''s mapped hotel -- status is true'
);

reset role;
update staff_profiles set active = false where auth_user_id = '00000042-0000-0000-0000-000000000007';
set local role authenticated;
set local request.jwt.claim.sub = '00000042-0000-0000-0000-000000000003';

select is(
  guest_requests_staff_access_status('00000042-0000-0000-0000-000000000008'),
  false,
  'deactivated staff_profiles row -- status is false again'
);

reset role;
update staff_profiles set active = true where auth_user_id = '00000042-0000-0000-0000-000000000007';
set local role authenticated;
set local request.jwt.claim.sub = '00000042-0000-0000-0000-000000000007';

select is(
  guest_requests_staff_access_status('00000042-0000-0000-0000-000000000008'),
  false,
  'the staff member themselves, without core.staff.manage, sees false even though a real active row exists'
);

reset role;

select * from finish();
rollback;
