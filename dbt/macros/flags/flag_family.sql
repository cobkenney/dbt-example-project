{#
    The registry behind every generated-flag macro, and the one place that knows
    the difference between the two families.

        {{ flag_family('amenity').prefix }}   ->  has_
        {{ flag_family('verification').seed }} ->  known_verification_methods

    THE POINT OF THIS FILE. Both families do the same four things — slugify a
    name into a column identifier, read the pinned list out of a seed, emit yml
    for an undeclared flag, regenerate the seed from the data — and each used to
    have its own macro for all four. Eight macros, two of every behaviour, and the
    two copies drifted: the documented run order was reversed between them, and one
    of the two orders could not work at all. Generic macros plus a config table
    means a behaviour is written once and a family is data.

    ADDING A FAMILY is an entry here and nothing else. The four macros pick it up
    with no edit.

    FIELDS

      label, plural      Prose, for the messages the generators print.
      prefix             Leads every generated column name. Keeps the families
                         from colliding in a model carrying both, and makes a
                         name starting with a digit ('65 inch HDTV...') a legal
                         identifier.
      seed               The pinned list. THE SEED IS THE COLUMN LIST — see
                         get_flag_values() for why that is a seed and not a query
                         against the data.
      seed_column        Column within it.
      source_model       Where generate_flag_seed() looks to DISCOVER values.
                         Deliberately not the seed: reading the seed there would
                         emit the file back to itself and never notice a new
                         value.
      source_column      Column within it.
      source_is_json     True when source_column is a JSON array needing a
                         lateral flatten rather than a plain select distinct.
      flag_model         The model whose yml generate_flag_yml() writes for, and
                         whose columns it reads to decide what is already
                         declared.
      marts              Models that name flags from this family EXPLICITLY
                         rather than passing them through with select *. A new
                         flag stops at flag_model until one of these is edited,
                         so the generators name them in their work orders.
      description        Prose for a generated yml entry. {} is the raw value.
#}
{% macro flag_family(family) -%}

    {%- set families = {
        'amenity': {
            'label': 'amenity',
            'plural': 'amenities',
            'prefix': 'has_',
            'seed': 'known_amenity_names',
            'seed_column': 'amenity_name',
            'source_model': 'int_listing_amenities',
            'source_column': 'amenity_name',
            'source_is_json': false,
            'flag_model': 'int_listing_daily',
            'marts': ['fct_listing_daily', 'dim_listings'],
            'description': 'Whether the listing offers "{}".'
        },
        'verification': {
            'label': 'verification method',
            'plural': 'verification methods',
            'prefix': 'is_verified_',
            'seed': 'known_verification_methods',
            'seed_column': 'verification_method',
            'source_model': 'stg_listings',
            'source_column': 'host_verifications',
            'source_is_json': true,
            'flag_model': 'int_hosts',
            'marts': ['dim_hosts'],
            'description': 'Whether the host completed the "{}" verification.'
        }
    } -%}

    {%- if family not in families -%}
        {%- do exceptions.raise_compiler_error(
            'flag_family: no family ' ~ family ~ '. Known families: '
            ~ families.keys() | join(', ') ~ '. Add one by adding an entry to '
            ~ 'macros/flags/flag_family.sql.'
        ) -%}
    {%- endif -%}

    {{ return(families[family]) }}
{%- endmacro %}
