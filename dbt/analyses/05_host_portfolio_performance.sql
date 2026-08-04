-- Professional multi-listing operators vs casual single-listing hosts.
--
-- Two different business relationships with different economics, which is the
-- reason is_multi_listing_host exists as a column rather than being derived in
-- each query. 7 of 36 hosts hold more than one listing.
--
-- revenue_per_listing, not total_revenue, is the comparison that matters — a
-- 5-listing host out-earns a 1-listing host in total by construction, so the
-- interesting question is whether they earn more PER property.
--
-- Verified, and the answer is counterintuitive: they earn LESS.
--   multi-listing  (7 hosts, 20 listings)  $19,267 per listing, 38.5% occupancy
--   single-listing (29 hosts, 29 listings) $39,749 per listing, 60.0% occupancy
-- Roughly half the revenue per property at two-thirds the occupancy. Length of
-- stay barely differs (6.25 vs 6.11 nights), so this is an occupancy gap rather
-- than a stay-length one. Worth investigating before treating multi-listing
-- hosts as the more valuable segment — but note 7 hosts is a small base.
--
-- host_name is PII and does not exist in plaintext in this project;
-- host_name_masked is a salted hash and host_id is the join key.
select
    is_multi_listing_host,

    count(*) as hosts,
    sum(listing_count) as listings,

    round(sum(total_revenue), 2) as total_revenue,
    round(avg(revenue_per_listing), 2) as avg_revenue_per_listing,

    round(avg(occupancy_rate), 3) as avg_occupancy_rate,
    round(avg(avg_nights_per_stay), 2) as avg_length_of_stay,
    round(avg(avg_list_price), 2) as avg_list_price,

    round(avg(avg_review_score), 2) as avg_review_score,
    round(avg(host_tenure_years), 1) as avg_tenure_years
from {{ ref('dim_hosts') }}
group by all
order by is_multi_listing_host desc
