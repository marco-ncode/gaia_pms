-- pgTAP: isolamento tenant e test per ruolo su room_types/rooms/rate_plans/
-- rate_prices/restrictions/taxes (M2). Stesso schema di test di
-- 0002_tenancy_rls.test.sql: fixture indipendente, tests.login_as/logout
-- ridefiniti in questa transazione (rollback a fine file).
begin;
select plan(32);

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
  ('00000000-0000-0000-0000-000000000000', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', 'authenticated', 'authenticated', 'owner-a2@test.local', crypt('x', gen_salt('bf')), now(), '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', 'authenticated', 'authenticated', 'gm-a2@test.local', crypt('x', gen_salt('bf')), now(), '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3', 'authenticated', 'authenticated', 'frontdesk-a2@test.local', crypt('x', gen_salt('bf')), now(), '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa4', 'authenticated', 'authenticated', 'accounting-a2@test.local', crypt('x', gen_salt('bf')), now(), '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', 'authenticated', 'authenticated', 'owner-b2@test.local', crypt('x', gen_salt('bf')), now(), '{}', '{}', now(), now(), '', '', '', '');

insert into public.tenants (id, name, slug) values
  ('11111111-1111-1111-1111-111111111111', 'Tenant A2', 'tenant-a2'),
  ('22222222-2222-2222-2222-222222222222', 'Tenant B2', 'tenant-b2');

insert into public.properties (id, tenant_id, name) values
  ('33333333-3333-3333-3333-333333333331', '11111111-1111-1111-1111-111111111111', 'Hotel A2'),
  ('33333333-3333-3333-3333-333333333332', '22222222-2222-2222-2222-222222222222', 'Hotel B2');

insert into public.memberships (tenant_id, user_id, role, property_ids) values
  ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', 'owner', '{}'),
  ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', 'gm', '{}'),
  ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3', 'front_desk', '{}'),
  ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa4', 'accounting', '{}'),
  ('22222222-2222-2222-2222-222222222222', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', 'owner', '{}');

insert into public.room_types (id, tenant_id, property_id, name, code, base_occupancy, max_occupancy) values
  ('44444444-4444-4444-4444-444444444441', '11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333331', 'Doppia Standard', 'DBL', 2, 3),
  ('44444444-4444-4444-4444-444444444442', '22222222-2222-2222-2222-222222222222', '33333333-3333-3333-3333-333333333332', 'Doppia Standard B', 'DBL', 2, 3);

insert into public.rate_plans (id, tenant_id, property_id, name, code, cancellation_policy, breakfast_included) values
  ('55555555-5555-5555-5555-555555555551', '11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333331', 'Flessibile', 'FLEX', 'flexible', true),
  ('55555555-5555-5555-5555-555555555552', '22222222-2222-2222-2222-222222222222', '33333333-3333-3333-3333-333333333332', 'Flessibile B', 'FLEX', 'flexible', true);

insert into public.rooms (id, tenant_id, property_id, room_type_id, number) values
  ('66666666-6666-6666-6666-666666666661', '11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333331', '44444444-4444-4444-4444-444444444441', '101'),
  ('66666666-6666-6666-6666-666666666662', '22222222-2222-2222-2222-222222222222', '33333333-3333-3333-3333-333333333332', '44444444-4444-4444-4444-444444444442', '101');

insert into public.rate_prices (id, tenant_id, property_id, rate_plan_id, room_type_id, stay_date, occupancy, amount_minor) values
  ('77777777-7777-7777-7777-777777777771', '11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333331', '55555555-5555-5555-5555-555555555551', '44444444-4444-4444-4444-444444444441', '2026-06-01', 2, 12000),
  ('77777777-7777-7777-7777-777777777772', '22222222-2222-2222-2222-222222222222', '33333333-3333-3333-3333-333333333332', '55555555-5555-5555-5555-555555555552', '44444444-4444-4444-4444-444444444442', '2026-06-01', 2, 12000);

insert into public.restrictions (id, tenant_id, property_id, room_type_id, stay_date, min_stay) values
  ('88888888-8888-8888-8888-888888888881', '11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333331', '44444444-4444-4444-4444-444444444441', '2026-06-01', 2),
  ('88888888-8888-8888-8888-888888888882', '22222222-2222-2222-2222-222222222222', '33333333-3333-3333-3333-333333333332', '44444444-4444-4444-4444-444444444442', '2026-06-01', 2);

insert into public.taxes (id, tenant_id, property_id, kind, name, rate_bps) values
  ('99999999-9999-9999-9999-999999999991', '11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333331', 'vat', 'IVA 10%', 1000),
  ('99999999-9999-9999-9999-999999999992', '22222222-2222-2222-2222-222222222222', '33333333-3333-3333-3333-333333333332', 'vat', 'IVA 10% B', 1000);

-- ── RLS attiva su tutte e sei le tabelle ──────────────────────────────────────
select is(
  (select count(*) from pg_class
   where relname in ('room_types','rooms','rate_plans','rate_prices','restrictions','taxes')
     and relnamespace = 'public'::regnamespace
     and not relrowsecurity),
  0::bigint, 'RLS attiva su tutte le tabelle anagrafiche di M2');

-- ── room_types ───────────────────────────────────────────────────────────────
select tests.login_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', 'aal2'); -- gm_a

select is(
  (select count(*) from public.room_types where id = '44444444-4444-4444-4444-444444444442'),
  0::bigint, 'gm_a non vede il room_type di tenant_b (isolamento SELECT)');

select tests.login_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3', 'aal2'); -- front_desk_a

select throws_ok(
  $$insert into public.room_types (tenant_id, property_id, name, code, base_occupancy, max_occupancy) values ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333331', 'Suite', 'STE', 2, 4)$$,
  null, null, 'front_desk_a non puo'' creare un room_type: serve gm+ (test per ruolo)');

select tests.login_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa4', 'aal2'); -- accounting_a

select throws_ok(
  $$insert into public.room_types (tenant_id, property_id, name, code, base_occupancy, max_occupancy) values ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333331', 'Suite', 'STE', 2, 4)$$,
  null, null, 'accounting_a non puo'' creare un room_type: serve gm+, non basta accounting');

select tests.login_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', 'aal2'); -- gm_a

select lives_ok(
  $$insert into public.room_types (tenant_id, property_id, name, code, base_occupancy, max_occupancy) values ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333331', 'Suite', 'STE', 2, 4)$$,
  'gm_a puo'' creare un room_type nel proprio tenant');

select tests.login_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', 'aal2'); -- owner_b

with upd as (
  update public.room_types set name = 'hacked' where id = '44444444-4444-4444-4444-444444444441' returning 1
)
select is((select count(*) from upd), 0::bigint,
  'owner_b non puo'' aggiornare il room_type di tenant_a (isolamento UPDATE)');

select tests.login_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', 'aal2'); -- gm_a

with del as (
  delete from public.room_types where id = '44444444-4444-4444-4444-444444444441' returning 1
)
select is((select count(*) from del), 0::bigint,
  'nessun ruolo cancella un room_type via RLS (mai hard delete, solo deleted_at)');

-- ── rooms ────────────────────────────────────────────────────────────────────
select is(
  (select count(*) from public.rooms where id = '66666666-6666-6666-6666-666666666662'),
  0::bigint, 'gm_a non vede la room di tenant_b (isolamento SELECT)');

select tests.login_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3', 'aal2'); -- front_desk_a

select throws_ok(
  $$insert into public.rooms (tenant_id, property_id, room_type_id, number) values ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333331', '44444444-4444-4444-4444-444444444441', '102')$$,
  null, null, 'front_desk_a non puo'' creare una room: serve gm+ (test per ruolo)');

select tests.login_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', 'aal2'); -- gm_a

select lives_ok(
  $$insert into public.rooms (tenant_id, property_id, room_type_id, number) values ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333331', '44444444-4444-4444-4444-444444444441', '102')$$,
  'gm_a puo'' creare una room nel proprio tenant');

select tests.login_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', 'aal2'); -- owner_b

with upd as (
  update public.rooms set floor = 'hacked' where id = '66666666-6666-6666-6666-666666666661' returning 1
)
select is((select count(*) from upd), 0::bigint,
  'owner_b non puo'' aggiornare la room di tenant_a (isolamento UPDATE)');

select tests.login_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', 'aal2'); -- gm_a

with del as (
  delete from public.rooms where id = '66666666-6666-6666-6666-666666666661' returning 1
)
select is((select count(*) from del), 0::bigint,
  'nessun ruolo cancella una room via RLS (mai hard delete, solo deleted_at)');

-- ── rate_plans ───────────────────────────────────────────────────────────────
select is(
  (select count(*) from public.rate_plans where id = '55555555-5555-5555-5555-555555555552'),
  0::bigint, 'gm_a non vede il rate_plan di tenant_b (isolamento SELECT)');

select tests.login_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3', 'aal2'); -- front_desk_a

select throws_ok(
  $$insert into public.rate_plans (tenant_id, property_id, name, code) values ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333331', 'Non rimborsabile', 'NRF')$$,
  null, null, 'front_desk_a non puo'' creare un rate_plan: serve gm+ (test per ruolo)');

select tests.login_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', 'aal2'); -- gm_a

select lives_ok(
  $$insert into public.rate_plans (tenant_id, property_id, name, code) values ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333331', 'Non rimborsabile', 'NRF')$$,
  'gm_a puo'' creare un rate_plan nel proprio tenant');

select tests.login_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', 'aal2'); -- owner_b

with upd as (
  update public.rate_plans set name = 'hacked' where id = '55555555-5555-5555-5555-555555555551' returning 1
)
select is((select count(*) from upd), 0::bigint,
  'owner_b non puo'' aggiornare il rate_plan di tenant_a (isolamento UPDATE)');

select tests.login_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', 'aal2'); -- gm_a

with del as (
  delete from public.rate_plans where id = '55555555-5555-5555-5555-555555555551' returning 1
)
select is((select count(*) from del), 0::bigint,
  'nessun ruolo cancella un rate_plan via RLS (mai hard delete, solo deleted_at)');

-- ── rate_prices ──────────────────────────────────────────────────────────────
select is(
  (select count(*) from public.rate_prices where id = '77777777-7777-7777-7777-777777777772'),
  0::bigint, 'gm_a non vede il prezzo di tenant_b (isolamento SELECT)');

select tests.login_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3', 'aal2'); -- front_desk_a

select throws_ok(
  $$insert into public.rate_prices (tenant_id, property_id, rate_plan_id, room_type_id, stay_date, occupancy, amount_minor) values ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333331', '55555555-5555-5555-5555-555555555551', '44444444-4444-4444-4444-444444444441', '2026-06-02', 2, 12500)$$,
  null, null, 'front_desk_a non puo'' inserire un prezzo: serve gm+ (test per ruolo)');

select tests.login_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', 'aal2'); -- gm_a

select lives_ok(
  $$insert into public.rate_prices (tenant_id, property_id, rate_plan_id, room_type_id, stay_date, occupancy, amount_minor) values ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333331', '55555555-5555-5555-5555-555555555551', '44444444-4444-4444-4444-444444444441', '2026-06-02', 2, 12500)$$,
  'gm_a puo'' inserire un prezzo nel proprio tenant');

select tests.login_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', 'aal2'); -- owner_b

with upd as (
  update public.rate_prices set amount_minor = 1 where id = '77777777-7777-7777-7777-777777777771' returning 1
)
select is((select count(*) from upd), 0::bigint,
  'owner_b non puo'' aggiornare il prezzo di tenant_a (isolamento UPDATE)');

select tests.login_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', 'aal2'); -- gm_a

select lives_ok(
  $$delete from public.rate_prices where id = '77777777-7777-7777-7777-777777777771'$$,
  'gm_a puo'' cancellare una cella di prezzo (dato di calendario, non anagrafica)');

-- ── restrictions ─────────────────────────────────────────────────────────────
select is(
  (select count(*) from public.restrictions where id = '88888888-8888-8888-8888-888888888882'),
  0::bigint, 'gm_a non vede la restriction di tenant_b (isolamento SELECT)');

select tests.login_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3', 'aal2'); -- front_desk_a

select throws_ok(
  $$insert into public.restrictions (tenant_id, property_id, room_type_id, stay_date, min_stay) values ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333331', '44444444-4444-4444-4444-444444444441', '2026-06-03', 3)$$,
  null, null, 'front_desk_a non puo'' inserire una restriction: serve gm+ (test per ruolo)');

select tests.login_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', 'aal2'); -- gm_a

select lives_ok(
  $$insert into public.restrictions (tenant_id, property_id, room_type_id, stay_date, min_stay) values ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333331', '44444444-4444-4444-4444-444444444441', '2026-06-03', 3)$$,
  'gm_a puo'' inserire una restriction nel proprio tenant');

select tests.login_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', 'aal2'); -- owner_b

with upd as (
  update public.restrictions set min_stay = 1 where id = '88888888-8888-8888-8888-888888888881' returning 1
)
select is((select count(*) from upd), 0::bigint,
  'owner_b non puo'' aggiornare la restriction di tenant_a (isolamento UPDATE)');

select tests.login_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', 'aal2'); -- gm_a

select lives_ok(
  $$delete from public.restrictions where id = '88888888-8888-8888-8888-888888888881'$$,
  'gm_a puo'' cancellare una restriction (dato di calendario, non anagrafica)');

-- ── taxes ────────────────────────────────────────────────────────────────────
select is(
  (select count(*) from public.taxes where id = '99999999-9999-9999-9999-999999999992'),
  0::bigint, 'gm_a non vede la tax di tenant_b (isolamento SELECT)');

select tests.login_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3', 'aal2'); -- front_desk_a

select throws_ok(
  $$insert into public.taxes (tenant_id, property_id, kind, name, amount_minor) values ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333331', 'city_tax', 'Tassa di soggiorno', 200)$$,
  null, null, 'front_desk_a non puo'' inserire una tax: serve accounting+ (test per ruolo)');

select tests.login_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa4', 'aal2'); -- accounting_a

select lives_ok(
  $$insert into public.taxes (tenant_id, property_id, kind, name, amount_minor) values ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333331', 'city_tax', 'Tassa di soggiorno', 200)$$,
  'accounting_a puo'' inserire una tax nel proprio tenant (gate accounting+, non solo gm+)');

select tests.login_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', 'aal2'); -- owner_b

with upd as (
  update public.taxes set name = 'hacked' where id = '99999999-9999-9999-9999-999999999991' returning 1
)
select is((select count(*) from upd), 0::bigint,
  'owner_b non puo'' aggiornare la tax di tenant_a (isolamento UPDATE)');

select tests.login_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa4', 'aal2'); -- accounting_a

with del as (
  delete from public.taxes where id = '99999999-9999-9999-9999-999999999991' returning 1
)
select is((select count(*) from del), 0::bigint,
  'nessun ruolo cancella una tax via RLS (mai hard delete, solo deleted_at)');

select tests.logout();

select * from finish();
rollback;
