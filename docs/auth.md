# Staff authentication

## The flow

```
Supabase Auth (auth.users)
      |
   profiles          -- identity only: full_name, avatar_url
      |
  memberships         -- property or organization, role
      |
role_permissions      -- what the role can do
      |
property_modules      -- whether the property even has that module
```

`auth.users` is the only source of truth for "who authenticated." Nothing
else — property, role, permissions, visible modules — is ever embedded in
the JWT or cached alongside the session; it's resolved by querying
`memberships` (through the RLS helpers, or through the Core SDK, which calls
the same functions) on every request. That's a deliberate tradeoff: a role
change or a membership revocation takes effect immediately, without forcing
a new login, at the cost of one more join per request — a join that's
already index-backed (see `memberships`' indexes in `data-model.md`).

## Creating a profile

There is no self-service signup in Phase 1. A `profiles` row is created by
whoever already has `core.staff.manage` on the target property/organization
— matching `guest_requests`' own proven convention (its README: "crea il
primo account admin a mano... non c'e un flusso self-service, di
proposito"). RLS has no `INSERT` policy for `authenticated` on `profiles`;
the first profile on a fresh project is necessarily created by a service-role
script or through Studio.

## What "one login for hotel staff" actually means

Two of the three existing modules already run on Supabase Auth
(`guest_requests`, `shifts`), each against its *own* Supabase project. A
staff member who works across modules today has as many separate accounts
as modules they use. Unifying that doesn't require touching what Supabase
Auth *is* — it requires every module's client to point at the **same**
Supabase project (this one, or whichever project ends up hosting
`organizations`/`properties`/`profiles`/`memberships`) instead of its own.
Concretely, per module, migration means:

1. Point the module's Supabase client env vars at the shared project.
2. Existing local accounts get re-created against the shared project (once,
   during that module's own migration — see the Architecture Proposal's
   Phase 2-4 sequencing). There's no automatic way to merge two separate
   `auth.users` tables; a staff member logs in once against the shared
   project to get a fresh account there.
3. The module reads role/property/permissions from `memberships` (via the
   Core SDK) instead of its own local table.

## `transfers` is the one exception

`transfers` doesn't use Supabase Auth at all today — it's Auth.js/NextAuth
with its own `bcrypt`-hashed `User.passwordHash` table (see the
three-module audit). Bringing it onto shared staff identity doesn't mean
replacing NextAuth or rewriting its session handling:

- Only the **hotel-side** roles (`HOTEL_STAFF`, `ADMIN`) need to move.
  `TaxiCompany`/`Driver` logins stay exactly as they are — per the
  Architecture Proposal's decision M4, they're not part of this core at all.
- NextAuth's `Credentials` provider changes what it checks *inside*
  `authorize()`: instead of comparing against the local `passwordHash`
  column, it verifies against Supabase Auth (or validates a Supabase-issued
  JWT). The login screen, the session cookie, the middleware in
  `src/proxy.ts` — none of that has to change.
- `Hotel.id` stays `transfers`' own primary key internally; a
  `legacy_property_mapping` (`Hotel.id` <-> this core's `properties.id`) is
  the adapter, introduced only when `transfers`' own migration actually
  starts (see the Architecture Proposal, section K, on when a mapping table
  is and isn't worth it).

This is explicitly Phase 4 work (the audit put `transfers` last precisely
because of this gap) — nothing here is implemented yet.

## Future methods

Magic link and SSO (Google/Microsoft) plug in downstream of `auth.users`
without touching `profiles` or `memberships` at all — they're just
different ways of populating the same `auth.users` row. Neither is
implemented in Phase 1, and neither requires a schema change when it is.
