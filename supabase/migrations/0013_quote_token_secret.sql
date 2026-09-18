-- Migration: 0013_quote_token_secret
-- Scopo: meccanismo HMAC per il quote_token (CLAUDE.md §8.2, TTL 15 min).
--        Il segreto vive in una tabella singleton in `private`, generata una
--        sola volta con pgcrypto, leggibile SOLO dalle funzioni SECURITY
--        DEFINER qui sotto (nessun grant a nessun ruolo, nemmeno service_role):
--        vedi docs/adr/0005-quote-token-secret-storage.md per le alternative
--        scartate (Supabase Vault, variabile d'ambiente).
-- Rollback: drop function if exists private.verify_quote_token(text);
--           drop function if exists private.generate_quote_token(jsonb);
--           drop table if exists private.app_secrets;

create table private.app_secrets (
  id boolean primary key default true,
  quote_hmac_secret bytea not null,
  constraint app_secrets_singleton check (id)
);
insert into private.app_secrets (quote_hmac_secret) values (extensions.gen_random_bytes(32));

revoke all on private.app_secrets from public, anon, authenticated, service_role;

create or replace function private.generate_quote_token(p_payload jsonb)
returns text
language plpgsql stable security definer set search_path = '' as $$
declare
  v_secret bytea;
  v_payload_text text;
  v_sig text;
begin
  select quote_hmac_secret into v_secret from private.app_secrets;
  v_payload_text := p_payload::text;
  v_sig := encode(extensions.hmac(convert_to(v_payload_text, 'utf8'), v_secret, 'sha256'), 'hex');
  return encode(convert_to(v_payload_text, 'utf8'), 'base64') || '.' || v_sig;
end;
$$;

create or replace function private.verify_quote_token(p_token text)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_secret bytea;
  v_dot_pos int;
  v_payload_b64 text;
  v_sig text;
  v_expected_sig text;
  v_payload_text text;
  v_payload jsonb;
begin
  select quote_hmac_secret into v_secret from private.app_secrets;

  v_dot_pos := position('.' in p_token);
  if v_dot_pos = 0 then
    return null; -- formato non valido
  end if;

  v_payload_b64 := substring(p_token from 1 for v_dot_pos - 1);
  v_sig := substring(p_token from v_dot_pos + 1);

  v_payload_text := convert_from(decode(v_payload_b64, 'base64'), 'utf8');
  v_expected_sig := encode(extensions.hmac(convert_to(v_payload_text, 'utf8'), v_secret, 'sha256'), 'hex');

  if v_sig is distinct from v_expected_sig then
    return null; -- firma non valida: token manomesso o falsificato
  end if;

  v_payload := v_payload_text::jsonb;

  if (v_payload->>'exp')::bigint < extract(epoch from now())::bigint then
    return null; -- QUOTE_EXPIRED
  end if;

  return v_payload;
end;
$$;

revoke all on function private.generate_quote_token(jsonb) from public, anon, authenticated;
revoke all on function private.verify_quote_token(text) from public, anon, authenticated;
grant execute on function private.generate_quote_token(jsonb) to service_role;
grant execute on function private.verify_quote_token(text) to service_role;
