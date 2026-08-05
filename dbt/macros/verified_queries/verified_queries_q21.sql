{#
    Verified queries for business question 21 — price per bedroom and per bed.
    Against sem_listing_daily.

    Returns a list of {name, question, sql} entries. Several entries may share
    one query under different phrasings, because QUESTION is the surface a
    natural-language client matches an asked question against.

    Normalizing COMPRESSES the entire-home premium over a private room sharply -
    less per bedroom than on raw price, and less again per bed. Most of the
    headline gap is buying more space rather than a higher rate for it, which is
    the entire reason to normalize before comparing.

    THE TWO DENOMINATORS FAIL IN OPPOSITE WAYS AND NEITHER SUBSTITUTES FOR THE
    OTHER. bedrooms goes NULL on some listings, so those rows drop out of that
    average. beds goes to 0 rather than NULL, so nullif is required or the
    division errors. Both gaps land entirely on entire homes - private rooms have
    complete data - and a listing can record a bedroom against no beds. Both
    guards are inside the view's fact definitions, so a query here cannot forget
    them; what a query CAN forget is that the per-bedroom entire-home figure rests
    on FEWER listings than the raw-price one does, which is why every entry
    returns the coverage counts alongside.

    Those coverage counts are why the main entry is CTE-wrapped. Counting how many
    listings are missing a denominator needs a conditional count over the
    dimension, which no metric expresses - so the query pulls one row per listing
    and computes both the averages and the coverage outside the clause.

    IT PULLS METRICS AT LISTING GRAIN RATHER THAN FACTS AT NIGHT GRAIN, which was
    the obvious first shape and does not work. Snowflake: "All expressions
    referenced in the query must come from the same entity when both FACTS and
    DIMENSIONS are specified." The facts are on daily and room_type is on listing,
    so the two cannot be selected together at all - a stricter rule than the
    facts-cannot-share-a-clause-with-metrics one, and it applies wherever a fact
    is pulled next to a joined attribute.

    Averaging per-listing averages, as this then does, is night-weighted only
    because every listing has the same number of calendar rows. If the snapshot
    ever covered listings
    for unequal windows the two would diverge, and this would become the
    listing-weighted figure - which is arguably the better one for comparing room
    types anyway, since it stops a long-tenured listing counting for more.

    price_per_guest is included wherever it fits. accommodates is populated on
    every listing, so it is the only one of the three normalizations backed by the
    whole portfolio - if a comparison has to cover everything, that is the one.

    is_deleted filtered throughout: a deleted listing has NULL bedrooms, beds and
    room type, so it contributes nothing to either normalization and would form a
    NULL group. Correct here, because the question compares attributes.

    Apostrophes are fine in either field - the dispatcher doubles them for the
    single-quoted SQL literal each is emitted into.
#}
{% macro verified_queries_q21(view=none) -%}

    {%- set view = view or this -%}

    {%- set by_room_type_sql -%}
with per_listing as (
    select *
    from semantic_view(
        {{ view }}
        metrics
            daily.avg_nightly_price,
            daily.avg_price_per_bedroom,
            daily.avg_price_per_bed,
            daily.avg_price_per_guest
        dimensions
            daily.listing_id,
            listing.room_type,
            listing.bedrooms,
            listing.beds
        where not daily.is_deleted
    )
)

select
    room_type,
    count(*) as listings,
    round(avg(avg_nightly_price), 2) as avg_nightly_price,
    round(avg(avg_price_per_bedroom), 2) as avg_price_per_bedroom,
    round(avg(avg_price_per_bed), 2) as avg_price_per_bed,
    round(avg(avg_price_per_guest), 2) as avg_price_per_guest,

    -- How much of each average is actually backed by data.
    count_if(bedrooms is null) as listings_missing_bedrooms,
    count_if(beds = 0) as listings_zero_beds
from per_listing
group by all
order by avg_nightly_price desc
    {%- endset -%}

    {%- set by_listing_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        daily.avg_nightly_price,
        daily.avg_price_per_bedroom,
        daily.avg_price_per_bed,
        daily.avg_price_per_guest,
        daily.occupancy_rate
    dimensions
        daily.listing_id,
        listing.listing_name,
        listing.room_type,
        listing.bedrooms,
        listing.beds,
        listing.accommodates
    where not daily.is_deleted
)
order by avg_price_per_bedroom desc nulls last
    {%- endset -%}

    {%- set by_neighborhood_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        daily.listings,
        daily.avg_nightly_price,
        daily.avg_price_per_bedroom,
        daily.avg_price_per_bed,
        daily.avg_price_per_guest
    dimensions listing.neighborhood
    where not daily.is_deleted
)
order by avg_price_per_bedroom desc nulls last
    {%- endset -%}

    {{ return([
        {
            'name': 'q21_a',
            'question': 'What is the price per bedroom and per bed by room '
                        ~ 'type?',
            'sql': by_room_type_sql,
        },
        {
            'name': 'q21_b',
            'question': 'How does an entire home compare to a private room once '
                        ~ 'you adjust for size?',
            'sql': by_room_type_sql,
        },
        {
            'name': 'q21_c',
            'question': 'Is a 4-bedroom really more expensive than a studio per '
                        ~ 'unit of space?',
            'sql': by_room_type_sql,
        },
        {
            'name': 'q21_d',
            'question': 'Show price per bedroom, per bed and per guest for '
                        ~ 'every listing',
            'sql': by_listing_sql,
        },
        {
            'name': 'q21_e',
            'question': 'Which listings charge the most per bedroom?',
            'sql': by_listing_sql,
        },
        {
            'name': 'q21_f',
            'question': 'What is the price per bedroom by neighborhood?',
            'sql': by_neighborhood_sql,
        },
    ]) }}
{%- endmacro %}
