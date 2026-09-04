-- Diagnosis-only, non-destructive. Explains why migration_readonly sees
-- 0 rows on hotels despite holding table-level SELECT: reads RLS status
-- and policy definitions from pg_class/pg_policies -- catalog metadata,
-- world-readable by any authenticated role, no admin/superuser needed,
-- no row content from the 7 data tables themselves. No fix applied here.
\set ON_ERROR_STOP on

\echo '--- 1. RLS status per table (relrowsecurity / relforcerowsecurity) ---'
select
  n.nspname as schema,
  c.relname as table_name,
  c.relrowsecurity,
  c.relforcerowsecurity
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('hotels','staff_profiles','rooms','stays','request_categories','request_types','guest_requests')
order by c.relname;

\echo '--- 2. RLS policies applicable to these 7 tables (policy definition text is SQL logic, not row data) ---'
select
  schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('hotels','staff_profiles','rooms','stays','request_categories','request_types','guest_requests')
order by tablename, policyname;

\echo '--- 3. Does any policy role list cover migration_readonly, public, or PUBLIC (0=none)? ---'
select
  tablename,
  count(*) filter (where 'migration_readonly' = any(roles)) as policies_naming_this_role,
  count(*) filter (where 'public' = any(roles)) as policies_naming_public_pseudo_role
from pg_policies
where schemaname = 'public'
  and tablename in ('hotels','staff_profiles','rooms','stays','request_categories','request_types','guest_requests')
group by tablename
order by tablename;
