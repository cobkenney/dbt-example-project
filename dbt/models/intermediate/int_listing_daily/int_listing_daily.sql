-- One row per listing per date — the daily grain the marts aggregate from.
--
-- The seed below is what the generated amenity flags are looped over, and the
-- ref() has to be stated here rather than left to get_flag_values(): a ref
-- inside a macro is invisible to dbt's parser, so without this line dbt would
-- schedule this model without waiting for the seed to load.
-- depends_on: {{ ref('known_amenity_names') }}
with calendar as (

    select * from {{ ref('stg_calendar') }}

),

listings as (

    -- int_listings rather than stg_listings, so the orphan flag below is read
    -- rather than derived. int_listings covers every listing the calendar
    -- references, which means the join finds a row for every calendar row.
    select * from {{ ref('int_listings') }}

),

amenities as (

    -- The boolean pivot, run here rather than in the bridge model upstream:
    -- int_listing_amenities' job is to get amenities out of JSON and into rows,
    -- and this is where the flags are actually consumed. Same split as
    -- int_host_verifications -> int_hosts.
    --
    -- Aggregated to one row per listing before the join below, so this cannot
    -- fan out the daily grain no matter how many amenities a listing has.
    --
    -- One boolean per amenity in seeds/known_amenity_names.csv, generated
    -- rather than hardcoded, so every amenity gets a flag without a line each.
    --
    -- The loop reads the SEED, not the data. That is what keeps this column
    -- list pinned: an amenity appearing or disappearing upstream changes
    -- nothing here until the seed is regenerated, which is a reviewable diff.
    -- Looping over `select distinct amenity_name` instead — which this model
    -- used to do — made the schema a function of today's rows, and a flag that
    -- stopped being generated took dim_listings down with it at run time.
    --
    -- The tripwire moved rather than disappeared: int_listing_amenities
    -- relationships-tests amenity_name against the same seed at severity warn,
    -- so a new amenity announces itself on the next build instead of arriving
    -- as an unreviewed column.
    --
    -- The amenity name is emitted as a quoted literal with any apostrophe
    -- doubled. No source name carries an ASCII apostrophe today — the ones
    -- that look like they do use U+2019, which needs no escaping — but the
    -- values are source data, and one named with a possessive would otherwise
    -- end its own literal and break the compile on every iteration.
    select
        listing_id,
        count(distinct amenity_name) as amenity_count,
        array_agg(distinct amenity_name) as amenity_list,

        -- LT02/LT05 are disabled for the loop body only. sqlfluff lints the
        -- compiled output, where the longest generated identifier overruns the
        -- 80-char limit on its own — no source formatting brings it under, and
        -- the loop's indentation is set by Jinja whitespace control rather than
        -- by layout.
        -- noqa: disable=LT02,LT05
        {%- for amenity_name in get_flag_values('amenity') %}
        boolor_agg(amenity_name = '{{ amenity_name | replace("'", "''") }}') as {{ flag_name('amenity', amenity_name) }}{{ "," if not loop.last }}
        {%- endfor %}
    -- noqa: enable=all
    from {{ ref('int_listing_amenities') }}
    group by all

),

joined as (

    select
        calendar.calendar_id,
        calendar.listing_id,
        calendar.calendar_date,
        calendar.is_available,
        calendar.reservation_id,
        calendar.price,
        calendar.minimum_nights,
        calendar.maximum_nights,

        -- Revenue only accrues on nights that are actually booked.
        case
            when not calendar.is_available then calendar.price
        end as revenue,

        listings.listing_name,
        listings.neighborhood,
        listings.property_type,
        listings.room_type,
        listings.accommodates,
        listings.bedrooms,
        listings.beds,
        listings.host_id,

        -- Flags the calendar rows whose listing never loaded, so marts can
        -- include or exclude them explicitly rather than by accident. Read from
        -- int_listings, which owns the rule — this model and dim_listings each
        -- used to derive it from their own left join to stg_listings.
        listings.is_orphan_listing,

        amenities.amenity_count,
        amenities.amenity_list,

        -- Every generated flag, named by the same loop over the same seed
        -- that built them rather than pulled in with amenities.*, so the
        -- compiled SQL states its own column list. The marts downstream
        -- deliberately narrow this to the handful of flags they use — see
        -- fct_listing_daily and dim_listings.
        -- noqa: disable=LT02,LT05
        {%- for amenity_name in get_flag_values('amenity') %}
        amenities.{{ flag_name('amenity', amenity_name) }}{{ "," if not loop.last }}
        {%- endfor %}
    -- noqa: enable=all

    from calendar
    -- Left, not inner. int_listings covers every listing the calendar
    -- references, so the two are equivalent today — but an inner join would
    -- respond to that stopping being true by silently dropping calendar rows,
    -- where the left join leaves is_orphan_listing NULL and its not_null test
    -- says so.
    left join listings on calendar.listing_id = listings.listing_id
    -- Left for the orphans' sake too, though today the changelog covers every
    -- listing the calendar references. amenity_count's not_null is the
    -- tripwire for that stopping being true.
    left join amenities on calendar.listing_id = amenities.listing_id

),

window_starts as (

    -- Marks the first available night of each contiguous run of available
    -- nights. The ingredient for the availability-window questions — #3
    -- (longest possible stay) and #25 (revenue lost to unbookable windows) —
    -- which otherwise each write the gap-and-island window function themselves.
    --
    -- Two window functions rather than one because is_window_start cannot be
    -- referenced by the sum() over it in the same select list.
    --
    -- WHY THIS SHAPE, and not the `calendar_date - row_number()` form that
    -- tests/assert_stay_cap_binds uses: that one only works on a
    -- rowset already filtered to available nights, so it can never be a column
    -- here. This one is computed over the whole calendar, which is what lets
    -- the run identity be carried on the fact table.
    --
    -- It costs an assumption in exchange. The row_number form needs no
    -- contiguous calendar; this one does, because a missing date would merge
    -- the runs on either side of it rather than splitting them. The calendar is
    -- gap-free and duplicate-free per listing; calendar_id's uniqueness test
    -- and calendar_date's not_null are the guards.
    --
    -- coalesce, not `is not true`: lag is NULL on each listing's first row, and
    -- without the default that row is never a window start even when available.
    select
        *,
        is_available
        and not coalesce(
            lag(is_available) over (
                partition by listing_id order by calendar_date
            ),
            false
        ) as is_window_start
    from joined

),

sequenced as (

    -- Running count of windows started so far, so the value is constant across
    -- every night of one window and identifies it.
    --
    -- MEANINGLESS ON BOOKED NIGHTS: a booked night carries the number of the
    -- window that ended before it, so every consumer must filter is_available
    -- before grouping on this. Documented at length on the column, because a
    -- group that forgets counts the booked nights after a run as part of it and
    -- reports a window longer than it is.
    select
        *,
        sum(case when is_window_start then 1 else 0 end) over (
            partition by listing_id
            order by calendar_date
            rows between unbounded preceding and current row
        ) as availability_window_seq
    from window_starts

)

select * from sequenced
