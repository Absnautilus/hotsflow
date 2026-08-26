-- Minimal audit log — only for the sensitive membership mutations this
-- phase introduces (create, suspend, reactivate, role change). Not a
-- generic logging framework: one table, four specific write paths, no
-- configuration, no generalized "log any action" mechanism. Extend this
-- later only when another concrete need shows up, same discipline as
-- everything else deferred from Fase 1.

create table audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_profile_id uuid references profiles(id) on delete set null,
  property_id uuid references properties(id) on delete set null,
  organization_id uuid references organizations(id) on delete set null,
  action text not null,
  target_type text not null,
  target_id uuid not null,
  old_value jsonb,
  new_value jsonb,
  created_at timestamptz not null default now()
);

create index audit_logs_property_idx on audit_logs (property_id, created_at) where property_id is not null;
create index audit_logs_organization_idx on audit_logs (organization_id, created_at) where organization_id is not null;

alter table audit_logs enable row level security;

-- Same authority as viewing/managing staff itself — no separate
-- audit-viewing permission introduced for this.
create policy audit_logs_select on audit_logs for select to authenticated
  using (
    (property_id is not null and has_permission(property_id, 'core.staff.manage'))
    or (organization_id is not null and has_organization_permission(organization_id, 'core.staff.manage'))
  );

-- No insert/update/delete policy for `authenticated` at all — every row
-- comes from one of the three SECURITY DEFINER writers below, which bypass
-- RLS as their owner. Nothing else should ever write here.

create function log_membership_created() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into audit_logs (actor_profile_id, property_id, organization_id, action, target_type, target_id, new_value)
  values (
    auth.uid(), new.property_id, new.organization_id,
    'membership.created', 'membership', new.id,
    jsonb_build_object('role_id', new.role_id, 'status', new.status)
  );
  return new;
end;
$$;

create trigger memberships_log_created
  after insert on memberships
  for each row execute function log_membership_created();

create function log_membership_status_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_action text;
begin
  if new.status is distinct from old.status then
    v_action := case new.status
      when 'suspended' then 'membership.suspended'
      when 'active' then 'membership.reactivated'
      else 'membership.status_changed'
    end;
    insert into audit_logs (actor_profile_id, property_id, organization_id, action, target_type, target_id, old_value, new_value)
    values (
      auth.uid(), new.property_id, new.organization_id,
      v_action, 'membership', new.id,
      jsonb_build_object('status', old.status),
      jsonb_build_object('status', new.status)
    );
  end if;
  return new;
end;
$$;

create trigger memberships_log_status_change
  after update of status on memberships
  for each row execute function log_membership_status_change();

-- Redefines 0010's assign_membership_role to also write
-- 'membership.role_changed' — CREATE OR REPLACE, not a new function; the
-- signature and every check inside are unchanged.
create or replace function assign_membership_role(p_membership_id uuid, p_new_role_id uuid) returns memberships
language plpgsql security definer set search_path = public as $$
declare
  v_target memberships%rowtype;
  v_result memberships%rowtype;
begin
  select * into v_target from memberships where id = p_membership_id;
  if v_target.id is null then
    raise exception 'membership_not_found' using errcode = '02000';
  end if;

  if not role_assignment_allowed(p_new_role_id, v_target.property_id, v_target.organization_id, v_target.profile_id) then
    raise exception 'role_assignment_not_allowed' using errcode = '42501';
  end if;

  update memberships set role_id = p_new_role_id where id = p_membership_id
    returning * into v_result;

  insert into audit_logs (actor_profile_id, property_id, organization_id, action, target_type, target_id, old_value, new_value)
  values (
    auth.uid(), v_result.property_id, v_result.organization_id,
    'membership.role_changed', 'membership', v_result.id,
    jsonb_build_object('role_id', v_target.role_id),
    jsonb_build_object('role_id', v_result.role_id)
  );

  return v_result;
end;
$$;

revoke all on function log_membership_created() from public;
revoke all on function log_membership_status_change() from public;
revoke all on function assign_membership_role(uuid, uuid) from public;
grant execute on function assign_membership_role(uuid, uuid) to authenticated;

revoke all on audit_logs from public;
grant select on audit_logs to authenticated;
