{#
    Verified queries for business question 9 — is there a price/occupancy sweet
    spot. Against sem_listing_performance.

    Returns a list of {name, question, sql} entries. Several entries may share
    one query under different phrasings, because QUESTION is the surface a
    natural-language client matches an asked question against.

    Banding by list price needs the CTE wrap. list_price is a FACT here, and
    Snowflake rejects FACTS and METRICS in the same SEMANTIC_VIEW clause -
    grouping there happens on dimensions only. FACTS combines with DIMENSIONS
    where the dimensions determine the facts, and listing_id is the primary key,
    so pulling facts at listing grain and banding outside the clause works.

    The bands are fixed dollar boundaries rather than ntile buckets, so the
    answer is readable as a price range and does not shift when a listing is
    added. list_price runs 25 to 571 dollars, so the top band is open-ended.

    The point of the question is that the highest-priced listing is rarely the
    highest-earning, so revenue and occupancy are returned together with the
    listing count per band - 50 listings across 5 bands is thin, and the base
    belongs next to the average.

    The scatter entry returns one row per listing instead, which is what somebody
    looking for a sweet spot actually needs: the shape, not five averages.

    Apostrophes are fine in either field - the dispatcher doubles them for the
    single-quoted SQL literal each is emitted into.
#}
{% macro verified_queries_q09(view=none) -%}

    {%- set view = view or this -%}

    {%- set by_price_band_sql -%}
with listing_facts as (
    select *
    from semantic_view(
        {{ view }}
        dimensions listing.listing_id
        facts
            listing.list_price,
            listing.occupancy_rate,
            listing.total_revenue,
            listing.achieved_nightly_rate
    )
)

select
    case
        when list_price < 75 then '1. under 75'
        when list_price < 150 then '2. 75 to 149'
        when list_price < 250 then '3. 150 to 249'
        when list_price < 400 then '4. 250 to 399'
        else '5. 400 and over'
    end as list_price_band,
    count(*) as listings,
    round(avg(list_price), 2) as avg_list_price,
    round(avg(occupancy_rate), 4) as avg_occupancy_rate,
    round(avg(total_revenue), 2) as avg_revenue,
    round(avg(achieved_nightly_rate), 2) as avg_achieved_rate
from listing_facts
where list_price is not null
group by all
order by list_price_band
    {%- endset -%}

    {%- set scatter_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        listing.avg_list_price,
        listing.avg_achieved_rate,
        listing.avg_occupancy_rate,
        listing.portfolio_revenue
    dimensions
        listing.listing_id,
        listing.listing_name,
        listing.room_type
    where not listing.is_orphan_listing
)
order by portfolio_revenue desc
    {%- endset -%}

    {{ return([
        {
            'name': 'q09_a',
            'question': 'Is there a sweet spot between price and occupancy?',
            'sql': by_price_band_sql,
        },
        {
            'name': 'q09_b',
            'question': 'What price range earns the most?',
            'sql': by_price_band_sql,
        },
        {
            'name': 'q09_c',
            'question': 'Do the highest-priced listings earn the most revenue?',
            'sql': scatter_sql,
        },
        {
            'name': 'q09_d',
            'question': 'Show price, occupancy and revenue for every listing',
            'sql': scatter_sql,
        },
    ]) }}
{%- endmacro %}
