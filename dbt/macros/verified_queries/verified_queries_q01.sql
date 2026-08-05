{#
    Verified queries for business question 1 — share of monthly revenue from
    listings without air conditioning. Against sem_listing_daily.

    Returns a list of {name, question, sql} entries. Several entries may share
    one query under different phrasings, because QUESTION is the surface a
    natural-language client matches an asked question against.

    THE DELETED LISTING IS DELIBERATELY LEFT IN. This is a revenue total, and an
    deleted listing carries real booked revenue. The deleted listing here also has air
    conditioning, so filtering it out strips revenue from the AC segment and
    pushes the no-AC share up - a different answer to the question
    asked, from a filter that looks like hygiene. The comparison here is on an
    amenity flag carried by the daily fact, not on a listing attribute, so the
    NULL-descriptive-columns reason for excluding it does not apply.

    ratio_to_report rather than a metric: the share is within a month, and a
    percentage of a partition is a window function, which no semantic view can
    express. Hence the CTE wrap - the SEMANTIC_VIEW clause supplies the revenue
    per month per segment and the outer query does the division.

    month_start_date, not date_trunc on calendar_date. Precomputed on the fact
    exactly so a monthly grouping cannot be got subtly wrong, and the view says
    so in AI_SQL_GENERATION.

    booked_nights rides along, because a segment share moves on volume as much as
    on rate and the reader needs to see which.

    Apostrophes are fine in either field - the dispatcher doubles them for the
    single-quoted SQL literal each is emitted into.
#}
{% macro verified_queries_q01(view=none) -%}

    {%- set view = view or this -%}

    {%- set by_month_sql -%}
with monthly as (
    select *
    from semantic_view(
        {{ view }}
        metrics
            daily.total_revenue,
            daily.booked_nights,
            daily.listings
        dimensions
            daily.month_start_date,
            daily.has_air_conditioning
    )
)

select
    month_start_date,
    has_air_conditioning,
    listings,
    booked_nights,
    total_revenue,
    round(
        100 * ratio_to_report(total_revenue) over (
            partition by month_start_date
        ),
        1
    ) as pct_of_month_revenue
from monthly
order by month_start_date, has_air_conditioning
    {%- endset -%}

    {%- set full_year_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        daily.total_revenue,
        daily.booked_nights,
        daily.occupancy_rate,
        daily.achieved_nightly_rate,
        daily.listings
    dimensions daily.has_air_conditioning
)
order by has_air_conditioning
    {%- endset -%}

    {{ return([
        {
            'name': 'q01_a',
            'question': 'What share of monthly revenue comes from listings '
                        ~ 'without air conditioning?',
            'sql': by_month_sql,
        },
        {
            'name': 'q01_b',
            'question': 'How much revenue do listings without AC bring in each '
                        ~ 'month?',
            'sql': by_month_sql,
        },
        {
            'name': 'q01_c',
            'question': 'Is the lack of air conditioning costing us money?',
            'sql': by_month_sql,
        },
        {
            'name': 'q01_d',
            'question': 'Compare listings with and without air conditioning on '
                        ~ 'revenue, occupancy and nightly rate',
            'sql': full_year_sql,
        },
    ]) }}
{%- endmacro %}
