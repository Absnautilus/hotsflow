-- RBAC — deliberately minimal. roles is a small, fixed, seeded set (seed data
-- lands in Step 4, not here); nothing in Phase 1 lets the app create roles or
-- permissions at runtime, so these three tables get no updated_at trigger.

create table roles (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  display_name text not null,
  -- 'organization': grants apply to every property under that organization
  -- (see memberships.organization_id in 0004). 'property': grants apply to
  -- one property only.
  scope text not null check (scope in ('organization', 'property')),
  -- true for every role Phase 1 ships with. Reserved for a later, org-defined
  -- custom role — not built now, this just avoids a future migration to add
  -- the distinction.
  is_system boolean not null default true,
  created_at timestamptz not null default now()
);

create table permissions (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  -- null = a core permission (e.g. managing staff/property settings).
  -- set = owned by that module; deleting the module deletes its permissions
  -- (and, via role_permissions' own cascade below, any grants of them).
  module_id uuid references modules(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table role_permissions (
  role_id uuid not null references roles(id) on delete cascade,
  permission_id uuid not null references permissions(id) on delete cascade,
  primary key (role_id, permission_id)
);
