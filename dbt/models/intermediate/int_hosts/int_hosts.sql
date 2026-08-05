-- depends_on: {{ ref('known_verification_methods') }}
with listings as (

    select *
    from {{ ref('int_listings') }}
    where not is_deleted

),

listing_performance as (

    -- Per-listing measures rebuilt from the daily grain rather than read from
    -- dim_listings, for the same no-mart-dependency reason. Kept to the columns
    -- this model actually aggregates.
    select
        listing_id,
        count(*) as calendar_days,
        count_if(not is_available) as booked_nights,
        coalesce(sum(revenue), 0) as total_revenue
    from {{ ref('int_listing_daily') }}
    group by all

),

reservation_performance as (

    select
        listing_id,
        count(*) as reservations,

        -- Censored reservations are excluded from the stay-length average only:
        -- their nights are truncated at the snapshot edge, so including them
        -- biases the average downward. The reservation COUNT keeps them, since
        -- those bookings really happened.
        avg(
            case
                when not (is_left_censored or is_right_censored) then nights
            end
        ) as avg_nights_per_stay
    from {{ ref('int_reservations') }}
    group by all

),

per_listing as (

    select
        listings.host_id,
        listings.listing_id,
        listings.host_name_masked,
        listings.host_since,
        listings.host_location,
        listings.list_price,
        listings.number_of_reviews,
        listings.review_scores_rating,
        coalesce(listing_performance.calendar_days, 0) as calendar_days,
        coalesce(listing_performance.booked_nights, 0) as booked_nights,
        coalesce(listing_performance.total_revenue, 0) as total_revenue,
        coalesce(reservation_performance.reservations, 0) as reservations,
        reservation_performance.avg_nights_per_stay

    from listings
    left join
        listing_performance
        on listings.listing_id = listing_performance.listing_id
    left join
        reservation_performance
        on listings.listing_id = reservation_performance.listing_id

),

verification_flags as (

    select
        host_id,
        count(*) as verification_count,
        array_agg(verification_method) as verification_list,

        -- One boolean per method in seeds/known_verification_methods.csv,
        -- generated rather than hardcoded
        --
        -- LT02/LT05 disabled for the loop body only, as in int_listing_daily:
        -- sqlfluff lints the compiled output, where the generated identifiers
        -- and indentation are set by Jinja whitespace control rather than by
        -- source formatting.
        -- noqa: disable=LT02,LT05
        {%- for method_name in get_flag_values('verification') %}
        boolor_agg(verification_method = {{ dbt.string_literal(dbt.escape_single_quotes(method_name)) }}) as {{ flag_name('verification', method_name) }}{{ "," if not loop.last }}
        {%- endfor %}
    -- noqa: enable=all
    from {{ ref('int_host_verifications') }}
    group by all

),

hosts as (

    select
        host_id,
        count(*) as listing_count,
        min(host_name_masked) as host_name_masked,
        min(host_since) as host_since,
        min(host_location) as host_location,
        sum(calendar_days) as calendar_days,
        sum(booked_nights) as booked_nights,
        sum(total_revenue) as total_revenue,
        sum(reservations) as reservations,
        div0(sum(booked_nights), sum(calendar_days)) as occupancy_rate,
        div0(
            sum(avg_nights_per_stay * reservations), sum(reservations)
        ) as avg_nights_per_stay,
        avg(list_price) as avg_list_price,
        sum(number_of_reviews) as total_reviews,
        avg(review_scores_rating) as avg_review_score
    from per_listing
    group by all

)

select
    hosts.*,
    verification_flags.* exclude (host_id)
from hosts
left join verification_flags on hosts.host_id = verification_flags.host_id
