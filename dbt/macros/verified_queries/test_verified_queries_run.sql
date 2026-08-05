{#
    Runs a semantic views verified queries against the warehouse and fails if
    any of them does not come back with rows.

        models:
          - name: sem_reservations
            data_tests:
              - verified_queries_run:
                  arguments:
                    question: q17

    WHAT THIS PROVES. That each query parses, that every metric and dimension it
    names still resolves, and that it returns at least one row.

    WHAT IT CANNOT PROVE. That the figures are right — a query can run, return
    rows, and be wrong. Verification needs to happen.

    ZERO ROWS IS A FAILURE, not an empty result.

    ENTRIES SHARING SQL ARE RUN ONCE.

#}
{% test verified_queries_run(model, question) %}

    {%- set entries = verified_queries_for(question=question, view=model) -%}

    {#-
        One branch per distinct query, unioned. count(*) with a bare `having`, so
        a row is emitted only where the query returned nothing. The count forces
        the whole query to run; a `where false` wrapper would let the optimizer
        prune the subtree and would then only be checking that the names resolve.

        Each verified query is emitted at the indentation it was written with
        rather than reindented, so the SQL in a failure reads the same as the
        macro it came from.
    -#}
    {%- set seen = [] -%}
    {%- for entry in entries if entry.sql not in seen -%}
        {%- do seen.append(entry.sql) -%}
        {{- '\nunion all\n' if not loop.first }}
select
    '{{ entry.name }}' as verified_query,
    count(*) as rows_returned
from (
{{ entry.sql }}
)
having count(*) = 0
    {%- endfor %}

{% endtest %}
