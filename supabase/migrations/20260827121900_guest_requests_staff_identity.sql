-- Fase 2 Step 4 — guest_requests staff identity backfill (profiles + memberships).
--
-- Approved mapping (D2): admin -> property_admin (property-scoped);
-- operatore -> receptionist (property-scoped, any department); master ->
-- organization_admin, one membership per existing organization (known,
-- accepted limitation — no platform_superadmin introduced here).
-- staff_profiles.active = false -> membership.status = 'suspended'.
--
-- staff_profiles.auth_user_id is `not null unique references auth.users(id)`
-- (0001_init.sql) — the database itself already guarantees it is never null
-- or invalid, and that no two staff_profiles rows share one auth user. So
-- profiles.id = auth_user_id always holds by construction; there is no
-- "null/invalid auth_user_id" case to branch on here, and no code is added
-- to handle one. Likewise `role` is a closed enum and
-- staff_profiles_department_matches_role (0009) already rules out any
-- role/department combination outside {admin, master} x {null} and
-- {operatore} x {housekeeping, reception, maintenance} — there is no "role
-- outside the enum" or inconsistent role/department case the database
-- itself doesn't already forbid.
--
-- staff_profiles remains the module's own authoritative source for its
-- local-only attributes (department, on_duty, login_username, name) — this
-- migration only ever reads it. It stops being read for authorization
-- purposes starting Step 6 (RLS wrapper); nothing changes about that here.

begin;

-- Backfill, safe to call more than once, not a client-facing RPC — no
-- grant to authenticated/anon (see the revoke below). Only ever run by the
-- migration itself or, in tests, by the connecting/superuser role.
create function backfill_staff_identity() returns void
language plpgsql as $$
declare
  s record;
  v_property_id uuid;
  v_role_id uuid;
  v_status text;
  v_existing_role_id uuid;
  org_row record;
begin
  for s in select * from staff_profiles order by id loop
    if not exists (select 1 from profiles where id = s.auth_user_id) then
      insert into profiles (id, full_name) values (s.auth_user_id, s.name);
    end if;
    -- profile already existing (e.g. from a prior run, or created by
    -- another process) is left untouched — never overwritten here.

    v_status := case when s.active then 'active' else 'suspended' end;

    if s.role in ('admin', 'operatore') then
      select platform_property_id into v_property_id
        from legacy_property_mapping where legacy_hotel_id = s.hotel_id;

      if v_property_id is null then
        raise exception
          'staff_profiles % (hotel %) has no legacy_property_mapping row — run backfill_legacy_property_mapping() first',
          s.id, s.hotel_id;
      end if;

      select id into v_role_id from roles
        where slug = case s.role when 'admin' then 'property_admin' else 'receptionist' end;

      select role_id into v_existing_role_id from memberships
        where profile_id = s.auth_user_id and property_id = v_property_id and organization_id is null;

      if v_existing_role_id is null then
        insert into memberships (profile_id, property_id, role_id, status)
          values (s.auth_user_id, v_property_id, v_role_id, v_status);
      elsif v_existing_role_id <> v_role_id then
        raise exception
          'staff_profiles % maps to role % for property %, but a membership with a different role_id (%) already exists — not silently corrected',
          s.id, v_role_id, v_property_id, v_existing_role_id;
      end if;
      -- v_existing_role_id = v_role_id: already correctly bootstrapped, left as-is
      -- (including status: an operational status change since bootstrap is not
      -- something this one-time backfill should overwrite).

    elsif s.role = 'master' then
      select id into v_role_id from roles where slug = 'organization_admin';

      for org_row in
        select distinct o.id as organization_id
        from legacy_property_mapping m
        join properties p on p.id = m.platform_property_id
        join organizations o on o.id = p.organization_id
      loop
        select role_id into v_existing_role_id from memberships
          where profile_id = s.auth_user_id and organization_id = org_row.organization_id and property_id is null;

        if v_existing_role_id is null then
          insert into memberships (profile_id, organization_id, role_id, status)
            values (s.auth_user_id, org_row.organization_id, v_role_id, v_status);
        elsif v_existing_role_id <> v_role_id then
          raise exception
            'staff_profiles % (master) maps to organization_admin for organization %, but a membership with a different role_id (%) already exists — not silently corrected',
            s.id, org_row.organization_id, v_existing_role_id;
        end if;
      end loop;
    end if;
  end loop;
end;
$$;

revoke all on function backfill_staff_identity() from public;

select backfill_staff_identity();

commit;
