# hotsflow-core

Platform core condiviso per la suite hotel: identità staff, organizations/properties,
membership, ruoli/permessi, entitlement dei moduli e sessioni guest. Nessuna business
logic dei moduli vive qui — `shifts`, `transfers` e `guest_requests` restano
applicazioni separate che si agganciano progressivamente a questo core.

Vedi l'Architecture Proposal approvata per il contesto completo (diagrammi, audit dei
tre moduli esistenti, decisioni architetturali).

## Stato — Fase 2 (`guest_requests`) in produzione

Il backend condiviso è **provisionato, validato end-to-end e in uso in produzione**
per Housekeeping / `guest_requests` di Palazzo Veneziano. Il cutover dal progetto
Supabase legacy al progetto Hotsflow condiviso è stato completato e validato; il
backend legacy resta congelato come safety net e non è più il backend operativo.

La migrazione ha portato nel Core condiviso identità Auth, profili, membership,
property mapping, entitlement e dati operativi migrati. L'autorizzazione database
di `guest_requests` passa già attraverso il Core tramite il compatibility wrapper
della Fase 2; il frontend conserva ancora alcuni concetti legacy che saranno
progressivamente sostituiti da runtime property context e capability Core.

La correzione PR0 post-cutover restringe inoltre la policy legacy di visibilità
`hotels` all'organizzazione effettivamente amministrata, eliminando il bypass
cross-organization ereditato dalla semantica legacy di `master`.

Vedi `docs/fase2-guest-requests-migration.md` per modello tenant/ruoli,
decisioni di compatibilità, debito tecnico residuo, configurazioni non ancora
infrastructure-as-code e stato post-cutover.

Questo repository possiede **l'intera migration history condivisa** del progetto
Supabase: `supabase/migrations/` include sia il Core sia le migration
`guest_requests` rilocate e successive. Le nuove migration di Housekeeping devono
quindi essere aggiunte qui, non nel repository Housekeeping.

## Stato — Fase 1.1 (Security Hardening) completata

Fase 1:

- [x] schema, constraint e indici Core
- [x] RLS e helper di isolamento tenant
- [x] seed, tipi TypeScript e Core SDK minimo
- [x] documentazione e suite di test

Fase 1.1 — Security Hardening:

- [x] gerarchia dei ruoli (`roles.rank`) e `assign_membership_role()`
- [x] bootstrap idempotente di modules/roles/permissions
- [x] hardening `SECURITY DEFINER`
- [x] isolamento `profiles` cross-tenant
- [x] coerenza `role.scope` ↔ membership scope
- [x] entitlement `property_modules` service-role only
- [x] audit log sulle mutazioni membership sensibili
- [x] CI GitHub Actions per SDK e database

`guest_requests` è il primo modulo esistente migrato al backend condiviso.
`shifts` e `transfers` restano da integrare progressivamente.

## Documentazione

```
docs/
  fase2-guest-requests-migration.md   stato Fase 2 e post-cutover
  architecture.md                    panoramica architetturale
  data-model.md                      modello dati Core
  auth.md                            auth staff e login condiviso
  permissions.md                     RBAC e scope organization/property
  guest-access.md                    guest_sessions
  rls.md                             enforcement e helper Core
  module-integration.md              integrazione dei moduli con la piattaforma
  architecture/monorepo.md           target monorepo (apps/web, modules/*,
                                      packages/*), boundary, CI, rollback
```

## Sviluppo locale

Richiede la Supabase CLI.

```bash
supabase start
supabase db reset
```

## Struttura

npm workspaces, consolidamento in corso secondo
`docs/architecture/monorepo.md`. `packages/core-sdk` (Fase 4),
`modules/housekeeping` (Fase 5) e `apps/web` (Fase 7) sono trasferimenti
riga-per-riga dai rispettivi repository precedenti, senza cambi di
comportamento — vedi lo storico dei commit per il dettaglio di ciascuna
fase. Dalla Fase 6, `apps/web` dipende da `modules/housekeeping` come
vera dipendenza workspace (`"*"`, non più `github:` pin), e
`modules/housekeeping` ha una build reale in libreria (Vite lib mode) che
produce `dist/` (JS, CSS Tailwind v4 compilato, dichiarazioni `.d.ts`
generate dai sorgenti, non a mano).

```
apps/
  web/           lo shell applicativo (ex repository hotsflow-app) —
                 routing, auth, property switcher, Home/Team/Settings,
                 punto di montaggio dei moduli embedded
    src/
    package.json, vite.config.ts, vercel.json
packages/
  core-sdk/      il Core SDK — identità, tenant, permessi, entitlement,
                 guest session
    src/
    package.json, tsconfig.json, eslint.config.mjs
  config/        base tsconfig/eslint condivisa, consumata via
                 devDependency (@hotsflow/config), mai import relativo
modules/
  housekeeping/  modulo staff Housekeeping embeddabile nello shell — build
                 in libreria (Vite lib mode + Tailwind v4/PostCSS + dts),
                 consumato da apps/web via dist/, non via src/
    src/
    package.json, tsconfig.json, eslint.config.mjs, vite.config.ts,
    postcss.config.js
supabase/
  migrations/    migration history condivisa Core + moduli migrati
  tests/         pgTAP: isolamento tenant, permessi, entitlement, guest session,
                 gerarchia ruoli e regression di sicurezza
  seed.sql       dati di sviluppo; reference data di sistema nelle migration
  config.toml
scripts/
  ci/            check di confine tra workspace, dipendenze circolari,
                 duplicazione pacchetti sensibili (React/Supabase) —
                 eseguiti in CI, non solo documentati
  dry-run/, freeze/, production/, verify/   script di migrazione/rehearsal
                 una tantum, non fanno parte di alcun workspace
.github/workflows/ci.yml
```

## Test

Database:

```bash
supabase test db
```

Da root, su tutti i workspace:

```bash
npm install
npm run lint
npm run typecheck
npm test
npm run build         # builda modules/housekeeping (vite build, dist/
                       # reale con JS/CSS/dts) e poi apps/web
                       # (tsc -b && vite build), che consuma quel dist/
npm run test:db        # richiede `supabase start` già avviato
npm run check:boundaries   # direzione delle dipendenze tra workspace
npm run check:circular     # cicli di import
npm run check:dedupe       # una sola versione installata di React/Supabase
```
