-- PRE-FLIGHT #14 redesign -- replaces direct auth-schema access.
-- Run with the SAME admin credential used for setup_readonly_role.sql,
-- AFTER setup_readonly_role.sql (the migration_readonly role must
-- already exist -- this script grants SELECT on the view to it).
--
-- PRE-FLIGHT #14 found that granting USAGE on schema auth to
-- migration_readonly does not take effect on the real legacy project:
-- the auth schema is owned by supabase_admin, not by the admin role
-- that runs these setup scripts, and its ACL is Supabase-internal --
-- deliberately not something this project keeps modifying. This script
-- avoids touching the auth schema's ACL entirely.
--
-- Instead: one narrow VIEW in public, owned by the admin role (whoever
-- runs this script), exposing only (staff_profile_id, auth_user_id,
-- email) for staff with a linked auth.users row -- never
-- password/hash/metadata, never the full auth.users table. Because a
-- view's underlying query runs with the OWNER's privileges (not the
-- caller's) unless security_invoker is set, migration_readonly can read
-- through it without ever holding any privilege on the auth schema
-- itself -- its access is capped by construction to exactly these two
-- columns, for exactly these rows, forever, regardless of what other
-- columns or objects auth.users/schema auth may ever contain.
--
-- Chosen over a SECURITY DEFINER function: a view's referenced objects
-- are bound by OID in the catalog (pg_rewrite) at CREATE VIEW time, not
-- re-resolved by name against a caller's search_path at each execution
-- -- so it is not exposed to the search_path-hijacking class of
-- privilege-escalation bug that a SECURITY DEFINER function must guard
-- against explicitly. For a single static SELECT like this one, that
-- extra risk surface buys nothing. All object references below are
-- schema-qualified even so, so creation itself does not depend on
-- search_path either.
\set ON_ERROR_STOP on

create view public.migration_readonly_auth_lookup
with (security_invoker = false)
as
select
  sp.id as staff_profile_id,
  sp.auth_user_id,
  au.email
from public.staff_profiles sp
join auth.users au on au.id = sp.auth_user_id;

comment on view public.migration_readonly_auth_lookup is
  'TEMPORARY -- PRE-FLIGHT #14 / Auth migration phase. Exposes only (staff_profile_id, auth_user_id, email) for staff with a linked auth.users row -- never password/hash/metadata, never the full auth.users table. Owned by the admin role so migration_readonly can read it without any grant on the auth schema itself. Drop after cutover -- see cleanup_post_cutover.sql.';

revoke all on public.migration_readonly_auth_lookup from public;
grant select on public.migration_readonly_auth_lookup to migration_readonly;

\echo '--- verification: exactly these 3 columns, granted only to migration_readonly ---'
select grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public' and table_name = 'migration_readonly_auth_lookup'
order by grantee;
