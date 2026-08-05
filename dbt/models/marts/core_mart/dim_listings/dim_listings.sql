{{ config(
    pre_hook="set calendar_as_of_date = (select max(calendar_date)
              from {{ ref('int_listing_daily') }})"
) }}

with listings as (

    select * from {{ ref('int_listings') }}

),

daily_rollup as (

    select
        listing_id,
        count(*) as calendar_days,
        count_if(not is_available) as booked_nights,
        count_if(is_available) as available_nights,
        coalesce(sum(revenue), 0) as total_revenue,
        avg(price) as avg_nightly_price,
        min(price) as min_nightly_price,
        max(price) as max_nightly_price,
        min(amenity_count) as amenity_count,
        boolor_agg(has_air_conditioning) as has_air_conditioning,
        boolor_agg(has_lockbox) as has_lockbox,
        boolor_agg(has_first_aid_kit) as has_first_aid_kit,
        boolor_agg(has_wifi) as has_wifi,
        boolor_agg(has_heating) as has_heating,
        boolor_agg(has_kitchen) as has_kitchen
    from {{ ref('int_listing_daily') }}
    group by all

),

final as (

    select
        listings.listing_id,
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
        $calendar_as_of_date as as_of_date,
        listings.host_id,
        listings.host_name_masked,
        listings.host_since,
        listings.host_location,
        listings.list_price,
        daily_rollup.amenity_count,
        daily_rollup.has_air_conditioning,
        daily_rollup.has_lockbox,
        daily_rollup.has_first_aid_kit,
        daily_rollup.has_wifi,
        daily_rollup.has_heating,
        daily_rollup.has_kitchen,
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
        listings.is_orphan_listing

    from listings
    left join daily_rollup on listings.listing_id = daily_rollup.listing_id

)

select * from final
