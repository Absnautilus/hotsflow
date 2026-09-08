begin;
create extension if not exists pgtap;
select plan(4);

insert into organizations (id, name, slug) values
  ('00000036-0000-0000-0000-000000000001', 'Embedded Check Org', 'test-036-org');
insert into properties (id, organization_id, name, slug) values
  ('00000036-0000-0000-0000-000000000011', '00000036-0000-0000-0000-000000000001', 'Embedded Check Property', 'embedded-036');
insert into hotels (id, name) values
  ('00000036-0000-0000-0000-000000000021', 'Embedded Legacy Hotel'),
  ('00000036-0000-0000-0000-000000000022', 'Standalone Legacy Hotel');
insert into legacy_property_mapping (legacy_hotel_id, platform_property_id) values
  ('00000036-0000-0000-0000-000000000021', '00000036-0000-0000-0000-000000000011');

insert into auth.users (id) values ('00000036-0000-0000-0000-000000000041');
insert into profiles (id, full_name) values ('00000036-0000-0000-0000-000000000041', 'Any Authenticated User');

set local role authenticated;
set local request.jwt.claim.sub = '00000036-0000-0000-0000-000000000041';

select ok(
  legacy_hotel_is_embedded('00000036-0000-0000-0000-000000000021'),
  'a hotel mapped to a Core property is reported as embedded'
);
select ok(
  not legacy_hotel_is_embedded('00000036-0000-0000-0000-000000000022'),
  'a hotel with no mapping row is reported as not embedded'
);
select ok(
  not legacy_hotel_is_embedded('00000036-0000-0000-0000-000000099999'::uuid),
  'an unknown hotel id is reported as not embedded, not an error'
);

reset role;
set local role anon;
select throws_ok(
  $$ select legacy_hotel_is_embedded('00000036-0000-0000-0000-000000000021') $$,
  '42501', null,
  'anonymous callers cannot probe the legacy mapping'
);

reset role;
select * from finish();
rollback;
