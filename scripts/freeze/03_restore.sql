-- Reopen — GRANT back exactly what the snapshot (table 01) recorded.
-- Deliberately reads from the persisted snapshot table, not from any
-- variable held in a prior session -- this is what makes the recovery
-- procedure work even when invoked as a totally separate step after an
-- interruption (see the failure-scenario test).
do $$
declare
  r record;
begin
  for r in select * from _freeze_acl_snapshot loop
    if r.level = 'TABLE' then
      execute format('grant %s on table %I to %I', r.privilege, r.table_name, r.grantee);
    else
      execute format('grant %s (%I) on table %I to %I', r.privilege, r.column_name, r.table_name, r.grantee);
    end if;
  end loop;
end $$;

\echo '--- post-RESTORE: current ACL for the same scope, to be diffed against the snapshot ---'
create table if not exists _freeze_acl_after (like _freeze_acl_snapshot including all);
truncate _freeze_acl_after;
insert into _freeze_acl_after (level, table_name, column_name, grantee, privilege)
select 'TABLE', c.relname, null, a.grantee::regrole::text, a.privilege_type
from pg_class c
cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
where c.relnamespace = 'public'::regnamespace
  and c.relname in ('guest_requests','stays','staff_profiles','rooms','request_categories','request_types','pms_integrations')
  and a.grantee::regrole::text in ('authenticated','anon')
  and a.privilege_type in ('INSERT','UPDATE','DELETE')
union all
select 'COLUMN', c.relname, att.attname, a.grantee::regrole::text, a.privilege_type
from pg_class c
join pg_attribute att on att.attrelid = c.oid and att.attnum > 0 and not att.attisdropped
cross join lateral aclexplode(att.attacl) a
where c.relnamespace = 'public'::regnamespace
  and c.relname in ('guest_requests','stays','staff_profiles','rooms','request_categories','request_types','pms_integrations')
  and att.attacl is not null
  and a.grantee::regrole::text in ('authenticated','anon')
  and a.privilege_type in ('INSERT','UPDATE','DELETE');

\echo '--- rows in snapshot but missing after restore (expect 0) ---'
select * from _freeze_acl_snapshot except select * from _freeze_acl_after;
\echo '--- rows present after restore but NOT in the original snapshot (expect 0 -- overshoot) ---'
select * from _freeze_acl_after except select * from _freeze_acl_snapshot;
\echo '--- row counts (expect equal) ---'
select (select count(*) from _freeze_acl_snapshot) as snapshot_count,
       (select count(*) from _freeze_acl_after) as after_count;
