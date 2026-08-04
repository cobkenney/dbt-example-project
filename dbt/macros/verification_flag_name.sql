{#
    Turn a raw verification method into a safe boolean column identifier.

    'email'                 -> is_verified_email
    'government_id'         -> is_verified_government_id
    'offline_government_id' -> is_verified_offline_government_id

    Same normalization as amenity_flag_name — every run of non-alphanumeric
    characters collapses to one underscore — but a different prefix, because
    these are not amenities and `has_email` would read as a listing feature.

    `is_verified_` also keeps the two families of generated columns from
    colliding in a model that carries both.
#}
{% macro verification_flag_name(method_name) -%}
    {%- set slug = modules.re.sub(
        '[^a-z0-9]+', '_', method_name | lower
    ) | trim('_') -%}
    {{- 'is_verified_' ~ slug -}}
{%- endmacro %}


{#
    The pinned verification methods, ordered so the generated column order is
    stable between runs.

    READS THE SEED, NOT THE DATA — seeds/known_verification_methods.csv, which is
    the same list the relationships test on int_host_verifications checks against.
    Same contract and same reasoning as get_amenity_names(); see that macro for
    why the column list is a committed decision rather than a query result.

    The short version: this used to flatten host_verifications on stg_listings, so
    a method appearing or disappearing in the source silently added or dropped an
    is_verified_* column on int_hosts. Dropping one is the dangerous direction —
    dim_hosts names all 11 flags explicitly, so it would fail at run time on a
    column that vanished without a commit.

    A SEED at 11 values, where int_host_verifications.yml previously argued the
    inline list was fine at this size. That was true when the seed only fed a
    test. It stopped being true once the seed also decides int_hosts' column list:
    an accepted_values list in yml cannot be read by a Jinja loop, so keeping it
    inline would mean two hand-maintained copies of the same 11 values, and the
    failure mode of them disagreeing is a column with no test or a test with no
    column.

    DEPENDENCY: int_hosts declares `-- depends_on: {{ ref(...) }}` on the seed in
    its own body, because a ref() inside a macro is invisible to dbt's parser —
    at parse time `execute` is false and this returns before rendering it.

    Unlike amenities, EVERY method in the list is flagged, with no coverage floor.
    `email` and `phone` are held by all 36 hosts and so carry no predictive
    signal, but a flag that is universally true is a tripwire: the day a host
    lands without a verified email, that flag goes false and is queryable.
    Dropping universal methods would mean losing the ability to notice.

    Returns [] when execute is false (dbt parse / dbt ls), so those commands
    still work without a warehouse connection — the model body is not run then,
    only rendered.
#}
{% macro get_verification_methods() -%}
    {%- if not execute -%}
        {{ return([]) }}
    {%- endif -%}

    {%- set query -%}
        select verification_method
        from {{ ref('known_verification_methods') }}
        order by 1
    {%- endset -%}

    {{ return(run_query(query).columns[0].values()) }}
{%- endmacro %}
