{#
    Verified queries for business question 17 — bookings, average length of
    stay, rate per booking. Against sem_reservations.

    Returns a list of {name, question, sql} entries. Several entries may share
    one query under different phrasings, because QUESTION is the surface a
    natural-language client matches an asked question against.

    The SQL is written against the view's own metrics, in the explicit
    SEMANTIC_VIEW(...) form — a metric cannot be selected from the view by
    name. Whichever entry a client picks, avg_length_of_stay already excludes
    the 70 censored reservations, which is the whole point of pinning this
    question: averaging the nights fact directly is the plausible wrong answer.

    Verified figures: 1,565 reservations, 10,059 booked nights, 6.49 nights
    average stay (6.43 including censored), $1,076.59 average booking value,
    70 censored.

    Apostrophes are fine in either field - the dispatcher doubles them for the
    single-quoted SQL literal each is emitted into.
#}
{% macro verified_queries_q17(view=none) -%}

    {%- set view = view or this -%}

    {%- set summary_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        reservations,
        booked_nights,
        total_revenue,
        avg_length_of_stay,
        avg_booking_value,
        avg_nightly_rate,
        censored_reservations
)
    {%- endset -%}

    {%- set by_month_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        reservations,
        booked_nights,
        avg_length_of_stay,
        avg_booking_value
    dimensions check_in_month
)
order by check_in_month
    {%- endset -%}

    {%- set censoring_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        reservations,
        censored_reservations,
        avg_length_of_stay,
        avg_length_of_stay_all
)
    {%- endset -%}

    {{ return([
        {
            'name': 'q17_a',
            'question': 'How many bookings were there, how long was the '
                        ~ 'average stay, and what was a booking worth?',
            'sql': summary_sql,
        },
        {
            'name': 'q17_b',
            'question': 'What is the average length of stay?',
            'sql': summary_sql,
        },
        {
            'name': 'q17_c',
            'question': 'How many reservations do we have and how many '
                        ~ 'nights were booked?',
            'sql': summary_sql,
        },
        {
            'name': 'q17_d',
            'question': 'Show bookings, average stay length and average '
                        ~ 'booking value by month',
            'sql': by_month_sql,
        },
        {
            'name': 'q17_e',
            'question': 'How much does excluding the truncated reservations '
                        ~ 'change the average length of stay?',
            'sql': censoring_sql,
        },
    ]) }}
{%- endmacro %}
