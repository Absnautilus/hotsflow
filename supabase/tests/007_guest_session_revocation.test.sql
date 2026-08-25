-- A revoked guest session is never valid, even if it hasn't expired yet.
begin;
create extension if not exists pgtap;
select plan(1);

insert into organizations (id, name, slug) values
  ('00000007-0000-0000-0000-000000000001', 'Test Org A', 'test-007-org-a');
insert into properties (id, organization_id, name, slug) values
  ('00000007-0000-0000-0000-000000000011', '00000007-0000-0000-0000-000000000001', 'Property A1', 'a1');

insert into guest_sessions (id, property_id, verification_method, verification_level, token_hash, expires_at, revoked_at)
values (
  '00000007-0000-0000-0000-000000000061', '00000007-0000-0000-0000-000000000011',
  'room_surname', 10, 'test-007-token', now() + interval '1 day', now()
);

set local role authenticated;

select ok(
  not guest_session_is_valid(
    '00000007-0000-0000-0000-000000000061'::uuid,
    '00000007-0000-0000-0000-000000000011'::uuid,
    10::smallint
  ),
  'a revoked guest session is not valid, regardless of its expiry'
);

select * from finish();
rollback;
