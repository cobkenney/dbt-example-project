{#
    Verified queries for business question 8 — advertised rate against achieved
    nightly rate. Against sem_listing_performance.

    Returns a list of {name, question, sql} entries. Several entries may share
    one query under different phrasings, because QUESTION is the surface a
    natural-language client matches an asked question against.

    THE GAP IS THE ANSWER, not either price. avg_discount_to_list is that gap as
    a named metric, so these entries return it rather than leaving a client to
    subtract two numbers it may have picked wrongly.

    The wrong pick being avg_nightly_price, which is a FACT here and is neither of
    the two rates this question is about: it is the mean rate the listing was
    OFFERED at across all 365 nights, booked or not. Confusing it with the
    achieved rate makes an unbooked listing look like a fully-priced one. So the
    entries name avg_achieved_rate and avg_list_price explicitly and never
    mention avg_nightly_price.

    achieved_nightly_rate is NULL for the 3 listings never booked - dividing
    revenue by zero nights - so those drop out of the averages rather than
    reading as zero-dollar rates.

    Apostrophes are fine in either field - the dispatcher doubles them for the
    single-quoted SQL literal each is emitted into.
#}
{% macro verified_queries_q08(view=none) -%}

    {%- set view = view or this -%}

    {%- set overall_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        listing.listings,
        listing.avg_list_price,
        listing.avg_achieved_rate,
        listing.avg_discount_to_list
)
    {%- endset -%}

    {%- set by_listing_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        listing.avg_list_price,
        listing.avg_achieved_rate,
        listing.avg_discount_to_list,
        listing.avg_occupancy_rate
    dimensions
        listing.listing_id,
        listing.listing_name,
        listing.neighborhood
    where not listing.is_orphan_listing
)
order by avg_discount_to_list desc
    {%- endset -%}

    {%- set by_segment_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        listing.listings,
        listing.avg_list_price,
        listing.avg_achieved_rate,
        listing.avg_discount_to_list
    dimensions
        listing.neighborhood,
        listing.room_type
    where not listing.is_orphan_listing
)
order by avg_discount_to_list desc
    {%- endset -%}

    {{ return([
        {
            'name': 'q08_a',
            'question': 'How does the advertised rate compare to what '
                        ~ 'listings actually earn per night?',
            'sql': overall_sql,
        },
        {
            'name': 'q08_b',
            'question': 'Are we discounting off our asking price?',
            'sql': overall_sql,
        },
        {
            'name': 'q08_c',
            'question': 'Which listings earn the least relative to their '
                        ~ 'asking price?',
            'sql': by_listing_sql,
        },
        {
            'name': 'q08_d',
            'question': 'Which listings are mispriced?',
            'sql': by_listing_sql,
        },
        {
            'name': 'q08_e',
            'question': 'Show the gap between asking and achieved rate by '
                        ~ 'neighborhood and room type',
            'sql': by_segment_sql,
        },
    ]) }}
{%- endmacro %}
