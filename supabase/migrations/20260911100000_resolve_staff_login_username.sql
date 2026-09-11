-- create-team-member-credentials's own header already says the plain
-- username is meant to be the only thing the admin and the staff member
-- ever see or type -- the synthetic auth.users email
-- (username@property-slug.org-slug.staff.hotsflow.internal) is an
-- implementation detail. That promise was never actually kept: nothing
-- translated a bare username back into the synthetic email at sign-in
-- time, so the login screen still required the full synthetic address.
--
-- username is only unique per property (memberships_property_username_unique
-- in 20260910120000), by design -- two unrelated properties are free to both
-- hand out "mario". So resolving a bare username can yield zero, one, or
-- more than one match; the caller (the login screen) proceeds automatically
-- on exactly one match and asks the person to be more specific otherwise.
-- Same rate-limiting shape as guest_login (20260827120000/1200100): an
-- anon-callable, SECURITY DEFINER function is the only way to read
-- memberships.username pre-auth, and repeated lookups from the same
-- IP/username are throttled the same way.

create table staff_login_lookup_attempts (
  id uuid primary key default gen_random_uuid(),
  ip_address inet,
  username_attempted text,
  created_at timestamptz not null default now()
);

create index staff_login_lookup_attempts_ip_idx
  on staff_login_lookup_attempts (ip_address, created_at);
create index staff_login_lookup_attempts_username_idx
  on staff_login_lookup_attempts (username_attempted, created_at);

alter table staff_login_lookup_attempts enable row level security;
-- No policies: not even authenticated can read this directly. The
-- resolver function below is SECURITY DEFINER, so it bypasses RLS to
-- write here regardless.

-- ---------------------------------------------------------------------------
-- resolve_staff_login_identifier
-- ---------------------------------------------------------------------------
-- Returns every synthesized login identifier whose membership carries this
-- username, across all properties. Rate-limited per IP and per username
-- attempted (15-minute window, matching guest_login's window); over the
-- limit returns an empty array rather than an error, so a lockout can't be
-- used to distinguish "too many attempts" from "no such username" either.
create function resolve_staff_login_identifier(p_username text, p_ip inet default null)
returns text[]
language plpgsql security definer set search_path = public as $$
declare
  v_recent_attempts int;
  v_identifiers text[];
begin
  select count(*) into v_recent_attempts
  from staff_login_lookup_attempts
  where created_at > now() - interval '15 minutes'
    and (ip_address = p_ip or username_attempted = p_username);

  if v_recent_attempts >= 20 then
    return array[]::text[];
  end if;

  insert into staff_login_lookup_attempts (ip_address, username_attempted)
  values (p_ip, p_username);

  select array_agg(
    m.username || '@' || p.slug || '.' || o.slug || '.staff.hotsflow.internal'
    order by m.id
  )
  into v_identifiers
  from memberships m
  join properties p on p.id = m.property_id
  join organizations o on o.id = p.organization_id
  where m.username = p_username;

  return coalesce(v_identifiers, array[]::text[]);
end;
$$;

revoke all on function resolve_staff_login_identifier(text, inet) from public;
grant execute on function resolve_staff_login_identifier(text, inet) to anon;
