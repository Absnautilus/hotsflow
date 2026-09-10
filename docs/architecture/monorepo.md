# Monorepo consolidation

Status: target architecture, approved for incremental execution. This
document describes where the platform is going; it does not itself move any
code. Each step below happens as its own small, reversible, CI-green pull
request, gated on explicit authorization before merge and again before any
production/deploy action — see "Delivery sequence and rollback" below.

## Why this supersedes the previous direction

`current-state.md` previously recorded: *"The current preferred topology is
a separate shell frontend rather than turning the Core SDK/database
repository into a large monorepo."* That was the right call at the time —
Housekeeping's frontend was still mid-migration and a shell didn't exist
yet. It is now explicitly superseded: `hotsflow` (this repository) becomes
the single canonical repository for the platform's schema, shared backend,
shell frontend, and first embedded module, absorbing `hotsflow-app` (the
shell) and `Housekeeping` (the embedded module) one small PR at a time.
`Absnautilus/Housekeeping` is legacy and frozen for the duration of this
migration: read-only inventory only, no writes of any kind, until transfer,
green CI, verified preview, verified production, and explicit authorization
to archive it.

The reason for the reversal: with Housekeeping now the first shell-embedded
module and Turni next in line (`turni-integration-plan.md`), three
repositories with independent CI, dependency graphs, and deploy pipelines
cost more in cross-repo coordination (the exact `github:` SHA-pinning this
migration removes) than a single repository with clearly enforced internal
boundaries costs in size. The boundary that mattered — module code must
never reach into another module's internals — is preserved; what changes is
that the boundary is now an npm workspace boundary inside one repository
instead of a repository boundary between three.

## Workspace layout and responsibilities

```
hotsflow/
  apps/
    web/                    the shell: routing, auth session, property
                             switcher, Home/Team/Settings, module mounting
  modules/
    housekeeping/
      src/
        public/             the module's public surface (see below)
        features/
          stays/
          requests/
          rooms/
          settings/
        data/                Supabase queries — adapters/repositories only
        domain/              pure validation, mapping, payload construction
        components/          presentation, no data fetching
        styles/              CSS, scoped, no global Preflight in embedded mode
        index.ts             the ONLY import path other workspaces may use
  packages/
    core-sdk/                identity/tenant/permission/entitlement client
                             (already this repository's src/, moved as-is)
    ui/                      truly-shared presentational primitives only —
                             populated the first time two workspaces need
                             the same component, not before
    config/                  shared tsconfig/eslint base configs
  supabase/
    migrations/               single shared migration history (unchanged
                               location — this repository already owns it)
    functions/                shared Edge Functions
    tests/                    pgTAP
    config.toml
  docs/
    architecture/
      monorepo.md             this file
```

`packages/ui` starts empty. It is not pre-populated in anticipation of
Turni — a component moves there only when a second module actually needs
it, per the standing "no premature shared-component extraction" rule.

## Dependency direction (enforced, not just documented)

```
apps/web  ---->  modules/*  ---->  packages/core-sdk
   |                 |                    ^
   |                 +------> packages/ui-+
   +----------------------------------------------> packages/ui
```

Rules, all enforced by a CI check (see "CI strategy"), not left to review
discipline alone:

- `apps/web` may depend on any `modules/*` and on `packages/core-sdk` /
  `packages/ui`.
- A module (`modules/*`) may depend only on `packages/core-sdk` and
  `packages/ui`. Never on `apps/web`, never on another module.
- `packages/core-sdk` depends on nothing in this repository except its own
  generated Supabase types. It never imports the shell, `packages/ui`, or
  any module.
- `packages/ui` contains no domain logic and no Supabase client usage — pure
  presentation, generic enough that both the shell and any module can use
  it unmodified.
- Every workspace's public surface is its `index.ts` (or `src/public/` for
  Housekeeping specifically, re-exported through `index.ts`). No workspace
  imports another workspace's internal path — no `modules/housekeeping/src/
  data/...` from outside the module, no `packages/core-sdk/src/client` — the
  import is always the package name.
- No relative import (`../../`) ever crosses a workspace boundary. If it
  would have to, the thing being reached belongs in that workspace's public
  API instead.

## Module public API: Housekeeping

The shell must be able to mount Housekeeping, and nothing more. The
intended shape:

```ts
// modules/housekeeping/src/index.ts
export { HousekeepingModule } from './public/HousekeepingModule'
export type { HousekeepingModuleProps } from './public/HousekeepingModule'
```

`HousekeepingModuleProps` is the entire contract between shell and module:
the already-authenticated Supabase client, the active property/hotel
context, the caller's resolved capabilities, whatever session info the
module needs, hotel settings, and navigation callbacks — never raw shell
internals, never a second Supabase client, never a rebuilt session. This
mirrors the module-integration contract already documented in
`module-integration.md` and the guest-facing pattern in `guest-access.md`;
this document does not restate those, it places them inside workspace
boundaries.

## Database and Edge Function ownership

Unchanged by this migration and stated here only to remove any ambiguity
once three repositories become one: `hotsflow`'s `supabase/` directory is
the single source of truth for the shared Supabase project — schema,
migrations, RLS, triggers, SQL functions, and Edge Functions. Housekeeping's
own frozen `supabase/migrations/` in the legacy repository describes a
schema that is no longer authoritative (see the Fase 1 stays-trigger fix for
a concrete instance of this drift) and is never a valid migration source
going forward.

## Supabase client lifecycle and auth

`apps/web` constructs the single Supabase client for the session and is the
only workspace that ever calls `createClient()`. It is injected into
`packages/core-sdk`'s client wrapper and passed down into every module as a
prop. A module never constructs its own client, never reads
`VITE_SUPABASE_*` env vars directly, and never manages its own auth session
— doing so would mean two Supabase client instances (and, in the browser
bundle-duplication sense, this migration explicitly checks for that; see
below). Auth state, the active property, and capability resolution live in
`apps/web` and `packages/core-sdk`; modules consume, never own, that state.

## Test strategy

- **Unit** (`packages/core-sdk`, `modules/*/src/domain`): pure functions —
  validation, mapping, payload construction, error classification. No
  network, no DOM.
- **Integration** (`modules/*/src/data`, against a local/preview Supabase
  instance, never production): the adapter/repository layer — stays
  load/edit/extend/anticipate/close, guest sessions, requests, property
  scoping, zero-rows-affected treated as an explicit error, not a silent
  success.
- **pgTAP** (`supabase/tests/`): unchanged in kind from what this repository
  already does extensively — RLS, tenant isolation, triggers, grants,
  `SECURITY DEFINER` functions, cross-property rejection, capability checks,
  stay/session lifecycle. Every mutation assertion is followed by a re-SELECT
  with the appropriate role proving the persisted value, never `lives_ok`/
  `throws_ok` alone — the house style already in place and reinforced by the
  Fase 1 stays-trigger test.
- **Browser/E2E** (`apps/web`, against preview or a disposable fixture
  project, never production data): login, shell load, navigation to
  Home/Team/Settings/Housekeeping, deep-link/refresh restoration, opening
  Housekeeping and loading stays, a non-destructive fixture edit, an error
  state, responsive desktop/mobile layouts, no duplicated header/chrome, no
  second Supabase client/session, a clean console, no unexpected network
  failures.

## CI strategy

One workflow, separate jobs so a failure is immediately attributable:

```
install  ->  lint  ->  typecheck
                          |
        +-----------------+------------------+
        |                 |                  |
  core-sdk tests   housekeeping tests    web tests
        |                 |                  |
        +--------+--------+---------+--------+
                 |                  |
              build            pgTAP (supabase/tests)
                 |
   dependency-boundary check
   circular-dependency check
   bundle-duplication check (single React/ReactDOM/@supabase/supabase-js)
```

Every job runs the repo's real command (no job is allowed to report success
without actually invoking lint/typecheck/test/build) and shares an npm
install cache without depending on another job's non-deterministic build
artifacts. `deploy-migrations.yml` stays a separate, manual-only,
gated workflow — unchanged by this document.

## Vercel strategy

One Vercel project for `hotsflow`, Root Directory `apps/web`, monorepo-aware
build (workspace-aware install, build only `apps/web` and its workspace
dependencies). The existing `hotsflow-app` Vercel project is not deleted
during migration — both are compared on identical paths (preview vs. old
production) before any cutover, and production cutover on the new project
happens only after that comparison and explicit authorization, per the
existing `production-cutover-runbook.md` pattern already used for the
Fase 2 backend cutover.

## Criteria for adding a new module

A workspace under `modules/` is justified once a module is actually being
migrated into this repository (Housekeeping now, Turni next per
`turni-integration-plan.md`) — never speculatively. Before creating one:

1. The module's own tenant/property scoping is already in place (Turni's
   own plan already covers this as a schema-transition prerequisite).
2. The module's public API surface has been drafted (mirroring
   Housekeeping's `index.ts` shape above) before the bulk of its code moves.
3. No module-to-module dependency is introduced — if two modules need to
   coordinate, the mechanism is a shared contract in `packages/core-sdk` or
   an explicit interface, per `module-integration.md`'s existing rule, never
   a direct import.
4. The transfer PR moves code and, where strictly necessary, fixes
   proven-by-test bugs — it never bundles an unrelated redesign.

## Criteria for future Turni transfer

`turni-integration-plan.md` already defines the data migration, identity
remapping, and authorization targets for Turni independent of this
document. Once that plan reaches its T4 (shell mount) step, Turni becomes
`modules/shift-planner` (naming to be finalized against the plan's own
table prefixes) under exactly the same workspace rules as Housekeeping
above: its own `index.ts`, no reach into Housekeeping or the shell's
internals, `property_id`-scoped tables owned in `supabase/migrations/`
here, not in a separate repository.

## Delivery sequence and rollback

Each numbered step is its own PR, CI-green, reviewed, and merged only on
explicit authorization — consistent with how the Fase 1 stays-trigger fix
was delivered:

1. Introduce npm workspaces in this repository: root `package-lock.json`,
   root scripts (`lint`/`typecheck`/`test`/`build`/`test:db`), shared
   TS/ESLint base config, the three CI checks above. No behavior change —
   existing `src/` becomes `packages/core-sdk/src/` with no logic edits.
2. Transfer only the Housekeeping code that the shell actually needs into
   `modules/housekeeping`, behind the public API above. Housekeeping's
   frozen repository is read from for inventory only, never written to.
3. Replace `hotsflow-app`'s `github:Absnautilus/Housekeeping#<sha>`
   dependency with `workspace:*`, and delete the pin — verified by
   confirming the old repository no longer appears anywhere in the
   lockfile and no GitHub fetch happens during install/build.
4. Transfer `hotsflow-app` itself into `apps/web`, preserving routing,
   auth, and every existing shell behavior; any fix proven necessary by a
   test travels with its own explicit note, never silently bundled.
5. Point the single Vercel project at `apps/web`; compare preview against
   the existing `hotsflow-app` deployment on identical paths before
   proposing production cutover.

Rollback at any step: because each step is its own PR against `main`, and
`hotsflow-app`/`Housekeeping` are never deleted or archived mid-migration,
reverting the merge commit for a given step restores the previous working
state without touching the other two repositories, which remain deployable
until this migration's Definition of Done is met.

## Criteria for archiving the legacy repositories

`hotsflow-app` and `Absnautilus/Housekeeping` may be proposed for archival
only once all of the following hold simultaneously: their code is fully
transferred into this repository; `apps/web` no longer references either
repository anywhere (dependency, CI, deploy config); install/lint/typecheck/
test/build all run from this repository's root; CI (including pgTAP and the
boundary/circular/bundle-duplication checks) is green; the new Vercel
project's preview and production deployments are verified against the old
ones; and explicit authorization to archive has been given separately from
authorization to merge the transfer PRs. Archiving is never implied by a
merge — it is its own explicit, separate decision.
