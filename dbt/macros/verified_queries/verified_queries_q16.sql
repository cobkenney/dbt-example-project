{#
    Verified queries for business question 16 — do listings with high
    minimum_nights have worse occupancy. Against sem_listing_daily.

    Returns a list of {name, question, sql} entries. Several entries may share
    one query under different phrasings, because QUESTION is the surface a
    natural-language client matches an asked question against.

    The business point is that a minimum-stay rule trades turnover cost against
    lost bookings, and the question is whether the trade is worth it. Question 26
    answers the sharper version of the same thing - what the rule actually costs
    in unbookable windows - so both are on this view and the phrasings here stay
    on the correlation.

    TWO GRAINS, AND THEY DISAGREE IN MEANING.

    The night-grain entry bands the requirement as it stood on each night, which
    is the honest version: minimum_nights MOVES within a listing over the year,
    so a listing does not have one requirement to be classified by. It also
    weights by nights, which is what occupancy_rate is defined on.

    The listing-grain entry bands each listing by its own average requirement, so
    each listing counts once. That is what somebody asking about "high
    minimum_nights listings" pictures, and it is why avg_minimum_nights exists as
    a metric. It hides the within-listing variation the night grain shows.

    Neither is wrong; they answer different questions, and the phrasings are
    assigned to whichever matches. The band boundaries are the same in both so
    the two are readable side by side.

    minimum_nights is a FACT, so the night-grain banding needs the CTE wrap:
    Snowflake rejects FACTS and METRICS in one SEMANTIC_VIEW clause. FACTS
    combines with DIMENSIONS where the dimensions determine the facts, and
    calendar_id is the primary key - so listing_id plus calendar_date pulls the
    fact at its own grain and the banding happens outside.

    Apostrophes are fine in either field - the dispatcher doubles them for the
    single-quoted SQL literal each is emitted into.
#}
{% macro verified_queries_q16(view=none) -%}

    {%- set view = view or this -%}

    {%- set by_night_sql -%}
with nights as (
    select *
    from semantic_view(
        {{ view }}
        dimensions
            daily.listing_id,
            daily.calendar_date,
            daily.is_available
        facts
            daily.minimum_nights,
            daily.price,
            daily.revenue
    )
)

select
    case
        when minimum_nights = 1 then '1. one night'
        when minimum_nights <= 3 then '2. 2 to 3 nights'
        when minimum_nights <= 7 then '3. 4 to 7 nights'
        when minimum_nights <= 30 then '4. 8 to 30 nights'
        else '5. over 30 nights'
    end as minimum_nights_band,
    count(distinct listing_id) as listings,
    count(*) as calendar_nights,
    count_if(not is_available) as booked_nights,
    round(div0(count_if(not is_available), count(*)), 4) as occupancy_rate,
    round(avg(price), 2) as avg_nightly_price,
    round(avg(revenue), 2) as achieved_nightly_rate,
    round(sum(revenue), 2) as total_revenue
from nights
group by all
order by minimum_nights_band
    {%- endset -%}

    {%- set by_listing_sql -%}
with per_listing as (
    select *
    from semantic_view(
        {{ view }}
        metrics
            daily.avg_minimum_nights,
            daily.max_minimum_nights,
            daily.occupancy_rate,
            daily.avg_nightly_price,
            daily.achieved_nightly_rate,
            daily.total_revenue
        dimensions daily.listing_id
    )
)

select
    case
        when avg_minimum_nights = 1 then '1. one night'
        when avg_minimum_nights <= 3 then '2. 2 to 3 nights'
        when avg_minimum_nights <= 7 then '3. 4 to 7 nights'
        when avg_minimum_nights <= 30 then '4. 8 to 30 nights'
        else '5. over 30 nights'
    end as minimum_nights_band,
    count(*) as listings,
    round(avg(avg_minimum_nights), 2) as avg_minimum_nights,
    round(avg(occupancy_rate), 4) as avg_occupancy_rate,
    round(avg(avg_nightly_price), 2) as avg_nightly_price,
    round(avg(achieved_nightly_rate), 2) as avg_achieved_rate,
    round(avg(total_revenue), 2) as avg_revenue
from per_listing
group by all
order by minimum_nights_band
    {%- endset -%}

    {%- set scatter_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        daily.avg_minimum_nights,
        daily.max_minimum_nights,
        daily.occupancy_rate,
        daily.avg_nightly_price,
        daily.total_revenue
    dimensions
        daily.listing_id,
        listing.listing_name,
        listing.room_type
    where not daily.is_deleted
)
order by avg_minimum_nights desc
    {%- endset -%}

    {{ return([
        {
            'name': 'q16_a',
            'question': 'Do listings with a high minimum stay have worse '
                        ~ 'occupancy?',
            'sql': by_listing_sql,
        },
        {
            'name': 'q16_b',
            'question': 'Is our minimum-stay policy costing us bookings?',
            'sql': by_listing_sql,
        },
        {
            'name': 'q16_c',
            'question': 'Compare occupancy and nightly rate across '
                        ~ 'minimum-stay requirements',
            'sql': by_night_sql,
        },
        {
            'name': 'q16_d',
            'question': 'How does occupancy differ on nights with a long '
                        ~ 'minimum stay?',
            'sql': by_night_sql,
        },
        {
            'name': 'q16_e',
            'question': 'Show the minimum stay and occupancy for every listing',
            'sql': scatter_sql,
        },
    ]) }}
{%- endmacro %}
