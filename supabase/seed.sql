-- Seed demo per sviluppo locale (M1: tenancy).
-- Crea un tenant demo con un owner e una property, per poter accedere subito
-- a Supabase Studio / staging locale senza passare dal flusso di signup.
-- Password demo: "demo1234" (solo locale, mai in produzione).

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
) values (
  '00000000-0000-0000-0000-000000000000',
  '00000000-0000-0000-0000-000000000001',
  'authenticated', 'authenticated', 'demo-owner@gaiapms.dev',
  crypt('demo1234', gen_salt('bf')), now(),
  '{}', '{}', now(), now(), '', '', '', ''
);

insert into public.tenants (id, name, slug, plan) values (
  '00000000-0000-0000-0000-0000000000a1', 'Gaia Resorts Demo', 'gaia-resorts-demo', 'starter'
);

insert into public.properties (id, tenant_id, name, timezone, currency) values (
  '00000000-0000-0000-0000-0000000000b1',
  '00000000-0000-0000-0000-0000000000a1',
  'Grand Hotel Demo', 'Europe/Rome', 'EUR'
);

insert into public.memberships (tenant_id, user_id, role, property_ids) values (
  '00000000-0000-0000-0000-0000000000a1',
  '00000000-0000-0000-0000-000000000001',
  'owner', '{}'
);
