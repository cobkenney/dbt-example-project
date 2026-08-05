-- Guards the grain reduction in int_listing_amenities.
--
-- That model keeps only each listing's latest amenity snapshot. Collapsing
-- history that way is only correct while every changelog event predates the
-- calendar window — otherwise a booked night would be attributed to an amenity
-- set the listing did not yet have, silently corrupting amenity revenue
-- analysis.
{{ config(severity='warn') }}

with calendar_window as (

    select min(calendar_date) as window_opens_at
    from {{ ref('stg_calendar') }}

)

select
    changelog.listing_id,
    changelog.changed_at,
    calendar_window.window_opens_at
from {{ ref('stg_amenities_changelog') }} as changelog
cross join calendar_window
where changelog.changed_at >= calendar_window.window_opens_at
