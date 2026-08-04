{#
    Verified queries for business question 27 — neighborhood supply density
    against achieved rate. Against sem_listing_performance.

    Returns a list of {name, question, sql} entries. Several entries may share
    one query under different phrasings, because QUESTION is the surface a
    natural-language client matches an asked question against.

    THIS QUESTION WAS FILED AS NEEDING A NEW MODEL and does not. It wanted a
    neighborhood-grain aggregate, and grouping the `listings` metric by
    neighborhood IS that aggregate - no new model was required. So the entry
    exists partly to record that the question is answerable, since the doc listed
    it under "need a new model" before this view existed.

    THE BASE IS THE FINDING HERE. Some neighborhoods hold a single listing - Back
    Bay is one - so a per-neighborhood achieved rate can rest on one property.
    listings is first in the select list on every entry for that reason: a density
    comparison that hides its denominator is the failure mode of this question,
    not a detail.

    Orphan listing filtered out - it has a NULL neighborhood and would otherwise
    form a group whose name is missing.

    Apostrophes are fine in either field - the dispatcher doubles them for the
    single-quoted SQL literal each is emitted into.
#}
{% macro verified_queries_q27(view=none) -%}

    {%- set view = view or this -%}

    {%- set density_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        listing.listings,
        listing.avg_achieved_rate,
        listing.avg_list_price,
        listing.avg_occupancy_rate,
        listing.portfolio_revenue,
        listing.avg_revenue_per_listing
    dimensions listing.neighborhood
    where not listing.is_orphan_listing
)
order by listings desc
    {%- endset -%}

    {%- set density_by_room_type_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        listing.listings,
        listing.avg_achieved_rate,
        listing.avg_occupancy_rate
    dimensions
        listing.neighborhood,
        listing.room_type
    where not listing.is_orphan_listing
)
order by neighborhood, listings desc
    {%- endset -%}

    {{ return([
        {
            'name': 'q27_a',
            'question': 'How does neighborhood supply density compare to the '
                        ~ 'achieved rate?',
            'sql': density_sql,
        },
        {
            'name': 'q27_b',
            'question': 'How many listings do we have in each neighborhood, '
                        ~ 'and what do they earn per night?',
            'sql': density_sql,
        },
        {
            'name': 'q27_c',
            'question': 'Do neighborhoods with more listings have lower rates?',
            'sql': density_sql,
        },
        {
            'name': 'q27_d',
            'question': 'Show supply and achieved rate by neighborhood and '
                        ~ 'room type',
            'sql': density_by_room_type_sql,
        },
    ]) }}
{%- endmacro %}
