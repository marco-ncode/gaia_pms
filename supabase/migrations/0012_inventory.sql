-- Migration: 0012_inventory
-- Scopo: inventario commerciale (M3, CLAUDE.md §5/§8.1): disponibilita' vendibile
--        per (room_type_id, stay_date). Overbooking impossibile per costruzione
--        (regola d'oro #10): CHECK sold+blocked<=total, non solo applicativo.
--        `blocked` sostituisce anche `maintenance_blocks`, fuori perimetro
--        (ADR-0006). `sold` scrivibile da gm+ fino a M4, vedi docs/domain.md.
-- Rollback: drop table if exists public.inventory cascade;

create table public.inventory (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  property_id uuid not null references public.properties(id) on delete cascade,
  room_type_id uuid not null references public.room_types(id) on delete cascade,
  stay_date date not null,
  total int not null default 0 check (total >= 0),
  sold int not null default 0 check (sold >= 0),
  blocked int not null default 0 check (blocked >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  unique (room_type_id, stay_date),
  constraint inventory_no_overbooking check (sold + blocked <= total)
);
alter table public.inventory enable row level security;
create index inventory_tenant_idx on public.inventory(tenant_id);
create index inventory_property_idx on public.inventory(property_id);

create policy tenant_boundary on public.inventory as restrictive to authenticated
  using      (tenant_id = (select private.current_tenant_id()))
  with check (tenant_id = (select private.current_tenant_id()));

create policy inventory_select on public.inventory for select to authenticated
  using ((select private.has_property_access(property_id, 'viewer')));

create policy inventory_insert on public.inventory for insert to authenticated
  with check ((select private.has_property_access(property_id, 'gm')));

create policy inventory_update on public.inventory for update to authenticated
  using      ((select private.has_property_access(property_id, 'gm')))
  with check ((select private.has_property_access(property_id, 'gm')));

create policy inventory_delete on public.inventory for delete to authenticated
  using ((select private.has_property_access(property_id, 'gm')));
