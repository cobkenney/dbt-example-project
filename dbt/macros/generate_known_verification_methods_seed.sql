{#
    Regenerate seeds/known_verification_methods.csv from the data.

        dbt --quiet run-operation generate_known_verification_methods_seed \
            > seeds/known_verification_methods.csv

    Prints the CSV — a header line and one verification method per row, ordered
    so the file diff stays stable between runs. Redirect it over the seed, review
    the diff, commit.

    `--quiet` IS NOT OPTIONAL, and it goes before run-operation. dbt writes its
    own log lines ("Running with dbt=...", "Registered adapter: ...") to STDOUT,
    not stderr, so without it three log lines land at the top of the CSV and the
    seed fails to load.

    Reads STG_LISTINGS, not the seed — get_verification_methods() reads the seed,
    so calling it here would emit the file back to itself and never notice a new
    method. The flatten below is deliberately the same query that macro used to
    run before the seed became the pinned list.

    ORDER OF OPERATIONS, the trap this macro shares with
    generate_known_amenity_names_seed: regenerating the seed is what ADDS THE
    COLUMN. int_hosts loops over the seed, so a method that only exists in the
    source has no is_verified_* flag until this runs. That is the point — the
    column list is a committed decision — but it means running this first turns
    the warn test green AND widens int_hosts in the same commit, before
    int_hosts.yml or dim_hosts know about the flag. Do the work the warning asks
    for, then regenerate:

        1. dbt run-operation generate_verification_flag_yml   (yml for the flag)
        2. decide whether dim_hosts carries it, and edit it if so
        3. regenerate this seed LAST

    No quoting logic, unlike the amenity seed. Method names are lowercase
    snake_case identifiers straight out of the source JSON — no commas, quotes or
    newlines to escape. If that ever stops being true the relationships test on
    int_host_verifications warns first, and this macro needs the RFC 4180
    branch from generate_known_amenity_names_seed copied in.

    Uses print() rather than log() so the output carries no timestamp prefix and
    can be redirected straight to the file.
#}
{% macro generate_known_verification_methods_seed() -%}

    {%- if not execute -%}{{ return('') }}{%- endif -%}

    {%- set query -%}
        select distinct method.value::string as method_name
        from {{ ref('stg_listings') }} as listings,
            lateral flatten(
                input => try_parse_json(listings.host_verifications)
            ) as method
        order by 1
    {%- endset -%}

    {%- do print('verification_method') -%}

    {%- for method_name in run_query(query).columns[0].values() -%}
        {%- do print(method_name) -%}
    {%- endfor -%}

    {{ return('') }}
{%- endmacro %}
