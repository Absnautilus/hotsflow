-- I: sensitive SECURITY DEFINER functions are not callable by PUBLIC/anon,
-- and guest_session_is_valid is not callable by anyone at all yet (no
-- guest-facing flow exists in this phase — see migration 0011's header).
begin;
create extension if not exists pgtap;
select plan(3);

set local role anon;

select throws_ok(
  $$ select has_permission('00000000-0000-0000-0000-000000000000'::uuid, 'core.property.manage') $$,
  '42501',
  null,
  'anon cannot execute has_permission'
);

select throws_ok(
  $$ select assign_membership_role('00000000-0000-0000-0000-000000000000'::uuid, '00000000-0000-0000-0000-000000000000'::uuid) $$,
  '42501',
  null,
  'anon cannot execute assign_membership_role'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000000';

select throws_ok(
  $$ select guest_session_is_valid('00000000-0000-0000-0000-000000000000'::uuid, '00000000-0000-0000-0000-000000000000'::uuid, 10::smallint) $$,
  '42501',
  null,
  'authenticated cannot execute guest_session_is_valid either — no grant exists yet'
);

select * from finish();
rollback;
