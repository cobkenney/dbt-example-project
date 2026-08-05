-- depends_on: {{ ref('known_amenity_names') }}
with calendar as (

    select * from {{ ref('stg_calendar') }}

),

listings as (

    select * from {{ ref('int_listings') }}

),

amenities as (

    select
        listing_id,
        count(distinct amenity_name) as amenity_count,
        array_agg(distinct amenity_name) as amenity_list,

        -- LT02/LT05 disabled for the loop body only. sqlfluff lints the
        -- compiled output, where the longest generated identifier overruns the
        -- 80-char limit on its own, and the loop's indentation is set by Jinja
        -- whitespace control rather than by source layout.
        -- noqa: disable=LT02,LT05
        {%- for amenity_name in get_flag_values('amenity') %}
        boolor_agg(amenity_name = {{ dbt.string_literal(dbt.escape_single_quotes(amenity_name)) }}) as {{ flag_name('amenity', amenity_name) }}{{ "," if not loop.last }}
        {%- endfor %}
    -- noqa: enable=all
    from {{ ref('int_listing_amenities') }}
    group by all

),

joined as (

    select
        calendar.calendar_id,
        calendar.listing_id,
        calendar.calendar_date,
        calendar.is_available,
        calendar.reservation_id,
        calendar.price,
        calendar.minimum_nights,
        calendar.maximum_nights,
        -- Revenue only accrues on nights that are actually booked.
        case
            when not calendar.is_available then calendar.price
        end as revenue,
        listings.listing_name,
        listings.neighborhood,
        listings.property_type,
        listings.room_type,
        listings.accommodates,
        listings.bedrooms,
        listings.beds,
        listings.host_id,
        listings.is_deleted,
        amenities.* exclude (listing_id)

    from calendar
    left join listings on calendar.listing_id = listings.listing_id
    left join amenities on calendar.listing_id = amenities.listing_id

),

window_starts as (

    -- Marks the first available night of each contiguous run of available
    -- nights. Assumes contiguous calendar per listing.
    -- coalesce, not `is not true`: lag is NULL on each listing's first row, and
    -- without the default that row is never a window start even when available.

    select
        *,
        is_available
        and not coalesce(
            lag(is_available) over (
                partition by listing_id order by calendar_date
            ),
            false
        ) as is_window_start
    from joined

),

sequenced as (

    -- Running count of windows started so far, so the value is constant across
    -- every night of one window and identifies it.

    select
        *,
        sum(case when is_window_start then 1 else 0 end) over (
            partition by listing_id
            order by calendar_date
            rows between unbounded preceding and current row
        ) as availability_window_seq
    from window_starts

)

select * from sequenced
