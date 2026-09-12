-- device_push_subscriptions is scoped strictly to its owning profile: a
-- profile can create/see/delete only its own rows, never another
-- profile's, regardless of module access.
begin;
create extension if not exists pgtap;
select plan(4);

insert into auth.users (id) values
  ('00000043-0000-0000-0000-000000000001'),
  ('00000043-0000-0000-0000-000000000002');
insert into profiles (id, full_name) values
  ('00000043-0000-0000-0000-000000000001', 'Device Owner'),
  ('00000043-0000-0000-0000-000000000002', 'Other Profile');

set local role authenticated;
set local request.jwt.claim.sub = '00000043-0000-0000-0000-000000000001';

insert into device_push_subscriptions (profile_id, endpoint, p256dh, auth) values
  ('00000043-0000-0000-0000-000000000001', 'https://push.example/ep-043', 'p256dh-043', 'auth-043');

select is(
  (select count(*)::int from device_push_subscriptions where endpoint = 'https://push.example/ep-043'),
  1,
  'the owning profile sees its own subscription'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000043-0000-0000-0000-000000000002';

select is(
  (select count(*)::int from device_push_subscriptions where endpoint = 'https://push.example/ep-043'),
  0,
  'a different profile cannot see another profile''s subscription'
);

delete from device_push_subscriptions where endpoint = 'https://push.example/ep-043';

reset role;

select is(
  (select count(*)::int from device_push_subscriptions where endpoint = 'https://push.example/ep-043'),
  1,
  'a different profile''s delete attempt is silently scoped away -- the row still exists'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000043-0000-0000-0000-000000000001';

delete from device_push_subscriptions where endpoint = 'https://push.example/ep-043';

reset role;

select is(
  (select count(*)::int from device_push_subscriptions where endpoint = 'https://push.example/ep-043'),
  0,
  'the owning profile can delete its own subscription'
);

select * from finish();
rollback;
