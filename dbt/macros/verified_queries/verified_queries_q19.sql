{#
    Verified queries for business question 19 — multi-listing operators against
    casual hosts. Against sem_host_performance.

    Returns a list of {name, question, sql} entries. Several entries may share
    one query under different phrasings, because QUESTION is the surface a
    natural-language client matches an asked question against.

    This question gets the most phrasings of the four, because the finding runs
    OPPOSITE to the intuition: multi-listing hosts earn roughly half the revenue
    per property at two-thirds the occupancy. A client generating its own SQL is
    liable to reach for a listing-weighted figure, which answers a different
    question and gives the intuitive number instead. Every phrasing therefore
    lands on the same host-weighted query.

    median_revenue_per_listing rides along deliberately. The multi-listing
    segment is 7 hosts, where a mean is one outlier away from misleading.

    avg_length_of_stay is here to show what the gap is NOT: stay length barely
    differs between the segments, so this is an occupancy story rather than a
    stay-length one.

    Verified figures: 7 hosts holding 20 listings at 19,267.27 dollars per
    listing and 38.46 percent occupancy, against 29 hosts at 39,748.97 and
    60.05 percent. Stay length 6.2516 against 6.1098 nights.

    Apostrophes are fine in either field - the dispatcher doubles them for the
    single-quoted SQL literal each is emitted into.
#}
{% macro verified_queries_q19(view=none) -%}

    {%- set view = view or this -%}

    {%- set segments_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        hosts,
        listings,
        avg_revenue_per_listing,
        median_revenue_per_listing,
        avg_occupancy_rate,
        avg_length_of_stay,
        avg_listings_per_host
    dimensions is_multi_listing_host
)
order by is_multi_listing_host desc
    {%- endset -%}

    {{ return([
        {
            'name': 'q19_a',
            'question': 'Do professional operators outperform casual hosts?',
            'sql': segments_sql,
        },
        {
            'name': 'q19_b',
            'question': 'Compare multi-listing hosts against single-listing '
                        ~ 'hosts',
            'sql': segments_sql,
        },
        {
            'name': 'q19_c',
            'question': 'Do hosts with more properties earn more per property?',
            'sql': segments_sql,
        },
        {
            'name': 'q19_d',
            'question': 'Is it better to work with professional hosts or '
                        ~ 'casual ones?',
            'sql': segments_sql,
        },
    ]) }}
{%- endmacro %}
