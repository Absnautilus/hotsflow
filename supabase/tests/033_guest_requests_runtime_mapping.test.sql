begin;
create extension if not exists pgtap;
select plan(4);

insert into hotels (id, name, timezone, active) values
  ('00000033-0000-0000-0000-00000000ff01', 'Runtime Hotel A', 'Europe/Rome', true),
  ('00000033-0000-0000-0000-00000000ff02', 'Runtime Hotel B', 'Europe/Rome', true);

select backfill_legacy_property_mapping();
select backfill_guest_requests_entitlement();

insert into auth.users (id) values
  ('00000033-0000-0000-0000-000000000a01');

insert into profiles (id, full_name) values
  ('00000033-0000-0000-0000-000000000a01', 'Runtime User');

insert into memberships (profile_id, property_id, role_id, status)
select
  '00000033-0000-0000-0000-000000000a01',
  m.platform_property_id,
  r.id,
  'active'
from legacy_property_mapping m
join roles r on r.slug = 'receptionist'
where m.legacy_hotel_id = '00000033-0000-0000-0000-00000000ff01';

set local role authenticated;
set local request.jwt.claim.sub = '00000033-0000-0000-0000-000000000a01';

select is(
  guest_requests_legacy_hotel_for_property(
    (select platform_property_id from legacy_property_mapping where legacy_hotel_id = '00000033-0000-0000-0000-00000000ff01')
  ),
  '00000033-0000-0000-0000-00000000ff01'::uuid,
  'accessible entitled property resolves to its legacy hotel id'
);

select is(
  guest_requests_legacy_hotel_for_property(
    (select platform_property_id from legacy_property_mapping where legacy_hotel_id = '00000033-0000-0000-0000-00000000ff02')
  ),
  null::uuid,
  'unrelated property mapping is not exposed'
);

reset role;

update property_modules pm
set enabled = false
from modules mo, legacy_property_mapping m
where pm.module_id = mo.id
  and mo.slug = 'guest_requests'
  and pm.property_id = m.platform_property_id
  and m.legacy_hotel_id = '00000033-0000-0000-0000-00000000ff01';

set local role authenticated;
set local request.jwt.claim.sub = '00000033-0000-0000-0000-000000000a01';

select is(
  guest_requests_legacy_hotel_for_property(
    (select platform_property_id from legacy_property_mapping where legacy_hotel_id = '00000033-0000-0000-0000-00000000ff01')
  ),
  null::uuid,
  'disabled guest_requests entitlement fails closed'
);

reset role;

select is(
  has_function_privilege('anon', 'guest_requests_legacy_hotel_for_property(uuid)', 'EXECUTE'),
  false,
  'anonymous callers cannot execute the runtime mapping resolver'
);

select * from finish();
rollback;
