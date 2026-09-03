-- Freeze mechanism rehearsal — exact ACL snapshot, per runbook §3/§E.
-- Not information_schema (which can normalize/expand column vs table
-- grants in ways that obscure the real underlying difference) but the raw
-- catalog ACL via aclexplode() on pg_class.relacl and pg_attribute.attacl
-- -- the actual source of truth Postgres itself uses. Scoped to exactly
-- the write privileges the freeze touches (INSERT/UPDATE/DELETE) for
-- exactly the roles the freeze touches (authenticated, anon), on exactly
-- the tables the runbook's freeze proposal names.
--
-- Written to a PERMANENT table (not temporary) on purpose: the whole
-- point of the failure-scenario test (item 3 below) is that recovery must
-- work from a completely separate process/session after an interruption
-- -- a temp table would not survive that and would silently invalidate
-- the test.
create table if not exists _freeze_acl_snapshot (
  level text not null,          -- 'TABLE' or 'COLUMN'
  table_name text not null,
  column_name text,             -- null for TABLE-level rows
  grantee text not null,
  privilege text not null
);
truncate _freeze_acl_snapshot;

insert into _freeze_acl_snapshot (level, table_name, column_name, grantee, privilege)
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

\echo '--- ACL snapshot captured ---'
select level, table_name, column_name, grantee, privilege
from _freeze_acl_snapshot order by 1,2,3,4,5;
select count(*) as snapshot_row_count from _freeze_acl_snapshot;
