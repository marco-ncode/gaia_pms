-- Migration: 0008_rate_plans
-- Scopo: anagrafica piani tariffari per property (M2). `cancellation_policy`
--        e' una categoria (non il motore di calcolo penali/no-show, che
--        appartiene al dominio prenotazioni/cancellazioni di M4).
-- Rollback: drop table if exists public.rate_plans cascade;

create table public.rate_plans (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  property_id uuid not null references public.properties(id) on delete cascade,
  name text not null,
  code text not null,
  cancellation_policy text not null default 'flexible'
    check (cancellation_policy in ('flexible','moderate','strict','non_refundable')),
  breakfast_included boolean not null default false,
  prepaid boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  deleted_at timestamptz,
  unique (property_id, code)
);
alter table public.rate_plans enable row level security;
create index rate_plans_tenant_idx on public.rate_plans(tenant_id);
create index rate_plans_property_idx on public.rate_plans(property_id);

create policy tenant_boundary on public.rate_plans as restrictive to authenticated
  using      (tenant_id = (select private.current_tenant_id()))
  with check (tenant_id = (select private.current_tenant_id()));

create policy rate_plans_select on public.rate_plans for select to authenticated
  using ((select private.has_property_access(property_id, 'viewer')));

create policy rate_plans_insert on public.rate_plans for insert to authenticated
  with check ((select private.has_property_access(property_id, 'gm')));

create policy rate_plans_update on public.rate_plans for update to authenticated
  using      ((select private.has_property_access(property_id, 'gm')))
  with check ((select private.has_property_access(property_id, 'gm')));

create policy rate_plans_delete on public.rate_plans for delete to authenticated
  using (false); -- solo soft delete via update deleted_at
