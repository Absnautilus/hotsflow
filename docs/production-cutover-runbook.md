# Production Cutover Runbook

Status: **PREPARATION ONLY. NOT AUTHORIZED TO EXECUTE.** Nothing in this
document has been run. No data, Auth, environment variable, or Vercel
change has been made. Rehearsal (`docs/production-migration-rehearsal.md`)
is GO for *preparing* cutover, not for executing it — this document is
that preparation. Execution requires separate, explicit authorization.

---

## 1. Frozen validated artifact

As of this document, the following are **frozen** — no functional change
without first showing a diff here and stating whether it requires a new
rehearsal:

| Artifact | Identity |
|---|---|
| hotsflow-core commit (scripts, as exercised by the rehearsal) | `2347f68` |
| Migration script | `scripts/dry-run/10_migrate_hotel.sql` |
| Reconciliation script | `scripts/dry-run/20_reconciliation.sql` |
| Shared helpers | `scripts/dry-run/lib.sh` |
| Orchestration template | `scripts/dry-run/orchestrate_rehearsal.sh` (production run reuses this shape: seed → Auth phase → SQL migration → reconciliation → E2E, same order, same scripts) |
| Seed *methodology* (not committed data) | `docs/production-migration-rehearsal.md` §1–§10 |

Note: `docs/production-migration-rehearsal.md` itself gained a
documentation-only commit (`c6d6643`) after the rehearsal ran — this did
not touch any script and does not invalidate the rehearsal. The
*script-affecting* commit is `2347f68`.

Any change to `10_migrate_hotel.sql` or `20_reconciliation.sql` between
now and cutover — including one I propose — gets a diff shown here first,
with an explicit call on whether it requires re-running the rehearsal
before cutover proceeds.

---

## 2. Pre-cutover checklist

Marked **[AUTO]** (I can verify via query/API) or **[MANUAL]** (needs your
action or judgment). Run immediately before MAINTENANCE/FREEZE (step 4.2),
not days in advance — some of these are only meaningful minutes before
cutover.

| # | Item | Type | Current status (as of this document) |
|---|---|---|---|
| 1 | CI verde (hotsflow-core `main`) | AUTO | Verify at cutover time — was green as of `2347f68`/`c6d6643`. |
| 2 | Schema Hotsflow alla versione prevista | AUTO | `supabase migration list` against Hotsflow, compare to repo's migration files. |
| 3 | Migration history coerente | AUTO | Same command as #2. |
| 4 | Row count legacy aggiornati | MANUAL | Re-run §A's count query (production-data-migration-plan.md) — numbers may have moved since the rehearsal (2026-09-03). |
| 5 | Staff roster aggiornato | MANUAL | Re-check `staff_profiles` on legacy for the real hotel — same query as the rehearsal's export 2, read-only, no re-export needed unless roster changed. |
| 6 | Staff suspended/inactive re-verified | MANUAL | `select count(*) from staff_profiles where hotel_id = '25b00bec-...' and not active;` — was 0 at rehearsal time. |
| 7 | Nessuna anomalia introdotta dopo la rehearsal | MANUAL | Re-run the full §2 validation query set from `production-migration-rehearsal.md` on legacy. |
| 8 | Entitlement config (module exists) | AUTO | `select id from modules where slug = 'guest_requests';` on Hotsflow — already stable since Fase 2. |
| 9 | Edge Functions | AUTO+MANUAL | Deployed status checkable via API (AUTO); actual behavior needs one live call each (MANUAL) — already confirmed working in the 5-step gate, re-verify not assumed stale-safe. |
| 10 | Realtime | AUTO | Same publication query used in the earlier infra gate — was PASS (`public.guest_requests` only). Re-run, don't assume unchanged. |
| 11 | Database Webhook | MANUAL — **currently FAIL, real blocker** | Fix migration `20260827122700` is committed and CI-green but **not deployed to Hosted** (deliberately held per the earlier "NON toccare Vercel" instruction). Must deploy via `deploy-migrations.yml` before cutover, then re-verify with the placeholder-check query. |
| 12 | VAPID | MANUAL — **currently incomplete, real blocker** | New key pair generated (ROTATED), **not yet applied** to Supabase Edge Function secrets or Vercel. Must be set before or as part of cutover (see §9). |
| 13 | PMS configuration | AUTO | `pms_integrations` had 0 rows at rehearsal time — re-confirm still 0 (or handle if now configured). |
| 14 | Secrets | MANUAL | See §9 — at least one new GitHub secret needs creating before the real run. |
| 15 | Auth configuration (Site URL / Redirect URLs) | MANUAL — **currently PENDING, real blocker** | Production domain was never finalized in the earlier infra gate. Must be decided and configured before cutover, or guest/staff login will break post-cutover regardless of data migration success. |
| 16 | Vercel environment attuale | MANUAL | Record current `VITE_SUPABASE_URL`/`VITE_SUPABASE_ANON_KEY`/`VITE_HOTEL_ID`/`VITE_VAPID_PUBLIC_KEY` values before touching anything — this is the rollback baseline (§7.D). |
| 17 | Backup/snapshot available | MANUAL | Confirm a recent Supabase-managed backup exists for the Hotsflow project (Studio → Database → Backups), or take a manual `pg_dump` snapshot immediately before FINAL EXPORT. Legacy itself is never written to, so it needs no separate backup for this migration. |

**Honest summary: items 11, 12, and 15 are not yet resolved** — this
checklist surfaces them again deliberately, not to duplicate the earlier
report but because cutover cannot proceed with them open. They are
independent of the data-migration mechanism itself (already proven by the
rehearsal) and can be worked in parallel with the rest of this
preparation.

---

## 3. Freeze / maintenance strategy (proposed, not implemented)

Legacy has exactly one hotel (confirmed: `hotels` count = 1) — no other
tenant is affected by freezing it.

**Proposed mechanism — least invasive, no new code, no new distributed
system:**

```sql
-- FREEZE (run on legacy immediately before FINAL EXPORT):
revoke insert, update, delete on
  guest_requests, stays, staff_profiles, rooms, request_categories,
  request_types, pms_integrations
from authenticated, anon;

-- REOPEN (run after DECISION, whichever way it goes):
grant insert, update, delete on
  guest_requests, stays, staff_profiles, rooms, request_categories,
  request_types, pms_integrations
to authenticated, anon;  -- (or the narrower grants each table actually had — see note)
```

This makes every write attempt fail at the database level — instant,
symmetric, trivially reversible (a single matching GRANT), no application
code touched, no maintenance-mode banner to build. Reads keep working, so
guests/staff see a real (if temporarily static) app rather than a hard
error page.

**Caveat, stated plainly, not glossed over:** the exact REVOKE must
mirror each table's actual current grants (some are already
role-restricted, e.g. `pms_integrations` has no direct client grant at
all — see the main plan §A). The precise REOKE/GRANT pair needs to be
generated from each table's real `information_schema.role_table_grants`
immediately before use, not copy-pasted blind — this is a preparation
task for step 4, not something to write once now and trust unchanged.

**Not implemented yet, per instruction.** Recommended window: 15–20
minutes (see §11.7 for the breakdown) — generous relative to the
rehearsal's sub-3-second script execution, to cover real network latency,
manual verification reads, and the deliberate STOP checkpoint in §5.

---

## 4. Production cutover sequence

Each step: comando/azione — sistema — expected result — PASS — STOP — reversibilità.

### PRE-FLIGHT
1. **Run pre-cutover checklist (§2) in full.**
   System: legacy + Hotsflow + Vercel + GitHub.
   Expected: all 17 items confirmed, including the 3 currently-open ones (§2.11/12/15) resolved.
   PASS: 17/17 green. STOP: any item red → do not proceed, resolve first.
   Reversibility: N/A (no state changed yet).

### MAINTENANCE / FREEZE
2. **Apply the REVOKE freeze (§3) to legacy**, generated fresh from that moment's real grants.
   System: legacy.
   Expected: write attempts from the app now fail; reads still work.
   PASS: a test write (e.g. attempt to create a guest request) fails as expected.
   STOP: freeze doesn't take effect (still able to write) → do not proceed to export.
   Reversibility: fully reversible (GRANT back) — this is the ONE step safe to reverse without any further consequence, at any point before FINAL EXPORT starts.

### FINAL EXPORT
3. **Re-run the export queries** (`production-migration-rehearsal.md` §"Export N") against legacy, anonymized inline as before, for the real hotel.
   System: legacy (read-only).
   Expected: fresh CSV/result sets, matching current (frozen) state.
   PASS: row counts match what §2.4 just confirmed.
   STOP: counts don't match, or a query errors → REOPEN (step 2's GRANT) and investigate before retrying.
   Reversibility: fully reversible (read-only; freeze can still be lifted with no side effect).

### VALIDATION
4. **Re-run the §2 anomaly-validation query set** against this fresh export.
   System: legacy (read-only).
   Expected: same clean result as the rehearsal (0 anomalies).
   PASS: 0 anomalies.
   STOP: any anomaly found → REOPEN, do not proceed with a known-bad export; resolve the anomaly (per the main plan's "don't normalize silently" instruction) and restart from FINAL EXPORT.
   Reversibility: fully reversible (still read-only).

### AUTH MIGRATION
5. **Run the Auth-creation phase** (`orchestrate_rehearsal.sh`'s pattern, real hotel, real Hotsflow project) — remapping strategy, no explicit id.
   System: Hotsflow (auth.users — a write, but additive/isolated).
   Expected: 3 new Auth users created, `legacy_id → new_id` mapping recorded.
   PASS: 3/3 created successfully.
   STOP: any creation fails → run the mid-Auth-failure cleanup procedure (delete whatever was created this run — plan §B.1.5), REOPEN, investigate. Do not proceed to SQL migration with a partial mapping.
   Reversibility: reversible via `admin.deleteUser()` for exactly the ids created this run — cheap, already validated in the rehearsal (item 12).

### SQL MIGRATION
6. **Run `10_migrate_hotel.sql`** against Hotsflow, real hotel id/name/slug, the just-built `auth_remap` table.
   System: Hotsflow (hotels, organizations, properties, legacy_property_mapping, property_modules, profiles, memberships, staff_profiles, rooms, request_categories, request_types, stays, guest_requests).
   Expected: single transaction, commits or fully rolls back — no partial state possible.
   PASS: `COMMIT` returned.
   STOP: any error → transaction auto-rolls-back (Postgres guarantee, validated in rehearsal item 13); then also clean up the now-orphaned Auth users from step 5 (plan §I.3/§B.1.5), REOPEN, investigate.
   Reversibility: the SQL side is atomic (all-or-nothing); once committed, reversing means a manual down-script, not automatic — see §7.C.

### RECONCILIATION
7. **Run `20_reconciliation.sql`** against Hotsflow for the real hotel id.
   System: Hotsflow (read-only).
   Expected: matches the rehearsal's pattern — 0 PK dupes, 0 FK orphans, exactly 1 hotel→property mapping, all staff chain checks true, entitlement enabled=true, active/suspended counts equal, master→organization_admin membership present.
   PASS: every check matches expected (§10 acceptance criteria).
   STOP: **any** mismatch → do NOT proceed to Application Cutover. Legacy is still production (freeze still on, but Vercel still points at legacy) — see §5 checkpoint below. Decide fix-forward vs full rollback (§7.C) before continuing.
   Reversibility: read-only itself; the decision it gates is not.

**>>> CHECKPOINT — see §5. Vercel has not been touched yet. <<<**

### APPLICATION CUTOVER
8. **Change Vercel production env vars**: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` (or publishable key) → Hotsflow's values; `VITE_HOTEL_ID` → unchanged (same value, ID preservation confirmed by the rehearsal); `VITE_VAPID_PUBLIC_KEY` → the new rotated key if VAPID rollout is bundled into this cutover. Redeploy.
   System: Vercel (production).
   Expected: new deployment live, pointing at Hotsflow.
   PASS: deployment succeeds, app loads.
   STOP: deployment fails or app doesn't load at all → revert env vars to the recorded baseline (§2.16), redeploy — legacy is untouched, this is still case §7.D (no new writes exist on Hotsflow from real users yet).
   Reversibility: fully reversible up until real user writes land on Hotsflow post-cutover (§7.D vs §7.E boundary).

### SMOKE TEST
9. **Run the smoke test set (§6)** against production, for real.
   System: Hotsflow + Vercel production.
   Expected: all non-destructive checks pass; the few mutating ones (§6) create clearly-marked test data or are done last, deliberately.
   PASS: 100% of critical checks (§10).
   STOP: any critical check fails → this is now potentially case §7.D or §7.E depending on whether any real (non-test) user write has landed since step 8 — check timestamps before deciding which.
   Reversibility: depends on whether real writes exist yet (§7.D vs §7.E).

### GO / ROLLBACK DECISION
10. **Explicit decision**, made by you, informed by steps 7–9's results against §10's acceptance criteria.
    System: N/A (human decision point).
    Expected: GO (stay on Hotsflow) or ROLLBACK (per §7's matching case).
    PASS: decision made and recorded.
    STOP: N/A — this step doesn't fail, it resolves the prior STOPs.
    Reversibility: N/A.

### REOPEN
11. **Lift the freeze** (§3's GRANT) — on whichever system is now production (legacy if rolled back, Hotsflow's write paths were never frozen since they're new).
    System: legacy (and confirm Hotsflow's own RLS/grants are in their normal, non-frozen state — they were never touched by the freeze).
    Expected: normal write traffic resumes on the actual production system.
    PASS: a real write succeeds against the correct backend.
    STOP: N/A — this is the closing step.
    Reversibility: N/A (end state).

---

## 5. Data migration vs Application cutover — explicit checkpoint

Between step 7 (RECONCILIATION) and step 8 (APPLICATION CUTOVER): **if
reconciliation, Auth chain, or integrity checks are not 100% as expected,
STOP. Vercel continues pointing at legacy — no exception, no "close
enough."** Only a clean §10-acceptance-criteria PASS on steps 6–7
authorizes proceeding to step 8. This is the single most important gate
in this runbook, named explicitly because it's the one place a "probably
fine" judgment call is not acceptable.

---

## 6. Post-cutover smoke test set

**Non-destructive (read-only or idempotent):**
- login master
- login admin / property_admin equivalent (real roster: no `admin`-role
  account exists on this hotel — test against `master` and confirm the
  UI's admin-only screens are reachable via master's org-wide reach, since
  there is no dedicated admin account to test with)
- login operatore (both real accounts: reception, housekeeping)
- roster visible (master sees all 3 staff)
- open requests migrated and visible in the queue (expect exactly the 2
  migrated)
- department visibility (housekeeping operatore sees housekeeping-assigned
  requests — same positive-only coverage as the rehearsal; the negative
  case remains untestable with this hotel's real data)
- entitlement check (guest_requests module enabled for this property)
- PMS permission path (master has `guest_requests.pms.manage`)
- cross-property denial (master denied on any property outside its
  organization — reuse a fixture property for this, not real data)

**Mutating (creates or changes real data — run last, clearly marked):**
- create a new guest request (a real, visible row — plan to
  delete/archive it immediately after confirming success, or clearly
  label it as a test in its note field)
- change a request's status (accept/complete) — prefer doing this on the
  test request just created, not a real migrated one, to avoid disturbing
  actual guest data
- staff management (create-staff-account path) — create one disposable
  test account, then delete it immediately after confirming success
- notifications/push — requires a staff member to actually opt in
  ("on duty") and receive a real push after the VAPID rollout; this is
  the one check that can't be fully automated or scripted, needs a human
  with a real device

---

## 7. Rollback decision tree

| Case | Trigger | Action |
|---|---|---|
| **A. Failure before Auth migration** (pre-flight, freeze, export, validation) | Any STOP in sequence steps 1–4 | No impact. Nothing was written anywhere. REOPEN (lift freeze if applied), fix the cause, restart from PRE-FLIGHT or the failed step. |
| **B. Failure during Auth migration** (step 5) | Any staff Auth-creation fails | Delete every Auth user created in *this run* (tracked as it happens, per plan §B.1.5 — already validated in rehearsal item 12). REOPEN. No SQL migration was attempted. Investigate and restart from AUTH MIGRATION (or earlier, if the cause is upstream). |
| **C. Failure in SQL migration, before Vercel cutover** (step 6 or the §5 checkpoint) | Transaction aborts, or reconciliation (step 7) fails the §5 checkpoint | SQL side: transaction auto-rolled-back if it aborted (nothing to undo); if it *committed* but reconciliation still failed some check, a manual down-script removes exactly what this run inserted (all ids are known — recorded from the run's own output). Auth side: delete the users created in step 5 for this run. REOPEN. **Legacy remains production throughout — Vercel was never touched.** |
| **D. Failure immediately after Vercel cutover, before any new real write on Hotsflow** | Step 8 or 9 fails, and a timestamp check confirms no real (non-test) row was created on Hotsflow after the cutover moment | Yes — simply repoint Vercel's env vars back to the recorded legacy baseline (§2.16) and redeploy. Legacy's data is unchanged (frozen, then reopened once the revert is live). This is the one case where "just revert the env vars" is actually sufficient — confirmed exactly that, not assumed. |
| **E. Failure after Hotsflow has received real writes** | A real guest/staff action landed on Hotsflow before the problem was found | **Not simply revertible — see below.** |

**Case E, in full:**
- **Which data could only exist on the new system:** anything with
  `created_at`/`accepted_at`/etc. later than the recorded cutover
  timestamp, in `guest_requests`, `stays`, or `staff_profiles` — i.e., any
  row the migration script itself didn't create.
- **How to identify it:** `where hotel_id = '25b00bec-...' and created_at > '<cutover_timestamp>'` on each of those three tables — small and bounded, the same pattern as the main plan's §I.3.
- **Replay/back-migration possibility:** yes, for simple cases (a new guest request can be manually re-entered into legacy by staff) — but not guaranteed lossless for anything with side effects already triggered (a push notification sent, a PMS sync already attempted) or for edits to a *migrated* row (distinguishing "a migrated row that got updated after cutover" from "genuinely new" needs the same timestamp comparison, applied more carefully).
- **When rollback becomes riskier than forward-fix:** as soon as more than a handful of real rows exist, or any of them have been acted on by a second person (e.g., a request accepted by staff, not just created) — replaying loses the *sequence* of who-did-what, not just the data. Default posture (per the main plan §I.3, unchanged by this runbook): **forward-fix, not backward-revert**, once real writes exist — fix the problem on Hotsflow rather than manually reconstructing lost actions on legacy.
- **Who/what decides:** you, explicitly, in the moment — this is deliberately not automated or pre-scripted. The runbook's job is to hand you the exact delta query and the two options, not to pick for you.

---

## 8. Rollback window

Recommended: yes, a short **controlled observation period** — not
dual-write. Proposal: keep legacy frozen (read-only, per §3's REVOKE,
left in place rather than reopened) but otherwise completely untouched
for **24–48 hours** after a successful cutover, purely as a cold,
unmodified fallback reference — not an active system, not written to,
not read by the application. If nothing surfaces in that window, formally
declare Hotsflow the source of truth and decide legacy's decommission
timeline separately (main plan §J). No dual-write, no sync mechanism, no
new distributed system — deliberately, per instruction, since building
one just to make a few dozen rows' migration reversible would be a much
bigger, riskier system than the migration itself.

---

## 9. Credential handling

**Never**: in the repository, in a `workflow_dispatch` input, in a log,
pasted in this chat. The rehearsal's workflow-input channel was
acceptable *only* because that data was already anonymized (main
rehearsal doc §9/§10) — production credentials and real data do not get
that same treatment.

**What needs manual setup before the real run, and where:**

| Credential | Where it's used | Who configures it |
|---|---|---|
| Hotsflow project's `secret`/`service_role` API key | Auth-creation phase (GoTrue admin API) for the real migration | **New** — does not currently exist as a GitHub secret in this repo (confirmed: `deploy-migrations.yml` only uses the raw DB password for SQL-level access, never the API key). You add it directly as a repository secret in GitHub Settings, never through me. |
| Hotsflow DB connection (`SUPABASE_DB_HOST`/`_USER`/`_PASSWORD`) | SQL migration + reconciliation | Already exists (`deploy-migrations.yml` already uses these) — reuse, don't recreate. |
| New VAPID private key | Supabase Edge Function secret on Hotsflow | You run `supabase secrets set VAPID_PRIVATE_KEY=... VAPID_PUBLIC_KEY=... VAPID_SUBJECT=...` yourself, directly against Hotsflow, using the CLI or Studio — never pasted here. |
| New VAPID public key | Vercel `VITE_VAPID_PUBLIC_KEY` | You set this directly in Vercel — it's not secret (client-exposed by design) but still a manual, direct action. |
| Vercel's Hotsflow `VITE_SUPABASE_URL`/anon key | Application cutover (step 8) | You set these directly in Vercel. |

Given a new secret is required either way, the actual production
migration run should go through a **new, dedicated GitHub Actions
workflow** (not the rehearsal's `rehearsal-migration.yml`, and not a
workflow_dispatch text input) — a manual-trigger workflow using the
`confirm_project_ref` human-gate pattern already established for
`deploy-migrations.yml`/`deploy-functions.yml`, reading the new secret
directly via `${{ secrets.* }}` (GitHub's own masking applies
automatically), never displayed anywhere. This workflow does not exist
yet — building it is part of what "preparing the cutover" still requires,
separate from this document.

---

## 10. Cutover acceptance criteria (binary)

```
Migration:
  unexpected data loss             = 0
  orphan FK                        = 0
  PK duplicates                    = 0
  Auth mappings                    = 3/3 (or current real staff count)
  memberships                      = expected (property-scoped for
                                      admin/operatore-equivalent roles,
                                      organization-scoped for master)
  entitlement                      = enabled = true, exactly 1 row
  active/suspended consistency     = legacy_active == core_active

Application:
  critical smoke tests             = 100% PASS (§6 non-destructive set)
  wrong-tenant visibility          = 0 (cross-property denial confirmed)
  authorization failures           = 0 (every expected-ALLOW path allowed,
                                      every expected-DENY path denied)
  critical Edge Functions          = PASS (create-staff-account,
                                      sync-pms-stays, notify-new-request
                                      all respond correctly to a real call)
  Auth config                      = Site URL / Redirect URLs correct for
                                      the real production domain (§2.15
                                      resolved, not assumed)
  Webhook                          = no placeholder present (§2.11
                                      resolved, not assumed)
```

"Sembra funzionare" is not a criterion anywhere in this list — every line
is a query result, an HTTP status, or a count, checked against a specific
expected value.

---

## 11. Summary output

1. **Runbook**: §4 (this document).
2. **Pre-flight checklist**: §2 — 14 of 17 items resolved as of this
   document; 3 (webhook deploy, VAPID application, Auth domain
   configuration) explicitly still open.
3. **Freeze strategy**: §3 — proposed REVOKE/GRANT mechanism, not yet
   implemented.
4. **Rollback decision tree**: §7 — cases A–E, with E fully elaborated
   per instruction.
5. **Acceptance criteria**: §10.
6. **Secrets/config manuali necessari**: §9 — one new GitHub secret
   required (Hotsflow's API key), plus VAPID and Vercel env changes, all
   manual, none through this chat.
7. **Maintenance window estimate**: 15–20 minutes, broken down —
   freeze+export+validation (~5 min including manual review, script
   itself is sub-second at this volume), Auth+SQL migration+reconciliation
   (~5 min including manual review), the §5 checkpoint decision (unbounded
   — a human decision, not timed), application cutover + redeploy (~3–5
   min, Vercel deploy time), smoke test (~5 min). Generous relative to the
   rehearsal's raw 2.6s script time, because real network latency and
   human verification dominate at this data volume, not computation.
8. **Differenze rispetto alla rehearsal**: real network path to the real
   Hotsflow project (not localhost); a brand-new Auth-creation credential
   (not needed in the rehearsal's local-stack context); the freeze
   mechanism (§3) was never exercised by the rehearsal, since a synthetic
   dry-run has nothing to freeze; the Application Cutover and Smoke Test
   steps have no rehearsal equivalent at all (the rehearsal never touched
   Vercel).
9. **Rischi residui**:
   - **HIGH**: rollback after real writes land on Hotsflow (§7.E) is a
     manual judgment call by design — not automatable, not resolved by
     any amount of further preparation.
   - **HIGH**: the three open pre-cutover items (§2.11/12/15) are real
     blockers, not administrative formalities — login itself breaks
     without §2.15 resolved, regardless of how clean the data migration
     is.
   - **MEDIUM**: the freeze mechanism (§3) is proposed but unexercised —
     first real use will be during the actual cutover, not rehearsed.
   - **MEDIUM**: department-isolation's negative case remains untested
     (carried over from the rehearsal, unchanged by this document).
   - **LOW**: `pms_integrations` migration path remains logically sound
     but never exercised against a non-empty row.

## PRODUCTION CUTOVER: NO-GO (not yet — preparation only)

Not a judgment on the migration mechanism, which the rehearsal already
validated end-to-end. Blocked specifically on: §2 items 11/12/15 (webhook
deploy, VAPID application, Auth domain decision), the new GitHub secret
(§9) and its dedicated workflow (not yet built), and your explicit
authorization to execute any step of §4. Nothing further will run without
that authorization.
