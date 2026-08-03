-- One row per listing: descriptive attributes plus amenity flags and lifetime
-- performance measures.
with amenities as (

    -- Driving table, not stg_listings — this sets the grain to all 50
    -- listings the calendar references, including orphan 276450.
    -- See ../README.md.

    select * from {{ ref('int_amenities_current') }}

),

listings as (

    select * from {{ ref('stg_listings') }}

),

daily_rollup as (

    select
        listing_id,
        count(*) as calendar_days,
        count_if(not is_available) as booked_nights,
        count_if(is_available) as available_nights,
        -- coalesce because 3 listings were never booked, so sum() over all-NULL
        -- revenue returns NULL. Zero is the honest measure.
        coalesce(sum(revenue), 0) as total_revenue,
        avg(price) as avg_nightly_price,
        min(price) as min_nightly_price,
        max(price) as max_nightly_price
    from {{ ref('int_listing_daily') }}
    group by all

),

final as (

    select
        amenities.listing_id,

        listings.listing_name,
        listings.neighborhood,
        listings.property_type,
        listings.room_type,
        listings.accommodates,
        listings.bedrooms,
        listings.beds,
        listings.bathrooms,
        listings.is_shared_bathroom,
        listings.number_of_reviews,
        listings.review_scores_rating,
        listings.first_review_date,
        listings.last_review_date,

        listings.host_id,
        listings.host_name,
        listings.host_since,
        listings.host_location,

        listings.price as list_price,

        amenities.amenity_count,
        amenities.has_air_conditioning,
        amenities.has_lockbox,
        amenities.has_first_aid_kit,
        amenities.has_wifi,
        amenities.has_heating,
        amenities.has_kitchen,

        daily_rollup.calendar_days,
        daily_rollup.booked_nights,
        daily_rollup.available_nights,
        daily_rollup.total_revenue,
        daily_rollup.avg_nightly_price,
        daily_rollup.min_nightly_price,
        daily_rollup.max_nightly_price,

        div0(
            daily_rollup.booked_nights, daily_rollup.calendar_days
        ) as occupancy_rate,

        listings.listing_id is null as is_orphan_listing

    from amenities
    left join listings on amenities.listing_id = listings.listing_id
    left join daily_rollup on amenities.listing_id = daily_rollup.listing_id

)

select * from final
