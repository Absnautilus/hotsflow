-- One-off, non-destructive GATE for the migration_readonly credential on
-- the REAL legacy Housekeeping project. Every requirement below is both
-- printed (for human review) AND asserted: a violated requirement makes
-- this script fail via a DO $$ ... RAISE EXCEPTION $$; block, so under
-- -v ON_ERROR_STOP=1 psql exits non-zero and the calling workflow fails
-- the GitHub Actions job -- this is a gate, not a report a human has to
-- read carefully to catch a problem.
--
-- NOT `\quit <n>`: an earlier version of this file used `\quit 1` on
-- failure. The real run of the sibling script
-- (verify_auth_lookup_view_created.sql, workflow run 33878792799)
-- against the real legacy project proved `\quit <n>` does not set
-- psql's process exit code in the psql client this runner has -- the
-- job reported success even though the script had printed FAIL. RAISE
-- EXCEPTION inside a DO block is pure control flow, not a data write,
-- so it is compatible with a read-only session
-- (default_transaction_read_only = on) -- this was the real, checked
-- concern that ruled out DO/RAISE EXCEPTION when this file was first
-- written, and it turned out to be unfounded: RAISE never touches heap
-- or index data, so the read-only-transaction guard never blocks it.
-- \set ON_ERROR_STOP on then makes psql itself exit non-zero on the
-- resulting SQL error, the same way it already did for every other real
-- error hit earlier in this engagement (the "permission denied for
-- schema auth" and sql_identifier[]/text[] cast errors both correctly
-- failed their jobs this way).
--
-- Metadata and privilege introspection only -- no row content is ever
-- read except a handful of count(*)/array_agg(column_name) results,
-- none of them PII.
--
-- migration_readonly holds NO privilege on the auth schema at all (see
-- setup_readonly_role.sql / create_migration_auth_lookup.sql) -- no
-- query in this file ever touches auth.users, direct or otherwise.
--
-- PUBLIC-grant check: has_table_privilege() does not offer a documented,
-- unambiguous way to ask "does the PUBLIC pseudo-role itself hold this
-- privilege" (passing the literal string 'public' would be resolved as
-- an actual role named "public", which does not exist here, not as the
-- PUBLIC pseudo-role) -- so that check is NOT used for the negative
-- (PUBLIC) side. Instead this reads pg_class.relacl directly via
-- aclexplode(): Postgres's own documented convention is that an ACL
-- entry with grantee OID = 0 means "granted to PUBLIC" (this is exactly
-- what \dp/\z render as "=X/owner" with no role name) -- unambiguous,
-- catalog-level, not dependent on any function's argument-parsing
-- special cases. has_table_privilege('migration_readonly', ...) IS used
-- for the positive side (a real role name, not the PUBLIC pseudo-role,
-- so no ambiguity there).
\set ON_ERROR_STOP on

\echo '=== 1. identity: current_user must be migration_readonly ==='
select current_user, session_user, current_database();
select coalesce(current_user = 'migration_readonly', false) as ok_role \gset
\if :ok_role
  \echo 'PASS: current_user = migration_readonly'
\else
  \echo 'FAIL: current_user is NOT migration_readonly -- aborting gate'
  DO $$
  BEGIN
    RAISE EXCEPTION 'Gate failed: current_user is NOT migration_readonly -- aborting gate';
  END
  $$;
\endif

\echo '=== 2. source confirmation: the real hotel must be present (count = 1) ==='
select count(*) as palazzo_veneziano_present from hotels where id = '25b00bec-1602-46e9-bf52-a4913ebb5bdb';
select coalesce((select count(*) from hotels where id = '25b00bec-1602-46e9-bf52-a4913ebb5bdb') = 1, false) as ok_hotel \gset
\if :ok_hotel
  \echo 'PASS: real hotel present exactly once'
\else
  \echo 'FAIL: real hotel not present exactly once -- aborting gate'
  DO $$
  BEGIN
    RAISE EXCEPTION 'Gate failed: real hotel not present exactly once -- aborting gate';
  END
  $$;
\endif

\echo '=== 3. session-level read-only enforcement must be "on" ==='
select current_setting('transaction_read_only') as transaction_read_only;
select coalesce(current_setting('transaction_read_only') = 'on', false) as ok_readonly \gset
\if :ok_readonly
  \echo 'PASS: transaction_read_only = on'
\else
  \echo 'FAIL: transaction_read_only is NOT on -- aborting gate'
  DO $$
  BEGIN
    RAISE EXCEPTION 'Gate failed: transaction_read_only is NOT on -- aborting gate';
  END
  $$;
\endif

\echo '=== 4. SELECT privilege on all 7 migrated tables (every column must be true) ==='
select
  has_table_privilege(current_user, 'public.hotels', 'SELECT') as hotels_select,
  has_table_privilege(current_user, 'public.staff_profiles', 'SELECT') as staff_profiles_select,
  has_table_privilege(current_user, 'public.rooms', 'SELECT') as rooms_select,
  has_table_privilege(current_user, 'public.stays', 'SELECT') as stays_select,
  has_table_privilege(current_user, 'public.request_categories', 'SELECT') as request_categories_select,
  has_table_privilege(current_user, 'public.request_types', 'SELECT') as request_types_select,
  has_table_privilege(current_user, 'public.guest_requests', 'SELECT') as guest_requests_select;
select coalesce(
  has_table_privilege(current_user, 'public.hotels', 'SELECT')
  and has_table_privilege(current_user, 'public.staff_profiles', 'SELECT')
  and has_table_privilege(current_user, 'public.rooms', 'SELECT')
  and has_table_privilege(current_user, 'public.stays', 'SELECT')
  and has_table_privilege(current_user, 'public.request_categories', 'SELECT')
  and has_table_privilege(current_user, 'public.request_types', 'SELECT')
  and has_table_privilege(current_user, 'public.guest_requests', 'SELECT'),
  false
) as ok_select_all \gset
\if :ok_select_all
  \echo 'PASS: SELECT granted on all 7 tables'
\else
  \echo 'FAIL: SELECT missing on at least one of the 7 tables -- aborting gate'
  DO $$
  BEGIN
    RAISE EXCEPTION 'Gate failed: SELECT missing on at least one of the 7 tables -- aborting gate';
  END
  $$;
\endif

\echo '=== 5. write privileges (INSERT/UPDATE/DELETE/TRUNCATE) on all 7 tables -- every column below must be false ==='
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
select coalesce(not (
     has_table_privilege(current_user, 'public.hotels', 'INSERT')
  or has_table_privilege(current_user, 'public.hotels', 'UPDATE')
  or has_table_privilege(current_user, 'public.hotels', 'DELETE')
  or has_table_privilege(current_user, 'public.hotels', 'TRUNCATE')
  or has_table_privilege(current_user, 'public.staff_profiles', 'INSERT')
  or has_table_privilege(current_user, 'public.staff_profiles', 'UPDATE')
  or has_table_privilege(current_user, 'public.staff_profiles', 'DELETE')
  or has_table_privilege(current_user, 'public.staff_profiles', 'TRUNCATE')
  or has_table_privilege(current_user, 'public.rooms', 'INSERT')
  or has_table_privilege(current_user, 'public.rooms', 'UPDATE')
  or has_table_privilege(current_user, 'public.rooms', 'DELETE')
  or has_table_privilege(current_user, 'public.rooms', 'TRUNCATE')
  or has_table_privilege(current_user, 'public.stays', 'INSERT')
  or has_table_privilege(current_user, 'public.stays', 'UPDATE')
  or has_table_privilege(current_user, 'public.stays', 'DELETE')
  or has_table_privilege(current_user, 'public.stays', 'TRUNCATE')
  or has_table_privilege(current_user, 'public.request_categories', 'INSERT')
  or has_table_privilege(current_user, 'public.request_categories', 'UPDATE')
  or has_table_privilege(current_user, 'public.request_categories', 'DELETE')
  or has_table_privilege(current_user, 'public.request_categories', 'TRUNCATE')
  or has_table_privilege(current_user, 'public.request_types', 'INSERT')
  or has_table_privilege(current_user, 'public.request_types', 'UPDATE')
  or has_table_privilege(current_user, 'public.request_types', 'DELETE')
  or has_table_privilege(current_user, 'public.request_types', 'TRUNCATE')
  or has_table_privilege(current_user, 'public.guest_requests', 'INSERT')
  or has_table_privilege(current_user, 'public.guest_requests', 'UPDATE')
  or has_table_privilege(current_user, 'public.guest_requests', 'DELETE')
  or has_table_privilege(current_user, 'public.guest_requests', 'TRUNCATE')
), false) as ok_write_none \gset
\if :ok_write_none
  \echo 'PASS: no write privilege on any of the 7 tables'
\else
  \echo 'FAIL: at least one write privilege is granted on a migrated table -- aborting gate'
  DO $$
  BEGIN
    RAISE EXCEPTION 'Gate failed: at least one write privilege is granted on a migrated table -- aborting gate';
  END
  $$;
\endif

\echo '=== 6. no privilege on the auth schema at all (must be false) ==='
select has_schema_privilege(current_user, 'auth', 'USAGE') as auth_schema_usage;
select coalesce(not has_schema_privilege(current_user, 'auth', 'USAGE'), false) as ok_no_auth_usage \gset
\if :ok_no_auth_usage
  \echo 'PASS: no USAGE privilege on schema auth'
\else
  \echo 'FAIL: migration_readonly has USAGE on schema auth -- aborting gate'
  DO $$
  BEGIN
    RAISE EXCEPTION 'Gate failed: migration_readonly has USAGE on schema auth -- aborting gate';
  END
  $$;
\endif

\echo '=== 7. public.migration_readonly_auth_lookup exists (count must be 1) ==='
select count(*) as lookup_view_exists from pg_views where schemaname = 'public' and viewname = 'migration_readonly_auth_lookup';
select coalesce((select count(*) from pg_views where schemaname = 'public' and viewname = 'migration_readonly_auth_lookup') = 1, false) as ok_view_exists \gset
\if :ok_view_exists
  \echo 'PASS: lookup view exists exactly once'
\else
  \echo 'FAIL: lookup view missing or duplicated -- aborting gate'
  DO $$
  BEGIN
    RAISE EXCEPTION 'Gate failed: lookup view missing or duplicated -- aborting gate';
  END
  $$;
\endif

\echo '=== 8. the view exposes exactly these columns, in this order (column names only, not data) ==='
select array_agg(column_name order by ordinal_position) as lookup_view_columns
from information_schema.columns
where table_schema = 'public' and table_name = 'migration_readonly_auth_lookup';
select coalesce(
  (select array_agg(column_name::text order by ordinal_position)
   from information_schema.columns
   where table_schema = 'public' and table_name = 'migration_readonly_auth_lookup')
  = array['staff_profile_id','auth_user_id','email']::text[],
  false
) as ok_columns \gset
\if :ok_columns
  \echo 'PASS: view exposes exactly (staff_profile_id, auth_user_id, email)'
\else
  \echo 'FAIL: view columns do not match exactly (staff_profile_id, auth_user_id, email) -- aborting gate'
  DO $$
  BEGIN
    RAISE EXCEPTION 'Gate failed: view columns do not match exactly (staff_profile_id, auth_user_id, email) -- aborting gate';
  END
  $$;
\endif

\echo '=== 9. migration_readonly holds SELECT on the view ==='
select has_table_privilege('migration_readonly', 'public.migration_readonly_auth_lookup', 'SELECT') as migration_readonly_view_select;
select coalesce(has_table_privilege('migration_readonly', 'public.migration_readonly_auth_lookup', 'SELECT'), false) as ok_role_select \gset
\if :ok_role_select
  \echo 'PASS: migration_readonly has SELECT on the view'
\else
  \echo 'FAIL: migration_readonly does NOT have SELECT on the view -- aborting gate'
  DO $$
  BEGIN
    RAISE EXCEPTION 'Gate failed: migration_readonly does NOT have SELECT on the view -- aborting gate';
  END
  $$;
\endif

\echo '=== 10. PUBLIC does NOT hold SELECT on the view -- catalog-level check, not has_table_privilege(''public'', ...) ==='
\echo '--- (grantee = 0 is Postgres''s own ACL convention for the PUBLIC pseudo-role -- see pg_class.relacl / aclexplode()) ---'
select
  case when a.grantee = 0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end as grantee,
  a.privilege_type
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) as a
where n.nspname = 'public' and c.relname = 'migration_readonly_auth_lookup'
order by grantee, a.privilege_type;
select coalesce(
  not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) as a
    where n.nspname = 'public' and c.relname = 'migration_readonly_auth_lookup'
      and a.grantee = 0
      and a.privilege_type = 'SELECT'
  ),
  false
) as ok_no_public_select \gset
\if :ok_no_public_select
  \echo 'PASS: no ACL entry grants SELECT to PUBLIC on the view'
\else
  \echo 'FAIL: PUBLIC holds SELECT on the view -- aborting gate'
  DO $$
  BEGIN
    RAISE EXCEPTION 'Gate failed: PUBLIC holds SELECT on the view -- aborting gate';
  END
  $$;
\endif

\echo '=== 11. no grantee other than migration_readonly or the view owner holds SELECT on the view ==='
\echo '--- (owner is expected -- CREATE VIEW grants the owner full rights by default; anyone else here would be a leak) ---'
select
  pg_get_userbyid(a.grantee) as grantee,
  a.privilege_type
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) as a
where n.nspname = 'public' and c.relname = 'migration_readonly_auth_lookup'
  and a.privilege_type = 'SELECT'
  and a.grantee <> 0
  and a.grantee not in (
    coalesce((select oid from pg_roles where rolname = 'migration_readonly'), -1),
    c.relowner
  )
order by grantee;
select coalesce(
  not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) as a
    where n.nspname = 'public' and c.relname = 'migration_readonly_auth_lookup'
      and a.privilege_type = 'SELECT'
      and a.grantee <> 0
      and a.grantee not in (
        coalesce((select oid from pg_roles where rolname = 'migration_readonly'), -1),
        c.relowner
      )
  ),
  false
) as ok_no_extra_select_grantees \gset
\if :ok_no_extra_select_grantees
  \echo 'PASS: no grantee other than migration_readonly/owner holds SELECT on the view'
\else
  \echo 'FAIL: an unexpected role holds SELECT on the view -- aborting gate'
  DO $$
  BEGIN
    RAISE EXCEPTION 'Gate failed: an unexpected role holds SELECT on the view -- aborting gate';
  END
  $$;
\endif

\echo '=== 12. migration_readonly does not hold SELECT WITH GRANT OPTION on the view ==='
select
  a.is_grantable as migration_readonly_select_grantable
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) as a
where n.nspname = 'public' and c.relname = 'migration_readonly_auth_lookup'
  and a.privilege_type = 'SELECT'
  and a.grantee = (select oid from pg_roles where rolname = 'migration_readonly');
select coalesce(
  not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) as a
    where n.nspname = 'public' and c.relname = 'migration_readonly_auth_lookup'
      and a.privilege_type = 'SELECT'
      and a.grantee = (select oid from pg_roles where rolname = 'migration_readonly')
      and a.is_grantable = true
  ),
  false
) as ok_no_grant_option \gset
\if :ok_no_grant_option
  \echo 'PASS: migration_readonly does not have WITH GRANT OPTION on the view'
\else
  \echo 'FAIL: migration_readonly holds WITH GRANT OPTION on the view -- aborting gate'
  DO $$
  BEGIN
    RAISE EXCEPTION 'Gate failed: migration_readonly holds WITH GRANT OPTION on the view -- aborting gate';
  END
  $$;
\endif

\echo '=== 13. the view is not security_invoker=true (it must run as its owner, not as migration_readonly, to read auth.users) ==='
select coalesce(c.reloptions::text, '') as reloptions
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname = 'migration_readonly_auth_lookup';
select coalesce(
  (select coalesce(c.reloptions::text, '') not like '%security_invoker=true%'
   from pg_class c
   join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'migration_readonly_auth_lookup'),
  false
) as ok_not_invoker \gset
\if :ok_not_invoker
  \echo 'PASS: view is not security_invoker=true'
\else
  \echo 'FAIL: view is security_invoker=true -- aborting gate'
  DO $$
  BEGIN
    RAISE EXCEPTION 'Gate failed: view is security_invoker=true -- aborting gate';
  END
  $$;
\endif

\echo '=== 14. no superuser/admin-level role attribute ==='
select rolsuper, rolcreaterole, rolcreatedb, rolbypassrls from pg_roles where rolname = current_user;
select coalesce(
  not (
    (select rolsuper from pg_roles where rolname = current_user)
    or (select rolcreaterole from pg_roles where rolname = current_user)
    or (select rolcreatedb from pg_roles where rolname = current_user)
    or (select rolbypassrls from pg_roles where rolname = current_user)
  ),
  false
) as ok_role_attrs \gset
\if :ok_role_attrs
  \echo 'PASS: no superuser/createrole/createdb/bypassrls'
\else
  \echo 'FAIL: role has a superuser-adjacent attribute -- aborting gate'
  DO $$
  BEGIN
    RAISE EXCEPTION 'Gate failed: role has a superuser-adjacent attribute -- aborting gate';
  END
  $$;
\endif

\echo '=== 15. end-to-end proof: every real-hotel staff member resolves to a lookup row with a non-null email (counts only, no email/name ever printed) ==='
select
  (select count(*) from staff_profiles where hotel_id = '25b00bec-1602-46e9-bf52-a4913ebb5bdb') as staff_total,
  (select count(*) from staff_profiles sp where sp.hotel_id = '25b00bec-1602-46e9-bf52-a4913ebb5bdb'
     and exists (select 1 from public.migration_readonly_auth_lookup mal where mal.staff_profile_id = sp.id and mal.email is not null)
  ) as staff_with_lookup_email,
  (select count(*) from staff_profiles sp where sp.hotel_id = '25b00bec-1602-46e9-bf52-a4913ebb5bdb'
     and not exists (select 1 from public.migration_readonly_auth_lookup mal where mal.staff_profile_id = sp.id and mal.email is not null)
  ) as staff_missing_lookup_email;
select coalesce(
  (select count(*) from staff_profiles where hotel_id = '25b00bec-1602-46e9-bf52-a4913ebb5bdb')
  =
  (select count(*) from staff_profiles sp where sp.hotel_id = '25b00bec-1602-46e9-bf52-a4913ebb5bdb'
     and exists (select 1 from public.migration_readonly_auth_lookup mal where mal.staff_profile_id = sp.id and mal.email is not null))
  and
  (select count(*) from staff_profiles sp where sp.hotel_id = '25b00bec-1602-46e9-bf52-a4913ebb5bdb'
     and not exists (select 1 from public.migration_readonly_auth_lookup mal where mal.staff_profile_id = sp.id and mal.email is not null)) = 0,
  false
) as ok_lookup_complete \gset
\if :ok_lookup_complete
  \echo 'PASS: staff_total = staff_with_lookup_email and staff_missing_lookup_email = 0'
\else
  \echo 'FAIL: not every real-hotel staff member resolves to a lookup row with a non-null email -- aborting gate'
  DO $$
  BEGIN
    RAISE EXCEPTION 'Gate failed: not every real-hotel staff member resolves to a lookup row with a non-null email -- aborting gate';
  END
  $$;
\endif

\echo ''
\echo '=== PRE-FLIGHT #14 GATE: ALL CHECKS PASSED ==='
