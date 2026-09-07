-- Separate Hotsflow access roles from hotel job roles.
--
-- Access role: controls what a member may do in Hotsflow.
-- Job role: describes what the person does at a specific property and is
-- deliberately configurable by that property's administrators.

-- 1. Rename the lowest Core role at the product/UI level without changing
-- its internal slug yet. Several shipped compatibility migrations and pgTAP
-- fixtures still reference `receptionist`, so changing the slug here would
-- break replay. The stable semantic label exposed to users is now `Staff`;
-- the internal slug can be migrated later once compatibility code is removed.
update roles
set display_name = 'Staff', scope = 'property', is_system = true, rank = 10
where slug = 'receptionist';

-- 2. Property-configurable job roles. These are NOT authorization roles.
create table property_job_roles (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  name text not null,
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint property_job_roles_name_nonempty check (length(trim(name)) > 0),
  constraint property_job_roles_property_name_unique unique (property_id, name)
);

create index property_job_roles_property_idx
  on property_job_roles(property_id, active, sort_order, name);

alter table property_job_roles enable row level security;

-- Any member with property access can read the available job roles. Mutation
-- is reserved for property administrators (rank >= 30). Organization admins
-- inherit access through current_actor_role_rank(property_id).
create policy property_job_roles_select
on property_job_roles for select to authenticated
using (has_property_access(property_id));

create policy property_job_roles_insert
on property_job_roles for insert to authenticated
with check (current_actor_role_rank(property_id) >= 30);

create policy property_job_roles_update
on property_job_roles for update to authenticated
using (current_actor_role_rank(property_id) >= 30)
with check (current_actor_role_rank(property_id) >= 30);

create policy property_job_roles_delete
on property_job_roles for delete to authenticated
using (current_actor_role_rank(property_id) >= 30);

-- 3. A membership may optionally carry the person's operational job role for
-- that property. Access role_id remains the sole RBAC authority.
alter table memberships
  add column job_role_id uuid null references property_job_roles(id) on delete set null;

create index memberships_job_role_idx on memberships(job_role_id);

-- Prevent assigning a job role belonging to another property. Organization-
-- scoped memberships intentionally have no property job role.
create or replace function enforce_membership_job_role_scope()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_job_property uuid;
begin
  if new.job_role_id is null then
    return new;
  end if;

  if new.property_id is null then
    raise exception 'Organization-scoped memberships cannot have a property job role';
  end if;

  select property_id into v_job_property
  from property_job_roles
  where id = new.job_role_id;

  if v_job_property is distinct from new.property_id then
    raise exception 'Job role must belong to the membership property';
  end if;

  return new;
end;
$$;

create trigger memberships_job_role_scope
before insert or update of job_role_id, property_id on memberships
for each row execute function enforce_membership_job_role_scope();

-- No default job-role rows are inserted here: each hotel may enable/create
-- only the operational roles it actually uses. UI may offer suggested names
-- without turning them into global database enums.
