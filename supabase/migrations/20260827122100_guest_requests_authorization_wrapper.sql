-- Fase 2 Step 6 — guest_requests RLS wrapper / authoritative role source.
--
-- Ground-truth policy inventory (queried directly from pg_policies, not
-- inferred) showed master has a GLOBAL bypass only on `hotels` and
-- `staff_profiles` — every other table (rooms, stays, guest_requests,
-- request_categories, request_types, guest_login_attempts) gates master
-- exactly like admin: `hotel_id = current_staff_hotel() AND role IN
-- ('admin','master')`, scoped to their own staff_profiles.hotel_id, never
-- org-wide. Approved design (explicit decision after this was flagged):
-- current_staff_hotel() keeps deriving the LEGACY hotel_id from the
-- caller's own staff_profiles.hotel_id (module-local operational context,
-- unchanged), and only uses core (has_property_access/has_module) to decide
-- whether to return it at all or NULL. This reproduces the legacy
-- single-hotel scoping for those 6 tables exactly, with no widening, no
-- extra membership, and no change to Step 4's approved data.
--
-- Staff management (core.staff.manage) and PMS (guest_requests.pms.manage)
-- are different, already-approved capability gates — explicitly NOT
-- derived from rank/current_staff_role() translation, and ARE org-wide for
-- organization_admin (has_permission()/has_organization_permission()'s own
-- OR-branch), per the approved matrix.

begin;

-- ---------------------------------------------------------------------------
-- new permission: guest_requests.pms.manage (matrix row 6)
-- ---------------------------------------------------------------------------
insert into permissions (slug, module_id)
select 'guest_requests.pms.manage', id from modules where slug = 'guest_requests'
on conflict (slug) do nothing;

insert into role_permissions (role_id, permission_id)
select r.id, p.id from roles r, permissions p
where p.slug = 'guest_requests.pms.manage' and r.slug in ('property_admin', 'organization_admin')
on conflict (role_id, permission_id) do nothing;

-- ---------------------------------------------------------------------------
-- module-local helpers (row-level: "for THIS hotel_id, does the caller have
-- access/permission" — not the caller's own single hotel). Used only by the
-- staff_profiles policies below, which must support organization-wide reach
-- (matrix rows 1 and 7a) and therefore can't reuse the single-value
-- current_staff_hotel() pattern.
-- ---------------------------------------------------------------------------
create function guest_requests_property_for_hotel(p_hotel_id uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select platform_property_id from legacy_property_mapping where legacy_hotel_id = p_hotel_id;
$$;

create function guest_requests_staff_roster_visible(p_hotel_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from legacy_property_mapping m
    join properties p on p.id = m.platform_property_id
    where m.legacy_hotel_id = p_hotel_id
      and (has_property_access(p.id) or has_organization_access(p.organization_id))
  );
$$;

create function guest_requests_staff_manage_allowed(p_hotel_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from legacy_property_mapping m
    join properties p on p.id = m.platform_property_id
    where m.legacy_hotel_id = p_hotel_id
      and (has_permission(p.id, 'core.staff.manage') or has_organization_permission(p.organization_id, 'core.staff.manage'))
  );
$$;

revoke all on function guest_requests_property_for_hotel(uuid) from public;
revoke all on function guest_requests_staff_roster_visible(uuid) from public;
revoke all on function guest_requests_staff_manage_allowed(uuid) from public;
grant execute on function guest_requests_property_for_hotel(uuid) to authenticated;
grant execute on function guest_requests_staff_roster_visible(uuid) to authenticated;
grant execute on function guest_requests_staff_manage_allowed(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- current_staff_hotel() — same contract, same signature, same "one hotel"
-- shape as the legacy version. Source of the hotel_id value itself is
-- unchanged (staff_profiles.hotel_id, module-local operational context, as
-- decided) — core only gates WHETHER to return it: an active membership
-- covering the mapped property (direct or org-wide) AND the module actually
-- entitled there. staff_profiles.active is kept as an additional required
-- condition (dual gate, as decided) alongside memberships.status='active'
-- (the latter enforced inside has_property_access itself).
-- ---------------------------------------------------------------------------
create or replace function current_staff_hotel() returns uuid
language sql security definer stable set search_path = public as $$
  select sp.hotel_id
  from staff_profiles sp
  join legacy_property_mapping m on m.legacy_hotel_id = sp.hotel_id
  where sp.auth_user_id = auth.uid()
    and sp.active
    and has_property_access(m.platform_property_id)
    and has_module(m.platform_property_id, 'guest_requests')
  limit 1;
$$;

-- ---------------------------------------------------------------------------
-- current_staff_role() — no longer reads staff_profiles.role. Derives the
-- legacy enum value from the caller's core rank at the SAME property
-- current_staff_hotel() would resolve (property-scoped or org-wide,
-- current_actor_role_rank already treats either as sufficient). Every
-- existing call site combines this with `hotel_id = current_staff_hotel()`
-- in the same predicate (verified against the full pg_policies inventory),
-- so it doesn't need to re-check access/entitlement itself.
-- 'manager' (rank 20) has no legacy equivalent — D2 never produces one from
-- existing data; a future manager promotion (out of scope here) would see
-- guest_requests as having no resolvable role, a known, documented gap.
-- ---------------------------------------------------------------------------
create or replace function current_staff_role() returns staff_role
language sql security definer stable set search_path = public as $$
  select case current_actor_role_rank(m.platform_property_id)
    when 40 then 'master'::staff_role
    when 30 then 'admin'::staff_role
    when 10 then 'operatore'::staff_role
    else null
  end
  from staff_profiles sp
  join legacy_property_mapping m on m.legacy_hotel_id = sp.hotel_id
  where sp.auth_user_id = auth.uid()
    and sp.active
  limit 1;
$$;

-- ---------------------------------------------------------------------------
-- current_staff_is_master() — no longer `current_staff_role() = 'master'`
-- reading staff_profiles.role; checks directly for an active
-- organization_admin-role membership anywhere (matches D2: master holds one
-- such membership per existing organization). staff_profiles.active kept
-- as the same dual-gate condition as every other wrapper here.
-- ---------------------------------------------------------------------------
create or replace function current_staff_is_master() returns boolean
language sql security definer stable set search_path = public as $$
  select exists (
    select 1
    from staff_profiles sp
    join memberships m on m.profile_id = sp.auth_user_id
    join roles r on r.id = m.role_id
    where sp.auth_user_id = auth.uid()
      and sp.active
      and m.status = 'active'
      and r.slug = 'organization_admin'
  );
$$;

-- current_staff_department() and current_staff_manages_front_desk() are
-- intentionally NOT redefined: neither ever read staff_profiles.role or
-- staff_profiles.hotel_id directly, and current_staff_manages_front_desk()
-- is already built compositionally on current_staff_role()/
-- current_staff_department() — its existing, unmodified body already
-- implements the approved "property_admin-or-higher OR department =
-- 'reception'" logic once current_staff_role() resolves through core.

-- These 3 functions never had PUBLIC execute revoked (verified: no
-- revoke/grant statement exists for them anywhere in the original 18
-- migrations — only the guest-facing RPCs in this same file got that
-- treatment). Closing that gap now, since all 3 are being redefined here
-- anyway; current_staff_department() and current_staff_manages_front_desk()
-- are left as they are (out of scope, not touched by this migration).
revoke all on function current_staff_hotel() from public;
revoke all on function current_staff_role() from public;
revoke all on function current_staff_is_master() from public;
grant execute on function current_staff_hotel() to authenticated;
grant execute on function current_staff_role() to authenticated;
grant execute on function current_staff_is_master() to authenticated;

-- ---------------------------------------------------------------------------
-- staff_profiles: roster visibility (7a) and staff management (row 1) now
-- use the approved capability gates directly — core.staff.manage for
-- writes, membership-only for read visibility — instead of the legacy
-- current_staff_role() = 'admin' / current_staff_is_master() bypass. This
-- is deliberately organization-wide (unlike current_staff_hotel() above):
-- matrix rows 1 and 7a call for has_permission/has_organization_permission
-- and has_property_access/has_organization_access respectively, and
-- staff_profiles' own policies are per-row already (not a single-value
-- session function), so there is no single-hotel-value limitation here.
-- ---------------------------------------------------------------------------
drop policy staff_profiles_select_scoped on staff_profiles;
create policy staff_profiles_select_scoped on staff_profiles for select to authenticated
  using (guest_requests_staff_roster_visible(hotel_id));

drop policy staff_profiles_write_scoped on staff_profiles;
create policy staff_profiles_write_scoped on staff_profiles for all to authenticated
  using (guest_requests_staff_manage_allowed(hotel_id))
  with check (guest_requests_staff_manage_allowed(hotel_id));

-- staff_profiles.role: readable for compatibility/debug, no longer usable
-- by any authorization check (verified above), and no longer client-
-- writable at all — direct writes could set it to anything with zero
-- effect on real authorization, but leaving it writable would still be
-- confusing/misleading, and role changes must go exclusively through
-- assign_membership_role() (core.roles.assign) from here on. staff
-- creation itself (which does set an initial role, for the
-- staff_profiles_department_matches_role / _login_username_matches_role
-- CHECK constraints to validate against) already runs through the
-- create-staff-account Edge Function under the service-role key, which
-- bypasses these grants entirely — unaffected by this change.
revoke insert, update on staff_profiles from authenticated;
grant insert (hotel_id, auth_user_id, name, department, active, login_username) on staff_profiles to authenticated;
grant update (hotel_id, auth_user_id, name, department, active, login_username, on_duty) on staff_profiles to authenticated;

-- ---------------------------------------------------------------------------
-- PMS: guest_requests.pms.manage replaces the current_staff_role()-based
-- check entirely (matrix: "non derivarla dal solo rank"). has_permission()
-- already folds in module entitlement automatically for module-owned
-- permissions, so a property with guest_requests disabled is correctly
-- denied here too, which the legacy role check never verified.
--
-- Also closes a real latent bug found while rewriting this: the legacy
-- `if current_staff_role() not in ('admin','master') then raise` used NULL
-- for an unrecognized/anonymous caller, and `NULL NOT IN (...)` evaluates
-- to NULL — falsy in a PL/pgSQL IF, so the exception was never raised, and
-- execution fell through to the query for ANY caller able to invoke the
-- function at all. Both functions also never had PUBLIC execute revoked
-- (same gap as the 3 helpers above), which combined with that NULL-
-- swallowing bug meant PMS status (though not the stored credentials
-- themselves — only a boolean has_credentials flag) was structurally
-- readable by anon. has_permission() has no such gap: it requires
-- m.profile_id = auth.uid(), which can never match for anon (NULL), so it
-- returns false rather than NULL, and the IF here correctly raises.
-- ---------------------------------------------------------------------------
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
    where not exists (select 1 from pms_integrations where hotel_id = v_hotel_id);
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

-- CREATE OR REPLACE preserves the original explicit `grant execute ... to
-- authenticated` from 20260827121000_guest_requests_pms_integration.sql;
-- only PUBLIC was never revoked for these two, closed here.
revoke all on function get_pms_integration_status(uuid) from public;
revoke all on function save_pms_integration(uuid, stay_source, text, text, text, text, text, text) from public;
grant execute on function get_pms_integration_status(uuid) to authenticated;
grant execute on function save_pms_integration(uuid, stay_source, text, text, text, text, text, text) to authenticated;

commit;
