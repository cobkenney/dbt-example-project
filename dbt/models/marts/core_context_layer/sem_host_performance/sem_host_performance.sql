{{ config(materialized='semantic_view') }}

TABLES (
    host AS {{ ref('dim_hosts') }}
        PRIMARY KEY (host_id)
        WITH SYNONYMS = ('hosts', 'owners', 'operators', 'landlords')
        COMMENT = 'One row per host with portfolio size, tenure, verification status, and lifetime performance over the fixed one-year snapshot. Covers only listings that have a listings row - deleted listings have no host, so their revenue is absent from every figure here.'
)

-- No RELATIONSHIPS clause: one logical table, nothing to join. Adding
-- dim_listings would let a host measure be summed across the listing join, which
-- double-counts every multi-listing host. Host attributes are already available
-- as dimensions in the other three views for exactly the slicing that would
-- otherwise want that join.

FACTS (
    host.total_revenue AS host.total_revenue
        WITH SYNONYMS = ('revenue', 'earnings', 'income')
        COMMENT = 'Lifetime booked revenue across all of the host listings. Scales with portfolio size by construction - compare hosts on revenue_per_listing instead.',

    host.revenue_per_listing AS host.revenue_per_listing
        WITH SYNONYMS = ('revenue per property', 'earnings per listing')
        COMMENT = 'Revenue divided by listing count. THE comparison that makes hosts of different portfolio sizes comparable, since a larger portfolio out-earns a smaller one in total by construction.',

    host.occupancy_rate AS host.occupancy_rate
        WITH SYNONYMS = ('occupancy', 'utilization')
        COMMENT = 'Booked nights divided by calendar nights across the host portfolio. Night-weighted within the host.',

    host.listing_count AS host.listing_count
        WITH SYNONYMS = ('portfolio size', 'properties', 'listings held')
        COMMENT = 'Number of listings the host holds. Most hosts hold exactly one, with a thin tail above that.',

    host.booked_nights AS host.booked_nights
        COMMENT = 'Nights occupied across the host portfolio.',

    host.calendar_days AS host.calendar_days
        COMMENT = 'Calendar nights across the host portfolio - the snapshot length times the listing count. The occupancy denominator, not a measure of tenure.',

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
        COMMENT = 'Whole years between host_since and the snapshot end. Question 20 - but host_since is tightly clustered, so there is little variance here to explain performance with. Measured against the snapshot end rather than current_date, so it does not drift between runs.',

    host.verification_count AS host.verification_count
        WITH SYNONYMS = ('trust signals', 'verifications')
        COMMENT = 'Distinct verification methods completed. The floor comes from every host holding the same baseline methods rather than from a designed minimum.',

    host.total_reviews AS host.total_reviews
        COMMENT = 'Summed review count across the host listings.',

    host.avg_review_score AS host.avg_review_score
        WITH SYNONYMS = ('rating', 'review score')
        COMMENT = 'Mean review score across the host listings.'
)

DIMENSIONS (
    host.host_id AS host.host_id
        COMMENT = 'Host identifier, and the only correct way to identify a host.',

    host.host_name_masked AS host.host_name_masked
        WITH SYNONYMS = ('host name')
        COMMENT = 'Salted hash of the host name. THE PLAINTEXT NAME IS PII AND DOES NOT EXIST IN THESE MODELS - it is masked at the staging boundary, and no query can recover it. Usable as a grouping key but NOT as an identifier: host names are not unique, so distinct hosts can share a name and therefore share a hash. Always identify a host by host_id.',

    host.host_since AS host.host_since
        COMMENT = 'Date the host joined. Tightly clustered - nearly every host joined within the same short window.',

    host.as_of_date AS host.as_of_date
        COMMENT = 'The snapshot end, constant on every row. What tenure is measured against instead of current_date.',

    host.host_location AS host.host_location
        COMMENT = 'Self-reported host location, free text and not normalized. Not comparable to a listing neighborhood - a host can live anywhere relative to the property they rent out.',

    host.is_multi_listing_host AS host.is_multi_listing_host
        WITH SYNONYMS = ('professional host', 'multi property', 'operator type')
        COMMENT = 'True where the host holds more than one listing. Question 19: two different business relationships. The finding runs opposite to the intuition - multi-listing hosts earn substantially LESS revenue per property at lower occupancy. Length of stay barely differs, so it is an occupancy gap, not a stay-length one. NOTE THE BASE IS SMALL - only a handful of hosts are multi-listing, so treat the comparison as indicative rather than established.',

    host.verification_list AS host.verification_list
        COMMENT = 'Array of the verification methods the host completed. Survives the source adding a method without a schema change, unlike the flags below.',

    -- Every flag. The universal ones are kept deliberately — see the comments.
    host.is_verified_email AS host.is_verified_email
        COMMENT = 'True for EVERY host, so it has no analytical use and cannot correlate with anything. Kept as a tripwire: a flag that is always true is the only thing whose becoming false is visible. Filter on this expecting variance and you get every host back.',

    host.is_verified_phone AS host.is_verified_phone
        COMMENT = 'True for EVERY host. Same tripwire rationale as is_verified_email, and the same warning - it cannot carry signal.',

    host.is_verified_reviews AS host.is_verified_reviews
        COMMENT = 'Verified by platform reviews. Held by nearly every host, so it discriminates poorly.',

    host.is_verified_kba AS host.is_verified_kba
        COMMENT = 'Knowledge-based authentication. Note it has the HIGHEST average review score and the LOWEST occupancy of any method, which is a good illustration of why verification badges do not predict performance here.',

    host.is_verified_government_id AS host.is_verified_government_id
        COMMENT = 'Government ID verification. DISTINCT from is_verified_offline_government_id, a separate method. Every offline host also carries this flag, so the two are NESTED rather than disjoint - do not add them together expecting a combined total.',

    host.is_verified_offline_government_id
        AS host.is_verified_offline_government_id
        COMMENT = 'Government ID verified through the offline channel. Every host carrying this also carries is_verified_government_id, so it is a subset of that flag on this data, though nothing in the source enforces that.',

    host.is_verified_jumio AS host.is_verified_jumio
        COMMENT = 'Jumio identity verification.',

    host.is_verified_facebook AS host.is_verified_facebook
        COMMENT = 'Facebook account linked. A social link rather than an identity check, yet it shows one of the highest occupancies of any method, which is why this set should be read as adoption and not as trust.',

    host.is_verified_selfie AS host.is_verified_selfie
        COMMENT = 'Selfie verification. A stronger identity check than a Facebook link, yet it sits BELOW average occupancy.',

    host.is_verified_identity_manual AS host.is_verified_identity_manual
        COMMENT = 'Manual identity review. Looks worst on every measure, but it is held by so few hosts that this is noise rather than a signal.',

    host.is_verified_work_email AS host.is_verified_work_email
        COMMENT = 'Work email verified. A separate method from is_verified_email, which every host has.',

    host.is_single_listing_host AS host.listing_count = 1
        COMMENT = 'True for hosts holding exactly one listing, which is most of them. The complement of is_multi_listing_host, exposed because the casual-host segment is usually the one being described.',

    host.has_bookings AS host.reservations > 0
        COMMENT = 'True where the host had at least one reservation in the window.'
)

METRICS (
    host.hosts AS count(*)
        WITH SYNONYMS = ('host count', 'number of hosts')
        COMMENT = 'Number of hosts in the slice. Do NOT compare directly against a listing count - hosts hold more listings than there are hosts, and deleted listings have no host at all.',

    host.listings AS sum(host.listing_count)
        WITH SYNONYMS = ('properties', 'portfolio size')
        COMMENT = 'Total listings held by the hosts in the slice. This is FEWER than the total listing count in the other views - deleted listings have no host row, so they are absent here.',

    host.portfolio_revenue AS sum(host.total_revenue)
        WITH SYNONYMS = ('total revenue', 'revenue')
        COMMENT = 'Summed host revenue. Safe at this grain, one row per host. Does NOT reconcile with the revenue totals in the other three views, because the deleted listing revenue has no host to attribute it to.',

    -- The metric the multi-listing finding turns on, and the reason for
    -- host-weighting.
    host.avg_revenue_per_listing AS avg(host.revenue_per_listing)
        WITH SYNONYMS = ('revenue per property', 'earnings per listing')
        COMMENT = 'Mean of the per-host revenue per listing. HOST-weighted: every host counts once regardless of portfolio size. This is the right comparison for question 18 and 19, where multi-listing hosts come out well below single-listing ones. For a listing-weighted figure use avg_revenue_per_listing in SEM_LISTING_PERFORMANCE, which answers a different question and gives a different number.',

    host.avg_revenue_per_host AS avg(host.total_revenue)
        COMMENT = 'Mean total revenue per host. Scales with portfolio size, so prefer avg_revenue_per_listing when comparing host segments.',

    host.median_revenue_per_listing AS median(host.revenue_per_listing)
        COMMENT = 'Median of the per-host revenue per listing. Less sensitive than the mean to a single outlier host, which matters because the multi-listing segment is a small base.',

    host.avg_occupancy_rate AS avg(host.occupancy_rate)
        WITH SYNONYMS = ('occupancy', 'average occupancy')
        COMMENT = 'Mean of the per-host occupancy rate. Host-weighted. Materially lower for multi-listing hosts than for single-listing ones - the gap that drives the revenue difference in question 19.',

    host.occupancy_rate_weighted
        AS div0(sum(host.booked_nights), sum(host.calendar_days))
        COMMENT = 'Total booked nights divided by total calendar nights across the hosts in the slice. Night-weighted, so a large portfolio counts for more. Use this for a portfolio total and avg_occupancy_rate for comparing segments.',

    host.avg_listings_per_host AS avg(host.listing_count)
        COMMENT = 'Mean portfolio size. Close to one, since most hosts hold a single listing.',

    host.max_listings_per_host AS max(host.listing_count)
        COMMENT = 'Largest portfolio in the slice.',

    host.total_reservations AS sum(host.reservations)
        WITH SYNONYMS = ('bookings')
        COMMENT = 'Total reservations across the hosts in the slice. Slightly BELOW the total in SEM_RESERVATIONS, since bookings on deleted listings have no host.',

    host.avg_length_of_stay AS avg(host.avg_nights_per_stay)
        COMMENT = 'Mean of the per-host average stay length, already excluding censored stays. Barely differs between multi- and single-listing hosts, which is what shows question 19 to be an occupancy story rather than a stay-length one.',

    host.avg_tenure_years AS avg(host.host_tenure_years)
        WITH SYNONYMS = ('average tenure', 'average experience')
        COMMENT = 'Mean host tenure in years, anchored to the snapshot end. Question 20 - with host_since tightly clustered there is little variance to correlate against.',

    host.avg_verification_count AS avg(host.verification_count)
        WITH SYNONYMS = ('average verifications')
        COMMENT = 'Mean number of verification methods completed. Read the view COMMENT before putting an occupancy claim on it.',

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
        COMMENT = 'How many hosts in the slice hold more than one listing. A small minority overall, so segment comparisons on it rest on a thin base.'
)

COMMENT = 'Rental host portfolios over a fixed one-year snapshot: portfolio size, tenure, verification status, and performance at one row per host. Covers only listings that have a listings row, so it holds fewer listings than the other views. Use this for which hosts to invest in, professional operators against casual ones, and whether tenure or verification tracks performance. Figures here are HOST-WEIGHTED - every host counts once whatever the portfolio size. For listing-weighted equivalents use SEM_LISTING_PERFORMANCE. IMPORTANT on trust signals: there is no finding here. Email and phone are held by every host, so their figures are just the overall average and cannot correlate with anything. The remaining spread is non-monotonic on tiny bases, and direction disagrees between measures - knowledge-based authentication has the highest review score and the lowest occupancy. There are more verification-method cells than there are hosts, so per-method figures rest on very few rows each. Read verification as ADOPTION and do not put an occupancy claim on a verification badge. Host tenure, question 20, has the same problem from the other side: host_since is tightly clustered, so there is almost no variance to explain performance with. A HOST REAL NAME CANNOT BE RETRIEVED - it is PII, masked before it reaches any of these models.'

AI_SQL_GENERATION 'Compare hosts on avg_revenue_per_listing, never on portfolio_revenue or avg_revenue_per_host, both of which scale with portfolio size by construction. Figures here are host-weighted; if the question is really about listings, use SEM_LISTING_PERFORMANCE instead. Revenue here will NOT match the other views, because deleted listings have no host and their revenue is therefore absent - say so rather than presenting a reconciled total. Never attempt to return a host real name: only a salted hash exists, more than one host can share it, and it is not an identifier - use host_id. Tenure is anchored to the as_of_date column, so never use current_date. When asked whether verification predicts performance, report adoption counts and state plainly that the data does not support a causal or even a reliable correlational claim - and never build one on is_verified_email or is_verified_phone, which are true for every host.'

{{ ai_verified_queries(['q18', 'q19', 'q20']) }}
