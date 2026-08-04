-- Business problem #3 — Long Stay / Picky Renter
--
-- Longest possible stay for listings offering both a lockbox and a first aid
-- kit, respecting both the availability window and the owner's maximum_nights.
--
-- Verified: listing 1303261 -> 159 nights.
--   1303261  Beacon Hill  159 nights  (159-night window, 180-night cap)
--    182613  Charlestown  112 nights  (112-night window, 1125-night cap)
--
-- This query groups availability windows rather than deriving them. It used to
-- read a dedicated fct_listing_availability_windows mart, which was collapsed
-- into here: 2 models and 25 tests served this one question, and the daily fact
-- reproduces the answer exactly. See models/README.md, "Collapsed models".
--
-- The gap-and-island itself now lives on fct_listing_daily as
-- availability_window_seq, so this query groups on a column instead of
-- subtracting a row number from a date. That column is why questions 3 and 26
-- can also be verified queries on sem_listing_daily, where a window function
-- cannot be expressed at all.
--
-- FILTER is_available BEFORE GROUPING, as the where clause below does. The
-- sequence is a running count of windows started, so a booked night carries the
-- number of the window that ended before it. Group without the filter and each
-- window collects the booked nights that follow it, reporting a longer run than
-- exists.
--
-- Two traps remain here, both of which produce a plausible wrong answer, and
-- neither of which the column encodes:
--
--   1. longest_possible_stay_nights must be least(window, cap). BOTH bind in
--      this data, so neither column alone answers the question:
--        listing 1303261 — 159-night window under a 180-night cap -> window
--        listing  743211 — 206-night window capped to  90 nights  -> cap
--      The cap binds in 8 of 204 windows across the whole calendar. Neither
--      listing returned below is cap-bound, so the clamp is invisible in this
--      result set but not optional.
--
--   2. Window length is count(*), NOT datediff(min, max), which is one lower.
--      Every available calendar date is a bookable night: 2022-02-03 through
--      2022-07-11 is 159 nights, not 158.
--
-- listing_name comes from dim_listings — fct_listing_daily deliberately omits
-- it, since a name repeated on 365 rows per listing is the denormalization the
-- star schema exists to avoid.
with windows as (

    select
        listing_id,
        availability_window_seq,

        -- Rows, not datediff — see trap 2 above.
        count(*) as window_length_nights,
        max(minimum_nights) as minimum_nights,
        max(maximum_nights) as maximum_nights,

        -- Clamped — see trap 1 above.
        least(count(*), max(maximum_nights)) as longest_possible_stay_nights

    from {{ ref('fct_listing_daily') }}
    where
        is_available
        and has_lockbox
        and has_first_aid_kit
    group by all

)

select
    windows.listing_id,
    listings.listing_name,
    listings.neighborhood,

    max(windows.longest_possible_stay_nights)
        as longest_possible_stay_nights,
    max(windows.window_length_nights) as longest_availability_window,
    max(windows.maximum_nights) as owner_max_nights,
    count(*) as availability_windows

from windows
left join
    {{ ref('dim_listings') }} as listings
    on windows.listing_id = listings.listing_id
group by all
order by longest_possible_stay_nights desc
