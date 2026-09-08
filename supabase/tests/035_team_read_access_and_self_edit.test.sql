begin;
create extension if not exists pgtap;
select plan(8);

insert into organizations (id, name, slug) values
  ('00000035-0000-0000-0000-000000000001', 'Team Org A', 'test-035-org-a');
insert into properties (id, organization_id, name, slug) values
  ('00000035-0000-0000-0000-000000000011', '00000035-0000-0000-0000-000000000001', 'Team Property A', 'team-035-a');

insert into auth.users (id) values
  ('00000035-0000-0000-0000-000000000041'),
  ('00000035-0000-0000-0000-000000000042'),
  ('00000035-0000-0000-0000-000000000043');
insert into profiles (id, full_name) values
  ('00000035-0000-0000-0000-000000000041', 'Property Admin'),
  ('00000035-0000-0000-0000-000000000042', 'Receptionist'),
  ('00000035-0000-0000-0000-000000000043', 'Housekeeper');
insert into memberships (profile_id, property_id, role_id, status)
select v.profile_id, v.property_id, r.id, 'active'
from (values
  ('00000035-0000-0000-0000-000000000041'::uuid, '00000035-0000-0000-0000-000000000011'::uuid, 'property_admin'),
  ('00000035-0000-0000-0000-000000000042'::uuid, '00000035-0000-0000-0000-000000000011'::uuid, 'receptionist'),
  ('00000035-0000-0000-0000-000000000043'::uuid, '00000035-0000-0000-0000-000000000011'::uuid, 'receptionist')
) as v(profile_id, property_id, role_slug)
join roles r on r.slug = v.role_slug;

-- ---------------------------------------------------------------------------
-- Fix 1: read-only Team access for staff without core.staff.manage
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '00000035-0000-0000-0000-000000000042';

select is(
  (select count(*)::int from memberships where property_id = '00000035-0000-0000-0000-000000000011'),
  3,
  'a receptionist without core.staff.manage can read the full property roster, not just their own row'
);
-- A silent no-op, not a thrown error: memberships_update's USING clause
-- excludes every row for this caller (no core.staff.manage), so the row is
-- simply not visible for update -- same non-throwing shape as the existing
-- 034 test's self-employment-status check below.
update memberships set status = 'suspended'
where profile_id = '00000035-0000-0000-0000-000000000043';
select is(
  (select status from memberships where profile_id = '00000035-0000-0000-0000-000000000043'),
  'active',
  'read access does not imply write access: same receptionist still cannot suspend a peer'
);
select throws_ok(
  $$ insert into memberships (profile_id, property_id, role_id, status)
     select '00000035-0000-0000-0000-000000000042', '00000035-0000-0000-0000-000000000011', id, 'active'
     from roles where slug = 'property_admin' $$,
  '42501', null,
  'and still cannot grant themselves a new membership/role'
);

reset role;

-- ---------------------------------------------------------------------------
-- Fix 2: property_staff_details self-edit guard
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '00000035-0000-0000-0000-000000000041';

select lives_ok(
  $$ insert into property_staff_details (property_id, profile_id, employment_status, created_by) values
     ('00000035-0000-0000-0000-000000000011', '00000035-0000-0000-0000-000000000042', 'active', '00000035-0000-0000-0000-000000000041') $$,
  'property admin can create staff details for someone else'
);
select throws_ok(
  $$ insert into property_staff_details (property_id, profile_id, employment_status, created_by) values
     ('00000035-0000-0000-0000-000000000011', '00000035-0000-0000-0000-000000000041', 'active', '00000035-0000-0000-0000-000000000041') $$,
  '42501', null,
  'property admin cannot create their own staff details row'
);

reset role;
insert into property_staff_details (property_id, profile_id, employment_status, created_by) values
  ('00000035-0000-0000-0000-000000000011', '00000035-0000-0000-0000-000000000041', 'active', null);

set local role authenticated;
set local request.jwt.claim.sub = '00000035-0000-0000-0000-000000000041';

select lives_ok(
  $$ update property_staff_details set employment_status = 'inactive'
     where profile_id = '00000035-0000-0000-0000-000000000042' $$,
  'property admin can change someone else''s employment status'
);
update property_staff_details set employment_status = 'inactive'
where profile_id = '00000035-0000-0000-0000-000000000041';
select is(
  (select employment_status from property_staff_details where profile_id = '00000035-0000-0000-0000-000000000041'),
  'active',
  'the same property admin cannot flip their own employment status back to active'
);

reset role;
insert into property_job_titles (id, property_id, name) values
  ('00000035-0000-0000-0000-000000000061', '00000035-0000-0000-0000-000000000011', 'Reception');

set local role authenticated;
set local request.jwt.claim.sub = '00000035-0000-0000-0000-000000000041';
update property_staff_details set job_title_id = '00000035-0000-0000-0000-000000000061'
where profile_id = '00000035-0000-0000-0000-000000000041';
select is(
  (select job_title_id from property_staff_details where profile_id = '00000035-0000-0000-0000-000000000041'),
  null,
  'nor assign themselves a job title'
);

select * from finish();
rollback;
