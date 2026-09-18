-- pgTAP: inventory (RLS + ruoli), quote_token (HMAC round-trip/tamper/scadenza),
-- api_search_availability (prezzo/tasse, restrizioni, sold-out, occupazione,
-- input non valido). M3, CLAUDE.md §8.1/§8.2/§16.
begin;
select plan(22);

create schema if not exists tests;

create or replace function tests.login_as(p_user_id uuid, p_aal text default 'aal2')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object(
    'sub', p_user_id::text,
    'role', 'authenticated',
    'aal', p_aal
  )::text, true);
  execute 'set local role authenticated';
end;
$$;

create or replace function tests.logout()
returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
end;
$$;

grant usage on schema tests to authenticated;
grant execute on function tests.login_as(uuid, text) to authenticated;
grant execute on function tests.logout() to authenticated;

-- ── Fixture (come postgres, bypassa RLS) ─────────────────────────────────────
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
) values
  ('00000000-0000-0000-0000-000000000000', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', 'authenticated', 'authenticated', 'owner-a3@test.local', extensions.crypt('x', extensions.gen_salt('bf')), now(), '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', 'authenticated', 'authenticated', 'gm-a3@test.local', extensions.crypt('x', extensions.gen_salt('bf')), now(), '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3', 'authenticated', 'authenticated', 'frontdesk-a3@test.local', extensions.crypt('x', extensions.gen_salt('bf')), now(), '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', 'authenticated', 'authenticated', 'owner-b3@test.local', extensions.crypt('x', extensions.gen_salt('bf')), now(), '{}', '{}', now(), now(), '', '', '', '');

insert into public.tenants (id, name, slug) values
  ('11111111-1111-1111-1111-111111111111', 'Tenant A3', 'tenant-a3'),
  ('22222222-2222-2222-2222-222222222222', 'Tenant B3', 'tenant-b3');

insert into public.properties (id, tenant_id, name) values
  ('33333333-3333-3333-3333-333333333331', '11111111-1111-1111-1111-111111111111', 'Hotel A3'),
  ('33333333-3333-3333-3333-333333333332', '22222222-2222-2222-2222-222222222222', 'Hotel B3');

insert into public.memberships (tenant_id, user_id, role, property_ids) values
  ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', 'owner', '{}'),
  ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', 'gm', '{}'),
  ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3', 'front_desk', '{}'),
  ('22222222-2222-2222-2222-222222222222', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', 'owner', '{}');

-- room_type normale (max 2) + un room_type "piccolo" (max 1, per il filtro occupazione)
insert into public.room_types (id, tenant_id, property_id, name, code, base_occupancy, max_occupancy) values
  ('44444444-4444-4444-4444-444444444441', '11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333331', 'Doppia', 'DBL', 2, 2),
  ('44444444-4444-4444-4444-444444444442', '11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333331', 'Singola', 'SGL', 1, 1),
  ('44444444-4444-4444-4444-444444444443', '22222222-2222-2222-2222-222222222222', '33333333-3333-3333-3333-333333333332', 'Doppia B', 'DBL', 2, 2);

insert into public.rate_plans (id, tenant_id, property_id, name, code, cancellation_policy) values
  ('55555555-5555-5555-5555-555555555551', '11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333331', 'Flessibile', 'FLEX', 'flexible');

insert into public.taxes (tenant_id, property_id, kind, name, rate_bps) values
  ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333331', 'vat', 'IVA 10%', 1000);
insert into public.taxes (tenant_id, property_id, kind, name, amount_minor) values
  ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333331', 'city_tax', 'Tassa di soggiorno', 150);

insert into public.inventory (tenant_id, property_id, room_type_id, stay_date, total, sold, blocked) values
  ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333331', '44444444-4444-4444-4444-444444444441', '2026-08-01', 2, 0, 0),
  ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333331', '44444444-4444-4444-4444-444444444441', '2026-08-02', 2, 0, 0),
  ('22222222-2222-2222-2222-222222222222', '33333333-3333-3333-3333-333333333332', '44444444-4444-4444-4444-444444444443', '2026-08-01', 2, 0, 0);

insert into public.rate_prices (tenant_id, property_id, rate_plan_id, room_type_id, stay_date, occupancy, amount_minor) values
  ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333331', '55555555-5555-5555-5555-555555555551', '44444444-4444-4444-4444-444444444441', '2026-08-01', 2, 10000),
  ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333331', '55555555-5555-5555-5555-555555555551', '44444444-4444-4444-4444-444444444441', '2026-08-02', 2, 10000);

-- ── inventory: RLS + isolamento + ruolo ───────────────────────────────────────
select ok((select relrowsecurity from pg_class where oid = 'public.inventory'::regclass),
  'RLS attiva su public.inventory');

select tests.login_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', 'aal2'); -- gm_a

select is(
  (select count(*) from public.inventory where property_id = '33333333-3333-3333-3333-333333333332'),
  0::bigint, 'gm_a non vede l''inventory di tenant_b (isolamento SELECT)');

select tests.login_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3', 'aal2'); -- front_desk_a

select throws_ok(
  $$insert into public.inventory (tenant_id, property_id, room_type_id, stay_date, total) values ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333331', '44444444-4444-4444-4444-444444444442', '2026-08-01', 2)$$,
  null, null, 'front_desk_a non puo'' scrivere inventory: serve gm+ (test per ruolo)');

select tests.login_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', 'aal2'); -- gm_a

select lives_ok(
  $$insert into public.inventory (tenant_id, property_id, room_type_id, stay_date, total) values ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333331', '44444444-4444-4444-4444-444444444442', '2026-08-01', 2)$$,
  'gm_a puo'' scrivere inventory nel proprio tenant');

select tests.login_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', 'aal2'); -- owner_b

with upd as (
  update public.inventory set total = 99 where room_type_id = '44444444-4444-4444-4444-444444444441' and stay_date = '2026-08-01'
  returning 1
)
select is((select count(*) from upd), 0::bigint,
  'owner_b non puo'' aggiornare inventory di tenant_a (isolamento UPDATE)');

select tests.logout();

-- CHECK constraint anti-overbooking: sold+blocked non puo'' superare total.
select throws_ok(
  $$insert into public.inventory (tenant_id, property_id, room_type_id, stay_date, total, sold, blocked) values ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333331', '44444444-4444-4444-4444-444444444441', '2026-08-05', 2, 2, 1)$$,
  null, null, 'CHECK inventory_no_overbooking blocca sold+blocked > total per costruzione');

-- ── quote_token: round-trip, manomissione, scadenza ───────────────────────────
select is(
  private.verify_quote_token(private.generate_quote_token(jsonb_build_object('foo', 'bar', 'exp', extract(epoch from now() + interval '1 minute')::bigint))),
  jsonb_build_object('foo', 'bar', 'exp', extract(epoch from now() + interval '1 minute')::bigint),
  'quote_token: round-trip generate->verify restituisce lo stesso payload');

select is(
  private.verify_quote_token('not-a-valid-token'),
  null, 'quote_token: formato non valido (nessun punto) restituisce null');

select is(
  private.verify_quote_token(
    left(private.generate_quote_token(jsonb_build_object('exp', extract(epoch from now() + interval '1 minute')::bigint)), -1) || 'x'
  ),
  null, 'quote_token: firma manomessa restituisce null');

select is(
  private.verify_quote_token(private.generate_quote_token(jsonb_build_object('exp', extract(epoch from now() - interval '1 minute')::bigint))),
  null, 'quote_token: token scaduto (exp nel passato) restituisce null');

-- ── api_search_availability: prezzo, tasse, quote_token ───────────────────────
select is(
  (select (public.api_search_availability(
     '33333333-3333-3333-3333-333333333331'::uuid, '2026-08-01'::date, '2026-08-03'::date, 2, 0,
     array['44444444-4444-4444-4444-444444444441']::uuid[]
   )->'room_types'->0->'price'->>'room_amount_minor')::bigint),
  20000::bigint, 'prezzo camera per 2 notti = 2 x 10000 (regola d''oro #5: intero in unita'' minori)');

select is(
  (select (public.api_search_availability(
     '33333333-3333-3333-3333-333333333331'::uuid, '2026-08-01'::date, '2026-08-03'::date, 2, 0,
     array['44444444-4444-4444-4444-444444444441']::uuid[]
   )->'room_types'->0->'price'->>'vat_minor')::bigint),
  2000::bigint, 'IVA 10% su 20000 = 2000');

select is(
  (select (public.api_search_availability(
     '33333333-3333-3333-3333-333333333331'::uuid, '2026-08-01'::date, '2026-08-03'::date, 2, 0,
     array['44444444-4444-4444-4444-444444444441']::uuid[]
   )->'room_types'->0->'price'->>'city_tax_minor')::bigint),
  600::bigint, 'tassa di soggiorno 150/notte/adulto x 2 notti x 2 adulti = 600');

select is(
  (select (public.api_search_availability(
     '33333333-3333-3333-3333-333333333331'::uuid, '2026-08-01'::date, '2026-08-03'::date, 2, 0,
     array['44444444-4444-4444-4444-444444444441']::uuid[]
   )->'room_types'->0->'price'->>'amount_minor')::bigint),
  22600::bigint, 'totale = 20000 + 2000 + 600 = 22600');

select ok(
  (select (public.api_search_availability(
     '33333333-3333-3333-3333-333333333331'::uuid, '2026-08-01'::date, '2026-08-03'::date, 2, 0,
     array['44444444-4444-4444-4444-444444444441']::uuid[]
   )->'room_types'->0->>'quote_token') is not null),
  'quote_token presente quando la combinazione e'' disponibile');

select ok(
  (private.verify_quote_token(
    (public.api_search_availability(
       '33333333-3333-3333-3333-333333333331'::uuid, '2026-08-01'::date, '2026-08-03'::date, 2, 0,
       array['44444444-4444-4444-4444-444444444441']::uuid[]
     )->'room_types'->0->>'quote_token')
  ) is not null),
  'il quote_token generato da api_search_availability e'' verificabile');

-- ── api_search_availability: chiamabile da anon (endpoint pubblico) ───────────
select tests.login_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', 'aal1'); -- ruolo qualunque, aal irrilevante qui
select tests.logout();

set local role anon;
select ok(
  (public.api_search_availability(
     '33333333-3333-3333-3333-333333333331'::uuid, '2026-08-01'::date, '2026-08-03'::date, 2, 0,
     array['44444444-4444-4444-4444-444444444441']::uuid[]
   ) is not null),
  'api_search_availability e'' chiamabile da anon (nessuna membership richiesta)');
reset role;

-- ── api_search_availability: restrizioni, sold-out, occupazione, input non valido
insert into public.restrictions (tenant_id, property_id, room_type_id, stay_date, min_stay)
values ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333331', '44444444-4444-4444-4444-444444444441', '2026-08-01', 3);

select is(
  (select (public.api_search_availability(
     '33333333-3333-3333-3333-333333333331'::uuid, '2026-08-01'::date, '2026-08-03'::date, 2, 0,
     array['44444444-4444-4444-4444-444444444441']::uuid[]
   )->'room_types'->0->>'available')::boolean),
  false, 'min_stay=3 sulla data di arrivo rende non disponibile un soggiorno di 2 notti');

update public.inventory set sold = 2
  where room_type_id = '44444444-4444-4444-4444-444444444441' and stay_date = '2026-08-01';

select is(
  (select (public.api_search_availability(
     '33333333-3333-3333-3333-333333333331'::uuid, '2026-08-01'::date, '2026-08-03'::date, 2, 0,
     array['44444444-4444-4444-4444-444444444441']::uuid[]
   )->'room_types'->0->>'available')::boolean),
  false, 'inventory esaurito (sold=total) rende non disponibile');

select is(
  (select count(*) from jsonb_array_elements(public.api_search_availability(
     '33333333-3333-3333-3333-333333333331'::uuid, '2026-08-01'::date, '2026-08-03'::date, 2, 0, null
   )->'room_types') as rt
   where rt->>'room_type_id' = '44444444-4444-4444-4444-444444444442'),
  0::bigint, 'room_type con max_occupancy=1 escluso quando si cercano 2 adulti (filtro occupazione)');

select throws_ok(
  $$select public.api_search_availability('33333333-3333-3333-3333-333333333331'::uuid, '2026-08-03'::date, '2026-08-01'::date, 2, 0, null)$$,
  null, null, 'check_in >= check_out solleva INVALID_REQUEST');

select throws_ok(
  $$select public.api_search_availability('33333333-3333-3333-3333-333333333331'::uuid, '2026-08-01'::date, '2026-08-03'::date, 0, 0, null)$$,
  null, null, 'adults+children=0 solleva INVALID_REQUEST');

select * from finish();
rollback;
