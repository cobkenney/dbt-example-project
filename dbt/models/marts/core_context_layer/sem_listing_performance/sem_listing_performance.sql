{{ config(materialized='semantic_view') }}

TABLES (
    listing AS {{ ref('dim_listings') }}
        PRIMARY KEY (listing_id)
        WITH SYNONYMS = ('listings', 'properties', 'units', 'rentals')
        COMMENT = 'One row per listing with lifetime measures over the fixed one-year snapshot. Covers every listing the calendar references, including deleted listings, whose descriptive columns are all NULL.',

    host AS {{ ref('dim_hosts') }}
        PRIMARY KEY (host_id)
        WITH SYNONYMS = ('hosts', 'owners', 'operators')
        COMMENT = 'Host attributes. Joined for segmentation only - host-grain measures live in sem_host_performance, because summing them here would double-count any host holding more than one listing.'
)

RELATIONSHIPS (
    -- Grouping a listing measure by a host attribute is safe: many listings to
    -- one host does not fan out the listing grain. The reverse is not, which is
    -- why no host measure appears below.
    listing_to_host AS listing (host_id) REFERENCES host (host_id)
)

FACTS (
    listing.total_revenue AS listing.total_revenue
        WITH SYNONYMS = ('revenue', 'earnings', 'income')
        COMMENT = 'Lifetime booked revenue over the year. Zero, not NULL, for listings that were never booked - question 5.',

    listing.occupancy_rate AS listing.occupancy_rate
        WITH SYNONYMS = ('occupancy', 'utilization')
        COMMENT = 'Booked nights divided by this listing calendar nights. Ranges 0 to 1.',

    listing.avg_nightly_price AS listing.avg_nightly_price
        COMMENT = 'Mean rate this listing was OFFERED at across every night of the snapshot, booked or not. Not what it earned.',

    listing.list_price AS listing.list_price
        WITH SYNONYMS = ('advertised price', 'asking price')
        COMMENT = 'Advertised nightly rate from the listings table. NULL for a deleted listing.',

    listing.booked_nights AS listing.booked_nights
        COMMENT = 'Nights occupied over the year.',

    listing.available_nights AS listing.available_nights
        COMMENT = 'Nights left open over the year.',

    listing.calendar_days AS listing.calendar_days
        COMMENT = 'Identical for every listing, since the source is a fixed one-year snapshot. It is the occupancy denominator, NOT a measure of how long the listing has existed.',

    listing.number_of_reviews AS listing.number_of_reviews
        WITH SYNONYMS = ('review count', 'reviews')
        COMMENT = 'Lifetime review count. Zero for listings never reviewed.',

    listing.review_scores_rating AS listing.review_scores_rating
        WITH SYNONYMS = ('rating', 'review score')
        COMMENT = 'Average review score. NULL for listings with no reviews.',

    listing.revenue_per_guest
        AS listing.total_revenue / nullif(listing.accommodates, 0)
        COMMENT = 'Lifetime revenue divided by guest capacity. Normalizes a studio against a 6-sleeper - question 12.',

    listing.achieved_nightly_rate
        AS listing.total_revenue / nullif(listing.booked_nights, 0)
        COMMENT = 'Revenue divided by nights actually sold - the rate the listing EARNED. NULL for listings never booked.',

    listing.discount_to_list
        AS listing.list_price
        - (listing.total_revenue / nullif(listing.booked_nights, 0))
        COMMENT = 'Advertised rate minus achieved rate, in dollars. Question 8 - a large positive gap is weak discounting discipline, and a negative one means the listing earned above its ask.',

    listing.days_since_last_review
        AS datediff(day, listing.last_review_date, listing.as_of_date)
        WITH SYNONYMS = ('review recency', 'staleness')
        COMMENT = 'Days between the most recent review and the snapshot end. Question 24. Measured against as_of_date rather than current_date, so the answer does not drift on every run. NULL for listings never reviewed, which is a DIFFERENT thing from stale.',

    listing.months_since_last_review
        AS datediff(month, listing.last_review_date, listing.as_of_date)
        COMMENT = 'Whole months since the most recent review, anchored to as_of_date. Runs to several years on the stalest listing, so do not assume the range is small.'
)

DIMENSIONS (
    listing.listing_id AS listing.listing_id
        COMMENT = 'Listing identifier, and the grain of this view - one row each.',

    listing.listing_name AS listing.listing_name
        WITH SYNONYMS = ('name', 'title')
        COMMENT = 'Listing title. NULL for a deleted listing.',

    listing.neighborhood AS listing.neighborhood
        WITH SYNONYMS = ('area', 'district', 'location')
        COMMENT = 'Listing neighborhood. NULL for a deleted listing. Some neighborhoods hold only a single listing, so treat per-neighborhood averages as THIN and check the listing count alongside any of them.',

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
        COMMENT = 'Bed count. Goes to zero rather than NULL on a few listings, all of them entire homes. A listing can record a bedroom and no beds, so bedrooms and beds are NOT substitutes for each other.',

    listing.bathrooms AS listing.bathrooms
        COMMENT = 'Bathroom count, parsed from a free-text label. Does NOT indicate whether the bathroom is shared - is_shared_bathroom is the only signal for that.',

    listing.is_shared_bathroom AS listing.is_shared_bathroom
        WITH SYNONYMS = ('shared bath')
        COMMENT = 'True where the raw bathroom label mentions shared, which is a minority of listings. Question 13, which quantifies a renovation case.',

    listing.first_review_date AS listing.first_review_date
        COMMENT = 'Earliest review. NULL for listings with no reviews.',

    listing.last_review_date AS listing.last_review_date
        WITH SYNONYMS = ('latest review', 'most recent review')
        COMMENT = 'Most recent review. NULL for listings with no reviews.',

    listing.as_of_date AS listing.as_of_date
        COMMENT = 'The snapshot end, constant on every row. The anchor every recency measure here uses instead of current_date.',

    listing.was_never_booked AS listing.total_revenue = 0
        COMMENT = 'True for listings that were available all year and never earned anything. A handful qualify. Question 5: price, photos, or location.',

    listing.has_reviews AS listing.number_of_reviews > 0
        COMMENT = 'True where the listing has ever been reviewed. Separates a genuinely stale listing from one that was never reviewed at all.',

    listing.is_deleted AS listing.is_deleted
        COMMENT = 'True for a listing the calendar references that has no listings row, so every descriptive column is NULL. Filter it out when comparing attributes - it would otherwise form a NULL group. LEAVE IT IN when totalling revenue, since it carries real booked revenue.',

    listing.has_air_conditioning AS listing.has_air_conditioning
        WITH SYNONYMS = ('ac', 'air con')
        COMMENT = 'True where the listing offers air conditioning.',

    listing.has_lockbox AS listing.has_lockbox
        COMMENT = 'True where the listing offers a lockbox.',

    listing.has_first_aid_kit AS listing.has_first_aid_kit
        COMMENT = 'True where the listing offers a first aid kit.',

    listing.has_wifi AS listing.has_wifi
        WITH SYNONYMS = ('internet', 'wireless')
        COMMENT = 'True where the listing offers wifi.',

    listing.has_heating AS listing.has_heating
        COMMENT = 'True where the listing offers heating.',

    listing.has_kitchen AS listing.has_kitchen
        COMMENT = 'True where the listing offers a kitchen.',

    listing.amenity_count AS listing.amenity_count
        COMMENT = 'Number of amenities on the listing. Many more distinct amenities exist across the portfolio than have their own flag here - see int_listing_amenities for the rest.',

    host.host_id AS host.host_id
        COMMENT = 'Host identifier. The join key - NEVER use the masked name, which distinct hosts can share.',

    host.host_name_masked AS host.host_name_masked
        COMMENT = 'Salted hash of the host name. The plaintext name is PII and does not exist anywhere in these models. Usable as a grouping key but NOT as a host identifier: host names are not unique, so distinct hosts can share a name and therefore share a hash. Join on host_id.',

    host.host_location AS host.host_location
        COMMENT = 'Self-reported host location, free text and not normalized. Not comparable to neighborhood, which describes where the listing is.',

    host.host_tenure_years AS host.host_tenure_years
        COMMENT = 'Whole years between the host joining and the snapshot end. Little variance - host_since is tightly clustered, so it explains very little.',

    host.is_multi_listing_host AS host.is_multi_listing_host
        COMMENT = 'True where the host holds more than one listing. A small minority of hosts, though they hold a disproportionate share of listings. NULL for a deleted listing, which has no host.',

    host.verification_count AS host.verification_count
        COMMENT = 'Number of verification methods the host completed. Read as adoption, not as trust - see SEM_HOST_PERFORMANCE for why it carries no performance signal.'
)

METRICS (
    listing.listings AS count(*)
        WITH SYNONYMS = ('listing count', 'properties', 'supply', 'inventory')
        COMMENT = 'Number of listings in the slice. Grouped by neighborhood this is supply density - question 26, which was filed as needing a new neighborhood-grain model before this view existed.',

    listing.portfolio_revenue AS sum(listing.total_revenue)
        WITH SYNONYMS = ('total revenue', 'revenue')
        COMMENT = 'Summed lifetime revenue. Safe at this grain: one row per listing, so nothing double-counts. Reconciles with total_revenue in sem_listing_daily.',

    listing.avg_revenue_per_listing AS avg(listing.total_revenue)
        COMMENT = 'Mean lifetime revenue per listing. Listing-weighted - for a host-weighted figure use revenue_per_listing in sem_host_performance, which answers a different question and gives a different number.',

    listing.median_revenue_per_listing AS median(listing.total_revenue)
        COMMENT = 'Median lifetime revenue per listing. Revenue is Pareto-shaped here, so this sits well below the mean.',

    listing.max_revenue AS max(listing.total_revenue)
        COMMENT = 'Highest lifetime revenue in the slice.',

    listing.avg_occupancy_rate AS avg(listing.occupancy_rate)
        WITH SYNONYMS = ('occupancy', 'average occupancy')
        COMMENT = 'Mean of the per-listing occupancy rate. LISTING-weighted: every listing counts equally. Use this to compare neighborhoods or room types, which is question 4. Equal to occupancy_rate_weighted on this data, since every listing covers the same number of calendar nights.',

    listing.occupancy_rate_weighted
        AS div0(sum(listing.booked_nights), sum(listing.calendar_days))
        COMMENT = 'Total booked nights divided by total calendar nights. NIGHT-weighted. Identical to avg_occupancy_rate on this data because every listing covers the same calendar window - it would only diverge if listings covered unequal windows. The two DO differ at host grain, where portfolio sizes vary; see SEM_HOST_PERFORMANCE.',

    listing.total_booked_nights AS sum(listing.booked_nights)
        COMMENT = 'Total nights occupied across the slice.',

    listing.total_available_nights AS sum(listing.available_nights)
        COMMENT = 'Total nights left open across the slice.',

    listing.avg_list_price AS avg(listing.list_price)
        WITH SYNONYMS = ('average advertised price')
        COMMENT = 'Mean advertised rate. Excludes deleted listings, whose list_price is NULL.',

    listing.avg_achieved_rate AS avg(listing.achieved_nightly_rate)
        WITH SYNONYMS = ('average earned rate')
        COMMENT = 'Mean of the per-listing achieved rate. Question 8 - compare against avg_list_price, and the gap is discounting discipline.',

    listing.avg_discount_to_list AS avg(listing.discount_to_list)
        COMMENT = 'Mean dollars between the advertised rate and the achieved rate. Positive means listings earn below their ask.',

    listing.avg_revenue_per_guest AS avg(listing.revenue_per_guest)
        COMMENT = 'Mean revenue per unit of guest capacity - question 12, which makes a studio and a 6-sleeper comparable.',

    listing.avg_review_score AS avg(listing.review_scores_rating)
        WITH SYNONYMS = ('average rating')
        COMMENT = 'Mean review score across listings that have one. Question 11 - whether review investment shows up in occupancy or a price premium.',

    listing.total_reviews AS sum(listing.number_of_reviews)
        COMMENT = 'Summed lifetime review count.',

    listing.never_booked_listings AS count_if(listing.total_revenue = 0)
        COMMENT = 'How many listings earned nothing all year - question 5.',

    listing.avg_amenity_count AS avg(listing.amenity_count)
        COMMENT = 'Mean number of amenities. Question 14 - but read the view COMMENT on why amenity comparisons here are cross-sectional only.',

    listing.avg_days_since_last_review AS avg(listing.days_since_last_review)
        COMMENT = 'Mean days since the last review, anchored to as_of_date rather than current_date. Question 24.',

    listing.stalest_days_since_review AS max(listing.days_since_last_review)
        COMMENT = 'Longest gap since a review in the slice, anchored to as_of_date.',

    listing.hosts AS count(distinct listing.host_id)
        COMMENT = 'Distinct hosts in the slice. Excludes deleted listings, whose host_id is NULL.'
)

COMMENT = 'Lifetime performance per rental listing over a fixed one-year snapshot: revenue, occupancy, pricing against the advertised rate, reviews, and attributes including amenities. Use this to compare listings or segments cross-sectionally - which neighborhood or room type performs, which listings never earned, whether reviews or amenities go with higher rates. For anything by date or month use SEM_LISTING_DAILY; for booking counts and length of stay use SEM_RESERVATIONS; for host portfolios use SEM_HOST_PERFORMANCE. IMPORTANT on amenities: any link between an amenity and revenue here is CORRELATION AT A POINT IN TIME, not impact. Every amenity changelog event predates the calendar window entirely, so there is no before-and-after period in the data and the revenue effect of ADDING an amenity cannot be measured at any modelling effort.'

AI_SQL_GENERATION 'Measures here are already lifetime totals per listing, so never multiply them by a night count or group them by a date. For recency and staleness use days_since_last_review or months_since_last_review, which anchor to as_of_date - NEVER use current_date, because the snapshot is a fixed window and current_date makes the answer drift on every run. Distinguish a NULL last_review_date, meaning never reviewed, from a large staleness value, meaning reviewed long ago. When comparing descriptive attributes filter is_deleted to false, since a deleted listing has NULL attributes and would form a NULL group; when totalling revenue leave it in. For occupancy pick deliberately: avg_occupancy_rate is listing-weighted and right for comparing segments, occupancy_rate_weighted is night-weighted and right for a portfolio total. Never present an amenity-to-revenue relationship as causal.'

{{ ai_verified_queries([
    'q04', 'q05', 'q07', 'q08', 'q09',
    'q11', 'q12', 'q13', 'q14', 'q24', 'q26',
]) }}
