-- Fase 2 Step 3 — tenant adapter for guest_requests.
--
-- hotels.id is referenced by too many FKs (rooms, stays, staff_profiles,
-- request_categories, pms_integrations, guest_login_attempts, guest_requests)
-- for a safe direct swap to property_id — see the Fase 2 decision document,
-- Decision-adjacent §5.B. Instead: one core `organization` + one core
-- `property` per existing hotel (1:1, no invented hierarchy), linked back to
-- hotels via legacy_property_mapping. Nothing else changes: hotels, its FKs,
-- staff_profiles, permissions, RLS, and the guest flow are all untouched by
-- this migration.

begin;

create table legacy_property_mapping (
  legacy_hotel_id uuid primary key references hotels(id),
  platform_property_id uuid not null unique references properties(id),
  created_at timestamptz not null default now()
);

-- Backend bookkeeping only, not client-facing yet — no RLS policy, no grant
-- to authenticated/anon, matching the same "RLS enabled, zero policies,
-- reachable only through a controlled function" pattern already used for
-- guest_requests_guest_sessions (0003_rls.sql). Nothing in core or in this
-- module reads from this table for any authorization decision in Step 3.
alter table legacy_property_mapping enable row level security;

-- Deterministic slug from a hotel name: unaccent, lowercase, collapse any
-- run of non-alphanumeric characters to a single hyphen, trim hyphens from
-- both ends. Reuses immutable_unaccent (0001_init.sql) rather than adding a
-- second unaccenting helper.
create function legacy_hotel_slug(p_name text) returns text
language sql immutable set search_path = public, extensions as $$
  select trim(both '-' from regexp_replace(lower(immutable_unaccent(p_name)), '[^a-z0-9]+', '-', 'g'));
$$;

-- Backfill, safe to call more than once: any hotel already present in
-- legacy_property_mapping is skipped, so re-invoking this (e.g. after a new
-- hotel is added to a demo dataset, or when a test calls it twice to prove
-- idempotency) never creates a duplicate organization/property. Not a
-- client-facing RPC — no grant to authenticated/anon (organizations has no
-- INSERT grant for authenticated at all, see 0007's comment), only ever run
-- by the migration itself or, in tests, by the connecting/superuser role.
create function backfill_legacy_property_mapping() returns void
language plpgsql as $$
declare
  h record;
  v_org_id uuid;
  v_property_id uuid;
  v_slug text;
begin
  for h in select * from hotels order by id loop
    if exists (select 1 from legacy_property_mapping where legacy_hotel_id = h.id) then
      continue;
    end if;

    v_slug := legacy_hotel_slug(h.name);
    if v_slug is null or v_slug = '' then
      v_slug := 'hotel';
    end if;

    -- organizations.slug is unique platform-wide; two hotels with the same
    -- (or same-after-slugifying) name would otherwise collide. Append a
    -- short deterministic suffix derived from the hotel's own id only when
    -- an actual collision is detected, so the common case stays readable.
    if exists (select 1 from organizations where slug = v_slug) then
      v_slug := v_slug || '-' || left(replace(h.id::text, '-', ''), 8);
    end if;

    insert into organizations (name, slug) values (h.name, v_slug)
      returning id into v_org_id;

    -- properties.slug only needs to be unique within its organization
    -- (organization_id, slug) — with a strict 1:1 org:property mapping, the
    -- same slug can never collide with a sibling property, so it's reused
    -- as-is rather than deriving a second one.
    insert into properties (organization_id, name, slug, timezone, status)
      values (
        v_org_id,
        h.name,
        v_slug,
        h.timezone,
        case when h.active then 'active' else 'suspended' end
      )
      returning id into v_property_id;

    insert into legacy_property_mapping (legacy_hotel_id, platform_property_id)
      values (h.id, v_property_id);
  end loop;
end;
$$;

revoke all on function backfill_legacy_property_mapping() from public;

select backfill_legacy_property_mapping();

commit;
