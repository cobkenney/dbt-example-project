{#
    Verified queries for business question 26 — revenue lost to unbookable
    availability windows. Against sem_listing_daily.

    Returns a list of {name, question, sql} entries. Several entries may share
    one query under different phrasings, because QUESTION is the surface a
    natural-language client matches an asked question against.

    The question: a contiguous run of open nights SHORTER than the listing's
    minimum-stay requirement cannot be sold at all. Nobody can book it, so it is
    not vacancy waiting for demand - it is inventory the pricing rules have
    removed from sale. Same gap-and-island as question 3, and the same reason it
    is expressible here: availability_window_seq is precomputed on
    fct_listing_daily, so the run is a GROUP BY rather than a window function.
    See verified_queries_q03 for the three rules the column does not encode.

    Verified against the marts: 204 availability windows, of which 59 are
    unbookable, covering 300 nights and $64,062 of asking price - 4.5 percent of
    the $1,430,664 in open inventory.

    max_minimum_nights, not avg_minimum_nights. minimum_nights VARIES inside 7 of
    the 204 windows, and a stay covering the run has to clear the requirement on
    every night of it, so the strictest night is the binding one. Taking the mean
    instead calls 58 windows unbookable rather than 59.

    The lost value is the sum of the nightly PRICES asked on those nights, not
    revenue - revenue is NULL on an available night by construction, so summing
    it here returns nothing. It is an upper bound on the opportunity: it assumes
    every one of those nights would otherwise have sold at its asking rate, which
    at 60 percent portfolio occupancy it would not.

    That sum is reconstructed as calendar_nights * avg_nightly_price, because the
    view exposes no sum-of-price metric - deliberately, since a total of asking
    prices across booked and open nights alike is not a quantity anybody wants by
    default. count(*) * avg(price) is exactly sum(price) as long as price is
    never NULL, which stg_calendar tests.

    The by-listing entry is the actionable one. Fixing this means lowering a
    minimum-stay setting, and that is a per-listing decision.

    Apostrophes are fine in either field - the dispatcher doubles them for the
    single-quoted SQL literal each is emitted into.
#}
{% macro verified_queries_q26(view=none) -%}

    {%- set view = view or this -%}

    {#- Shared by every entry: one row per availability window, with the -#}
    {#- strictest minimum-stay across it and the asking value of its nights. -#}
    {%- set windows_cte -%}
with windows as (
    select *
    from semantic_view(
        {{ view }}
        metrics
            daily.calendar_nights,
            daily.max_minimum_nights,
            daily.avg_nightly_price
        dimensions
            daily.listing_id,
            listing.listing_name,
            daily.availability_window_seq
        where daily.is_available
    )
),

classified as (
    select
        listing_id,
        listing_name,
        availability_window_seq,
        calendar_nights as window_length_nights,
        max_minimum_nights as minimum_nights,
        calendar_nights < max_minimum_nights as is_unbookable,
        calendar_nights * avg_nightly_price as window_asking_value
    from windows
)
    {%- endset -%}

    {%- set portfolio_sql -%}
{{ windows_cte }}

select
    count(*) as availability_windows,
    count_if(is_unbookable) as unbookable_windows,
    sum(case when is_unbookable then window_length_nights end)
        as unbookable_nights,
    round(sum(case when is_unbookable then window_asking_value end), 2)
        as unbookable_asking_value,
    sum(window_length_nights) as all_available_nights,
    round(sum(window_asking_value), 2) as all_available_asking_value,
    round(
        100 * sum(case when is_unbookable then window_asking_value end)
        / sum(window_asking_value),
        2
    ) as pct_of_open_inventory_unbookable
from classified
    {%- endset -%}

    {%- set by_listing_sql -%}
{{ windows_cte }}

select
    listing_id,
    listing_name,
    count(*) as availability_windows,
    count_if(is_unbookable) as unbookable_windows,
    max(minimum_nights) as strictest_minimum_nights,
    sum(case when is_unbookable then window_length_nights end)
        as unbookable_nights,
    round(sum(case when is_unbookable then window_asking_value end), 2)
        as unbookable_asking_value
from classified
group by all
having count_if(is_unbookable) > 0
order by unbookable_asking_value desc
    {%- endset -%}

    {%- set detail_sql -%}
{{ windows_cte }}

select
    listing_id,
    listing_name,
    availability_window_seq,
    window_length_nights,
    minimum_nights,
    round(window_asking_value, 2) as window_asking_value
from classified
where is_unbookable
order by window_asking_value desc
    {%- endset -%}

    {{ return([
        {
            'name': 'q26_a',
            'question': 'How much revenue is lost to availability windows that '
                        ~ 'are too short to book?',
            'sql': portfolio_sql,
        },
        {
            'name': 'q26_b',
            'question': 'How many open nights cannot be sold because the gap is '
                        ~ 'shorter than the minimum stay?',
            'sql': portfolio_sql,
        },
        {
            'name': 'q26_c',
            'question': 'What share of our open inventory is unbookable?',
            'sql': portfolio_sql,
        },
        {
            'name': 'q26_d',
            'question': 'Which listings lose the most to unbookable gaps in '
                        ~ 'their calendar?',
            'sql': by_listing_sql,
        },
        {
            'name': 'q26_e',
            'question': 'Where should we lower the minimum-stay requirement?',
            'sql': by_listing_sql,
        },
        {
            'name': 'q26_f',
            'question': 'List every availability window that is shorter than '
                        ~ 'the minimum stay allowed',
            'sql': detail_sql,
        },
    ]) }}
{%- endmacro %}
