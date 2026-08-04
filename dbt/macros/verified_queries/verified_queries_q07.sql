{#
    Verified queries for business question 7 — revenue concentration, the share
    from the top 5 listings. Against sem_listing_performance.

    Returns a list of {name, question, sql} entries. Several entries may share
    one query under different phrasings, because QUESTION is the surface a
    natural-language client matches an asked question against.

    THIS QUESTION HAS NO METRIC, deliberately, and the view says so where the
    metric would have been. A share of total needs a window function or a rank,
    which a semantic view cannot express. So this is the CTE-wrapped form the
    view comment promises: pull revenue at listing grain through the view, then
    rank and total outside it. A CTE wrapping SEMANTIC_VIEW(...) is allowed.

    Ranking outside is the whole point of the entry. Without it a client asking
    for concentration either gets refused or reaches for some adjacent metric -
    max_revenue, or an average - and reports it as the answer.

    The orphan listing is LEFT IN. This is a revenue total, and an orphan carries
    real booked revenue; excluding it would understate the denominator and
    overstate every share. That is the opposite of the choice q04 makes, and the
    reason is that this question totals rather than compares attributes.

    Apostrophes are fine in either field - the dispatcher doubles them for the
    single-quoted SQL literal each is emitted into.
#}
{% macro verified_queries_q07(view=none) -%}

    {%- set view = view or this -%}

    {%- set concentration_sql -%}
with listing_revenue as (
    select *
    from semantic_view(
        {{ view }}
        metrics listing.portfolio_revenue
        dimensions
            listing.listing_id,
            listing.listing_name
    )
),

ranked as (
    select
        listing_id,
        listing_name,
        portfolio_revenue,
        row_number() over (order by portfolio_revenue desc) as revenue_rank,
        sum(portfolio_revenue) over () as total_revenue
    from listing_revenue
)

select
    listing_id,
    listing_name,
    round(portfolio_revenue, 2) as revenue,
    revenue_rank,
    round(100 * portfolio_revenue / nullif(total_revenue, 0), 2)
        as pct_of_total,
    round(
        100 * sum(portfolio_revenue) over (order by revenue_rank)
        / nullif(total_revenue, 0),
        2
    ) as running_pct_of_total
from ranked
order by revenue_rank
    {%- endset -%}

    {%- set top_five_share_sql -%}
with listing_revenue as (
    select *
    from semantic_view(
        {{ view }}
        metrics listing.portfolio_revenue
        dimensions listing.listing_id
    )
),

ranked as (
    select
        portfolio_revenue,
        row_number() over (order by portfolio_revenue desc) as revenue_rank
    from listing_revenue
)

select
    count(*) as listings,
    round(sum(portfolio_revenue), 2) as total_revenue,
    round(sum(case when revenue_rank <= 5 then portfolio_revenue end), 2)
        as top_5_revenue,
    round(
        100 * sum(case when revenue_rank <= 5 then portfolio_revenue end)
        / nullif(sum(portfolio_revenue), 0),
        2
    ) as top_5_pct_of_total
from ranked
    {%- endset -%}

    {{ return([
        {
            'name': 'q07_a',
            'question': 'What share of revenue comes from the top 5 listings?',
            'sql': top_five_share_sql,
        },
        {
            'name': 'q07_b',
            'question': 'How concentrated is our revenue?',
            'sql': concentration_sql,
        },
        {
            'name': 'q07_c',
            'question': 'Rank listings by revenue and show each share of the '
                        ~ 'total',
            'sql': concentration_sql,
        },
        {
            'name': 'q07_d',
            'question': 'If we lost our biggest listing, how much revenue '
                        ~ 'would that be?',
            'sql': concentration_sql,
        },
    ]) }}
{%- endmacro %}
