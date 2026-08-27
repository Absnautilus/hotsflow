-- get_pms_integration_status()'s `returns table (hotel_id uuid, ...)` clause
-- implicitly declares a plpgsql variable named hotel_id for every OUT column.
-- The union-all branch's `where not exists (select 1 from pms_integrations
-- where hotel_id = v_hotel_id)` referenced hotel_id unqualified, which
-- Postgres can't resolve between that OUT variable and
-- pms_integrations.hotel_id — raising "column reference \"hotel_id\" is
-- ambiguous" on every call. Same fix as the first branch already used
-- (table alias + qualified column).
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
begin
  if current_staff_role() not in ('admin', 'master') then
    raise exception 'not authorized';
  end if;

  v_hotel_id := coalesce(p_hotel_id, current_staff_hotel());
  if current_staff_role() = 'admin' and v_hotel_id is distinct from current_staff_hotel() then
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
