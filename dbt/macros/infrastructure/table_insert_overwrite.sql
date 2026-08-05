{#
    A `table` materialization that preserves Snowflake Time Travel.

    dbt's built-in table materialization emits `create or replace table`, which
    drops the old table and creates a new object. Time Travel is scoped to an
    object, so the previous version's history is destroyed on every run — you
    cannot ask "what did this mart look like before last night's build?".

    `insert overwrite into ... select` instead replaces the *rows* while keeping
    the same object, so `at(offset => ...)` and `before(statement => ...)` still
    reach the prior state.

    IMPORTANT: `insert overwrite` matches columns by POSITION, not name, and
    cannot change the tables shape. So this materialization compares the
    models column signature to the existing tables and falls back to
    `create or replace` when they differ.

    Falls back to `create or replace` when:
      - the table does not exist yet
      - the existing relation is not a table (e.g. it was a view)
      - the column signature changed (name or order)
      - --full-refresh was passed
#}

{% materialization table_insert_overwrite, adapter='snowflake' %}

    {%- set original_query_tag = set_query_tag() -%}

    {%- set target_relation = this.incorporate(type='table') -%}
    {%- set existing_relation = load_cached_relation(this) -%}

    {{ run_hooks(pre_hooks) }}

    {#-- Decide between insert overwrite and create or replace. --#}
    {%- set can_overwrite = false -%}

    {%- if existing_relation is not none
           and existing_relation.is_table
           and not should_full_refresh() -%}

        {#-- Compare column signatures. `insert overwrite` binds by position,
             so both the names and their order have to match. --#}
        {%- set existing_columns = adapter.get_columns_in_relation(existing_relation)
                                   | map(attribute='name') | map('upper') | list -%}
        {%- set model_columns = get_column_schema_from_query(sql)
                                | map(attribute='name') | map('upper') | list -%}

        {%- if existing_columns == model_columns -%}
            {%- set can_overwrite = true -%}
        {%- else -%}
            {{ log(
                "Column signature changed for " ~ target_relation ~
                " — falling back to create or replace. Time Travel history for "
                ~ "the previous version will not be retained. Existing: " ~
                existing_columns ~ " / model: " ~ model_columns, info=True
            ) }}
        {%- endif -%}

    {%- endif -%}

    {%- if can_overwrite -%}

        {%- call statement('main') -%}
            insert overwrite into {{ target_relation }} (
                {{ model_columns | join(', ') }}
            )
            {{ sql }}
        {%- endcall -%}

    {%- else -%}

        {#-- Not an overwrite candidate: build (or rebuild) the object. Use the
             adapter's own DDL so transient/cluster_by/grants configs still
             apply. --#}
        {%- if existing_relation is not none and not existing_relation.is_table -%}
            {{ drop_relation_if_exists(existing_relation) }}
        {%- endif -%}

        {%- call statement('main') -%}
            {{ create_table_as(False, target_relation, sql) }}
        {%- endcall -%}

    {%- endif -%}

    {{ run_hooks(post_hooks) }}

    {%- set should_revoke = should_revoke(existing_relation, full_refresh_mode=not can_overwrite) -%}
    {% do apply_grants(target_relation, config.get('grants'), should_revoke=should_revoke) %}

    {% do persist_docs(target_relation, model) %}

    {% do unset_query_tag(original_query_tag) %}

    {{ return({'relations': [target_relation]}) }}

{% endmaterialization %}
