-- One row per listing: descriptive attributes plus amenity flags and lifetime
-- performance measures.
--
-- as_of_date arrives as a session variable set by the pre-hook, the same
-- pattern dim_hosts uses for the same reason — see that model's header for the
-- full rationale and the two costs (the compiled SQL no longer runs standalone,
-- and the int_listing_daily dependency lives only in the hook). Same variable
-- name, same source, so the two dimensions cannot disagree about where the
-- snapshot ends.
--
-- Why the variable rather than a cross join matters more here than on
-- dim_hosts: the anchor has to reach orphan listing 276450, and that listing
-- has no host_id, so it cannot inherit the date from dim_hosts. A scalar in the
-- select list reaches every row without a join that could drop one.
--
-- The ref() stays literal Jinja inside the string — concatenating it with ~
-- resolves to THIS model during parse and compiles to a silent self-reference.
{{ config(
    pre_hook="set calendar_as_of_date = (select max(calendar_date)
              from {{ ref('int_listing_daily') }})"
) }}

with amenities as (

    -- Driving table, not stg_listings — this sets the grain to all 50 listings
    -- the calendar references, including orphan 276450.
    --
    -- The bridge model, reduced to one row per listing. It carries no flags of
    -- its own now that the pivot lives in int_listing_daily, so the six flags
    -- this mart exposes come from daily_rollup below.
    select distinct listing_id
    from {{ ref('int_listing_amenities') }}

),

listings as (

    select * from {{ ref('stg_listings') }}

),

daily_rollup as (

    select
        listing_id,
        count(*) as calendar_days,
        count_if(not is_available) as booked_nights,
        count_if(is_available) as available_nights,
        -- coalesce because 3 listings were never booked, so sum() over all-NULL
        -- revenue returns NULL. Zero is the honest measure.
        coalesce(sum(revenue), 0) as total_revenue,
        avg(price) as avg_nightly_price,
        min(price) as min_nightly_price,
        max(price) as max_nightly_price,

        -- Amenity attributes are constant across a listing's daily rows, so any
        -- aggregate returns the same value. min()/boolor_agg() collapse them
        -- back to listing grain without a second join to the bridge.
        --
        -- Only the six flags this mart exposes, named explicitly rather than
        -- carried in bulk: int_listing_daily generates all 81, and letting them
        -- all through would let a new amenity upstream change this mart's
        -- shape without anyone deciding to. Same friction as dim_hosts' 11
        -- verification flags. Query int_listing_amenities for an amenity that
        -- has no column here.
        min(amenity_count) as amenity_count,
        boolor_agg(has_air_conditioning) as has_air_conditioning,
        boolor_agg(has_lockbox) as has_lockbox,
        boolor_agg(has_first_aid_kit) as has_first_aid_kit,
        boolor_agg(has_wifi) as has_wifi,
        boolor_agg(has_heating) as has_heating,
        boolor_agg(has_kitchen) as has_kitchen
    from {{ ref('int_listing_daily') }}
    group by all

),

final as (

    select
        amenities.listing_id,

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

        -- Sits next to the review dates because that is what it is for: review
        -- recency has to be measured against the snapshot's end, not
        -- current_date, which drifts on every run and would make a
        -- stale-listing answer depend on when it was asked.
        --
        -- Nothing in this model divides by it — the age itself is left to the
        -- query, since datediff in whichever unit the question wants is cheaper
        -- than picking one here and being wrong for the other.
        $calendar_as_of_date as as_of_date,

        listings.host_id,
        listings.host_name_masked,
        listings.host_since,
        listings.host_location,

        listings.price as list_price,

        daily_rollup.amenity_count,
        daily_rollup.has_air_conditioning,
        daily_rollup.has_lockbox,
        daily_rollup.has_first_aid_kit,
        daily_rollup.has_wifi,
        daily_rollup.has_heating,
        daily_rollup.has_kitchen,

        daily_rollup.calendar_days,
        daily_rollup.booked_nights,
        daily_rollup.available_nights,
        daily_rollup.total_revenue,
        daily_rollup.avg_nightly_price,
        daily_rollup.min_nightly_price,
        daily_rollup.max_nightly_price,

        div0(
            daily_rollup.booked_nights, daily_rollup.calendar_days
        ) as occupancy_rate,

        listings.listing_id is null as is_orphan_listing

    from amenities
    left join listings on amenities.listing_id = listings.listing_id
    left join daily_rollup on amenities.listing_id = daily_rollup.listing_id

)

select * from final
