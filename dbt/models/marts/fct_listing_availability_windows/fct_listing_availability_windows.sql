-- One row per contiguous availability window per listing, carrying the
-- amenity flags needed to filter windows by what the listing offers.
--
-- longest_possible_stay_nights is already clamped upstream to
-- least(window_length_nights, maximum_nights). Both constraints bind in real
-- data, so neither column alone answers "how long could someone actually stay".
with windows as (

    select * from {{ ref('int_listing_availability_windows') }}

),

amenities as (

    select * from {{ ref('int_amenities_current') }}

),

listings as (

    select * from {{ ref('stg_listings') }}

)

select
    windows.availability_window_id,
    windows.listing_id,
    windows.window_start_date,
    windows.window_end_date,
    windows.window_length_nights,
    windows.minimum_nights,
    windows.maximum_nights,
    windows.longest_possible_stay_nights,

    -- A window shorter than the owner's minimum cannot actually be booked.
    windows.window_length_nights >= windows.minimum_nights
        as is_bookable_window,

    listings.listing_name,
    listings.neighborhood,
    listings.property_type,
    listings.room_type,

    amenities.has_air_conditioning,
    amenities.has_lockbox,
    amenities.has_first_aid_kit,
    amenities.amenity_count

from windows
left join amenities on windows.listing_id = amenities.listing_id
left join listings on windows.listing_id = listings.listing_id
