-- Migration: 0002_tenants_properties_memberships
-- Scopo: tabelle fondanti della gerarchia multi-tenant (CLAUDE.md §6.1):
--        tenants (catena/gruppo) -> properties (hotel) -> memberships (staff).
--        RLS abilitata subito (nessuna policy in questa migration: le policy
--        arrivano in 0004 dopo gli helper di 0003, quindi fino ad allora ogni
--        accesso da `authenticated` e' negato di default - stato sicuro).
-- Rollback: drop table if exists public.memberships, public.properties, public.tenants cascade;

create table public.tenants (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug extensions.citext unique not null,
  plan text not null default 'starter',
  settings jsonb not null default '{}',
  created_at timestamptz not null default now()
);
alter table public.tenants enable row level security;

create table public.properties (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null,
  timezone text not null default 'Europe/Rome',
  currency char(3) not null default 'EUR',
  settings jsonb not null default '{}',
  created_at timestamptz not null default now()
);
alter table public.properties enable row level security;
create index properties_tenant_idx on public.properties(tenant_id);

create table public.memberships (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id   uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in
    ('owner','gm','front_desk','housekeeping','accounting','viewer')),
  property_ids uuid[] not null default '{}',   -- vuoto = tutte le proprieta' del tenant
  created_at timestamptz not null default now(),
  primary key (user_id, tenant_id)
);
alter table public.memberships enable row level security;
create index memberships_user_idx on public.memberships(user_id);
create index memberships_tenant_idx on public.memberships(tenant_id, user_id);
