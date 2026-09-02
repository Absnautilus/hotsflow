# hotsflow-core

Platform core condiviso per la suite hotel: identità staff, organizations/properties,
membership, ruoli/permessi, entitlement dei moduli e sessioni guest. Nessuna business
logic dei moduli vive qui — `shifts`, `transfers` e `guest_requests` restano
applicazioni separate che si aggancieranno progressivamente a questo core.

Vedi l'Architecture Proposal approvata per il contesto completo (diagrammi, audit dei
tre moduli esistenti, decisioni architetturali).

## Stato — Fase 2 (migrazione `guest_requests`), Step 9

Il backend condiviso è **provisionato e validato end-to-end** contro il
progetto Supabase live (E2E reale via browser, `Housekeeping`
`e2e-smoke.yml`). **Il cutover di produzione non è avvenuto**: Vercel di
`guest_requests` punta ancora al vecchio progetto separato. Vedi
`docs/fase2-guest-requests-migration.md` per lo stato completo — modello
tenant/ruoli, deviazioni di sicurezza intenzionali, debito tecnico
residuo, configurazioni non ancora infrastructure-as-code, procedura per
nuove migration.

Questo repository possiede **l'intera migration history condivisa** del
progetto Supabase applicato in produzione — non solo lo schema del core:
`supabase/migrations/` include sia `0001`–`0014` (core) sia le migration
`guest_requests` rilocate e nuove (`YYYYMMDDHHMMSS_guest_requests_*.sql`).

## Stato — Fase 1.1 (Security Hardening) completata

Fase 1:

- [x] Step 2 — schema, constraint, indici (`supabase/migrations/0001`–`0005`)
- [x] Step 3 — RLS, helper function, test di isolamento tenant (`0006`–`0007`, `supabase/tests/`)
- [x] Step 4 — seed (`supabase/seed.sql`), tipi TypeScript, Core SDK minimo (`src/`)
- [x] Step 5 — documentazione (`docs/`), suite di test finale

Fase 1.1 — Security Hardening (`0008`–`0014`):

- [x] gerarchia dei ruoli (`roles.rank`) e `assign_membership_role()` — niente più privilege escalation via `core.staff.manage`
- [x] bootstrap dei reference data di sistema (`modules`, ruoli, permessi core, `role_permissions`) come migration idempotenti, non più seed-only
- [x] `REVOKE ... FROM PUBLIC` esplicito su tutte le funzioni `SECURITY DEFINER`
- [x] isolamento `profiles` cross-tenant
- [x] coerenza `role.scope` ↔ `membership` scope (trigger)
- [x] `property_modules` non più scrivibile da staff hotel — entitlement service-role only
- [x] audit log minimale sulle mutazioni membership sensibili
- [x] CI GitHub Actions (`.github/workflows/ci.yml`)

Nessuno dei tre moduli esistenti è stato toccato in Fase 1/1.1. `guest_requests`
è stato toccato a partire da Fase 2 (vedi sopra) — `shifts` e `transfers`
restano intatti.

Criteri di successo di Fase 1.1 (verificati end-to-end su un database pulito: le 14
migration → `seed.sql` → l'intera suite pgTAP, tutti insieme, come fa
realmente `supabase test db`). **Nota (Step 9):** questa frase è rimasta
per mesi vera solo "a mano" — il job `database` di `ci.yml` ha fallito su
ogni singolo run dalla sua introduzione fino a Step 9, per un artefatto
solo-locale della Supabase CLI (non un problema di questi criteri stessi),
root-causato e risolto in Step 9 (vedi
`docs/fase2-guest-requests-migration.md`, sezione "Why CI needed a
local-only-divergence fix"). Da quel fix in poi la frase è effettivamente
verificata da CI, non solo dichiarata:

- [x] conosce `organizations`
- [x] conosce `properties`
- [x] conosce le identità (`profiles`), isolate cross-tenant
- [x] gestisce `memberships` (property-scoped e organization-wide)
- [x] gestisce `permissions` (role-based, con entitlement dei moduli separata)
- [x] gerarchia dei ruoli senza privilege escalation, nessuna self-promotion
- [x] conosce i moduli abilitati (`property_modules`), non modificabile da staff hotel
- [x] supporta `guest_sessions` (revocabili, scadenza, agnostiche dal metodo di verifica)
- [x] `SECURITY DEFINER` non esposte a `PUBLIC` involontariamente
- [x] impedisce l'accesso cross-tenant (RLS, 29 assertion pgTAP su 17 file)

## Documentazione

```
docs/
  fase2-guest-requests-migration.md   stato Fase 2: modello legacy, deviazioni di
                           sicurezza intenzionali, debito tecnico, config non-IaC,
                           procedura nuove migration, stato produzione
  architecture.md         panoramica, cosa c'è e cosa manca deliberatamente
  data-model.md            le 10 tabelle: colonne, vincoli, indici
  auth.md                  flusso auth staff + come arrivare a un login unico lato hotel
  permissions.md           il modello RBAC, i ruoli seedati, l'accesso a livello organization
  guest-access.md          guest_sessions, la convenzione verification_level, come aggiungere un metodo
  rls.md                   le due tabelle di enforcement, le 6 helper function, un esempio per un nuovo modulo
  module-integration.md    la domanda "come collego un nuovo modulo alla piattaforma?"
```

## Sviluppo locale

Richiede la [Supabase CLI](https://supabase.com/docs/guides/cli).

```bash
supabase start        # avvia Postgres/Studio locali
supabase db reset      # applica le migration in supabase/migrations/ in ordine
```

## Struttura

```
supabase/
  migrations/    schema Postgres, in ordine di dipendenza (vedi commenti in ogni file);
                 0009 include il bootstrap idempotente di modules/roles/permissions di sistema
  tests/         17 file pgTAP: isolamento tenant, permessi, entitlement, guest session,
                 gerarchia ruoli, isolamento profili, grant SECURITY DEFINER
  seed.sql       dati di sviluppo — organization/property demo, entitlement di esempio;
                 i reference data di sistema vivono nelle migration, non più qui
  config.toml    configurazione del progetto Supabase locale
src/
  types/database.ts  tipi generati dallo schema (vedi header del file)
  types/domain.ts     tipi applicativi esposti dall'SDK — mai i tipi grezzi del DB
  client.ts            createCoreClient() — punto di ingresso dell'SDK
  profile.ts, memberships.ts, permissions.ts, modules.ts, guestSession.ts
  moduleContract.ts     il tipo ModuleDescriptor che un modulo usa per dichiararsi
.github/workflows/ci.yml   typecheck + test SDK, e migration+seed+pgTAP su ogni push/PR
```

## Test

Database (richiede l'estensione [pgTAP](https://pgtap.org/)):

```bash
supabase test db
```

Core SDK:

```bash
npm install
npm run typecheck
npm test
```

