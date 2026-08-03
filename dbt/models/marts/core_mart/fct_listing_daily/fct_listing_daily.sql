-- One row per listing per date — the atomic fact table. Left at daily grain
-- rather than pre-aggregated by month so it serves both revenue-by-month and
-- point-in-time price questions.
with daily as (

    select * from {{ ref('int_listing_daily') }}

)

select
    calendar_id,
    listing_id,
    calendar_date,

    -- Precomputed: every revenue-by-month query needs it, and date_trunc inside
    -- a group by is easy to get subtly wrong.
    date_trunc('month', calendar_date)::date as month_start_date,

    is_available,
    reservation_id,
    price,
    revenue,
    minimum_nights,
    maximum_nights,

    neighborhood,
    property_type,
    room_type,
    accommodates,
    host_id,

    has_air_conditioning,
    has_lockbox,
    has_first_aid_kit,
    amenity_count,

    is_orphan_listing

from daily
