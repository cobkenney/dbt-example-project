-- One row per listing per date. Deduped because the raw table
-- can have duplicates at that grain.
with deduplicated as (

    {{ dbt_utils.deduplicate(
        relation=source('rentals', 'calendar'),
        partition_by='listing_id, date',
        order_by='date',
    ) }}

),

renamed as (

    select
        {{ dbt_utils.generate_surrogate_key(['listing_id', 'date']) }}
            as calendar_id,
        listing_id,
        date as calendar_date,
        available as is_available,
        nullif(reservation_id, 'NULL') as reservation_id,
        try_cast(price as number(10, 2)) as price,
        minimum_nights,
        maximum_nights
    from deduplicated

)

select * from renamed
