-- Production migration -- creates (or rotates the password of) a
-- dedicated, minimally-privileged role for the read-only legacy
-- connection used by the production migration workflow.
--
-- NOT for the disposable E2E test alone -- this is the real setup script
-- for the real legacy project too, but per explicit instruction it must
-- NOT be run against the real legacy project until separately authorized.
-- Never commit a real password anywhere: pass it in at runtime.
--
-- Usage: psql "$LEGACY_ADMIN_DB_URL" -v role_password='...' -f setup_readonly_role.sql
--
-- Two independent layers of read-only enforcement, deliberately not just
-- one:
--   1. Grants: SELECT only, on exactly the 7 tables the migration reads
--      row data from, plus two columns (id, email) of auth.users --
--      nothing else, no INSERT/UPDATE/DELETE anywhere, ever.
--   2. Role-level session default: every session that logs in as this
--      role gets default_transaction_read_only = on automatically, so
--      even a role mis-grant can't produce a write -- Postgres itself
--      rejects any DML at the engine level before privileges are even
--      checked.
--
-- Deliberately NOT a `do $$ ... $$` block for the password-setting logic:
-- psql's `:'var'` substitution does not happen inside dollar-quoted
-- bodies (a real bug hit earlier in this project, in 10_migrate_hotel.sql's
-- first draft) -- so this uses plain top-level SQL + \gset + \if/\endif
-- instead, where substitution works correctly.
\set ON_ERROR_STOP on

select exists(select 1 from pg_roles where rolname = 'migration_readonly') as role_exists \gset

\if :role_exists
  \echo 'Role migration_readonly already exists -- rotating password only.'
  alter role migration_readonly with password :'role_password';
\else
  \echo 'Creating role migration_readonly.'
  create role migration_readonly with login password :'role_password';
\endif

alter role migration_readonly set default_transaction_read_only = on;

-- Data tables: full-row SELECT. These are exactly the tables
-- 02_export_legacy.sql reads from -- nothing broader.
grant select on
  hotels, staff_profiles, rooms, stays, request_categories, request_types, guest_requests
to migration_readonly;

-- auth.users: column-level grant, (id, email) only. `id` is needed only
-- to join staff_profiles.auth_user_id = auth.users.id (Postgres requires
-- the column privilege even when a joined column never appears in the
-- final SELECT list); `email` is the only auth.users value the Auth
-- migration phase actually needs -- passwords are never carried over
-- from legacy (a fresh, deterministic value is generated at creation
-- time instead, same approach already validated in the rehearsal). No
-- other auth.users column (encrypted_password, phone,
-- raw_user_meta_data, confirmed_at, ...) is ever granted or read.
grant select (id, email) on auth.users to migration_readonly;

\echo '--- verification: role must have zero write privileges on any migrated table ---'
select
  has_table_privilege('migration_readonly', 'public.hotels', 'INSERT') as hotels_insert,
  has_table_privilege('migration_readonly', 'public.staff_profiles', 'INSERT') as staff_profiles_insert,
  has_table_privilege('migration_readonly', 'public.rooms', 'INSERT') as rooms_insert,
  has_table_privilege('migration_readonly', 'public.stays', 'INSERT') as stays_insert,
  has_table_privilege('migration_readonly', 'public.request_categories', 'INSERT') as request_categories_insert,
  has_table_privilege('migration_readonly', 'public.request_types', 'INSERT') as request_types_insert,
  has_table_privilege('migration_readonly', 'public.guest_requests', 'INSERT') as guest_requests_insert;
-- every column above must be false
