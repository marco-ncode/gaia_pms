# ADR 0006: `maintenance_blocks` non implementata, `inventory.blocked` come sostituto manuale

- Stato: accettata
- Data: 2026-09-18
- Milestone: M3

## Contesto

CLAUDE.md §8.1 mostra un vincolo di esclusione per `maintenance_blocks(room_id, period)` e
dice che "deve alimentare anche l'inventario commerciale: una camera in manutenzione riduce
total". Ma l'introduzione stessa del documento elenca esplicitamente "manutenzione avanzata"
tra le cose fuori perimetro ("Fuori perimetro: ... manutenzione avanzata ..."), e nessuna
milestone (§16) nomina `maintenance_blocks` tra i propri deliverable.

## Decisione

In M3 non viene creata la tabella `maintenance_blocks` ne' alcun meccanismo automatico che
derivi `inventory.total` dal conteggio delle camere fisiche meno i blocchi di manutenzione.
La colonna `inventory.blocked` (scrivibile da `gm`+) resta l'unico meccanismo con cui lo staff
riduce manualmente la capacita' vendibile per una data — sia per manutenzione sia per altri
usi (uso interno, cortesia, ecc.), senza distinguere il motivo del blocco.

## Alternative considerate

- Implementare comunque `maintenance_blocks` con il vincolo di esclusione di §8.1 — scartata:
  e' esplicitamente "manutenzione avanzata" fuori perimetro; aggiungerla ora significherebbe
  costruire un'entita' non richiesta da nessuna milestone.

## Conseguenze

Se in futuro serve tracciare *perche'* una camera e' bloccata (manutenzione vs uso interno) o
vincolare fisicamente le camere bloccate (non solo il conteggio commerciale), servira' una
nuova ADR e probabilmente `maintenance_blocks` con il vincolo `exclude using gist` di §8.1,
fuori dal perimetro attuale del progetto salvo richiesta esplicita.
