-- Lets a hotel admin choose, per hotel, between manual room/stay management
-- (as today) and an automatic feed from OperaCloud via OHIP (Oracle
-- Hospitality Integration Platform). Only the mode and non-secret config
-- are ever readable by the browser; OHIP credentials only ever flow through
-- the SECURITY DEFINER functions below (which never return them once
-- saved — the same "write-only" convention Vercel uses for Sensitive env
-- vars) or through the sync-pms-stays edge function's service-role client.

create table pms_integrations (
  hotel_id uuid primary key references hotels(id) on delete cascade,
  mode stay_source not null default 'manual',
  ohip_hotel_code text,
  ohip_enterprise_id text,
  ohip_gateway_url text,
  ohip_client_id text,
  ohip_client_secret text,
  ohip_app_key text,
  last_sync_at timestamptz,
  last_sync_status text check (last_sync_status in ('success', 'error')),
  last_sync_error text,
  updated_at timestamptz not null default now()
);

alter table pms_integrations enable row level security;
-- deliberately no policies for anon/authenticated: this table is only ever
-- touched through the SECURITY DEFINER functions below, or by the edge
-- function's service-role client (which bypasses RLS entirely).

create trigger pms_integrations_set_updated_at
  before update on pms_integrations
  for each row execute function set_updated_at();

create function get_pms_integration_status(p_hotel_id uuid default null)
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
    where not exists (select 1 from pms_integrations where hotel_id = v_hotel_id);
end;
$$;

grant execute on function get_pms_integration_status(uuid) to authenticated;

create function save_pms_integration(
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
begin
  if current_staff_role() not in ('admin', 'master') then
    raise exception 'not authorized';
  end if;

  if current_staff_role() = 'admin' then
    if p_hotel_id is not null and p_hotel_id is distinct from current_staff_hotel() then
      raise exception 'not authorized';
    end if;
    v_hotel_id := current_staff_hotel();
  else
    v_hotel_id := coalesce(p_hotel_id, current_staff_hotel());
  end if;

  if v_hotel_id is null then
    raise exception 'hotel_id required';
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
    -- blank on the form = "leave unchanged": a secret already saved is
    -- never sent back to the browser to be resubmitted, so a blank field
    -- here must not overwrite it with null.
    ohip_client_id = coalesce(excluded.ohip_client_id, pms_integrations.ohip_client_id),
    ohip_client_secret = coalesce(excluded.ohip_client_secret, pms_integrations.ohip_client_secret),
    ohip_app_key = coalesce(excluded.ohip_app_key, pms_integrations.ohip_app_key);
end;
$$;

grant execute on function save_pms_integration(uuid, stay_source, text, text, text, text, text, text) to authenticated;
