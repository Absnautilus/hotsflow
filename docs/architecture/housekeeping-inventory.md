# Housekeeping inventory (Fase 3)

Status: read-only inventory. Produced entirely by reading
`Absnautilus/Housekeeping` (local read-only clone, commit `e0987e1` on
`claude/hotel-guest-requests-app-xrpgqm`, the repository's default branch).
**No file in that repository was created, modified, or deleted to produce
this document**, and nothing here is copied into this repository yet —
that is Fase 5. This table only decides what a future transfer PR should
and should not move, per `monorepo.md`'s workspace layout.

The classification follows the rule already stated in `monorepo.md`: a
file transfers only if `apps/web`'s shell-embedded `HousekeepingModule`
actually needs it. Nothing is copied "because it's there."

## What Housekeeping actually ships today

Two independent frontend surfaces share one Vite project
(`apps/web/src/App.tsx`, standalone-only):

- **Staff** (`/staff/*`, `StaffApp`) — the only surface the shell already
  embeds. `apps/web/src/module-entry.tsx` mounts exactly `StaffApp` behind
  `HousekeepingModule(props)`, built as a separate library bundle
  (`vite.module.config.ts` → `dist/housekeeping-module.{js,css}`) and
  published as `@hotsflow/housekeeping-module`, the exact `github:` pin
  this migration's Fase 6 removes.
- **Guest** (`/g/*`, `GuestApp`) — the guest-facing PWA (QR/pin
  verification, request submission, service worker for offline support).
  **Not part of the npm module boundary at all** — `module.d.ts` only
  declares `HousekeepingModule`, nothing guest-facing. It is a separate
  product surface with its own deployment question, out of scope for this
  transfer. Flagged below, not classified as transfer/no-transfer — that
  decision belongs to whoever scopes the guest-facing consolidation, not
  to the Housekeeping-staff-module transfer this document supports.

## Classification table

| Path | What it is | Classification | Target | Rationale |
|---|---|---|---|---|
| `apps/web/src/staff/**` | `StaffApp` and every staff screen (stays, requests, rooms/items, operators, PMS, archive, stats) | **Transfer** | `modules/housekeeping/src/features/*` (split by the existing sub-areas: stays, requests, rooms, settings) | This is the module — the entire reason for the transfer. |
| `apps/web/src/module-entry.tsx`, `module.d.ts` | The module's public API (`HousekeepingModule`, prop types) | **Transfer** | `modules/housekeeping/src/public/HousekeepingModule.tsx`, re-exported via `index.ts` | Already exactly the shape `monorepo.md` specifies — no redesign needed, just a move. |
| `apps/web/src/lib/staff-api.ts`, `admin-api.ts`, `stays-api.ts`, `opera-import.ts` (+ `.test.mjs`), `hotel-query-scope.ts` (+ `.test.mjs`) | Supabase queries and business logic the staff screens call | **Transfer** | `modules/housekeeping/src/data/` (queries/adapters) and `src/domain/` (pure logic — `opera-import.ts`'s parsing, `hotel-query-scope.ts`'s scoping helpers) | Real consumers: every staff screen. Split data vs. domain during the actual move per the "no file mixing query+transform+presentation" rule — these currently mix some of that and should not move as-is unexamined. |
| `apps/web/src/lib/supabase.ts` (`configureSupabaseClient`) | The compatibility seam that lets an embedding shell inject its own client | **Transfer, but re-examine** | Folded into the module's `index.ts`/public boundary | `monorepo.md` says the shell constructs the one client and injects it as a prop (already true here — `module-entry.tsx` calls `configureSupabaseClient(supabase)` from the injected prop, not a module-owned client) — this file's job shrinks to "accept the injected client," not construct one. |
| `apps/web/src/lib/errors.ts`, `format.ts`, `constants.ts`, `cn.ts`, `beep.ts`, `push.ts`, `types.ts`, `staff-types.ts` | Shared utilities/types used across staff screens | **Transfer** | `modules/housekeeping/src/domain/` or a small `lib/` under the module (not `packages/ui` — these are Housekeeping-specific, not generic) | Used throughout `src/staff/**`. |
| `apps/web/src/lib/i18n/**` | Housekeeping's own translation dictionaries/auto-translate | **Transfer** | `modules/housekeeping/src/i18n/` (module-owned, not `packages/ui`) | Module-specific copy, not shared with the shell or a future Turni module — no justification for `packages/ui` yet. |
| `apps/web/src/lib/guest-token.ts`, `guest-api.ts`, `operator-login.ts` | Guest-session/standalone-login logic | **Do not transfer with the staff module; re-evaluate with the guest surface** | — | `guest-token.ts`/`guest-api.ts` back the guest PWA, out of this transfer's scope per above. `operator-login.ts` backs standalone staff login — embedded mode receives an already-authenticated session from the shell and never shows this screen; confirm zero embedded-mode import before dropping it, don't carry it "just in case." |
| `apps/web/src/hooks/use-request-alerts.ts`, `use-toasts.ts` | Staff-side hooks (live request alerts, toast queue) | **Transfer** | `modules/housekeeping/src/features/requests/` or module-local `hooks/` | Real consumers in `src/staff/**`. |
| `apps/web/src/components/ui/**` (button, card, table, badge, switch, checkbox, field, icon-button, date-time-picker, file-input, action-icons) | Generic presentational primitives, currently Housekeeping-local | **Transfer as module-local first** | `modules/housekeeping/src/components/` | Per `monorepo.md`'s "no premature shared-component extraction": these move to `packages/ui` only the day a second module (Turni) actually needs the same primitive, not speculatively now. |
| `apps/web/src/components/avatar.tsx`, `logo.tsx`, `toast-stack.tsx`, `error-boundary.tsx`, `confirm-dialog.tsx`, `empty-state.tsx`, `category-icon.tsx` | Staff-used presentational components | **Transfer** | `modules/housekeeping/src/components/` | Confirmed staff-side consumers (dashboard, admin pages). |
| `apps/web/src/components/public-header.tsx`, `flag-icon.tsx`, `language-toggle.tsx`, `text-size-toggle.tsx`, `notification-settings-toggle.tsx`, `auto-text.tsx` | Shared between `GuestApp` and `StaffApp` | **Transfer only the staff-consumed subset** | `modules/housekeeping/src/components/` | Verify each one's actual embedded-mode usage individually at transfer time — some of these (`public-header.tsx` especially) read as guest-surface-shaped and may have no real consumer once only `StaffApp` moves. Do not copy the set wholesale. |
| `apps/web/src/embedded.css`, `housekeeping-theme.css` | Module-scoped styles | **Transfer** | `modules/housekeeping/src/styles/` | `module-entry.tsx` imports exactly `embedded.css`, not `index.css` — the "no global Preflight in embedded entry" rule this repository requires is already satisfied upstream; preserve that boundary on the move, don't accidentally pull in `index.css`'s Tailwind base/Preflight. |
| `apps/web/src/index.css`, standalone `main.tsx` | Standalone-app Tailwind entry (Preflight, global reset) | **Do not transfer** | — | Embedded mode deliberately never imports this today; carrying it over would silently reintroduce the exact global-Preflight problem `monorepo.md`'s Fase 5 section warns against. |
| `apps/web/src/guest/**`, `apps/web/public/sw.js`, `apps/web/src/lib/guest-token.ts`, `guest-api.ts` | Guest PWA (verification, request flow, offline service worker) | **Not classified — flagged for separate scoping** | — | Not part of today's npm module boundary; deciding its future home is a distinct question from this staff-module transfer, and forcing a transfer/no-transfer call here would be exactly the kind of unjustified scope creep this phase is meant to avoid. |
| `apps/web/e2e/*.mjs` | Playwright-style E2E scripts against the standalone Vite app (`admin-login`, `guest-flow`, `entitlement-and-pms`, `operator-and-master`, `staff-and-pms-authorization`, `staff-mgmt-and-boundaries`, `on-duty-and-suspended`) | **Recover selectively, do not transfer as-is** | Rewritten against `apps/web` (the shell) in Fase 8, guest-flow scripts excluded per the guest-surface note above | These test the standalone app's own routing/login, which won't exist once Housekeeping is shell-embedded — they're a reference for what scenarios to cover, not a file to move and expect to run. |
| `apps/web/src/lib/hotel-query-scope.test.mjs`, `opera-import.test.mjs` | Unit tests for the two lib files above | **Transfer with their source file** | Alongside their moved source under `modules/housekeeping/src/` | Follows the source file each one tests. |
| `supabase/functions/create-staff-account/`, `notify-new-request/`, `sync-pms-stays/` | Live Edge Function business logic | **Transfer candidates, not this phase** | `supabase/functions/` (already this repository's home for shared functions) | Unlike the migrations below, this is active business logic, not a superseded schema description — but every table/column reference must be re-verified against `hotsflow`'s actual current schema before porting, exactly the lesson from the Fase 1 stays-trigger fix (Housekeeping's own copy of this exact class of function was already found to reference a schema that no longer matches production). Treat each function as its own small, tested transfer PR, never a bulk copy. |
| `supabase/migrations/0001`–`0019` | Housekeeping's own standalone schema history | **Do not transfer** | — | Confirmed superseded: `hotsflow`'s own `20260827*` migrations already consolidated this schema under different, current names (`guest_requests_guest_sessions`, not `guest_sessions`); `0019` specifically is the ineffective fix the Fase 1 PR corrected for real. Per the standing constraint, none of this is copied or applied. |
| `supabase/seed.sql` | Housekeeping's dev/demo seed data | **Do not transfer as production seed**; isolate only what a specific test needs | `supabase/tests/` fixtures, case by case | Matches the standing "no demo data as fallback" rule — a concrete pgTAP or integration test can pull in a specific fixture row if and when it needs one, never the whole file. |
| `.github/workflows/ci.yml`, `e2e-smoke.yml`, `deploy-functions.yml` | Housekeeping's own CI/deploy pipeline | **Do not transfer** | — | Superseded by this repository's own consolidated CI (`monorepo.md`'s CI strategy); these pipelines reference the standalone app and legacy Supabase project. |
| `apps/web/vercel.json` | Housekeeping's own Vercel config | **Do not transfer** | — | Superseded by the Fase 10 single-Vercel-project plan. |
| `apps/web/public/favicon.svg`, `icons.svg` | Standalone app icons/sprite | **Do not transfer** (favicon); **re-evaluate** (icons.svg) | — | `favicon.svg` is the standalone app's own browser-tab icon, meaningless once embedded. `icons.svg` may be a sprite sheet consumed by staff screens — verify actual `<use>` references before dropping it. |
| `dist/`, `apps/web/dist/` | Build output | **Do not transfer** | — | Regenerated by the module's own build step; never a source artifact. |
| `README.md`, `apps/web/README.md` | Housekeeping's own repo docs | **Do not transfer** | — | Describe the standalone repo; superseded by this repository's own `docs/`. |

## What this inventory deliberately does not do

It does not move a single file, does not touch
`Absnautilus/Housekeeping` in any write sense, and does not resolve the
guest-surface question — that is a separate scoping decision, not an
oversight. The "Transfer" rows above are candidates for the Fase 5 pull
request, where each one still needs the per-file "does this have a real
consumer" check `monorepo.md` requires before it actually moves; this
table narrows that work, it does not replace it.
