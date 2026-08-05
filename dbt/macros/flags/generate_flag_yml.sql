{#
    Codegen for a family's generated flag columns.

        dbt run-operation generate_flag_yml --args '{family: amenity}'
        dbt run-operation generate_flag_yml --args '{family: verification}'

    Prints a yml block for every flag in the family not already declared in its
    model's yml, ready to paste into that model's `columns:` block. Also reports
    flags declared in the yml that the seed no longer produces — which is how a
    stale has_pool entry gets caught.

    The yml stays the source of truth. dbt parses yml as YAML, not as a Jinja
    template, so a `{% raw %}{% for %}{% endraw %}` loop cannot live there — it
    fails with "found character that cannot start any token". This macro generates
    the text; a human commits it.

    Uses print() rather than log() so the output has no timestamp prefix and can be
    pasted directly.

    Pass all=true to re-emit every flag instead of only the missing ones. Flags
    already declared keep their {{ doc(...) }} reference so the curated descriptions
    in docs.md are never replaced by generated prose:

        dbt run-operation generate_flag_yml --args '{family: amenity, all: true}'

    READS THE SEED, via get_flag_values(), so run this AFTER regenerating the seed
    rather than before — a value that exists only in the source is invisible here
    and this emits nothing for it. generate_flag_seed() documents the full order.

    Names the family's marts in its reminder, because they select their flags
    explicitly rather than passing them through with select *: anything emitted here
    reaches the flag model only, and a second edit is what gets it to a mart.
#}
{% macro generate_flag_yml(family, all=false) -%}

    {%- if not execute -%}{{ return('') }}{%- endif -%}

    {%- set config = flag_family(family) -%}

    {#- Flags already documented in the model's yml. -#}
    {%- set declared = [] -%}
    {%- for node in graph.nodes.values() -%}
        {%- if node.name == config.flag_model -%}
            {%- for column_name in node.columns.keys() -%}
                {%- do declared.append(column_name | lower) -%}
            {%- endfor -%}
        {%- endif -%}
    {%- endfor -%}

    {%- set values = get_flag_values(family) -%}
    {%- set flags_in_seed = [] -%}
    {%- set to_emit = [] -%}

    {%- for value in values -%}
        {%- set flag = flag_name(family, value) -%}
        {%- do flags_in_seed.append(flag) -%}
        {%- if all or flag not in declared -%}
            {%- do to_emit.append((flag, value)) -%}
        {%- endif -%}
    {%- endfor -%}

    {#- Flags the yml declares that the seed no longer produces. -#}
    {%- set stale = [] -%}
    {%- for column_name in declared -%}
        {%- if column_name.startswith(config.prefix)
               and column_name not in flags_in_seed -%}
            {%- do stale.append(column_name) -%}
        {%- endif -%}
    {%- endfor -%}

    {%- do print('') -%}
    {%- do print(
        values | length ~ ' ' ~ config.plural ~ ' in seed ' ~ config.seed ~ '; '
        ~ declared | length ~ ' columns declared in ' ~ config.flag_model
        ~ '.yml; ' ~ to_emit | length ~ ' to emit.'
    ) -%}

    {%- if stale | length > 0 -%}
        {%- do print('') -%}
        {%- do print(
            'STALE: declared in yml but absent from the seed. Remove from '
            ~ config.flag_model ~ '.yml AND from '
            ~ config.marts | join(' / ') ~ ', which name these explicitly -> '
            ~ stale | join(', ')
        ) -%}
    {%- endif -%}

    {%- if to_emit | length == 0 -%}
        {%- do print('') -%}
        {%- do print('Nothing to emit — the yml covers every flag.') -%}
        {{ return('') }}
    {%- endif -%}

    {%- do print('') -%}
    {%- do print(
        'Reminder: ' ~ config.marts | join(' and ') ~ ' select these by name. '
        ~ 'Anything emitted below also needs adding there to reach the marts.'
    ) -%}
    {%- do print('') -%}
    {%- do print(
        '--- paste into the columns: block of ' ~ config.flag_model ~ '.yml ---'
    ) -%}
    {%- do print('') -%}

    {%- for (flag, value) in to_emit -%}
        {%- do print('      - name: ' ~ flag) -%}
        {%- if flag in declared -%}
            {#- Already curated in docs.md — keep the reference, not prose. -#}
            {%- do print(
                '        description: "{{ doc(\'' ~ flag ~ '\') }}"'
            ) -%}
        {%- else -%}
            {%- do print('        description: >') -%}
            {%- do print(
                '          ' ~ config.description | replace('{}', value)
            ) -%}
            {%- do print(
                '          Generated flag — exact match on that '
                ~ config.label ~ ' name.'
            ) -%}
        {%- endif -%}
        {%- do print('') -%}
    {%- endfor -%}

    {{ return('') }}
{%- endmacro %}
