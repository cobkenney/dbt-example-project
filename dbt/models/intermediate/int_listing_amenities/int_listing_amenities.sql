-- One row per listing per amenity — the bridge grain, flattened out of the JSON
-- array on the changelog's latest event per listing.
--
-- Deliberately just the flatten. The boolean pivot that used to live here now
-- runs in int_listing_daily, where the flags are consumed; this model's only
-- job is to get the amenity set out of JSON and into rows. Same split as
-- int_host_verifications, which flattens verifications and leaves the
-- is_verified_* pivot to int_hosts.
--
-- The reduction to the CURRENT amenity set is still here, and it is still a
-- reduction rather than history. The changelog does hold real history — most
-- listings have events with differing amenity sets — but every event predates
-- the calendar window, so a point-in-time join provably changes nothing — see
-- tests/assert_amenities_predate_calendar.sql, which fails if that stops being
-- true. If it ever fails, this model becomes SCD2 and the pivot downstream has
-- to join on a date range rather than on listing_id alone.
--
-- Built from the changelog rather than stg_listings so that orphan listings —
-- present in the calendar but absent from listings — still get amenities.
with latest_amenities as (

    select
        listing_id,
        amenities
    -- The changelog, not stg_listings: it covers every listing the calendar
    -- references, including the orphans that listings is missing.
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

)

-- distinct rather than raw flatten output, matching int_host_verifications: a
-- malformed source array could repeat an amenity for one listing, which would
-- break the declared grain and double-count it in amenity_count downstream.
select distinct
    listing_id,
    amenity_name
from flattened
