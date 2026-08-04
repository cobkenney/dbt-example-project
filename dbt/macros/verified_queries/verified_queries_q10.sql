{#
    Verified queries for business question 10 — day-of-week occupancy and
    pricing patterns. Against sem_listing_daily.

    Returns a list of {name, question, sql} entries. Several entries may share
    one query under different phrasings, because QUESTION is the surface a
    natural-language client matches an asked question against.

    Two grains, because the question is really two. day_of_week gives the shape
    across all seven days, which is what pricing wants; is_weekend gives the
    single number, which is what a weekend-premium answer wants. Both are
    dimensions the view already computes, so neither needs a CTE.

    ORDERING BY dayname IS ALPHABETICAL AND THEREFORE MEANINGLESS - Fri, Mon,
    Sat... The outer order by uses dayofweek on the day name mapped back through
    a case, so Monday leads. This is the one place the query is longer than the
    question deserves, and the alternative is a chart with the days shuffled.

    BOTH price metrics are returned together, always. avg_nightly_price is what
    was ASKED across every night; achieved_nightly_rate is what was EARNED on
    booked nights only. A weekend premium in the first is a pricing decision; a
    premium in the second is what the market paid. They can disagree, and a
    single-metric answer here silently picks one meaning of the question.

    is_weekend uses Snowflake dayofweek where 0 is Sunday, so it covers Saturday
    and Sunday. Note this is the calendar weekend, not the hospitality one - a
    Friday night stay is priced as a weekend night in practice and counts as
    midweek here.

    No orphan filter on the day-of-week entries: they group on a date attribute,
    not a listing attribute, and revenue totals should include listing 276450.
    The room-type cross does filter it, since room_type is NULL for it.

    Apostrophes are fine in either field - the dispatcher doubles them for the
    single-quoted SQL literal each is emitted into.
#}
{% macro verified_queries_q10(view=none) -%}

    {%- set view = view or this -%}

    {%- set by_day_sql -%}
with by_day as (
    select *
    from semantic_view(
        {{ view }}
        metrics
            daily.calendar_nights,
            daily.booked_nights,
            daily.occupancy_rate,
            daily.avg_nightly_price,
            daily.achieved_nightly_rate,
            daily.total_revenue
        dimensions daily.day_of_week
    )
)

select *
from by_day
order by case day_of_week
    when 'Mon' then 1
    when 'Tue' then 2
    when 'Wed' then 3
    when 'Thu' then 4
    when 'Fri' then 5
    when 'Sat' then 6
    when 'Sun' then 7
end
    {%- endset -%}

    {%- set weekend_premium_sql -%}
select *
from semantic_view(
    {{ view }}
    metrics
        daily.calendar_nights,
        daily.booked_nights,
        daily.occupancy_rate,
        daily.avg_nightly_price,
        daily.achieved_nightly_rate,
        daily.total_revenue
    dimensions daily.is_weekend
)
order by is_weekend
    {%- endset -%}

    {%- set by_day_and_room_type_sql -%}
with by_day as (
    select *
    from semantic_view(
        {{ view }}
        metrics
            daily.occupancy_rate,
            daily.avg_nightly_price,
            daily.achieved_nightly_rate
        dimensions
            daily.day_of_week,
            listing.room_type
        where not daily.is_orphan_listing
    )
)

select *
from by_day
order by room_type, case day_of_week
    when 'Mon' then 1
    when 'Tue' then 2
    when 'Wed' then 3
    when 'Thu' then 4
    when 'Fri' then 5
    when 'Sat' then 6
    when 'Sun' then 7
end
    {%- endset -%}

    {{ return([
        {
            'name': 'q10_a',
            'question': 'What are the occupancy and pricing patterns by day of '
                        ~ 'week?',
            'sql': by_day_sql,
        },
        {
            'name': 'q10_b',
            'question': 'Which days of the week have the worst occupancy?',
            'sql': by_day_sql,
        },
        {
            'name': 'q10_c',
            'question': 'Where are the midweek gaps we could be filling?',
            'sql': by_day_sql,
        },
        {
            'name': 'q10_d',
            'question': 'How big is the weekend premium?',
            'sql': weekend_premium_sql,
        },
        {
            'name': 'q10_e',
            'question': 'Compare weekend nights against weeknights on price and '
                        ~ 'occupancy',
            'sql': weekend_premium_sql,
        },
        {
            'name': 'q10_f',
            'question': 'Do entire homes and private rooms have different '
                        ~ 'day-of-week patterns?',
            'sql': by_day_and_room_type_sql,
        },
    ]) }}
{%- endmacro %}
