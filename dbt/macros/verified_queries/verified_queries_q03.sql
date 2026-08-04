{#
    Verified queries for business question 3 — longest possible stay for a
    renter who wants both a lockbox and a first aid kit. Against
    sem_listing_daily.

    Returns a list of {name, question, sql} entries. Several entries may share
    one query under different phrasings, because QUESTION is the surface a
    natural-language client matches an asked question against.

    THIS IS THE QUESTION THAT DRIVES THE COLUMN. The answer needs contiguous
    runs of available nights, which is a gap-and-island — and a semantic view
    cannot express a window function at all. Rather than give up on the question
    here, int_listing_daily precomputes the run identity and fct_listing_daily
    carries it, so availability_window_seq is an ordinary dimension and the
    window becomes a GROUP BY.

    Three rules the column does NOT encode, all of which produce a plausible
    wrong answer, and all of which therefore have to be written out here:

      1. FILTER is_available BEFORE GROUPING. The sequence is a running count of
         runs started, so a booked night carries the number of the run that
         closed before it. Group without the filter and every window collects
         the booked nights that follow it.

      2. Window length is count(*), NOT datediff(min, max), which is one lower.
         Every available date is itself a bookable night, so a date difference
         undercounts every window by one.

      3. The answer is least(window_length, maximum_nights). BOTH bind in this
         data - the owner cap on a minority of windows, the window itself on the
         rest - so neither column alone answers it. Drop the clamp and a listing
         reports a stay longer than its own owner cap allows.
         tests/assert_stay_cap_binds.sql is what holds that premise.

    The CTE wrap is forced twice over. availability_window_seq is a DIMENSION, so
    it could sit in a metrics clause - but the aggregation is two-level (nights
    per window, then longest window per listing) and the clamp is arithmetic
    across two aggregates. Neither is expressible inside SEMANTIC_VIEW.

    listing_name is pulled alongside listing_id rather than instead of it. An
    orphan listing has a NULL name, and orphans are not filtered out here - they
    hold no lockbox flag either way, so the amenity filter already excludes them.

    Apostrophes are fine in either field - the dispatcher doubles them for the
    single-quoted SQL literal each is emitted into.
#}
{% macro verified_queries_q03(view=none) -%}

    {%- set view = view or this -%}

    {%- set picky_renter_sql -%}
with windows as (
    select *
    from semantic_view(
        {{ view }}
        metrics
            daily.calendar_nights,
            daily.max_maximum_nights
        dimensions
            daily.listing_id,
            listing.listing_name,
            listing.neighborhood,
            daily.availability_window_seq
        where
            daily.is_available
            and daily.has_lockbox
            and daily.has_first_aid_kit
    )
),

clamped as (
    select
        listing_id,
        listing_name,
        neighborhood,
        availability_window_seq,
        calendar_nights as window_length_nights,
        max_maximum_nights as owner_max_nights,
        least(calendar_nights, max_maximum_nights)
            as longest_possible_stay_nights
    from windows
)

select
    listing_id,
    listing_name,
    neighborhood,
    max(longest_possible_stay_nights) as longest_possible_stay_nights,
    max(window_length_nights) as longest_availability_window,
    max(owner_max_nights) as owner_max_nights,
    count(*) as availability_windows
from clamped
group by all
order by longest_possible_stay_nights desc
    {%- endset -%}

    {%- set all_windows_sql -%}
with windows as (
    select *
    from semantic_view(
        {{ view }}
        metrics
            daily.calendar_nights,
            daily.max_maximum_nights,
            daily.max_minimum_nights
        dimensions
            daily.listing_id,
            listing.listing_name,
            daily.availability_window_seq
        where daily.is_available
    )
)

select
    listing_id,
    listing_name,
    availability_window_seq,
    calendar_nights as window_length_nights,
    max_minimum_nights as minimum_nights,
    max_maximum_nights as owner_max_nights,
    least(calendar_nights, max_maximum_nights)
        as longest_possible_stay_nights,
    calendar_nights > max_maximum_nights as is_cap_bound
from windows
order by longest_possible_stay_nights desc
    {%- endset -%}

    {{ return([
        {
            'name': 'q03_a',
            'question': 'What is the longest stay available at a listing with '
                        ~ 'both a lockbox and a first aid kit?',
            'sql': picky_renter_sql,
        },
        {
            'name': 'q03_b',
            'question': 'I want a long stay somewhere with a lockbox and a '
                        ~ 'first aid kit - what is the most nights I could '
                        ~ 'book?',
            'sql': picky_renter_sql,
        },
        {
            'name': 'q03_c',
            'question': 'Which listings can take the longest bookings for a '
                        ~ 'renter who needs a lockbox and a first aid kit?',
            'sql': picky_renter_sql,
        },
        {
            'name': 'q03_d',
            'question': 'What is the longest continuous stretch of open nights '
                        ~ 'on each listing?',
            'sql': all_windows_sql,
        },
        {
            'name': 'q03_e',
            'question': 'Show every availability window with its length and '
                        ~ 'the maximum stay the owner allows',
            'sql': all_windows_sql,
        },
    ]) }}
{%- endmacro %}
