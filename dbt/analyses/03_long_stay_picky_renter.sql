-- Business problem #3 — Long Stay / Picky Renter
--
-- Longest possible stay for listings offering both a lockbox and a first aid
-- kit, respecting both the availability window and the owner's maximum_nights.
--
-- Verified: listing 1303261 -> 159 nights.
--
-- Both constraints genuinely bind, which is why longest_possible_stay_nights
-- is least(window_length_nights, maximum_nights) rather than either column:
--   listing 1303261 — 159-night window under a 180-night cap -> window binds
--   listing  743211 — 206-night window capped to  90 nights  -> cap binds
-- The cap binds in 8 of 204 windows. Neither of the two listings returned below
-- is cap-bound, so the clamp is invisible in this result set but not optional.
select
    listing_id,
    listing_name,
    neighborhood,
    max(longest_possible_stay_nights) as longest_possible_stay_nights,
    max(window_length_nights) as longest_availability_window,
    max(maximum_nights) as owner_max_nights,
    count(*) as availability_windows
from {{ ref('fct_listing_availability_windows') }}
where
    has_lockbox
    and has_first_aid_kit
group by all
order by longest_possible_stay_nights desc
