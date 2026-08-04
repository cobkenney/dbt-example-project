{#
    Verified queries for business question 14 — which amenities go with higher
    achieved rates. Against sem_listing_performance.

    Returns a list of {name, question, sql} entries. Several entries may share
    one query under different phrasings, because QUESTION is the surface a
    natural-language client matches an asked question against.

    CROSS-SECTIONAL ONLY, and every phrasing here is written to ask "goes with"
    rather than "impact of". Every amenity changelog event predates the calendar
    window entirely - asserted by tests/assert_amenities_predate_calendar.sql -
    so there is no before-and-after period in the data and the revenue effect of
    ADDING an amenity cannot be measured at any modelling effort. The view COMMENT and
    AI_SQL_GENERATION both say so; these entries avoid handing a client a query
    whose shape implies otherwise. That is why no entry is phrased "how much
    would adding X earn us".

    The comparison across amenities is a union with one branch per flag, because
    each amenity is its own boolean dimension and there is no single column to
    group on. The branches are generated from a literal list of the flags
    this view declares - not from the source - so this needs no warehouse query
    and no ref outside core_mart. int_listing_amenities holds the full amenity set
    if a question ever needs one without a flag here.

    amenity_count is a FACT, so the banded entry is CTE-wrapped at listing grain.
    That one is the more honest read of the question anyway: it asks whether
    better-equipped listings earn more, without attributing the difference to any
    single amenity.

    Apostrophes are fine in either field - the dispatcher doubles them for the
    single-quoted SQL literal each is emitted into.
#}
{% macro verified_queries_q14(view=none) -%}

    {%- set view = view or this -%}

    {#- The six amenity flags this view exposes as dimensions. -#}
    {%- set flags = [
        'has_air_conditioning',
        'has_wifi',
        'has_heating',
        'has_kitchen',
        'has_lockbox',
        'has_first_aid_kit',
    ] -%}

    {%- set branches = [] -%}
    {%- for flag in flags -%}
        {%- set branch -%}
select '{{ flag }}' as amenity, *
from semantic_view(
    {{ view }}
    metrics
        listing.listings,
        listing.avg_achieved_rate,
        listing.avg_list_price,
        listing.avg_occupancy_rate,
        listing.avg_revenue_per_listing
    where listing.{{ flag }} and not listing.is_orphan_listing
)
        {%- endset -%}
        {%- do branches.append(branch) -%}
    {%- endfor -%}

    {%- set by_amenity_sql -%}
{{ branches | join('\nunion all\n') }}
order by avg_achieved_rate desc
    {%- endset -%}

    {%- set ac_split_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        listing.listings,
        listing.avg_achieved_rate,
        listing.avg_list_price,
        listing.avg_occupancy_rate,
        listing.avg_revenue_per_listing
    dimensions listing.has_air_conditioning
    where not listing.is_orphan_listing
)
order by has_air_conditioning desc
    {%- endset -%}

    {%- set by_amenity_count_sql -%}
with listing_facts as (
    select *
    from semantic_view(
        {{ view }}
        dimensions
            listing.listing_id,
            listing.is_orphan_listing
        facts
            listing.amenity_count,
            listing.achieved_nightly_rate,
            listing.occupancy_rate,
            listing.total_revenue
    )
)

select
    case
        when amenity_count < 15 then '1. under 15'
        when amenity_count < 25 then '2. 15 to 24'
        when amenity_count < 35 then '3. 25 to 34'
        else '4. 35 and over'
    end as amenity_count_band,
    count(*) as listings,
    round(avg(amenity_count), 1) as avg_amenity_count,
    round(avg(achieved_nightly_rate), 2) as avg_achieved_rate,
    round(avg(occupancy_rate), 4) as avg_occupancy_rate,
    round(avg(total_revenue), 2) as avg_revenue
from listing_facts
where not is_orphan_listing
group by all
order by amenity_count_band
    {%- endset -%}

    {{ return([
        {
            'name': 'q14_a',
            'question': 'Which amenities go with higher achieved nightly '
                        ~ 'rates?',
            'sql': by_amenity_sql,
        },
        {
            'name': 'q14_b',
            'question': 'Which amenity should we prioritize spending on?',
            'sql': by_amenity_sql,
        },
        {
            'name': 'q14_c',
            'question': 'Do listings with air conditioning earn more than '
                        ~ 'those without?',
            'sql': ac_split_sql,
        },
        {
            'name': 'q14_d',
            'question': 'Do better-equipped listings earn more?',
            'sql': by_amenity_count_sql,
        },
        {
            'name': 'q14_e',
            'question': 'Does the number of amenities go with higher rates or '
                        ~ 'occupancy?',
            'sql': by_amenity_count_sql,
        },
    ]) }}
{%- endmacro %}
