-- pgTAP: isolamento tenant e test per ruolo su tenants/properties/memberships
-- (CLAUDE.md §14: "per ogni tabella tenant-scoped un test 0 righe di un altro tenant
-- su SELECT/INSERT/UPDATE(cambio tenant_id)/DELETE + test per ruolo").
--
-- Fixture: tenant_a (owner_a, viewer_a, front_desk_restricted su una sola property),
--          tenant_b (owner_b). Tutta la fixture viene creata come `postgres`
--          (bypassa RLS per essere table owner); gli helper tests.login_as/logout,
--          creati in questa stessa transazione, simulano una sessione autenticata
--          impostando request.jwt.claims + `set local role authenticated` cosi'
--          che le policy RLS (TO authenticated) vengano davvero valutate.
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

-- Una volta passati al ruolo `authenticated`, un successivo login_as()/logout()
-- viene eseguito CON quel ruolo: serve quindi USAGE/EXECUTE espliciti, dato che
-- una schema appena creata non concede privilegi impliciti a PUBLIC.
grant usage on schema tests to authenticated;
grant execute on function tests.login_as(uuid, text) to authenticated;
grant execute on function tests.logout() to authenticated;

-- ── Fixture (come postgres, bypassa RLS) ─────────────────────────────────────
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
) values
  ('00000000-0000-0000-0000-000000000000', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', 'authenticated', 'authenticated', 'owner-a@test.local', extensions.crypt('x', extensions.gen_salt('bf')), now(), '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', 'authenticated', 'authenticated', 'viewer-a@test.local', extensions.crypt('x', extensions.gen_salt('bf')), now(), '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3', 'authenticated', 'authenticated', 'invited-a@test.local', extensions.crypt('x', extensions.gen_salt('bf')), now(), '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa4', 'authenticated', 'authenticated', 'fd-restricted-a@test.local', extensions.crypt('x', extensions.gen_salt('bf')), now(), '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', 'authenticated', 'authenticated', 'owner-b@test.local', extensions.crypt('x', extensions.gen_salt('bf')), now(), '{}', '{}', now(), now(), '', '', '', '');

insert into public.tenants (id, name, slug) values
  ('11111111-1111-1111-1111-111111111111', 'Tenant A', 'tenant-a'),
  ('22222222-2222-2222-2222-222222222222', 'Tenant B', 'tenant-b');

insert into public.properties (id, tenant_id, name) values
  ('33333333-3333-3333-3333-333333333331', '11111111-1111-1111-1111-111111111111', 'Hotel A1'),
  ('33333333-3333-3333-3333-333333333332', '22222222-2222-2222-2222-222222222222', 'Hotel B1');

insert into public.memberships (tenant_id, user_id, role, property_ids) values
  ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', 'owner', '{}'),
  ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', 'viewer', '{}'),
  ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa4', 'front_desk', array['33333333-3333-3333-3333-333333333331']::uuid[]),
  ('22222222-2222-2222-2222-222222222222', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', 'owner', '{}');

-- ── Sanity: RLS attiva su tutte e tre le tabelle ─────────────────────────────
select ok((select relrowsecurity from pg_class where oid = 'public.tenants'::regclass), 'RLS attiva su public.tenants');
select ok((select relrowsecurity from pg_class where oid = 'public.properties'::regclass), 'RLS attiva su public.properties');
select ok((select relrowsecurity from pg_class where oid = 'public.memberships'::regclass), 'RLS attiva su public.memberships');

-- ── tenants ──────────────────────────────────────────────────────────────────
select tests.login_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', 'aal2'); -- owner_a

select is(
  (select count(*) from public.tenants where id = '22222222-2222-2222-2222-222222222222'),
  0::bigint, 'owner_a non vede tenant_b (isolamento SELECT tenants)');

select is(
  (select count(*) from public.tenants where id = '11111111-1111-1111-1111-111111111111'),
  1::bigint, 'owner_a vede il proprio tenant');

select throws_ok(
  $$insert into public.tenants (name, slug) values ('Rogue', 'rogue-tenant')$$,
  null, null, 'insert diretto su tenants sempre negato (solo via public.api_create_tenant)');

select lives_ok(
  $$update public.tenants set name = 'Tenant A rinominato' where id = '11111111-1111-1111-1111-111111111111'$$,
  'owner_a (aal2) puo'' aggiornare il proprio tenant');

select is(
  (select name from public.tenants where id = '11111111-1111-1111-1111-111111111111'),
  'Tenant A rinominato', 'la rinomina di tenant_a e'' stata applicata');

select tests.login_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', 'aal2'); -- owner_b

with upd as (
  update public.tenants set name = 'hacked' where id = '11111111-1111-1111-1111-111111111111'
  returning 1
)
select is(
  (select count(*) from upd),
  0::bigint, 'owner_b non puo'' aggiornare tenant_a (isolamento UPDATE tenants)');

with del as (
  delete from public.tenants where id = '22222222-2222-2222-2222-222222222222' returning 1
)
select is(
  (select count(*) from del),
  0::bigint, 'nessun ruolo cancella un tenant via RLS (mai hard delete)');

select tests.login_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', 'aal2'); -- viewer_a

with upd as (
  update public.tenants set name = 'viewer hack' where id = '11111111-1111-1111-1111-111111111111'
  returning 1
)
select is(
  (select count(*) from upd),
  0::bigint, 'viewer_a (ruolo viewer) non puo'' aggiornare il proprio tenant (test per ruolo)');

select tests.login_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', 'aal1'); -- owner_a SENZA mfa

with upd as (
  update public.tenants set name = 'no mfa' where id = '11111111-1111-1111-1111-111111111111'
  returning 1
)
select is(
  (select count(*) from upd),
  0::bigint, 'owner_a senza MFA (aal1) non puo'' aggiornare il tenant: gate aal2 attivo');

-- ── properties ───────────────────────────────────────────────────────────────
select tests.login_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', 'aal2'); -- owner_a

select is(
  (select count(*) from public.properties where id = '33333333-3333-3333-3333-333333333332'),
  0::bigint, 'owner_a non vede la property di tenant_b (isolamento SELECT properties)');

select is(
  (select count(*) from public.properties where id = '33333333-3333-3333-3333-333333333331'),
  1::bigint, 'owner_a vede la property del proprio tenant');

select lives_ok(
  $$insert into public.properties (id, tenant_id, name) values ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', 'Hotel A2')$$,
  'owner_a (gm+) puo'' creare una nuova property nel proprio tenant');

select throws_ok(
  $$insert into public.properties (tenant_id, name) values ('22222222-2222-2222-2222-222222222222', 'Hotel intruso')$$,
  null, null, 'owner_a non puo'' creare una property nel tenant_b (tenant_boundary + has_tenant_role)');

select lives_ok(
  $$update public.properties set name = 'Hotel A1 rinominato' where id = '33333333-3333-3333-3333-333333333331'$$,
  'owner_a puo'' rinominare la property del proprio tenant');

select throws_ok(
  $$update public.properties set tenant_id = '22222222-2222-2222-2222-222222222222' where id = '33333333-3333-3333-3333-333333333331'$$,
  null, null, 'owner_a non puo'' spostare una property in un altro tenant (tentativo di cambio tenant_id)');

select tests.login_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', 'aal2'); -- viewer_a

select throws_ok(
  $$insert into public.properties (tenant_id, name) values ('11111111-1111-1111-1111-111111111111', 'Hotel viewer')$$,
  null, null, 'viewer_a non puo'' creare property: serve ruolo gm+ (test per ruolo)');

select tests.login_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', 'aal2'); -- owner_b

with upd as (
  update public.properties set name = 'hacked' where id = '33333333-3333-3333-3333-333333333331'
  returning 1
)
select is(
  (select count(*) from upd),
  0::bigint, 'owner_b non puo'' aggiornare la property di tenant_a (isolamento UPDATE properties)');

with del as (
  delete from public.properties where id = '33333333-3333-3333-3333-333333333331' returning 1
)
select is(
  (select count(*) from del),
  0::bigint, 'nessun ruolo cancella una property via RLS (mai hard delete)');

-- ── memberships ──────────────────────────────────────────────────────────────
select tests.login_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', 'aal2'); -- owner_a

select is(
  (select count(*) from public.memberships where tenant_id = '22222222-2222-2222-2222-222222222222'),
  0::bigint, 'owner_a non vede le membership di tenant_b (isolamento SELECT memberships)');

select is(
  (select count(*) from public.memberships where tenant_id = '11111111-1111-1111-1111-111111111111'),
  3::bigint, 'owner_a vede le membership del proprio tenant');

select tests.login_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', 'aal2'); -- viewer_a

select throws_ok(
  $$insert into public.memberships (tenant_id, user_id, role, property_ids) values ('11111111-1111-1111-1111-111111111111', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', 'viewer', '{}')$$,
  null, null, 'viewer_a non puo'' invitare membri: serve ruolo owner (test per ruolo)');

select tests.login_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', 'aal2'); -- owner_a

select lives_ok(
  $$insert into public.memberships (tenant_id, user_id, role, property_ids) values ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3', 'front_desk', '{}')$$,
  'owner_a puo'' invitare un nuovo membro nel proprio tenant');

select throws_ok(
  $$insert into public.memberships (tenant_id, user_id, role, property_ids) values ('22222222-2222-2222-2222-222222222222', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3', 'front_desk', '{}')$$,
  null, null, 'owner_a non puo'' inserire una membership nel tenant_b');

select lives_ok(
  $$update public.memberships set role = 'accounting' where tenant_id = '11111111-1111-1111-1111-111111111111' and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2'$$,
  'owner_a puo'' cambiare il ruolo di un membro del proprio tenant');

select throws_ok(
  $$update public.memberships set tenant_id = '22222222-2222-2222-2222-222222222222' where tenant_id = '11111111-1111-1111-1111-111111111111' and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2'$$,
  null, null, 'owner_a non puo'' spostare una membership in un altro tenant');

select lives_ok(
  $$delete from public.memberships where tenant_id = '11111111-1111-1111-1111-111111111111' and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3'$$,
  'owner_a puo'' revocare una membership nel proprio tenant');

select tests.login_as('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', 'aal2'); -- owner_b

with upd as (
  update public.memberships set role = 'gm'
  where tenant_id = '11111111-1111-1111-1111-111111111111' and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1'
  returning 1
)
select is(
  (select count(*) from upd),
  0::bigint, 'owner_b non puo'' modificare le membership di tenant_a (isolamento UPDATE memberships)');

-- ── property_ids: restrizione a singola property per un ruolo front_desk ─────
select tests.login_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa4', 'aal2'); -- front_desk_restricted (solo Hotel A1)

select is(
  (select count(*) from public.properties where id = '33333333-3333-3333-3333-333333333331'),
  1::bigint, 'front_desk con property_ids=[A1] vede Hotel A1');

select is(
  (select count(*) from public.properties where id = '33333333-3333-3333-3333-333333333333'),
  0::bigint, 'front_desk con property_ids=[A1] NON vede Hotel A2 (restrizione property_ids)');

select tests.logout();

select * from finish();
rollback;
