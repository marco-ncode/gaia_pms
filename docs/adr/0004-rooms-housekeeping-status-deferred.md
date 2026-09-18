# ADR 0004: Stato housekeeping delle camere non modificabile direttamente in M2

- Stato: accettata
- Data: 2026-09-18
- Milestone: M2

## Contesto

`public.rooms.housekeeping_status` esiste da subito (fa parte dell'anagrafica camera), ma
CLAUDE.md prevede un'entita' dedicata `housekeeping_tasks` in M6 per il flusso operativo
reale (assegnazione task, completamento, board). La milestone M2 riguarda solo le
"anagrafiche" (CRUD strutturale room_types/rooms/rate_plans/rate_prices/restrictions/taxes),
non il flusso operativo housekeeping.

## Decisione

In M2 la policy UPDATE su `public.rooms` richiede il ruolo `gm`+ per **qualsiasi** colonna,
incluso `housekeeping_status`. Non viene creata una policy/RPC separata che permetta a
`housekeeping`/`front_desk` di cambiare solo lo stato pulizia: quel meccanismo arrivera' con
`housekeeping_tasks` in M6, probabilmente tramite una RPC dedicata (es.
`public.api_complete_housekeeping_task`) che aggiorna `rooms.housekeeping_status` con
`security definer`, invece di una policy RLS diretta sulla tabella.

## Alternative considerate

- Policy UPDATE separata gia' ora per il solo campo `housekeeping_status` aperta al ruolo
  `housekeeping` — scartata: Postgres RLS non supporta policy per singola colonna in modo
  pulito (richiederebbe trigger aggiuntivi), e anticiperebbe logica di M6 senza il contesto
  di `housekeeping_tasks`.

## Conseguenze

Fino a M6, il cambio di stato pulizia di una camera e' possibile solo per gm/owner (o via
service_role/staff interno). Nessun impatto sui dati: e' una restrizione, non un'apertura.
