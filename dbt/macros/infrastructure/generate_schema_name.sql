{#
    Route each layer to its own schema so permissions can be granted per
    schema: analytics_stg, analytics_int, analytics_seed, and one schema per
    mart (core_mart). The schema name comes from the `+schema:` config in
    dbt_project.yml.

    dbt built-in behaviour concatenates the profile schema with `+schema:`
    (giving `dbt_ckenney_core_mart`), which is what we want in dev — one
    developer's build cannot clobber another's, or the shared tables analysts
    query. In prod we want the bare name, since that is what grants are
    written against.

    So:
      target.name == 'prod'  ->  core_mart
      anything else          ->  dbt_ckenney_core_mart

    Models with no `+schema:` fall back to the profile schema unchanged, which
    keeps `dbt init`-style scratch models and anything outside the three
    layers working.
#}

{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- set default_schema = target.schema -%}

    {%- if custom_schema_name is none -%}

        {{ default_schema }}

    {%- elif target.name == 'prod' -%}

        {{ custom_schema_name | trim }}

    {%- else -%}

        {{ default_schema }}_{{ custom_schema_name | trim }}

    {%- endif -%}

{%- endmacro %}
