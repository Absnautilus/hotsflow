begin;

-- Development-phase cleanup of test/rehearsal fixtures left in the shared
-- production Supabase project, explicitly authorized by the platform
-- owner. End state: her own real account (Ana Beatrice Simone, Palazzo
-- Veneziano, master) and Francesco Breda's real Hotsflow Team auth
-- identity are the only two Supabase Auth users this migration leaves
-- behind that were touched by any of this session's Housekeeping/Team
-- testing. Everything else here is either an E2E/rehearsal fixture (three
-- entirely synthetic "Hotel Demo*" properties, never a real hotel) or a
-- duplicate Housekeeping identity: grant-housekeeping-access bridges a
-- Team member into staff_profiles by auth_user_id, which cannot detect a
-- person who already had a *separate* native Housekeeping account under a
-- different auth identity -- exactly what happened for Francesco Breda
-- (native "fbreda" PIN account, auth_user_id 6f3a511e-...) and would have
-- kept happening for anyone else in the same situation.
--
-- Deletes are specified as explicit inclusion lists (delete exactly these
-- ids), never as "delete everyone except X": a typo in an inclusion list
-- under-deletes (harmless leftover test data); a typo in an exclusion
-- list could delete the one row that must survive. Fail safe, not fail
-- dangerous.

create temporary table _cleanup_demo_hotel_ids (id uuid) on commit drop;
insert into _cleanup_demo_hotel_ids (id) values
  ('00000000-0000-0000-0000-000000000001'), -- Hotel Demo
  ('00000000-0000-0000-0000-000000000002'), -- Hotel Demo 2 (E2E Test)
  ('00000000-0000-0000-0000-000000000003'); -- Hotel Demo 3 (E2E cross-org boundary)

-- The two Palazzo Veneziano staff_profiles rows to remove. Francesco
-- Breda's OTHER staff_profiles row (32296ed1-..., auth_user_id
-- e64a27f8-..., his real Team-bridged Housekeeping profile) is
-- deliberately NOT in this list -- it IS the correct bridge, kept as-is.
create temporary table _cleanup_staff_profile_ids (id uuid) on commit drop;
insert into _cleanup_staff_profile_ids (id) values
  ('c427faa3-1030-430f-883d-5c6c905e2b22'), -- Farouk (no Team account at all)
  ('5bb9c3c7-a318-4d67-9244-4a998e8dc132'); -- Francesco Breda, old native "fbreda" PIN account

-- Detach (never delete) any stray staff attribution on Palazzo
-- Veneziano's own real data pointing at the two rows above -- this
-- hotel's own guest_requests/stays are real and must survive untouched
-- otherwise.
update stays set created_by = null
  where created_by in (select id from _cleanup_staff_profile_ids);
update guest_requests set accepted_by = null
  where accepted_by in (select id from _cleanup_staff_profile_ids);
update guest_requests set created_by_staff = null
  where created_by_staff in (select id from _cleanup_staff_profile_ids);

-- Full wipe of the three demo hotels' own data, deepest-dependency-first.
delete from guest_requests where hotel_id in (select id from _cleanup_demo_hotel_ids);
delete from guest_requests_guest_sessions where stay_id in (
  select id from stays where hotel_id in (select id from _cleanup_demo_hotel_ids)
);
delete from stays where hotel_id in (select id from _cleanup_demo_hotel_ids);
delete from rooms where hotel_id in (select id from _cleanup_demo_hotel_ids);
-- request_types has no hotel_id of its own; it's scoped via category_id.
delete from request_types where category_id in (
  select id from request_categories where hotel_id in (select id from _cleanup_demo_hotel_ids)
);
delete from request_categories where hotel_id in (select id from _cleanup_demo_hotel_ids);
delete from guest_login_attempts where hotel_id in (select id from _cleanup_demo_hotel_ids);
delete from legacy_property_mapping where legacy_hotel_id in (select id from _cleanup_demo_hotel_ids);

-- staff_profiles: every row at the three demo hotels, plus the two
-- specific Palazzo Veneziano rows identified above.
-- push_subscriptions references staff_profiles with its own
-- ON DELETE CASCADE, so those clean up automatically.
delete from staff_profiles
  where hotel_id in (select id from _cleanup_demo_hotel_ids)
     or id in (select id from _cleanup_staff_profile_ids);

delete from hotels where id in (select id from _cleanup_demo_hotel_ids);

-- The Supabase Auth identities behind the demo fixtures and the one
-- genuinely orphaned duplicate (Farouk, Francesco Breda's old native
-- account). Ana Beatrice Simone's own account (016e00a4-...) and
-- Francesco Breda's real Hotsflow Team identity (e64a27f8-...) are
-- deliberately absent from this list.
delete from auth.users where id in (
  '888bbcde-99fe-45d2-86a4-cb21eb210c8e', -- Admin Demo 2
  'f75b34a2-e9aa-40a9-a10a-6fc446a64781', -- Admin Demo 3
  '3c939d79-5569-40ed-8dbe-06510c18c641', -- E2E Authz Temp
  '62cd04b7-20b1-4ca8-88f6-cdb1fc3b86f2', -- E2E Temp Staff 49600197
  '98284dd5-1b3a-4d88-9391-1fb9e867f4ea', -- E2E Temp Staff 73648576
  '04bec9ad-3342-4c60-8d5f-bc0d72acf796', -- Master Demo (E2E)
  '06960958-b665-49cc-978c-3e4212515d49', -- Operatore Demo (E2E)
  'c7a0fb2f-ae6d-4a13-8c0a-c18e03767af8', -- Staff Sospeso Demo (E2E)
  '311f7638-6f8c-4e43-b1f9-e270cd5599c3', -- Admin Hotel2 Demo (E2E)
  '2aeee55b-0ae1-48f5-ad84-abcf6da37ff2', -- E2E Authz Temp Org
  '5de93fca-d070-4a96-bda6-3b5fd3bba000', -- Admin B (E2E, Hotel Demo 3)
  '0bab404d-4cce-4fff-ae94-cc5fefece866', -- Farouk
  '6f3a511e-4735-461d-aa64-cb0b297af77a'  -- Francesco Breda, old native "fbreda"
);

-- Fail loudly instead of silently if the end state isn't exactly what
-- was intended.
do $$
declare
  bad_count int;
begin
  select count(*) into bad_count from staff_profiles
    where hotel_id in (select id from _cleanup_demo_hotel_ids);
  if bad_count <> 0 then
    raise exception 'cleanup incomplete: % staff_profiles rows still reference a demo hotel', bad_count;
  end if;

  select count(*) into bad_count from hotels
    where id in (select id from _cleanup_demo_hotel_ids);
  if bad_count <> 0 then
    raise exception 'cleanup incomplete: % demo hotel rows still exist', bad_count;
  end if;

  select count(*) into bad_count from staff_profiles
    where id in (select id from _cleanup_staff_profile_ids);
  if bad_count <> 0 then
    raise exception 'cleanup incomplete: % of the two doomed Palazzo Veneziano staff_profiles rows still exist', bad_count;
  end if;

  if not exists (select 1 from staff_profiles where id = 'ac68e209-859b-464d-a3a1-b1e50a9d16e9') then
    raise exception 'cleanup went too far: Ana Beatrice Simone''s staff_profiles row is gone';
  end if;
  if not exists (select 1 from auth.users where id = '016e00a4-d265-4dc3-925d-9232aa75026c') then
    raise exception 'cleanup went too far: Ana Beatrice Simone''s auth.users row is gone';
  end if;
  if not exists (select 1 from auth.users where id = 'e64a27f8-2488-4eef-82b4-fffd00030445') then
    raise exception 'cleanup went too far: Francesco Breda''s real Hotsflow Team auth.users row is gone';
  end if;
  if not exists (select 1 from staff_profiles where id = '32296ed1-ff68-4d91-9894-0133607e48ec') then
    raise exception 'cleanup went too far: Francesco Breda''s Team-bridged Housekeeping staff_profiles row is gone';
  end if;
end $$;

commit;
