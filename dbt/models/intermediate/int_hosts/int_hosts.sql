-- One row per host: portfolio size, tenure, and performance rolled up from
-- their listings.
--
-- Hosts arrive denormalized onto the listings table, not as their own source,
-- so this reconstructs the grain by grouping. Most hosts hold a single listing,
-- with a thin tail holding several.
--
-- Sourced from int_listings rather than dim_listings to keep the intermediate
-- layer free of mart dependencies. Orphan listings are excluded, which is
-- correct: with no listings row an orphan has no host_id, so it cannot belong
-- to any host.
--
-- That exclusion is now a stated filter rather than a side effect. Reading
-- stg_listings, the orphan was absent because the model it came from did not
-- have it — the right outcome for a reason unrelated to hosts, and invisible in
-- this file. int_listings carries the orphans, so the filter has to be written
-- down, and is_orphan_listing is what makes it sayable.
--
-- The seed below is what the generated is_verified_* flags are looped over, and
-- the ref() has to be stated here rather than left inside get_flag_values(): a
-- ref inside a macro is invisible to dbt's parser, so without this line dbt
-- would schedule this model without waiting for the seed to load.
-- depends_on: {{ ref('known_verification_methods') }}
with listings as (

    -- Orphans excluded here rather than downstream: host_id is NULL for them,
    -- and grouping on that below would invent a host that does not exist. The
    -- not_null test on host_id would catch it, but the filter states the intent
    -- where a reader of this grain will look for it.
    select *
    from {{ ref('int_listings') }}
    where not is_orphan_listing

),

listing_performance as (

    -- Per-listing measures rebuilt from the daily grain rather than read from
    -- dim_listings, for the same no-mart-dependency reason. Kept to the columns
    -- this model actually aggregates.
    select
        listing_id,
        count(*) as calendar_days,
        count_if(not is_available) as booked_nights,
        coalesce(sum(revenue), 0) as total_revenue
    from {{ ref('int_listing_daily') }}
    group by all

),

reservation_performance as (

    select
        listing_id,
        count(*) as reservations,

        -- Censored reservations are excluded from the stay-length average only:
        -- their nights are truncated at the snapshot edge, so including them
        -- biases the average downward. The reservation COUNT keeps them, since
        -- those bookings really happened.
        avg(
            case
                when not (is_left_censored or is_right_censored) then nights
            end
        ) as avg_nights_per_stay
    from {{ ref('int_reservations') }}
    group by all

),

per_listing as (

    select
        listings.host_id,
        listings.listing_id,
        listings.host_name_masked,
        listings.host_since,
        listings.host_location,
        -- host_verifications is not selected here. It was, and was never
        -- aggregated by the hosts CTE below — the flags come from the
        -- int_host_verifications bridge, which is the only path that should
        -- exist. int_listings carries no raw JSON, so the dead column is gone.
        listings.list_price,
        listings.number_of_reviews,
        listings.review_scores_rating,

        coalesce(listing_performance.calendar_days, 0) as calendar_days,
        coalesce(listing_performance.booked_nights, 0) as booked_nights,
        coalesce(listing_performance.total_revenue, 0) as total_revenue,
        coalesce(reservation_performance.reservations, 0) as reservations,
        reservation_performance.avg_nights_per_stay

    from listings
    left join
        listing_performance
        on listings.listing_id = listing_performance.listing_id
    left join
        reservation_performance
        on listings.listing_id = reservation_performance.listing_id

),

verification_flags as (

    select
        host_id,
        count(*) as verification_count,
        array_agg(verification_method) as verification_list,

        -- One boolean per method in seeds/known_verification_methods.csv,
        -- generated rather than hardcoded — same pattern as the amenity flags
        -- on int_listing_daily, and now the same guarantee: the loop reads the
        -- SEED, so this column list is pinned to a committed file rather than
        -- to today's rows.
        --
        -- It matters more here than for amenities. dim_hosts names every flag
        -- explicitly, so back when this looped over `select distinct` on the
        -- source, a method disappearing upstream dropped a column here and
        -- broke the mart at run time — no test, no review, just a failed build
        -- one morning. int_host_verifications relationships-tests
        -- verification_method against the same seed at severity warn, which is
        -- where a source change gets noticed instead.
        --
        -- No coverage floor: email and phone are held by every host and carry
        -- no predictive signal, but a universally-true flag is a tripwire. The
        -- day a host lands without a verified email, that flag goes false and
        -- is queryable — which is only possible if the column exists.
        --
        -- The method name is emitted as a quoted literal with any apostrophe
        -- doubled. Every method is a snake_case identifier today, so the escape
        -- is a no-op — it stays because the values are source data, and one
        -- carrying an apostrophe would end its own literal and break the
        -- compile.
        --
        -- LT02/LT05 disabled for the loop body only, as in
        -- int_listing_daily: sqlfluff lints the compiled output, where the
        -- generated identifiers and indentation are set by Jinja whitespace
        -- control rather than source formatting.
        -- noqa: disable=LT02,LT05
        {%- for method_name in get_flag_values('verification') %}
        boolor_agg(verification_method = '{{ method_name | replace("'", "''") }}') as {{ flag_name('verification', method_name) }}{{ "," if not loop.last }}
        {%- endfor %}
    -- noqa: enable=all
    from {{ ref('int_host_verifications') }}
    group by all

),

hosts as (

    select
        host_id,

        count(*) as listing_count,

        -- Host attributes are denormalized onto every listing row, so any
        -- aggregate returns the same value. min() picks one deterministically
        -- rather than relying on Snowflake's any_value, which is not stable.
        -- assert_host_attributes_consistent.sql checks the premise holds.
        min(host_name_masked) as host_name_masked,
        min(host_since) as host_since,
        min(host_location) as host_location,

        sum(calendar_days) as calendar_days,
        sum(booked_nights) as booked_nights,
        sum(total_revenue) as total_revenue,
        sum(reservations) as reservations,

        -- Portfolio-wide rate, not the mean of per-listing rates: a host with a
        -- full-year listing and a part-year one should not have the short one
        -- weigh equally. div0 guards a host whose listings have no calendar
        -- rows.
        div0(sum(booked_nights), sum(calendar_days)) as occupancy_rate,

        -- Weighted by reservations for the same reason.
        div0(
            sum(avg_nights_per_stay * reservations), sum(reservations)
        ) as avg_nights_per_stay,

        avg(list_price) as avg_list_price,
        sum(number_of_reviews) as total_reviews,

        -- Unweighted: this is the average of the host's listing scores, which
        -- is what "how well reviewed is this host" means. NULL-scored listings
        -- drop out rather than counting as zero.
        avg(review_scores_rating) as avg_review_score

    from per_listing
    group by all

)

-- select * because the verification flags are generated: naming them here
-- would duplicate the seed's list in a third place, and the failure mode of the
-- copies disagreeing is a flag computed above and dropped silently on the way
-- out. The seed is the one list; this passes through whatever it produced.
select
    hosts.*,
    verification_flags.* exclude (host_id)
from hosts
-- Left, not inner: a host whose verifications array is empty or unparseable has
-- no rows in the bridge model, and dropping them here would silently shrink the
-- host grain. Their flags land NULL, which is distinguishable from false.
left join verification_flags on hosts.host_id = verification_flags.host_id
