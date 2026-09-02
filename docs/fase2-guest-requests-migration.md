# Fase 2 — `guest_requests` on the shared core

Status as of Step 9: **the shared backend is provisioned and E2E-validated.
Production has not been cut over.** See "Production status" below before
reading anything else in this file as a green light to touch Vercel env
vars — it isn't one.

This is the first of the three existing applications (`guest_requests`,
`shifts`, `transfers`) to migrate onto `hotsflow-core`. Nothing here
generalizes to the other two yet; where a decision was guest_requests-
specific, it's called out as such.

## hotsflow-core owns the shared migration history

As of Fase 2 Step 2, this repository's `supabase/migrations/` is the
**single authoritative migration history for the shared Supabase project** —
not just this repo's own schema. `guest_requests`' 18 original migrations
were copied here (renamed per the convention below) and now live
side-by-side with `0001`–`0014`, applied in one `supabase db reset` /
`supabase migration up` run against one Postgres database. The
`Housekeeping` repository's own `supabase/migrations/` directory is
frozen at the point of the copy — it is not applied to the shared project
and must not gain new migrations; any future guest_requests-side schema
change is a new migration in *this* repo.

Two real namespace collisions were resolved at copy time, both
documented in `20260827120000_guest_requests_init.sql`'s header:
- `set_updated_at()`: identical utility function defined independently by
  both repos — the relocated copy dropped its own duplicate; core's
  (`0001`) is canonical.
- `guest_sessions`: two semantically different tables shared this name
  (core's generic, unused platform primitive vs. guest_requests' own
  active table). The module's table was renamed to
  `guest_requests_guest_sessions` — a physical rename only, no behavior
  change.

## Migration naming convention

- Core's own migrations keep the pre-existing `NNNN_description.sql`
  numeric-prefix style (`0001`–`0014`).
- Every guest_requests-relocated or guest_requests-authored migration
  uses `YYYYMMDDHHMMSS_guest_requests_description.sql` — a real
  timestamp, always prefixed `guest_requests_`, so it's unambiguous at a
  glance which migrations belong to this module versus core, and they
  sort correctly after `0001`–`0014` regardless of how many core
  migrations are added later. A future module (`shifts`, `transfers`)
  migrating the same way should use its own slug prefix
  (`YYYYMMDDHHMMSS_shifts_description.sql`), not reuse `guest_requests_`.

## Organization/property model — the legacy adapter

`hotels.id` is referenced by too many guest_requests tables for a primary
key swap to be safe or worth it. Instead, `legacy_property_mapping`
(added in `20260827121800_guest_requests_tenant_adapter.sql`) is a strict
**1:1** adapter: every legacy `hotels` row gets exactly one new
`organizations` row and exactly one `properties` row under it, no
invented hierarchy (this was an explicit Step 3 decision — no grouping
multiple hotels under one organization, even where that might look
tempting later). `backfill_legacy_property_mapping()` is idempotent and
re-invokable, not a client RPC.

`legacy_hotel_slug()` derives the new organization/property slug from the
hotel's name (unaccent, lowercase, punctuation collapsed to hyphens), with
a short id-derived suffix appended only on an actual collision.
`hotels.active = false` maps to `properties.status = 'suspended'`
(currently inert — no core policy reads `properties.status` yet).

## Role / rank / permission model — the legacy role mapping

Core's four system roles (`0009_bootstrap_reference_data.sql`):
`receptionist` (rank 10, property-scoped), `manager` (rank 20, unused by
this mapping), `property_admin` (rank 30, property-scoped),
`organization_admin` (rank 40, organization-scoped). See
`../docs/permissions.md` for the full model — this section only covers
the legacy mapping specific to guest_requests.

`backfill_staff_identity()` (`20260827121900_guest_requests_staff_identity.sql`)
maps every `staff_profiles` row to a core `profiles` row (same id as
`auth_user_id`) plus a membership, per the approved mapping (decision D2):

| legacy `staff_profiles.role` | → core role | scope |
|---|---|---|
| `admin` | `property_admin` | property |
| `operatore` (any `department`) | `receptionist` | property |
| `master` | `organization_admin` | **one membership per existing organization**, created at the moment the backfill runs |

The `master` → `organization_admin` mapping is a known, approved,
non-reversible characteristic, not a bug: `organization_admin` is scoped
to one organization; legacy `master` saw every hotel. Reproducing that
requires one membership per organization that exists *when the backfill
runs* — a master account created (or a backfill re-run) after a new hotel
joins needs the backfill invoked again to pick up the new organization,
or that master won't see the new hotel's guest_requests data via the
6-table single-hotel path described below. This was flagged and approved
during Step 4/Step 9, not discovered as a defect.

`department` (`reception`/`housekeeping`/`maintenance`, nullable) stays a
guest_requests-local concept — it is never modeled in core; it only
filters the module's own staff-facing queue.

## `property_modules` as entitlement for guest_requests

`backfill_guest_requests_entitlement()`
(`20260827122000_guest_requests_entitlement.sql`) ensures a
`property_modules` row (`enabled = true`) for every mapped property. Not
a client RPC — service-role/migration only, same as `property_modules`
writes are everywhere else in core (see `../docs/permissions.md`).
A pre-existing `enabled = false` row is left alone and makes the backfill
raise rather than silently flip it — it could be a deliberate disable
decision, not "not yet bootstrapped".

**Known UI gap, not fixed as part of Fase 2 (see Backlog below):** when
`property_modules.enabled = false`, `current_staff_hotel()` resolves to
`NULL` for every caller at that property, which silently empties every
`guest_requests` query (0 rows, no error) rather than surfacing "this
module isn't enabled for your property" anywhere in the UI. Confirmed via
live E2E during Step 8, not a security issue (nothing leaks; the caller
simply sees nothing), purely a UX gap.

## `staff_profiles.role` is not authoritative

As of Step 6 (`20260827122100_guest_requests_authorization_wrapper.sql`),
no RLS policy and no authorization-checking function reads
`staff_profiles.role` to decide access. `current_staff_hotel()`,
`current_staff_role()`, and `current_staff_is_master()` were redefined
(`CREATE OR REPLACE`, same signatures) to derive from core
(`memberships`/`roles`/`role_permissions`) via `has_property_access()` /
`has_permission()`. `staff_profiles.role` remains in the table —
readable for compatibility/debug/UI display, and `authenticated` had its
INSERT/UPDATE grant on that one column revoked entirely
(`revoke insert, update on staff_profiles from authenticated;` then a
column-level re-grant on every other column) — a client can no longer
write it at all, but changing it (even by a superuser, in a test) has
**zero** effect on real authorization. Verified explicitly:
`021_guest_requests_authorization_wrapper.test.sql` mutates
`staff_profiles.role` toward `'master'` on a `receptionist` membership
and confirms nothing changes.

The one exception, and the one place this repository still writes
`staff_profiles.role`, is `backfill_staff_identity()` itself — a one-time,
service-role-only translation from legacy state into core memberships,
not a live authorization path.

**staff management and PMS are organization-wide for `organization_admin`,
unlike the 6 operational tables below** — deliberate, approved, capability
gates (`core.staff.manage`, `guest_requests.pms.manage`), not derived from
`current_staff_hotel()`'s single-hotel value.

### PMS: an intentional security deviation, not a preserved translation

`get_pms_integration_status()`/`save_pms_integration()` are the one place
in Step 6 that changed *behavior*, not just *source of truth* — recorded
as a durable, queryable fact via `COMMENT ON FUNCTION`
(`20260827122200_guest_requests_pms_fix_documentation.sql`), not only in
a commit message:

> The legacy `current_staff_role() not in ('admin','master') then raise`
> check silently no-opped for a NULL role (`NULL NOT IN (...)` is `NULL`,
> falsy in a PL/pgSQL `IF`) — combined with PUBLIC execute never having
> been revoked on either function, PMS status (the `has_credentials`
> boolean and sync metadata, not the stored OHIP secrets themselves) was
> structurally readable by `anon`. Rewritten to require
> `has_permission(property, 'guest_requests.pms.manage')`, which has no
> such NULL-bypass, and PUBLIC is now explicitly revoked.

Query it directly: `select obj_description('get_pms_integration_status(uuid)'::regprocedure);`

## The dual compatibility gate: `memberships.status` + `staff_profiles.active`

`current_staff_hotel()` requires **both** an active core membership
(`has_property_access()`, which itself requires
`memberships.status = 'active'`) **and** `staff_profiles.active = true` —
a deliberate, explicit Step 6 decision, not an oversight. Either one alone
is insufficient; both together are required to allow. Verified by all 4
combinations in `025_guest_requests_cross_tenant_compatibility_gate.test.sql`.
This is transitional: it exists so that flipping `staff_profiles.active`
(the legacy suspend mechanism, still used by whatever legacy tooling
reads/writes it) continues to actually suspend someone, without requiring
every legacy code path to learn about `memberships.status` on day one. A
future cleanup could collapse this to a single source of truth once
nothing outside this module still depends on `staff_profiles.active`
independently — not done now, no legacy consumer identified that would
allow it safely.

One real, confirmed UX side effect: `staff_profiles.active = false`
auto-derives to `memberships.status = 'suspended'`, which then also blocks
the person's own self-`SELECT` on their `staff_profiles` row (RLS's
`guest_requests_staff_roster_visible()` requires
`has_property_access()`/`has_organization_access()`, both membership-
gated). A suspended user's login therefore bounces back to the login
screen with **no explicit "account disabled" message** — the frontend's
`!profile.active` branch in `staff-app.tsx` is unreachable in this exact
scenario, since no profile row comes back at all. Confirmed via live E2E
in Step 8. Not fixed here — same category as the entitlement UI gap
above, both real but out of scope for Fase 2 (see Backlog).

## `staff_profiles.hotel_id` — compatibility operational context

`current_staff_hotel()` still derives its **value** from the caller's own
`staff_profiles.hotel_id` (module-local operational context), unchanged
by Step 6 — core is only consulted to decide *whether* to return it
(active membership + module entitlement), not to supply the value itself.
This reproduces the legacy single-hotel scoping exactly for the 6
operational tables (`guest_requests`, `rooms`, `stays`,
`request_categories`, `request_types`, `guest_login_attempts`) — including
for `master`/`organization_admin`, who despite holding an org-wide
membership still only ever sees **one** hotel's operational data through
this path (their own `staff_profiles.hotel_id`), confirmed via live E2E
(a master denied on a second hotel's `guest_requests` despite a formal
`organization_admin` membership there). Staff management and PMS are the
two deliberate exceptions (see above) — both go org-wide via
`has_permission()`'s own OR-branch, never through
`current_staff_hotel()`.

## `service_role` default privileges — exact scope, documented deliberately

Step 8's live E2E testing found `service_role` (the role every Edge
Function runs as) had **zero** SELECT/INSERT/UPDATE/DELETE on any of the
23 tables in the shared project's `public` schema — a one-time project
provisioning gap (verified: no migration in this history touches
`service_role` privileges at all), not caused by Fase 2. Fixed by
`20260827122400_service_role_default_privileges.sql`. Documented here
precisely, per an explicit request not to let this become a broad,
RLS-bypassing shortcut disguised as a grant fix:

- **What was granted, immediately, on every existing object**:
  `grant all privileges` (i.e. the full set: SELECT/INSERT/UPDATE/DELETE/
  TRUNCATE/REFERENCES/TRIGGER for tables, USAGE+SELECT+UPDATE for
  sequences, EXECUTE for functions) to `service_role`, scoped to
  `all tables/sequences/functions in schema public` — the `public` schema
  only, nowhere else (not `auth`, not `storage`, not `graphql`).
- **What was granted going forward**: three
  `alter default privileges in schema public grant all privileges on
  {tables|sequences|functions} to service_role` statements — meaning the
  grant applies to objects subsequently created **by whichever role runs
  the statement** (`postgres`, the role every migration in this history
  runs as) in schema `public`. Not `for role X` for any other role, not
  applied to any other schema.
- **What this does *not* do**: it does not touch RLS policies, does not
  grant anything to `anon`/`authenticated`, does not touch any other
  schema, and is entirely orthogonal to `service_role`'s pre-existing
  `BYPASSRLS` attribute (a separate Postgres mechanism — `BYPASSRLS` skips
  row-level *policies*; it has never substituted for, and does not
  interact with, the table-level GRANT privileges this migration
  restores). This is the standard Supabase baseline every normally
  provisioned project gets automatically at creation time — this
  migration restores that baseline, it does not widen it.
- **Queryable proof, not just narrative**: `029_step8_regression_pms_and_service_role.test.sql`
  asserts both the immediate grant (`has_table_privilege()` for all four
  privileges, on every real table) and the forward-looking default
  (creates a table *after* this migration inside the test transaction,
  confirms `service_role` has full access to it with no migration having
  granted it by hand), plus the exact `pg_default_acl.defaclobjtype` set
  this leaves behind (`r`/`S`/`f` — relations, sequences, functions —
  nothing broader, via `aclexplode()`).

## Configuration not yet infrastructure-as-code

Three pieces of live project configuration exist only as manual dashboard
state or environment variables, not as anything this repository's
migrations reproduce automatically on a fresh project:

- **Realtime**: enabled for the staff-facing read path (guest-facing
  status uses polling instead — the anon key has no direct table access,
  only RPC, and Realtime enforces the same RLS, so there's no clean way to
  push events to an anon client scoped to its own token without a real
  guest JWT). Enabling a table for `supabase_realtime` replication is a
  project-level toggle (Studio → Database → Replication, or
  `ALTER PUBLICATION supabase_realtime ADD TABLE ...` run by hand) — no
  migration in this history issues that statement.
- **Database Webhook** (`guest_requests` → `notify-new-request` Edge
  Function): the trigger mechanism itself *is* a migration
  (`20260827121300_guest_requests_guest_request_webhook.sql`, using
  `pg_net` directly rather than Studio's Webhooks UI, which this project
  doesn't expose), but the migration ships with literal placeholders
  (`YOUR_PROJECT_REF`, `YOUR_ANON_KEY`) that must be hand-edited to the
  live project's real values before/after the migration is applied — it
  is not a drop-in, environment-portable migration as written.
- **VAPID keys** (staff push notifications, `notify-new-request`): the
  public key is a `VITE_VAPID_PUBLIC_KEY` build-time env var on the
  frontend, the private key an Edge Function secret — both generated and
  set by hand per project, never versioned, never in a migration.

A fresh clone of the shared Supabase project (a DR restore, a new staging
environment) needs all three redone by hand; none is currently a blocking
gap (documented deliberately here so it doesn't get rediscovered as a
surprise), and none is in scope to fix as part of Fase 2 — see Backlog.

## E2E fixtures and test coverage available

Two independent layers of coverage exist for this migration, verified
separately, testing different things:

- **pgTAP** (`supabase/tests/018`–`029`, this repo): schema/RLS/grant-level
  correctness against a fresh, from-scratch database — the migration
  history applies cleanly, the mapping/backfill functions are idempotent
  and correct, and the full cross-tenant security matrix (tenant
  isolation, permission boundaries, module entitlement, the compatibility
  gate, department isolation, guest isolation, SECURITY DEFINER hygiene)
  holds. 185/185 assertions across 29 files, CI-green as of Step 9 (see
  below — this took real, non-trivial root-causing to get to).
- **Playwright E2E** (`Housekeeping/apps/web/e2e/*.mjs`, run via
  `.github/workflows/e2e-smoke.yml` in the `Housekeeping` repo): real
  browser/network tests against the **live, hosted** Supabase project —
  the only way to catch what pgTAP structurally cannot (a genuine runtime
  bug in a function body, a live project provisioning gap). This is how
  Step 8's two real regressions were found (see "Migrations added since
  Step 7" below); pgTAP's own coverage of those exact functions had never
  exercised their *allowed* paths, only denied ones.

Fixtures for both are demo/test-only, clearly namespaced
(`00000024-...`-style UUIDs per test file for pgTAP; env-var-driven
accounts — `E2E_OPERATOR_USERNAME`, `E2E_MASTER_EMAIL`,
`E2E_HOTEL2_ADMIN_EMAIL`, `E2E_SUSPENDED_USERNAME`, etc. — for the
Playwright suite), and repeatable: pgTAP fixtures live inside a
`begin ... rollback` per file (never persisted), Playwright fixtures are
pre-provisioned once via Studio and reused run to run.

## Procedure for adding a new migration

1. File name: `YYYYMMDDHHMMSS_guest_requests_description.sql` (real
   timestamp — `date -u +%Y%m%d%H%M%S` — not a made-up one, so ordering
   against concurrent work stays meaningful).
2. If the migration adds a `SECURITY DEFINER` function that should be
   reachable by `authenticated` and/or `anon`: explicitly
   `revoke all on function X from public;` **and also** `revoke ... from
   anon` / `from authenticated` for whichever of those two should NOT
   reach it, then `grant execute on function X to <role>` for whichever
   should. Revoking only from `public` is not sufficient locally — see
   "Why CI needed a local-only-divergence fix" below; every function
   migration in this history already follows the full by-name pattern,
   keep doing so for new ones.
3. Test it: add or extend a pgTAP file under `supabase/tests/`
   (`0NN_description.test.sql`, sequential numbering) covering the new
   behavior's allowed AND denied paths — Step 8's two live regressions
   both existed specifically because only the denied path had test
   coverage.
4. Run `supabase db reset && supabase test db` locally if Docker is
   available, or push to a branch and let `.github/workflows/ci.yml`'s
   `database` job do the same from a clean container — it now reliably
   reflects real pass/fail (see below), so a green run there is a real
   signal, not noise to ignore.
5. Deploy to the live project via the `deploy-migrations.yml`
   `workflow_dispatch` (mode `check` first, then `apply` with the project
   ref confirmation) — never applied automatically on push.

## Why CI needed a local-only-divergence fix (Step 9)

`.github/workflows/ci.yml`'s `database` job had failed on every run since
it was added, including commits whose messages claimed a full green suite
— those claims were verified by hand against a bare Postgres before
Docker was available in the environment developing this project, not by
this workflow. Root-caused in Step 9 via a temporary diagnostic step
reading `pg_default_acl` directly: the local Supabase CLI's Postgres
bootstrap installs two `ALTER DEFAULT PRIVILEGES` baselines on schema
`public` (`FOR ROLE supabase_admin` and `FOR ROLE postgres`) *before* any
migration in this history runs, each granting full privileges to
`postgres`/`anon`/`authenticated`/`service_role` on every object
subsequently created by that role. This project's own migrations run as
`postgres`, so every function they create is born with `anon`/
`authenticated` already holding an explicit grant — independent of, and
unaffected by, `revoke ... from public` (`PUBLIC` and a named role are
different grantees). Confirmed via direct queries against the live,
hosted project that this default does not exist there — a local-CLI-only
artifact, not a live security gap, and not caused by any migration in
this history.

Fixed by `20260827122500_explicit_anon_authenticated_revokes.sql`:
explicit `revoke ... from anon` (and `authenticated`/`public` where the
object should be fully unreachable) on exactly the objects this history
already documented as intentionally locked down, plus a forward-looking
`alter default privileges in schema public revoke execute on functions
from anon, authenticated` (functions only — this project's *tables*
intentionally rely on Supabase's standard broad grant + RLS as their
actual boundary, so the table/sequence default was deliberately left
alone). A guaranteed no-op on hosted (revoking a privilege never held is
a no-op, not an error), so local and hosted stay on the identical
migration history.

Two further failures, found while fixing the above, turned out to be
unrelated pre-existing test bugs, not the CLI divergence:
`024_guest_requests_cross_tenant_entitlement.test.sql` had an unscoped
`property_modules` count that ignored `seed.sql`'s own 3 demo rows; and
`029`'s own new regression test had an inverted boolean (`not exists`
where it should have read `exists`) that made it pass only if
`service_role` had access to *nothing*. Both fixed; see the two commits
for the full root-cause writeups.

## Residual technical debt

- **`create-staff-account` and `sync-pms-stays` Edge Functions
  (`Housekeeping` repo) still use `staff_profiles.role`/`.active` as
  their authorization source**, not core's `has_permission()`/
  `current_staff_role()`:
  ```ts
  const { data: caller } = await callerClient.from('staff_profiles')
    .select('id, hotel_id, role, active').eq('auth_user_id', user.id).maybeSingle()
  if (!caller || !caller.active || !['admin', 'master'].includes(caller.role)) {
    return json({ error: 'forbidden' }, 403)
  }
  ```
  Confirmed by direct source read, not assumed. This means the
  authorization migration is **not fully complete** — these two functions
  are transitional compatibility debt with no remediation yet scheduled.
  Since `staff_profiles.role` is no longer client-writable (see above)
  and these functions run under the service-role key regardless of RLS,
  this is not currently exploitable from a client, but it does mean a
  future role-model change (a new role, a rank adjustment) would need to
  be applied in two places — core's `role_permissions` and these two
  functions' hardcoded `['admin','master']` checks — and would silently
  drift if only one is updated. Remediation: rewrite both to call
  `has_permission()`/`has_organization_permission()` against
  `core.staff.manage`, same as every RLS policy already does.
- **The compatibility gate** (`memberships.status` + `staff_profiles.active`)
  and **`staff_profiles.hotel_id`** as the operational-context source are
  both explicitly transitional — see their own sections above.
- **`master` → `organization_admin`'s per-organization-at-backfill-time
  membership** — see the role mapping section above.

## Backlog (not fixed as part of Fase 2 — future App Shell / module
## lifecycle work)

- **`property_modules.enabled = false` gives no explicit UI signal.**
  The UI must eventually distinguish "this module isn't available for
  your property" from "there's just no data yet" — currently both render
  as an empty list. Deferred deliberately to the upcoming App Shell /
  module lifecycle redesign, not fixed as a one-off patch here.
- **A suspended staff member's login gives no explicit "account
  disabled" message** — same root cause and same deferral as above (see
  "The dual compatibility gate").

## Production status

**Do not read anything in this file as authorization to change Vercel
production environment variables.** As of Step 9:

- The shared backend (`hotsflow-core` + `guest_requests`' relocated
  migrations, applied to one Supabase project) is **provisioned and
  E2E-validated** — live-verified via real browser/network Playwright
  runs covering admin login, guest flow, operator/master roles, staff
  management, cross-property denial, on-duty toggling, suspended staff,
  disabled entitlement, and PMS status/save (Step 8's full checklist).
- Vercel production for `guest_requests` **still points at the old,
  separate Supabase project.** No cutover has happened. `guest_requests`
  had no real production data at the start of Fase 2 (confirmed by the
  project owner) — the eventual cutover is low-risk for that reason, but
  it is a separate, distinct action from anything documented in this
  file, requiring its own explicit go-ahead and an explicit review of
  exactly which env vars change, before any of them are touched.
