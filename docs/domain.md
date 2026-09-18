# Modello di dominio

Vedi CLAUDE.md §5 per il modello completo. Questo documento verrà arricchito con diagrammi e
dettagli via via che le entità vengono introdotte milestone per milestone (M1: tenants/properties/
memberships; M2: anagrafiche; M3: inventario; M4: prenotazioni/folio; ...).

## Stato attuale (M1)

M0 ha introdotto estensioni Postgres e schemi (`private`, `api`, `audit`, `integrations`,
`billing`) — vedi `supabase/migrations/0001_extensions_and_schemas.sql`.

M1 introduce la gerarchia multi-tenant di base:

- `public.tenants` — catena/gruppo. Nessun insert diretto da `authenticated`: si crea solo
  via `public.api_create_tenant(name, slug)` (self-serve, vedi ADR-0003), che crea
  atomicamente il tenant e la prima membership `owner`.
- `public.properties` — hotel, `tenant_id` obbligatorio. CRUD gestito da ruolo `gm`+.
- `public.memberships` — associazione utente↔tenant con ruolo e `property_ids` (array vuoto =
  tutte le proprietà del tenant). Gestita solo da `owner`.
- `private.current_tenant_id()`, `private.has_tenant_role()`, `private.has_property_access()`
  — helper di autorizzazione (SECURITY DEFINER) usati da tutte le policy RLS presenti e
  future. `has_tenant_role` incorpora il gate MFA (aal2) per i ruoli owner/gm/accounting
  (vedi ADR-0002): senza aal2, quella membership non conta ai fini dell'autorizzazione.
- `public.custom_access_token_hook(event)` — Custom Access Token Hook (§6.5): inietta
  `tenant_id`/`role`/`property_ids` in `app_metadata` del JWT per routing/UI. L'autorizzazione
  fine resta sempre sugli helper `private.has_*`, mai sul contenuto del JWT.

Ruoli membership (`memberships.role`): `owner`, `gm`, `front_desk`, `housekeeping`,
`accounting`, `viewer` — gerarchia crescente in `private.has_tenant_role`.

Test di isolamento: `supabase/tests/0002_tenancy_rls.test.sql` (pgTAP) copre SELECT/INSERT/
UPDATE(tentativo di cambio tenant)/DELETE per le tre tabelle, test per ruolo, il gate MFA e
la restrizione per `property_ids`.

Prossime milestone: M2 anagrafiche (room_types, rooms, rate_plans, ...), M3 inventario, M4
prenotazioni/folio, ...
