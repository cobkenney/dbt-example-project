-- One row per host: portfolio size, tenure, and performance.
--
-- The second dimension a star schema wants. Both facts carry host_id, so
-- revenue and reservations can be sliced by host segment without touching
-- dim_listings.
--
-- host_name is PII and is not available here in plaintext — host_name_masked is
-- a salted hash, and host_id is what you join on. See macros/mask_pii.sql.
--
-- The as_of_date that tenure is anchored to arrives as a session variable set
-- by the pre-hook below, rather than as a one-row CTE cross joined onto every
-- host. Both produce the same column — verified identical: the same row count,
-- a single distinct as_of_date, and the same tenure either way.
--
-- What the variable buys: a scalar in the select list cannot change the row
-- count, so the host grain is preserved by construction. The cross join could
-- only preserve it while calendar_window returned exactly one row, which is
-- why this model carried an equal_rowcount test against int_hosts. That test is
-- gone with the join.
--
-- Costs, both real:
--   1. The compiled SQL is no longer runnable on its own. Pasting
--      target/compiled/.../dim_hosts.sql into a worksheet fails with "Session
--      variable '$CALENDAR_AS_OF_DATE' does not exist" until you run the set
--      statement yourself.
--   2. The dependency on int_listing_daily now lives only in the hook. dbt does
--      register refs from hooks — the DAG edge and build order survive — but it
--      is invisible when reading the select.
--
-- The ref() is left as literal Jinja inside the string rather than concatenated
-- with ~. dbt renders hook SQL in a later pass; a ref() evaluated while the
-- config block itself is parsed resolves to THIS model, which compiles to a
-- self-reference that silently reads dim_hosts' own previous build.
--
-- dim_listings sets the same variable from the same source in its own pre-hook.
-- Sharing the name is deliberate — one anchor date for the mart, defined once
-- in wording and twice in SQL. It is safe under dbt's threading because
-- dbt-snowflake holds one connection per thread and a session variable is
-- scoped to its session: two models on different threads set their own copy,
-- and two on the same thread set it to the same value in sequence.
{{ config(
    pre_hook="set calendar_as_of_date = (select max(calendar_date)
              from {{ ref('int_listing_daily') }})"
) }}

with hosts as (

    select * from {{ ref('int_hosts') }}

)

select
    hosts.host_id,
    hosts.host_name_masked,

    hosts.host_since,

    -- Tenure and staleness measured against the snapshot's end, not
    -- current_date. This data is a fixed year, so current_date would make every
    -- measure drift as time passes and give a different answer on every run.
    $calendar_as_of_date as as_of_date,
    datediff(year, hosts.host_since, $calendar_as_of_date)
        as host_tenure_years,

    hosts.host_location,

    hosts.verification_count,
    hosts.verification_list,

    -- Named explicitly rather than select *
    hosts.is_verified_email,
    hosts.is_verified_phone,
    hosts.is_verified_reviews,
    hosts.is_verified_kba,
    hosts.is_verified_government_id,
    hosts.is_verified_offline_government_id,
    hosts.is_verified_jumio,
    hosts.is_verified_facebook,
    hosts.is_verified_selfie,
    hosts.is_verified_identity_manual,
    hosts.is_verified_work_email,

    hosts.listing_count,
    hosts.listing_count > 1 as is_multi_listing_host,

    hosts.calendar_days,
    hosts.booked_nights,
    hosts.total_revenue,
    hosts.reservations,

    hosts.occupancy_rate,
    hosts.avg_nights_per_stay,
    hosts.avg_list_price,

    -- The comparison that makes hosts comparable across portfolio sizes: a
    -- 5-listing host will out-earn a 1-listing host in total by construction.
    div0(hosts.total_revenue, hosts.listing_count)
        as revenue_per_listing,

    hosts.total_reviews,
    hosts.avg_review_score

from hosts
