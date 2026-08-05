with listing_universe as (

    -- The driving table, and the reason the grain includes hard deletes. The
    -- bridge is built off stg_amenities_changelog, which covers every listing
    -- the calendar references, including the ones stg_listings lacks.
    --
    -- distinct because this is a bridge at one row per listing per amenity.
    select distinct listing_id
    from {{ ref('int_listing_amenities') }}

),

listings as (

    select * from {{ ref('stg_listings') }}

),

final as (

    select
        listing_universe.listing_id,
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
        listings.host_name_masked,
        listings.host_since,
        listings.host_location,
        listings.price as list_price,
        listings.listing_id is null as is_orphan_listing

    from listing_universe
    left join listings
        on listing_universe.listing_id = listings.listing_id

)

select * from final
