{#
    Codegen for the generated verification flag columns on int_hosts.

        dbt run-operation generate_verification_flag_yml

    Prints a yml block for every is_verified_* flag not already declared in
    int_hosts.yml, ready to paste into its `columns:` block. Also reports flags
    declared in the yml that no longer exist in the data.

    Same shape and same reasoning as generate_amenity_flag_yml — see that macro
    for why the yml has to be generated rather than looped over in place (dbt
    parses yml as YAML, not as a Jinja template).

    One difference worth knowing: dim_hosts names its flags explicitly rather
    than passing them through with select *, so a new method needs adding in TWO
    places — int_hosts.yml and dim_hosts.sql/.yml. This macro only covers
    int_hosts.yml; the stale report is what catches the mart drifting.

    Pass --args '{all: true}' to re-emit every flag instead of only the missing
    ones. Flags already declared keep their {{ doc(...) }} reference so curated
    descriptions in docs.md are never replaced by generated prose.
#}
{% macro generate_verification_flag_yml(all=false) -%}

    {%- if not execute -%}{{ return('') }}{%- endif -%}

    {#- Flags already documented in the model's yml. -#}
    {%- set declared = [] -%}
    {%- for node in graph.nodes.values() -%}
        {%- if node.name == 'int_hosts' -%}
            {%- for column_name in node.columns.keys() -%}
                {%- do declared.append(column_name | lower) -%}
            {%- endfor -%}
        {%- endif -%}
    {%- endfor -%}

    {%- set method_names = get_verification_methods() -%}
    {%- set flags_in_data = [] -%}
    {%- set to_emit = [] -%}

    {%- for method_name in method_names -%}
        {%- set flag = verification_flag_name(method_name) -%}
        {%- do flags_in_data.append(flag) -%}
        {%- if all or flag not in declared -%}
            {%- do to_emit.append((flag, method_name)) -%}
        {%- endif -%}
    {%- endfor -%}

    {#- Flags the yml declares that the data no longer produces. -#}
    {%- set stale = [] -%}
    {%- for column_name in declared -%}
        {%- if column_name.startswith('is_verified_')
               and column_name not in flags_in_data -%}
            {%- do stale.append(column_name) -%}
        {%- endif -%}
    {%- endfor -%}

    {%- do print('') -%}
    {%- do print(
        method_names | length ~ ' verification methods in source; '
        ~ declared | length ~ ' columns declared in yml; '
        ~ to_emit | length ~ ' to emit.'
    ) -%}

    {%- if stale | length > 0 -%}
        {%- do print('') -%}
        {%- do print(
            'STALE: declared in yml but absent from the data. Remove from '
            ~ 'int_hosts.yml AND from dim_hosts.sql / dim_hosts.yml, which name '
            ~ 'these explicitly -> ' ~ stale | join(', ')
        ) -%}
    {%- endif -%}

    {%- if to_emit | length == 0 -%}
        {%- do print('') -%}
        {%- do print('Nothing to emit — the yml covers every flag.') -%}
        {{ return('') }}
    {%- endif -%}

    {%- do print('') -%}
    {%- do print(
        'Reminder: dim_hosts selects these by name. Anything emitted below also '
        ~ 'needs adding to dim_hosts.sql and dim_hosts.yml to reach the mart.'
    ) -%}
    {%- do print('') -%}
    {%- do print(
        '--- paste into the columns: block of int_hosts.yml ---'
    ) -%}
    {%- do print('') -%}

    {%- for (flag, method_name) in to_emit -%}
        {%- do print('      - name: ' ~ flag) -%}
        {%- if flag in declared -%}
            {#- Already curated in docs.md — keep the reference, not prose. -#}
            {%- do print(
                '        description: "{{ doc(\'' ~ flag ~ '\') }}"'
            ) -%}
        {%- else -%}
            {%- do print('        description: >') -%}
            {%- do print(
                '          Whether the host completed the "' ~ method_name
                ~ '" verification.'
            ) -%}
            {%- do print(
                '          Generated flag — exact match on that method name.'
            ) -%}
        {%- endif -%}
        {%- do print('') -%}
    {%- endfor -%}

    {{ return('') }}
{%- endmacro %}
