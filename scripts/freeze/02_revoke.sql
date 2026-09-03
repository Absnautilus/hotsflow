-- Freeze — REVOKE exactly what's in the snapshot (table 01), nothing more,
-- nothing assumed. Dynamic per-row REVOKE rather than a blanket statement,
-- so this only ever touches privileges actually confirmed present.
do $$
declare
  r record;
begin
  for r in select * from _freeze_acl_snapshot loop
    if r.level = 'TABLE' then
      execute format('revoke %s on table %I from %I', r.privilege, r.table_name, r.grantee);
    else
      execute format('revoke %s (%I) on table %I from %I', r.privilege, r.column_name, r.table_name, r.grantee);
    end if;
  end loop;
end $$;

\echo '--- post-REVOKE: remaining write grants on the frozen tables (expect 0 rows) ---'
select a.grantee::regrole::text, c.relname, a.privilege_type
from pg_class c
cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
where c.relnamespace = 'public'::regnamespace
  and c.relname in ('guest_requests','stays','staff_profiles','rooms','request_categories','request_types','pms_integrations')
  and a.grantee::regrole::text in ('authenticated','anon')
  and a.privilege_type in ('INSERT','UPDATE','DELETE');
