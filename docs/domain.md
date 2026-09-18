# Modello di dominio

Vedi CLAUDE.md §5 per il modello completo. Questo documento verrà arricchito con diagrammi e
dettagli via via che le entità vengono introdotte milestone per milestone (M1: tenants/properties/
memberships; M2: anagrafiche; M3: inventario; M4: prenotazioni/folio; ...).

## Stato attuale (M3)

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

M3 introduce l'inventario commerciale e la ricerca disponibilita' pubblica:

- `public.inventory(room_type_id, stay_date)` — `total`/`sold`/`blocked`, con
  `check (sold + blocked <= total)`: overbooking impossibile per costruzione (regola d'oro
  #10), non solo controllato a runtime. `blocked` e' anche il meccanismo con cui lo staff
  riduce manualmente la capacita' vendibile (es. manutenzione): `maintenance_blocks` non e'
  implementata, e' esplicitamente fuori perimetro ("manutenzione avanzata", vedi ADR-0006).
  CRUD riservato a `gm`+, dato di calendario (niente `deleted_at`, hard delete permesso).
  `sold` resta scrivibile da `gm`+ come le altre colonne fino a M4: quando esistera'
  `api_create_reservation` andra' rivalutato se irrigidirlo (trigger o revoke) per impedire
  manomissioni dirette fuori dal flusso di prenotazione.
- `private.app_secrets` — tabella singleton con il segreto HMAC per il `quote_token`
  (ADR-0005), leggibile solo da `private.generate_quote_token`/`private.verify_quote_token`
  (SECURITY DEFINER, nessun grant a nessun ruolo). Token = `base64(payload) || '.' || hex(hmac_sha256(payload, secret))`, TTL 15 minuti (`exp` dentro il payload).
- `public.api_search_availability(property_id, check_in, check_out, adults, children, room_type_ids)`
  — RPC pubblica (CLAUDE.md §8.2): **non** richiede membership di staff, e' concessa a
  `anon`/`authenticated`/`service_role` (endpoint da booking engine/agenti AI/software terzi).
  SECURITY DEFINER: bypassa la RLS staff-only di room_types/rate_plans/inventory/rate_prices/
  restrictions/taxes per restituire solo il risultato calcolato (mai le righe grezze). Per
  ogni combinazione (room_type × rate_plan) attiva della property, calcola in un'unica query
  set-based (niente loop per notte): disponibilita' residua per notte, `restrictions`
  applicate (min/max stay e CTA/CTD valutati sulla data di arrivo/partenza), prezzo totale in
  `amount_minor` (camera + IVA + tassa di soggiorno, quest'ultima moltiplicata per notti e
  adulti — i minori esenti restano un dettaglio rimandato a M7), `quote_token` quando la
  combinazione e' disponibile e ha prezzo completo.

Test: `supabase/tests/0004_inventory_availability.test.sql` (pgTAP, 22 asserzioni) copre RLS +
isolamento + ruolo su `inventory`, il vincolo anti-overbooking, il round-trip/manomissione/
scadenza del `quote_token`, il calcolo di prezzo/IVA/tassa di soggiorno, l'esclusione per
restrizione min_stay, l'esaurimento inventario, il filtro per occupazione massima, la
chiamabilita' da `anon` e gli errori di input non valido.

Non verificato in questo ambiente: il target di performance di M3 ("query disponibilita' <
100ms su 1M righe di benchmark", CLAUDE.md §16) richiede un Postgres reale con un dataset di
benchmark — non disponibile in questo sandbox (nessun docker daemon). La query e' scritta in
modo set-based con indici su `(room_type_id, stay_date)` per `inventory`/`rate_prices`/
`restrictions`, ma il numero effettivo va misurato con `EXPLAIN ANALYZE` su un'istanza reale
prima di considerare la milestone chiusa a tutti gli effetti.

Prossime milestone: M4 prenotazioni (`api_create_reservation`, idempotenza, folio,
outbox/webhook), M5 API `/v1`, ...
