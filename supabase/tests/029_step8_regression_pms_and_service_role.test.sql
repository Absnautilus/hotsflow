-- Fase 2 Step 8/9 — permanent regression coverage for two bugs found ONLY
-- by live browser/network E2E testing, never by this suite:
--
-- 1. get_pms_integration_status(): 021's own PMS coverage only ever
--    exercised the DENIED paths (receptionist -> not authorized). No test
--    anywhere called it on an ALLOWED path and checked the result — so a
--    genuine runtime bug (ambiguous "hotel_id" column reference, fixed in
--    20260827122300) shipped and stayed live until an actual browser hit
--    it. This file adds the missing positive-path coverage for both
--    get_pms_integration_status() and save_pms_integration(), including
--    verifying the row actually written, not just "didn't throw".
--
-- 2. service_role had zero SELECT/INSERT/UPDATE/DELETE on any public-
--    schema table on the live project (fixed in 20260827122400) — a gap
--    with no SQL-level test at all before now, since every prior test
--    connects as `authenticated`/`anon`/superuser, never checks what
--    service_role (the role every Edge Function runs as) can actually do.
begin;
create extension if not exists pgtap;
select plan(10);

-- --- fixtures ----------------------------------------------------------
insert into hotels (id, name, timezone, active) values
  ('00000029-0000-0000-0000-00000000ff01', 'Hotel Uno', 'Europe/Rome', true),
  ('00000029-0000-0000-0000-00000000ff02', 'Hotel Due', 'Europe/Rome', true);
select backfill_legacy_property_mapping();
select backfill_guest_requests_entitlement();

insert into auth.users (id) values
  ('00000029-0000-0000-0000-000000000a01'), -- property_admin @ H1
  ('00000029-0000-0000-0000-000000000a02'); -- master, home hotel H1

insert into staff_profiles (id, hotel_id, auth_user_id, name, role, department, active, login_username) values
  ('00000029-0000-0000-0000-000000000101', '00000029-0000-0000-0000-00000000ff01', '00000029-0000-0000-0000-000000000a01', 'PA Uno', 'admin', null, true, null),
  ('00000029-0000-0000-0000-000000000102', '00000029-0000-0000-0000-00000000ff01', '00000029-0000-0000-0000-000000000a02', 'Master Uno', 'master', null, true, null);
select backfill_staff_identity();

-- =========================================================================
-- get_pms_integration_status() — positive path (the actual bug: was
-- raising "column reference \"hotel_id\" is ambiguous" for EVERY caller,
-- allowed or not, because the error was in the query body, past the
-- authorization check)
-- =========================================================================
set local role authenticated;
set local request.jwt.claim.sub = '00000029-0000-0000-0000-000000000a01';
select lives_ok(
  $$ select * from get_pms_integration_status('00000029-0000-0000-0000-00000000ff01') $$,
  'get_pms_integration_status() succeeds for a property_admin on their own, entitled hotel (regression: was "column reference hotel_id is ambiguous")'
);
select is(
  (select hotel_id from get_pms_integration_status('00000029-0000-0000-0000-00000000ff01')),
  '00000029-0000-0000-0000-00000000ff01'::uuid,
  'the returned row''s hotel_id matches the requested hotel'
);
select is(
  (select mode from get_pms_integration_status('00000029-0000-0000-0000-00000000ff01')),
  'manual'::stay_source,
  'with no pms_integrations row yet, the fallback branch returns mode=manual, not an error'
);
reset role;

-- master (organization_admin, org-wide guest_requests.pms.manage) reading
-- status for a hotel that isn't their own home hotel -- 021 only covered
-- this for save_pms_integration, never for the read side.
set local role authenticated;
set local request.jwt.claim.sub = '00000029-0000-0000-0000-000000000a02';
select lives_ok(
  $$ select * from get_pms_integration_status('00000029-0000-0000-0000-00000000ff02') $$,
  'master reads PMS status for a hotel that is not their home hotel (org-wide) without error'
);
reset role;

-- =========================================================================
-- save_pms_integration() — 021 already checked this doesn't throw
-- (lives_ok); strengthen to verify the row actually lands correctly.
-- =========================================================================
set local role authenticated;
set local request.jwt.claim.sub = '00000029-0000-0000-0000-000000000a01';
select save_pms_integration('00000029-0000-0000-0000-00000000ff01', 'opera', 'HTL01', 'ENT01', 'https://example.test/gw', 'client-id', 'client-secret', 'app-key');
reset role;
select is(
  (select mode from pms_integrations where hotel_id = '00000029-0000-0000-0000-00000000ff01'),
  'opera'::stay_source,
  'save_pms_integration actually persists the row (mode), not just "does not throw"'
);
select is(
  (select ohip_hotel_code from pms_integrations where hotel_id = '00000029-0000-0000-0000-00000000ff01'),
  'HTL01',
  'save_pms_integration persists ohip_hotel_code correctly'
);

-- =========================================================================
-- service_role privileges -- the actual object of the second live bug.
-- =========================================================================
select ok(
  (select bool_and(has_table_privilege('service_role', 'public.staff_profiles', priv))
   from unnest(array['SELECT','INSERT','UPDATE','DELETE']) as priv),
  'service_role has SELECT/INSERT/UPDATE/DELETE on staff_profiles (the table the live regression broke)'
);

-- information_schema.role_table_grants (not pg_tables + has_table_privilege
-- per row) -- the latter blew up on at least one catalog-listed relation
-- that has_table_privilege couldn't resolve (a migration-tracking table
-- some local Supabase CLI versions place directly in public), which isn't
-- a table this check needs to reason about anyway.
select is(
  (select count(distinct t.tablename)::int
   from pg_tables t
   where t.schemaname = 'public'
     and t.tablename !~ '^(schema_migrations|_test029_.*)$'
     and not exists (
       select 1 from (values ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE')) as need(priv)
       where not exists (
         select 1 from information_schema.role_table_grants g
         where g.table_schema = 'public' and g.table_name = t.tablename
           and g.grantee = 'service_role' and g.privilege_type = need.priv
       )
     )),
  0,
  'service_role has full SELECT/INSERT/UPDATE/DELETE on every real table in the public schema, not just staff_profiles'
);

-- =========================================================================
-- default privileges: a table created AFTER this migration (by the same
-- role that ran it) must automatically get the same service_role grants --
-- this is the actual guarantee 20260827122400's ALTER DEFAULT PRIVILEGES
-- makes, and the only way to prove it holds is to create a table and check.
-- =========================================================================
create table _test029_default_privs_probe (id int);
select ok(
  has_table_privilege('service_role', 'public._test029_default_privs_probe', 'SELECT')
  and has_table_privilege('service_role', 'public._test029_default_privs_probe', 'INSERT')
  and has_table_privilege('service_role', 'public._test029_default_privs_probe', 'UPDATE')
  and has_table_privilege('service_role', 'public._test029_default_privs_probe', 'DELETE'),
  'a table created after 20260827122400 automatically gets full service_role grants via ALTER DEFAULT PRIVILEGES, with no migration having to grant it by hand'
);
drop table _test029_default_privs_probe;

-- Document exactly what the default-privilege entry covers (schema,
-- grantee, object type) -- this is the queryable fact backing Step 9's
-- documentation of the grant's scope, not just "it works" behaviorally.
select set_eq(
  $$ select defaclobjtype from pg_default_acl da
     join pg_namespace n on n.oid = da.defaclnamespace
     where n.nspname = 'public'
       and exists (select 1 from aclexplode(da.defaclacl) x join pg_roles gr on gr.oid = x.grantee where gr.rolname = 'service_role') $$,
  $$ values ('r'), ('S'), ('f') $$,
  'the recorded default-ACL entries granting service_role in schema public are scoped to exactly relations (r), sequences (S) and functions (f) -- not schemas, types, or anything broader'
);

select * from finish();
rollback;
