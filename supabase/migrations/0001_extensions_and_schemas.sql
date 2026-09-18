-- Migration: 0001_extensions_and_schemas
-- Scopo: abilita le estensioni Postgres richieste dal dominio e crea gli schemi
--        applicativi previsti da CLAUDE.md §2 (private, api, audit, integrations, billing).
--        Le estensioni relocatable vanno esplicitamente nello schema `extensions`
--        (convenzione piattaforma Supabase, gia' nel search_path via
--        `extra_search_path` di config.toml): qualsiasi funzione SECURITY DEFINER
--        con `set search_path = ''` deve quindi chiamarle come `extensions.*`
--        (es. `extensions.hmac(...)` in 0013), mai senza qualificare lo schema.
-- Rollback: drop schema if exists private, api, audit, integrations, billing cascade;
--           drop extension if exists pg_cron, pg_trgm, citext, btree_gist, pgcrypto;
--           drop schema if exists extensions;
--           (nessuna tabella dipende ancora da questi oggetti in questa milestone)

create schema if not exists extensions;

create extension if not exists pgcrypto with schema extensions;
create extension if not exists btree_gist with schema extensions;
create extension if not exists citext with schema extensions;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists pg_cron;

-- public: tabelle di dominio con RLS, esposte via PostgREST.
-- (schema "public" esiste già di default in Postgres/Supabase)

-- private: helper di autorizzazione e logica di dominio, mai esposto in PostgREST.
create schema if not exists private;

-- api: viste/RPC della superficie pubblica /v1.
create schema if not exists api;

-- audit, integrations, billing: schemi non esposti in PostgREST.
create schema if not exists audit;
create schema if not exists integrations;
create schema if not exists billing;

-- Nessuno schema oltre "public" e' esposto a anon/authenticated in questa milestone:
-- l'esposizione di "api" verra' decisa in M5 con la superficie pubblica /v1 (vedi ADR dedicato).
revoke all on schema private, api, audit, integrations, billing from public, anon, authenticated;
grant usage on schema private, api, audit, integrations, billing to postgres, service_role;
