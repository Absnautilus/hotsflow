-- Closes the privilege-escalation gap in 0007's memberships policies: a
-- generic UPDATE let anyone with core.staff.manage rewrite role_id (assign
-- themselves or anyone else any role, including their own), property_id,
-- organization_id, or profile_id. Fix has three parts:
--   1. role_assignment_allowed() — the one hierarchy rule, used by both the
--      insert policy (inviting someone already assigns a role) and the new
--      assign_membership_role() RPC (reassigning one).
--   2. assign_membership_role() — the only sanctioned way to change a
--      membership's role_id going forward.
--   3. A column-level GRANT restricting what `authenticated` can UPDATE
--      directly on memberships to `status` only — role_id/property_id/
--      organization_id/profile_id become unwritable from the client no
--      matter what a policy might otherwise permit. Defense in depth: even
--      a mistake in the policy logic can't reopen this.

-- ---------------------------------------------------------------------------
-- current_actor_role_rank / current_actor_role_rank_for_organization
-- ---------------------------------------------------------------------------
-- The rank of the calling profile's own active membership covering the
-- given scope. If they somehow hold both a direct and an org-wide
-- membership reaching the same property, the higher rank wins — consistent
-- with has_property_access/has_permission already treating either as
-- sufficient (an OR, not a most-specific-wins rule).
create function current_actor_role_rank(p_property_id uuid) returns smallint
language sql stable security definer set search_path = public as $$
  select r.rank
  from memberships m
  join roles r on r.id = m.role_id
  where m.profile_id = auth.uid()
    and m.status = 'active'
    and (
      m.property_id = p_property_id
      or m.organization_id = (select organization_id from properties where id = p_property_id)
    )
  order by r.rank desc
  limit 1;
$$;

-- Org-wide membership only — a property-scoped membership doesn't grant
-- organization-level authority, same restriction as has_organization_permission.
create function current_actor_role_rank_for_organization(p_organization_id uuid) returns smallint
language sql stable security definer set search_path = public as $$
  select r.rank
  from memberships m
  join roles r on r.id = m.role_id
  where m.profile_id = auth.uid()
    and m.status = 'active'
    and m.organization_id = p_organization_id
  limit 1;
$$;

-- ---------------------------------------------------------------------------
-- role_assignment_allowed — the single hierarchy rule
-- ---------------------------------------------------------------------------
-- Denies if: the target is the caller themselves (no self-promotion, no
-- exceptions — see docs/permissions.md); the new role's scope doesn't match
-- the membership's own scope; the caller lacks core.roles.assign on that
-- scope; or the new role's rank isn't strictly below the caller's own.
-- That last comparison is the entire hierarchy — no per-role special
-- casing. See docs/permissions.md for why this one rule already produces
-- every behavior the Architecture Proposal asked for (manager capped below
-- property_admin, property_admin capped below organization_admin,
-- organization_admin never able to promote another organization_admin).
create function role_assignment_allowed(
  p_new_role_id uuid,
  p_property_id uuid,
  p_organization_id uuid,
  p_target_profile_id uuid
) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  v_new_role_scope text;
  v_new_role_rank smallint;
  v_actor_rank smallint;
begin
  if p_target_profile_id = auth.uid() then
    return false;
  end if;

  select scope, rank into v_new_role_scope, v_new_role_rank from roles where id = p_new_role_id;
  if v_new_role_scope is null then
    return false;
  end if;

  if p_property_id is not null then
    if v_new_role_scope <> 'property' then
      return false;
    end if;
    if not has_permission(p_property_id, 'core.roles.assign') then
      return false;
    end if;
    v_actor_rank := current_actor_role_rank(p_property_id);
  elsif p_organization_id is not null then
    if v_new_role_scope <> 'organization' then
      return false;
    end if;
    if not has_organization_permission(p_organization_id, 'core.roles.assign') then
      return false;
    end if;
    v_actor_rank := current_actor_role_rank_for_organization(p_organization_id);
  else
    return false;
  end if;

  return v_actor_rank is not null and v_new_role_rank < v_actor_rank;
end;
$$;

-- ---------------------------------------------------------------------------
-- assign_membership_role — the only way to change an existing membership's
-- role from here on (see the column-level GRANT at the bottom of this file)
-- ---------------------------------------------------------------------------
create function assign_membership_role(p_membership_id uuid, p_new_role_id uuid) returns memberships
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

  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- memberships_insert — now also gated by role_assignment_allowed. Without
-- this, inviting a new member (which necessarily sets an initial role_id)
-- would bypass the hierarchy rule entirely — the RPC above only protects
-- the update path.
-- ---------------------------------------------------------------------------
drop policy memberships_insert on memberships;
create policy memberships_insert on memberships for insert to authenticated
  with check (
    (
      (property_id is not null and has_permission(property_id, 'core.staff.manage'))
      or (organization_id is not null and has_organization_permission(organization_id, 'core.staff.manage'))
    )
    and role_assignment_allowed(role_id, property_id, organization_id, profile_id)
  );

-- ---------------------------------------------------------------------------
-- memberships_update — adds "not your own row" (see docs/permissions.md on
-- why self-service stays default-deny for now: it isn't just role changes —
-- nothing about your own membership is updatable through this path).
-- role_id itself is additionally protected at the grant level below, so
-- this policy no longer needs to special-case it.
-- ---------------------------------------------------------------------------
drop policy memberships_update on memberships;
create policy memberships_update on memberships for update to authenticated
  using (
    profile_id <> auth.uid()
    and (
      (property_id is not null and has_permission(property_id, 'core.staff.manage'))
      or (organization_id is not null and has_organization_permission(organization_id, 'core.staff.manage'))
    )
  )
  with check (
    profile_id <> auth.uid()
    and (
      (property_id is not null and has_permission(property_id, 'core.staff.manage'))
      or (organization_id is not null and has_organization_permission(organization_id, 'core.staff.manage'))
    )
  );

-- ---------------------------------------------------------------------------
-- Column-level grant: `authenticated` may UPDATE status only. role_id moves
-- exclusively through assign_membership_role() (SECURITY DEFINER, not bound
-- by this grant); property_id/organization_id/profile_id become
-- unwritable from the client through any path — moving a membership to a
-- different scope or person isn't a "manage staff" operation.
-- ---------------------------------------------------------------------------
revoke update on memberships from authenticated;
grant update (status) on memberships to authenticated;

grant execute on function current_actor_role_rank(uuid) to authenticated;
grant execute on function current_actor_role_rank_for_organization(uuid) to authenticated;
grant execute on function role_assignment_allowed(uuid, uuid, uuid, uuid) to authenticated;
grant execute on function assign_membership_role(uuid, uuid) to authenticated;
