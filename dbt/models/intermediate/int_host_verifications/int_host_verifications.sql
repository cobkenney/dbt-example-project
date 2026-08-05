-- One row per host per verification method — the bridge grain, kept alongside
-- the generated flags on int_hosts.
--
-- Both shapes earn their place. The flags answer "which hosts have X" in a
-- filter; this answers "how many hosts hold each method" and "how does adoption
-- vary" without naming 11 columns, and it does not change shape when the source
-- adds a method.
--
-- host_verifications arrives as a JSON array string, exactly like amenities:
--   '["email", "phone", "reviews", "kba"]'
-- 11 distinct methods across 36 hosts.
with hosts as (

    -- Grouped to the host grain first. Verifications are a host attribute
    -- denormalized onto every listing row, so flattening stg_listings directly
    -- would emit a row per listing per method and overcount multi-listing
    -- hosts. min() is safe here for the same reason it is in int_hosts, and
    -- tests/assert_host_attributes_consistent.sql asserts the premise.
    select
        host_id,
        min(host_verifications) as host_verifications
    from {{ ref('stg_listings') }}
    group by all

),

flattened as (

    select
        hosts.host_id,
        method.value::string as verification_method
    from hosts,
        lateral flatten(
            input => try_parse_json(hosts.host_verifications)
        ) as method

)

-- distinct rather than raw flatten output: a malformed source array could
-- repeat a method for one host, which would break the declared grain.
select distinct
    host_id,
    verification_method
from flattened
