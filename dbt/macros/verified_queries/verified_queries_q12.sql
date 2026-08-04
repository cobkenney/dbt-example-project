{#
    Verified queries for business question 12 — revenue per guest of capacity.
    Against sem_listing_performance.

    Returns a list of {name, question, sql} entries. Several entries may share
    one query under different phrasings, because QUESTION is the surface a
    natural-language client matches an asked question against.

    avg_revenue_per_guest is the named metric, built on a fact that already
    guards the denominator with nullif(accommodates, 0). A client dividing
    total_revenue by accommodates itself gets a division error or an infinity on
    any listing recording zero capacity; this metric returns NULL for it.

    Note this is NOT the same normalization as question 22, which divides the
    nightly PRICE by bedrooms and beds in sem_listing_daily. Capacity is the
    clean denominator of the three - accommodates has no NULLs or zeros in this
    data, where bedrooms goes NULL on some listings and beds goes to 0 on others.

    accommodates is a dimension here, so grouping by it needs no CTE.

    Apostrophes are fine in either field - the dispatcher doubles them for the
    single-quoted SQL literal each is emitted into.
#}
{% macro verified_queries_q12(view=none) -%}

    {%- set view = view or this -%}

    {%- set by_capacity_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        listing.listings,
        listing.avg_revenue_per_guest,
        listing.avg_revenue_per_listing,
        listing.avg_occupancy_rate,
        listing.avg_achieved_rate
    dimensions listing.accommodates
    where not listing.is_orphan_listing
)
order by accommodates
    {%- endset -%}

    {%- set by_listing_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        listing.avg_revenue_per_guest,
        listing.portfolio_revenue,
        listing.avg_occupancy_rate
    dimensions
        listing.listing_id,
        listing.listing_name,
        listing.accommodates,
        listing.room_type
    where not listing.is_orphan_listing
)
order by avg_revenue_per_guest desc
    {%- endset -%}

    {%- set by_room_type_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        listing.listings,
        listing.avg_revenue_per_guest,
        listing.avg_revenue_per_listing
    dimensions listing.room_type
    where not listing.is_orphan_listing
)
order by avg_revenue_per_guest desc
    {%- endset -%}

    {{ return([
        {
            'name': 'q12_a',
            'question': 'What is the revenue per guest of capacity?',
            'sql': by_capacity_sql,
        },
        {
            'name': 'q12_b',
            'question': 'Which listings earn the most per guest they sleep?',
            'sql': by_listing_sql,
        },
        {
            'name': 'q12_c',
            'question': 'Do larger listings earn proportionally more than '
                        ~ 'small ones?',
            'sql': by_capacity_sql,
        },
        {
            'name': 'q12_d',
            'question': 'Compare revenue per guest by room type',
            'sql': by_room_type_sql,
        },
    ]) }}
{%- endmacro %}
