-- RLS helper functions. Every one is SECURITY DEFINER + STABLE + an explicit
-- search_path, for the same reason: a policy on table X that queries table Y
-- directly would re-trigger Y's own RLS during evaluation, which is how you
-- get either infinite recursion (X queries X) or a silent wrong answer (Y's
-- policy denies the row before X's policy even gets to look at it). Wrapping
-- the check in a SECURITY DEFINER function makes it run with the function
-- owner's privileges, bypassing RLS on the tables *inside* the function —
-- this is the same fix already proven in guest_requests (0003) and
-- plannerturni (0003_fix_admin_policy_recursion.sql).
--
-- `set search_path = public` on every one of them is not optional: without
-- it, a SECURITY DEFINER function resolves unqualified table names using the
-- *caller's* search_path, which the caller controls — an attacker could in
-- principle point it at a table of their own choosing. Pinning it removes
-- that entirely.
--
-- Six functions, each answering exactly one question:
--   has_property_access       — can this profile see this property at all?
--   has_organization_access   — can this profile see this organization at all?
--   has_permission             — can this profile do X on this property?
--   has_organization_permission — can this profile do X on this organization?
--   has_module                 — is this module switched on for this property?
--   guest_session_is_valid     — is this guest session currently usable?

-- ---------------------------------------------------------------------------
-- has_property_access
-- ---------------------------------------------------------------------------
-- True if the profile has an active membership on this exact property, OR an
-- active org-wide membership on the organization that owns it. This is the
-- single OR-branch mentioned in the Architecture Proposal — not inheritance,
-- just one extra condition in one function.
create function has_property_access(p_property_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from memberships m
    where m.profile_id = auth.uid()
      and m.status = 'active'
      and (
        m.property_id = p_property_id
        or m.organization_id = (select organization_id from properties where id = p_property_id)
      )
  );
$$;

-- ---------------------------------------------------------------------------
-- has_organization_access
-- ---------------------------------------------------------------------------
-- True if the profile has an active org-wide membership on this
-- organization, OR an active membership on any one of its properties.
create function has_organization_access(p_organization_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from memberships m
    where m.profile_id = auth.uid()
      and m.status = 'active'
      and (
        m.organization_id = p_organization_id
        or m.property_id in (select id from properties where organization_id = p_organization_id)
      )
  );
$$;

-- ---------------------------------------------------------------------------
-- has_permission
-- ---------------------------------------------------------------------------
-- The main authorization check: role grants the permission (via
-- role_permissions), AND the membership covers this property (directly or
-- org-wide, same OR as has_property_access), AND — only when the permission
-- belongs to a module (permissions.module_id is not null) — that module is
-- actually enabled for this property. This last clause is what keeps
-- entitlement (property_modules) and authorization (permissions) genuinely
-- separate: a role can be allowed to use `transfers`, but if the property
-- hasn't got the module switched on, this still returns false.
create function has_permission(p_property_id uuid, p_permission_slug text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from memberships m
    join role_permissions rp on rp.role_id = m.role_id
    join permissions perm on perm.id = rp.permission_id
    where perm.slug = p_permission_slug
      and m.profile_id = auth.uid()
      and m.status = 'active'
      and (
        m.property_id = p_property_id
        or m.organization_id = (select organization_id from properties where id = p_property_id)
      )
      and (
        perm.module_id is null
        or exists (
          select 1 from property_modules pm
          where pm.property_id = p_property_id
            and pm.module_id = perm.module_id
            and pm.enabled
        )
      )
  );
$$;

-- ---------------------------------------------------------------------------
-- has_organization_permission
-- ---------------------------------------------------------------------------
-- Same idea as has_permission, but for actions on the organization itself
-- (e.g. renaming it, creating a new property under it) where there is no
-- single property_id to check against yet. Deliberately org-wide-membership
-- only — a property-scoped membership doesn't grant organization-level
-- authority, only has_permission's OR-branch works in that direction.
create function has_organization_permission(p_organization_id uuid, p_permission_slug text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from memberships m
    join role_permissions rp on rp.role_id = m.role_id
    join permissions perm on perm.id = rp.permission_id
    where perm.slug = p_permission_slug
      and m.profile_id = auth.uid()
      and m.status = 'active'
      and m.organization_id = p_organization_id
  );
$$;

-- ---------------------------------------------------------------------------
-- has_module
-- ---------------------------------------------------------------------------
-- Pure entitlement check, no authorization involved: "is this module even
-- switched on here?" Kept separate from has_permission so a module's own
-- frontend can ask this question on its own (e.g. to decide whether to show
-- itself at all in a property switcher) without needing a specific
-- permission slug.
create function has_module(p_property_id uuid, p_module_slug text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from property_modules pm
    join modules mod on mod.id = pm.module_id
    where pm.property_id = p_property_id
      and mod.slug = p_module_slug
      and pm.enabled
  );
$$;

-- ---------------------------------------------------------------------------
-- guest_session_is_valid
-- ---------------------------------------------------------------------------
-- The only way anything ever reads guest_sessions in Phase 1 (the table
-- itself gets zero RLS policies — see 0007). Re-checks the row live: a
-- revoked or expired session stops working immediately, it isn't enough for
-- a token/claim to merely exist. property_id must match exactly — a session
-- issued for one property is never valid for another, no OR-branch here.
create function guest_session_is_valid(p_session_id uuid, p_property_id uuid, p_min_level smallint) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from guest_sessions gs
    where gs.id = p_session_id
      and gs.property_id = p_property_id
      and gs.revoked_at is null
      and gs.expires_at > now()
      and gs.verification_level >= p_min_level
  );
$$;

grant execute on function has_property_access(uuid) to authenticated;
grant execute on function has_organization_access(uuid) to authenticated;
grant execute on function has_permission(uuid, text) to authenticated;
grant execute on function has_organization_permission(uuid, text) to authenticated;
grant execute on function has_module(uuid, text) to authenticated;
grant execute on function guest_session_is_valid(uuid, uuid, smallint) to authenticated;
