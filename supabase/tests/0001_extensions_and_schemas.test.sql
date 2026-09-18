-- pgTAP: verifica che la migration 0001 abbia creato estensioni e schemi attesi.
begin;
select plan(10);

select has_extension('pgcrypto');
select has_extension('btree_gist');
select has_extension('citext');
select has_extension('pg_trgm');
select has_extension('pg_cron');

select has_schema('private');
select has_schema('api');
select has_schema('audit');
select has_schema('integrations');
select has_schema('billing');

select * from finish();
rollback;
