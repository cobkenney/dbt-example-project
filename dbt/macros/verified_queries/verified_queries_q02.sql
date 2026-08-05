{#
    Verified queries for business question 2 — average price increase by
    neighborhood across the calendar window. Against sem_listing_daily.

    Returns a list of {name, question, sql} entries. Several entries may share
    one query under different phrasings, because QUESTION is the surface a
    natural-language client matches an asked question against.

    THE PER-LISTING CTE IS THE POINT, not scaffolding. Averaging each listing's
    own price change and then averaging those is NOT the same as differencing two
    neighborhood averages - the second is wrong whenever the set of listings in
    the neighborhood differs between the two dates. It happens to agree on this
    data, where every listing spans the whole window, and it would silently stop
    agreeing the moment a listing entered or left. The endpoint prices are pulled
    per listing here for that reason.

    The dates are hardcoded endpoints rather than min and max of calendar_date. A
    semantic view cannot supply its own extent to its own filter, and the window
    is a fixed snapshot, so pinning them is honest rather than fragile - this is
    the one place a date literal belongs, since it is the query's own bound and
    not a claim about the data. If the snapshot ever moves, this query returns
    empty rather than quietly comparing the wrong two days.

    listings rides along on every entry: some neighborhoods hold a single
    listing, so a neighborhood average there is one number wearing a plural, and
    the base belongs next to it.

    is_orphan_listing is filtered out - it has a NULL neighborhood and would
    otherwise form a NULL group. Correct here, because the question compares an
    attribute rather than totalling revenue.

    Apostrophes are fine in either field - the dispatcher doubles them for the
    single-quoted SQL literal each is emitted into.
#}
{% macro verified_queries_q02(view=none) -%}

    {%- set view = view or this -%}

    {%- set price_change_sql -%}
with endpoints as (
    select *
    from semantic_view(
        {{ view }}
        metrics daily.avg_nightly_price
        dimensions
            daily.listing_id,
            listing.neighborhood,
            daily.calendar_date
        where
            daily.calendar_date in ('2021-07-12', '2022-07-11')
            and not daily.is_orphan_listing
    )
),

listing_price_change as (
    select
        listing_id,
        neighborhood,
        max(case
            when calendar_date = '2021-07-12' then avg_nightly_price
        end) as start_price,
        max(case
            when calendar_date = '2022-07-11' then avg_nightly_price
        end) as end_price
    from endpoints
    group by all
)

select
    neighborhood,
    count(*) as listings,
    round(avg(end_price - start_price), 2) as avg_price_increase,
    round(avg(start_price), 2) as avg_start_price,
    round(avg(end_price), 2) as avg_end_price
from listing_price_change
group by all
order by avg_price_increase desc
    {%- endset -%}

    {%- set monthly_trend_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        daily.avg_nightly_price,
        daily.achieved_nightly_rate,
        daily.listings
    dimensions
        listing.neighborhood,
        daily.month_start_date
    where not daily.is_orphan_listing
)
order by neighborhood, month_start_date
    {%- endset -%}

    {{ return([
        {
            'name': 'q02_a',
            'question': 'What is the average price increase per neighborhood?',
            'sql': price_change_sql,
        },
        {
            'name': 'q02_b',
            'question': 'Which neighborhoods raised their nightly rates the '
                        ~ 'most over the year?',
            'sql': price_change_sql,
        },
        {
            'name': 'q02_c',
            'question': 'Where are rates moving?',
            'sql': price_change_sql,
        },
        {
            'name': 'q02_d',
            'question': 'Show the monthly nightly price trend for each '
                        ~ 'neighborhood',
            'sql': monthly_trend_sql,
        },
    ]) }}
{%- endmacro %}
