begin;
create extension if not exists pgtap;
select plan(12);

insert into organizations (id, name, slug) values
  ('00000035-0000-0000-0000-000000000001', 'Team Org A', 'test-035-org-a'),
  ('00000035-0000-0000-0000-000000000002', 'Team Org B', 'test-035-org-b');
insert into properties (id, organization_id, name, slug) values
  ('00000035-0000-0000-0000-000000000011', '00000035-0000-0000-0000-000000000001', 'Team Property A1', 'team-035-a1'),
  ('00000035-0000-0000-0000-000000000012', '00000035-0000-0000-0000-000000000001', 'Team Property A2', 'team-035-a2'),
  ('00000035-0000-0000-0000-000000000013', '00000035-0000-0000-0000-000000000002', 'Team Property B1', 'team-035-b1');

insert into auth.users (id) values
  ('00000035-0000-0000-0000-000000000041'),
  ('00000035-0000-0000-0000-000000000042'),
  ('00000035-0000-0000-0000-000000000043'),
  ('00000035-0000-0000-0000-000000000044'),
  ('00000035-0000-0000-0000-000000000045'),
  ('00000035-0000-0000-0000-000000000046');
insert into profiles (id, full_name) values
  ('00000035-0000-0000-0000-000000000041', 'Property A1 Admin'),
  ('00000035-0000-0000-0000-000000000042', 'Property A1 Receptionist'),
  ('00000035-0000-0000-0000-000000000043', 'Property A1 Peer'),
  ('00000035-0000-0000-0000-000000000044', 'Org A Admin'),
  ('00000035-0000-0000-0000-000000000045', 'Property A2 Member'),
  ('00000035-0000-0000-0000-000000000046', 'Org B Admin');

insert into memberships (profile_id, property_id, organization_id, role_id, status)
select v.profile_id, v.property_id, v.organization_id, r.id, 'active'
from (values
  ('00000035-0000-0000-0000-000000000041'::uuid, '00000035-0000-0000-0000-000000000011'::uuid, null::uuid, 'property_admin'),
  ('00000035-0000-0000-0000-000000000042'::uuid, '00000035-0000-0000-0000-000000000011'::uuid, null::uuid, 'receptionist'),
  ('00000035-0000-0000-0000-000000000043'::uuid, '00000035-0000-0000-0000-000000000011'::uuid, null::uuid, 'receptionist'),
  ('00000035-0000-0000-0000-000000000044'::uuid, null::uuid, '00000035-0000-0000-0000-000000000001'::uuid, 'organization_admin'),
  ('00000035-0000-0000-0000-000000000045'::uuid, '00000035-0000-0000-0000-000000000012'::uuid, null::uuid, 'receptionist'),
  ('00000035-0000-0000-0000-000000000046'::uuid, null::uuid, '00000035-0000-0000-0000-000000000002'::uuid, 'organization_admin')
) as v(profile_id, property_id, organization_id, role_slug)
join roles r on r.slug = v.role_slug;

set local role authenticated;
set local request.jwt.claim.sub = '00000035-0000-0000-0000-000000000042';

select is(
  (select count(*)::int from memberships where property_id = '00000035-0000-0000-0000-000000000011'),
  3,
  'read-only staff sees the full roster of their property'
);
select is(
  (select count(*)::int from memberships where organization_id = '00000035-0000-0000-0000-000000000001'),
  1,
  'read-only staff sees an organization-wide membership covering their property'
);
select is(
  (select count(*)::int from memberships where property_id = '00000035-0000-0000-0000-000000000012'),
  0,
  'property-scoped staff cannot see direct memberships from another property in the same organization'
);
select is(
  (select count(*)::int from memberships where organization_id = '00000035-0000-0000-0000-000000000002'),
  0,
  'property-scoped staff cannot see memberships from another organization'
);

update memberships set status = 'suspended'
where profile_id = '00000035-0000-0000-0000-000000000043';
select is(
  (select status from memberships where profile_id = '00000035-0000-0000-0000-000000000043'),
  'active',
  'roster read access does not let staff suspend a peer'
);
select throws_ok(
  $$ insert into memberships (profile_id, property_id, role_id, status)
     select '00000035-0000-0000-0000-000000000042', '00000035-0000-0000-0000-000000000011', id, 'active'
     from roles where slug = 'property_admin' $$,
  '42501', null,
  'roster read access does not let staff self-assign a role'
);

reset role;
insert into property_job_titles (id, property_id, name) values
  ('00000035-0000-0000-0000-000000000061', '00000035-0000-0000-0000-000000000011', 'Reception');

set local role authenticated;
set local request.jwt.claim.sub = '00000035-0000-0000-0000-000000000041';

insert into property_staff_details (property_id, profile_id, job_title_id, employment_status, created_by) values
  ('00000035-0000-0000-0000-000000000011', '00000035-0000-0000-0000-000000000041', '00000035-0000-0000-0000-000000000061', 'inactive', '00000035-0000-0000-0000-000000000041'),
  ('00000035-0000-0000-0000-000000000011', '00000035-0000-0000-0000-000000000043', '00000035-0000-0000-0000-000000000061', 'inactive', '00000035-0000-0000-0000-000000000041');
select is(
  (select job_title_id from property_staff_details where profile_id = '00000035-0000-0000-0000-000000000041'),
  '00000035-0000-0000-0000-000000000061'::uuid,
  'property admin really assigns operational metadata to themselves'
);
select is(
  (select employment_status from property_staff_details where profile_id = '00000035-0000-0000-0000-000000000043'),
  'inactive',
  'property admin really assigns operational metadata to another member'
);

update property_staff_details set employment_status = 'active'
where property_id = '00000035-0000-0000-0000-000000000011'
  and profile_id = '00000035-0000-0000-0000-000000000041';
update property_staff_details set employment_status = 'active'
where property_id = '00000035-0000-0000-0000-000000000011'
  and profile_id = '00000035-0000-0000-0000-000000000043';
select is(
  (select employment_status from property_staff_details where profile_id = '00000035-0000-0000-0000-000000000041'),
  'active',
  'property admin can really update their own operational metadata'
);
select is(
  (select employment_status from property_staff_details where profile_id = '00000035-0000-0000-0000-000000000043'),
  'active',
  'property admin can really update another member operational metadata'
);

update memberships set status = 'suspended'
where profile_id = '00000035-0000-0000-0000-000000000041';
select is(
  (select status from memberships where profile_id = '00000035-0000-0000-0000-000000000041'),
  'active',
  'property admin still cannot suspend their own software access'
);
select throws_ok(
  $$ select assign_membership_role(
       (select id from memberships where profile_id = '00000035-0000-0000-0000-000000000041'),
       (select id from roles where slug = 'receptionist')
     ) $$,
  '42501', null,
  'property admin still cannot change their own software role'
);

select * from finish();
rollback;
