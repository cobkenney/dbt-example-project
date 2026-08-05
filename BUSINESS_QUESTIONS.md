# Business questions

What you can ask of this data, and how: questions the marts answer as they
stand, questions needing a new model or a non-obvious query, and questions the
source data cannot answer at any amount of modeling effort. A last section
lists the properties of this data that make a reasonable-looking query wrong.

Nothing here is a finding. Figures appear only where they identify the rows a
question would return. Each question's verified result is pinned by its macro in
[dbt/macros/verified_queries/](dbt/macros/verified_queries/), whose header records
why the query is shaped the way it is.

Column names are checked against the marts as built.

Most of these are also answerable through the semantic views in
[dbt/models/marts/core_context_layer/](dbt/models/marts/core_context_layer/),
which name the metrics and carry these caveats where a natural-language client
will read them. The "How to answer" column below stays written against the marts,
since that is the lower-level and still-correct route.

---

## Answerable today

One query against the marts, no new modeling.

| # | Question | Why it matters | How to answer |
|---|---|---|---|
| 1 | Share of monthly revenue from listings without AC | Amenity gaps that cost money | `fct_listing_daily` — `revenue` by `month_start_date`, split on `has_air_conditioning` |
| 2 | Neighborhood average price increase | Where rates are moving | `fct_listing_daily` — `price` by `neighborhood` over `calendar_date` |
| 3 | Longest possible stay for a lockbox + first-aid-kit renter | Long-stay inventory for a picky renter | `fct_listing_daily` + `dim_listings`. Group on `availability_window_seq`, filtering `is_available` first — see `macros/verified_queries/verified_queries_q03.sql`, and read its header before adapting it |
| 4 | Occupancy rate by neighborhood and room type | Where demand concentrates vs where supply sits | `dim_listings` — `occupancy_rate` by `neighborhood`, `room_type` |
| 5 | Which listings earned zero revenue all year | 3 listings were available 365 days and never booked — price, photos, or location? | `dim_listings` — `total_revenue = 0` |
| 6 | Revenue seasonality across the portfolio | Staffing, cleaning contracts, pricing floors | `fct_listing_daily` — `revenue` by `month_start_date` |
| 7 | Revenue concentration — share from the top 5 listings | Portfolio risk: if Pareto-shaped, losing one host hurts | `dim_listings` — rank on `total_revenue` |
| 8 | Advertised rate vs achieved nightly rate | The gap is discounting discipline; a listing far under its ask is mispriced | `dim_listings` — `list_price` vs `avg_nightly_price` |
| 9 | Is there a price/occupancy sweet spot | The highest-priced listing is rarely the highest-earning | `dim_listings` — `list_price`, `occupancy_rate`, `total_revenue` |
| 10 | Day-of-week occupancy and pricing patterns | Weekend premium sizing; midweek gap-filling | `fct_listing_daily` — `dayofweek(calendar_date)`, `is_available`, `price` |
| 11 | Do review scores predict occupancy or a price premium | Whether review investment pays, and how much | `dim_listings` — `review_scores_rating`, `number_of_reviews`, `occupancy_rate` |
| 12 | Revenue per guest of capacity | Normalizes a studio against a 6-sleeper | `dim_listings` — `total_revenue / accommodates` |
| 13 | Shared-bathroom penalty on price and occupancy | 9 shared vs 39 private; quantifies a renovation case | `dim_listings` — `is_shared_bathroom` |
| 14 | Which amenities go with higher achieved rates | Capex prioritization: which amenity first | `dim_listings` — amenity flags vs `avg_nightly_price`. Cross-sectional only, see Amenity change impact below |
| 15 | How often a listing changes its nightly price | Dynamic-pricing hosts vs set-and-forget | `fct_listing_daily` — distinct `price` per `listing_id` over `calendar_date` |
| 16 | Do high `minimum_nights` listings have worse occupancy | Is the policy costing more than it saves in turnover | `fct_listing_daily` — `minimum_nights` vs `is_available` |
| 17 | Bookings, average length of stay, rate per booking | The reservation-level view of demand | `fct_reservations` — `nights`, `reservation_revenue`. Exclude `is_censored` from stay-length averages |
| 18 | Host portfolio performance | Which hosts to invest in | `dim_hosts` — `listing_count`, `revenue_per_listing`, `occupancy_rate` |
| 19 | Multi-listing operators vs casual hosts | Two different business relationships | `dim_hosts` — group on `is_multi_listing_host` |
| 20 | Does host tenure predict performance | Whether experience shows up in results | `dim_hosts` — `host_tenure_years`. Little variance to work with: `host_since` clusters in 2008–2009 |
| 21 | Price per bedroom and per bed | Compares a 4-bed against a studio fairly | `fct_listing_daily` — `price / bedrooms`, `price / nullif(beds, 0)`. `bedrooms` is NULL on 8 listings, `beds` is 0 on 4 |
| 22 | Which reservations span a month boundary | Whether monthly revenue splits need proration | `fct_reservations` — compare `check_in_month` against `last_night_date` |
| 23 | Length-of-stay distribution by neighborhood or room type | Which inventory attracts long stays | `fct_reservations` — `nights` by `neighborhood`, `room_type` |

## Need a new model or a non-obvious query

| # | Question | What it takes |
|---|---|---|
| 24 | Which listings have gone stale — no recent reviews | `last_review_date` is on `dim_listings` but unused. Needs a recency measure against a fixed reference date, not `current_date` — the snapshot ends 2022-07-11, so `current_date` drifts on every run |
| 25 | Revenue lost to unbookable availability windows | A contiguous run shorter than the listing's `minimum_nights` is real vacancy that cannot be sold. Needs the same gap-and-island as question 3, then compare run length to `minimum_nights` — reproducible from `fct_listing_daily`, no new model required |
| 26 | Neighborhood supply density vs achieved rate | ~~Needs a neighborhood-grain aggregate, which doesn't exist.~~ Answerable today: `sem_listing_performance` exposes `listings` (a distinct listing count) and the achieved-rate metrics, so grouping on `neighborhood` **is** the aggregate. No new model was needed |

## Cannot answer — the source data doesn't support it

Stated explicitly so nobody spends a day discovering them.

- **Booking lead time and booking pace.** There is no booking-created timestamp,
  only the nights a reservation occupies. "How far ahead do people book" needs
  new source data, not a new model.
- **Host-blocked vs booked.** `is_available = false` covers both "booked" and
  "host blocked the date." `reservation_id` separates them only insofar as the
  loader populated it for every real booking. Occupancy currently treats every
  unavailable night as booked — defensible given the
  `is_available = true ⟺ reservation_id is null` invariant holds, but it means
  host-blocked dates are indistinguishable by construction.
- **Amenity change impact over time.** 42 listings gained AC between their two
  changelog events, but every event predates the calendar window (latest
  2021-07-06; the window opens 2021-07-12). There is no before/after period
  inside the fact window, so the revenue impact of adding an amenity can only be
  estimated cross-sectionally, as in question 14.
- **Cancellations, guest identity, review text.** Not in the source at all.
- **Cost and margin.** Revenue only — no cleaning fees, platform commission, or
  operating costs, so profitability questions are out of scope.
- **Anything about a host's real name.** `host_name` is PII and is masked at the
  staging boundary; only `host_name_masked` exists downstream. Two of the 36
  hosts share a name and therefore share a hash, so it is not a host identifier
  either — join on `host_id`. See [dbt/macros/infrastructure/mask_pii.sql](dbt/macros/infrastructure/mask_pii.sql)
  and step 11 of the [README](README.md).

## Known caveats that change answers

Four properties of this data that will make a reasonable-looking query wrong.

- **The snapshot has hard edges.** The calendar is a fixed year ending
  2022-07-11. 70 reservations are truncated by those edges (`is_censored` on
  `fct_reservations`), so their `nights` is a floor rather than the real stay
  length. Average length of stay is 6.49 nights excluding them and 6.43
  including — exclude them for stay-length questions, keep them for counts,
  since those bookings really happened.
- **`reservation_id` is not unique on its own.** Id 836 covers two separate
  one-night stays on listings 753446 and 801680. The grain is
  `(listing_id, reservation_id)`, and `reservation_key` is the surrogate key.
  Grouping on `reservation_id` alone merges them into one impossible two-night
  reservation across two properties.
- **Listing 276450 has no `listings` row** but appears in 367 calendar and
  changelog rows. It carries `is_deleted = true` through every model, and
  its descriptive columns are NULL. Filter it out of anything comparing
  attributes; leave it in when totalling revenue.
- **`bedrooms` and `beds` fail in opposite ways.** `bedrooms` is NULL on 8 of 49
  listings; `beds` is 0 on 4. Both gaps fall entirely on entire homes, and one
  listing records 1 bedroom with 0 beds — so neither column is a clean fallback
  for the other. Guard both, and treat entire-home per-unit figures as the
  noisier pair.
