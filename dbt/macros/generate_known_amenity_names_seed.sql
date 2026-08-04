{#
    Regenerate seeds/known_amenity_names.csv from the data.

        dbt --quiet run-operation generate_known_amenity_names_seed \
            > seeds/known_amenity_names.csv

    Prints the CSV — a header line and one amenity name per row, ordered so the
    file diff stays stable between runs. Redirect it over the seed, review the
    diff, commit.

    `--quiet` IS NOT OPTIONAL, and it goes before run-operation. dbt writes its
    own log lines ("Running with dbt=...", "Registered adapter: ...") to STDOUT,
    not stderr, so without it three log lines land at the top of the CSV and the
    seed fails to load. Verified: with --quiet the output is byte-identical to the
    committed file; without it the file gains three junk rows.

    WHY A MACRO AND NOT A HAND-EDITED FILE. The seed is the accepted-values list
    for int_listing_amenities.amenity_name, so it has to match the source exactly,
    including the Unicode apostrophes in two of the names. Retyping a name is how
    a false positive gets committed, and the warning it silences is the one asking
    for the work.

    Reads INT_LISTING_AMENITIES, not the seed. get_amenity_names() reads the seed
    now, so calling it here would emit the file back to itself and never notice a
    new amenity — this macro is the one place that still has to look at the data.

    ORDER OF OPERATIONS, and it is the reverse of what it used to be: the seed
    drives the generated flag columns on int_listing_daily, so regenerating it is
    what ADDS THE COLUMN. That makes this step first, not last:

        1. regenerate this seed — the diff is the reviewable decision
        2. dbt run-operation generate_amenity_flag_yml   (yml for the new flag)
        3. decide whether dim_listings / fct_listing_daily carry it

    The tripwire is still real. Regenerating turns the relationships warning green
    by definition, so the commit that does it has to carry steps 2 and 3 with it —
    a seed diff on its own means a column exists with no documentation and no mart
    decision behind it.

    Uses print() rather than log() so the output carries no timestamp prefix and
    can be redirected straight to the file.

    Quoting follows RFC 4180 and matches what dbt's seed loader expects: a value
    is wrapped in double quotes only when it contains a comma, a double quote or a
    newline, and an embedded double quote is doubled. One amenity name needs it
    today — "65 inch HDTV with Netflix, HBO Max, Amazon Prime Video, standard
    cable". Apostrophes need no quoting at all, ASCII or Unicode.

    Same shape and same reasoning as generate_amenity_flag_yml, which emits the
    yml for the flag columns — except that one reads the seed, via
    get_amenity_names(), because its job is to document the columns that exist
    rather than to discover new values. Neither writes anything.
#}
{% macro generate_known_amenity_names_seed() -%}

    {%- if not execute -%}{{ return('') }}{%- endif -%}

    {%- set query -%}
        select distinct amenity_name
        from {{ ref('int_listing_amenities') }}
        order by 1
    {%- endset -%}
    {%- set amenity_names = run_query(query).columns[0].values() -%}

    {%- do print('amenity_name') -%}

    {%- for amenity_name in amenity_names -%}
        {%- set needs_quoting =
            ',' in amenity_name
            or '"' in amenity_name
            or '\n' in amenity_name -%}
        {%- if needs_quoting -%}
            {%- do print(
                '"' ~ amenity_name | replace('"', '""') ~ '"'
            ) -%}
        {%- else -%}
            {%- do print(amenity_name) -%}
        {%- endif -%}
    {%- endfor -%}

    {{ return('') }}
{%- endmacro %}
