-- Seed demo per sviluppo locale (M1: tenancy; M2: anagrafiche).
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

-- M2: anagrafiche minime per vedere subito qualcosa in apps/staff.
insert into public.room_types (id, tenant_id, property_id, name, code, base_occupancy, max_occupancy, size_sqm) values
  ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 'Doppia Standard', 'DBL', 2, 3, 22.0),
  ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 'Suite', 'STE', 2, 4, 38.0);

insert into public.rooms (tenant_id, property_id, room_type_id, number, floor) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000c1', '101', '1'),
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000c1', '102', '1'),
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000c2', '201', '2');

insert into public.rate_plans (id, tenant_id, property_id, name, code, cancellation_policy, breakfast_included, prepaid) values
  ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 'Flessibile con colazione', 'FLEX-BB', 'flexible', true, false),
  ('00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 'Non rimborsabile', 'NRF', 'non_refundable', false, true);

insert into public.taxes (tenant_id, property_id, kind, name, rate_bps) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 'vat', 'IVA 10%', 1000);

insert into public.taxes (tenant_id, property_id, kind, name, amount_minor) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 'city_tax', 'Tassa di soggiorno', 200);
