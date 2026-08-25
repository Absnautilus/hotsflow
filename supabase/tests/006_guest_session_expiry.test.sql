-- An expired guest session is never valid, regardless of everything else
-- about it.
begin;
create extension if not exists pgtap;
select plan(1);

insert into organizations (id, name, slug) values
  ('00000006-0000-0000-0000-000000000001', 'Test Org A', 'test-006-org-a');
insert into properties (id, organization_id, name, slug) values
  ('00000006-0000-0000-0000-000000000011', '00000006-0000-0000-0000-000000000001', 'Property A1', 'a1');

-- created_at is backdated so expires_at can legitimately be in the past
-- while still satisfying guest_sessions_expires_after_created.
insert into guest_sessions (id, property_id, verification_method, verification_level, token_hash, created_at, expires_at)
values (
  '00000006-0000-0000-0000-000000000061', '00000006-0000-0000-0000-000000000011',
  'room_surname', 10, 'test-006-token', now() - interval '2 days', now() - interval '1 hour'
);

set local role authenticated;

select ok(
  not guest_session_is_valid(
    '00000006-0000-0000-0000-000000000061'::uuid,
    '00000006-0000-0000-0000-000000000011'::uuid,
    10::smallint
  ),
  'an expired guest session is not valid'
);

select * from finish();
rollback;
