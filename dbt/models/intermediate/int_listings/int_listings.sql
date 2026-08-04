-- One row per listing the project recognises — a superset of what stg_listings
-- has, since the calendar references listings the raw listings table lacks.
--
-- WHY THIS MODEL EXISTS. Four models used to read stg_listings directly and
-- each took its own column subset, which was fine while nothing was shared.
-- One thing was: `listings.listing_id is null as is_orphan_listing` was
-- computed independently in int_listing_daily and again in dim_listings. Two
-- copies of the rule that decides which listings are missing attributes, in
-- two layers, with nothing tying them together — that is the logic this model
-- centralizes, and the reason it is a model rather than a passthrough.
--
-- THE GRAIN IS THE POINT. The calendar references more listings than
-- stg_listings holds, so driving off stg_listings silently drops the difference
-- and every consumer that needs the full universe has to rebuild it itself.
-- Driving off the amenities bridge — which is changelog-derived and covers
-- every listing the calendar references — sets the grain once, here.
--
-- Consequence worth stating plainly: an orphan row has a listing_id and NULL
-- for every descriptive column. That is not a defect to be filtered, it is the
-- honest shape of the data, and is_orphan_listing is what lets a consumer
-- decide. int_hosts filters them out, because a listing with no host_id cannot
-- belong to a host; fct_reservations keeps them, because they carry real booked
-- revenue.
--
-- NOT a pass-through of stg_listings, and deliberately not a copy of it
-- either. The raw JSON columns stay upstream: host_verifications is flattened
-- by int_host_verifications and amenities by the changelog path, so carrying
-- them here would offer two routes to the same array and invite the wrong one.
-- Anything needing raw JSON refs stg_listings, which is why
-- int_host_verifications still does.
--
-- No measures. Revenue, occupancy and nightly rates are all calendar-derived
-- and live in int_listing_daily; mixing them in here would give two homes for
-- a listing-grain measure and no rule for choosing.
with listing_universe as (

    -- The driving table, and the reason the grain is the full universe. The
    -- bridge is built off stg_amenities_changelog, which covers every listing
    -- the calendar references, including the ones stg_listings lacks.
    --
    -- distinct because this is a bridge at one row per listing per amenity.
    select distinct listing_id
    from {{ ref('int_listing_amenities') }}

),

listings as (

    select * from {{ ref('stg_listings') }}

),

final as (

    select
        listing_universe.listing_id,

        listings.listing_name,
        listings.neighborhood,
        listings.property_type,
        listings.room_type,
        listings.accommodates,
        listings.bedrooms,
        listings.beds,
        listings.bathrooms,
        listings.is_shared_bathroom,

        listings.number_of_reviews,
        listings.review_scores_rating,
        listings.first_review_date,
        listings.last_review_date,

        listings.host_id,
        listings.host_name_masked,
        listings.host_since,
        listings.host_location,

        listings.price as list_price,

        -- The rule this model exists to hold. A left join that found no
        -- listings row means the listing is in the calendar but absent from
        -- the raw listings table, so every column above is NULL for it.
        --
        -- Named on the join result rather than on a listing_id literal: an
        -- orphan HAS a listing_id, inherited from the driving table, so testing
        -- that would report false for the very rows it is about.
        listings.listing_id is null as is_orphan_listing

    from listing_universe
    left join listings
        on listing_universe.listing_id = listings.listing_id

)

select * from final
