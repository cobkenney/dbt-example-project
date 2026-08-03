-- One row per listing holding its CURRENT amenity set — a deliberate
-- reduction of the changelog, valid only because every amenity event
-- predates the calendar window. Enforced by
-- tests/assert_amenities_predate_calendar.sql; if that test ever fails this
-- must become SCD2. See ../README.md for the verification and migration path.
with latest_amenities as (

    select
        listing_id,
        amenities
    -- The changelog, not stg_listings: it covers all 50 listings the calendar
    -- references, including 276450, which listings is missing.
    from {{ ref('stg_amenities_changelog') }}
    qualify
        row_number() over (
            partition by listing_id order by changed_at desc
        ) = 1

),

flattened as (

    select
        latest_amenities.listing_id,
        amenity.value::string as amenity_name
    from latest_amenities,
        lateral flatten(
            input => try_parse_json(latest_amenities.amenities)
        ) as amenity

),

pivoted as (

    select
        listing_id,
        count(distinct amenity_name) as amenity_count,
        array_agg(distinct amenity_name) as amenity_list,

        -- One boolean per amenity actually present in the source, generated
        -- rather than hardcoded.
        -- NOTE: this makes the model's column list depend on the data. A new
        -- amenity appearing upstream adds a column on the next run
        --
        -- LT02/LT05 are disabled for the loop body only. sqlfluff lints the
        -- compiled output, where one generated identifier runs 71 characters
        -- (has_65_inch_hdtv_...) — no source formatting brings that under the
        -- 80-char limit, and the loop's indentation is set by Jinja whitespace
        -- control rather than by layout.
        -- noqa: disable=LT02,LT05
        {%- for amenity_name in get_amenity_names() %}
        boolor_agg(amenity_name = '{{ amenity_name | replace("'", "''") }}') as {{ amenity_flag_name(amenity_name) }}{{ "," if not loop.last }}
        {%- endfor %}
    -- noqa: enable=all
    from flattened
    group by all

)

select * from pivoted
