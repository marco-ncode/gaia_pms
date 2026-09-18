-- Migration: 0014_api_search_availability
-- Scopo: RPC pubblica di ricerca disponibilita' (M3, CLAUDE.md §8.2): endpoint
--        pubblico, NON richiede membership, concessa a anon/authenticated/
--        service_role. SECURITY DEFINER: bypassa la RLS staff-only di
--        room_types/rate_plans/inventory/rate_prices/restrictions/taxes,
--        restituisce solo il risultato calcolato. Set-based (niente loop per
--        notte); target < 100ms su 1M righe (§16) non verificato in sandbox.
-- Rollback: drop function if exists public.api_search_availability(uuid, date, date, int, int, uuid[]);

create or replace function public.api_search_availability(
  p_property_id uuid,
  p_check_in date,
  p_check_out date,
  p_adults int default 2,
  p_children int default 0,
  p_room_type_ids uuid[] default null
) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_nights int;
  v_occupancy int := coalesce(p_adults, 0) + coalesce(p_children, 0);
  v_result jsonb;
  v_vat record;
  v_city_tax record;
begin
  if p_check_in is null or p_check_out is null or p_check_in >= p_check_out then
    raise exception 'INVALID_REQUEST' using errcode = '22023',
      detail = 'check_in deve essere precedente a check_out';
  end if;

  if v_occupancy <= 0 then
    raise exception 'INVALID_REQUEST' using errcode = '22023',
      detail = 'adults + children deve essere maggiore di zero';
  end if;

  v_nights := p_check_out - p_check_in;

  select t.* into v_vat from public.taxes t
    where t.property_id = p_property_id and t.kind = 'vat' and t.deleted_at is null
    limit 1;
  select t.* into v_city_tax from public.taxes t
    where t.property_id = p_property_id and t.kind = 'city_tax' and t.deleted_at is null
    limit 1;

  with nights as (
    select generate_series(p_check_in, p_check_out - 1, interval '1 day')::date as stay_date
  ),
  candidate_room_types as (
    select rt.id, rt.name
    from public.room_types rt
    where rt.property_id = p_property_id
      and rt.deleted_at is null
      and rt.max_occupancy >= v_occupancy
      and (p_room_type_ids is null or rt.id = any(p_room_type_ids))
  ),
  candidate_rate_plans as (
    select rp.id, rp.name, rp.cancellation_policy, rp.breakfast_included, rp.prepaid
    from public.rate_plans rp
    where rp.property_id = p_property_id
      and rp.deleted_at is null
  ),
  combos as (
    select rt.id as room_type_id, rt.name as room_type_name,
           rp.id as rate_plan_id, rp.name as rate_plan_name,
           rp.cancellation_policy, rp.breakfast_included, rp.prepaid
    from candidate_room_types rt
    cross join candidate_rate_plans rp
  ),
  nightly as (
    select
      c.room_type_id, c.rate_plan_id, n.stay_date,
      coalesce(inv.total, 0) - coalesce(inv.sold, 0) - coalesce(inv.blocked, 0) as remaining,
      rp_price.amount_minor, rp_price.currency
    from combos c
    cross join nights n
    left join public.inventory inv
      on inv.room_type_id = c.room_type_id and inv.stay_date = n.stay_date
    left join public.rate_prices rp_price
      on rp_price.rate_plan_id = c.rate_plan_id
     and rp_price.room_type_id = c.room_type_id
     and rp_price.stay_date = n.stay_date
     and rp_price.occupancy = v_occupancy
  ),
  arrival_restriction as (
    select r.room_type_id, r.min_stay, r.max_stay, r.closed_to_arrival
    from public.restrictions r
    where r.property_id = p_property_id and r.stay_date = p_check_in
  ),
  departure_restriction as (
    select r.room_type_id, r.closed_to_departure
    from public.restrictions r
    where r.property_id = p_property_id and r.stay_date = p_check_out
  ),
  aggregated as (
    select
      c.room_type_id, c.room_type_name, c.rate_plan_id, c.rate_plan_name,
      c.cancellation_policy, c.breakfast_included, c.prepaid,
      bool_and(ni.remaining > 0) as inventory_ok,
      bool_and(ni.amount_minor is not null) as price_complete,
      sum(ni.amount_minor) as room_total_minor,
      max(ni.currency) as currency,
      jsonb_agg(jsonb_build_object('stay_date', ni.stay_date, 'remaining', ni.remaining) order by ni.stay_date) as per_night
    from combos c
    join nightly ni on ni.room_type_id = c.room_type_id and ni.rate_plan_id = c.rate_plan_id
    group by c.room_type_id, c.room_type_name, c.rate_plan_id, c.rate_plan_name,
             c.cancellation_policy, c.breakfast_included, c.prepaid
  )
  select jsonb_build_object(
    'property_id', p_property_id,
    'check_in', p_check_in,
    'check_out', p_check_out,
    'nights', v_nights,
    'adults', p_adults,
    'children', p_children,
    'room_types', coalesce(jsonb_agg(
      jsonb_build_object(
        'room_type_id', a.room_type_id,
        'room_type_name', a.room_type_name,
        'rate_plan_id', a.rate_plan_id,
        'rate_plan_name', a.rate_plan_name,
        'cancellation_policy', a.cancellation_policy,
        'breakfast_included', a.breakfast_included,
        'prepaid', a.prepaid,
        'available', (
          a.inventory_ok and a.price_complete
          and not coalesce(ar.closed_to_arrival, false)
          and not coalesce(dr.closed_to_departure, false)
          and (ar.min_stay is null or v_nights >= ar.min_stay)
          and (ar.max_stay is null or v_nights <= ar.max_stay)
        ),
        'restrictions', jsonb_build_object(
          'min_stay', ar.min_stay,
          'max_stay', ar.max_stay,
          'closed_to_arrival', coalesce(ar.closed_to_arrival, false),
          'closed_to_departure', coalesce(dr.closed_to_departure, false)
        ),
        'remaining_per_night', a.per_night,
        'price', case when a.price_complete then jsonb_build_object(
          'room_amount_minor', a.room_total_minor,
          'vat_minor', coalesce(round(a.room_total_minor * v_vat.rate_bps / 10000.0)::bigint, 0),
          'city_tax_minor', coalesce(v_city_tax.amount_minor * v_nights * p_adults, 0),
          'amount_minor', a.room_total_minor
            + coalesce(round(a.room_total_minor * v_vat.rate_bps / 10000.0)::bigint, 0)
            + coalesce(v_city_tax.amount_minor * v_nights * p_adults, 0),
          'currency', a.currency
        ) else null end,
        'quote_token', case when (a.inventory_ok and a.price_complete) then
          private.generate_quote_token(jsonb_build_object(
            'property_id', p_property_id,
            'room_type_id', a.room_type_id,
            'rate_plan_id', a.rate_plan_id,
            'check_in', p_check_in,
            'check_out', p_check_out,
            'adults', p_adults,
            'children', p_children,
            'amount_minor', a.room_total_minor
              + coalesce(round(a.room_total_minor * v_vat.rate_bps / 10000.0)::bigint, 0)
              + coalesce(v_city_tax.amount_minor * v_nights * p_adults, 0),
            'currency', a.currency,
            'exp', extract(epoch from (now() + interval '15 minutes'))::bigint
          ))
        else null end
      )
    ), '[]'::jsonb)
  )
  into v_result
  from aggregated a
  left join arrival_restriction ar on ar.room_type_id = a.room_type_id
  left join departure_restriction dr on dr.room_type_id = a.room_type_id;

  return v_result;
end;
$$;

revoke all on function public.api_search_availability(uuid, date, date, int, int, uuid[]) from public;
grant execute on function public.api_search_availability(uuid, date, date, int, int, uuid[])
  to anon, authenticated, service_role;
