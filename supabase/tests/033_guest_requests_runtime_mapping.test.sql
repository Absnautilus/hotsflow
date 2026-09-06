begin;
create extension if not exists pgtap;
select plan(4);

insert into hotels (id, name, timezone, active) values
  ('00000033-0000-0000-0000-00000000ff01', 'Runtime Hotel A', 'Europe/Rome', true),
  ('00000033-0000-0000-0000-00000000ff02', 'Runtime Hotel B', 'Europe/Rome', true);

select backfill_legacy_property_mapping();
select backfill_guest_requests_entitlement();

create temporary table runtime_mapping_ids (
  key text primary key,
  property_id uuid not null
);

insert into runtime_mapping_ids (key, property_id)
select
  case m.legacy_hotel_id
    when '00000033-0000-0000-0000-00000000ff01'::uuid then 'a'
    when '00000033-0000-0000-0000-00000000ff02'::uuid then 'b'
  end,
  m.platform_property_id
from legacy_property_mapping m
where m.legacy_hotel_id in (
  '00000033-0000-0000-0000-00000000ff01'::uuid,
  '00000033-0000-0000-0000-00000000ff02'::uuid
);
grant select on runtime_mapping_ids to authenticated;

insert into auth.users (id) values
  ('00000033-0000-0000-0000-000000000a01');

insert into profiles (id, full_name) values
  ('00000033-0000-0000-0000-000000000a01', 'Runtime User');

insert into memberships (profile_id, property_id, role_id, status)
select
  '00000033-0000-0000-0000-000000000a01',
  (select property_id from runtime_mapping_ids where key = 'a'),
  r.id,
  'active'
from roles r
where r.slug = 'receptionist';

set local role authenticated;
set local request.jwt.claim.sub = '00000033-0000-0000-0000-000000000a01';

select is(
  guest_requests_legacy_hotel_for_property(
    (select property_id from runtime_mapping_ids where key = 'a')
  ),
  '00000033-0000-0000-0000-00000000ff01'::uuid,
  'accessible entitled property resolves to its legacy hotel id'
);

select is(
  guest_requests_legacy_hotel_for_property(
    (select property_id from runtime_mapping_ids where key = 'b')
  ),
  null::uuid,
  'unrelated property mapping is not exposed'
);

reset role;

update property_modules pm
set enabled = false
from modules mo
where pm.module_id = mo.id
  and mo.slug = 'guest_requests'
  and pm.property_id = (select property_id from runtime_mapping_ids where key = 'a');

set local role authenticated;
set local request.jwt.claim.sub = '00000033-0000-0000-0000-000000000a01';

select is(
  guest_requests_legacy_hotel_for_property(
    (select property_id from runtime_mapping_ids where key = 'a')
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
