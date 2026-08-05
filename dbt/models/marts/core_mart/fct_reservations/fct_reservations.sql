with reservations as (

    select * from {{ ref('int_reservations') }}

),

listings as (

    -- int_listings, which covers the deleted listings too. That makes the join
    -- below find a row for every reservation — a deleted listing's attributes
    -- are still NULL, since it has none anywhere, but they are NULL from a row
    -- that exists rather than from a join that missed.
    select * from {{ ref('int_listings') }}

),

amenities as (

    -- The flags come from int_listing_daily now that the pivot lives there, not
    -- from the bridge model — which carries only listing_id and amenity_name.
    -- Reduced back to one row per listing so this cannot fan out reservations;
    -- these columns are constant across a listing's daily rows, so any
    -- aggregate returns the same value.
    --
    -- Only the flags this mart exposes, for the same reason dim_listings names
    -- the ones it carries: int_listing_daily generates a flag per known
    -- amenity, and letting them through in bulk would let a new amenity
    -- upstream change this mart's shape.
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

    reservations.reservation_key,
    reservations.reservation_id,
    reservations.listing_id,
    reservations.check_in_date,
    reservations.last_night_date,
    reservations.check_out_date,
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
    reservations.is_deleted

from reservations
left join listings on reservations.listing_id = listings.listing_id
left join amenities on reservations.listing_id = amenities.listing_id
