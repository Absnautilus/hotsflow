-- Fase 2 Step 7 — COMPATIBILITY GATE.
-- The dual gate decided for Step 6 (memberships.status='active' AND
-- staff_profiles.active=true, both required) exercised in all 4
-- combinations, on the same profile so only the gate values differ.
begin;
create extension if not exists pgtap;
select plan(5);

insert into hotels (id, name, timezone, active) values
  ('00000025-0000-0000-0000-00000000ff01', 'Hotel Uno', 'Europe/Rome', true);
select backfill_legacy_property_mapping();
select backfill_guest_requests_entitlement();

insert into auth.users (id) values ('00000025-0000-0000-0000-000000000a01');
insert into staff_profiles (id, hotel_id, auth_user_id, name, role, department, active, login_username) values
  ('00000025-0000-0000-0000-000000000101', '00000025-0000-0000-0000-00000000ff01', '00000025-0000-0000-0000-000000000a01', 'PA Uno', 'admin', null, true, null);
select backfill_staff_identity();

-- control case: both active -> access granted
set local role authenticated;
set local request.jwt.claim.sub = '00000025-0000-0000-0000-000000000a01';
select is(current_staff_hotel(), '00000025-0000-0000-0000-00000000ff01'::uuid,
  'control: membership active AND staff_profiles.active=true -> access granted'
);
reset role;

-- membership suspended, staff_profiles.active=true -> denied
update memberships set status = 'suspended' where profile_id = '00000025-0000-0000-0000-000000000a01';
set local role authenticated;
set local request.jwt.claim.sub = '00000025-0000-0000-0000-000000000a01';
select is(current_staff_hotel(), null,
  'membership suspended, staff_profiles.active=true -> denied (core gate alone is enough to block)'
);
reset role;
update memberships set status = 'active' where profile_id = '00000025-0000-0000-0000-000000000a01';

-- membership active, staff_profiles.active=false -> denied
update staff_profiles set active = false where id = '00000025-0000-0000-0000-000000000101';
set local role authenticated;
set local request.jwt.claim.sub = '00000025-0000-0000-0000-000000000a01';
select is(current_staff_hotel(), null,
  'membership active, staff_profiles.active=false -> denied (legacy gate alone is enough to block, as decided)'
);
reset role;

-- both inactive -> denied
update memberships set status = 'suspended' where profile_id = '00000025-0000-0000-0000-000000000a01';
set local role authenticated;
set local request.jwt.claim.sub = '00000025-0000-0000-0000-000000000a01';
select is(current_staff_hotel(), null, 'both membership suspended AND staff_profiles.active=false -> denied');
reset role;

-- restore both -> access granted again (proves the gate is live, not a
-- one-way latch, and that restoring both together works too)
update memberships set status = 'active' where profile_id = '00000025-0000-0000-0000-000000000a01';
update staff_profiles set active = true where id = '00000025-0000-0000-0000-000000000101';
set local role authenticated;
set local request.jwt.claim.sub = '00000025-0000-0000-0000-000000000a01';
select is(current_staff_hotel(), '00000025-0000-0000-0000-00000000ff01'::uuid,
  'restoring both membership.status=active and staff_profiles.active=true together -> access granted again'
);
reset role;

select * from finish();
rollback;
