-- One row per reservation, carrying listing attributes so stay-length and
-- booking-value questions need no join.
--
-- This should most likely come from a source, but in the absence of a source,
-- we will use listings. This most likely means we are missing unconfirmed
-- reservations vs the reservations on listings are confirmed. A reservations
-- model would be key to this mart for understanding easily things like how many
-- reservations did we have, what is the avg length of stay, etc.
--
-- What that costs, stated plainly for anyone reporting off this table:
--   * A reservation exists here only because a night is occupied, so requested-
--     but-never-confirmed and cancelled bookings are invisible. Booking
--     conversion and cancellation rate cannot be measured from this table.
--   * There is no booking-created timestamp anywhere in the raw data, so
--     booking lead time and booking pace are also out of reach.
--   * A date the host blocked for themselves is indistinguishable from a
--     booked night except by reservation_id being populated.
with reservations as (

    select * from {{ ref('int_reservations') }}

),

listings as (

    select * from {{ ref('stg_listings') }}

),

amenities as (

    -- The flags come from int_listing_daily now that the pivot lives there, not
    -- from the bridge model — which carries only listing_id and amenity_name.
    -- Reduced back to one row per listing so this cannot fan out reservations;
    -- these columns are constant across a listing's daily rows, so any
    -- aggregate returns the same value.
    --
    -- Only the flags this mart exposes, for the same reason dim_listings names
    -- its six: int_listing_daily generates all 81, and letting them through in
    -- bulk would let a new amenity upstream change this mart's shape.
    select
        listing_id,
        min(amenity_count) as amenity_count,
        boolor_agg(has_air_conditioning) as has_air_conditioning,
        boolor_agg(has_lockbox) as has_lockbox,
        boolor_agg(has_first_aid_kit) as has_first_aid_kit
    from {{ ref('int_listing_daily') }}
    group by all

)

select
    -- The primary key, not reservation_id — that column is not unique on its
    -- own. Id 836 covers two separate one-night stays on different listings.
    reservations.reservation_key,
    reservations.reservation_id,
    reservations.listing_id,

    reservations.check_in_date,
    reservations.last_night_date,
    reservations.check_out_date,

    -- Precomputed for the same reason fct_listing_daily precomputes it: every
    -- bookings-per-month query needs it, and date_trunc inside a group by is
    -- easy to get subtly wrong. Keyed on check-in, so a stay spanning a month
    -- boundary counts in the month it started.
    date_trunc('month', reservations.check_in_date)::date as check_in_month,

    reservations.nights,
    reservations.reservation_revenue,
    reservations.avg_nightly_price,

    reservations.is_contiguous,
    reservations.is_left_censored,
    reservations.is_right_censored,

    -- One flag to filter on before averaging length of stay. Either edge
    -- truncates the stay, so treating them separately invites using one and
    -- forgetting the other.
    reservations.is_left_censored
    or reservations.is_right_censored as is_censored,

    -- Denormalized listing attributes: intentional star-schema redundancy, so
    -- "average length of stay by neighborhood" needs no join to dim_listings.
    listings.listing_name,
    listings.neighborhood,
    listings.property_type,
    listings.room_type,
    listings.accommodates,
    listings.host_id,

    amenities.has_air_conditioning,
    amenities.has_lockbox,
    amenities.has_first_aid_kit,
    amenities.amenity_count,

    reservations.is_orphan_listing

from reservations
-- Left, not inner: listing 276450 has booked nights but no listings row, and an
-- inner join would drop its reservations and their revenue.
left join listings on reservations.listing_id = listings.listing_id
left join amenities on reservations.listing_id = amenities.listing_id
