-- Lets the guest UI show a personalized greeting (room number, surname)
-- without exposing the stays table itself to anon.
create function guest_stay_info(p_token text) returns table(room_number text, guest_last_name text, check_out_at timestamptz)
language sql security definer stable set search_path = public, extensions as $$
  select r.room_number, s.guest_last_name, s.check_out_at
  from guest_requests_guest_sessions gs
  join stays s on s.id = gs.stay_id
  join rooms r on r.id = s.room_id
  where gs.token_hash = encode(digest(p_token, 'sha256'), 'hex')
    and gs.revoked_at is null
    and gs.expires_at > now()
    and s.status = 'active'
    and now() < s.check_out_at
  limit 1;
$$;

grant execute on function guest_stay_info(text) to anon;
