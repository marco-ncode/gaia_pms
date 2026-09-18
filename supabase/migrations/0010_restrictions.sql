-- Migration: 0010_restrictions
-- Scopo: restrizioni di vendita per room_type/notte (min/max stay, chiusure
--        arrivo/partenza) (M2). Dato di calendario come rate_prices: niente
--        deleted_at, hard delete consentito sulla singola cella.
-- Rollback: drop table if exists public.restrictions cascade;

create table public.restrictions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  property_id uuid not null references public.properties(id) on delete cascade,
  room_type_id uuid not null references public.room_types(id) on delete cascade,
  stay_date date not null,
  min_stay int check (min_stay is null or min_stay > 0),
  max_stay int check (max_stay is null or min_stay is null or max_stay >= min_stay),
  closed_to_arrival boolean not null default false,
  closed_to_departure boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  unique (room_type_id, stay_date)
);
alter table public.restrictions enable row level security;
create index restrictions_tenant_idx on public.restrictions(tenant_id);
create index restrictions_property_idx on public.restrictions(property_id);
create index restrictions_lookup_idx on public.restrictions(room_type_id, stay_date);

create policy tenant_boundary on public.restrictions as restrictive to authenticated
  using      (tenant_id = (select private.current_tenant_id()))
  with check (tenant_id = (select private.current_tenant_id()));

create policy restrictions_select on public.restrictions for select to authenticated
  using ((select private.has_property_access(property_id, 'viewer')));

create policy restrictions_insert on public.restrictions for insert to authenticated
  with check ((select private.has_property_access(property_id, 'gm')));

create policy restrictions_update on public.restrictions for update to authenticated
  using      ((select private.has_property_access(property_id, 'gm')))
  with check ((select private.has_property_access(property_id, 'gm')));

create policy restrictions_delete on public.restrictions for delete to authenticated
  using ((select private.has_property_access(property_id, 'gm')));
