-- PR0 regression — an organization_admin must not inherit the legacy
-- master's former platform-wide SELECT bypass on `hotels`.
--
-- The legacy backfill intentionally gives an existing `master` one
-- organization_admin membership per organization. This fixture first runs
-- that real backfill, then narrows the user to Org A only to model the normal
-- post-migration platform case: an organization_admin who administers one
-- organization, while another unrelated organization also exists.

begin;
create extension if not exists pgtap;
select plan(4);

insert into hotels (id, name, timezone, active) values
  ('00000032-0000-0000-0000-00000000ff01', 'Hotel Org A', 'Europe/Rome', true),
  ('00000032-0000-0000-0000-00000000ff02', 'Hotel Org B', 'Europe/Rome', true);

select backfill_legacy_property_mapping();
select backfill_guest_requests_entitlement();

insert into auth.users (id) values
  ('00000032-0000-0000-0000-000000000a01');

insert into staff_profiles (
  id, hotel_id, auth_user_id, name, role, department, active, login_username
) values (
  '00000032-0000-0000-0000-000000000101',
  '00000032-0000-0000-0000-00000000ff01',
  '00000032-0000-0000-0000-000000000a01',
  'Org A Admin',
  'master',
  null,
  true,
  null
);

select backfill_staff_identity();

-- D2 gives a migrated legacy master organization_admin on every existing
-- organization. Narrow it to Org A only so this test represents a normal
-- organization-scoped admin in the target Core model.
delete from memberships
where profile_id = '00000032-0000-0000-0000-000000000a01'
  and organization_id <> (
    select p.organization_id
    from legacy_property_mapping m
    join properties p on p.id = m.platform_property_id
    where m.legacy_hotel_id = '00000032-0000-0000-0000-00000000ff01'
  );

set local role authenticated;
set local request.jwt.claim.sub = '00000032-0000-0000-0000-000000000a01';

select ok(
  current_staff_is_master(),
  'sanity: the caller is still an active Core-derived organization_admin after being narrowed to Org A'
);

select is(
  (select count(*)::int from hotels where id = '00000032-0000-0000-0000-00000000ff01'),
  1,
  'organization_admin of Org A can see the hotel mapped to Org A'
);

select is(
  (select count(*)::int from hotels where id = '00000032-0000-0000-0000-00000000ff02'),
  0,
  'organization_admin of Org A cannot see the hotel mapped to unrelated Org B'
);

reset role;

-- Grant the same caller organization_admin on Org B as well. The row should
-- become visible, proving the policy is scoped rather than simply disabling
-- legacy master visibility across non-home hotels.
insert into memberships (profile_id, organization_id, role_id, status)
select
  '00000032-0000-0000-0000-000000000a01',
  p.organization_id,
  r.id,
  'active'
from legacy_property_mapping m
join properties p on p.id = m.platform_property_id
join roles r on r.slug = 'organization_admin'
where m.legacy_hotel_id = '00000032-0000-0000-0000-00000000ff02';

set local role authenticated;
set local request.jwt.claim.sub = '00000032-0000-0000-0000-000000000a01';

select is(
  (select count(*)::int from hotels where id = '00000032-0000-0000-0000-00000000ff02'),
  1,
  'after receiving organization_admin on Org B, the caller can see Org B hotel too'
);

reset role;
select * from finish();
rollback;
