{#
    Regenerate a family's seed CSV from the data.

        dbt --quiet run-operation generate_flag_seed --args '{family: amenity}' \
            > seeds/known_amenity_names.csv

        dbt --quiet run-operation generate_flag_seed \
            --args '{family: verification}' \
            > seeds/known_verification_methods.csv

    Prints the CSV — a header line and one value per row, ordered so the file diff
    stays stable between runs. Redirect it over the seed, review the diff, commit.

    `--quiet` IS NOT OPTIONAL, and it goes before run-operation. dbt writes its own
    log lines ("Running with dbt=...", "Registered adapter: ...") to STDOUT, not
    stderr, so without it three log lines land at the top of the CSV and the seed
    fails to load. Verified: with --quiet the output is byte-identical to the
    committed file; without it the file gains three junk rows.

    WHY A MACRO AND NOT A HAND-EDITED FILE. The seed is the accepted-values list
    for the family's bridge model, so it has to match the source exactly, including
    the Unicode apostrophes some amenity names carry. Retyping a name is how a false
    positive gets committed, and the warning it silences is the one asking for the
    work.

    THE ONLY MACRO IN THIS SET THAT READS THE DATA. get_flag_values() reads the
    seed, so calling it here would emit the file back to itself and never notice a
    new value.

    ORDER OF OPERATIONS, the same for every family: the seed drives the generated
    flag columns, so regenerating it is what ADDS THE COLUMN. That makes this step
    first, not last:

        1. regenerate the seed — the diff is the reviewable decision
        2. dbt run-operation generate_flag_yml --args '{family: <family>}'
        3. decide whether the family's marts carry the flag

    It has to be this way round rather than the reverse. Step 2 reads the seed, via
    get_flag_values(), so a value that exists only in the source is invisible to it
    — run it before step 1 and it emits nothing at all.

    The tripwire is still real. Regenerating turns the relationships warning green
    by definition, so the commit that does it has to carry steps 2 and 3 with it — a
    seed diff on its own means a column exists with no documentation and no mart
    decision behind it. The marts name their flags explicitly rather than passing
    them through with select *, so step 3 is what actually gets the flag to a mart.

    Uses print() rather than log() so the output carries no timestamp prefix and can
    be redirected straight to the file.

    Quoting follows RFC 4180 and matches what dbt's seed loader expects: a value is
    wrapped in double quotes only when it contains a comma, a double quote or a
    newline, and an embedded double quote is doubled. One amenity name needs it
    today — "65 inch HDTV with Netflix, HBO Max, Amazon Prime Video, standard
    cable". Apostrophes need no quoting at all, ASCII or Unicode. Applied to every
    family rather than only to amenities: verification methods are snake_case
    identifiers with nothing to escape today, and the branch is a no-op for them,
    but it costs nothing and the alternative is one family silently lacking it if
    the source ever changes shape.
#}
{% macro generate_flag_seed(family) -%}

    {%- if not execute -%}{{ return('') }}{%- endif -%}

    {%- set config = flag_family(family) -%}

    {#- A JSON array needs flattening into rows; a plain column does not. -#}
    {%- if config.source_is_json -%}
        {%- set query -%}
            select distinct value.value::string as flag_value
            from {{ ref(config.source_model) }} as source_rows,
                lateral flatten(
                    input => try_parse_json(source_rows.{{ config.source_column }})
                ) as value
            order by 1
        {%- endset -%}
    {%- else -%}
        {%- set query -%}
            select distinct {{ config.source_column }} as flag_value
            from {{ ref(config.source_model) }}
            order by 1
        {%- endset -%}
    {%- endif -%}

    {%- do print(config.seed_column) -%}

    {%- for flag_value in run_query(query).columns[0].values() -%}
        {%- set needs_quoting =
            ',' in flag_value
            or '"' in flag_value
            or '\n' in flag_value -%}
        {%- if needs_quoting -%}
            {%- do print(
                '"' ~ flag_value | replace('"', '""') ~ '"'
            ) -%}
        {%- else -%}
            {%- do print(flag_value) -%}
        {%- endif -%}
    {%- endfor -%}

    {{ return('') }}
{%- endmacro %}
