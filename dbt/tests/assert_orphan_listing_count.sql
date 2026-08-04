-- Pins the number of orphan listings in int_listings at exactly one.
--
-- An orphan is a listing the calendar references that has no stg_listings
-- row, so every descriptive column is NULL for it. The count is load-bearing
-- across the project — models/README.md, the semantic view COMMENTs, and the
-- revenue reconciliation that explains how the orphan gap could result in the
-- host view being short.
--
-- Pinned at one rather than asserted as "at least one" because both
-- directions are worth knowing about:
--
--   MORE than one — another listing has gone missing from the raw listings
--     table. A real source signal, and every figure derived from the orphan
--     gap is now wrong by an amount nobody has measured.
--   ZERO — the source has been fixed upstream, or the grain has silently
--     changed to stg_listings' 49. The second is the regression this guards:
--     if the driving table in int_listings were ever repointed at
--     stg_listings, the model would still build, still pass its unique and
--     not_null tests, and quietly lose a listing.
--
-- WARN, not error. A change in the source's completeness is not a defect in
-- this model, and blocking the build would be the wrong response to it — the
-- right one is to look at the source and then at every figure quoting the
-- gap. Same reasoning as the two known-values tripwires on the bridges.
{{ config(severity='warn') }}

select
    count_if(is_orphan_listing) as orphan_listings,
    count(*) as listings
from {{ ref('int_listings') }}
having count_if(is_orphan_listing) != 1
