-- Fase 2 Step 8 — re-fixes a real regression found via live E2E testing
-- (a property_admin calling get_pms_integration_status() on their own,
-- entitled hotel got a genuine 400: "column reference \"hotel_id\" is
-- ambiguous", not an authorization error).
--
-- 20260827121700 already fixed this exact bug once (the function's
-- `returns table (hotel_id uuid, ...)` clause implicitly declares a
-- plpgsql variable named hotel_id for every OUT column, so an unqualified
-- `hotel_id` reference inside the body is ambiguous against
-- pms_integrations.hotel_id) by aliasing the table as `x` in the
-- UNION ALL branch's NOT EXISTS subquery. 20260827122100 (the
-- authorization-wrapper rewrite) then `create or replace`d this same
-- function for its own reason (has_permission()-based authorization) and,
-- in doing so, silently dropped that alias/qualification again — the
-- exact same bug came back. Not caught by the pgTAP suite, which tested
-- the denial paths but never a successful call. Same fix as before, no
-- other change.
begin;

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
    where not exists (select 1 from pms_integrations x where x.hotel_id = v_hotel_id);
end;
$$;

commit;
