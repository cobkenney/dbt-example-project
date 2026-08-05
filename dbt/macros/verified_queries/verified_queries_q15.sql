{#
    Verified queries for business question 15 — how often a listing changes its
    nightly price. Against sem_listing_daily.

    Returns a list of {name, question, sql} entries. Several entries may share
    one query under different phrasings, because QUESTION is the surface a
    natural-language client matches an asked question against.

    distinct_prices is the whole answer, and it is a count of distinct RATES, not
    a count of CHANGES. A listing that alternates between two rates all year
    reports 2, the same as one that moved once and stayed. The gap between the two
    readings needs lag over calendar_date, which no semantic view can express -
    so this measures price VARIETY and the phrasings are written to promise that
    rather than a change frequency. distinct_prices = 1 is the unambiguous end:
    the rate never moved at all.

    min and max nightly price ride along to give the variety a size. Ten distinct
    rates within a few dollars of each other is noise; ten spanning hundreds is a
    pricing strategy, and the count alone cannot tell them apart.

    The banding entry sorts hosts into set-and-forget against dynamic, which is
    what the question is for. Bands are on the distinct-rate count, which is a
    METRIC here rather than a fact - so the CTE wrap is to band an aggregate,
    not to dodge the facts-with-metrics restriction.

    is_deleted is not filtered from the per-listing entries: a deleted listing has
    a price series like any other listing and the grouping key is listing_id, so
    its NULL attributes never surface. The room-type cross does filter them.

    Apostrophes are fine in either field - the dispatcher doubles them for the
    single-quoted SQL literal each is emitted into.
#}
{% macro verified_queries_q15(view=none) -%}

    {%- set view = view or this -%}

    {%- set by_listing_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        daily.distinct_prices,
        daily.min_nightly_price,
        daily.max_nightly_price,
        daily.avg_nightly_price,
        daily.achieved_nightly_rate,
        daily.occupancy_rate
    dimensions
        daily.listing_id,
        listing.listing_name
)
order by distinct_prices desc
    {%- endset -%}

    {%- set banded_sql -%}
with per_listing as (
    select *
    from semantic_view(
        {{ view }}
        metrics
            daily.distinct_prices,
            daily.min_nightly_price,
            daily.max_nightly_price,
            daily.occupancy_rate,
            daily.total_revenue
        dimensions daily.listing_id
    )
)

select
    case
        when distinct_prices = 1 then '1. never changed'
        when distinct_prices <= 5 then '2. 2 to 5 rates'
        when distinct_prices <= 20 then '3. 6 to 20 rates'
        else '4. over 20 rates'
    end as pricing_style,
    count(*) as listings,
    round(avg(distinct_prices), 1) as avg_distinct_prices,
    round(avg(max_nightly_price - min_nightly_price), 2) as avg_price_spread,
    round(avg(occupancy_rate), 4) as avg_occupancy_rate,
    round(avg(total_revenue), 2) as avg_revenue
from per_listing
group by all
order by pricing_style
    {%- endset -%}

    {#- Wrapped so the filter on distinct_prices sits in a WHERE. The metric is -#}
    {#- an aggregate, and SEMANTIC_VIEW takes no HAVING - its own WHERE filters -#}
    {#- rows before aggregation, which is the wrong side of the group here. -#}
    {%- set static_pricers_sql -%}
with per_listing as (
    select *
    from semantic_view(
        {{ view }}
        metrics
            daily.distinct_prices,
            daily.avg_nightly_price,
            daily.occupancy_rate,
            daily.total_revenue
        dimensions
            daily.listing_id,
            listing.listing_name,
            listing.room_type
        where not daily.is_deleted
    )
)

select *
from per_listing
where distinct_prices = 1
order by total_revenue desc
    {%- endset -%}

    {{ return([
        {
            'name': 'q15_a',
            'question': 'How many different nightly rates does each listing '
                        ~ 'use?',
            'sql': by_listing_sql,
        },
        {
            'name': 'q15_b',
            'question': 'Which listings move their price the most?',
            'sql': by_listing_sql,
        },
        {
            'name': 'q15_c',
            'question': 'Which hosts use dynamic pricing and which are '
                        ~ 'set-and-forget?',
            'sql': banded_sql,
        },
        {
            'name': 'q15_d',
            'question': 'Does moving your price around lead to better '
                        ~ 'occupancy?',
            'sql': banded_sql,
        },
        {
            'name': 'q15_e',
            'question': 'Which listings never changed their price all year?',
            'sql': static_pricers_sql,
        },
    ]) }}
{%- endmacro %}
