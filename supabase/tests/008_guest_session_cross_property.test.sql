-- A guest session issued for one property must not validate against a
-- different property, even within the same organization.
begin;
create extension if not exists pgtap;
select plan(2);

insert into organizations (id, name, slug) values
  ('00000008-0000-0000-0000-000000000001', 'Test Org A', 'test-008-org-a');
insert into properties (id, organization_id, name, slug) values
  ('00000008-0000-0000-0000-000000000011', '00000008-0000-0000-0000-000000000001', 'Property A1', 'a1'),
  ('00000008-0000-0000-0000-000000000012', '00000008-0000-0000-0000-000000000001', 'Property A2', 'a2');

insert into guest_sessions (id, property_id, verification_method, verification_level, token_hash, expires_at)
values (
  '00000008-0000-0000-0000-000000000061', '00000008-0000-0000-0000-000000000011',
  'room_surname', 10, 'test-008-token', now() + interval '1 day'
);

-- No role switch — see 006's comment: guest_session_is_valid() has no
-- client-facing grant as of Fase 1.1, this tests its logic directly.
select ok(
  not guest_session_is_valid(
    '00000008-0000-0000-0000-000000000061'::uuid,
    '00000008-0000-0000-0000-000000000012'::uuid,
    10::smallint
  ),
  'a session issued for property A1 is not valid when checked against property A2'
);
select ok(
  guest_session_is_valid(
    '00000008-0000-0000-0000-000000000061'::uuid,
    '00000008-0000-0000-0000-000000000011'::uuid,
    10::smallint
  ),
  'the same session is valid when checked against the property it was actually issued for'
);

select * from finish();
rollback;
