-- Module registry and per-property entitlement.
-- modules = which technical modules exist on the platform at all.
-- property_modules = which of those a given property has switched on.
-- This answers ONLY "is the module available here?" — staff authorization is
-- a separate concern (roles/permissions, migration 0003) and so is guest
-- authorization (guest_sessions, migration 0005). Keep them decoupled.

create table modules (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  display_name text not null,
  status text not null default 'active' check (status in ('active', 'beta', 'deprecated')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger modules_set_updated_at
  before update on modules
  for each row execute function set_updated_at();

create table property_modules (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  module_id uuid not null references modules(id) on delete cascade,
  enabled boolean not null default false,
  -- Reserved for a future billing/plan tier per module; unused in Phase 1.
  plan text,
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (property_id, module_id)
);

-- No separate index on property_id: the unique constraint above leads with
-- it, which is also the lookup direction every entitlement check uses
-- ("which modules does property X have?").

create trigger property_modules_set_updated_at
  before update on property_modules
  for each row execute function set_updated_at();
