-- Migration: 0009_rate_prices
-- Scopo: prezzi per notte/room_type/occupazione/rate_plan (M2). Dato di calendario,
--        non anagrafica in senso stretto: niente deleted_at, l'aggiornamento e'
--        upsert/hard delete della singola cella. Denaro come intero in unita'
--        minori + valuta (regola d'oro #5).
-- Rollback: drop table if exists public.rate_prices cascade;

create table public.rate_prices (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  property_id uuid not null references public.properties(id) on delete cascade,
  rate_plan_id uuid not null references public.rate_plans(id) on delete cascade,
  room_type_id uuid not null references public.room_types(id) on delete cascade,
  stay_date date not null,
  occupancy int not null check (occupancy > 0),
  amount_minor bigint not null check (amount_minor >= 0),
  currency char(3) not null default 'EUR',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  unique (rate_plan_id, room_type_id, stay_date, occupancy)
);
alter table public.rate_prices enable row level security;
create index rate_prices_tenant_idx on public.rate_prices(tenant_id);
create index rate_prices_property_idx on public.rate_prices(property_id);
create index rate_prices_lookup_idx on public.rate_prices(room_type_id, stay_date);

create policy tenant_boundary on public.rate_prices as restrictive to authenticated
  using      (tenant_id = (select private.current_tenant_id()))
  with check (tenant_id = (select private.current_tenant_id()));

create policy rate_prices_select on public.rate_prices for select to authenticated
  using ((select private.has_property_access(property_id, 'viewer')));

create policy rate_prices_insert on public.rate_prices for insert to authenticated
  with check ((select private.has_property_access(property_id, 'gm')));

create policy rate_prices_update on public.rate_prices for update to authenticated
  using      ((select private.has_property_access(property_id, 'gm')))
  with check ((select private.has_property_access(property_id, 'gm')));

create policy rate_prices_delete on public.rate_prices for delete to authenticated
  using ((select private.has_property_access(property_id, 'gm')));
