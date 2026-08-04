{#
    Verified queries for business question 20 — does host tenure predict
    performance. Against sem_host_performance.

    Returns a list of {name, question, sql} entries. Several entries may share
    one query under different phrasings, because QUESTION is the surface a
    natural-language client matches an asked question against.

    WHY THE FIRST QUERY IS CTE-WRAPPED. host_tenure_years, revenue_per_listing
    and occupancy_rate are FACTS on this view, not dimensions, and Snowflake
    rejects FACTS and METRICS in the same SEMANTIC_VIEW clause - grouping there
    happens on dimensions only. So grouping by tenure means pulling the facts out
    at host grain and aggregating outside the clause. FACTS combines with
    DIMENSIONS only where the dimensions determine the facts; host_id is the
    primary key, so it does.

    The second query needs no wrapping: host_since IS a dimension. It is noisier,
    with a row per distinct join date, and that is the point - it makes the
    clustering visible rather than averaging it away.

    What these pin: tenure spans 9 to 14 years with host_since clustered in 2008
    to 2009, so there is almost no variance here to explain performance with. The
    honest answer to this question is that the data does not support one, and the
    phrasings are written to invite that rather than a correlation.

    Tenure is anchored to as_of_date, 2022-07-11. Neither query mentions
    current_date, which would drift on every run.

    Apostrophes are fine in either field - the dispatcher doubles them for the
    single-quoted SQL literal each is emitted into.
#}
{% macro verified_queries_q20(view=none) -%}

    {%- set view = view or this -%}

    {%- set by_tenure_sql -%}
with host_facts as (
    select *
    from semantic_view(
        {{ view }}
        dimensions host_id
        facts
            host_tenure_years,
            revenue_per_listing,
            occupancy_rate,
            listing_count
    )
)
select
    host_tenure_years,
    count(*) as hosts,
    sum(listing_count) as listings,
    round(avg(revenue_per_listing), 2) as avg_revenue_per_listing,
    round(avg(occupancy_rate), 4) as avg_occupancy_rate
from host_facts
group by all
order by host_tenure_years
    {%- endset -%}

    {%- set by_host_since_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        hosts,
        listings,
        avg_tenure_years,
        avg_revenue_per_listing,
        avg_occupancy_rate
    dimensions host_since
)
order by host_since
    {%- endset -%}

    {{ return([
        {
            'name': 'q20_a',
            'question': 'Does host tenure predict performance?',
            'sql': by_tenure_sql,
        },
        {
            'name': 'q20_b',
            'question': 'Do longer-tenured hosts earn more or have higher '
                        ~ 'occupancy?',
            'sql': by_tenure_sql,
        },
        {
            'name': 'q20_c',
            'question': 'Does a host\'s experience show up in their results?',
            'sql': by_tenure_sql,
        },
        {
            'name': 'q20_d',
            'question': 'When did our hosts join, and how does performance '
                        ~ 'vary by join date?',
            'sql': by_host_since_sql,
        },
    ]) }}
{%- endmacro %}
