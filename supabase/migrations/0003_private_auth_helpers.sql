-- Migration: 0003_private_auth_helpers
-- Scopo: helper di autorizzazione in `private`, letti live dalle policy RLS (CLAUDE.md §6.2).
--        Deviazione documentata rispetto al codice letterale di §6.2: `has_tenant_role`
--        aggiunge il gate MFA (aal2) per i ruoli owner/gm/accounting richiesto da §7/§6.5
--        ("MFA obbligatoria per gm/owner/accounting, policy as restrictive su aal='aal2'").
--        Vedi docs/adr/0002-mfa-aal2-in-has-tenant-role.md.
-- Rollback: drop function if exists private.has_property_access(uuid, text);
--           drop function if exists private.has_tenant_role(uuid, text);
--           drop function if exists private.current_tenant_id();

create or replace function private.current_tenant_id() returns uuid
language sql stable security definer set search_path = '' as $$
  select m.tenant_id from public.memberships m
  where m.user_id = (select auth.uid()) limit 1;
$$;

create or replace function private.has_tenant_role(p_tenant uuid, p_min text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.memberships m
    where m.user_id = (select auth.uid()) and m.tenant_id = p_tenant
      and (
        -- Gate MFA: un membership con ruolo owner/gm/accounting conta ai fini
        -- dell'autorizzazione solo se la sessione ha completato MFA (aal2).
        m.role not in ('owner','gm','accounting')
        or (select auth.jwt() ->> 'aal') = 'aal2'
      )
      and case p_min
            when 'viewer'      then m.role in ('viewer','housekeeping','front_desk','accounting','gm','owner')
            when 'front_desk'  then m.role in ('front_desk','accounting','gm','owner')
            when 'accounting'  then m.role in ('accounting','gm','owner')
            when 'gm'          then m.role in ('gm','owner')
            when 'owner'       then m.role = 'owner'
            else false end
  );
$$;

create or replace function private.has_property_access(p_property uuid, p_min text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.properties p
    join public.memberships m
      on m.tenant_id = p.tenant_id and m.user_id = (select auth.uid())
    where p.id = p_property
      and (cardinality(m.property_ids) = 0 or p_property = any(m.property_ids))
      and private.has_tenant_role(p.tenant_id, p_min)
  );
$$;

revoke all on function private.current_tenant_id() from public, anon, authenticated;
revoke all on function private.has_tenant_role(uuid, text) from public, anon, authenticated;
revoke all on function private.has_property_access(uuid, text) from public, anon, authenticated;
grant execute on function private.current_tenant_id() to authenticated, service_role;
grant execute on function private.has_tenant_role(uuid, text) to authenticated, service_role;
grant execute on function private.has_property_access(uuid, text) to authenticated, service_role;
