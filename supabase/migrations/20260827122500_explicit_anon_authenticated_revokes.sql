-- Fase 2 Step 9 -- root-causes and closes a real local-vs-hosted CI
-- divergence (13 pgTAP failures, present on every CI run since the
-- workflow was added, never previously root-caused).
--
-- Root cause, confirmed via a temporary diagnostic step reading
-- pg_default_acl directly on the local CI stack (not guessed): the local
-- Supabase CLI's Postgres bootstrap installs, before any migration in this
-- project ever runs, two ALTER DEFAULT PRIVILEGES baselines on schema
-- public -- one FOR ROLE supabase_admin, one FOR ROLE postgres -- each
-- granting full privileges (arwdDxt on tables, X on functions, rwU on
-- sequences) to postgres, anon, authenticated AND service_role on every
-- object subsequently created by that role. This project's own migrations
-- run as `postgres`, so every table/function/sequence they create is born
-- with `anon` and `authenticated` already holding an explicit ACL entry --
-- independent of, and unaffected by, this history's existing
-- `revoke ... from public` statements (PUBLIC and a named role are
-- different grantees; revoking one never revokes the other). Direct
-- queries against the live, hosted project (has_function_privilege /
-- has_table_privilege for anon/authenticated on has_permission,
-- legacy_property_mapping, guest_requests_guest_sessions,
-- current_staff_hotel -- all four false) confirm hosted does not carry
-- this default -- this is a local-CLI-only artifact, not a live security
-- gap, and not something any migration in this history caused.
--
-- Fix: revoke, BY NAME, from anon (and authenticated / public where
-- relevant) on exactly the objects this history already documents as
-- intentionally not meant to be reachable by them -- restoring the same
-- end state locally as on hosted. Every `authenticated` grant referenced
-- below that is meant to stay is untouched (a targeted REVOKE never
-- touches a different grantee's own ACL entry). A guaranteed no-op on any
-- project that never had this local-only default in the first place
-- (hosted included) -- revoking a privilege a role never held is a no-op
-- in Postgres, not an error, so this is safe to deploy there too and keeps
-- local and hosted running the identical migration history.
begin;

-- 0011: has_permission / assign_membership_role -- authenticated keeps its
-- explicit grant from 0011; anon must not execute either.
revoke execute on function has_permission(uuid, text) from anon;
revoke execute on function assign_membership_role(uuid, uuid) from anon;

-- 20260827121800: legacy_property_mapping -- backend bookkeeping only,
-- never meant to be reachable by any client role at all.
revoke all on legacy_property_mapping from anon, authenticated, public;

-- 20260827120000: guest_requests_guest_sessions -- RLS-enabled, zero
-- policies, reachable only through the guest RPCs; not even an active,
-- entitled property_admin should hold a direct table grant.
revoke all on guest_requests_guest_sessions from anon, authenticated, public;

-- 0013: property_modules -- authenticated keeps SELECT only. INSERT/UPDATE
-- were already explicitly revoked by 0013 itself; TRIGGER/TRUNCATE/DELETE/
-- REFERENCES were never an intended grant either.
revoke trigger, truncate, delete, references on property_modules from authenticated;

-- 20260827122100: the 3 Step-6 module-local helpers, current_staff_hotel/
-- _role/_is_master, and the 2 PMS functions -- authenticated keeps its
-- explicit EXECUTE grant from that migration; anon must not execute any of
-- them.
revoke execute on function guest_requests_property_for_hotel(uuid) from anon;
revoke execute on function guest_requests_staff_roster_visible(uuid) from anon;
revoke execute on function guest_requests_staff_manage_allowed(uuid) from anon;
revoke execute on function current_staff_hotel() from anon;
revoke execute on function current_staff_role() from anon;
revoke execute on function current_staff_is_master() from anon;
revoke execute on function get_pms_integration_status(uuid) from anon;
revoke execute on function save_pms_integration(uuid, stay_source, text, text, text, text, text, text) from anon;

-- 20260827120100: guest_stay_from_token -- internal-only, called only from
-- inside other SECURITY DEFINER function bodies (an owner's own privileges
-- on its own objects are never affected by a revoke targeting a different
-- role) -- no client role, guest or staff, should ever call it directly.
revoke execute on function guest_stay_from_token(text) from anon, authenticated;

-- Forward-looking half of the fix, functions only: every function-creating
-- migration in this history already states its intended authenticated/anon
-- grant explicitly (verified across 0006, 0010, 0011, 20260827120100,
-- 20260827122100 and every other function migration here) -- this just
-- stops the local default from silently adding an extra, unintended anon/
-- authenticated grant on top of that stated intent for every FUTURE
-- function too, so this exact class of gap can't quietly reappear the next
-- time a migration adds a new SECURITY DEFINER function. Deliberately
-- scoped to FUNCTIONS only: this project's TABLES intentionally rely on
-- Supabase's standard broad anon/authenticated grant plus RLS policies as
-- the actual boundary (no migration in this history hand-grants a table),
-- so changing the table/sequence default would be a real, unwanted
-- widening of scope -- not what this fix is for.
alter default privileges in schema public revoke execute on functions from anon, authenticated;

commit;
