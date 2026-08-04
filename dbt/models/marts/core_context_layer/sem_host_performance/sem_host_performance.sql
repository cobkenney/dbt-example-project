-- Host portfolios: who to invest in, and whether professional operators actually
-- outperform. One row per host.
--
-- Answers business questions 18, 19, 20 and 21.
--
-- WHY THIS IS NOT FOLDED INTO sem_listing_performance. Host revenue can be had
-- by aggregating dim_listings grouped by host_id, so a fourth view looks like
-- duplication. It is not, because the two weightings give different numbers and
-- both are legitimate:
--
--   host-weighted    — every host counts once, whatever the portfolio size.
--                      This view. It is what analyses/05 reports: multi-listing
--                      hosts at 19,267 dollars per listing against 39,749 for
--                      single-listing hosts.
--   listing-weighted — every listing counts once, so a 5-listing host pulls the
--                      average five times as hard. That is
--                      sem_listing_performance.
--
-- Aggregating listings to answer a host question silently returns the second
-- when the question wanted the first. Two views, each weighting one way, with
-- comments saying which — rather than one view where the choice is invisible.
--
-- Exposing dim_hosts measures in a view that also holds dim_listings would be
-- the actual bug: 7 of 36 hosts hold more than one listing, so summing host
-- revenue across the listing join double-counts every one of them.
{{ config(materialized='semantic_view') }}

TABLES (
    host AS {{ ref('dim_hosts') }}
        PRIMARY KEY (host_id)
        WITH SYNONYMS = ('hosts', 'owners', 'operators', 'landlords')
        COMMENT = 'One row per host with portfolio size, tenure, verification status, and lifetime performance over the year ending 2022-07-11. 36 hosts holding 49 listings - the 50th, listing 276450, has no listings row and therefore no host, so its revenue is absent from every figure here.'
)

-- No RELATIONSHIPS clause: one logical table, nothing to join. Adding
-- dim_listings would let a host measure be summed across the listing join, which
-- double-counts the 7 multi-listing hosts. Host attributes are already available
-- as dimensions in the other three views for exactly the slicing that would
-- otherwise want that join.

FACTS (
    host.total_revenue AS host.total_revenue
        WITH SYNONYMS = ('revenue', 'earnings', 'income')
        COMMENT = 'Lifetime booked revenue across all of the host listings. Scales with portfolio size by construction - compare hosts on revenue_per_listing instead.',

    host.revenue_per_listing AS host.revenue_per_listing
        WITH SYNONYMS = ('revenue per property', 'earnings per listing')
        COMMENT = 'Revenue divided by listing count. THE comparison that makes hosts of different portfolio sizes comparable, since a 5-listing host out-earns a 1-listing host in total by construction.',

    host.occupancy_rate AS host.occupancy_rate
        WITH SYNONYMS = ('occupancy', 'utilization')
        COMMENT = 'Booked nights divided by calendar nights across the host portfolio. Night-weighted within the host.',

    host.listing_count AS host.listing_count
        WITH SYNONYMS = ('portfolio size', 'properties', 'listings held')
        COMMENT = 'Number of listings the host holds. 29 of 36 hold exactly one; the largest holds 5.',

    host.booked_nights AS host.booked_nights
        COMMENT = 'Nights occupied across the host portfolio.',

    host.calendar_days AS host.calendar_days
        COMMENT = 'Calendar nights across the host portfolio - 365 times the listing count. The occupancy denominator, not a measure of tenure.',

    host.reservations AS host.reservations
        WITH SYNONYMS = ('bookings')
        COMMENT = 'Number of reservations across the host portfolio.',

    host.avg_nights_per_stay AS host.avg_nights_per_stay
        WITH SYNONYMS = ('length of stay', 'average stay')
        COMMENT = 'Mean length of stay across the host reservations, already excluding stays truncated by the snapshot edges. NULL where every reservation of the host is censored, or the host has none.',

    host.avg_list_price AS host.avg_list_price
        COMMENT = 'Mean advertised nightly rate across the host listings.',

    host.host_tenure_years AS host.host_tenure_years
        WITH SYNONYMS = ('tenure', 'experience', 'years hosting')
        COMMENT = 'Whole years between host_since and 2022-07-11, ranging 9 to 14. Question 20 - but host_since clusters in 2008 to 2009, so there is little variance here to explain performance with. Measured against the snapshot end rather than current_date, so it does not drift between runs.',

    host.verification_count AS host.verification_count
        WITH SYNONYMS = ('trust signals', 'verifications')
        COMMENT = 'Distinct verification methods completed, ranging 2 to 9 and clustering at 4 to 6. The floor is 2 because every host has email and phone.',

    host.total_reviews AS host.total_reviews
        COMMENT = 'Summed review count across the host listings.',

    host.avg_review_score AS host.avg_review_score
        WITH SYNONYMS = ('rating', 'review score')
        COMMENT = 'Mean review score across the host listings.'
)

DIMENSIONS (
    host.host_id AS host.host_id
        COMMENT = 'Host identifier, and the only correct way to identify a host. 36 hosts.',

    host.host_name_masked AS host.host_name_masked
        WITH SYNONYMS = ('host name')
        COMMENT = 'Salted hash of the host name, truncated to 16 hex characters. THE PLAINTEXT NAME IS PII AND DOES NOT EXIST IN THESE MODELS - it is masked at the staging boundary, and no query can recover it. Usable as a grouping key but NOT as an identifier: 36 hosts hold 35 distinct names, so two hosts share a name and therefore share a hash. Always identify a host by host_id.',

    host.host_since AS host.host_since
        COMMENT = 'Date the host joined. Clusters in 2008 to 2009 for 49 of 50 listings.',

    host.as_of_date AS host.as_of_date
        COMMENT = 'The snapshot end, 2022-07-11, constant on every row. What tenure is measured against instead of current_date.',

    host.host_location AS host.host_location
        COMMENT = 'Self-reported host location, free text and not normalized. Not comparable to a listing neighborhood - a host can live anywhere relative to the property they rent out.',

    host.is_multi_listing_host AS host.is_multi_listing_host
        WITH SYNONYMS = ('professional host', 'multi property', 'operator type')
        COMMENT = 'True where the host holds more than one listing - 7 hosts holding 20 listings, against 29 single-listing hosts. Question 19: two different business relationships. The finding runs opposite to the intuition - multi-listing hosts earn ROUGHLY HALF the revenue per property at two-thirds the occupancy. Length of stay barely differs, so it is an occupancy gap, not a stay-length one. Note the base is only 7 hosts.',

    host.verification_list AS host.verification_list
        COMMENT = 'Array of the verification methods the host completed. Survives the source adding a method without a schema change, unlike the flags below.',

    -- All 11 flags. The universal ones are kept deliberately — see the comments.
    host.is_verified_email AS host.is_verified_email
        COMMENT = 'True for ALL 36 hosts, so it has no analytical use and cannot correlate with anything. Kept as a tripwire: a flag that is always true is the only thing whose becoming false is visible. Filter on this expecting variance and you get every host back.',

    host.is_verified_phone AS host.is_verified_phone
        COMMENT = 'True for ALL 36 hosts. Same tripwire rationale as is_verified_email, and the same warning - it cannot carry signal.',

    host.is_verified_reviews AS host.is_verified_reviews
        COMMENT = 'True for 34 of 36 hosts.',

    host.is_verified_kba AS host.is_verified_kba
        COMMENT = 'Knowledge-based authentication - 18 of 36 hosts. Note it has the HIGHEST average review score and the LOWEST occupancy of any method, which is a good illustration of why verification badges do not predict performance here.',

    host.is_verified_government_id AS host.is_verified_government_id
        COMMENT = 'Government ID verification - 16 of 36 hosts. DISTINCT from is_verified_offline_government_id, a separate method. All 10 offline hosts also carry this flag, so the two are nested rather than disjoint - do not add them together expecting 26 hosts.',

    host.is_verified_offline_government_id
        AS host.is_verified_offline_government_id
        COMMENT = 'Government ID verified through the offline channel - 10 of 36 hosts, all of whom also carry is_verified_government_id. A subset on this data, though nothing in the source enforces that.',

    host.is_verified_jumio AS host.is_verified_jumio
        COMMENT = 'Jumio identity verification - 10 of 36 hosts.',

    host.is_verified_facebook AS host.is_verified_facebook
        COMMENT = 'Facebook account linked - 10 of 36 hosts. A social link rather than an identity check, yet it shows the second-highest occupancy of any method, which is why this set should be read as adoption and not as trust.',

    host.is_verified_selfie AS host.is_verified_selfie
        COMMENT = 'Selfie verification - 5 of 36 hosts. A stronger identity check than a Facebook link, yet it sits BELOW average occupancy.',

    host.is_verified_identity_manual AS host.is_verified_identity_manual
        COMMENT = 'Manual identity review - 4 of 36 hosts. Looks worst on every measure, which at 4 hosts is noise rather than a signal.',

    host.is_verified_work_email AS host.is_verified_work_email
        COMMENT = 'Work email verified - 4 of 36 hosts. A separate method from is_verified_email, which every host has.',

    host.is_single_listing_host AS host.listing_count = 1
        COMMENT = 'True for the 29 hosts holding exactly one listing. The complement of is_multi_listing_host, exposed because the casual-host segment is usually the one being described.',

    host.has_bookings AS host.reservations > 0
        COMMENT = 'True where the host had at least one reservation in the window.'
)

METRICS (
    host.hosts AS count(*)
        WITH SYNONYMS = ('host count', 'number of hosts')
        COMMENT = 'Number of hosts in the slice. 36 in total. Safe to compare against a listing count only if you remember 36 hosts hold 49 listings.',

    host.listings AS sum(host.listing_count)
        WITH SYNONYMS = ('properties', 'portfolio size')
        COMMENT = 'Total listings held by the hosts in the slice. Sums to 49, NOT 50 - the orphan listing 276450 has no host row.',

    host.portfolio_revenue AS sum(host.total_revenue)
        WITH SYNONYMS = ('total revenue', 'revenue')
        COMMENT = 'Summed host revenue. Safe at this grain, one row per host. Does NOT reconcile with the revenue totals in the other three views, because the orphan listing revenue has no host to attribute it to.',

    -- The metric analyses/05 turns on, and the reason for host-weighting.
    host.avg_revenue_per_listing AS avg(host.revenue_per_listing)
        WITH SYNONYMS = ('revenue per property', 'earnings per listing')
        COMMENT = 'Mean of the per-host revenue per listing. HOST-weighted: every host counts once regardless of portfolio size. This is the right comparison for question 18 and 19 - 19,267 dollars for multi-listing hosts against 39,749 for single-listing ones. For a listing-weighted figure use avg_revenue_per_listing in SEM_LISTING_PERFORMANCE, which answers a different question and gives a different number.',

    host.avg_revenue_per_host AS avg(host.total_revenue)
        COMMENT = 'Mean total revenue per host. Scales with portfolio size, so prefer avg_revenue_per_listing when comparing host segments.',

    host.median_revenue_per_listing AS median(host.revenue_per_listing)
        COMMENT = 'Median of the per-host revenue per listing. Less sensitive than the mean to a single outlier host, which matters at 7 hosts in the multi-listing segment.',

    host.avg_occupancy_rate AS avg(host.occupancy_rate)
        WITH SYNONYMS = ('occupancy', 'average occupancy')
        COMMENT = 'Mean of the per-host occupancy rate. Host-weighted. 38.5 percent for multi-listing hosts against 60.0 percent for single-listing ones - the gap that drives the revenue difference in question 19.',

    host.occupancy_rate_weighted
        AS div0(sum(host.booked_nights), sum(host.calendar_days))
        COMMENT = 'Total booked nights divided by total calendar nights across the hosts in the slice. Night-weighted, so a large portfolio counts for more. Use this for a portfolio total and avg_occupancy_rate for comparing segments.',

    host.avg_listings_per_host AS avg(host.listing_count)
        COMMENT = 'Mean portfolio size. 1.36 across all 36 hosts.',

    host.max_listings_per_host AS max(host.listing_count)
        COMMENT = 'Largest portfolio in the slice. 5 overall.',

    host.total_reservations AS sum(host.reservations)
        WITH SYNONYMS = ('bookings')
        COMMENT = 'Total reservations across the hosts in the slice. Slightly below the 1,565 in SEM_RESERVATIONS, since the orphan listing bookings have no host.',

    host.avg_length_of_stay AS avg(host.avg_nights_per_stay)
        COMMENT = 'Mean of the per-host average stay length, already excluding censored stays. 6.25 nights for multi-listing hosts against 6.11 for single-listing ones - barely different, which is what shows question 19 to be an occupancy story rather than a stay-length one.',

    host.avg_tenure_years AS avg(host.host_tenure_years)
        WITH SYNONYMS = ('average tenure', 'average experience')
        COMMENT = 'Mean host tenure in years, anchored to 2022-07-11. Question 20 - with host_since clustered in 2008 to 2009 there is little variance to correlate against.',

    host.avg_verification_count AS avg(host.verification_count)
        WITH SYNONYMS = ('average verifications')
        COMMENT = 'Mean number of verification methods completed. Question 21 - read the view COMMENT before putting an occupancy claim on it.',

    -- Named portfolio_* rather than reusing the fact names: facts and metrics
    -- share one namespace here, and Snowflake rejects a metric whose name
    -- collides with a fact.
    host.portfolio_avg_review_score AS avg(host.avg_review_score)
        WITH SYNONYMS = ('average rating')
        COMMENT = 'Mean of the per-host average review score.',

    host.portfolio_total_reviews AS sum(host.total_reviews)
        COMMENT = 'Summed review count across the hosts in the slice.',

    host.portfolio_avg_list_price AS avg(host.avg_list_price)
        COMMENT = 'Mean of the per-host average advertised rate.',

    host.multi_listing_hosts AS count_if(host.listing_count > 1)
        COMMENT = 'How many hosts in the slice hold more than one listing. 7 overall.'
)

COMMENT = 'Rental host portfolios over the year ending 2022-07-11: portfolio size, tenure, verification status, and performance at one row per host. 36 hosts holding 49 listings. Use this for which hosts to invest in, professional operators against casual ones, and whether tenure or verification tracks performance. Figures here are HOST-WEIGHTED - every host counts once whatever the portfolio size. For listing-weighted equivalents use SEM_LISTING_PERFORMANCE. IMPORTANT on trust signals, question 21: there is no finding here. Email and phone are held by all 36 hosts, so their figures are just the overall average and cannot correlate with anything. The remaining spread is non-monotonic on tiny bases, and direction disagrees between measures - knowledge-based authentication has the highest review score and the lowest occupancy. With 36 hosts against 11 methods there are more cells than hosts. Read verification as ADOPTION and do not put an occupancy claim on a verification badge. Host tenure, question 20, has the same problem from the other side: host_since clusters in 2008 to 2009, so there is almost no variance to explain performance with. A HOST REAL NAME CANNOT BE RETRIEVED - it is PII, masked before it reaches any of these models.'

AI_SQL_GENERATION 'Compare hosts on avg_revenue_per_listing, never on portfolio_revenue or avg_revenue_per_host, both of which scale with portfolio size by construction. Figures here are host-weighted; if the question is really about listings, use SEM_LISTING_PERFORMANCE instead. Revenue here will not match the other views, because the orphan listing 276450 has no host and its revenue is therefore absent - say so rather than presenting a reconciled total. Never attempt to return a host real name: only a salted hash exists, two hosts share it, and it is not an identifier - use host_id. Tenure is anchored to as_of_date of 2022-07-11, so never use current_date. When asked whether verification predicts performance, report adoption counts and state plainly that the data does not support a causal or even a reliable correlational claim - and never build one on is_verified_email or is_verified_phone, which are true for every host.'

{#
    Verified queries, in macros/verified_queries/, one macro per question.

    Two shapes rather than one. Questions 18 and 19 group on dimensions and are
    plain SEMANTIC_VIEW(...) queries. Question 20 groups by tenure, which is a
    FACT - and Snowflake rejects FACTS and METRICS in one clause, so that one is
    CTE-wrapped at host grain. Reasoning is in the macro.

    NO ENTRY FOR QUESTION 21, deliberately. Comparing the 11 verification methods
    needs one union branch per method, because each is its own boolean dimension
    with no single column to group on. Generating that from
    get_verification_methods() also drags a stg_listings ref into this view,
    which is the wrong dependency for a context layer built over core_mart. The
    question has no finding to pin anyway - the view COMMENT and
    AI_SQL_GENERATION already say to report verification as adoption and refuse
    an occupancy claim, which is the guidance a client needs here.

    Not yet validated. Snowflake accepts a verified query without checking that
    it runs, so these build green either way - the validator in TODO item 14 is
    what will make "verified" mean anything here.
#}
{{ ai_verified_queries(['q18', 'q19', 'q20']) }}
