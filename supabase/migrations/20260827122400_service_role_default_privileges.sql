-- Fase 2 Step 8 — fixes a systemic, project-level gap found via live E2E
-- testing: service_role has ZERO basic CRUD (SELECT/INSERT/UPDATE/DELETE)
-- on every table in the public schema on the shared Hotsflow project
-- (confirmed via information_schema.role_table_grants: 23 of 23 tables
-- affected). service_role is meant to bypass RLS by design (BYPASSRLS),
-- but BYPASSRLS only skips row-level POLICIES — it does not substitute for
-- the underlying GRANT-based table privilege system, which is what was
-- actually missing here.
--
-- This is not something any Fase 2 migration caused (none of them touch
-- service_role privileges — verified against the full migration set) and
-- not specific to staff_profiles either. It's a one-time project
-- provisioning gap: on a normally-created Supabase project, every table
-- gets these grants automatically via a schema-level ALTER DEFAULT
-- PRIVILEGES set up at project creation time; that default apparently
-- didn't carry over (or wasn't yet in effect) when this project's tables
-- were first created by running the migration history against it.
--
-- Fixes it two ways: (1) grants on every EXISTING object right now, so
-- every Edge Function that uses the service-role client (create-staff-
-- account, sync-pms-stays, notify-new-request, and any future one) works
-- immediately; (2) ALTER DEFAULT PRIVILEGES, so this doesn't quietly
-- recur for a table created by a future migration.
begin;

grant usage on schema public to service_role;
grant all privileges on all tables in schema public to service_role;
grant all privileges on all sequences in schema public to service_role;
grant all privileges on all functions in schema public to service_role;

alter default privileges in schema public grant all privileges on tables to service_role;
alter default privileges in schema public grant all privileges on sequences to service_role;
alter default privileges in schema public grant all privileges on functions to service_role;

commit;
