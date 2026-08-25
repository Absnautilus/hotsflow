-- Platform core — organizations and properties.
-- organization = hotel-side legal/commercial entity (a single hotel or a group).
-- property = the operative tenant: every module-owned row is scoped to a property_id,
-- never to an organization_id directly (see docs/data-model.md when written in Step 5).

create extension if not exists pgcrypto;

-- Shared trigger used by every table below that carries updated_at. Reference
-- tables seeded once (roles, permissions, role_permissions, modules) don't get
-- this trigger — they're not expected to change at runtime in Phase 1.
create function set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- organizations
-- ---------------------------------------------------------------------------

create table organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger organizations_set_updated_at
  before update on organizations
  for each row execute function set_updated_at();

-- ---------------------------------------------------------------------------
-- properties — the operative tenant
-- ---------------------------------------------------------------------------

create table properties (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete restrict,
  name text not null,
  slug text not null,
  timezone text not null default 'Europe/Rome',
  status text not null default 'active' check (status in ('active', 'suspended')),
  -- Free-form, low-churn config (e.g. display preferences). Promote a key to a
  -- real column, or to a dedicated table, only if it starts being queried/
  -- validated on its own — see the Architecture Proposal's verdict on
  -- property_settings.
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- A slug is only unique within its own organization, not platform-wide.
  unique (organization_id, slug)
);

-- No separate index on organization_id: the unique constraint above already
-- leads with organization_id, so it doubles as that index.

create trigger properties_set_updated_at
  before update on properties
  for each row execute function set_updated_at();
