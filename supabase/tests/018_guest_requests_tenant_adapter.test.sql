-- Fase 2 Step 3 — guest_requests tenant adapter (legacy_property_mapping).
-- Covers the 8 checks requested before Step 3 sign-off: one mapping per
-- hotel, one property per mapping, correct organization ownership, no
-- orphaned hotel, idempotency on re-run, timezone/name preservation,
-- deterministic/collision-safe slugs, and that nothing reads the mapping
-- for authorization yet.
begin;
create extension if not exists pgtap;
select plan(17);

-- Fixture: 4 hotels covering the interesting cases —
--  018...01: plain name, active
--  018...02: same name as 01 (forces the slug-collision fallback)
--  018...03: inactive (hotels.active = false)
--  018...04: accented/punctuated name + a non-default timezone
insert into hotels (id, name, timezone, active) values
  ('00000018-0000-0000-0000-000000000001', 'Hotel Roma', 'Europe/Rome', true),
  ('00000018-0000-0000-0000-000000000002', 'Hotel Roma', 'Europe/Rome', true),
  ('00000018-0000-0000-0000-000000000003', 'Hotel Inattivo', 'Europe/Rome', false),
  ('00000018-0000-0000-0000-000000000004', 'Albergo città, S.r.l.', 'America/New_York', true);

select backfill_legacy_property_mapping();

-- 1. exactly one mapping per hotel
select is(
  (select count(*)::int from legacy_property_mapping
   where legacy_hotel_id in (
     '00000018-0000-0000-0000-000000000001','00000018-0000-0000-0000-000000000002',
     '00000018-0000-0000-0000-000000000003','00000018-0000-0000-0000-000000000004'
   )),
  4,
  'each of the 4 fixture hotels has exactly one legacy_property_mapping row'
);

-- 2. each mapping points to a distinct property (no property shared by two hotels)
select is(
  (select count(distinct platform_property_id)::int from legacy_property_mapping
   where legacy_hotel_id in (
     '00000018-0000-0000-0000-000000000001','00000018-0000-0000-0000-000000000002',
     '00000018-0000-0000-0000-000000000003','00000018-0000-0000-0000-000000000004'
   )),
  4,
  'all 4 mappings point to 4 distinct properties'
);

-- 3. each property belongs to an organization created only for that hotel
--    (that organization has exactly one property: the mapped one)
select is(
  (select count(*)::int
   from legacy_property_mapping m
   join properties p on p.id = m.platform_property_id
   where m.legacy_hotel_id = '00000018-0000-0000-0000-000000000001'
     and (select count(*) from properties p2 where p2.organization_id = p.organization_id) = 1),
  1,
  'the property for hotel 01 belongs to an organization that owns exactly that one property'
);

-- 4. no orphaned hotel among the fixtures
select is(
  (select count(*)::int from hotels h
   where h.id in (
     '00000018-0000-0000-0000-000000000001','00000018-0000-0000-0000-000000000002',
     '00000018-0000-0000-0000-000000000003','00000018-0000-0000-0000-000000000004'
   )
   and not exists (select 1 from legacy_property_mapping m where m.legacy_hotel_id = h.id)),
  0,
  'no fixture hotel is missing a mapping'
);

-- 5. idempotency: calling the backfill again creates nothing new
select backfill_legacy_property_mapping();
select is(
  (select count(*)::int from legacy_property_mapping
   where legacy_hotel_id in (
     '00000018-0000-0000-0000-000000000001','00000018-0000-0000-0000-000000000002',
     '00000018-0000-0000-0000-000000000003','00000018-0000-0000-0000-000000000004'
   )),
  4,
  'calling backfill_legacy_property_mapping() twice does not duplicate mappings'
);
select is(
  (select count(*)::int from organizations o
   join legacy_property_mapping m on true
   join properties p on p.id = m.platform_property_id and p.organization_id = o.id
   where m.legacy_hotel_id = '00000018-0000-0000-0000-000000000001'),
  1,
  'hotel 01 still has exactly one organization after a second backfill call'
);

-- 6. timezone and name preserved from the legacy hotel
select is(
  (select p.timezone from legacy_property_mapping m join properties p on p.id = m.platform_property_id
   where m.legacy_hotel_id = '00000018-0000-0000-0000-000000000004'),
  'America/New_York',
  'property.timezone preserves the non-default hotels.timezone'
);
select is(
  (select p.name from legacy_property_mapping m join properties p on p.id = m.platform_property_id
   where m.legacy_hotel_id = '00000018-0000-0000-0000-000000000004'),
  'Albergo città, S.r.l.',
  'property.name preserves hotels.name exactly'
);
select is(
  (select o.name from legacy_property_mapping m
   join properties p on p.id = m.platform_property_id
   join organizations o on o.id = p.organization_id
   where m.legacy_hotel_id = '00000018-0000-0000-0000-000000000004'),
  'Albergo città, S.r.l.',
  'organization.name preserves hotels.name exactly'
);

-- hotels.active = false -> property.status = 'suspended' (approved mapping)
select is(
  (select p.status from legacy_property_mapping m join properties p on p.id = m.platform_property_id
   where m.legacy_hotel_id = '00000018-0000-0000-0000-000000000003'),
  'suspended',
  'hotels.active = false maps to property.status = suspended'
);
select is(
  (select p.status from legacy_property_mapping m join properties p on p.id = m.platform_property_id
   where m.legacy_hotel_id = '00000018-0000-0000-0000-000000000001'),
  'active',
  'hotels.active = true maps to property.status = active'
);

-- 7. deterministic + collision-safe slugs
select is(legacy_hotel_slug('Hotel Roma'), legacy_hotel_slug('Hotel Roma'),
  'legacy_hotel_slug() is deterministic for the same input');
select is(legacy_hotel_slug('Albergo città, S.r.l.'), 'albergo-citta-s-r-l',
  'legacy_hotel_slug() unaccents, lowercases, and collapses punctuation to single hyphens');

select isnt(
  (select o1.slug from legacy_property_mapping m1 join organizations o1 on o1.id =
     (select organization_id from properties where id = m1.platform_property_id)
   where m1.legacy_hotel_id = '00000018-0000-0000-0000-000000000001'),
  (select o2.slug from legacy_property_mapping m2 join organizations o2 on o2.id =
     (select organization_id from properties where id = m2.platform_property_id)
   where m2.legacy_hotel_id = '00000018-0000-0000-0000-000000000002'),
  'two hotels named identically get distinct organization slugs (collision fallback engaged)'
);
select ok(
  (select o.slug from legacy_property_mapping m join organizations o on o.id =
     (select organization_id from properties where id = m.platform_property_id)
   where m.legacy_hotel_id = '00000018-0000-0000-0000-000000000002')
  like 'hotel-roma-%',
  'the colliding hotel''s slug keeps the readable prefix plus a suffix, not an opaque id'
);
select is(
  (select o.slug from legacy_property_mapping m join organizations o on o.id =
     (select organization_id from properties where id = m.platform_property_id)
   where m.legacy_hotel_id = '00000018-0000-0000-0000-000000000001'),
  'hotel-roma',
  'the first hotel to claim a slug keeps the plain, unsuffixed form'
);

-- 8. nothing reads the mapping for authorization yet: it carries no policy
-- at all (RLS enabled, zero grants to authenticated/anon) — direct access
-- from a staff session must be denied outright, not silently filtered.
set local role authenticated;
set local request.jwt.claim.sub = '00000018-0000-0000-0000-000000000099';
select throws_ok(
  $$ select * from legacy_property_mapping $$,
  '42501',
  null,
  'authenticated has no grant on legacy_property_mapping — nothing depends on it for access control yet'
);
reset role;

select * from finish();
rollback;
