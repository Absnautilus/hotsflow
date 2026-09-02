-- Fase 2 Step 9 pre-cutover gate — closes a real gap found while fixing
-- create-staff-account/sync-pms-stays: guest_requests_staff_roster_visible()
-- and guest_requests_staff_manage_allowed() (which gate staff_profiles'
-- own RLS policies since Step 6) only check memberships.status via
-- has_property_access()/has_permission() -- neither checks
-- staff_profiles.active. Nothing syncs staff_profiles.active into
-- memberships.status after the one-time Step 4 backfill (the admin
-- dashboard's deactivate toggle, apps/web/src/lib/admin-api.ts, updates
-- staff_profiles.active alone) -- so a staff member deactivated via that
-- toggle kept full roster read/write access as long as their session and
-- membership.status both stayed valid. Full inventory of every helper in
-- the staff/PMS gate chain, and what each one checks, is in this
-- migration's accompanying commit message and docs/fase2-guest-requests-
-- migration.md.
--
-- get_pms_integration_status()/save_pms_integration() have the identical
-- gap, but only when called with an explicit p_hotel_id (the function body
-- does `v_hotel_id := coalesce(p_hotel_id, current_staff_hotel())` --
-- current_staff_hotel() DOES check staff_profiles.active, but is never
-- invoked when p_hotel_id is provided, which is how both the corrected
-- sync-pms-stays Edge Function and the admin UI's own master-hotel-picker
-- call them, per apps/web/src/lib/admin-api.ts). Included here because the
-- stated goal for this gate is explicitly "no PMS management either" for a
-- deactivated caller, not just roster/staff management.
--
-- One new, reusable helper -- current_staff_active() -- rather than
-- duplicating the same staff_profiles lookup inline in four places; named
-- to match the existing current_staff_hotel()/current_staff_role()/
-- current_staff_is_master() family.
begin;

create function current_staff_active() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from staff_profiles where auth_user_id = auth.uid() and active
  );
$$;

revoke all on function current_staff_active() from public;
grant execute on function current_staff_active() to authenticated;

create or replace function guest_requests_staff_roster_visible(p_hotel_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from legacy_property_mapping m
    join properties p on p.id = m.platform_property_id
    where m.legacy_hotel_id = p_hotel_id
      and current_staff_active()
      and (has_property_access(p.id) or has_organization_access(p.organization_id))
  );
$$;

create or replace function guest_requests_staff_manage_allowed(p_hotel_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from legacy_property_mapping m
    join properties p on p.id = m.platform_property_id
    where m.legacy_hotel_id = p_hotel_id
      and current_staff_active()
      and (has_permission(p.id, 'core.staff.manage') or has_organization_permission(p.organization_id, 'core.staff.manage'))
  );
$$;

create or replace function get_pms_integration_status(p_hotel_id uuid default null)
returns table (
  hotel_id uuid,
  mode stay_source,
  ohip_hotel_code text,
  ohip_enterprise_id text,
  ohip_gateway_url text,
  has_credentials boolean,
  last_sync_at timestamptz,
  last_sync_status text,
  last_sync_error text
)
language plpgsql security definer stable set search_path = public as $$
declare
  v_hotel_id uuid;
  v_property_id uuid;
begin
  if not current_staff_active() then
    raise exception 'not authorized';
  end if;

  v_hotel_id := coalesce(p_hotel_id, current_staff_hotel());
  v_property_id := guest_requests_property_for_hotel(v_hotel_id);

  if v_property_id is null or not has_permission(v_property_id, 'guest_requests.pms.manage') then
    raise exception 'not authorized';
  end if;

  return query
    select p.hotel_id, p.mode, p.ohip_hotel_code, p.ohip_enterprise_id, p.ohip_gateway_url,
      (p.ohip_client_id is not null and p.ohip_client_secret is not null),
      p.last_sync_at, p.last_sync_status, p.last_sync_error
    from pms_integrations p
    where p.hotel_id = v_hotel_id
    union all
    select v_hotel_id, 'manual'::stay_source, null::text, null::text, null::text,
      false, null::timestamptz, null::text, null::text
    -- aliased `x` deliberately -- see 20260827122300's own header: this
    -- exact unqualified-hotel_id ambiguity (the function's `returns table
    -- (hotel_id uuid, ...)` clause implicitly declares a plpgsql variable
    -- named hotel_id for every OUT column) has already been reintroduced
    -- once before by a CREATE OR REPLACE that copied this function body
    -- without preserving the alias. Not repeating that mistake a third time.
    where not exists (select 1 from pms_integrations x where x.hotel_id = v_hotel_id);
end;
$$;

create or replace function save_pms_integration(
  p_hotel_id uuid,
  p_mode stay_source,
  p_ohip_hotel_code text,
  p_ohip_enterprise_id text,
  p_ohip_gateway_url text,
  p_ohip_client_id text,
  p_ohip_client_secret text,
  p_ohip_app_key text
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_hotel_id uuid;
  v_property_id uuid;
begin
  if not current_staff_active() then
    raise exception 'not authorized';
  end if;

  v_hotel_id := coalesce(p_hotel_id, current_staff_hotel());
  if v_hotel_id is null then
    raise exception 'hotel_id required';
  end if;

  v_property_id := guest_requests_property_for_hotel(v_hotel_id);
  if v_property_id is null or not has_permission(v_property_id, 'guest_requests.pms.manage') then
    raise exception 'not authorized';
  end if;

  insert into pms_integrations (
    hotel_id, mode, ohip_hotel_code, ohip_enterprise_id, ohip_gateway_url,
    ohip_client_id, ohip_client_secret, ohip_app_key
  )
  values (
    v_hotel_id, p_mode, p_ohip_hotel_code, p_ohip_enterprise_id, p_ohip_gateway_url,
    p_ohip_client_id, p_ohip_client_secret, p_ohip_app_key
  )
  on conflict (hotel_id) do update set
    mode = excluded.mode,
    ohip_hotel_code = excluded.ohip_hotel_code,
    ohip_enterprise_id = excluded.ohip_enterprise_id,
    ohip_gateway_url = excluded.ohip_gateway_url,
    ohip_client_id = coalesce(excluded.ohip_client_id, pms_integrations.ohip_client_id),
    ohip_client_secret = coalesce(excluded.ohip_client_secret, pms_integrations.ohip_client_secret),
    ohip_app_key = coalesce(excluded.ohip_app_key, pms_integrations.ohip_app_key);
end;
$$;

-- CREATE OR REPLACE preserves the grants already on all four functions
-- (authenticated: EXECUTE on all four; PUBLIC: none, revoked in
-- 20260827122100/20260827122500) -- nothing to re-grant here.

commit;
