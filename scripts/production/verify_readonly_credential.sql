-- One-off, non-destructive verification of the migration_readonly
-- credential on the REAL legacy Housekeeping project. Metadata and
-- privilege introspection only -- no row content is ever read except a
-- handful of count(*)/array_agg(column_name) results, none of them PII.
-- No write is attempted.
--
-- Rewritten for the PRE-FLIGHT #14 view-based redesign: the original
-- version of this file checked has_column_privilege() on auth.users
-- directly (id/email true, encrypted_password false) -- that assumed
-- the old column-grant design. migration_readonly now holds NO
-- privilege on the auth schema at all (see setup_readonly_role.sql /
-- create_migration_auth_lookup.sql); this file no longer issues any
-- query against auth.users, direct or otherwise. It instead verifies
-- the replacement mechanism: schema-auth USAGE is absent, the lookup
-- view exists with exactly the columns it should, grants on the view
-- are scoped to migration_readonly only, the view is not
-- security_invoker (so it can read auth.users as its owner without
-- migration_readonly needing to), and -- the actual end-to-end proof --
-- migration_readonly can resolve, for every real-hotel staff member,
-- an expected lookup row with a non-null email, entirely through
-- counts, never printing the email/name itself.
\set ON_ERROR_STOP on

\echo '--- 1. identity: which role is actually connected ---'
select current_user, session_user, current_database();

\echo '--- 2. source confirmation: the real hotel this migration targets must be present here (count expected = 1) ---'
select count(*) as palazzo_veneziano_present from hotels where id = '25b00bec-1602-46e9-bf52-a4913ebb5bdb';

\echo '--- 3. session-level read-only enforcement (must be "on") ---'
select current_setting('transaction_read_only') as transaction_read_only;

\echo '--- 4. SELECT privilege on all 7 migrated tables (every column must be true) ---'
select
  has_table_privilege(current_user, 'public.hotels', 'SELECT') as hotels_select,
  has_table_privilege(current_user, 'public.staff_profiles', 'SELECT') as staff_profiles_select,
  has_table_privilege(current_user, 'public.rooms', 'SELECT') as rooms_select,
  has_table_privilege(current_user, 'public.stays', 'SELECT') as stays_select,
  has_table_privilege(current_user, 'public.request_categories', 'SELECT') as request_categories_select,
  has_table_privilege(current_user, 'public.request_types', 'SELECT') as request_types_select,
  has_table_privilege(current_user, 'public.guest_requests', 'SELECT') as guest_requests_select;

\echo '--- 5. write privileges (INSERT/UPDATE/DELETE/TRUNCATE) on all 7 tables -- every column below must be false ---'
select
  has_table_privilege(current_user, 'public.hotels', 'INSERT') as hotels_insert,
  has_table_privilege(current_user, 'public.hotels', 'UPDATE') as hotels_update,
  has_table_privilege(current_user, 'public.hotels', 'DELETE') as hotels_delete,
  has_table_privilege(current_user, 'public.hotels', 'TRUNCATE') as hotels_truncate,
  has_table_privilege(current_user, 'public.staff_profiles', 'INSERT') as staff_profiles_insert,
  has_table_privilege(current_user, 'public.staff_profiles', 'UPDATE') as staff_profiles_update,
  has_table_privilege(current_user, 'public.staff_profiles', 'DELETE') as staff_profiles_delete,
  has_table_privilege(current_user, 'public.staff_profiles', 'TRUNCATE') as staff_profiles_truncate,
  has_table_privilege(current_user, 'public.rooms', 'INSERT') as rooms_insert,
  has_table_privilege(current_user, 'public.rooms', 'UPDATE') as rooms_update,
  has_table_privilege(current_user, 'public.rooms', 'DELETE') as rooms_delete,
  has_table_privilege(current_user, 'public.rooms', 'TRUNCATE') as rooms_truncate,
  has_table_privilege(current_user, 'public.stays', 'INSERT') as stays_insert,
  has_table_privilege(current_user, 'public.stays', 'UPDATE') as stays_update,
  has_table_privilege(current_user, 'public.stays', 'DELETE') as stays_delete,
  has_table_privilege(current_user, 'public.stays', 'TRUNCATE') as stays_truncate,
  has_table_privilege(current_user, 'public.request_categories', 'INSERT') as request_categories_insert,
  has_table_privilege(current_user, 'public.request_categories', 'UPDATE') as request_categories_update,
  has_table_privilege(current_user, 'public.request_categories', 'DELETE') as request_categories_delete,
  has_table_privilege(current_user, 'public.request_categories', 'TRUNCATE') as request_categories_truncate,
  has_table_privilege(current_user, 'public.request_types', 'INSERT') as request_types_insert,
  has_table_privilege(current_user, 'public.request_types', 'UPDATE') as request_types_update,
  has_table_privilege(current_user, 'public.request_types', 'DELETE') as request_types_delete,
  has_table_privilege(current_user, 'public.request_types', 'TRUNCATE') as request_types_truncate,
  has_table_privilege(current_user, 'public.guest_requests', 'INSERT') as guest_requests_insert,
  has_table_privilege(current_user, 'public.guest_requests', 'UPDATE') as guest_requests_update,
  has_table_privilege(current_user, 'public.guest_requests', 'DELETE') as guest_requests_delete,
  has_table_privilege(current_user, 'public.guest_requests', 'TRUNCATE') as guest_requests_truncate;

\echo '--- 6. no privilege on the auth schema at all (must be false -- this is the replacement for the old auth.users column-privilege check) ---'
select has_schema_privilege(current_user, 'auth', 'USAGE') as auth_schema_usage;

\echo '--- 7. public.migration_readonly_auth_lookup exists (count expected = 1) ---'
select count(*) as lookup_view_exists from pg_views where schemaname = 'public' and viewname = 'migration_readonly_auth_lookup';

\echo '--- 8. the view exposes exactly these columns, in this order (column names only, not data) ---'
select array_agg(column_name order by ordinal_position) as lookup_view_columns
from information_schema.columns
where table_schema = 'public' and table_name = 'migration_readonly_auth_lookup';
-- must be exactly {staff_profile_id,auth_user_id,email}

\echo '--- 9. grants on the view: migration_readonly SELECT only, nothing else (any PUBLIC row here would be a leak) ---'
select grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public' and table_name = 'migration_readonly_auth_lookup'
order by grantee, privilege_type;
-- must be exactly one row: migration_readonly / SELECT

\echo '--- 10. the view is not security_invoker=true (it must run as its owner, not as migration_readonly, to read auth.users) ---'
select coalesce(c.reloptions::text, '') not like '%security_invoker=true%' as security_invoker_not_true
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname = 'migration_readonly_auth_lookup';

\echo '--- 11. no superuser/admin-level privilege on this role ---'
select rolsuper, rolcreaterole, rolcreatedb, rolbypassrls from pg_roles where rolname = current_user;

\echo '--- 12. end-to-end proof, as migration_readonly, with zero auth-schema privilege: every real-hotel staff member resolves to a lookup row with a non-null email (counts only, no email/name ever printed) ---'
select
  (select count(*) from staff_profiles where hotel_id = '25b00bec-1602-46e9-bf52-a4913ebb5bdb') as staff_total,
  (select count(*) from staff_profiles sp where sp.hotel_id = '25b00bec-1602-46e9-bf52-a4913ebb5bdb'
     and exists (select 1 from public.migration_readonly_auth_lookup mal where mal.staff_profile_id = sp.id and mal.email is not null)
  ) as staff_with_lookup_email,
  (select count(*) from staff_profiles sp where sp.hotel_id = '25b00bec-1602-46e9-bf52-a4913ebb5bdb'
     and not exists (select 1 from public.migration_readonly_auth_lookup mal where mal.staff_profile_id = sp.id and mal.email is not null)
  ) as staff_missing_lookup_email;
-- staff_with_lookup_email must equal staff_total; staff_missing_lookup_email must be 0
