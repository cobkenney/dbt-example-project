{#
    Irreversibly pseudonymize a PII column at the staging boundary, so no dbt
    model downstream of staging ever holds the plaintext.

        {{ mask_pii('host_name') }} as host_name_masked

    Salted SHA-256, truncated to 16 hex characters. Each part earns its place:

    * Hashing, not dropping, keeps the column usable as a grouping key — rows
      sharing a hash share a value — without revealing the value itself.

    * The salt is what makes it irreversible. Host names are first names from a
      space of maybe a few thousand candidates, so an UNSALTED sha2('Maria') is
      recovered instantly by hashing a name list and matching. A secret salt
      defeats that; without it, this macro would be theatre.

    * Truncation to 16 chars keeps the column readable in a SQL client. 64 bits
      still makes collisions negligible at this cardinality, and the point is
      pseudonymity, not a cryptographic commitment.

    The salt comes from PII_HASH_SALT. The default is deliberately NOT a secret
    and is only there so a fresh clone builds — set the env var in any
    environment where the masking has to actually hold. Rotating it changes every
    hash, so downstream joins on a masked column break by design; that is the
    tradeoff for the salt being rotatable at all.

    * NULL in gives NULL out, rather than hashing a coalesced empty string.
      Otherwise "this host has no name recorded" would be indistinguishable from
      a real name, and every NULL row would share one hash and look like a single
      prolific host. sha2 already propagates NULL; this is called out because
      coalescing here is the tempting mistake.

    Scope note: this protects the dbt layers, which is where analysts read. It
    does nothing about the plaintext still sitting in RAW_DATA — that needs a
    Snowflake masking policy or a change to what the loader lands, neither of
    which dbt can express.
#}
{% macro mask_pii(column_name) -%}
    {%- set salt = env_var('PII_HASH_SALT', 'dbt-example-project-default-salt') -%}
    left(sha2(concat('{{ salt }}', {{ column_name }}), 256), 16)
{%- endmacro %}
