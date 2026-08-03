-- Guards the grain reduction in int_amenities_current.
--
-- That model keeps only each listing's latest amenity snapshot. Collapsing
-- history that way is only correct while every changelog event predates the
-- calendar window — otherwise a booked night would be attributed to an amenity
-- set the listing did not yet have, silently corrupting amenity revenue
-- analysis.
--
-- Today the newest event is 2021-07-06 and the calendar opens 2021-07-12, so
-- this returns no rows. If a newer amenity event is ever loaded, this fails and
-- int_amenities_current must become an SCD2 model (valid_from/valid_to via
-- lead() — each changelog row already carries a full snapshot, not a delta).
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
