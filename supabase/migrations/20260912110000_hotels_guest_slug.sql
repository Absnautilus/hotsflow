-- A short, readable, path-based slug for the single shared apps/guest
-- domain (https://<guest-domain>/<slug>), replacing the plain
-- hotels.id-in-the-URL approach. Generated automatically from the hotel's
-- name, with a numeric suffix on collision (`palazzo-veneziano`,
-- `palazzo-veneziano-2`, ...) -- never chosen by hand, so it can't be left
-- blank or produce a broken link.

begin;

alter table hotels add column guest_slug text unique;

create function slugify_hotel_name(p_name text) returns text
language sql immutable as $$
  select trim(both '-' from regexp_replace(lower(trim(p_name)), '[^a-z0-9]+', '-', 'g'));
$$;

-- Finds the first available slug starting from a base candidate, appending
-- -2, -3, ... on collision. p_exclude_id lets a row that already occupies
-- p_base (re-checking its own current slug) not collide with itself; leave
-- null when the row being assigned doesn't exist in the table yet (a
-- pre-insert check, see the trigger below).
create function next_available_hotel_slug(p_base text, p_exclude_id uuid default null) returns text
language plpgsql as $$
declare
  v_candidate text := p_base;
  v_suffix int := 1;
begin
  while exists (
    select 1 from hotels
    where guest_slug = v_candidate
      and (p_exclude_id is null or id <> p_exclude_id)
  ) loop
    v_suffix := v_suffix + 1;
    v_candidate := p_base || '-' || v_suffix;
  end loop;
  return v_candidate;
end;
$$;

-- Assigns (and persists) a unique guest_slug for one EXISTING hotel row,
-- deriving the base from its current name. Used by the one-time backfill
-- below; new rows get their slug from the before-insert trigger further
-- down instead, which needs its own variant since the row isn't in the
-- table yet at that point.
create function assign_hotel_guest_slug(p_hotel_id uuid) returns text
language plpgsql as $$
declare
  v_name text;
  v_slug text;
begin
  select name into v_name from hotels where id = p_hotel_id;
  v_slug := next_available_hotel_slug(slugify_hotel_name(v_name), p_hotel_id);
  update hotels set guest_slug = v_slug where id = p_hotel_id;
  return v_slug;
end;
$$;

-- Backfill every hotel that predates this migration (in production, just
-- Palazzo Veneziano after 20260911180000's fixture cleanup; in CI's fresh
-- database, whatever seed.sql or a given test's own fixture inserted before
-- this point in the replay).
do $$
declare
  r record;
begin
  for r in select id from hotels where guest_slug is null order by created_at loop
    perform assign_hotel_guest_slug(r.id);
  end loop;
end;
$$;

alter table hotels alter column guest_slug set not null;

-- Must run before insert, not after: the not-null constraint above is
-- checked against the row being inserted itself, so an after-insert trigger
-- can never satisfy it -- by the time it would run, the insert has already
-- failed. Setting NEW.guest_slug directly here also avoids a second
-- UPDATE statement per insert.
create function trigger_assign_hotel_guest_slug() returns trigger
language plpgsql as $$
begin
  new.guest_slug := next_available_hotel_slug(slugify_hotel_name(new.name));
  return new;
end;
$$;

create trigger hotels_assign_guest_slug
  before insert on hotels
  for each row execute function trigger_assign_hotel_guest_slug();

-- Guest-facing resolution: apps/guest reads the first path segment and
-- calls this to find which hotel it means. No RLS bypass beyond exactly
-- this one column-equivalent lookup, and only for an active hotel.
create function resolve_hotel_guest_slug(p_slug text) returns uuid
language sql stable security definer set search_path = public as $$
  select id from hotels where guest_slug = p_slug and active;
$$;

revoke all on function resolve_hotel_guest_slug(text) from public;
grant execute on function resolve_hotel_guest_slug(text) to anon;

-- Core-facing bridge for Settings' "Link accesso ospiti" row, mirroring
-- guest_requests_legacy_hotel_for_property's exact access check (any
-- member with access to the property and the guest_requests module
-- enabled -- no staff_profiles row required).
create function guest_requests_slug_for_property(p_property_id uuid) returns text
language sql stable security definer set search_path = public as $$
  select h.guest_slug
  from legacy_property_mapping m
  join hotels h on h.id = m.legacy_hotel_id
  where m.platform_property_id = p_property_id
    and has_property_access(p_property_id)
    and has_module(p_property_id, 'guest_requests')
  limit 1;
$$;

revoke all on function guest_requests_slug_for_property(uuid) from public;
grant execute on function guest_requests_slug_for_property(uuid) to authenticated;

commit;
