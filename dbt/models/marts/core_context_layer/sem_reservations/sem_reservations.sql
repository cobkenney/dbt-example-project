-- Bookings: how many, how long, and what each was worth. One row per
-- reservation.
--
-- Separate from sem_listing_daily because the grains differ and cannot be mixed:
-- one row per reservation here against one row per listing-night there. One view
-- holding both would let "reservations by month" join a booking against every
-- night it occupies and count it once per night. Snowflake returns that without
-- complaint.
--
-- Answers business questions 17, 22 and 23.
--
-- What this table cannot do, because it is derived from occupied calendar nights
-- rather than from a bookings source: cancelled and never-confirmed bookings are
-- invisible, so conversion and cancellation rate are out of reach, and there is
-- no booking-created timestamp anywhere in the raw data, so lead time and
-- booking pace are too. Stated in the view COMMENT so a natural-language client
-- gets told rather than guessing.
{{ config(materialized='semantic_view') }}

TABLES (
    reservation AS {{ ref('fct_reservations') }}
        PRIMARY KEY (reservation_key)
        WITH SYNONYMS = ('reservations', 'bookings', 'stays', 'trips')
        COMMENT = 'One row per reservation. The key is reservation_key, NOT reservation_id - the same id can cover two separate stays on two different listings, so grouping on reservation_id alone merges them into one impossible reservation spanning two properties.',

    listing AS {{ ref('dim_listings') }}
        PRIMARY KEY (listing_id)
        WITH SYNONYMS = ('listings', 'properties', 'units')
        COMMENT = 'Listing attributes. Joined for description only - lifetime listing measures live in sem_listing_performance.',

    host AS {{ ref('dim_hosts') }}
        PRIMARY KEY (host_id)
        WITH SYNONYMS = ('hosts', 'owners', 'operators')
        COMMENT = 'Host attributes. Joined for segmentation only - host measures live in sem_host_performance.'
)

RELATIONSHIPS (
    reservation_to_listing AS reservation (listing_id)
        REFERENCES listing (listing_id),

    -- An orphan listing has a NULL host_id, so its reservations drop out of any
    -- host-grouped total. They are real bookings carrying real revenue.
    listing_to_host AS listing (host_id) REFERENCES host (host_id)
)

FACTS (
    reservation.nights AS reservation.nights
        WITH SYNONYMS = ('length of stay', 'stay length', 'duration')
        COMMENT = 'Nights occupied. CAVEAT: a floor rather than the true length on the censored reservations, which are cut off by the edges of the snapshot. Filter is_censored to false before averaging this.',

    reservation.reservation_revenue AS reservation.reservation_revenue
        WITH SYNONYMS = ('booking value', 'stay revenue')
        COMMENT = 'Total revenue for the stay, summed across its nights.',

    reservation.avg_nightly_price AS reservation.avg_nightly_price
        COMMENT = 'Mean nightly rate within this one reservation.'
)

DIMENSIONS (
    reservation.reservation_key AS reservation.reservation_key
        COMMENT = 'The reservation primary key, over listing_id and reservation_id. Use this to identify a booking, never reservation_id alone.',

    reservation.listing_id AS reservation.listing_id
        COMMENT = 'Listing identifier. Group by this for bookings per listing.',

    reservation.listing_name AS reservation.listing_name
        WITH SYNONYMS = ('name', 'title')
        COMMENT = 'Listing title, denormalized onto the fact. NULL for an orphan listing.',

    reservation.check_in_date AS reservation.check_in_date
        WITH SYNONYMS = ('arrival', 'start date')
        COMMENT = 'First night of the stay.',

    reservation.last_night_date AS reservation.last_night_date
        COMMENT = 'Final night occupied. Compare against check_in_month to find stays that cross a month boundary - question 22.',

    reservation.check_out_date AS reservation.check_out_date
        WITH SYNONYMS = ('departure', 'end date')
        COMMENT = 'Departure date, the morning after the last night. Not an occupied night, so it is not counted in nights.',

    reservation.check_in_month AS reservation.check_in_month
        WITH SYNONYMS = ('month', 'booking month')
        COMMENT = 'First day of the check-in month, precomputed. A stay spanning a month boundary counts entirely in the month it STARTED - revenue is not prorated across months.',

    reservation.spans_month_boundary
        AS date_trunc('month', reservation.last_night_date)
        != reservation.check_in_month
        COMMENT = 'True where the stay starts in one month and ends in another. Question 22 - these are the reservations whose revenue would need prorating if monthly revenue had to be exact.',

    -- The filter that changes the answer, and the reason it is one column rather
    -- than two: either edge truncates a stay, so exposing left and right
    -- separately invites filtering one and forgetting the other.
    reservation.is_censored AS reservation.is_censored
        COMMENT = 'True for reservations truncated by an edge of the snapshot, whose real length is unknown and whose nights is therefore a floor. EXCLUDE these when averaging length of stay - including them pulls the mean DOWN, since every censored stay is recorded shorter than it really was. KEEP them when counting bookings or totalling revenue, because those bookings really happened and their revenue is real.',

    reservation.is_left_censored AS reservation.is_left_censored
        COMMENT = 'True where the stay was already running when the snapshot opened. Prefer is_censored, which covers both edges.',

    reservation.is_right_censored AS reservation.is_right_censored
        COMMENT = 'True where the stay was still running when the snapshot closed. Prefer is_censored, which covers both edges.',

    reservation.is_contiguous AS reservation.is_contiguous
        COMMENT = 'True where every night between check-in and the last night is occupied by this reservation, with no gap.',

    reservation.is_orphan_listing AS reservation.is_orphan_listing
        COMMENT = 'True for reservations on a listing that has no listings row, so its descriptive columns are all NULL. Filter out when comparing attributes; LEAVE IN when totalling revenue or counting bookings.',

    listing.neighborhood AS listing.neighborhood
        WITH SYNONYMS = ('area', 'district', 'location')
        COMMENT = 'Listing neighborhood. For question 23, length-of-stay distribution by area.',

    listing.property_type AS listing.property_type
        COMMENT = 'Apartment, house, condominium and similar.',

    listing.room_type AS listing.room_type
        COMMENT = 'Entire home/apt, private room, or shared room.',

    listing.accommodates AS listing.accommodates
        WITH SYNONYMS = ('capacity', 'sleeps', 'guests')
        COMMENT = 'Guest capacity.',

    listing.is_shared_bathroom AS listing.is_shared_bathroom
        COMMENT = 'True where the bathroom is shared, which is a minority of listings.',

    listing.review_scores_rating AS listing.review_scores_rating
        COMMENT = 'Average review score. NULL for listings with no reviews.',

    reservation.has_air_conditioning AS reservation.has_air_conditioning
        WITH SYNONYMS = ('ac', 'air con')
        COMMENT = 'True where the listing offers air conditioning.',

    reservation.has_lockbox AS reservation.has_lockbox
        COMMENT = 'True where the listing offers a lockbox.',

    reservation.has_first_aid_kit AS reservation.has_first_aid_kit
        COMMENT = 'True where the listing offers a first aid kit.',

    reservation.amenity_count AS reservation.amenity_count
        COMMENT = 'Number of amenities on the listing.',

    host.is_multi_listing_host AS host.is_multi_listing_host
        COMMENT = 'True where the host holds more than one listing, which is a small minority of hosts. Grouping by this drops orphan listings, which have no host.',

    host.host_tenure_years AS host.host_tenure_years
        COMMENT = 'Whole years between the host joining and the snapshot end, never current_date.'
)

METRICS (
    reservation.reservations AS count(*)
        WITH SYNONYMS = ('bookings', 'booking count', 'stays')
        COMMENT = 'Number of reservations. Counts rows, so it is safe on the censored ones - do NOT filter is_censored here.',

    reservation.booked_nights AS sum(reservation.nights)
        COMMENT = 'Total nights occupied across the reservations in the slice. Slightly understated by the censored stays, whose nights are a floor.',

    reservation.total_revenue AS sum(reservation.reservation_revenue)
        WITH SYNONYMS = ('revenue', 'earnings')
        COMMENT = 'Booking revenue. Reconciles with total_revenue in sem_listing_daily, since both derive from the same occupied nights.',

    -- The metric where the censoring filter is built in rather than left to the
    -- caller. This is the whole reason is_censored exists as a column.
    reservation.avg_length_of_stay
        AS avg(case when not reservation.is_censored
                then reservation.nights end)
        WITH SYNONYMS = ('average stay', 'average nights', 'typical stay')
        COMMENT = 'Mean nights per stay over COMPLETE reservations only - the censored ones are excluded here by construction, because their length is truncated and would bias the mean down. Use this rather than averaging nights yourself.',

    reservation.avg_length_of_stay_all
        AS avg(reservation.nights)
        COMMENT = 'Mean nights per stay INCLUDING censored reservations, which pulls it below the complete-stay figure. Provided only so the difference is inspectable - prefer avg_length_of_stay.',

    reservation.median_length_of_stay
        AS median(case when not reservation.is_censored
                    then reservation.nights end)
        COMMENT = 'Median nights per stay over complete reservations. Less sensitive than the mean to the long tail of multi-month stays.',

    reservation.max_length_of_stay
        AS max(case when not reservation.is_censored
                then reservation.nights end)
        COMMENT = 'Longest complete stay in the slice.',

    reservation.avg_booking_value AS avg(reservation.reservation_revenue)
        WITH SYNONYMS = ('average booking', 'revenue per booking')
        COMMENT = 'Mean revenue per reservation. NOT filtered for censoring - the revenue on a truncated stay is real, only its length is unknown.',

    reservation.avg_nightly_rate AS avg(reservation.avg_nightly_price)
        COMMENT = 'Mean of the per-reservation nightly rate. Reservation-weighted, so a one-night stay counts as much as a months-long one - for a night-weighted rate use achieved_nightly_rate in sem_listing_daily.',

    reservation.censored_reservations AS count_if(reservation.is_censored)
        COMMENT = 'How many reservations in the slice are truncated by a snapshot edge. Read this alongside any length-of-stay figure to see how much was excluded.',

    reservation.month_boundary_reservations
        AS count_if(reservation.spans_month_boundary)
        COMMENT = 'How many reservations start in one month and end in another - question 22.',

    reservation.listings AS count(distinct reservation.listing_id)
        COMMENT = 'Distinct listings with at least one booking in the slice. FEWER than the total listing count - a few listings were never booked at all.',

    reservation.hosts AS count(distinct reservation.host_id)
        COMMENT = 'Distinct hosts with at least one booking. Excludes orphan listings, whose host_id is NULL.'
)

COMMENT = 'Rental bookings: volume, length of stay, and booking value at one row per reservation. Use this for how many bookings, how long people stay, and what a booking is worth. For anything by specific date or month-over-month pricing use SEM_LISTING_DAILY. CANNOT ANSWER: cancellation rate, booking conversion, and booking lead time or pace - these reservations are derived from occupied calendar nights, so unconfirmed and cancelled bookings are invisible and no booking-created timestamp exists in the source. Repeat-guest questions are also impossible: reservation_id identifies a booking, not a guest, and there is no guest identity in the data.'

AI_SQL_GENERATION 'Always use reservation_key as the reservation identifier, never reservation_id, which is NOT unique - the same id can cover separate stays on different listings. For any question about how long people stay, use the avg_length_of_stay metric, which already excludes the censored reservations; do not average the nights fact directly, because censored stays are truncated and bias it down. For counts and revenue do NOT filter is_censored, since those bookings really happened. The snapshot is a fixed one-year window, not a rolling one - never use current_date. Revenue is not prorated across months: a stay is attributed entirely to its check-in month.'

{#
    Verified queries for the three questions this view answers. The entries live
    in macros/verified_queries/, one macro per question, because the SQL is long
    and the caveat each entry pins is worth a comment next to it.

    Not yet validated. Snowflake accepts a verified query without checking that
    it runs, so these build green either way - the validator in TODO item 14 is
    what will make "verified" mean anything here.
#}
{{ ai_verified_queries(['q17', 'q22', 'q23']) }}
