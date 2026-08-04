{#
    Verified queries for business question 6 — revenue seasonality across the
    portfolio. Against sem_listing_daily.

    Returns a list of {name, question, sql} entries. Several entries may share
    one query under different phrasings, because QUESTION is the surface a
    natural-language client matches an asked question against.

    The plainest question this view answers, and the one most likely to be asked
    first, so it gets several phrasings rather than several queries.

    THE MONTH IS NOT A SEASON. The window is a fixed year that does not start on
    a month boundary, so its first and last calendar month are the SAME month of
    the year and both halves are partial.
    Grouping by month name to get "seasonality" therefore double-counts that
    partial month against itself. month_start_date keeps the two apart, and
    calendar_nights
    is returned next to revenue so a short month is visible as a short month
    rather than read as a downturn. occupancy_rate and achieved_nightly_rate are
    the two figures that are actually comparable across months, since both are
    per-night.

    No orphan filter: this is a revenue total, and an orphan carries real
    booked revenue. Nothing here groups on a listing attribute, so its NULLs
    never form a group.

    month_start_date, not date_trunc on calendar_date - precomputed on the fact
    exactly so a monthly grouping cannot be got subtly wrong.

    Apostrophes are fine in either field - the dispatcher doubles them for the
    single-quoted SQL literal each is emitted into.
#}
{% macro verified_queries_q06(view=none) -%}

    {%- set view = view or this -%}

    {%- set by_month_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        daily.total_revenue,
        daily.calendar_nights,
        daily.booked_nights,
        daily.occupancy_rate,
        daily.achieved_nightly_rate,
        daily.avg_nightly_price,
        daily.listings
    dimensions daily.month_start_date
)
order by month_start_date
    {%- endset -%}

    {%- set by_month_and_neighborhood_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        daily.total_revenue,
        daily.occupancy_rate,
        daily.achieved_nightly_rate,
        daily.listings
    dimensions
        daily.month_start_date,
        listing.neighborhood
    where not daily.is_orphan_listing
)
order by neighborhood, month_start_date
    {%- endset -%}

    {{ return([
        {
            'name': 'q06_a',
            'question': 'How does revenue vary by month?',
            'sql': by_month_sql,
        },
        {
            'name': 'q06_b',
            'question': 'What does revenue seasonality look like across the '
                        ~ 'portfolio?',
            'sql': by_month_sql,
        },
        {
            'name': 'q06_c',
            'question': 'Which months are our busiest and which are slowest?',
            'sql': by_month_sql,
        },
        {
            'name': 'q06_d',
            'question': 'When should we plan for peak cleaning and staffing '
                        ~ 'demand?',
            'sql': by_month_sql,
        },
        {
            'name': 'q06_e',
            'question': 'Do neighborhoods peak in different months?',
            'sql': by_month_and_neighborhood_sql,
        },
    ]) }}
{%- endmacro %}
