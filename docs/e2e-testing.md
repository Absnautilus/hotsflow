# End-to-end (browser) tests for `apps/web`

First iteration, deliberately small: one smoke-test file
(`apps/web/e2e/smoke.spec.ts`), Playwright, **local only** — not wired into
CI yet. Covers two of the checks from `docs/architecture/monorepo.md`'s Test
strategy section (login, shell load); the rest of that checklist is future
work, added incrementally the same way.

## Test 1: login form renders (no backend needed)

Only needs the dev server up and *some* value for `VITE_SUPABASE_URL` /
`VITE_SUPABASE_ANON_KEY` in `apps/web/.env.local` — constructing the
Supabase client doesn't make a network call, so a placeholder is enough
(same assumption `packages/core-sdk/src/client.test.ts` already makes).

```bash
cd apps/web
npm run test:e2e -- -g "shows the login form"
```

## Test 2: real login reaches Home (needs a local Supabase stack)

1. `supabase start` (from the repository root)
2. Get the local service-role key: `supabase status` → copy the
   "service_role key" value
3. Provision the one fixed test user (idempotent, safe to re-run):
   ```bash
   SUPABASE_SERVICE_ROLE_KEY=<paste> node scripts/e2e/create-test-user.mjs
   ```
   Creates `e2e-smoke@example.test` / `e2e-smoke-test-password-only` with an
   org-wide admin membership on the seed data's "Organization A"
   (`supabase/seed.sql`) — enough to reach a working Home page after login.
4. Point `apps/web/.env.local` at the same local stack (`supabase status`
   again for the URL and anon key):
   ```
   VITE_SUPABASE_URL=http://127.0.0.1:54321
   VITE_SUPABASE_ANON_KEY=<paste>
   ```
5. Run it, with the test credentials as env vars (the test skips itself
   when these aren't set, rather than failing):
   ```bash
   cd apps/web
   E2E_TEST_EMAIL=e2e-smoke@example.test E2E_TEST_PASSWORD=e2e-smoke-test-password-only npm run test:e2e
   ```

## Known limitation

Test 2 has not been run end-to-end against a real local Supabase stack as
part of writing it — the sandbox this was developed in has the Docker
*client* but no running daemon, which `supabase start` requires. Test 1 was
verified to actually pass there. Please run Test 2 yourself (or from CI,
once that's wired up) before relying on it.
