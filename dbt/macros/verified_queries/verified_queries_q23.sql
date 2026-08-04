{#
    Verified queries for business question 23 — which reservations span a month
    boundary, and therefore whether monthly revenue needs proration. Against
    sem_reservations.

    Returns a list of {name, question, sql} entries. Several entries may share
    one query under different phrasings, because QUESTION is the surface a
    natural-language client matches an asked question against.

    spans_month_boundary is a derived dimension on the view, so the comparison
    of last_night_date against check_in_month is made once here rather than
    left to whoever asks. The count metric is month_boundary_reservations.

    Revenue is attributed entirely to the check-in month — these are the
    reservations whose revenue would move if it were prorated, which is the
    reason the question exists.

    Apostrophes are fine in either field - the dispatcher doubles them for the
    single-quoted SQL literal each is emitted into.
#}
{% macro verified_queries_q23(view=none) -%}

    {%- set view = view or this -%}

    {%- set count_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        reservations,
        month_boundary_reservations,
        total_revenue
)
    {%- endset -%}

    {%- set by_month_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        reservations,
        month_boundary_reservations,
        total_revenue
    dimensions check_in_month
)
order by check_in_month
    {%- endset -%}

    {%- set detail_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        reservations,
        booked_nights,
        total_revenue
    dimensions
        reservation_key,
        listing_id,
        check_in_date,
        last_night_date,
        check_in_month
    where spans_month_boundary
)
order by check_in_date
    {%- endset -%}

    {{ return([
        {
            'name': 'q23_a',
            'question': 'How many reservations span a month boundary?',
            'sql': count_sql,
        },
        {
            'name': 'q23_b',
            'question': 'Do we need to prorate monthly revenue across '
                        ~ 'reservations that cross a month boundary?',
            'sql': count_sql,
        },
        {
            'name': 'q23_c',
            'question': 'How many bookings start in one month and end in '
                        ~ 'another, by month?',
            'sql': by_month_sql,
        },
        {
            'name': 'q23_d',
            'question': 'List the reservations that start in one month and '
                        ~ 'end in another',
            'sql': detail_sql,
        },
    ]) }}
{%- endmacro %}
