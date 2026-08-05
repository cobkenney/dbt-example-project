{#
   Returns the config row for a family (amenity or verification):
   prefix, seed, source model, flag model, marts, prose template.
   Its the only place the two families differ, so adding a third
   is one entry and no macro edits.
#}
{% macro get_flag_values(family) -%}
    {%- if not execute -%}
        {{ return([]) }}
    {%- endif -%}

    {%- set config = flag_family(family) -%}

    {%- set query -%}
        select {{ config.seed_column }}
        from {{ ref(config.seed) }}
        order by 1
    {%- endset -%}

    {{ return(run_query(query).columns[0].values()) }}
{%- endmacro %}
