-- Question 22 — price normalized by bedrooms and beds.
--
-- The comparison total price cannot make: a 4-bedroom unit at $400 and a
-- 1-bedroom at $150 are not ranked by price alone. Uses the calendar's nightly
-- price rather than the listing's advertised rate, which is why these columns
-- belong on the daily fact.
--
-- Verified:
--   entire home/apt (31)  $216.84 nightly  $165.68/bedroom  $128.10/bed
--   private room    (18)  $ 89.11 nightly  $ 85.74/bedroom  $ 84.15/bed
--
-- Normalizing compresses the gap sharply. On raw price an entire home looks
-- 2.4x a private room; per bedroom that falls to 1.9x and per bed to 1.5x. Most
-- of the headline premium is buying more space, not a higher rate for it —
-- which is the whole reason to normalize before comparing.
--
-- Both denominators are guarded, for different reasons, and both gaps fall
-- entirely on entire homes — private rooms have complete data:
--   bedrooms — 8 of 31 entire homes leave it NULL, so they drop out of that
--              average. That figure covers 23 listings, not 31.
--   beds     — 4 of 31 record 0, so nullif is required or the division errors.
-- One listing records 1 bedroom and 0 beds, so neither column is a clean
-- fallback for the other. Treat the entire-home figures as the noisier pair.
select
    room_type,

    count(distinct listing_id) as listings,
    round(avg(price), 2) as avg_nightly_price,

    round(avg(price / bedrooms), 2) as avg_price_per_bedroom,
    round(avg(price / nullif(beds, 0)), 2) as avg_price_per_bed,

    -- How much of each average is actually backed by data.
    count(distinct case when bedrooms is null then listing_id end)
        as listings_missing_bedrooms,
    count(distinct case when beds = 0 then listing_id end)
        as listings_zero_beds
from {{ ref('fct_listing_daily') }}
where not is_orphan_listing
group by all
order by avg_price_per_bedroom desc
