# Modello di dominio

Vedi CLAUDE.md §5 per il modello completo. Questo documento verrà arricchito con diagrammi e
dettagli via via che le entità vengono introdotte milestone per milestone (M1: tenants/properties/
memberships; M2: anagrafiche; M3: inventario; M4: prenotazioni/folio; ...).

## Stato attuale (M2)

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

M2 introduce le anagrafiche di property, tutte `tenant_id`+`property_id` scoped con lo stesso
pattern RLS (`tenant_boundary` restrictive + `private.has_property_access`), policy incluse
nella stessa migration della `create table` (gli helper esistono gia' da M1):

- `public.room_types` — tipologie di camera (occupazione base/max, letto extra, mq). CRUD
  riservato a `gm`+. Anagrafica: `deleted_at`, mai hard delete da RLS.
- `public.rooms` — camere fisiche, FK a `room_type_id`. CRUD strutturale riservato a `gm`+;
  il cambio operativo di `housekeeping_status` giorno per giorno arriva con
  `housekeeping_tasks` in M6, non tramite update diretto qui (vedi ADR-0004).
- `public.rate_plans` — piani tariffari (`cancellation_policy` categoriale, colazione,
  prepagato). CRUD riservato a `gm`+. Anagrafica con soft delete.
- `public.rate_prices` — prezzo per (rate_plan, room_type, stay_date, occupancy), in
  `amount_minor`/`currency` (regola d'oro #5). Dato di calendario, non anagrafica: niente
  `deleted_at`, hard delete consentito sulla singola cella, gestito da `gm`+.
- `public.restrictions` — min/max stay, chiusure arrivo/partenza per (room_type, stay_date).
  Stesso trattamento "dato di calendario" di `rate_prices`.
- `public.taxes` — aliquote IVA (`rate_bps`) e tassa di soggiorno (`amount_minor`), un solo
  `kind` per riga (vincolo CHECK). Gestita da `accounting`+ (non solo `gm`+, a differenza
  delle altre anagrafiche M2): e' materia fiscale. Il calcolo effettivo (esenzioni, notti
  massime, fasce d'eta') arriva con il night audit/folio in M7; qui c'e' solo la definizione.

Non ancora implementata: `public.policies` (checkin/checkout time, child policy, deposito) —
elencata nel modello di dominio generale (§5) ma non nell'elenco esplicito della milestone M2
(§16); rimandata a quando servira' davvero (probabilmente M4/M6).

Non costruita in questa passata: l'interfaccia CRUD in `apps/staff` (resta uno stub) — il
criterio "CRUD staff" di M2 e' soddisfatto qui a livello di RLS/RPC e dimostrato dai test
pgTAP, non da schermate Next.js.

Test di isolamento: `supabase/tests/0003_anagrafiche_rls.test.sql` (pgTAP, 32 asserzioni) copre
RLS attiva, isolamento SELECT/UPDATE, test per ruolo (gm+ vs accounting+ vs front_desk negato)
e la differenza hard-delete-vietato (anagrafiche) vs hard-delete-permesso (dati di calendario)
per tutte e sei le tabelle.

Prossime milestone: M3 inventario e disponibilita' (`inventory`, `api_search_availability`,
`quote_token`), M4 prenotazioni/folio, ...
