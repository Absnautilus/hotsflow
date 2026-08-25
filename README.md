# hotsflow-core

Platform core condiviso per la suite hotel: identità staff, organizations/properties,
membership, ruoli/permessi, entitlement dei moduli e sessioni guest. Nessuna business
logic dei moduli vive qui — `shifts`, `transfers` e `guest_requests` restano
applicazioni separate che si aggancieranno progressivamente a questo core.

Vedi l'Architecture Proposal approvata per il contesto completo (diagrammi, audit dei
tre moduli esistenti, decisioni architetturali).

## Stato — Fase 1 in corso

- [x] Step 2 — schema, constraint, indici (`supabase/migrations/0001`–`0005`)
- [ ] Step 3 — RLS, helper function, test di isolamento tenant
- [ ] Step 4 — seed, tipi TypeScript, Core SDK minimo
- [ ] Step 5 — documentazione, suite di test finale

Nessuno dei tre moduli esistenti viene toccato in questa fase.

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
  config.toml    configurazione del progetto Supabase locale
```
