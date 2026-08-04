{#
    Verified queries for business question 18 — host portfolio performance,
    which hosts to invest in. Against sem_host_performance.

    Returns a list of {name, question, sql} entries. Several entries may share
    one query under different phrasings, because QUESTION is the surface a
    natural-language client matches an asked question against.

    What these pin, and the reason the question is worth pinning at all:

    - avg_revenue_per_listing rather than portfolio_revenue. Both are metrics
      here and only one answers "which host is doing well" - portfolio_revenue
      and avg_revenue_per_host scale with portfolio size by construction, so
      ranking on either returns the largest host rather than the best one.
    - host_name_masked never appears without host_id. 36 hosts hold 35 distinct
      names, so two share a hash and it is a grouping key rather than an
      identifier.

    The portfolio total carries listings, which sums to 49 and not 50 - the
    orphan listing has no host row. Pinning it here makes that the answer rather
    than a discrepancy somebody finds later.

    Top-N is an outer order by and limit around the closing paren. That is
    ordinary SQL, not a window function, so it needs no CTE.

    Apostrophes are fine in either field - the dispatcher doubles them for the
    single-quoted SQL literal each is emitted into.
#}
{% macro verified_queries_q18(view=none) -%}

    {%- set view = view or this -%}

    {%- set leaderboard_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        avg_revenue_per_listing,
        avg_occupancy_rate,
        listings,
        total_reservations,
        avg_length_of_stay
    dimensions
        host_id,
        host_name_masked,
        is_multi_listing_host
)
order by avg_revenue_per_listing desc
    {%- endset -%}

    {%- set top_ten_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        avg_revenue_per_listing,
        avg_occupancy_rate,
        listings,
        total_reservations
    dimensions
        host_id,
        host_name_masked
)
order by avg_revenue_per_listing desc
limit 10
    {%- endset -%}

    {%- set portfolio_total_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        hosts,
        listings,
        portfolio_revenue,
        avg_revenue_per_listing,
        occupancy_rate_weighted,
        avg_listings_per_host,
        max_listings_per_host
)
    {%- endset -%}

    {{ return([
        {
            'name': 'q18_a',
            'question': 'Which hosts should we invest in?',
            'sql': leaderboard_sql,
        },
        {
            'name': 'q18_b',
            'question': 'Who are our best performing hosts?',
            'sql': leaderboard_sql,
        },
        {
            'name': 'q18_c',
            'question': 'Rank hosts by revenue per listing',
            'sql': leaderboard_sql,
        },
        {
            'name': 'q18_d',
            'question': 'Show the top 10 hosts by revenue per listing',
            'sql': top_ten_sql,
        },
        {
            'name': 'q18_e',
            'question': 'How many hosts do we have and what do they earn?',
            'sql': portfolio_total_sql,
        },
    ]) }}
{%- endmacro %}
