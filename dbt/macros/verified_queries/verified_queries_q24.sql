{#
    Verified queries for business question 24 — which listings have gone stale,
    with no recent reviews. Against sem_listing_performance.

    Returns a list of {name, question, sql} entries. Several entries may share
    one query under different phrasings, because QUESTION is the surface a
    natural-language client matches an asked question against.

    THIS QUESTION IS THE REASON as_of_date EXISTS. The snapshot is a fixed window,
    so recency measured against current_date drifts on every run and every answer
    silently ages. days_since_last_review and months_since_last_review are
    anchored to as_of_date instead, and pinning them here is what keeps a client
    from writing datediff against current_date. It was filed as needing a new
    model for exactly this reason; the anchored facts on the view are that work.

    NEVER REVIEWED IS NOT STALE. last_review_date is NULL on listings that
    have no reviews at all, so days_since_last_review is NULL for them too - not a
    large number. Sorting descending on it puts NULLs first unless told otherwise,
    which reads as the stalest listings in the portfolio. Every entry here uses
    `nulls last` and returns has_reviews, so the two states stay distinguishable.

    days_since_last_review is a FACT, so the banded entry is CTE-wrapped at
    listing grain. The range runs to several years on the stalest listing, so the
    top band has to be open-ended.

    Apostrophes are fine in either field - the dispatcher doubles them for the
    single-quoted SQL literal each is emitted into.
#}
{% macro verified_queries_q24(view=none) -%}

    {%- set view = view or this -%}

    {%- set stalest_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        listing.avg_days_since_last_review,
        listing.total_reviews,
        listing.avg_occupancy_rate,
        listing.portfolio_revenue
    dimensions
        listing.listing_id,
        listing.listing_name,
        listing.neighborhood,
        listing.last_review_date,
        listing.has_reviews
    where listing.has_reviews and not listing.is_orphan_listing
)
order by avg_days_since_last_review desc nulls last
    {%- endset -%}

    {%- set never_reviewed_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        listing.listings,
        listing.avg_days_since_last_review,
        listing.stalest_days_since_review,
        listing.total_reviews,
        listing.avg_occupancy_rate
    dimensions listing.has_reviews
    where not listing.is_orphan_listing
)
order by has_reviews desc
    {%- endset -%}

    {%- set by_staleness_band_sql -%}
with listing_facts as (
    select *
    from semantic_view(
        {{ view }}
        dimensions
            listing.listing_id,
            listing.is_orphan_listing
        facts
            listing.months_since_last_review,
            listing.number_of_reviews,
            listing.occupancy_rate,
            listing.total_revenue
    )
)

select
    case
        when months_since_last_review is null then '0. never reviewed'
        when months_since_last_review <= 3 then '1. within 3 months'
        when months_since_last_review <= 12 then '2. 4 to 12 months'
        when months_since_last_review <= 36 then '3. 1 to 3 years'
        else '4. over 3 years'
    end as staleness_band,
    count(*) as listings,
    round(avg(number_of_reviews), 1) as avg_reviews,
    round(avg(occupancy_rate), 4) as avg_occupancy_rate,
    round(avg(total_revenue), 2) as avg_revenue
from listing_facts
where not is_orphan_listing
group by all
order by staleness_band
    {%- endset -%}

    {{ return([
        {
            'name': 'q24_a',
            'question': 'Which listings have gone stale with no recent '
                        ~ 'reviews?',
            'sql': stalest_sql,
        },
        {
            'name': 'q24_b',
            'question': 'Which listings have not been reviewed in a long time?',
            'sql': stalest_sql,
        },
        {
            'name': 'q24_c',
            'question': 'How long has it been since our listings were '
                        ~ 'reviewed?',
            'sql': by_staleness_band_sql,
        },
        {
            'name': 'q24_d',
            'question': 'Which listings have never been reviewed at all?',
            'sql': never_reviewed_sql,
        },
    ]) }}
{%- endmacro %}
