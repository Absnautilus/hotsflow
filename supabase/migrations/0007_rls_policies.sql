-- RLS. Two layers on every table, both required: policies restrict which
-- ROWS a query can see/touch, grants restrict which OPERATIONS a role can
-- attempt at all. A permissive policy with no matching grant still fails
-- closed — that's deliberate, and it's exactly how guest_sessions ends up
-- fully locked down below (RLS enabled, zero policies, zero grants).
--
-- Nothing here grants anything to `anon`. No guest-facing flow exists yet in
-- Phase 1 (see 0005's header) — anon grants land with the first module that
-- actually needs them, scoped as tightly as guest_requests' own RPC-only
-- pattern already proves out.
--
-- No self-service writes exist yet for organizations/profiles creation
-- either: a brand-new organization or a brand-new profile has, by
-- definition, no membership yet to authorize itself with. Those stay
-- service-role-only (seed scripts, future admin tooling) in Phase 1 — RLS
-- simply has no INSERT policy for `authenticated` on those two tables, which
-- means default-deny.

alter table organizations enable row level security;
alter table properties enable row level security;
alter table modules enable row level security;
alter table property_modules enable row level security;
alter table roles enable row level security;
alter table permissions enable row level security;
alter table role_permissions enable row level security;
alter table profiles enable row level security;
alter table memberships enable row level security;
alter table guest_sessions enable row level security;

grant usage on schema public to authenticated;

-- ---------------------------------------------------------------------------
-- organizations
-- ---------------------------------------------------------------------------
create policy organizations_select on organizations for select to authenticated
  using (has_organization_access(id));

create policy organizations_update on organizations for update to authenticated
  using (has_organization_permission(id, 'core.organization.manage'))
  with check (has_organization_permission(id, 'core.organization.manage'));

grant select, update on organizations to authenticated;

-- ---------------------------------------------------------------------------
-- properties
-- ---------------------------------------------------------------------------
create policy properties_select on properties for select to authenticated
  using (has_property_access(id));

-- New property: no property_id exists yet to check has_permission against,
-- so this is authorized at the organization level instead.
create policy properties_insert on properties for insert to authenticated
  with check (has_organization_permission(organization_id, 'core.property.manage'));

-- Editing an existing property: has_permission already covers both a
-- property-scoped property_admin and an org-wide organization_admin (see
-- 0006) — no need to duplicate that OR-branch here.
create policy properties_update on properties for update to authenticated
  using (has_permission(id, 'core.property.manage'))
  with check (has_permission(id, 'core.property.manage'));

grant select, insert, update on properties to authenticated;

-- ---------------------------------------------------------------------------
-- modules — read-only reference data, no write policy (service-role/
-- migration managed, same as roles/permissions/role_permissions below)
-- ---------------------------------------------------------------------------
create policy modules_select on modules for select to authenticated using (true);

grant select on modules to authenticated;

-- ---------------------------------------------------------------------------
-- property_modules — entitlement, not authorization (kept conceptually
-- separate from permissions per the Architecture Proposal)
-- ---------------------------------------------------------------------------
create policy property_modules_select on property_modules for select to authenticated
  using (has_property_access(property_id));

create policy property_modules_insert on property_modules for insert to authenticated
  with check (has_permission(property_id, 'core.property.manage'));

create policy property_modules_update on property_modules for update to authenticated
  using (has_permission(property_id, 'core.property.manage'))
  with check (has_permission(property_id, 'core.property.manage'));

grant select, insert, update on property_modules to authenticated;

-- ---------------------------------------------------------------------------
-- roles / permissions / role_permissions — small, fixed, seeded reference
-- tables. Read-only from the app's point of view in Phase 1; no write
-- policy on any of the three (default-deny, service-role/migration only).
-- ---------------------------------------------------------------------------
create policy roles_select on roles for select to authenticated using (true);
create policy permissions_select on permissions for select to authenticated using (true);
create policy role_permissions_select on role_permissions for select to authenticated using (true);

grant select on roles to authenticated;
grant select on permissions to authenticated;
grant select on role_permissions to authenticated;

-- ---------------------------------------------------------------------------
-- profiles — identity only, no property/role/permission data lives here, so
-- letting any authenticated user read any profile (name, avatar) is the same
-- low-risk tradeoff already made by guest_requests and shifts. Writing is
-- restricted to your own row; there is no self-service creation flow yet
-- (see file header) so no insert policy either.
-- ---------------------------------------------------------------------------
create policy profiles_select on profiles for select to authenticated using (true);

create policy profiles_update_own on profiles for update to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

grant select, update on profiles to authenticated;

-- ---------------------------------------------------------------------------
-- memberships — the table every access decision above ultimately traces
-- back to. A profile always sees its own memberships; seeing or managing
-- someone else's requires 'core.staff.manage' on the relevant scope.
-- ---------------------------------------------------------------------------
create policy memberships_select on memberships for select to authenticated
  using (
    profile_id = auth.uid()
    or (property_id is not null and has_permission(property_id, 'core.staff.manage'))
    or (organization_id is not null and has_organization_permission(organization_id, 'core.staff.manage'))
  );

-- Deliberately no `profile_id = auth.uid()` branch here: granting yourself
-- (or editing your own) membership is not something owning the row should
-- allow — only someone with staff-management authority over that scope can.
create policy memberships_insert on memberships for insert to authenticated
  with check (
    (property_id is not null and has_permission(property_id, 'core.staff.manage'))
    or (organization_id is not null and has_organization_permission(organization_id, 'core.staff.manage'))
  );

create policy memberships_update on memberships for update to authenticated
  using (
    (property_id is not null and has_permission(property_id, 'core.staff.manage'))
    or (organization_id is not null and has_organization_permission(organization_id, 'core.staff.manage'))
  )
  with check (
    (property_id is not null and has_permission(property_id, 'core.staff.manage'))
    or (organization_id is not null and has_organization_permission(organization_id, 'core.staff.manage'))
  );

grant select, insert, update on memberships to authenticated;

-- ---------------------------------------------------------------------------
-- guest_sessions — RLS enabled, zero policies, zero grants, for `anon` and
-- `authenticated` alike. Reachable only through guest_session_is_valid()
-- (0006) and, later, whatever SECURITY DEFINER functions a guest-facing
-- module adds for creating/using sessions. This mirrors guest_requests'
-- proven pattern exactly.
-- ---------------------------------------------------------------------------
