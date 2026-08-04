-- Reservation volume and length of stay — the questions fct_reservations was
-- built for and the daily grain cannot answer.
--
-- Verified: 1,565 reservations across 10,059 booked nights, average length of
-- stay 6.49 nights, average booking value $1,076.59.
--
-- Note the is_censored filter on the length-of-stay measures. 70 reservations
-- touch an edge of the calendar snapshot, so their nights are truncated;
-- including them pulls average stay from 6.49 down to 6.43. Counts and revenue
-- deliberately do NOT filter — those reservations really happened and their
-- revenue is real, it is only their *length* that is unknown.
select
    neighborhood,

    count(*) as reservations,
    sum(nights) as booked_nights,
    round(sum(reservation_revenue), 2) as total_revenue,

    -- Length of stay over complete reservations only.
    round(avg(case when not is_censored then nights end), 2)
        as avg_length_of_stay,
    count_if(is_censored) as censored_reservations,

    round(avg(reservation_revenue), 2) as avg_booking_value,
    round(avg(avg_nightly_price), 2) as avg_nightly_rate
from {{ ref('fct_reservations') }}
group by all
order by total_revenue desc
