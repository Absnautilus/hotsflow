-- Pre-cutover check: is the real legacy Housekeeping project currently
-- OPERATIONAL (app-facing roles can still write), or does it show the
-- signature of an active/incomplete FREEZE from a previous attempt?
--
-- Read-only, catalog/metadata introspection only, using ONLY the
-- migration_readonly credential (LEGACY_DB_URL_READONLY) -- exactly the
-- same posture as every other verify_*.sql script in this directory. No
-- write is attempted, no snapshot/restore table is created or modified,
-- no application data is read.
--
-- Ground truth definition of "frozen" is taken directly from this
-- repo's own freeze mechanism (scripts/freeze/01_snapshot.sql /
-- 02_revoke.sql / 03_restore.sql): FREEZE revokes INSERT/UPDATE/DELETE
-- from authenticated and anon on exactly these 7 tables --
-- guest_requests, stays, staff_profiles, rooms, request_categories,
-- request_types, pms_integrations (note: this is the FREEZE scope, not
-- the migration's 7-table read scope -- it includes pms_integrations
-- and excludes hotels). 02_revoke.sql's own post-REVOKE verification
-- treats "0 rows" on that exact ACL query as proof the freeze took.
-- This script runs the same query as a live check: any row found means
-- at least one app-facing write path is still open, which is only true
-- if the project is NOT currently frozen.
--
-- Two independent pieces of evidence, both catalog-level (aclexplode on
-- pg_class.relacl / pg_attribute.attacl -- no SELECT privilege on the
-- tables themselves is required to inspect their ACL, same technique
-- already used throughout PRE-FLIGHT #14 for the auth lookup view):
--
--   1. Does a freeze/restore attempt leave any trace at all? Checked via
--      pg_tables existence of _freeze_acl_snapshot / _freeze_acl_after
--      (the permanent tracking tables scripts/freeze/01_snapshot.sql and
--      03_restore.sql create) -- existence only, via catalog metadata;
--      migration_readonly has no SELECT grant on these tables and their
--      contents are not read here.
--   2. The live ACL state itself -- the real ground truth, independent
--      of whether the freeze scripts in this repo were the exact
--      mechanism used for any prior attempt.
--
-- No PII: every result below is a role name, a table/column name, or a
-- privilege type -- never row content.
\set ON_ERROR_STOP on

\echo '=== connection identity (context only) ==='
select current_user, session_user, current_database();

\echo '=== A. does a freeze/restore attempt leave a trace? (existence only, no content read) ==='
select
  exists(select 1 from pg_tables where schemaname = 'public' and tablename = '_freeze_acl_snapshot') as freeze_snapshot_table_exists,
  exists(select 1 from pg_tables where schemaname = 'public' and tablename = '_freeze_acl_after') as freeze_restore_after_table_exists;

\echo '=== B. live ACL check: INSERT/UPDATE/DELETE for authenticated/anon on the 7 freeze-scope tables (table-level) ==='
\echo '--- (freeze-scope tables per scripts/freeze/01_snapshot.sql: guest_requests, stays, staff_profiles, rooms, request_categories, request_types, pms_integrations) ---'
select c.relname as table_name, a.grantee::regrole::text as grantee, a.privilege_type
from pg_class c
cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
where c.relnamespace = 'public'::regnamespace
  and c.relname in ('guest_requests','stays','staff_profiles','rooms','request_categories','request_types','pms_integrations')
  and a.grantee::regrole::text in ('authenticated','anon')
  and a.privilege_type in ('INSERT','UPDATE','DELETE')
order by 1,2,3;

\echo '=== C. live ACL check: INSERT/UPDATE/DELETE for authenticated/anon on the same 7 tables (column-level) ==='
select c.relname as table_name, att.attname as column_name, a.grantee::regrole::text as grantee, a.privilege_type
from pg_class c
join pg_attribute att on att.attrelid = c.oid and att.attnum > 0 and not att.attisdropped
cross join lateral aclexplode(att.attacl) a
where c.relnamespace = 'public'::regnamespace
  and c.relname in ('guest_requests','stays','staff_profiles','rooms','request_categories','request_types','pms_integrations')
  and att.attacl is not null
  and a.grantee::regrole::text in ('authenticated','anon')
  and a.privilege_type in ('INSERT','UPDATE','DELETE')
order by 1,2,3,4;

\echo '=== D. combined write-grant count across B + C (this is the actual OPERATIONAL/FROZEN determination) ==='
select (
  (select count(*)
   from pg_class c
   cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
   where c.relnamespace = 'public'::regnamespace
     and c.relname in ('guest_requests','stays','staff_profiles','rooms','request_categories','request_types','pms_integrations')
     and a.grantee::regrole::text in ('authenticated','anon')
     and a.privilege_type in ('INSERT','UPDATE','DELETE'))
  +
  (select count(*)
   from pg_class c
   join pg_attribute att on att.attrelid = c.oid and att.attnum > 0 and not att.attisdropped
   cross join lateral aclexplode(att.attacl) a
   where c.relnamespace = 'public'::regnamespace
     and c.relname in ('guest_requests','stays','staff_profiles','rooms','request_categories','request_types','pms_integrations')
     and att.attacl is not null
     and a.grantee::regrole::text in ('authenticated','anon')
     and a.privilege_type in ('INSERT','UPDATE','DELETE'))
) as total_write_grants_found;

select coalesce((
  (select count(*)
   from pg_class c
   cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
   where c.relnamespace = 'public'::regnamespace
     and c.relname in ('guest_requests','stays','staff_profiles','rooms','request_categories','request_types','pms_integrations')
     and a.grantee::regrole::text in ('authenticated','anon')
     and a.privilege_type in ('INSERT','UPDATE','DELETE'))
  +
  (select count(*)
   from pg_class c
   join pg_attribute att on att.attrelid = c.oid and att.attnum > 0 and not att.attisdropped
   cross join lateral aclexplode(att.attacl) a
   where c.relnamespace = 'public'::regnamespace
     and c.relname in ('guest_requests','stays','staff_profiles','rooms','request_categories','request_types','pms_integrations')
     and att.attacl is not null
     and a.grantee::regrole::text in ('authenticated','anon')
     and a.privilege_type in ('INSERT','UPDATE','DELETE'))
) > 0, false) as ok_operational \gset

\if :ok_operational
  \echo 'LEGACY STATUS: OPERATIONAL / UNFROZEN -- at least one INSERT/UPDATE/DELETE grant for authenticated/anon is present on the freeze-scope tables (see sections B/C above for the exact evidence).'
\else
  \echo 'LEGACY STATUS: STILL FROZEN OR AMBIGUOUS -- zero INSERT/UPDATE/DELETE grants found for authenticated/anon across all 7 freeze-scope tables (table- and column-level). This matches exactly the state scripts/freeze/02_revoke.sql defines as a successful freeze (its own post-REVOKE check expects 0 rows on this identical query). Do not proceed to cutover. Do not attempt automatic restore.'
  DO $$
  BEGIN
    RAISE EXCEPTION 'Legacy status check: zero write grants found for authenticated/anon on the freeze-scope tables -- ambiguous or still frozen, aborting for manual review';
  END
  $$;
\endif

\echo ''
\echo '=== LEGACY OPERATIONAL STATUS CHECK: COMPLETE ==='
