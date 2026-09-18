# ADR 0003: Creazione self-serve di un tenant via RPC

- Stato: accettata
- Data: 2026-09-18
- Milestone: M1

## Contesto

CLAUDE.md non specifica se un nuovo tenant (catena/hotel) debba essere creato in self-serve
da un utente autenticato (flusso "crea il tuo account") oppure solo tramite provisioning
manuale/interno (B2B invite-only). Lo schema `tenants` ha pero' `plan text not null default
'starter'`, che suggerisce piani SaaS auto-attivabili.

## Decisione

Si adotta un flusso self-serve: qualunque utente autenticato (`auth.uid()` non nullo) puo'
invocare `public.api_create_tenant(name, slug)`, che internamente chiama
`private.create_tenant_with_owner()` (SECURITY DEFINER) e crea atomicamente il tenant e la
prima membership con ruolo `owner` per chi ha effettuato la chiamata. Non esiste alcuna
policy INSERT diretta su `public.tenants` per `authenticated`: la creazione passa solo da
questa RPC, coerente con la regola d'oro #1 (logica di dominio nelle funzioni SQL).

## Alternative considerate

- Provisioning solo da `service_role`/staff interno — scartata come default: bloccherebbe un
  eventuale onboarding self-serve senza un motivo esplicito in CLAUDE.md, ed e' comunque
  facilmente ottenibile in futuro revocando `execute` su `public.api_create_tenant` da
  `authenticated` senza cambi di schema.

## Conseguenze

Reversibile: per passare a invite-only basta una migration che fa
`revoke execute on function public.api_create_tenant(text, citext) from authenticated;`
Da rivedere quando si definisce il flusso di fatturazione/piano (billing, fuori perimetro
attuale) perche' oggi qualunque utente puo' creare tenant illimitati sul piano `starter`.
