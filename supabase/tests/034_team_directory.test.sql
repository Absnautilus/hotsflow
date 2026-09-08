begin;
create extension if not exists pgtap;
select plan(13);

insert into organizations (id, name, slug) values
  ('00000034-0000-0000-0000-000000000001', 'Team Org A', 'test-034-org-a'),
  ('00000034-0000-0000-0000-000000000002', 'Team Org B', 'test-034-org-b');
insert into properties (id, organization_id, name, slug) values
  ('00000034-0000-0000-0000-000000000011', '00000034-0000-0000-0000-000000000001', 'Team Property A', 'team-a'),
  ('00000034-0000-0000-0000-000000000012', '00000034-0000-0000-0000-000000000002', 'Team Property B', 'team-b');

insert into auth.users (id) values
  ('00000034-0000-0000-0000-000000000041'),
  ('00000034-0000-0000-0000-000000000042'),
  ('00000034-0000-0000-0000-000000000043');
insert into profiles (id, full_name) values
  ('00000034-0000-0000-0000-000000000041', 'Property A Admin'),
  ('00000034-0000-0000-0000-000000000042', 'Property A Receptionist'),
  ('00000034-0000-0000-0000-000000000043', 'Property B Admin');
insert into memberships (profile_id, property_id, role_id, status)
select v.profile_id, v.property_id, r.id, 'active'
from (values
  ('00000034-0000-0000-0000-000000000041'::uuid, '00000034-0000-0000-0000-000000000011'::uuid, 'property_admin'),
  ('00000034-0000-0000-0000-000000000042'::uuid, '00000034-0000-0000-0000-000000000011'::uuid, 'receptionist'),
  ('00000034-0000-0000-0000-000000000043'::uuid, '00000034-0000-0000-0000-000000000012'::uuid, 'property_admin')
) as v(profile_id, property_id, role_slug)
join roles r on r.slug = v.role_slug;

select ok(
  (select relrowsecurity from pg_class where oid = 'property_job_titles'::regclass),
  'property_job_titles has RLS enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'property_staff_details'::regclass),
  'property_staff_details has RLS enabled'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000034-0000-0000-0000-000000000041';

select lives_ok(
  $$ insert into property_job_titles (id, property_id, name, created_by) values
     ('00000034-0000-0000-0000-000000000061', '00000034-0000-0000-0000-000000000011', 'Reception', '00000034-0000-0000-0000-000000000041') $$,
  'property admin can create a job title in their property'
);
select throws_ok(
  $$ insert into property_job_titles (property_id, name) values
     ('00000034-0000-0000-0000-000000000012', 'Cross-property title') $$,
  '42501', null,
  'property admin cannot create a job title in another property'
);
select lives_ok(
  $$ insert into property_staff_details (property_id, profile_id, job_title_id, created_by) values
     ('00000034-0000-0000-0000-000000000011', '00000034-0000-0000-0000-000000000042', '00000034-0000-0000-0000-000000000061', '00000034-0000-0000-0000-000000000041') $$,
  'property admin can assign an active property job title'
);
select throws_ok(
  $$ insert into property_staff_details (property_id, profile_id) values
     ('00000034-0000-0000-0000-000000000011', '00000034-0000-0000-0000-000000000043') $$,
  '23514', 'profile_not_member_of_property',
  'a profile from another hotel cannot be attached to this property directory'
);
select throws_ok(
  $$ update property_staff_details set property_id = '00000034-0000-0000-0000-000000000012'
     where profile_id = '00000034-0000-0000-0000-000000000042' $$,
  '42501', null,
  'property_id is protected by a column-level grant'
);

reset role;
insert into property_job_titles (id, property_id, name) values
  ('00000034-0000-0000-0000-000000000062', '00000034-0000-0000-0000-000000000012', 'Other Hotel Job');

set local role authenticated;
set local request.jwt.claim.sub = '00000034-0000-0000-0000-000000000042';

select is(
  (select count(*)::int from property_job_titles), 1,
  'staff sees titles only for their accessible property'
);
select is(
  (select name from property_job_titles), 'Reception',
  'the visible title belongs to the current property'
);
select is(
  (select job_title_id from property_staff_details where profile_id = auth.uid()),
  '00000034-0000-0000-0000-000000000061'::uuid,
  'staff can read their property-specific assignment'
);
select throws_ok(
  $$ insert into property_job_titles (property_id, name) values
     ('00000034-0000-0000-0000-000000000011', 'Unauthorized title') $$,
  '42501', null,
  'staff without core.staff.manage cannot create titles'
);
select throws_ok(
  $$ update property_staff_details set employment_status = 'inactive'
     where profile_id = '00000034-0000-0000-0000-000000000042' $$,
  '42501', null,
  'staff cannot change their own employment metadata'
);

reset role;
update property_job_titles set active = false where id = '00000034-0000-0000-0000-000000000061';

set local role authenticated;
set local request.jwt.claim.sub = '00000034-0000-0000-0000-000000000041';
select throws_ok(
  $$ update property_staff_details set job_title_id = '00000034-0000-0000-0000-000000000061'
     where profile_id = '00000034-0000-0000-0000-000000000042' $$,
  '23514', 'job_title_not_active_for_property',
  'an inactive title cannot be assigned'
);

select * from finish();
rollback;
