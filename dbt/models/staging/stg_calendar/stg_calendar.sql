-- One row per listing per date. The raw table has 1 triplicated row
-- (listing 1303261 on 2022-07-07, fully identical), so dedupe to restore
-- the grain before anything downstream aggregates on it.
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

        -- The loader wrote the string 'NULL' rather than a true NULL.
        nullif(reservation_id, 'NULL') as reservation_id,

        -- Plain numeric string here, e.g. "125" — unlike listings.price,
        -- which carries a "$" prefix.
        try_cast(price as number(10, 2)) as price,

        minimum_nights,
        maximum_nights

    from deduplicated

)

select * from renamed
