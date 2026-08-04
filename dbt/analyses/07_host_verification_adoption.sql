-- Question 21 — which verification methods hosts actually complete, and whether
-- verification tracks performance.
--
-- Reads the bridge grain rather than the 11 is_verified_* flags on dim_hosts:
-- this shape asks "how many hosts hold each method" without naming a column per
-- method, so it does not need editing when the source adds one.
--
-- Verified. Adoption is the finding; performance is not:
--   email                 36 hosts  55.9% occ  $35,766/listing  4.69 review
--   phone                 36        55.9%      $35,766          4.69
--   reviews               34        53.3%      $35,176          4.69
--   kba                   18        49.0%      $33,574          4.80
--   government_id         16        58.9%      $43,054          4.67
--   facebook              10        63.3%      $39,366          4.73
--   jumio                 10        56.9%      $39,115          4.56
--   offline_government_id 10        60.1%      $48,284          4.64
--   selfie                 5        53.6%      $47,378          4.34
--   identity_manual        4        42.4%      $20,469          4.18
--   work_email             4        65.3%      $34,954          4.81
--
-- THERE IS NO TRUST-SIGNAL FINDING HERE, and the table is included partly to
-- show that. The intuition — verified hosts perform better — does not survive:
--   - email and phone cover all 36 hosts, so their rows are just the overall
--     average. They cannot correlate with anything.
--   - The remaining spread is non-monotonic and rides on tiny bases. facebook
--     (a social link, not an identity check) shows the second-highest
--     occupancy; selfie, a stronger check, sits below average. identity_manual
--     looks worst at 4 hosts, which is noise, not a signal.
--   - Direction disagrees between measures: kba has the HIGHEST review score
--     and the LOWEST occupancy.
-- With 36 hosts and 11 methods there are more cells than hosts. Read this as
-- adoption, and do not put an occupancy claim on a verification badge.
--
-- What the model is actually for: email and phone are held by every host, which
-- makes them useless as predictors and valuable as tripwires. A flag that is
-- always true is the only thing whose becoming false is visible. If a host
-- lands tomorrow without a verified email, is_verified_email goes false and
-- this query shows it — impossible if the universal methods had been dropped
-- for carrying no signal.
--
-- host_name is PII and does not exist in plaintext in this project; join on
-- host_id.
with adoption as (

    select
        verifications.verification_method,

        count(*) as hosts,
        round(count(*) / (select count(*) from {{ ref('dim_hosts') }}), 3)
            as host_share,

        round(avg(hosts.occupancy_rate), 3) as avg_occupancy_rate,
        round(avg(hosts.revenue_per_listing), 2) as avg_revenue_per_listing,
        round(avg(hosts.avg_review_score), 2) as avg_review_score,
        round(avg(hosts.verification_count), 2) as avg_verification_count

    from {{ ref('int_host_verifications') }} as verifications
    inner join
        {{ ref('dim_hosts') }} as hosts
        on verifications.host_id = hosts.host_id
    group by all

)

select
    *,

    -- Flags the rows that cannot carry signal by construction, so nobody reads
    -- an average off a method every host holds and calls it a correlation.
    host_share = 1 as is_universal_method
from adoption
order by hosts desc, verification_method asc
