{#
    Verified queries for business question 11 — do review scores predict occupancy
    or a price premium. Against sem_listing_performance.

    Returns a list of {name, question, sql} entries. Several entries may share
    one query under different phrasings, because QUESTION is the surface a
    natural-language client matches an asked question against.

    Banding needs the CTE wrap: review_scores_rating and number_of_reviews are
    FACTS, and FACTS cannot share a SEMANTIC_VIEW clause with METRICS. Pulled at
    listing_id grain, which determines them, then banded outside.

    TWO KINDS OF MISSING, and the query keeps them apart. review_scores_rating is
    NULL on listings that have never been reviewed - which is not a low score,
    and averaging it as zero would invent one. The band expression gives those
    their own labelled bucket rather than dropping them silently, so the base is
    visible. has_reviews exists on the view for the same reason.

    Bands are fixed rather than quantiles so a band means the same thing between
    runs. The boundaries below are the query's own, not a claim about the current
    spread of scores.

    Both halves of the question are returned together - occupancy AND achieved
    rate - because "review investment pays" could mean either and the answer
    differs. The portfolio is a thin base for either claim, so listings rides
    along.

    Apostrophes are fine in either field - the dispatcher doubles them for the
    single-quoted SQL literal each is emitted into.
#}
{% macro verified_queries_q11(view=none) -%}

    {%- set view = view or this -%}

    {%- set by_score_band_sql -%}
with listing_facts as (
    select *
    from semantic_view(
        {{ view }}
        dimensions listing.listing_id
        facts
            listing.review_scores_rating,
            listing.number_of_reviews,
            listing.occupancy_rate,
            listing.achieved_nightly_rate,
            listing.total_revenue
    )
)

select
    case
        when review_scores_rating is null then '0. never reviewed'
        when review_scores_rating < 4.0 then '1. under 4.0'
        when review_scores_rating < 4.5 then '2. 4.0 to 4.49'
        when review_scores_rating < 4.8 then '3. 4.5 to 4.79'
        else '4. 4.8 and over'
    end as review_score_band,
    count(*) as listings,
    round(avg(number_of_reviews), 1) as avg_reviews,
    round(avg(occupancy_rate), 4) as avg_occupancy_rate,
    round(avg(achieved_nightly_rate), 2) as avg_achieved_rate,
    round(avg(total_revenue), 2) as avg_revenue
from listing_facts
group by all
order by review_score_band
    {%- endset -%}

    {%- set by_review_volume_sql -%}
with listing_facts as (
    select *
    from semantic_view(
        {{ view }}
        dimensions listing.listing_id
        facts
            listing.number_of_reviews,
            listing.occupancy_rate,
            listing.achieved_nightly_rate
    )
)

select
    case
        when number_of_reviews = 0 then '0. none'
        when number_of_reviews < 10 then '1. 1 to 9'
        when number_of_reviews < 50 then '2. 10 to 49'
        when number_of_reviews < 100 then '3. 50 to 99'
        else '4. 100 and over'
    end as review_count_band,
    count(*) as listings,
    round(avg(occupancy_rate), 4) as avg_occupancy_rate,
    round(avg(achieved_nightly_rate), 2) as avg_achieved_rate
from listing_facts
group by all
order by review_count_band
    {%- endset -%}

    {%- set per_listing_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        listing.avg_review_score,
        listing.total_reviews,
        listing.avg_occupancy_rate,
        listing.avg_achieved_rate
    dimensions
        listing.listing_id,
        listing.listing_name,
        listing.has_reviews
    where not listing.is_deleted
)
order by avg_review_score desc nulls last
    {%- endset -%}

    {{ return([
        {
            'name': 'q11_a',
            'question': 'Do review scores predict occupancy or a price '
                        ~ 'premium?',
            'sql': by_score_band_sql,
        },
        {
            'name': 'q11_b',
            'question': 'Do better-reviewed listings earn more?',
            'sql': by_score_band_sql,
        },
        {
            'name': 'q11_c',
            'question': 'Is investing in reviews worth it?',
            'sql': by_score_band_sql,
        },
        {
            'name': 'q11_d',
            'question': 'Does having more reviews go with higher occupancy?',
            'sql': by_review_volume_sql,
        },
        {
            'name': 'q11_e',
            'question': 'Show review score, occupancy and achieved rate for '
                        ~ 'every listing',
            'sql': per_listing_sql,
        },
    ]) }}
{%- endmacro %}
