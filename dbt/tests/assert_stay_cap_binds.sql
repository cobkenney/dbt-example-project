-- Guards the premise behind the clamp in analyses/03_long_stay_picky_renter.
--
-- That query answers "longest bookable stay" with
-- least(window_length_nights, maximum_nights), and the reason it clamps is that
-- BOTH constraints bind in this data — the owner's cap in 8 of 204 availability
-- windows, the window itself in the rest. Drop the clamp and listing 743211
-- reports a 206-night stay against a 90-night cap.
--
-- fct_listing_availability_windows used to hold that rule as a tested column.
-- It was collapsed into the analysis, so this test is what remains: it fails if
-- the cap stops binding anywhere, which is the signal that the clamp has become
-- dead code and the query can be simplified — or, read the other way, that
-- maximum_nights has stopped arriving and something upstream broke.
--
-- Deliberately NOT a test that the clamp is applied. Nothing can enforce that
-- from here, which is the honest cost of collapsing the model; the analysis
-- header carries the warning instead.
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
