-- Migration: 0006_room_types
-- Scopo: anagrafica tipologie di camera per property (M2, CLAUDE.md §5/§16).
--        Policy RLS gia' complete in questa stessa migration: gli helper
--        private.has_property_access/has_tenant_role esistono da M1 (0003).
--        Soft delete (deleted_at): e' un'anagrafica (regola d'oro, CLAUDE.md §4),
--        quindi niente hard delete da RLS.
-- Rollback: drop table if exists public.room_types cascade;

create table public.room_types (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  property_id uuid not null references public.properties(id) on delete cascade,
  name text not null,
  code text not null,
  base_occupancy int not null check (base_occupancy > 0),
  max_occupancy int not null check (max_occupancy >= base_occupancy),
  extra_bed_allowed boolean not null default false,
  size_sqm numeric(6,2) check (size_sqm is null or size_sqm > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  deleted_at timestamptz,
  unique (property_id, code)
);
alter table public.room_types enable row level security;
create index room_types_tenant_idx on public.room_types(tenant_id);
create index room_types_property_idx on public.room_types(property_id);

create policy tenant_boundary on public.room_types as restrictive to authenticated
  using      (tenant_id = (select private.current_tenant_id()))
  with check (tenant_id = (select private.current_tenant_id()));

create policy room_types_select on public.room_types for select to authenticated
  using ((select private.has_property_access(property_id, 'viewer')));

create policy room_types_insert on public.room_types for insert to authenticated
  with check ((select private.has_property_access(property_id, 'gm')));

create policy room_types_update on public.room_types for update to authenticated
  using      ((select private.has_property_access(property_id, 'gm')))
  with check ((select private.has_property_access(property_id, 'gm')));

create policy room_types_delete on public.room_types for delete to authenticated
  using (false); -- solo soft delete via update deleted_at
