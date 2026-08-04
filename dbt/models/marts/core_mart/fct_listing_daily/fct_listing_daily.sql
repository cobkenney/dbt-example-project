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

    -- Availability-run identity, for questions 3 and 26. Carried so those
    -- queries group on a column instead of writing a gap-and-island window
    -- function, which a semantic view cannot express at all.
    --
    -- BOTH ARE ONLY MEANINGFUL UNDER `where is_available`. On a booked night
    -- the sequence holds the number of the window that ended before it. Filter
    -- first, then group — see the column docs.
    is_window_start,
    availability_window_seq,

    neighborhood,
    property_type,
    room_type,
    accommodates,

    -- Carried at the daily grain so price-per-bedroom and price-per-bed can be
    -- computed against the date's actual nightly price, not the listing's
    -- advertised rate.
    bedrooms,
    beds,

    host_id,

    has_air_conditioning,
    has_lockbox,
    has_first_aid_kit,
    amenity_count,

    is_orphan_listing

from daily
