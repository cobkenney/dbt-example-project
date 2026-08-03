with source as (

    select * from {{ source('rentals', 'listings') }}

),

renamed as (

    select
        id as listing_id,
        name as listing_name,
        host_id,
        host_name,
        host_since,
        host_location,
        host_verifications,
        neighborhood,
        property_type,
        room_type,
        accommodates,

        -- Raw text like "2.5 baths" / "1 shared bath"; keep the label and
        -- pull the leading number out as a usable measure.
        bathrooms_text,
        try_cast(split_part(trim(bathrooms_text), ' ', 1) as number(4, 1))
            as bathrooms,
        contains(lower(bathrooms_text), 'shared') as is_shared_bathroom,

        bedrooms,
        beds,
        amenities,

        -- Currency string, e.g. "$125.00" — strip $ and thousands separators.
        try_cast(replace(replace(price, '$', ''), ',', '') as number(10, 2))
            as price,

        number_of_reviews,

        -- Landed as TEXT but every value is a valid ISO date.
        try_cast(first_review as date) as first_review_date,
        try_cast(last_review as date) as last_review_date,

        review_scores_rating

    from source

    -- 2 rows land with a NULL id and cannot be joined to anything downstream.
    where id is not null

)

select * from renamed
