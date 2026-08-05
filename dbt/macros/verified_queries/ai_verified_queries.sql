{#
    Emits the whole AI_VERIFIED_QUERIES clause for a semantic view, so each
    view file carries one line rather than a wall of quoted SQL.

        {{ ai_verified_queries(['q17', 'q22', 'q23']) }}

    Each question name resolves to a verified_queries_<name> macro, called with
    the view relation and returning a list of {name, question, sql} entries.
    Resolution goes through `context`, so a question with no macro fails at
    compile time with the name in the message rather than emitting nothing.

    Grammar, per Snowflake, is one entry per name:

        AI_VERIFIED_QUERIES (
            <name> AS ( QUESTION '<text>' SQL '<query>' )
            [ , ... ]
        )

    It belongs after AI_SQL_GENERATION in the DDL.

    QUESTION and SQL are single-quoted SQL literals, so an apostrophe in either
    would end the string early and leave Snowflake parsing the rest as DDL — an
    error reported nowhere near its cause. Both are therefore escaped here, by
    doubling, which is how a literal apostrophe is written inside a SQL literal.

    Escaping rather than forbidding, unlike the COMMENT convention elsewhere in
    these views: a verified query legitimately contains quoted strings of its own.
    The union branches in q14 label each row with an amenity name, and that label
    has to be a literal. Callers can write apostrophes freely.

    Nothing about the SQL is validated. Snowflake does not check a verified
    query at create time either — a query against a table that does not exist
    builds green — so a query only becomes verified once the validator in
    TODO item 14 runs it and pins its result.

    NO FIGURES IN THE HEADERS of the per-question macros, by convention. A header
    says why its query is SHAPED the way it is and what the plausible wrong answer
    would be; it does not restate what the query currently returns. A figure in a
    comment is true of the load it was read off and goes wrong silently the next
    time the source loads, with no test failing. Where a result is worth pinning,
    the query returns it — several entries here carry a coverage count or a
    side-by-side comparison for exactly that reason, so the number is read off the
    warehouse rather than off a comment. The QUESTION and SQL text these macros
    emit is figure-free for a stronger reason — a client reads it and would quote a
    number in it as fact. Where a boundary is part of the query rather than a claim
    about the data, such as a price band in a case expression, it stays: it is what
    the query does, not what the data currently says.
#}
{% macro ai_verified_queries(questions, view=none) -%}

    {%- set view = view or this -%}
    {%- set entries = [] -%}

    {%- for question in questions -%}
        {%- set macro_name = 'verified_queries_' ~ question -%}
        {%- if macro_name not in context -%}
            {%- do exceptions.raise_compiler_error(
                'ai_verified_queries: no macro ' ~ macro_name ~ '() for '
                ~ 'question ' ~ question ~ '. Expected it in '
                ~ 'macros/verified_queries/.'
            ) -%}
        {%- endif -%}
        {%- do entries.extend(context[macro_name](view=view)) -%}
    {%- endfor -%}

AI_VERIFIED_QUERIES (
    {% for entry in entries %}
    {{- entry.name }} AS (
        QUESTION '{{ entry.question | replace("'", "''") }}'
        SQL '{{ entry.sql | replace("'", "''") }}'
    ){{ ',' if not loop.last }}
    {% endfor %}
)
{%- endmacro %}
