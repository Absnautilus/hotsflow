-- RPC functions — the only way anon (guests) ever touches guest data.
-- All SECURITY DEFINER, all revoked from PUBLIC by default and re-granted
-- explicitly at the bottom of this file.

-- ---------------------------------------------------------------------------
-- staff helpers, used inside RLS policies to avoid recursive policy checks
-- ---------------------------------------------------------------------------
create function current_staff_hotel() returns uuid
language sql security definer stable set search_path = public as $$
  select hotel_id from staff_profiles where auth_user_id = auth.uid() and active limit 1;
$$;

create function current_staff_role() returns staff_role
language sql security definer stable set search_path = public as $$
  select role from staff_profiles where auth_user_id = auth.uid() and active limit 1;
$$;

create function current_staff_department() returns department
language sql security definer stable set search_path = public as $$
  select department from staff_profiles where auth_user_id = auth.uid() and active limit 1;
$$;

-- front-desk duties (managing stays, rooms is admin-only separately) are
-- open to admin and to operatore whose department is reception
create function current_staff_manages_front_desk() returns boolean
language sql security definer stable set search_path = public as $$
  select current_staff_role() = 'admin'
    or (current_staff_role() = 'operatore' and current_staff_department() = 'reception');
$$;

-- ---------------------------------------------------------------------------
-- guest_login — camera + cognome, single query, generic outcome either way
-- ---------------------------------------------------------------------------
create function guest_login(p_hotel_id uuid, p_room_number text, p_last_name text, p_ip inet default null)
returns text
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_normalized text := normalize_guest_name(p_last_name);
  v_stay stays%rowtype;
  v_recent_attempts int;
  v_token text;
begin
  select count(*) into v_recent_attempts
  from guest_login_attempts
  where hotel_id = p_hotel_id
    and created_at > now() - interval '15 minutes'
    and (ip_address = p_ip or room_number_attempted = p_room_number);

  if v_recent_attempts >= 8 then
    insert into guest_login_attempts (hotel_id, ip_address, room_number_attempted, succeeded)
    values (p_hotel_id, p_ip, p_room_number, false);
    return null;
  end if;

  -- one query: never let "room exists" and "surname matches" be distinguishable
  select s.* into v_stay
  from stays s
  join rooms r on r.id = s.room_id
  where r.hotel_id = p_hotel_id
    and r.room_number = p_room_number
    and s.guest_last_name_normalized = v_normalized
    and s.status = 'active'
    and now() >= s.check_in_at
    and now() < s.check_out_at
  order by s.check_in_at desc
  limit 1;

  insert into guest_login_attempts (hotel_id, ip_address, room_number_attempted, succeeded)
  values (p_hotel_id, p_ip, p_room_number, v_stay.id is not null);

  if v_stay.id is null then
    return null;
  end if;

  v_token := encode(gen_random_bytes(32), 'hex');

  insert into guest_requests_guest_sessions (stay_id, token_hash, expires_at, created_ip)
  values (v_stay.id, encode(digest(v_token, 'sha256'), 'hex'), v_stay.check_out_at, p_ip);

  return v_token;
end;
$$;

-- ---------------------------------------------------------------------------
-- internal only — never granted to anon directly
-- ---------------------------------------------------------------------------
create function guest_stay_from_token(p_token text) returns stays
language sql security definer stable set search_path = public, extensions as $$
  select s.*
  from guest_requests_guest_sessions gs
  join stays s on s.id = gs.stay_id
  where gs.token_hash = encode(digest(p_token, 'sha256'), 'hex')
    and gs.revoked_at is null
    and gs.expires_at > now()
    and s.status = 'active'
    and now() < s.check_out_at
  limit 1;
$$;

-- ---------------------------------------------------------------------------
-- create_guest_request
-- ---------------------------------------------------------------------------
create function create_guest_request(p_token text, p_request_type_id uuid, p_quantity int default null, p_note text default null)
returns guest_requests
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_stay stays%rowtype;
  v_request guest_requests%rowtype;
begin
  v_stay := guest_stay_from_token(p_token);
  if v_stay.id is null then
    raise exception 'invalid_session' using errcode = '28000';
  end if;

  update guest_requests_guest_sessions set last_seen_at = now()
    where token_hash = encode(digest(p_token, 'sha256'), 'hex');

  insert into guest_requests (hotel_id, stay_id, request_type_id, quantity, note, assigned_department)
  values (v_stay.hotel_id, v_stay.id, p_request_type_id, p_quantity, p_note, null)
  returning * into v_request;

  return v_request;
end;
$$;

-- ---------------------------------------------------------------------------
-- list_my_requests
-- ---------------------------------------------------------------------------
create function list_my_requests(p_token text) returns setof guest_requests
language plpgsql security definer stable set search_path = public as $$
declare
  v_stay stays%rowtype;
begin
  v_stay := guest_stay_from_token(p_token);
  if v_stay.id is null then
    raise exception 'invalid_session' using errcode = '28000';
  end if;

  return query
    select * from guest_requests where stay_id = v_stay.id order by created_at desc;
end;
$$;

-- ---------------------------------------------------------------------------
-- cancel_my_request — guest can only cancel while still untouched by staff
-- ---------------------------------------------------------------------------
create function cancel_my_request(p_token text, p_request_id uuid) returns guest_requests
language plpgsql security definer set search_path = public as $$
declare
  v_stay stays%rowtype;
  v_request guest_requests%rowtype;
begin
  v_stay := guest_stay_from_token(p_token);
  if v_stay.id is null then
    raise exception 'invalid_session' using errcode = '28000';
  end if;

  update guest_requests
    set status = 'cancelled'
    where id = p_request_id and stay_id = v_stay.id and status = 'requested'
    returning * into v_request;

  if v_request.id is null then
    raise exception 'request_not_cancellable' using errcode = '22023';
  end if;

  return v_request;
end;
$$;

-- ---------------------------------------------------------------------------
-- grants — anon gets only the RPC surface, nothing on the tables themselves
-- ---------------------------------------------------------------------------
revoke execute on function guest_stay_from_token(text) from public;

grant execute on function guest_login(uuid, text, text, inet) to anon;
grant execute on function create_guest_request(text, uuid, int, text) to anon;
grant execute on function list_my_requests(text) to anon;
grant execute on function cancel_my_request(text, uuid) to anon;
