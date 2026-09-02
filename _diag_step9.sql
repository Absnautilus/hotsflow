\echo '--- current_user / session_user at diagnostic time ---'
select current_user, session_user;

\echo '--- owner of has_permission(uuid, text) ---'
select p.proname, r.rolname as owner
from pg_proc p join pg_roles r on r.oid = p.proowner
where p.proname = 'has_permission';

\echo '--- raw ACL on has_permission(uuid, text) ---'
select p.proname, p.proacl
from pg_proc p
where p.proname = 'has_permission';

\echo '--- raw ACL on staff_profiles table ---'
select c.relname, c.relacl, r.rolname as owner
from pg_class c join pg_roles r on r.oid = c.relowner
where c.relname = 'staff_profiles';

\echo '--- pg_default_acl entries for schema public, all roles ---'
select gr.rolname as defacl_for_role, n.nspname, da.defaclobjtype, da.defaclacl
from pg_default_acl da
join pg_namespace n on n.oid = da.defaclnamespace
join pg_roles gr on gr.oid = da.defaclrole
where n.nspname = 'public';

\echo '--- roles present ---'
select rolname, rolsuper, rolcreaterole, rolcreatedb from pg_roles where rolname in ('postgres','supabase_admin','anon','authenticated','service_role','supabase_auth_admin') order by rolname;

\echo '--- has_permission EXECUTE checks ---'
select has_function_privilege('anon', 'has_permission(uuid, text)', 'EXECUTE') as anon_exec,
       has_function_privilege('authenticated', 'has_permission(uuid, text)', 'EXECUTE') as authenticated_exec,
       has_function_privilege('service_role', 'has_permission(uuid, text)', 'EXECUTE') as service_role_exec;

\echo '--- service_role staff_profiles checks ---'
select has_table_privilege('service_role','public.staff_profiles','SELECT') as svc_select,
       has_table_privilege('service_role','public.staff_profiles','INSERT') as svc_insert;
