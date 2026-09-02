\echo '--- staff_profiles: has_table_privilege per privilege for service_role ---'
select priv, has_table_privilege('service_role', 'public.staff_profiles', priv) as has_it
from unnest(array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) as priv;

\echo '--- staff_profiles raw relacl ---'
select relacl from pg_class where relname = 'staff_profiles';

\echo '--- pms_integrations: has_table_privilege per privilege for service_role ---'
select priv, has_table_privilege('service_role', 'public.pms_integrations', priv) as has_it
from unnest(array['SELECT','INSERT','UPDATE','DELETE']) as priv;

\echo '--- pms_integrations raw relacl ---'
select relacl from pg_class where relname = 'pms_integrations';

\echo '--- ALL public tables: per-privilege has_table_privilege matrix for service_role ---'
select c.relname,
  has_table_privilege('service_role', c.oid, 'SELECT') as sel,
  has_table_privilege('service_role', c.oid, 'INSERT') as ins,
  has_table_privilege('service_role', c.oid, 'UPDATE') as upd,
  has_table_privilege('service_role', c.oid, 'DELETE') as del
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r'
order by c.relname;

\echo '--- service_role role attributes ---'
select rolname, rolsuper, rolbypassrls, rolcanlogin from pg_roles where rolname = 'service_role';

\echo '--- is postgres a member of service_role, or vice versa? ---'
select r.rolname as role, m.rolname as member_of
from pg_auth_members am
join pg_roles r on r.oid = am.roleid
join pg_roles m on m.oid = am.member
where r.rolname = 'service_role' or m.rolname = 'service_role';
