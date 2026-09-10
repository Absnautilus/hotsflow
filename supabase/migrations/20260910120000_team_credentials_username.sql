-- Adds a per-property login username to memberships, backing a
-- credentials-based (no email) alternative to the existing email-invite
-- flow: a synthetic, globally-unique auth.users email is derived from
-- username + property slug + organization slug at account-creation time
-- (see create-team-member-credentials Edge Function), while the admin and
-- the staff member only ever see the plain username.
--
-- Scoped to property (not organization), matching the org-wide membership
-- rows (property_id null) not having a single property to scope a username
-- to in the first place -- the credentials flow only ever targets a
-- single-property membership, same as the existing email-invite flow.
--
-- No grant changes needed: `insert` on memberships is already granted
-- without a column list (0007_rls_policies.sql), and username is only ever
-- set at insert time by the Edge Functions below, never updated afterwards
-- (0010_role_assignment.sql's `grant update (status)` already excludes it,
-- which is what we want -- renaming a username isn't a feature here).

alter table memberships add column username text;

alter table memberships add constraint memberships_username_format
  check (username is null or username ~ '^[a-z0-9][a-z0-9_-]{1,30}[a-z0-9]$');

create unique index memberships_property_username_unique
  on memberships (property_id, username)
  where property_id is not null and username is not null;
