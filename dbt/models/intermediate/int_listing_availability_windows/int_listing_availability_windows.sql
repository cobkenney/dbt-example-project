-- One row per contiguous window of available dates per listing.
--
-- Gap-and-island: subtracting a row number from the date yields a constant for
-- consecutive dates, so that constant groups each island.
with available_dates as (

    select
        listing_id,
        calendar_date,
        maximum_nights,
        minimum_nights,
        dateadd(
            day,
            -row_number() over (
                partition by listing_id order by calendar_date
            ),
            calendar_date
        ) as island_group
    from {{ ref('stg_calendar') }}
    where is_available

),

runs as (

    select
        {{ dbt_utils.generate_surrogate_key([
            'listing_id', 'island_group'
        ]) }} as availability_window_id,
        listing_id,
        min(calendar_date) as window_start_date,
        max(calendar_date) as window_end_date,

        count(*) as window_length_nights,
        max(maximum_nights) as maximum_nights,
        max(minimum_nights) as minimum_nights,

        -- Clamped because both constraints bind in this data — the window in
        -- some cases, the owner's cap in 8 of 204.
        least(count(*), max(maximum_nights)) as longest_possible_stay_nights
    from available_dates
    group by all

)

select * from runs
