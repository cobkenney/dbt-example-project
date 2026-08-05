with source as (

    select * from {{ source('rentals', 'amenities_changelog') }}

),

renamed as (

    select
        {{ dbt_utils.generate_surrogate_key(['listing_id', 'change_at']) }}
            as amenities_change_id,
        listing_id,
        change_at as changed_at,
        amenities

    from source

)

select * from renamed
