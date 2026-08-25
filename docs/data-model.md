# Data model

Ten tables, `supabase/migrations/0001`-`0005`. Each migration file's own
header comments explain the *why* behind non-obvious choices in more depth
than this document repeats — treat this as the map, the migrations as the
territory.

## organizations

The hotel-side legal/commercial entity — a single hotel or a group. Not
generalized to cover taxi companies, agencies, or other B2B counterparts
(see `transfers` in the three-module audit): those stay internal to
whichever module needs them.

| column | type | notes |
|---|---|---|
| id | uuid pk | |
| name | text | |
| slug | text | unique |
| created_at / updated_at | timestamptz | |

## properties

The operative tenant — every module-owned row is scoped to a `property_id`,
never to an `organization_id` directly.

| column | type | notes |
|---|---|---|
| id | uuid pk | |
| organization_id | uuid fk -> organizations | on delete restrict |
| name, slug | text | unique together, not globally |
| timezone | text | default `Europe/Rome` |
| status | text | `active` \| `suspended` |
| settings | jsonb | free-form, low-churn config; promote a key to a real column only once it's actually queried on its own |
| created_at / updated_at | timestamptz | |

## modules / property_modules

`modules` is the registry of technical modules that exist at all;
`property_modules` is which of those a given property has switched on.
Answers *only* "is it available here?" — see `permissions.md` for why that's
kept separate from authorization.

`modules`: `id`, `slug` (unique — `shifts`, `transfers`, `guest_requests`),
`display_name`, `status` (`active` \| `beta` \| `deprecated`).

`property_modules`: `id`, `property_id` fk, `module_id` fk, `enabled`
(boolean), `plan` (reserved, unused in Phase 1), `settings` jsonb, unique
`(property_id, module_id)`.

## roles / permissions / role_permissions

Small, fixed, seeded — not runtime-configurable in Phase 1, no write RLS
policy exists for any of the three (see `rls.md`).

`roles`: `id`, `slug` (unique), `display_name`, `scope` (`organization` \|
`property`), `is_system` (always true today; reserved for a future
org-defined custom role).

`permissions`: `id`, `slug` (unique), `module_id` (nullable fk -> modules;
null = a core permission, e.g. `core.property.manage`).

`role_permissions`: `role_id`, `permission_id`, composite primary key — a
pure join table, no other columns.

## profiles

Staff identity only — 1:1 with `auth.users`, no role, no property, no
permission. That relationship lives entirely in `memberships`.

| column | type | notes |
|---|---|---|
| id | uuid pk | = auth.users.id, on delete cascade |
| full_name | text | |
| avatar_url | text | nullable |
| created_at / updated_at | timestamptz | |

## memberships

The table every access decision traces back to. A membership grants a role
either on **one property**, or **across an entire organization** — never
both, never neither:

```sql
constraint memberships_exactly_one_scope check (
  (property_id is not null and organization_id is null)
  or (property_id is null and organization_id is not null)
)
```

This is what lets an Organization Admin operate on every property under
their org without one membership row per property — a single extra
condition inside `has_property_access()` (see `rls.md`), not a hierarchy
walk.

| column | type | notes |
|---|---|---|
| id | uuid pk | |
| profile_id | uuid fk -> profiles | |
| property_id | uuid fk -> properties, nullable | exactly one of these two |
| organization_id | uuid fk -> organizations, nullable | |
| role_id | uuid fk -> roles | on delete restrict |
| status | text | `invited` \| `active` \| `suspended` |
| invited_by | uuid fk -> profiles, nullable | |
| created_at / updated_at | timestamptz | |

Unique partial indexes: one active-or-not membership per `(profile_id,
property_id)` and per `(profile_id, organization_id)` — partial because each
column is null on roughly half the rows by design. Plus plain indexes on
`property_id` and `organization_id` alone, for the reverse lookup ("who has
access to this property") that the partial-unique indexes (which lead with
`profile_id`) don't serve.

## guest_sessions

A temporary, revocable, property-scoped guest access — deliberately
agnostic to *how* the guest was verified. See `guest-access.md` for the
full design rationale; this is the column reference.

| column | type | notes |
|---|---|---|
| id | uuid pk | |
| property_id | uuid fk -> properties | |
| reservation_id, room_id, guest_id | text, nullable | opaque, not FKs — the core doesn't own a PMS/reservation model |
| verification_method | text | free text, not an enum — new methods don't need a core migration |
| verification_level | smallint | rank, not enum — see `guest-access.md` |
| token_hash | text | unique, not null — the only lookup mechanism Phase 1 needs |
| issued_by_module_id | uuid fk -> modules, nullable | which module created this session |
| expires_at | timestamptz | |
| revoked_at, last_seen_at | timestamptz, nullable | |
| metadata | jsonb | |
| created_at | timestamptz | |

`check (expires_at > created_at)` — a session can't be created already
expired; a test that needs an expired fixture backdates `created_at`
explicitly (see `supabase/tests/006_guest_session_expiry.test.sql`).

## Not built in Phase 1

**`property_settings`** — use `properties.settings jsonb`. A dedicated table
is only worth it once settings become genuinely relational and heavily
queried on their own.

**`invitations`, `audit_logs`** — both reasonable additions, neither needed
to satisfy Phase 1's own success criteria. Add when a real module migration
needs one, not before.
