{#
    Verified queries for business question 4 — occupancy rate by neighborhood
    and room type. Against sem_listing_performance.

    Returns a list of {name, question, sql} entries. Several entries may share
    one query under different phrasings, because QUESTION is the surface a
    natural-language client matches an asked question against.

    avg_occupancy_rate, not occupancy_rate_weighted. The two are IDENTICAL on
    this data, because calendar_days is the same for every listing, so picking
    either returns the same number today. The listing-weighted one is still the
    right name for comparing segments, and pinning it means these queries keep
    answering the question asked if the snapshot ever covers listings for unequal
    windows and the two start to diverge.

    listings rides along on every entry: some neighborhoods hold a single listing,
    so an occupancy average there is thin, and the base belongs next to it.

    is_orphan_listing filtered out. An orphan has NULL neighborhood and room
    type, so it would otherwise form a NULL group. Correct here because the
    question compares attributes, and wrong for a revenue total.

    Apostrophes are fine in either field - the dispatcher doubles them for the
    single-quoted SQL literal each is emitted into.
#}
{% macro verified_queries_q04(view=none) -%}

    {%- set view = view or this -%}

    {%- set by_neighborhood_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        listing.listings,
        listing.avg_occupancy_rate,
        listing.total_booked_nights,
        listing.total_available_nights
    dimensions listing.neighborhood
    where not listing.is_orphan_listing
)
order by avg_occupancy_rate desc
    {%- endset -%}

    {%- set by_room_type_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        listing.listings,
        listing.avg_occupancy_rate,
        listing.total_booked_nights,
        listing.total_available_nights
    dimensions listing.room_type
    where not listing.is_orphan_listing
)
order by avg_occupancy_rate desc
    {%- endset -%}

    {%- set by_both_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        listing.listings,
        listing.avg_occupancy_rate,
        listing.avg_achieved_rate
    dimensions
        listing.neighborhood,
        listing.room_type
    where not listing.is_orphan_listing
)
order by neighborhood, room_type
    {%- endset -%}

    {{ return([
        {
            'name': 'q04_a',
            'question': 'What is the occupancy rate by neighborhood?',
            'sql': by_neighborhood_sql,
        },
        {
            'name': 'q04_b',
            'question': 'Which neighborhoods have the highest occupancy?',
            'sql': by_neighborhood_sql,
        },
        {
            'name': 'q04_c',
            'question': 'What is the occupancy rate by room type?',
            'sql': by_room_type_sql,
        },
        {
            'name': 'q04_d',
            'question': 'Where does demand concentrate against where supply '
                        ~ 'sits?',
            'sql': by_both_sql,
        },
    ]) }}
{%- endmacro %}
