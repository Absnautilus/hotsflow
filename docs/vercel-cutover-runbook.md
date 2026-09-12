# Vercel cutover runbook

Covers step 5 of `docs/architecture/monorepo.md`'s delivery sequence: point a
single Vercel project at `apps/web`, compare it against the existing
`hotsflow-app` production deployment on identical paths, and only then
propose a production cutover. This is preparation and comparison guidance —
it does not itself perform any Vercel configuration, deployment, or cutover.
Those steps require access to the Vercel dashboard/API that this repository
and its automation do not have, and, for the production cutover step
specifically, separate explicit authorization per the standing production-
safety constraints for this engagement.

## Prerequisite: repository-side fix already in place

`apps/web/vercel.json` now sets an explicit `buildCommand`:

```json
"buildCommand": "cd ../.. && npm run build"
```

Reason, verified locally by simulating Vercel's own Root-Directory-scoped
execution: `installCommand: npm ci` is safe as-is (npm's own install command
is workspace-root-aware regardless of the directory it's invoked from — it
walks up to find the workspace root and installs the whole tree), but
`npm run build` is **not** — run directly inside `apps/web` with no
override, it only executes `apps/web`'s own `build` script
(`tsc -b && vite build`) and fails with
`Cannot find module '@homisuite/housekeeping-module'`, because
`modules/housekeeping`'s own library build (`dist/`) never runs first. This
is the same class of bug fixed for GitHub Actions CI in Fase 6 (PR #29),
surfacing again here because Vercel's zero-config default for a Vite project
with Root Directory set is exactly the unqualified `npm run build`.

## Required Vercel dashboard configuration (manual — not performed by this repository)

Create a **new** Vercel project pointed at this repository (`hotsflow`), and
set:

- **Root Directory**: `apps/web`
- **Include files outside of the Root Directory in the Build Step**: **ON**
  — required for `buildCommand`'s `cd ../..` to reach the monorepo root
  (`modules/`, `packages/`, the root `package-lock.json`).
- **Framework Preset**: Vite (should auto-detect; `outputDirectory` stays the
  default `dist`, relative to Root Directory — verified locally that the
  build produces `apps/web/dist/index.html` and `apps/web/dist/assets/`).
- **Install Command** / **Build Command**: leave as the values already
  committed in `apps/web/vercel.json` (`npm ci` / `cd ../.. && npm run build`)
  — do not override in the dashboard, to avoid the config drifting from what
  is actually verified and version-controlled.

Environment variables (Preview and Production), per
`modules/housekeeping/src/lib/env.ts` and `apps/web/.env.example`:

| Variable | Required | Notes |
| --- | --- | --- |
| `VITE_SUPABASE_URL` | Yes | Same shared Homisuite Supabase project already used by `apps/web` and `Housekeeping`'s production data (per `fase2-guest-requests-migration.md`) — never a separate/legacy project. |
| `VITE_SUPABASE_ANON_KEY` | Yes | Same project as above. |
| `VITE_VAPID_PUBLIC_KEY` | No | Push notifications for the Housekeeping on-duty toggle; the toggle hides itself when unset. |
| `VITE_HOTEL_ID` | **No — do not set** | Only read by a standalone-guest-mode code path that was deliberately not transferred in Fase 5 (`docs/architecture/housekeeping-inventory.md`); verified unreferenced anywhere in `modules/housekeeping/src`'s reachable embedded code. Setting it would have no effect. |

The existing `hotsflow-app` Vercel project is **not** modified, paused, or
deleted at any point in this procedure — it keeps serving production traffic
throughout the comparison.

## Comparison checklist (preview vs. existing `hotsflow-app` production)

No automated Browser/E2E suite exists yet for `apps/web` (a separate, not yet
authorized body of work — see `docs/architecture/monorepo.md`'s Test
strategy section). Until it does, this comparison is manual, run on the new
project's **Preview** deployment against the current `hotsflow-app`
production URL, same paths on both:

- [ ] Login (staff auth) succeeds on both
- [ ] Shell loads: Home, Team, Settings navigation all reachable
- [ ] Housekeeping opens from the shell gate and loads stays
- [ ] Deep-link and page-refresh restoration works for at least one
      non-root route (Vercel's SPA rewrite in `vercel.json` is unchanged from
      Fase 7 — `/(.*) -> /index.html`)
- [ ] A non-destructive fixture edit inside Housekeeping round-trips
      correctly
- [ ] Triggering a known error state renders the expected error UI, not a
      blank screen or unhandled exception
- [ ] Responsive layout: desktop and mobile widths, no obviously broken
      layout
- [ ] No duplicated header/chrome between shell and embedded module
- [ ] Exactly one Supabase client/session active (browser devtools — no
      duplicate auth listeners or conflicting sessions)
- [ ] Browser console is clean (no errors/warnings introduced by this
      deployment)
- [ ] No unexpected network failures (browser devtools network tab)

## Production cutover

Only proposed after every item above passes on the Preview deployment, and
only performed with separate, explicit authorization for that specific
action — consistent with every other production-adjacent step in this
engagement. The old `hotsflow-app` Vercel project remains deployable and
unmodified as a rollback target until this migration's Definition of Done
(`docs/architecture/monorepo.md`'s "Criteria for archiving the legacy
repositories") is met.
