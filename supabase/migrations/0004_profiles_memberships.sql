-- Staff identity (profiles) and the property/organization link (memberships).
-- profiles carries identity ONLY — no role, no property, no permission.
-- That relationship lives entirely in memberships, which is the single
-- source of truth every RLS policy will check against (helpers land in
-- Step 3, migration 0006).

create table profiles (
  -- 1:1 with auth.users. Deleting the auth user deletes the profile — this
  -- mirrors the pattern already used by guest_requests and shifts.
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger profiles_set_updated_at
  before update on profiles
  for each row execute function set_updated_at();

-- ---------------------------------------------------------------------------
-- memberships
-- ---------------------------------------------------------------------------
-- A membership grants a role either on ONE property, or across an entire
-- organization (every property under it) — never both, and never neither.
-- This is what lets an Organization Admin operate on all of an org's
-- properties without one membership row per property, without building a
-- general inheritance system: it's a single OR-branch in the RLS helper
-- (has_property_access, migration 0006), not a hierarchy walk.

create table memberships (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles(id) on delete cascade,
  property_id uuid references properties(id) on delete cascade,
  organization_id uuid references organizations(id) on delete cascade,
  role_id uuid not null references roles(id) on delete restrict,
  status text not null default 'active' check (status in ('invited', 'active', 'suspended')),
  invited_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint memberships_exactly_one_scope check (
    (property_id is not null and organization_id is null)
    or (property_id is null and organization_id is not null)
  )
);

-- One active-or-not membership per (profile, property) / (profile, organization).
-- Partial (not plain) unique indexes because property_id/organization_id are
-- each null on roughly half the rows by design.
create unique index memberships_profile_property_unique
  on memberships (profile_id, property_id) where property_id is not null;

create unique index memberships_profile_organization_unique
  on memberships (profile_id, organization_id) where organization_id is not null;

-- Reverse-lookup indexes ("who has access to property/org X") — the
-- partial-unique indexes above lead with profile_id, which doesn't serve
-- this direction. Needed for any future staff-list view, not just RLS.
create index memberships_property_idx on memberships (property_id) where property_id is not null;
create index memberships_organization_idx on memberships (organization_id) where organization_id is not null;

create trigger memberships_set_updated_at
  before update on memberships
  for each row execute function set_updated_at();
