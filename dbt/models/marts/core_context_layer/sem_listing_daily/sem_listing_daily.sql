{{ config(materialized='semantic_view') }}

TABLES (
    daily AS {{ ref('fct_listing_daily') }}
        PRIMARY KEY (calendar_id)
        WITH SYNONYMS = ('calendar', 'nightly', 'daily rates')
        COMMENT = 'One row per listing per date across a fixed one-year snapshot. Not a rolling window, so never measure recency against current_date - anchor to the max calendar_date instead.',

    listing AS {{ ref('dim_listings') }}
        PRIMARY KEY (listing_id)
        WITH SYNONYMS = ('listings', 'properties', 'units')
        COMMENT = 'Listing attributes. Joined for description only in this view - its lifetime measures live in sem_listing_performance.',

    host AS {{ ref('dim_hosts') }}
        PRIMARY KEY (host_id)
        WITH SYNONYMS = ('hosts', 'owners', 'operators')
        COMMENT = 'Host attributes. Joined for segmentation only in this view - host measures live in sem_host_performance.'
)

RELATIONSHIPS (
    -- Complete: dim_listings covers every listing the calendar references,
    -- including the orphans.
    daily_to_listing AS daily (listing_id) REFERENCES listing (listing_id),

    -- NOT complete. An orphan listing has a NULL host_id, so grouping a daily
    -- metric by any host attribute drops its rows and the revenue on them.
    -- Group by listing attributes when a total has to reconcile.
    listing_to_host AS listing (host_id) REFERENCES host (host_id)
)

FACTS (
    daily.price AS daily.price
        COMMENT = 'Nightly rate offered for this date, booked or not. This is the rate on the calendar, not the advertised list price.',

    daily.revenue AS daily.revenue
        COMMENT = 'Nightly price on booked nights, NULL on available nights. NULL rather than zero is deliberate, so SUM gives booked revenue with no date filter and AVG gives the rate actually achieved rather than being dragged down by vacant nights.',

    daily.minimum_nights AS daily.minimum_nights
        COMMENT = 'Shortest stay the host will accept on this date.',

    daily.maximum_nights AS daily.maximum_nights
        COMMENT = 'Longest stay the host will accept on this date. Caps how much of an availability window can be sold as one stay.',

    -- Question 21. Both denominators are guarded and they fail in opposite
    -- ways, which is why neither is a fallback for the other.
    daily.price_per_bedroom AS daily.price / nullif(daily.bedrooms, 0)
        COMMENT = 'Nightly price divided by bedrooms. bedrooms goes NULL on some listings, all of them entire homes, so those rows drop out rather than counting as zero.',

    daily.price_per_bed AS daily.price / nullif(daily.beds, 0)
        COMMENT = 'Nightly price divided by beds. beds goes to 0 rather than NULL on some listings, so nullif is required or the division errors. A listing can record a bedroom and no beds, so bedrooms and beds are NOT interchangeable.',

    daily.price_per_guest AS daily.price / nullif(daily.accommodates, 0)
        COMMENT = 'Nightly price divided by guest capacity. Normalizes a studio against a 6-sleeper.'
)

DIMENSIONS (
    daily.listing_id AS daily.listing_id
        COMMENT = 'Listing identifier. Group by this for anything measured per listing over time.',

    listing.listing_name AS listing.listing_name
        WITH SYNONYMS = ('name', 'title')
        COMMENT = 'Listing title, from the listing dimension rather than the fact - a name repeated on every daily row of a listing is the redundancy the star schema exists to avoid. NULL for an orphan listing.',

    daily.calendar_date AS daily.calendar_date
        WITH SYNONYMS = ('date', 'night', 'day')
        COMMENT = 'The date this row describes. Spans a fixed one-year window - take its bounds from min and max of this column rather than assuming them.',

    daily.month_start_date AS daily.month_start_date
        WITH SYNONYMS = ('month', 'monthly')
        COMMENT = 'First day of the calendar month, precomputed. Use this for revenue by month rather than truncating calendar_date.',

    daily.day_of_week AS dayname(daily.calendar_date)
        WITH SYNONYMS = ('weekday', 'day name')
        COMMENT = 'Three-letter day name. For question 10, weekend premium and midweek gaps.',

    daily.is_weekend AS dayofweek(daily.calendar_date) in (0, 6)
        COMMENT = 'True on Saturday and Sunday, using Snowflake dayofweek where 0 is Sunday.',

    daily.is_available AS daily.is_available
        WITH SYNONYMS = ('vacant', 'open', 'bookable')
        COMMENT = 'True when bookable on this date, false when occupied. Revenue accrues only on occupied nights. CAVEAT: false covers both booked and host-blocked - the source does not distinguish them, so occupancy treats every unavailable night as booked.',

    daily.reservation_id AS daily.reservation_id
        COMMENT = 'Booking occupying this date, NULL when available. NOT unique on its own - the same id can cover two separate stays on different listings. Count reservations in sem_reservations, not here.',

    daily.availability_window_seq AS daily.availability_window_seq
        WITH SYNONYMS = ('availability window', 'availability run', 'vacancy run')
        COMMENT = 'Which contiguous run of available nights this date belongs to, numbered per listing. Group by listing_id and this to get one row per availability window. MEANINGFUL ONLY WHERE is_available IS TRUE - always filter is_available before grouping on it. It is a running count of runs started, so a booked night carries the number of the run that closed before it, and a group that omits the filter collects those booked nights and reports a longer window than exists. Window length is the count of nights in the group, NEVER a date difference: every available date is itself a bookable night, so a datediff between the first and last date of a run undercounts it by one.',

    daily.is_orphan_listing AS daily.is_orphan_listing
        COMMENT = 'True for a listing the calendar references that has no listings row, so its descriptive columns are all NULL. Filter it out when comparing attributes. LEAVE IT IN when totalling revenue - orphans carry real booked revenue, and dropping them shifts every revenue share, including the answer to question 1.',

    listing.neighborhood AS listing.neighborhood
        WITH SYNONYMS = ('area', 'district', 'location')
        COMMENT = 'Listing neighborhood. NULL for an orphan listing.',

    listing.property_type AS listing.property_type
        COMMENT = 'Apartment, house, condominium and similar.',

    listing.room_type AS listing.room_type
        WITH SYNONYMS = ('accommodation type')
        COMMENT = 'Entire home/apt, private room, or shared room. Entire homes and private rooms make up nearly all of the portfolio.',

    listing.accommodates AS listing.accommodates
        WITH SYNONYMS = ('capacity', 'sleeps', 'guests')
        COMMENT = 'Guest capacity.',

    listing.bedrooms AS listing.bedrooms
        COMMENT = 'Bedroom count. Goes NULL on a minority of listings, all of them entire homes.',

    listing.beds AS listing.beds
        COMMENT = 'Bed count. Goes to zero rather than NULL on a few listings, all of them entire homes.',

    listing.is_shared_bathroom AS listing.is_shared_bathroom
        COMMENT = 'True where the raw bathroom label mentions shared, which is a minority of listings. Not reflected in the bathroom count, so this is the only signal for it.',

    listing.list_price AS listing.list_price
        COMMENT = 'Advertised nightly rate from the listings table. Compare against the achieved rate metrics to size discounting - a listing far under its ask is mispriced.',

    listing.review_scores_rating AS listing.review_scores_rating
        WITH SYNONYMS = ('review score', 'rating')
        COMMENT = 'Average review score. NULL for listings with no reviews.',

    daily.has_air_conditioning AS daily.has_air_conditioning
        WITH SYNONYMS = ('ac', 'air con')
        COMMENT = 'True where the listing offers air conditioning. For question 1, the share of revenue from listings without it.',

    daily.has_lockbox AS daily.has_lockbox
        COMMENT = 'True where the listing offers a lockbox. For question 3, with the first aid kit flag.',

    daily.has_first_aid_kit AS daily.has_first_aid_kit
        COMMENT = 'True where the listing offers a first aid kit.',

    daily.amenity_count AS daily.amenity_count
        COMMENT = 'Number of amenities on the listing.',

    host.host_tenure_years AS host.host_tenure_years
        COMMENT = 'Whole years between the host joining and the snapshot end. Little variance to work with - host_since is tightly clustered, so it explains very little.',

    host.is_multi_listing_host AS host.is_multi_listing_host
        COMMENT = 'True where the host holds more than one listing, which is a small minority of hosts - treat segment comparisons on it as indicative. Reaching this from the daily grain drops the orphan listings, which have no host.'
)

METRICS (
    daily.total_revenue AS sum(daily.revenue)
        WITH SYNONYMS = ('revenue', 'earnings', 'income')
        COMMENT = 'Booked revenue. Sums only occupied nights, since revenue is NULL on available ones.',

    daily.calendar_nights AS count(*)
        COMMENT = 'Nights in the window. Identical for every listing, since the snapshot is a fixed year - so it is the occupancy denominator rather than a measure of listing age.',

    daily.booked_nights AS count_if(not daily.is_available)
        WITH SYNONYMS = ('occupied nights', 'nights sold')
        COMMENT = 'Nights occupied. Includes host-blocked dates, which the source cannot distinguish from bookings.',

    daily.available_nights AS count_if(daily.is_available)
        WITH SYNONYMS = ('vacant nights', 'empty nights')
        COMMENT = 'Nights still open.',

    daily.occupancy_rate AS div0(count_if(not daily.is_available), count(*))
        WITH SYNONYMS = ('occupancy', 'utilization')
        COMMENT = 'Booked nights divided by total nights in whatever slice is grouped. Night-weighted, so it is the correct portfolio-level occupancy: a listing with more calendar rows counts for more. Use this by default.',

    daily.avg_nightly_price AS avg(daily.price)
        WITH SYNONYMS = ('average price', 'average rate')
        COMMENT = 'Mean rate the listing was OFFERED at across all nights, booked or not. This is not what it earned - see achieved_nightly_rate.',

    daily.achieved_nightly_rate AS avg(daily.revenue)
        WITH SYNONYMS = ('realized rate', 'earned rate')
        COMMENT = 'Mean rate actually EARNED, over booked nights only, because revenue is NULL elsewhere. The gap against avg_nightly_price is discounting discipline. For question 8, compare this against list_price.',

    daily.min_nightly_price AS min(daily.price)
        COMMENT = 'Lowest rate offered in the slice.',

    daily.max_nightly_price AS max(daily.price)
        COMMENT = 'Highest rate offered in the slice.',

    daily.distinct_prices AS count(distinct daily.price)
        WITH SYNONYMS = ('price changes', 'price points')
        COMMENT = 'Distinct nightly rates in the slice. Grouped by listing this separates dynamic-pricing hosts from set-and-forget ones - a value of 1 means the rate never moved all year.',

    daily.listings AS count(distinct daily.listing_id)
        WITH SYNONYMS = ('listing count', 'properties', 'supply')
        COMMENT = 'Distinct listings in the slice. Grouped by neighborhood this is supply density, question 26, which needed a new model before this view existed.',

    daily.hosts AS count(distinct daily.host_id)
        COMMENT = 'Distinct hosts in the slice. Excludes orphan listings, whose host_id is NULL.',

    daily.avg_price_per_bedroom AS avg(daily.price_per_bedroom)
        COMMENT = 'Mean of price per bedroom. Backed by every private room but only some entire homes, since bedrooms goes NULL on entire homes only - so an entire-home figure here rests on a smaller base than the raw price does. Normalizing COMPRESSES the entire-home premium over a private room rather than removing it.',

    daily.avg_price_per_bed AS avg(daily.price_per_bed)
        COMMENT = 'Mean of price per bed. Also short some entire homes, since beds goes to 0 on a few of them. Compresses the same premium further than the per-bedroom version does.',

    daily.avg_price_per_guest AS avg(daily.price_per_guest)
        COMMENT = 'Mean of price per guest of capacity. accommodates is populated on every listing, so unlike the per-bedroom and per-bed versions this one is backed by all of them - prefer it when the comparison has to cover the whole portfolio.',

    daily.avg_minimum_nights AS avg(daily.minimum_nights)
        COMMENT = 'Mean minimum-stay requirement. For question 16, against occupancy.',

    daily.max_maximum_nights AS max(daily.maximum_nights)
        COMMENT = 'Longest stay any listing in the slice will accept. For question 3, the cap that clamps an availability window.',

    daily.max_minimum_nights AS max(daily.minimum_nights)
        COMMENT = 'Strictest minimum-stay requirement in the slice. For question 25: an availability window shorter than this cannot be sold as a single stay at all. The strictest rather than the mean, because a stay covering the run has to clear the requirement on every night of it.'
)

COMMENT = 'Nightly economics for rental listings: revenue, pricing, occupancy and availability at listing x date grain over a fixed one-year snapshot. Use this for anything about a specific date, month, day of week, or price over time. For lifetime per-listing measures use SEM_LISTING_PERFORMANCE, for booking counts and length of stay use SEM_RESERVATIONS, for host portfolios use SEM_HOST_PERFORMANCE.'

AI_SQL_GENERATION 'The calendar is a fixed snapshot, not a rolling window. NEVER use current_date or current_timestamp for recency, staleness or tenure - anchor to the max calendar_date or to the as_of_date column instead, or the answer changes on every run. Prefer the precomputed month_start_date over date_trunc on calendar_date. Do not filter out is_orphan_listing when totalling revenue, because orphan listings carry real booked revenue; do filter them out when comparing descriptive attributes, which are NULL for them. Do not count reservations in this view - reservation_id is not unique here and each booking spans many rows. For anything about a contiguous stretch of open nights, group by listing_id and availability_window_seq with is_available filtered first, and measure the length of a window as the count of rows in the group rather than as a difference between dates.'

{{ ai_verified_queries([
    'q01', 'q02', 'q03', 'q06', 'q10',
    'q15', 'q16', 'q21', 'q25',
]) }}
