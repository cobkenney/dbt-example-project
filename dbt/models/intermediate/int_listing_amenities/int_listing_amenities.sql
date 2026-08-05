with latest_amenities as (

    select
        listing_id,
        amenities
    from {{ ref('stg_amenities_changelog') }}
    -- no relevant history exists relative to the calendar, so take current
    qualify
        row_number() over (
            partition by listing_id order by changed_at desc
        ) = 1

),

flattened as (

    select
        latest_amenities.listing_id,
        amenity.value::string as amenity_name
    from latest_amenities,
        lateral flatten(
            input => try_parse_json(latest_amenities.amenities)
        ) as amenity

)

select distinct
    listing_id,
    amenity_name
from flattened
