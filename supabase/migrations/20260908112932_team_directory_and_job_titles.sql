-- Property-scoped Team directory metadata. Authentication identity remains in
-- auth.users/profiles and software access remains in memberships; these tables
-- only describe the person's operational place inside one hotel.

create table property_job_titles (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 80),
  active boolean not null default true,
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index property_job_titles_name_unique
  on property_job_titles (property_id, lower(trim(name)));
create index property_job_titles_property_idx on property_job_titles (property_id);

create trigger property_job_titles_set_updated_at
  before update on property_job_titles
  for each row execute function set_updated_at();

create table property_staff_details (
  property_id uuid not null references properties(id) on delete cascade,
  profile_id uuid not null references profiles(id) on delete cascade,
  job_title_id uuid references property_job_titles(id) on delete set null,
  employment_status text not null default 'active'
    check (employment_status in ('active', 'inactive')),
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (property_id, profile_id)
);

create index property_staff_details_profile_idx on property_staff_details (profile_id);
create index property_staff_details_job_title_idx on property_staff_details (job_title_id)
  where job_title_id is not null;

create function validate_property_staff_job_title() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not exists (
    select 1 from memberships m
    where m.profile_id = new.profile_id
      and (
        m.property_id = new.property_id
        or m.organization_id = (select organization_id from properties where id = new.property_id)
      )
  ) then
    raise exception 'profile_not_member_of_property' using errcode = '23514';
  end if;

  if new.job_title_id is not null and not exists (
    select 1 from property_job_titles jt
    where jt.id = new.job_title_id
      and jt.property_id = new.property_id
      and jt.active
  ) then
    raise exception 'job_title_not_active_for_property' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger property_staff_details_validate_job_title
  before insert or update of property_id, job_title_id on property_staff_details
  for each row execute function validate_property_staff_job_title();

create trigger property_staff_details_set_updated_at
  before update on property_staff_details
  for each row execute function set_updated_at();

alter table property_job_titles enable row level security;
alter table property_staff_details enable row level security;

-- A manager must still be able to render the identity attached to an invited
-- or suspended membership. Regular property users keep the narrower existing
-- visibility rule; this additional branch requires core.staff.manage.
create function can_manage_profile(p_target_profile_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from memberships target_m
    where target_m.profile_id = p_target_profile_id
      and (
        (target_m.property_id is not null and has_permission(target_m.property_id, 'core.staff.manage'))
        or (
          target_m.organization_id is not null
          and has_organization_permission(target_m.organization_id, 'core.staff.manage')
        )
      )
  );
$$;

drop policy profiles_select on profiles;
create policy profiles_select on profiles for select to authenticated
  using (auth.uid() = id or shares_accessible_property(id) or can_manage_profile(id));

create policy property_job_titles_select on property_job_titles for select to authenticated
  using (has_property_access(property_id));
create policy property_job_titles_insert on property_job_titles for insert to authenticated
  with check (has_permission(property_id, 'core.staff.manage'));
create policy property_job_titles_update on property_job_titles for update to authenticated
  using (has_permission(property_id, 'core.staff.manage'))
  with check (has_permission(property_id, 'core.staff.manage'));

create policy property_staff_details_select on property_staff_details for select to authenticated
  using (has_property_access(property_id));
create policy property_staff_details_insert on property_staff_details for insert to authenticated
  with check (has_permission(property_id, 'core.staff.manage'));
create policy property_staff_details_update on property_staff_details for update to authenticated
  using (has_permission(property_id, 'core.staff.manage'))
  with check (has_permission(property_id, 'core.staff.manage'));

-- Explicit Data API surface. New Supabase projects no longer auto-grant new
-- public tables, and relying on the old default would make environments drift.
grant select, insert on property_job_titles to authenticated;
grant update (name, active) on property_job_titles to authenticated;
grant select, insert on property_staff_details to authenticated;
grant update (job_title_id, employment_status) on property_staff_details to authenticated;

revoke all on function validate_property_staff_job_title() from public;
revoke all on function can_manage_profile(uuid) from public;
grant execute on function can_manage_profile(uuid) to authenticated;

comment on table property_job_titles is
  'Property-owned operational job titles; deliberately separate from Core RBAC roles.';
comment on table property_staff_details is
  'Property-specific employment metadata for an authenticated profile; never grants software access.';
