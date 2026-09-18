# ADR 0001: Esposizione dello schema `api` rimandata a M5

- Stato: accettata
- Data: 2026-09-18
- Milestone: M0

## Contesto

CLAUDE.md §2 elenca uno schema `api` per "viste/RPC della superficie pubblica /v1", ma §4 e §8
mostrano le RPC pubbliche come funzioni `public.api_*` (es. `public.api_search_availability`,
`public.api_create_reservation`). Non è specificato se lo schema `api` debba essere esposto in
PostgREST (`api.schemas` in `supabase/config.toml`) o resti un contenitore chiamato solo da
service_role dalle Edge Functions.

## Decisione

In M0 lo schema `api` viene creato ma **non** esposto in PostgREST e **non** riceve grant per
`anon`/`authenticated` (solo `postgres`/`service_role`). La migrazione `0001` lo documenta con un
commento esplicito. La decisione su come/se esporlo (PostgREST diretto vs. solo tramite router
Hono in `supabase/functions/api-v1`) viene presa in M5, quando si implementa la superficie
pubblica `/v1` con OAuth2/API key, scopes e rate limit.

## Alternative considerate

- Esporre subito `api` in `api.schemas` — scartata: prematuro senza RPC né modello di auth
  client-machine definito, rischio di dover fare un breaking change prima ancora del rilascio.

## Conseguenze

Nessun impatto su dati esistenti (nessuna tabella ancora creata). Da rivedere esplicitamente in
M5; fino ad allora lo schema `api` resta inerte.
