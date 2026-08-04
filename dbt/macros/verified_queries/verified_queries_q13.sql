{#
    Verified queries for business question 13 — the shared-bathroom penalty on
    price and occupancy. Against sem_listing_performance.

    Returns a list of {name, question, sql} entries. Several entries may share
    one query under different phrasings, because QUESTION is the surface a
    natural-language client matches an asked question against.

    is_shared_bathroom is a dimension, so the split is a plain query.

    THE BASE IS 9 SHARED AGAINST 39 PRIVATE, so listings rides along on every
    entry. That is a renovation case worth quantifying and a base too small to
    call a penalty precisely, and a client that reports the gap without the
    counts has dropped the more important half.

    The confound is worth knowing before the number is used: shared bathrooms sit
    disproportionately on private rooms rather than entire homes, so a raw split
    partly measures room type. The second entry breaks the same comparison out
    within room_type, which is as far as 9 listings can be pushed.

    bathrooms - the COUNT - is a separate column and does not indicate sharing.
    These entries name is_shared_bathroom only, so a client does not conclude that
    a 1.0-bathroom listing is a shared one.

    Apostrophes are fine in either field - the dispatcher doubles them for the
    single-quoted SQL literal each is emitted into.
#}
{% macro verified_queries_q13(view=none) -%}

    {%- set view = view or this -%}

    {%- set split_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        listing.listings,
        listing.avg_list_price,
        listing.avg_achieved_rate,
        listing.avg_occupancy_rate,
        listing.avg_revenue_per_listing,
        listing.avg_review_score
    dimensions listing.is_shared_bathroom
    where not listing.is_orphan_listing
)
order by is_shared_bathroom
    {%- endset -%}

    {%- set by_room_type_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        listing.listings,
        listing.avg_list_price,
        listing.avg_achieved_rate,
        listing.avg_occupancy_rate
    dimensions
        listing.room_type,
        listing.is_shared_bathroom
    where not listing.is_orphan_listing
)
order by room_type, is_shared_bathroom
    {%- endset -%}

    {{ return([
        {
            'name': 'q13_a',
            'question': 'What is the penalty for a shared bathroom on price '
                        ~ 'and occupancy?',
            'sql': split_sql,
        },
        {
            'name': 'q13_b',
            'question': 'Do listings with shared bathrooms earn less?',
            'sql': split_sql,
        },
        {
            'name': 'q13_c',
            'question': 'Would it be worth renovating the shared bathrooms?',
            'sql': split_sql,
        },
        {
            'name': 'q13_d',
            'question': 'Compare shared and private bathrooms within each '
                        ~ 'room type',
            'sql': by_room_type_sql,
        },
    ]) }}
{%- endmacro %}
