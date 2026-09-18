-- Migration: 0011_taxes
-- Scopo: anagrafica fiscale per property (M2): aliquote IVA e tassa di
--        soggiorno. Il calcolo dettagliato (esenzioni, notti massime, fasce
--        d'eta') e' rimandato a M7 (night audit / folio); qui si registra solo
--        la definizione, in `rules` per i dettagli specifici del kind.
--        Gestione riservata al ruolo accounting+ (non solo gm+, a differenza
--        delle altre anagrafiche di M2): e' materia fiscale.
-- Rollback: drop table if exists public.taxes cascade;

create table public.taxes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  property_id uuid not null references public.properties(id) on delete cascade,
  kind text not null check (kind in ('vat','city_tax')),
  name text not null,
  rate_bps int check (rate_bps is null or (rate_bps >= 0 and rate_bps <= 10000)),
  amount_minor bigint check (amount_minor is null or amount_minor >= 0),
  currency char(3) not null default 'EUR',
  rules jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  deleted_at timestamptz,
  constraint taxes_kind_fields check (
    (kind = 'vat' and rate_bps is not null and amount_minor is null) or
    (kind = 'city_tax' and amount_minor is not null and rate_bps is null)
  )
);
alter table public.taxes enable row level security;
create index taxes_tenant_idx on public.taxes(tenant_id);
create index taxes_property_idx on public.taxes(property_id);

create policy tenant_boundary on public.taxes as restrictive to authenticated
  using      (tenant_id = (select private.current_tenant_id()))
  with check (tenant_id = (select private.current_tenant_id()));

create policy taxes_select on public.taxes for select to authenticated
  using ((select private.has_property_access(property_id, 'viewer')));

create policy taxes_insert on public.taxes for insert to authenticated
  with check ((select private.has_property_access(property_id, 'accounting')));

create policy taxes_update on public.taxes for update to authenticated
  using      ((select private.has_property_access(property_id, 'accounting')))
  with check ((select private.has_property_access(property_id, 'accounting')));

create policy taxes_delete on public.taxes for delete to authenticated
  using (false); -- solo soft delete via update deleted_at
