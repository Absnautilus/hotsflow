-- One-off, non-destructive verification of the migration_readonly
-- credential on the REAL legacy Housekeeping project. Metadata and
-- privilege introspection only -- no row content is ever read except a
-- single count(*), which is a number, not PII. No write is attempted.
--
-- Reuses the exact has_table_privilege()/has_column_privilege() pattern
-- already validated in setup_readonly_role.sql and the E2E mechanism --
-- just extended to full coverage (all 4 write privilege types, all 7
-- tables) since this is the one real check against the real credential,
-- not a repeated automated one.
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

\echo '--- 6. auth.users column-level privilege: id/email must be true, encrypted_password must be false ---'
select
  has_column_privilege(current_user, 'auth.users', 'id', 'SELECT') as id_select,
  has_column_privilege(current_user, 'auth.users', 'email', 'SELECT') as email_select,
  has_column_privilege(current_user, 'auth.users', 'encrypted_password', 'SELECT') as encrypted_password_select;

\echo '--- 7. no superuser/admin-level privilege ---'
select rolsuper, rolcreaterole, rolcreatedb, rolbypassrls from pg_roles where rolname = current_user;
