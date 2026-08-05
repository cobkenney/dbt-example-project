{#
    Turn a raw value into a safe boolean column identifier for its family.

        {{ flag_name('amenity', 'Air conditioning') }}      -> has_air_conditioning
        {{ flag_name('amenity', 'Children’s books') }}      -> has_children_s_books
        {{ flag_name('amenity', 'Pack ’n Play/travel crib') }}
                                                    -> has_pack_n_play_travel_crib
        {{ flag_name('verification', 'government_id') }}
                                                    -> is_verified_government_id

    Every run of non-alphanumeric characters collapses to one underscore, which is
    what makes the Unicode apostrophes, colons, slashes and commas in the source
    amenity names safe. Values starting with a digit ('65 inch HDTV...') are fine
    because the family's prefix always leads.

    The prefix is the only thing that differs between families, and it comes from
    flag_family(). `has_email` would read as a listing feature rather than a host
    verification, and a model carrying both families needs the two sets of columns
    not to collide.

    LOWERCASES, which is load-bearing rather than cosmetic: an upstream `Email`
    would slugify onto the same identifier as `email` rather than producing a
    second flag. The relationships test on each bridge model is what reports it,
    since the seed match is case-sensitive.
#}
{% macro flag_name(family, value) -%}
    {%- set config = flag_family(family) -%}
    {%- set slug = modules.re.sub(
        '[^a-z0-9]+', '_', value | lower
    ) | trim('_') -%}
    {{- config.prefix ~ slug -}}
{%- endmacro %}
