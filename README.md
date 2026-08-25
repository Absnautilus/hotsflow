# hotsflow-core

Platform core condiviso per la suite hotel: identità staff, organizations/properties,
membership, ruoli/permessi, entitlement dei moduli e sessioni guest. Nessuna business
logic dei moduli vive qui — `shifts`, `transfers` e `guest_requests` restano
applicazioni separate che si aggancieranno progressivamente a questo core.

Vedi l'Architecture Proposal approvata per il contesto completo (diagrammi, audit dei
tre moduli esistenti, decisioni architetturali).

## Stato — Fase 1 completata

- [x] Step 2 — schema, constraint, indici (`supabase/migrations/0001`–`0005`)
- [x] Step 3 — RLS, helper function, test di isolamento tenant (`0006`–`0007`, `supabase/tests/`)
- [x] Step 4 — seed (`supabase/seed.sql`), tipi TypeScript, Core SDK minimo (`src/`)
- [x] Step 5 — documentazione (`docs/`), suite di test finale

Nessuno dei tre moduli esistenti è stato toccato in questa fase.

Criteri di successo (verificati end-to-end su un database pulito: migration
0001–0007 → `seed.sql` → suite pgTAP, tutti insieme, come fa realmente
`supabase test db`):

- [x] conosce `organizations`
- [x] conosce `properties`
- [x] conosce le identità (`profiles`)
- [x] gestisce `memberships` (property-scoped e organization-wide)
- [x] gestisce `permissions` (role-based, con entitlement dei moduli separata)
- [x] conosce i moduli abilitati (`property_modules`)
- [x] supporta `guest_sessions` (revocabili, scadenza, agnostiche dal metodo di verifica)
- [x] impedisce l'accesso cross-tenant (RLS, 13 assertion pgTAP)

## Documentazione

```
docs/
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
  migrations/    schema Postgres, in ordine di dipendenza (vedi commenti in ogni file)
  tests/         test pgTAP (isolamento tenant, permessi, entitlement, guest session)
  seed.sql       dati di sviluppo (2 organization, 3 property, moduli, ruoli — nessuna
                 credenziale reale, vedi il file per il bootstrap degli utenti di test)
  config.toml    configurazione del progetto Supabase locale
src/
  types/database.ts  tipi generati dallo schema (vedi header del file)
  types/domain.ts     tipi applicativi esposti dall'SDK — mai i tipi grezzi del DB
  client.ts            createCoreClient() — punto di ingresso dell'SDK
  profile.ts, memberships.ts, permissions.ts, modules.ts, guestSession.ts
  moduleContract.ts     il tipo ModuleDescriptor che un modulo usa per dichiararsi
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

