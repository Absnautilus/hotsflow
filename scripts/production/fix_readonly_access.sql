-- PRE-FLIGHT #14 fix -- authorized, minimal, additive. Run with an ADMIN
-- credential against the real legacy Housekeeping project (migration_readonly
-- itself cannot run this: CREATE POLICY / GRANT USAGE ON SCHEMA require a
-- privilege it does not have, by design).
--
-- What this does, exactly and only:
--   1. Adds ONE new SELECT-only RLS policy per migrated table, scoped
--      exclusively to migration_readonly. Does not touch, modify, or
--      remove any existing policy (the 16 app-facing policies already on
--      these tables are untouched). Every other role's access is
--      unchanged.
--   2. Grants USAGE on schema auth to migration_readonly -- the one
--      missing piece already present as a GRANT in setup_readonly_role.sql
--      but apparently without effect on this role; this re-applies it.
--
-- What this explicitly does NOT do:
--   - no BYPASSRLS anywhere
--   - no RLS disabled on any table
--   - no change to rolbypassrls or any other role attribute
--   - no change to any write privilege (INSERT/UPDATE/DELETE/TRUNCATE
--     remain ungranted, as already verified)
\set ON_ERROR_STOP on

create policy migration_readonly_select_hotels on hotels for select to migration_readonly using (true);
create policy migration_readonly_select_staff_profiles on staff_profiles for select to migration_readonly using (true);
create policy migration_readonly_select_rooms on rooms for select to migration_readonly using (true);
create policy migration_readonly_select_stays on stays for select to migration_readonly using (true);
create policy migration_readonly_select_request_categories on request_categories for select to migration_readonly using (true);
create policy migration_readonly_select_request_types on request_types for select to migration_readonly using (true);
create policy migration_readonly_select_guest_requests on guest_requests for select to migration_readonly using (true);

grant usage on schema auth to migration_readonly;

\echo '--- verification: the 7 new policies now exist (names only -- keep this list, needed to drop them after cutover) ---'
select tablename, policyname, roles, cmd
from pg_policies
where policyname like 'migration_readonly_select_%'
order by tablename;
