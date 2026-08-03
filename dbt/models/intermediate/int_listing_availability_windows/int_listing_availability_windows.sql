-- One row per contiguous window of available dates per listing.
--
-- Classic gap-and-island: subtracting a row number from the date yields a
-- constant for consecutive dates, so that constant groups each island.
--
-- The longest bookable stay is the shorter of the window and the owner's
-- maximum_nights cap, and both genuinely bind in this data:
--   listing 1303261 — 159-night window under a 180-night cap -> window binds
--   listing  743211 — 206-night window capped to  90 nights  -> cap binds
-- The cap binds in 8 of 204 windows, so neither column alone is correct.
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

        -- Counts available dates, not datediff(start, end) — which would be one
        -- lower. Every available calendar date counts as a bookable night, so
        -- 1303261's 2022-02-03 -> 2022-07-11 window is 159 nights, not 158.
        count(*) as window_length_nights,
        max(maximum_nights) as maximum_nights,
        max(minimum_nights) as minimum_nights,

        -- The owner's cap can exceed the window, so clamp to the run.
        least(count(*), max(maximum_nights)) as longest_possible_stay_nights
    from available_dates
    group by all

)

select * from runs
