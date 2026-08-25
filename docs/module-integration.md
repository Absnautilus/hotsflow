# How a module connects to the platform

The question this document exists to answer for whoever migrates the next
module. Nothing here is implemented in Phase 1 — this is the target shape,
based on what the three-module audit found already works
(`guest_requests`' `guest_sessions`/RLS pattern especially) and what the
Architecture Proposal decided.

## The one rule

```
MODULE -> CORE            (allowed)
MODULE A -> MODULE B      (never)
```

A module depends on this repo (its schema, its RLS helpers, its Core SDK).
It never imports another module's code, and it never queries another
module's tables directly. Future cross-module integration (e.g. `transfers`
notifying `guest_requests`) goes through an explicit contract — a shared
TypeScript interface, or a Postgres view/RPC built for that purpose — never
a module reaching into another module's internals. None of that exists yet;
it's explicitly Phase 5+.

## What a module owns vs. what the core owns

| | owns |
|---|---|
| **Core** (this repo) | identity, tenant, membership, roles/permissions, module entitlement, guest session validity |
| **Module** | its own tables, its own business logic, its own frontend — everything else |

Every module-owned table gets a `property_id not null references
properties(id)` — that's the entire tenant-scoping contract. There is no
core table a module writes its own business data into.

## Integrating an existing module (the real case for Phase 2-4)

1. **Add `property_id` where it's missing.** `guest_requests` and
   `transfers` already have an equivalent (`hotel_id`); `shifts` has none on
   any table and needs it added to all nine — see the three-module audit for
   exactly which module needs which.
2. **Map existing tenant rows to `organizations`/`properties`.** One
   existing "hotel" typically becomes one `properties` row (organization is
   new — none of the three modules have that concept today).
3. **Map existing users to `profiles`/`memberships`.** This is the most
   structurally invasive step for `guest_requests` and `transfers`, both of
   which currently fuse identity+membership+role into a single row with a
   unique constraint on the auth user — meaning a user belongs to exactly
   one tenant forever. Splitting that into `profiles` (identity) +
   `memberships` (one row per property or org) is what actually enables
   multi-property staff.
4. **Point the client at the shared Supabase project** — see `auth.md` for
   what that means concretely, including the `transfers`-specific path
   (NextAuth stays, only what `authorize()` checks against changes).
5. **Register the module**: a row in `modules` (once, ever) and a
   `property_modules` row per property that has it enabled.
6. **Replace local tenant/auth checks with the Core SDK.** The module's own
   RLS policies call `has_permission()`/`has_module()` directly (see
   `rls.md`'s worked example) instead of reimplementing the same logic.
7. **UI and business logic stay untouched.** Nothing about this changes what
   the module *does* — only how it answers "who is this, what property, can
   they do this."

## Using the Core SDK

```ts
import { createCoreClient } from '@hotsflow/core-sdk'

const core = createCoreClient(SUPABASE_URL, SUPABASE_ANON_KEY)

const profile = await core.getCurrentProfile()
const properties = await core.getAccessibleProperties()
const membership = await core.getMembership(propertyId)
const canManage = await core.hasPermission(propertyId, 'guest_requests.manage')
const enabledModules = await core.getEnabledModules(propertyId)
```

`core.raw` is the underlying `SupabaseClient` — the escape hatch for a
module's own queries against its own tables. The SDK never wraps or proxies
module data; it only answers identity/tenant/permission/entitlement
questions. See `src/index.ts` for the full exported surface, and
`src/types/domain.ts` for the shapes these calls return — never the raw
database row shapes from `src/types/database.ts`.

## Declaring a module

`ModuleDescriptor` (`src/moduleContract.ts`) is the shared *type* a module
uses to describe itself:

```ts
import type { ModuleDescriptor } from '@hotsflow/core-sdk'

const descriptor: ModuleDescriptor = {
  slug: 'guest_requests',
  displayName: 'Guest Requests',
  requiredPermissions: ['guest_requests.view', 'guest_requests.manage'],
}
```

This is a compile-time contract only — not a plugin registry, and it has no
runtime connection to the `modules` table. Actually making the module known
to the platform is a data change (`insert into modules ...`), not a code
change.

## Guest-facing modules

See `guest-access.md` for the full walkthrough — in short: a module builds
its *own* `SECURITY DEFINER` verification function that creates
`guest_sessions` rows, grants `execute` on that function (and only that
function) to `anon`, and checks `guest_session_is_valid()` before every
subsequent guest operation. The core never mediates the verification method
itself, only the resulting session's validity.
