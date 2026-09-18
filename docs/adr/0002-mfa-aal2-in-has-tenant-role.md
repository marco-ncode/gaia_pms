# ADR 0002: Gate MFA (aal2) incorporato in `private.has_tenant_role`

- Stato: accettata
- Data: 2026-09-18
- Milestone: M1

## Contesto

CLAUDE.md §7 richiede "MFA obbligatoria per gm/owner/accounting (policy as restrictive su
aal='aal2')", ma non specifica il meccanismo esatto: se debba trattarsi di una policy RLS
`restrictive` separata applicata tabella per tabella, oppure di un controllo centralizzato.
Le uniche tabelle "sensibili" esistenti in M1 sono `tenants`/`properties`/`memberships`
stesse; tabelle come `rate_plans`, `reservations` o `payments` (dove servirebbe applicare
policy restrittive specifiche) non esistono ancora.

## Decisione

Il controllo aal2 viene incorporato direttamente in `private.has_tenant_role(p_tenant, p_min)`:
se la membership dell'utente ha ruolo `owner`/`gm`/`accounting`, la funzione la considera
valida ai fini dell'autorizzazione solo se la sessione corrente ha `auth.jwt()->>'aal' =
'aal2'`. In caso contrario la membership viene trattata come inesistente (deny), anche per
azioni di sola lettura (`viewer`). Poiche' `has_property_access` chiama internamente
`has_tenant_role`, il gate si propaga automaticamente a ogni policy che lo utilizza, senza
bisogno di duplicare una policy `restrictive` su ogni tabella futura.

## Alternative considerate

- Policy `restrictive` dedicata su ogni tabella sensibile — scartata per ora: duplicherebbe
  la stessa condizione ovunque e andrebbe comunque ri-applicata a ogni nuova tabella
  (rate_plans, reservations, payments, api_keys) introdotta nelle milestone successive,
  violando "una sola fonte di verita'".

## Conseguenze

Un utente con ruolo owner/gm/accounting che non ha completato l'MFA non puo' fare **nulla**
nel tenant (nemmeno letture), finche' non completa lo step-up MFA: e' il comportamento piu'
conservativo e coerente con "MFA obbligatoria", ma va comunicato chiaramente in UI (staff
app, M2) per non confondere l'utente con un "accesso negato" silenzioso.
Se in futuro serve un comportamento piu' granulare (es. lettura consentita, scrittura
negata), va rivisto con un nuovo ADR prima di un eventuale M2+.
