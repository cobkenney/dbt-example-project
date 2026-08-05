-- Guards the grain reduction in int_reservations.
--
-- That model collapses booked calendar nights into one row per reservation. The
-- reduction is only lossless if every booked night lands in exactly one
-- reservation and its revenue survives the group by — so total nights and total
-- revenue must reconcile against the daily grain they came from.
--
-- Catches a whole class of regression at once: a group by that drops rows, an
-- id that starts colliding in a new way, or a revenue change applied to one
-- model and not the other. Cheaper and broader than asserting each separately.
with daily as (

    select
        count(*) as booked_nights,
        sum(revenue) as booked_revenue
    from {{ ref('int_listing_daily') }}
    where reservation_id is not null

),

reservations as (

    select
        sum(nights) as booked_nights,
        sum(reservation_revenue) as booked_revenue
    from {{ ref('int_reservations') }}

)

select
    daily.booked_nights as daily_nights,
    reservations.booked_nights as reservation_nights,
    daily.booked_revenue as daily_revenue,
    reservations.booked_revenue as reservation_revenue
from daily
cross join reservations
where
    daily.booked_nights != reservations.booked_nights
    or daily.booked_revenue != reservations.booked_revenue
