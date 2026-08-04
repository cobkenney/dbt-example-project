-- One row per listing per date — the daily grain the marts aggregate from.
--
-- The seed below is what the generated amenity flags are looped over, and the
-- ref() has to be stated here rather than left to get_amenity_names(): a ref
-- inside a macro is invisible to dbt's parser, so without this line dbt would
-- schedule this model without waiting for the seed to load.
-- depends_on: {{ ref('known_amenity_names') }}
with calendar as (

    select * from {{ ref('stg_calendar') }}

),

listings as (

    select * from {{ ref('stg_listings') }}

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
    -- rather than hardcoded, so all 81 amenities get a flag without 81 lines.
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
    -- The amenity name goes through sql_string_literal rather than being quoted
    -- inline. Inline escaping leaves an odd number of apostrophes on the line,
    -- which SQL highlighters read as an unterminated string — every line after
    -- the loop then renders as a string literal. It matters more here than
    -- anywhere: several source amenity names carry Unicode apostrophes already.
    select
        listing_id,
        count(distinct amenity_name) as amenity_count,
        array_agg(distinct amenity_name) as amenity_list,

        -- LT02/LT05 are disabled for the loop body only. sqlfluff lints the
        -- compiled output, where one generated identifier runs 71 characters
        -- (has_65_inch_hdtv_...) — no source formatting brings that under the
        -- 80-char limit, and the loop's indentation is set by Jinja whitespace
        -- control rather than by layout.
        -- noqa: disable=LT02,LT05
        {%- for amenity_name in get_amenity_names() %}
        boolor_agg(amenity_name = {{ sql_string_literal(amenity_name) }}) as {{ amenity_flag_name(amenity_name) }}{{ "," if not loop.last }}
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
        -- include or exclude them explicitly rather than by accident.
        listings.listing_id is null as is_orphan_listing,

        amenities.amenity_count,
        amenities.amenity_list,

        -- All 81 generated flags, named by the same loop over the same seed
        -- that built them rather than pulled in with amenities.*, so the
        -- compiled SQL states its own column list. The marts downstream
        -- deliberately narrow this to the six flags they use — see
        -- fct_listing_daily and dim_listings.
        -- noqa: disable=LT02,LT05
        {%- for amenity_name in get_amenity_names() %}
        amenities.{{ amenity_flag_name(amenity_name) }}{{ "," if not loop.last }}
        {%- endfor %}
    -- noqa: enable=all

    from calendar
    -- Left, not inner: an inner join drops listings with no bookings
    left join listings on calendar.listing_id = listings.listing_id
    -- Left for the orphan's sake too, though today the changelog covers all 50
    -- listings the calendar references. amenity_count's not_null is the
    -- tripwire for that stopping being true.
    left join amenities on calendar.listing_id = amenities.listing_id

),

window_starts as (

    -- Marks the first available night of each contiguous run of available
    -- nights. The ingredient for the availability-window questions — #3
    -- (longest possible stay) and #26 (revenue lost to unbookable windows) —
    -- which otherwise each write the gap-and-island window function themselves.
    --
    -- Two window functions rather than one because is_window_start cannot be
    -- referenced by the sum() over it in the same select list.
    --
    -- WHY THIS SHAPE, and not the `calendar_date - row_number()` form that
    -- analyses/03 and tests/assert_stay_cap_binds use: that one only works on a
    -- rowset already filtered to available nights, so it can never be a column
    -- here. This one is computed over the whole calendar, which is what lets
    -- the run identity be carried on the fact table.
    --
    -- It costs an assumption in exchange. The row_number form needs no
    -- contiguous calendar; this one does, because a missing date would merge
    -- the runs on either side of it rather than splitting them. Verified: 50
    -- listings x 365 dates, no gaps and no duplicates. calendar_id's uniqueness
    -- test and calendar_date's not_null are the guards.
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
