-- Narrow, one-off, non-destructive GATE: did
-- create_migration_auth_lookup.sql produce exactly the object it should
-- on the real legacy project -- structural/ACL checks only, distinct
-- from the full PRE-FLIGHT #14 gate (verify_readonly_credential.sql),
-- not a re-run of it. Never reads view content, never touches
-- auth.users. Every requirement is printed (for human review) AND
-- asserted via \gset + \if + \quit 1 -- run with -v ON_ERROR_STOP=1, so
-- a violation fails the calling GitHub Actions job, not just something
-- printed for a human to notice.
\set ON_ERROR_STOP on

\echo '=== connection identity (context only) ==='
select current_user, session_user, current_database();

\echo '=== 1. object type must be VIEW (relkind = v) ==='
select relkind from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'migration_readonly_auth_lookup';
select coalesce(
  (select relkind from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'migration_readonly_auth_lookup') = 'v',
  false
) as ok_is_view \gset
\if :ok_is_view
  \echo 'PASS: object is a VIEW'
\else
  \echo 'FAIL: object is missing or not a VIEW -- aborting gate'
  \quit 1
\endif

\echo '=== 2. view owner (role name only, not PII -- the admin role that ran create_migration_auth_lookup.sql) ==='
select pg_get_userbyid(c.relowner) as view_owner from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'migration_readonly_auth_lookup';

\echo '=== 3. the view exposes exactly these columns, in this order (column names only, not data) ==='
select array_agg(column_name order by ordinal_position) as lookup_view_columns
from information_schema.columns
where table_schema = 'public' and table_name = 'migration_readonly_auth_lookup';
select coalesce(
  (select array_agg(column_name order by ordinal_position)
   from information_schema.columns
   where table_schema = 'public' and table_name = 'migration_readonly_auth_lookup')
  = array['staff_profile_id','auth_user_id','email'],
  false
) as ok_columns \gset
\if :ok_columns
  \echo 'PASS: view exposes exactly (staff_profile_id, auth_user_id, email)'
\else
  \echo 'FAIL: view columns do not match exactly -- aborting gate'
  \quit 1
\endif

\echo '=== 4. security_invoker is not true ==='
select coalesce(c.reloptions::text, '') as reloptions
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname = 'migration_readonly_auth_lookup';
select coalesce(
  (select coalesce(c.reloptions::text, '') not like '%security_invoker=true%'
   from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'migration_readonly_auth_lookup'),
  false
) as ok_not_invoker \gset
\if :ok_not_invoker
  \echo 'PASS: view is not security_invoker=true'
\else
  \echo 'FAIL: view is security_invoker=true -- aborting gate'
  \quit 1
\endif

\echo '=== 5. migration_readonly holds explicit SELECT on the view ==='
select has_table_privilege('migration_readonly', 'public.migration_readonly_auth_lookup', 'SELECT') as migration_readonly_view_select;
select coalesce(has_table_privilege('migration_readonly', 'public.migration_readonly_auth_lookup', 'SELECT'), false) as ok_role_select \gset
\if :ok_role_select
  \echo 'PASS: migration_readonly has SELECT on the view'
\else
  \echo 'FAIL: migration_readonly does NOT have SELECT on the view -- aborting gate'
  \quit 1
\endif

\echo '=== 6. PUBLIC does NOT hold SELECT on the view (grantee = 0 is the ACL convention for PUBLIC) ==='
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
  \quit 1
\endif

\echo '=== 7. no grantee other than migration_readonly or the view owner holds SELECT on the view ==='
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
  \quit 1
\endif

\echo '=== 8. migration_readonly does not hold SELECT WITH GRANT OPTION on the view ==='
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
  \quit 1
\endif

\echo '=== 9. migration_readonly still has no USAGE on schema auth ==='
select has_schema_privilege(current_user, 'auth', 'USAGE') as auth_schema_usage;
select coalesce(not has_schema_privilege(current_user, 'auth', 'USAGE'), false) as ok_no_auth_usage \gset
\if :ok_no_auth_usage
  \echo 'PASS: no USAGE privilege on schema auth'
\else
  \echo 'FAIL: migration_readonly has USAGE on schema auth -- aborting gate'
  \quit 1
\endif

\echo '=== 10. no write privilege was added to the role on the 7 migrated tables -- every column below must be false ==='
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
  \quit 1
\endif

\echo ''
\echo '=== AUTH LOOKUP VIEW CREATION: STRUCTURAL VERIFICATION -- ALL CHECKS PASSED ==='
