# Modello di dominio

Vedi CLAUDE.md §5 per il modello completo. Questo documento verrà arricchito con diagrammi e
dettagli via via che le entità vengono introdotte milestone per milestone (M1: tenants/properties/
memberships; M2: anagrafiche; M3: inventario; M4: prenotazioni/folio; ...).

## Stato attuale (M0)

Nessuna tabella di dominio esiste ancora. La milestone M0 introduce solo estensioni Postgres e
schemi (`private`, `api`, `audit`, `integrations`, `billing`) — vedi
`supabase/migrations/0001_extensions_and_schemas.sql`.
