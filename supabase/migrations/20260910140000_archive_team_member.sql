-- Replaces the hard delete added by 20260910130000_membership_delete.sql:
-- removing someone from a property's Team permanently destroyed their
-- membership row, taking down anything that referenced it (job title
-- assignment, historical stays/requests attribution, audit log entries)
-- along with it. An archive instead keeps the row -- and every foreign key
-- pointing at it -- intact, and only hides it from the Team roster.
--
-- archive_team_member() carries the exact same restrictions
-- memberships_delete enforced (never your own row, never an org-wide
-- membership -- that reaches every property in the organization, so
-- archiving it from a single property's Team page would deactivate that
-- person everywhere) plus setting status to 'suspended' in the same
-- transaction, since an archived person shouldn't keep active access.

alter table memberships add column archived_at timestamptz;

drop policy memberships_delete on memberships;
revoke delete on memberships from authenticated;

create function archive_team_member(p_membership_id uuid) returns memberships
language plpgsql security definer set search_path = public as $$
declare
  v_target memberships%rowtype;
  v_result memberships%rowtype;
begin
  select * into v_target from memberships where id = p_membership_id;
  if v_target.id is null then
    raise exception 'membership_not_found' using errcode = '02000';
  end if;

  if v_target.profile_id = auth.uid() then
    raise exception 'cannot_archive_self' using errcode = '42501';
  end if;

  if v_target.property_id is null then
    raise exception 'cannot_archive_org_wide_membership' using errcode = '42501';
  end if;

  if not has_permission(v_target.property_id, 'core.staff.manage') then
    raise exception 'archive_not_allowed' using errcode = '42501';
  end if;

  update memberships set archived_at = now(), status = 'suspended'
    where id = p_membership_id
    returning * into v_result;

  return v_result;
end;
$$;

grant execute on function archive_team_member(uuid) to authenticated;
