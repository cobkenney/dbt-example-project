-- Business problem #2 — Neighborhood Pricing
--
-- Average price increase per neighborhood between the first and last day of
-- the calendar window (2021-07-12 to 2022-07-11).
--
-- Verified: Back Bay has a single listing (10813), whose $106 -> $150 move
-- gives a $44.00 neighborhood average.
--
-- The per-listing CTE matters: averaging the price change per listing, then
-- averaging across listings, is not the same as differencing neighborhood
-- averages when listings enter or leave the window.
with listing_price_change as (

    select
        listing_id,
        neighborhood,
        max(case
            when calendar_date = '2021-07-12' then price
        end) as start_price,
        max(case
            when calendar_date = '2022-07-11' then price
        end) as end_price
    from {{ ref('fct_listing_daily') }}
    where neighborhood is not null
    group by all

)

select
    neighborhood,
    count(*) as listings,
    round(avg(end_price - start_price), 2) as avg_price_increase,
    round(avg(start_price), 2) as avg_start_price,
    round(avg(end_price), 2) as avg_end_price
from listing_price_change
group by all
order by avg_price_increase desc
