{#
    Verified queries for business question 24 — length-of-stay distribution by
    neighborhood and room type. Against sem_reservations.

    Returns a list of {name, question, sql} entries. Several entries may share
    one query under different phrasings, because QUESTION is the surface a
    natural-language client matches an asked question against.

    Two things these entries exist to pin:

    - The length measures come from avg_length_of_stay and
      median_length_of_stay, which exclude the censored reservations by
      construction. censored_reservations rides along so the reader can see how
      much was dropped from each group.
    - is_orphan_listing is filtered out. An orphan has no listings row, so
      its neighborhood and room_type are NULL and it would otherwise show up as
      an unnamed group. Filtering it is correct here because the question
      compares attributes, and wrong for a revenue total.

    Apostrophes are fine in either field - the dispatcher doubles them for the
    single-quoted SQL literal each is emitted into.
#}
{% macro verified_queries_q24(view=none) -%}

    {%- set view = view or this -%}

    {%- set by_neighborhood_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        reservations,
        booked_nights,
        avg_length_of_stay,
        median_length_of_stay,
        max_length_of_stay,
        censored_reservations
    dimensions neighborhood
    where not is_orphan_listing
)
order by avg_length_of_stay desc
    {%- endset -%}

    {%- set by_room_type_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        reservations,
        booked_nights,
        avg_length_of_stay,
        median_length_of_stay,
        max_length_of_stay,
        censored_reservations
    dimensions room_type
    where not is_orphan_listing
)
order by avg_length_of_stay desc
    {%- endset -%}

    {%- set by_neighborhood_room_type_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        reservations,
        avg_length_of_stay,
        median_length_of_stay,
        censored_reservations
    dimensions
        neighborhood,
        room_type
    where not is_orphan_listing
)
order by neighborhood, room_type
    {%- endset -%}

    {{ return([
        {
            'name': 'q24_a',
            'question': 'What is the length-of-stay distribution by '
                        ~ 'neighborhood?',
            'sql': by_neighborhood_sql,
        },
        {
            'name': 'q24_b',
            'question': 'Which neighborhoods attract the longest stays?',
            'sql': by_neighborhood_sql,
        },
        {
            'name': 'q24_c',
            'question': 'What is the length-of-stay distribution by room '
                        ~ 'type?',
            'sql': by_room_type_sql,
        },
        {
            'name': 'q24_d',
            'question': 'Do entire homes get longer stays than private rooms?',
            'sql': by_room_type_sql,
        },
        {
            'name': 'q24_e',
            'question': 'Show average and median length of stay by '
                        ~ 'neighborhood and room type',
            'sql': by_neighborhood_room_type_sql,
        },
    ]) }}
{%- endmacro %}
