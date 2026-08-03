-- One row per listing per date — the daily grain the marts aggregate from.
--
-- Left joins are deliberate. Listing 276450 appears in the calendar but not
-- in listings, and inner joining silently drops its 365 rows and $2,200 of
-- booked revenue, which visibly skews revenue-share splits.
with calendar as (

    select * from {{ ref('stg_calendar') }}

),

listings as (

    select * from {{ ref('stg_listings') }}

),

amenities as (

    select * from {{ ref('int_amenities_current') }}

),

joined as (

    select
        calendar.calendar_id,
        calendar.listing_id,
        calendar.calendar_date,
        calendar.is_available,
        calendar.reservation_id,
        calendar.price,
        calendar.minimum_nights,
        calendar.maximum_nights,

        -- Revenue only accrues on nights that are actually booked.
        case
            when not calendar.is_available then calendar.price
        end as revenue,

        listings.listing_name,
        listings.neighborhood,
        listings.property_type,
        listings.room_type,
        listings.accommodates,
        listings.host_id,

        -- Flags the calendar rows whose listing never loaded, so marts can
        -- include or exclude them explicitly rather than by accident.
        listings.listing_id is null as is_orphan_listing,

        amenities.has_air_conditioning,
        amenities.has_lockbox,
        amenities.has_first_aid_kit,
        amenities.amenity_count

    from calendar
    left join listings on calendar.listing_id = listings.listing_id
    left join amenities on calendar.listing_id = amenities.listing_id

)

select * from joined
