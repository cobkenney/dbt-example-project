# Marts layer

Three models analysts query directly. All materialized as tables (`marts:
+materialized: table` in `dbt_project.yml`) — marts are read many times and the
underlying data is a fixed one-year snapshot, so paying the build cost once is
the right trade.

No cleaning or casting happens here. Everything is typed and deduplicated by
the time it reaches this layer — see [staging](../staging/README.md) for the
cleaning log and [intermediate](../intermediate/README.md) for the join and
materialization rationale.

| Model | Grain | Rows | Serves |
|---|---|---|---|
| `dim_listings` | one row per listing | 50 | listing attributes, amenity flags, lifetime rollups |
| `fct_listing_daily` | one row per listing × date | 18,250 | business problems #1 and #2 |
| `fct_listing_availability_windows` | one row per contiguous availability window | 204 | business problem #3 |

## dim_listings

Built from `int_amenities_current`, not `stg_listings`. That choice sets the
grain to all 50 listings the calendar actually references, including orphan
276450 which never appears in `listings`. Its descriptive columns land NULL and
`is_orphan_listing` flags it, rather than the listing vanishing.

`total_revenue` uses `coalesce(sum(revenue), 0)`. Three listings (1454258,
1510876, 743759) are available all 365 days and never booked, so `sum()` over
all-NULL revenue returns NULL. A `not_null` test caught this; zero is the
honest measure for a listing that earned nothing, so the model was fixed rather
than the test relaxed.

`occupancy_rate` uses `div0` so a listing with no calendar rows returns 0
instead of erroring.

## fct_listing_daily

The atomic fact. Deliberately left at daily grain rather than pre-aggregated by
month, so it can serve both revenue-by-month and point-in-time price questions
from one table.

`month_start_date` is precomputed. Every revenue-by-month query needs it, and
`date_trunc` inside a `group by` is easy to get subtly wrong.

Carries denormalized listing attributes and the three amenity flags the
business questions filter on. This is intentional star-schema redundancy —
analysts answering #1 or #2 never need to join to `dim_listings`.

## fct_listing_availability_windows

`longest_possible_stay_nights` is clamped upstream in
`int_listing_availability_windows` to
`least(window_length_nights, maximum_nights)`. Both constraints bind in real
data, so neither column alone answers "how long could someone actually stay":

- listing 1303261 — 159-night window under a 180-night cap → the window binds
- listing 743211 — 206-night window capped to 90 nights → the owner's cap binds

The cap binds in 8 of the 204 windows.

`window_length_nights` counts available dates, not
`datediff(window_start_date, window_end_date)` — which would be one lower. Every
available calendar date is treated as a bookable night.

`is_bookable_window` marks windows shorter than the owner's `minimum_nights`.
59 of the 204 windows fail this check — they exist in the calendar but cannot
actually be booked, so they should be excluded from availability analysis rather
than silently counted.

## Orphan listing handling

Listing 276450 has 365 calendar rows and 2 amenity-changelog rows but no row in
`listings`. Joins throughout the intermediate and marts layers are **left**
joins so it survives, and `is_orphan_listing` carries the flag forward.

This is load-bearing for business problem #1. Listing 276450 contributes $2,200
of booked July 2022 revenue and does have air conditioning, so inner joining it
away strips revenue from the AC segment and pushes the no-AC share from the
correct 21.2% up to 22.1%. Queries that need complete revenue should not filter
on `is_orphan_listing`; queries about neighborhoods or property types should,
since those attributes are NULL for it.

## Sample queries

`../../analyses/` holds one query per business problem. They compile with
`dbt compile` but are not built as models — they demonstrate how an analyst
uses these marts.

| Analysis | Mart used | Verified result |
|---|---|---|
| `01_amenity_revenue.sql` | `fct_listing_daily` | July 2022 → 21.2% of revenue from listings without AC |
| `02_neighborhood_pricing.sql` | `fct_listing_daily` | Back Bay → 1 listing, $44.00 average increase ($106 → $150) |
| `03_long_stay_picky_renter.sql` | `fct_listing_availability_windows` | listing 1303261 → 159 nights |

## Tests

Each model has a paired `.yml` in its subfolder. Model-level tests use the
default `error` severity — unlike the source tests, which `warn` because the
raw data's known quality issues are documented rather than blocking.

- `unique` and `not_null` on every primary key
- `relationships` from both facts back to `dim_listings`
- `dbt_utils.equal_rowcount` from each fact to its intermediate parent, so a
  mart cannot silently drop rows
- `dbt_utils.unique_combination_of_columns` on
  `fct_listing_daily (listing_id, calendar_date)` — the declared grain, tested
  independently of the surrogate key
- `dbt_utils.accepted_range` on `occupancy_rate` (0–1 inclusive)
- `dbt_utils.expression_is_true` asserting
  `booked_nights + available_nights = calendar_days` on `dim_listings`, and
  `longest_possible_stay_nights <= window_length_nights` on the stay-windows fact
