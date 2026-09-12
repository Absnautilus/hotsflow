-- guest_slug: auto-assigned on insert, collision-safe, resolvable by anon
-- for an active hotel only, and bridged to Core properties the same way
-- guest_requests_legacy_hotel_for_property already is.
begin;
create extension if not exists pgtap;
select plan(10);

select is(
  slugify_hotel_name('Palazzo Veneziano'),
  'palazzo-veneziano',
  'slugify_hotel_name lowercases and hyphenates spaces'
);
select is(
  slugify_hotel_name('  Café & Co.  '),
  'caf-co',
  'slugify_hotel_name strips punctuation/accented bytes and trims stray hyphens'
);

-- ### auto-assignment + collision suffix, purely via the insert trigger ###
insert into hotels (id, name, timezone, active) values
  ('00000044-0000-0000-0000-000000000001', 'Test Slug Hotel', 'Europe/Rome', true);
insert into hotels (id, name, timezone, active) values
  ('00000044-0000-0000-0000-000000000002', 'Test Slug Hotel', 'Europe/Rome', true);
insert into hotels (id, name, timezone, active) values
  ('00000044-0000-0000-0000-000000000003', 'Test Slug Hotel', 'Europe/Rome', false);

select is(
  (select guest_slug from hotels where id = '00000044-0000-0000-0000-000000000001'),
  'test-slug-hotel',
  'the first hotel with this name gets the plain slug, with no explicit call needed -- the insert trigger alone assigns it'
);
select is(
  (select guest_slug from hotels where id = '00000044-0000-0000-0000-000000000002'),
  'test-slug-hotel-2',
  'a same-named hotel collides and gets a -2 suffix'
);
select is(
  (select guest_slug from hotels where id = '00000044-0000-0000-0000-000000000003'),
  'test-slug-hotel-3',
  'a third same-named hotel gets -3, not another -2'
);

-- ### anon resolution ###
set local role anon;
select is(
  resolve_hotel_guest_slug('test-slug-hotel'),
  '00000044-0000-0000-0000-000000000001'::uuid,
  'anon resolves the plain slug to the first (active) hotel'
);
select is(
  resolve_hotel_guest_slug('test-slug-hotel-3'),
  null,
  'anon resolution of an inactive hotel''s slug returns null, not the id'
);
select is(
  resolve_hotel_guest_slug('no-such-slug'),
  null,
  'anon resolution of an unknown slug returns null'
);
reset role;

-- ### Core bridge, mirroring guest_requests_legacy_hotel_for_property's own
-- access check ###
insert into organizations (id, name, slug) values
  ('00000044-0000-0000-0000-000000000010', 'Slug Test Org', 'test-044-org');
insert into properties (id, organization_id, name, slug) values
  ('00000044-0000-0000-0000-000000000011', '00000044-0000-0000-0000-000000000010', 'Slug Test Property', 'test-044-prop');
insert into legacy_property_mapping (platform_property_id, legacy_hotel_id) values
  ('00000044-0000-0000-0000-000000000011', '00000044-0000-0000-0000-000000000001');
insert into property_modules (property_id, module_id, enabled)
select '00000044-0000-0000-0000-000000000011', id, true from modules where slug = 'guest_requests';

insert into auth.users (id) values ('00000044-0000-0000-0000-000000000021');
insert into profiles (id, full_name) values ('00000044-0000-0000-0000-000000000021', 'Slug Test Member');
insert into memberships (profile_id, property_id, role_id, status)
select '00000044-0000-0000-0000-000000000021', '00000044-0000-0000-0000-000000000011', r.id, 'active'
from roles r where r.slug = 'property_admin';

set local role authenticated;
set local request.jwt.claim.sub = '00000044-0000-0000-0000-000000000021';
select is(
  guest_requests_slug_for_property('00000044-0000-0000-0000-000000000011'),
  'test-slug-hotel',
  'an authorized member with the module enabled gets the mapped hotel''s slug'
);
reset role;

insert into auth.users (id) values ('00000044-0000-0000-0000-000000000022');
insert into profiles (id, full_name) values ('00000044-0000-0000-0000-000000000022', 'Outsider');
set local role authenticated;
set local request.jwt.claim.sub = '00000044-0000-0000-0000-000000000022';
select is(
  guest_requests_slug_for_property('00000044-0000-0000-0000-000000000011'),
  null,
  'a profile with no membership on the property gets null, not the slug'
);
reset role;

select * from finish();
rollback;
