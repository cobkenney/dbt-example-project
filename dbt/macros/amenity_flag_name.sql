{#
    Quote a value as a SQL string literal, doubling any embedded apostrophe.

        Air conditioning  ->  the same text, wrapped in apostrophes
        Chefs kitchen     ->  likewise; and an apostrophe in the input is
                              doubled, so the literal stays valid

    Exists to keep apostrophes out of the models that call the flag loops.
    Writing the escaping inline leaves an ODD number of apostrophes on the source
    line, and a SQL highlighter reads that as an unterminated string — every line
    after it renders as string literal, which is exactly the symptom that led
    here. Jinja and dbt compile it correctly; only the editor is confused.

    So every line below carries an EVEN number of apostrophes. The two-character
    doubled form is the only literal written, and `| first` takes one character
    off it to get a single apostrophe. That is the whole reason for the
    indirection — a plain assignment of one apostrophe would reintroduce the
    problem here instead of in the models.

    Deliberately NOT dbt.string_literal, which wraps a value in quotes WITHOUT
    escaping it: passing that an apostrophe produces a compile-time syntax error.
    Verified against Snowflake rather than assumed.

    No amenity or verification name contains an apostrophe today, so this is
    defensive. It stays because the inputs are source data — an amenity named
    with a possessive would otherwise emit a broken literal into every flag loop.
#}
{% macro sql_string_literal(value) -%}
    {%- set doubled = "''" -%}
    {%- set apostrophe = doubled | first -%}
    {%- set escaped = value | string | replace(apostrophe, doubled) -%}
    {{- apostrophe ~ escaped ~ apostrophe -}}
{%- endmacro %}


{#
    Turn a raw amenity name into a safe boolean column identifier.

    'Air conditioning'           -> has_air_conditioning
    'Children’s books and toys'  -> has_children_s_books_and_toys
    'Pack ’n Play/travel crib'   -> has_pack_n_play_travel_crib

    Every run of non-alphanumeric characters collapses to one underscore, which
    is what makes the Unicode apostrophes, colon, slash and commas in the source
    names safe. Names starting with a digit ('65 inch HDTV...') are fine because
    the has_ prefix always leads.
#}
{% macro amenity_flag_name(amenity_name) -%}
    {%- set slug = modules.re.sub(
        '[^a-z0-9]+', '_', amenity_name | lower
    ) | trim('_') -%}
    {{- 'has_' ~ slug -}}
{%- endmacro %}


{#
    The pinned amenity names, ordered so the generated column order is stable
    between runs.

    READS THE SEED, NOT THE DATA. seeds/known_amenity_names.csv is the committed
    list of the 81 amenities, and it is the same list the relationships test on
    int_listing_amenities checks against — so the generated flag columns and the
    test can never disagree about what exists.

    This is the whole point of the indirection, and it inverts what this macro
    used to do. Reading `select distinct amenity_name from int_listing_amenities`
    made the column list a function of TODAY'S DATA: a new amenity in the source
    added a column on the next run, and an amenity that stopped appearing removed
    one, both without a commit and both silently. Downstream that is not a widened
    table, it is a schema change nobody reviewed — the marts name the flags they
    carry, so a removed flag breaks dim_listings at run time rather than at review
    time.

    Now the seed decides the columns and the source decides only whether the
    warn test fires. A new amenity upstream warns and changes nothing else; the
    column appears when someone regenerates the seed, which is a reviewable diff.

    DEPENDENCY, and the reason both callers carry a `depends_on` hint: a ref()
    inside a macro is invisible to dbt's parser, because at parse time `execute`
    is false and this returns before the ref is ever rendered. int_listing_daily
    therefore declares `-- depends_on: {{ ref('known_amenity_names') }}` in its
    own body. Without it dbt would happily build the model before the seed
    existed and fail on a missing relation, or worse, build against a stale one.

    Returns [] when execute is false (dbt parse / dbt ls), so those commands
    still work without a warehouse connection — the model body is not run then,
    only rendered.
#}
{% macro get_amenity_names() -%}
    {%- if not execute -%}
        {{ return([]) }}
    {%- endif -%}

    {%- set query -%}
        select amenity_name
        from {{ ref('known_amenity_names') }}
        order by 1
    {%- endset -%}

    {{ return(run_query(query).columns[0].values()) }}
{%- endmacro %}
