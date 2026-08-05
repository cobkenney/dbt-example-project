{#
    Maps a question name to its verified-query macro and returns that macro's
    entries. One branch per question, and the only place the mapping lives —
    both ai_verified_queries() and the verified_queries_run test come through
    here, so a question name is resolved the same way whether it is being
    emitted into DDL or executed against the warehouse.

    A HAND-WRITTEN IF-CHAIN, WHICH LOOKS LIKE THE WRONG ANSWER. The obvious
    version is `context['verified_queries_' ~ question](view=view)`, and that is
    what this replaced — it works fine in a model, and it is what the DDL
    dispatcher used to do. It CANNOT work in a test.

    Why, established by probe: dbt renders a generic test twice. The first pass
    gets the full macro namespace; the second gets a restricted context of ~65
    keys, and project macros are absent from it. That context is also populated
    LAZILY — a macro appears in `context` only once something references it
    STATICALLY, by name, at template-compile time. So a dynamic subscript finds
    nothing to resolve on the second pass and the test fails with
    `'verified_queries_q17' is undefined` at parse. Nesting the dynamic lookup
    one macro deeper does not help; the restricted context follows the call.

    A static reference is what survives, because it is what makes dbt load the
    macro in the first place. Hence 26 branches naming 26 macros. The cost is
    that adding a question means editing this file — caught immediately, since
    the else branch raises rather than returning nothing.

    Every branch returns rather than falling through, so exactly one
    per-question macro is called and the other 25 are never evaluated.
#}
{% macro verified_queries_for(question, view) -%}

    {%- if question == 'q01' -%}{{ return(verified_queries_q01(view=view)) }}
    {%- elif question == 'q02' -%}{{ return(verified_queries_q02(view=view)) }}
    {%- elif question == 'q03' -%}{{ return(verified_queries_q03(view=view)) }}
    {%- elif question == 'q04' -%}{{ return(verified_queries_q04(view=view)) }}
    {%- elif question == 'q05' -%}{{ return(verified_queries_q05(view=view)) }}
    {%- elif question == 'q06' -%}{{ return(verified_queries_q06(view=view)) }}
    {%- elif question == 'q07' -%}{{ return(verified_queries_q07(view=view)) }}
    {%- elif question == 'q08' -%}{{ return(verified_queries_q08(view=view)) }}
    {%- elif question == 'q09' -%}{{ return(verified_queries_q09(view=view)) }}
    {%- elif question == 'q10' -%}{{ return(verified_queries_q10(view=view)) }}
    {%- elif question == 'q11' -%}{{ return(verified_queries_q11(view=view)) }}
    {%- elif question == 'q12' -%}{{ return(verified_queries_q12(view=view)) }}
    {%- elif question == 'q13' -%}{{ return(verified_queries_q13(view=view)) }}
    {%- elif question == 'q14' -%}{{ return(verified_queries_q14(view=view)) }}
    {%- elif question == 'q15' -%}{{ return(verified_queries_q15(view=view)) }}
    {%- elif question == 'q16' -%}{{ return(verified_queries_q16(view=view)) }}
    {%- elif question == 'q17' -%}{{ return(verified_queries_q17(view=view)) }}
    {%- elif question == 'q18' -%}{{ return(verified_queries_q18(view=view)) }}
    {%- elif question == 'q19' -%}{{ return(verified_queries_q19(view=view)) }}
    {%- elif question == 'q20' -%}{{ return(verified_queries_q20(view=view)) }}
    {%- elif question == 'q21' -%}{{ return(verified_queries_q21(view=view)) }}
    {%- elif question == 'q22' -%}{{ return(verified_queries_q22(view=view)) }}
    {%- elif question == 'q23' -%}{{ return(verified_queries_q23(view=view)) }}
    {%- elif question == 'q24' -%}{{ return(verified_queries_q24(view=view)) }}
    {%- elif question == 'q25' -%}{{ return(verified_queries_q25(view=view)) }}
    {%- elif question == 'q26' -%}{{ return(verified_queries_q26(view=view)) }}
    {%- else -%}
        {%- do exceptions.raise_compiler_error(
            'verified_queries_for: unknown question ' ~ question ~ '. Add a '
            ~ 'branch here and a verified_queries_' ~ question ~ '() macro in '
            ~ 'macros/verified_queries/.'
        ) -%}
    {%- endif -%}
{%- endmacro %}
