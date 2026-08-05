{{ config(
    pre_hook="set calendar_as_of_date = (select max(calendar_date)
              from {{ ref('int_listing_daily') }})"
) }}

with hosts as (

    select * from {{ ref('int_hosts') }}

)

select
    hosts.host_id,
    hosts.host_name_masked,
    hosts.host_since,
    $calendar_as_of_date as as_of_date,
    datediff(year, hosts.host_since, $calendar_as_of_date)
        as host_tenure_years,
    hosts.host_location,
    hosts.verification_count,
    hosts.verification_list,
    hosts.is_verified_email,
    hosts.is_verified_phone,
    hosts.is_verified_reviews,
    hosts.is_verified_kba,
    hosts.is_verified_government_id,
    hosts.is_verified_offline_government_id,
    hosts.is_verified_jumio,
    hosts.is_verified_facebook,
    hosts.is_verified_selfie,
    hosts.is_verified_identity_manual,
    hosts.is_verified_work_email,
    hosts.listing_count,
    hosts.listing_count > 1 as is_multi_listing_host,
    hosts.calendar_days,
    hosts.booked_nights,
    hosts.total_revenue,
    hosts.reservations,
    hosts.occupancy_rate,
    hosts.avg_nights_per_stay,
    hosts.avg_list_price,
    div0(hosts.total_revenue, hosts.listing_count)
        as revenue_per_listing,
    hosts.total_reviews,
    hosts.avg_review_score

from hosts
