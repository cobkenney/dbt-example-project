{#
    Verified queries for business question 5 — which listings earned zero revenue
    all year. Against sem_listing_performance.

    Returns a list of {name, question, sql} entries. Several entries may share
    one query under different phrasings, because QUESTION is the surface a
    natural-language client matches an asked question against.

    A handful of listings qualify: available every night of the window and never
    booked, so the question behind the question is price, photos or location. The
    detail entry names the current ones, which is why it is here rather than a
    count alone.

    was_never_booked is a derived dimension on the view - total_revenue = 0 -
    which matters because total_revenue is ZERO and not NULL for these listings.
    A client testing `total_revenue is null` finds nothing and reports that every
    listing earned something.

    The detail query groups metrics by listing_id, which at this grain returns one
    row per listing rather than an aggregate. available_nights on those rows is
    what shows these were open all year rather than withheld from sale.

    Apostrophes are fine in either field - the dispatcher doubles them for the
    single-quoted SQL literal each is emitted into.
#}
{% macro verified_queries_q05(view=none) -%}

    {%- set view = view or this -%}

    {%- set detail_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        listing.total_available_nights,
        listing.avg_list_price,
        listing.avg_review_score,
        listing.total_reviews
    dimensions
        listing.listing_id,
        listing.listing_name,
        listing.neighborhood,
        listing.room_type
    where listing.was_never_booked
)
order by listing_id
    {%- endset -%}

    {%- set count_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        listing.listings,
        listing.never_booked_listings,
        listing.portfolio_revenue
)
    {%- endset -%}

    {%- set by_neighborhood_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        listing.listings,
        listing.never_booked_listings,
        listing.avg_occupancy_rate
    dimensions listing.neighborhood
    where not listing.is_orphan_listing
)
order by never_booked_listings desc
    {%- endset -%}

    {{ return([
        {
            'name': 'q05_a',
            'question': 'Which listings earned zero revenue all year?',
            'sql': detail_sql,
        },
        {
            'name': 'q05_b',
            'question': 'Are there any listings that were never booked?',
            'sql': detail_sql,
        },
        {
            'name': 'q05_c',
            'question': 'How many listings made no money?',
            'sql': count_sql,
        },
        {
            'name': 'q05_d',
            'question': 'Which neighborhoods have listings that never booked?',
            'sql': by_neighborhood_sql,
        },
    ]) }}
{%- endmacro %}
