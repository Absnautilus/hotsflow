-- Replaces "camera + cognome" with "camera + PIN" for guest login. Multi-
-- language guests shouldn't have to reproduce exactly how reception
-- transliterated their surname; a 4-digit PIN generated at check-in and
-- handed to the guest sidesteps that entirely, with equivalent security
-- (see rate limiting in guest_login — unchanged). guest_last_name stays on
-- stays for reception's own records and the personalized greeting; it's
-- just no longer part of the login check.

begin;

alter table stays add column guest_pin text;
update stays set guest_pin = lpad((floor(random() * 10000))::int::text, 4, '0') where guest_pin is null;
alter table stays alter column guest_pin set not null;
alter table stays alter column guest_pin set default lpad((floor(random() * 10000))::int::text, 4, '0');

drop function guest_login(uuid, text, text, inet);

create function guest_login(p_hotel_id uuid, p_room_number text, p_pin text, p_ip inet default null)
returns text
language plpgsql security definer set search_path = public, extensions as $$
declare
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

  -- one query: never let "room exists" and "PIN matches" be distinguishable
  select s.* into v_stay
  from stays s
  join rooms r on r.id = s.room_id
  where r.hotel_id = p_hotel_id
    and r.room_number = p_room_number
    and s.guest_pin = p_pin
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

grant execute on function guest_login(uuid, text, text, inet) to anon;

commit;
