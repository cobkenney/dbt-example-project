with booked_nights as (

    select
        listing_id,
        reservation_id,
        calendar_date,
        price,
        revenue,
        is_orphan_listing
    from {{ ref('int_listing_daily') }}
    where reservation_id is not null

),

calendar_window as (

    -- Snapshot boundaries, derived rather than hardcoded
    select
        min(calendar_date) as window_start_date,
        max(calendar_date) as window_end_date
    from {{ ref('int_listing_daily') }}

),

reservations as (

    select
        -- Surrogate key over the real grain, following the same pattern as
        -- calendar_id. Needed because reservation_id is NOT unique on its own:
        -- the same id can appear on two different listings, covering two
        -- separate stays.
        {{ dbt_utils.generate_surrogate_key([
            'listing_id', 'reservation_id'
        ]) }} as reservation_key,

        booked_nights.reservation_id,
        booked_nights.listing_id,
        min(booked_nights.calendar_date) as check_in_date,
        max(booked_nights.calendar_date) as last_night_date,
        dateadd(day, 1, max(booked_nights.calendar_date)) as check_out_date,
        count(*) as nights,
        sum(booked_nights.revenue) as reservation_revenue,
        avg(booked_nights.price) as avg_nightly_price,
        boolor_agg(booked_nights.is_orphan_listing) as is_orphan_listing
    from booked_nights
    group by all

),

flagged as (

    select
        reservations.reservation_key,
        reservations.reservation_id,
        reservations.listing_id,
        reservations.check_in_date,
        reservations.last_night_date,
        reservations.check_out_date,
        reservations.nights,
        reservations.reservation_revenue,
        reservations.avg_nightly_price,
        reservations.is_orphan_listing,

        -- min/max collapse a reservation to one span, which is only honest if
        -- its nights are consecutive. This makes the assumption checkable
        -- rather than implicit: a gap means the id covers two separate stays,
        -- and check_out_date would overstate the stay. Asserted true in the
        -- .yml, so a future load that breaks it fails the build instead of
        -- quietly inflating length of stay.
        datediff(
            day, reservations.check_in_date, reservations.last_night_date
        ) + 1 = reservations.nights as is_contiguous,

        -- Censored at the snapshot edge: the stay began before the calendar
        -- opens or continues after it closes, so `nights` undercounts the real
        -- stay. Exclude these before reporting average length of stay, or the
        -- average is biased downward.
        reservations.check_in_date = calendar_window.window_start_date
            as is_left_censored,
        reservations.last_night_date = calendar_window.window_end_date
            as is_right_censored

    from reservations
    cross join calendar_window

)

select * from flagged
