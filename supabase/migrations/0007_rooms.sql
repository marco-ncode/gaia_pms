-- Migration: 0007_rooms
-- Scopo: anagrafica camere fisiche per property (M2). CRUD strutturale (numero,
--        piano, tipo, accessibilita') riservato a gm+. Le variazioni operative
--        di stato housekeeping giorno per giorno arriveranno con
--        housekeeping_tasks in M6 (non tramite update diretto qui): vedi
--        docs/adr/0004-rooms-housekeeping-status-deferred.md.
-- Rollback: drop table if exists public.rooms cascade;

create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  property_id uuid not null references public.properties(id) on delete cascade,
  room_type_id uuid not null references public.room_types(id) on delete restrict,
  number text not null,
  floor text,
  housekeeping_status text not null default 'clean'
    check (housekeeping_status in ('clean','dirty','inspected','out_of_order')),
  accessible boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  deleted_at timestamptz,
  unique (property_id, number)
);
alter table public.rooms enable row level security;
create index rooms_tenant_idx on public.rooms(tenant_id);
create index rooms_property_idx on public.rooms(property_id);
create index rooms_room_type_idx on public.rooms(room_type_id);

create policy tenant_boundary on public.rooms as restrictive to authenticated
  using      (tenant_id = (select private.current_tenant_id()))
  with check (tenant_id = (select private.current_tenant_id()));

create policy rooms_select on public.rooms for select to authenticated
  using ((select private.has_property_access(property_id, 'viewer')));

create policy rooms_insert on public.rooms for insert to authenticated
  with check ((select private.has_property_access(property_id, 'gm')));

create policy rooms_update on public.rooms for update to authenticated
  using      ((select private.has_property_access(property_id, 'gm')))
  with check ((select private.has_property_access(property_id, 'gm')));

create policy rooms_delete on public.rooms for delete to authenticated
  using (false); -- solo soft delete via update deleted_at
