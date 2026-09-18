# ADR 0005: Segreto HMAC del quote_token in una tabella singleton `private`

- Stato: accettata
- Data: 2026-09-18
- Milestone: M3

## Contesto

CLAUDE.md §8.2 richiede un `quote_token` "HMAC server-side, TTL 15 min" ma non specifica dove
vive la chiave di firma. Le opzioni realistiche sono: Supabase Vault (`supabase_vault`,
richiede l'estensione e la gestione delle chiavi di cifratura del progetto), una variabile
d'ambiente/secret dell'Edge Function (ma la generazione del token avviene in SQL, dentro
`api_search_availability`, non nell'Edge Function), oppure una tabella Postgres ordinaria
protetta solo da RLS/grant.

## Decisione

Il segreto vive in `private.app_secrets`, tabella singleton (un solo possibile valore di `id`,
forzato a `true` da un CHECK) con una colonna `bytea` generata una volta con
`gen_random_bytes(32)` alla creazione della migration. Nessun grant a nessun ruolo (nemmeno
`service_role`): e' leggibile solo dall'interno delle funzioni `private.generate_quote_token`/
`private.verify_quote_token`, entrambe `SECURITY DEFINER`, che bypassano la RLS in quanto
possedute dal proprietario della tabella.

## Alternative considerate

- Supabase Vault — scartata per ora: aggiunge una dipendenza/estensione (`supabase_vault`) e un
  concetto (chiavi di progetto per la cifratura) non necessari per un HMAC interno che non deve
  mai lasciare il database; da riconsiderare se in futuro servira' anche decifrare segreti
  scritti da un servizio esterno.
- Env var dell'Edge Function — scartata: il token e' generato/verificato interamente in SQL
  (dentro le RPC `api_*`), non nel livello Edge Function; duplicare il segreto in due posti
  aumenterebbe la superficie di errore.

## Conseguenze

Rotazione del segreto = una nuova migration che sostituisce la riga (invalida tutti i
quote_token in circolazione, accettabile dato il TTL di 15 minuti). Nessun accesso diretto al
segreto e' possibile via API pubblica o Studio con un ruolo normale, solo con accesso diretto al
database come superuser/proprietario.
