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
    Distinct amenity names from the changelog, ordered so the generated column
    order is stable between runs.

    Returns [] when execute is false (dbt parse / dbt ls), so those commands
    still work without a warehouse connection — the model body is not run then,
    only rendered.
#}
{% macro get_amenity_names() -%}
    {%- if not execute -%}
        {{ return([]) }}
    {%- endif -%}

    {%- set query -%}
        select distinct amenity.value::string as amenity_name
        from {{ ref('stg_amenities_changelog') }} as changelog,
            lateral flatten(
                input => try_parse_json(changelog.amenities)
            ) as amenity
        order by 1
    {%- endset -%}

    {{ return(run_query(query).columns[0].values()) }}
{%- endmacro %}
