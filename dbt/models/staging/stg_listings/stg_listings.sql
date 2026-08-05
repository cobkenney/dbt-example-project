with source as (

    select * from {{ source('rentals', 'listings') }}

),

renamed as (

    select
        id as listing_id,
        name as listing_name,
        host_id,
        {{ mask_pii('host_name') }} as host_name_masked,
        host_since,
        host_location,
        host_verifications,
        neighborhood,
        property_type,
        room_type,
        accommodates,
        bathrooms_text,
        try_cast(split_part(trim(bathrooms_text), ' ', 1) as number(4, 1))
            as bathrooms,
        contains(lower(bathrooms_text), 'shared') as is_shared_bathroom,
        bedrooms,
        beds,
        amenities,
        try_cast(replace(replace(price, '$', ''), ',', '') as number(10, 2))
            as price,
        number_of_reviews,
        try_cast(first_review as date) as first_review_date,
        try_cast(last_review as date) as last_review_date,
        review_scores_rating
    from source
    -- Some source rows land with a NULL id and cannot be joined to anything
    -- downstream.
    where id is not null

)

select * from renamed
