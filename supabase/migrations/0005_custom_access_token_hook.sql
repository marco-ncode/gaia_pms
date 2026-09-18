-- Migration: 0005_custom_access_token_hook
-- Scopo: Custom Access Token Hook (CLAUDE.md §6.5) che inietta in app_metadata del JWT
--        tenant_id attivo, role e property_ids al momento dell'emissione del token.
--        Solo per routing/UI: l'autorizzazione fine resta sempre su private.has_*,
--        che legge lo stato live delle membership (revoca immediata).
-- Rollback: drop function if exists public.custom_access_token_hook(jsonb);

create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  claims jsonb;
  v_tenant_id uuid;
  v_role text;
  v_property_ids uuid[];
begin
  claims := coalesce(event->'claims', '{}'::jsonb);

  select m.tenant_id, m.role, m.property_ids
    into v_tenant_id, v_role, v_property_ids
  from public.memberships m
  where m.user_id = (event->>'user_id')::uuid
  limit 1;

  if v_tenant_id is not null then
    claims := jsonb_set(
      claims,
      '{app_metadata}',
      coalesce(claims->'app_metadata', '{}'::jsonb) || jsonb_build_object(
        'tenant_id', v_tenant_id,
        'role', v_role,
        'property_ids', to_jsonb(coalesce(v_property_ids, '{}'::uuid[]))
      )
    );
  end if;

  return jsonb_set(event, '{claims}', claims);
end;
$$;

revoke all on function public.custom_access_token_hook(jsonb) from public, anon, authenticated;
grant execute on function public.custom_access_token_hook(jsonb) to supabase_auth_admin;
grant usage on schema public to supabase_auth_admin;
grant select on public.memberships to supabase_auth_admin;
