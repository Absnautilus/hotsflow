-- Post-cutover cleanup. Removes everything PRE-FLIGHT #14 added to the
-- real legacy Housekeeping project: the additive RLS policies
-- (fix_readonly_access.sql), the temporary auth lookup view
-- (create_migration_auth_lookup.sql), and finally the migration_readonly
-- role itself. Run once, after cutover is complete and the rollback
-- observation window (see the runbook, section 8) has passed, with the
-- same admin credential used for every other script in this directory.
--
-- Deliberately touches only objects we own and control (public schema
-- tables/policies/view, and the role itself) -- nothing here depends on
-- any privilege over the auth schema, which is owned by supabase_admin
-- on the real legacy project. The final design grants migration_readonly
-- no privilege on auth at all, so there is nothing to revoke there; an
-- early version of this script did include a schema-auth REVOKE pair
-- "just in case" a historical grant remained, but under ON_ERROR_STOP
-- that made this cleanup's success depend on a schema this project does
-- not own -- removed rather than risk that.
--
-- Order matters: DROP ROLE fails ("role cannot be dropped because some
-- objects depend on it") while any GRANT, POLICY, or view privilege
-- still references the role -- so every dependency is removed first,
-- role last.
\set ON_ERROR_STOP on

-- 1. Revoke the base table grants (setup_readonly_role.sql)
revoke all privileges on
  hotels, staff_profiles, rooms, stays, request_categories, request_types, guest_requests
from migration_readonly;

-- 2. Drop the 7 additive RLS policies (fix_readonly_access.sql)
drop policy if exists migration_readonly_select_hotels on hotels;
drop policy if exists migration_readonly_select_staff_profiles on staff_profiles;
drop policy if exists migration_readonly_select_rooms on rooms;
drop policy if exists migration_readonly_select_stays on stays;
drop policy if exists migration_readonly_select_request_categories on request_categories;
drop policy if exists migration_readonly_select_request_types on request_types;
drop policy if exists migration_readonly_select_guest_requests on guest_requests;

-- 3. Drop the temporary auth lookup view (create_migration_auth_lookup.sql)
--    -- this also removes the GRANT SELECT on it, the last remaining
--    dependency.
drop view if exists public.migration_readonly_auth_lookup;

-- 4. Remove the role itself -- must come last.
drop role if exists migration_readonly;

\echo '--- verification: role no longer exists ---'
select exists(select 1 from pg_roles where rolname = 'migration_readonly') as migration_readonly_still_exists;
-- must be false

\echo '--- verification: no policy named migration_readonly_% remains anywhere ---'
select count(*) as residual_policies from pg_policies where policyname like 'migration_readonly_%';
-- must be 0

\echo '--- verification: the lookup view no longer exists ---'
select count(*) as residual_view from pg_views where schemaname = 'public' and viewname = 'migration_readonly_auth_lookup';
-- must be 0
