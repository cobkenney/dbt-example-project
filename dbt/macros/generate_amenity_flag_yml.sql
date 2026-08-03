{#
    Codegen for the generated amenity flag columns on int_amenities_current.

        dbt run-operation generate_amenity_flag_yml

    Prints a yml block for every amenity flag not already declared in
    int_amenities_current.yml, ready to paste into its `columns:` block. Also
    reports flags declared in the yml that no longer exist in the data — which
    is how the stale has_pool entry would have been caught.

    The yml stays the source of truth. dbt parses yml as YAML, not as a Jinja
    template, so a `{% raw %}{% for %}{% endraw %}` loop cannot live there —
    it fails with "found character that cannot start any token". This macro
    generates the text; a human commits it.

    Uses print() rather than log() so the output has no timestamp prefix and can
    be pasted directly.

    Pass --args '{all: true}' to re-emit all 81 flags instead of only the
    missing ones. Flags already declared keep their {{ doc(...) }} reference so
    the curated descriptions in docs.md are never replaced by generated prose.
#}
{% macro generate_amenity_flag_yml(all=false) -%}

    {%- if not execute -%}{{ return('') }}{%- endif -%}

    {#- Flags already documented in the model's yml. -#}
    {%- set declared = [] -%}
    {%- for node in graph.nodes.values() -%}
        {%- if node.name == 'int_amenities_current' -%}
            {%- for column_name in node.columns.keys() -%}
                {%- do declared.append(column_name | lower) -%}
            {%- endfor -%}
        {%- endif -%}
    {%- endfor -%}

    {%- set amenity_names = get_amenity_names() -%}
    {%- set flags_in_data = [] -%}
    {%- set to_emit = [] -%}

    {%- for amenity_name in amenity_names -%}
        {%- set flag = amenity_flag_name(amenity_name) -%}
        {%- do flags_in_data.append(flag) -%}
        {%- if all or flag not in declared -%}
            {%- do to_emit.append((flag, amenity_name)) -%}
        {%- endif -%}
    {%- endfor -%}

    {#- Flags the yml declares that the data no longer produces. -#}
    {%- set stale = [] -%}
    {%- for column_name in declared -%}
        {%- if column_name.startswith('has_')
               and column_name not in flags_in_data -%}
            {%- do stale.append(column_name) -%}
        {%- endif -%}
    {%- endfor -%}

    {%- do print('') -%}
    {%- do print(
        amenity_names | length ~ ' amenities in source; '
        ~ declared | length ~ ' columns declared in yml; '
        ~ to_emit | length ~ ' to emit.'
    ) -%}

    {%- if stale | length > 0 -%}
        {%- do print('') -%}
        {%- do print(
            'STALE: declared in yml but absent from the data. Remove from the '
            ~ 'yml and from any model selecting them -> ' ~ stale | join(', ')
        ) -%}
    {%- endif -%}

    {%- if to_emit | length == 0 -%}
        {%- do print('') -%}
        {%- do print('Nothing to emit — the yml covers every flag.') -%}
        {{ return('') }}
    {%- endif -%}

    {%- do print('') -%}
    {%- do print(
        '--- paste into the columns: block of '
        ~ 'int_amenities_current.yml ---'
    ) -%}
    {%- do print('') -%}

    {%- for (flag, amenity_name) in to_emit -%}
        {%- do print('      - name: ' ~ flag) -%}
        {%- if flag in declared -%}
            {#- Already curated in docs.md — keep the reference, not prose. -#}
            {%- do print(
                '        description: "{{ doc(\'' ~ flag ~ '\') }}"'
            ) -%}
        {%- else -%}
            {%- do print('        description: >') -%}
            {%- do print(
                '          Whether the listing offers "' ~ amenity_name ~ '".'
            ) -%}
            {%- do print(
                '          Generated flag — exact match on that amenity name.'
            ) -%}
        {%- endif -%}
        {%- do print('') -%}
    {%- endfor -%}

    {{ return('') }}
{%- endmacro %}
