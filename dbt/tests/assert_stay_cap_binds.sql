-- Guards the premise behind the clamp in the longest-bookable-stay question.
--
-- That question is answered with least(window_length_nights, maximum_nights),
-- and the reason it clamps is that BOTH constraints bind in this data — the
-- owner's cap on a minority of availability windows, the window itself on the
-- rest. Drop the clamp and a listing reports a stay several times longer than
-- its own owner cap allows.
--
-- fct_listing_availability_windows used to hold that rule as a tested column.
-- It was collapsed, so this test is what remains: it fails if the cap stops
-- binding anywhere, which is the signal that the clamp has become dead code and
-- the query can be simplified — or, read the other way, that maximum_nights has
-- stopped arriving and something upstream broke.
--
-- Deliberately NOT a test that the clamp is applied. Nothing can enforce that
-- from here, which is the honest cost of collapsing the model; the header of
-- macros/verified_queries/verified_queries_q03.sql carries the warning instead.
-- Groups on availability_window_seq from fct_listing_daily rather than deriving
-- the gap-and-island here. is_available is filtered before grouping, which that
-- column requires: it is a running count of windows started, so a booked night
-- carries the number of the window that closed before it.
with windows as (

    select
        listing_id,
        availability_window_seq,
        count(*) as window_length_nights,
        max(maximum_nights) as maximum_nights
    from {{ ref('fct_listing_daily') }}
    where is_available
    group by all

)

-- One row back means the cap never binds. No rows means it does, somewhere.
select count(*) as cap_bound_windows
from windows
where maximum_nights < window_length_nights
having count(*) = 0
