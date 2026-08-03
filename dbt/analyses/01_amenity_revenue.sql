-- Business problem #1 — Amenity Revenue
--
-- Total revenue and percentage of revenue by month, segmented by whether the
-- listing has air conditioning.
--
-- Verified: July 2022 shows 21.2% of revenue from listings without AC.
--
-- Note this deliberately does NOT filter is_orphan_listing. Listing 276450
-- contributes $2,200 of booked July 2022 revenue and does have air
-- conditioning, so dropping it strips revenue from the AC segment and pushes
-- the no-AC share up to 22.1%.
select
    month_start_date,
    has_air_conditioning,
    sum(revenue) as total_revenue,
    round(100 * ratio_to_report(sum(revenue)) over (
        partition by month_start_date
    ), 1) as pct_of_month_revenue
from {{ ref('fct_listing_daily') }}
group by all
order by month_start_date, has_air_conditioning
