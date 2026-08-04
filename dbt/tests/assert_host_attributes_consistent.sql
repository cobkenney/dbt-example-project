-- Guards the grain reconstruction in int_hosts.
--
-- Hosts are denormalized onto the listings table rather than arriving as their
-- own source, so int_hosts rebuilds the host grain by grouping on host_id and
-- picking each attribute with min(). That is only honest while every listing of
-- a given host agrees on those attributes.
--
-- If a host's two listings ever disagree — a name corrected on one row, a
-- host_since that differs — min() would silently pick one and the other value
-- would vanish without trace. This fails instead, which is the signal that
-- hosts need their own source or a real SCD treatment.
select
    host_id,
    count(distinct host_name_masked) as distinct_names,
    count(distinct host_since) as distinct_since_dates,
    count(distinct host_location) as distinct_locations,
    count(distinct host_verifications) as distinct_verifications
from {{ ref('stg_listings') }}
group by all
having
    count(distinct host_name_masked) > 1
    or count(distinct host_since) > 1
    or count(distinct host_location) > 1
    or count(distinct host_verifications) > 1
