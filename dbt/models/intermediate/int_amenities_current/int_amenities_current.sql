-- One row per listing holding its CURRENT amenity set — a deliberate
-- reduction of the changelog, not a full history.
--
-- The changelog has real history: 2 events per listing, and 48 of 50 listings
-- have a different amenity set between them (growth is purely additive — no
-- amenity ever disappears). Collapsing to the latest event is only valid
-- because every event predates the calendar window: the newest changelog
-- event is 2021-07-06, the calendar opens 2021-07-12. A point-in-time (SCD2)
-- join was built and compared — 0 of 18,250 calendar rows resolve to a
-- superseded version, so it is a provable no-op on this data.
--
-- That assumption is enforced by tests/assert_amenities_predate_calendar.sql.
-- If it ever fails, this model must become a versioned SCD2 model: each
-- changelog row carries the entire amenity array (a snapshot, not a delta),
-- so valid_from/valid_to via lead() is all that is required.
--
-- Amenities land as a JSON array string, so flatten to one row per
-- listing-amenity and pivot the ones the marts filter on into boolean flags.
--
-- Substring matching the raw string is unsafe: '%air%' also matches
-- "Hair dryer". Exact matches against flattened values avoid that.
--
-- Sourced from the changelog rather than stg_listings because the changelog
-- covers all 50 listings that appear in the calendar — including 276450,
-- which is missing from listings entirely.
with latest_amenities as (

    select
        listing_id,
        amenities
    from {{ ref('stg_amenities_changelog') }}
    qualify
        row_number() over (
            partition by listing_id order by changed_at desc
        ) = 1

),

flattened as (

    select
        latest_amenities.listing_id,
        amenity.value::string as amenity_name
    from latest_amenities,
        lateral flatten(
            input => try_parse_json(latest_amenities.amenities)
        ) as amenity

),

pivoted as (

    select
        listing_id,
        count(distinct amenity_name) as amenity_count,
        array_agg(distinct amenity_name) as amenity_list,
        boolor_agg(amenity_name = 'Air conditioning')
            as has_air_conditioning,
        boolor_agg(amenity_name = 'Lockbox') as has_lockbox,
        boolor_agg(amenity_name = 'First aid kit') as has_first_aid_kit,
        boolor_agg(amenity_name = 'Wifi') as has_wifi,
        boolor_agg(amenity_name = 'Heating') as has_heating,
        boolor_agg(amenity_name = 'Kitchen') as has_kitchen,
        boolor_agg(amenity_name = 'Pool') as has_pool
    from flattened
    group by all

)

select * from pivoted
