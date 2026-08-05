with daily as (

    select * from {{ ref('int_listing_daily') }}

)

select
    calendar_id,
    listing_id,
    calendar_date,
    date_trunc('month', calendar_date)::date as month_start_date,
    is_available,
    reservation_id,
    price,
    revenue,
    minimum_nights,
    maximum_nights,
    is_window_start,
    availability_window_seq,
    neighborhood,
    property_type,
    room_type,
    accommodates,
    bedrooms,
    beds,
    host_id,
    has_air_conditioning,
    has_lockbox,
    has_first_aid_kit,
    amenity_count,
    is_deleted

from daily
