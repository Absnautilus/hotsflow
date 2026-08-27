-- Fase 2 Step 5 — guest_requests module entitlement backfill.
-- Covers the 7 requested checks plus the "pre-existing incompatible row"
-- stop-and-report case, mirroring the same idempotency/no-silent-correction
-- discipline as Steps 3 and 4.
begin;
create extension if not exists pgtap;
select plan(10);

-- --- fixtures: 2 mapped hotels + 1 unmapped hotel -------------------------
insert into hotels (id, name, timezone, active) values
  ('00000020-0000-0000-0000-00000000ff01', 'Hotel Sette', 'Europe/Rome', true),
  ('00000020-0000-0000-0000-00000000ff02', 'Hotel Otto', 'Europe/Rome', true);
select backfill_legacy_property_mapping();

-- an unmapped property, entirely unrelated to guest_requests, to prove
-- check 5 (no accidental entitlement) and check 6 (other modules untouched)
insert into organizations (id, name, slug) values
  ('00000020-0000-0000-0000-000000000201', 'Org Non Mappata', 'org-020-non-mappata');
insert into properties (id, organization_id, name, slug) values
  ('00000020-0000-0000-0000-000000000202', '00000020-0000-0000-0000-000000000201', 'Property Non Mappata', 'p-020');
insert into property_modules (property_id, module_id, enabled)
select '00000020-0000-0000-0000-000000000202', id, true from modules where slug = 'shifts';

select backfill_guest_requests_entitlement();

-- 1. every mapped property has exactly one guest_requests entitlement row
select is(
  (select count(*)::int
   from legacy_property_mapping m
   join property_modules pm on pm.property_id = m.platform_property_id
   join modules mod on mod.id = pm.module_id and mod.slug = 'guest_requests'
   where m.legacy_hotel_id in ('00000020-0000-0000-0000-00000000ff01','00000020-0000-0000-0000-00000000ff02')),
  2,
  'both mapped hotels have exactly one guest_requests entitlement row each'
);

-- 2. enabled = true for bootstrap-created rows
select is(
  (select count(*)::int
   from legacy_property_mapping m
   join property_modules pm on pm.property_id = m.platform_property_id
   join modules mod on mod.id = pm.module_id and mod.slug = 'guest_requests'
   where m.legacy_hotel_id in ('00000020-0000-0000-0000-00000000ff01','00000020-0000-0000-0000-00000000ff02')
     and pm.enabled = true),
  2,
  'both bootstrap-created rows have enabled = true'
);

-- 3. double execution -> no duplication
select backfill_guest_requests_entitlement();
select is(
  (select count(*)::int
   from legacy_property_mapping m
   join property_modules pm on pm.property_id = m.platform_property_id
   join modules mod on mod.id = pm.module_id and mod.slug = 'guest_requests'
   where m.legacy_hotel_id in ('00000020-0000-0000-0000-00000000ff01','00000020-0000-0000-0000-00000000ff02')),
  2,
  'calling backfill_guest_requests_entitlement() twice does not duplicate rows'
);

-- 4. has_module(property, 'guest_requests') = true for all mapped properties
select ok(
  (select bool_and(has_module(m.platform_property_id, 'guest_requests'))
   from legacy_property_mapping m
   where m.legacy_hotel_id in ('00000020-0000-0000-0000-00000000ff01','00000020-0000-0000-0000-00000000ff02')),
  'has_module(property, ''guest_requests'') is true for every mapped property'
);

-- 5. unmapped property -> no guest_requests entitlement created accidentally
select is(
  (select count(*)::int from property_modules pm
   join modules mod on mod.id = pm.module_id and mod.slug = 'guest_requests'
   where pm.property_id = '00000020-0000-0000-0000-000000000202'),
  0,
  'the unmapped property received no guest_requests entitlement row'
);

-- 6. other modules already present in property_modules -> untouched
select is(
  (select pm.enabled from property_modules pm
   join modules mod on mod.id = pm.module_id and mod.slug = 'shifts'
   where pm.property_id = '00000020-0000-0000-0000-000000000202'),
  true,
  'the unrelated pre-existing shifts entitlement on another property is untouched'
);
select is(
  (select count(*)::int from property_modules where property_id = '00000020-0000-0000-0000-000000000202'),
  1,
  'the unmapped property still has exactly its one original module row, nothing added'
);

-- 7. no additional client grant introduced: authenticated still has only
-- SELECT on property_modules (insert/update revoked in 0013)
select set_eq(
  $$ select privilege_type from information_schema.role_table_grants
     where table_name = 'property_modules' and grantee = 'authenticated' $$,
  $$ values ('SELECT') $$,
  'authenticated still has only SELECT on property_modules — no grant added by this migration'
);

-- pre-existing incompatible row (enabled=false) is never silently flipped
insert into hotels (id, name, timezone, active) values
  ('00000020-0000-0000-0000-00000000ff03', 'Hotel Nove', 'Europe/Rome', true);
select backfill_legacy_property_mapping();
insert into property_modules (property_id, module_id, enabled)
select m.platform_property_id, mod.id, false
from legacy_property_mapping m, modules mod
where m.legacy_hotel_id = '00000020-0000-0000-0000-00000000ff03' and mod.slug = 'guest_requests';

select throws_ok(
  $$ select backfill_guest_requests_entitlement() $$,
  'P0001',
  null,
  'a pre-existing enabled=false entitlement row is never silently flipped to true — the backfill fails loud instead'
);

-- and the row genuinely was left at enabled=false, not corrected before failing
select is(
  (select pm.enabled from legacy_property_mapping m
   join property_modules pm on pm.property_id = m.platform_property_id
   join modules mod on mod.id = pm.module_id and mod.slug = 'guest_requests'
   where m.legacy_hotel_id = '00000020-0000-0000-0000-00000000ff03'),
  false,
  'the disabled entitlement row is untouched after the failed backfill attempt'
);

select * from finish();
rollback;
