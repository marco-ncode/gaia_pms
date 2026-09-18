-- Migration: 0004_tenancy_rls_policies
-- Scopo: policy RLS per tenants/properties/memberships, applicando alle tre tabelle
--        fondanti lo stesso pattern obbligatorio mostrato in CLAUDE.md §6.3 per
--        "reservations" (li' descritto come pattern generale, non solo per quella
--        tabella). Aggiunge inoltre la RPC di bootstrap per la creazione self-serve
--        di un nuovo tenant (vedi docs/adr/0003-self-serve-tenant-creation.md):
--        nessuna policy INSERT permette scritture dirette su `tenants` da
--        `authenticated` (regola d'oro #1: la creazione passa da una funzione SQL).
-- Rollback: drop function if exists public.api_create_tenant(text, citext);
--           drop function if exists private.create_tenant_with_owner(text, citext);
--           drop policy if exists tenants_select, tenants_insert, tenants_update, tenants_delete on public.tenants;
--           drop policy if exists tenant_boundary, properties_select, properties_insert, properties_update, properties_delete on public.properties;
--           drop policy if exists tenant_boundary, memberships_select, memberships_insert, memberships_update, memberships_delete on public.memberships;

-- ── tenants ──────────────────────────────────────────────────────────────────
create policy tenants_select on public.tenants for select to authenticated
  using ((select private.has_tenant_role(id, 'viewer')));

create policy tenants_insert on public.tenants for insert to authenticated
  with check (false); -- mai insert diretto: solo via public.api_create_tenant()

create policy tenants_update on public.tenants for update to authenticated
  using      ((select private.has_tenant_role(id, 'owner')))
  with check ((select private.has_tenant_role(id, 'owner')));

create policy tenants_delete on public.tenants for delete to authenticated
  using (false); -- mai hard delete su un tenant

-- ── properties ───────────────────────────────────────────────────────────────
create policy tenant_boundary on public.properties as restrictive to authenticated
  using      (tenant_id = (select private.current_tenant_id()))
  with check (tenant_id = (select private.current_tenant_id()));

create policy properties_select on public.properties for select to authenticated
  using ((select private.has_property_access(id, 'viewer')));

create policy properties_insert on public.properties for insert to authenticated
  with check ((select private.has_tenant_role(tenant_id, 'gm')));

create policy properties_update on public.properties for update to authenticated
  using      ((select private.has_property_access(id, 'gm')))
  with check ((select private.has_property_access(id, 'gm')));

create policy properties_delete on public.properties for delete to authenticated
  using (false); -- soft delete via settings/stato, non hard delete da RLS

-- ── memberships ──────────────────────────────────────────────────────────────
create policy tenant_boundary on public.memberships as restrictive to authenticated
  using      (tenant_id = (select private.current_tenant_id()))
  with check (tenant_id = (select private.current_tenant_id()));

create policy memberships_select on public.memberships for select to authenticated
  using ((select private.has_tenant_role(tenant_id, 'viewer')));

create policy memberships_insert on public.memberships for insert to authenticated
  with check ((select private.has_tenant_role(tenant_id, 'owner')));

create policy memberships_update on public.memberships for update to authenticated
  using      ((select private.has_tenant_role(tenant_id, 'owner')))
  with check ((select private.has_tenant_role(tenant_id, 'owner')));

create policy memberships_delete on public.memberships for delete to authenticated
  using ((select private.has_tenant_role(tenant_id, 'owner')));

-- ── bootstrap: creazione self-serve di un nuovo tenant + owner ────────────────
create or replace function private.create_tenant_with_owner(p_name text, p_slug citext)
returns public.tenants
language plpgsql security definer set search_path = '' as $$
declare
  v_tenant public.tenants;
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;

  insert into public.tenants (name, slug) values (p_name, p_slug)
  returning * into v_tenant;

  insert into public.memberships (tenant_id, user_id, role, property_ids)
  values (v_tenant.id, v_uid, 'owner', '{}');

  return v_tenant;
end;
$$;

revoke all on function private.create_tenant_with_owner(text, citext) from public, anon, authenticated;
grant execute on function private.create_tenant_with_owner(text, citext) to service_role;

create or replace function public.api_create_tenant(p_name text, p_slug citext)
returns public.tenants
language sql security definer set search_path = '' as $$
  select * from private.create_tenant_with_owner(p_name, p_slug);
$$;

revoke all on function public.api_create_tenant(text, citext) from public, anon;
grant execute on function public.api_create_tenant(text, citext) to authenticated;
