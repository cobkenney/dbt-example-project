with hosts as (

    select
        host_id,
        -- assumes verifications are the same for all host rows
        -- if not, may need SCD / applied more accurately to daily listing
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

select distinct
    host_id,
    verification_method
from flattened
