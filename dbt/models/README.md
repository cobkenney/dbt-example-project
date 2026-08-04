# Models

Every transformation between `RENTALS.RAW_DATA` and the marts analysts query,
and the reason each one exists. Keep this current when you change a model.

Raw tables are landed from CSV as-is. All cleaning happens in staging, so that
section is the single place to look when a downstream number disagrees with the
source.

> **Figures in this document are a snapshot, not a live claim.** Every row count,
> revenue total, date range and listing id below was recorded on **2026-08-04**
> against the `RENTALS` raw load current at that date, and is not re-derived on
> build. They are a **regression baseline**: their value is that a rebuild
> disagreeing with them is a signal worth chasing. Do not quote them as the
> current state of the data — query the models for that. Comments inside the
> models, and the `COMMENT` text on the semantic views, are deliberately
> figure-free for the same reason: they describe what a column means, which is
> durable, rather than what it currently holds, which is not.

## Layer map

| Layer | Folder | Responsibility | Materialization |
|---|---|---|---|
| Staging | `staging/` | Cast, dedupe, rename. One model per source table. | view |
| Intermediate | `intermediate/` | Reshape: flatten JSON, join the daily grain, collapse dates into windows. No cleaning. | table |
| Marts | `marts/core_mart/` | What analysts query. No cleaning or casting. | table |

Column descriptions shared across models live once in [docs.md](docs.md) and
are referenced with `{{ doc('...') }}`. Columns that only look shared are
deliberately absent from it — `price` most notably, since the calendar's nightly
rate and the host's advertised rate are different measures with the same name.

Four topics span all three layers and are documented once, at the bottom:
[PII handling](#pii-handling), [orphan listing
276450](#orphan-listing-276450), [test severity](#test-severity), and the
[business questions](#business-questions).

---

# Staging — cleaning log

## Row counts

| Model | Raw rows | Staged rows | Difference |
|---|---|---|---|
| `stg_listings` | 51 | 49 | −2 NULL-id rows dropped |
| `stg_calendar` | 18,252 | 18,250 | −2 duplicate rows collapsed |
| `stg_amenities_changelog` | 100 | 100 | none |

## stg_listings

Grain: one row per listing.

### Rows dropped

**2 rows with a NULL `id`.** The natural key is missing, so these rows cannot be
joined to `calendar` or `amenities_changelog` and cannot be tested for
uniqueness meaningfully. Filtered with `where id is not null`.

One consequence worth knowing: one of the dropped rows held the highest raw
price (`$999.99`) and the `60 baths` outlier. Staged `price` therefore maxes at
`$571.00`, and `bathrooms` runs 1.0–2.5. If a raw-vs-staged price comparison
looks off, this is why.

### Casts and derivations

| Column | From | To | Note |
|---|---|---|---|
| `price` | `TEXT` `"$125.00"` | `NUMBER(10,2)` | Strips `$` and `,` before casting. All 51 raw values are `$`-prefixed — unlike `calendar.price`. |
| `first_review_date` | `TEXT` `"2015-10-30"` | `DATE` | Landed as text; every value is valid ISO, 0 uncastable. |
| `last_review_date` | `TEXT` | `DATE` | Same. |
| `bathrooms` | `bathrooms_text` | `NUMBER(4,1)` | Leading number pulled out of free text (`"2.5 baths"` → `2.5`). |
| `is_shared_bathroom` | `bathrooms_text` | `BOOLEAN` | True when the text contains "shared". 9 shared, 39 private, 1 NULL. |

`bathrooms_text` is kept alongside the parsed columns — the raw label carries
detail the number loses (`"1 private bath"` vs `"1 shared bath"`).

`bathrooms` and `is_shared_bathroom` are NULL for the 1 row where
`bathrooms_text` is NULL. `try_cast` is used rather than `cast` so a future
unparseable value yields NULL instead of failing the build.

### Renames

`id` → `listing_id` (so joins read consistently downstream), `name` →
`listing_name` (avoids the `NAME` keyword and is more specific).

## stg_calendar

Grain: one row per listing per date.

### Deduplication

**1 row triplicated:** listing `1303261` on `2022-07-07` appeared 3 times, fully
identical across every column. This broke the stated grain and would have
inflated any aggregate over that listing.

Handled with `dbt_utils.deduplicate` partitioned by `(listing_id, date)`. On
Snowflake this compiles to `qualify row_number() over (...) = 1` — one table
scan, no self-join. Because the duplicates are byte-identical, `order_by` is
arbitrary; any of the three survives with the same values.

### Casts and derivations

| Column | From | To | Note |
|---|---|---|---|
| `price` | `TEXT` `"125"` | `NUMBER(10,2)` | **No `$` prefix here**, unlike `listings.price`. All 18,252 raw values are plain numerics, so no stripping needed. |
| `reservation_id` | `TEXT` `'NULL'` | `TEXT` / true NULL | The loader wrote the literal 4-character string `'NULL'` for unbooked dates — 8,193 raw rows, converted via `nullif`. 8,191 remain after dedupe, since the triplicated row was an available date. |
| `calendar_id` | `(listing_id, date)` | `TEXT` | Surrogate key from `dbt_utils.generate_surrogate_key`, giving a single-column PK for the compound grain. |

The `reservation_id` fix matters: before it, `reservation_id is not null` was
true for every row, so any "is this date booked?" filter would silently return
the whole table.

### Known-good invariant

`available = true` ⟺ `reservation_id is null` holds for all 18,250 rows (8,191
available / 10,059 booked). Asserted with `dbt_utils.expression_is_true` so a
future load that breaks it fails loudly.

## stg_amenities_changelog

Grain: one row per listing per change timestamp.

No rows dropped, no casts needed — the raw types are already correct.

| Change | Detail |
|---|---|
| `amenities_change_id` | Surrogate key over `(listing_id, changed_at)`. |
| `change_at` → `changed_at` | Consistent past-tense naming for event timestamps. |

---

# Intermediate — reshaping

| Model | Grain | Materialization | Rows |
|---|---|---|---|
| `int_amenities_current` | listing | table | 50 |
| `int_listings` | listing | table | 50 |
| `int_listing_daily` | listing × date | table | 18,250 |
| `int_reservations` | listing × reservation | table | 1,565 |
| `int_host_verifications` | host × verification method | table | 183 |
| `int_hosts` | host | table | 36 |

All tables, with no per-model exceptions — one rule for the layer.

This departs from dbt's recommended `ephemeral` for intermediate models.
Ephemeral inlines each model as a CTE in every consumer — nothing lands in the
warehouse, but the logic re-runs per consumer. `int_amenities_current`,
`int_listing_daily` and `int_listings` all have multiple consumers, so tables
build that work once instead.
The cost of that choice is these models are queryable, which is why analysts are
pointed at the marts layer rather than this one.

At this data size nothing warrants `incremental` — it would add reload
complexity for no measurable gain.

## int_amenities_current

`amenities` arrives as a **JSON array string**, not free text:

```
'[\n  "Oven",\n  "Washer",\n  "Air conditioning",\n ... ]'
```

`try_parse_json` succeeds on all 100 changelog rows, and flattening yields
2,285 listing-amenity pairs across 81 distinct amenity names. Those are pivoted
into boolean flags (`has_air_conditioning`, `has_lockbox`, `has_first_aid_kit`,
and a few common others).

### Why "current" and not a full history

The name is deliberate: this model keeps **one row per listing**, built from the
changelog's latest event. That is a grain reduction, and the changelog really
does hold history worth reducing:

| Fact | Value |
|---|---|
| Changelog rows / listings | 100 / 50 — exactly 2 events each |
| Listings whose amenity set differs between events | 48 of 50 |
| Listings that gained AC between events | 42 |
| Amenities that ever disappeared | 0 — growth is purely additive |
| Event 1 dates | 2008–2009; matches `host_since` for 49 of 50 listings |
| Event 2 dates | 2020-07-17 → 2021-07-06 |

So why collapse it? **Every changelog event predates the fact window.** The
calendar runs 2021-07-12 → 2022-07-11; the newest amenity event is 2021-07-06,
six days earlier. Zero events fall inside the window.

That was verified rather than assumed. A full SCD2 version was built
(`valid_from` / `valid_to` per snapshot via `lead()`, joined to the calendar with
`between`) and compared against this model:

- calendar rows resolving to a **superseded** amenity version: **0 of 18,250**
- rows where the point-in-time AC flag disagrees with this model: **0 of 18,250**
- July 2022 no-AC revenue share under SCD2: **21.2%** — identical

A point-in-time join is a provable no-op on this data, so it would add a range
predicate to every downstream mart for zero change in output.

The assumption is enforced, not just documented:
[../tests/assert_amenities_predate_calendar.sql](../tests/assert_amenities_predate_calendar.sql)
fails if any changelog event ever lands on or after the calendar window opens —
which is exactly when "latest wins" would start misattributing revenue to
amenities a listing did not yet have.

Migrating is cheap if that day comes: each changelog row carries the **entire**
amenity array, not a delta. It is a snapshot log, so SCD2 is the `lead()` CTE
above with no event-replay logic.

### Why exact matches, not substring search

The obvious approach is `contains(lower(amenities), 'air conditioning')`. It
happens to work for that string, but the pattern is unsafe — `'%air%'` also
matches **"Hair dryer"**. Flattening first and comparing
`amenity_name = 'Air conditioning'` removes the class of bug rather than
dodging one instance of it.

### Why the changelog, not stg_listings

`stg_listings` is missing listing 276450 entirely. The changelog covers all 50
listings the calendar references, so sourcing amenities from it means the orphan
still gets flags instead of NULLs.

The latest of the 2 events per listing is taken via
`qualify row_number() = 1`. This is a point-in-time-safe shape, but note the
data doesn't currently require it: amenities are static across the whole period,
and the latest state agrees with `stg_listings.amenities` for all 49 listings
present in both.

## int_listings

One row per listing the project recognises — **50**, against the 49 in
`stg_listings`. Descriptive attributes only: no measures, no raw JSON.

### What it centralizes

Four models read `stg_listings` directly before this existed, each taking its own
column subset. That was defensible while nothing was shared. Two things were:

**The grain.** `stg_listings` has 49 rows and the calendar references 50, so
every consumer needing all of them rebuilt the universe itself — `dim_listings`
drove off `select distinct listing_id` from the amenities bridge for exactly that
reason. This model drives off the bridge once, here.

**`is_orphan_listing`.** It was computed independently in `int_listing_daily` and
again in `dim_listings`, both as `listings.listing_id is null` off their own left
join. Two copies of the rule deciding which listings lack attributes, in two
layers, with nothing tying them together. It is computed here and read
downstream.

### What it deliberately does not carry

**The raw JSON columns.** `host_verifications` and `amenities` stay on
`stg_listings`. Each has a dedicated flattening path, and carrying them here
would offer a second route to the same array and invite the wrong one.
`int_host_verifications` still refs `stg_listings`, correctly, because it needs
the raw column.

**Measures.** Revenue, occupancy and nightly rates are calendar-derived and live
in `int_listing_daily`. Two homes for a listing-grain measure means no rule for
choosing between them.

`price` is renamed to `list_price`, the name the marts already used — the staging
name is ambiguous next to the calendar's nightly `price`, which is a different
measure.

### The orphan row is the interesting one

It has a `listing_id` and NULL for every descriptive column, including `host_id`.
That is not a defect to filter out, it is the honest shape of the data, and
`is_orphan_listing` is what lets each consumer decide. `int_hosts` filters it out
with `where not is_orphan_listing` — with no `host_id` it cannot belong to a
host, and grouping on NULL would invent a 37th. `fct_reservations` keeps it,
because it carries real booked revenue.

`tests/assert_orphan_listing_count.sql` pins the count at exactly one, at
severity warn. Both directions matter: more than one means another listing has
gone missing from the source, and **zero** means the grain has silently collapsed
back to `stg_listings`' 49 — a regression that would otherwise build green and
pass every other test on the model.

## int_listing_daily

The daily grain the marts aggregate from: `stg_calendar` joined to listing
attributes from `int_listings` and amenity flags, one row per listing per date.

### Left joins are load-bearing

Listing 276450 appears in the calendar but not in the raw `listings` table. An
inner join against `stg_listings` drops its 365 rows and **$2,200** of booked
July-2022 revenue — enough to shift the no-AC revenue share from the correct
**21.2%** to **22.1%**.

`int_listings` covers all 50 listings the calendar references, so the join finds
a row for every calendar row and left versus inner no longer changes the result
today. It stays a left join anyway: an inner join would answer the listing
universe narrowing again by silently dropping calendar rows, where the left join
leaves `is_orphan_listing` NULL and its `not_null` test says so.

That test is meaningful only since the repoint. The column used to be computed in
place as `listings.listing_id is null`, which returns true or false and never
NULL, so a `not_null` test on it could not fail. Read across a join, it can.

The flag itself makes the include-or-exclude choice explicit downstream: marts
decide deliberately rather than inheriting a silent join-side effect. Row count is
also asserted equal to `stg_calendar` via `dbt_utils.equal_rowcount`.

### revenue

```sql
case when not is_available then price end as revenue
```

NULL on available nights, so `sum(revenue)` is total booked revenue with no
filtering. A test asserts revenue is non-null exactly when a night is booked.

`neighborhood`, `property_type`, and other listing attributes are NULL on the
365 orphan rows — expected, and the reason neighborhood aggregations naturally
exclude them.

## int_reservations

One row per reservation, grouping the calendar's booked nights on
`reservation_id`. 10,059 booked nights collapse to **1,565 reservations**.

### It is derived, not sourced

This should most likely come from a source, but in the absence of one it is
derived from `listings`/the calendar. That most likely means we are missing
unconfirmed reservations, whereas the reservations on listings are confirmed. So:

- **Cancellations and unconfirmed requests are invisible.** A reservation exists
  here only because a night is occupied. Booking conversion and cancellation
  rate are not answerable from this table.
- **Booking lead time is unanswerable.** No booking-created timestamp exists
  anywhere in the raw data — only the nights a reservation occupies.
- **Host-blocked dates** are indistinguishable from booked nights except by
  `reservation_id` being populated.

### reservation_id is not unique

The `unique` test caught this on the first build: **id 836 appears on two
listings** — 753446 and 801680, both single nights on 2021-07-12. Two unrelated
stays sharing an id.

Grouping on `reservation_id` alone would have merged them into one impossible
2-night reservation spanning two properties. The grain is therefore
`(listing_id, reservation_id)`, with `reservation_key` as the surrogate key —
the same pattern as `calendar_id`. Consumers should join and count on
`reservation_key`.

### Censoring at the snapshot edges

The calendar is a fixed year, so a reservation touching either edge has nights
outside the loaded window and `nights` is a floor rather than a fact. 70 of
1,565 reservations are censored. `is_left_censored` / `is_right_censored` flag
them, and `fct_reservations` adds `is_censored` as the single filter to use.

It matters modestly but in the direction you'd expect — long stays are the most
likely to cross an edge:

| Measure | All reservations | Uncensored only |
|---|---|---|
| Average length of stay | 6.43 nights | **6.49 nights** |

Counts and revenue should **not** filter on it: those reservations happened and
their revenue is real. Only their length is unknown.

### Contiguity is asserted, not assumed

`min`/`max` collapse a reservation to one span, which is only honest if its
nights are consecutive. `is_contiguous` makes that checkable and the `.yml`
asserts it — currently true for all 1,565. A gap would mean one id covers two
separate stays and `check_out_date` overstates the first.

[../tests/assert_reservation_nights_reconcile.sql](../tests/assert_reservation_nights_reconcile.sql)
asserts total nights and revenue match the daily grain, so the reduction cannot
silently drop or double-count a night.

Observed range: 1 to 14 nights, average booking value $1,076.59, $1,684,864
total — which reconciles to the daily grain's booked revenue by construction.

## int_host_verifications

One row per host per verification method — 183 rows for 36 hosts. `stg_listings.
host_verifications` arrives as a JSON array string, exactly like `amenities`:

```
'["email", "phone", "reviews", "kba"]'
```

11 distinct methods, by host count: email 36, phone 36, reviews 34, kba 18,
government_id 16, jumio 10, facebook 10, offline_government_id 10, selfie 5,
identity_manual 4, work_email 4.

### Grouped to the host grain BEFORE flattening

Verifications are a *host* attribute denormalized onto every *listing* row.
Flattening `stg_listings` directly would emit a row per listing per method and
overcount the 7 multi-listing hosts — the 5-listing host would contribute each of
their methods five times. So this groups to `host_id` first (`min()`, same
premise and same test as `int_hosts`), then flattens.

### Both the bridge and the flags exist

The generated `is_verified_*` flags on `int_hosts` answer "which hosts have X"
inside a filter. This bridge answers "how many hosts hold each method" without
naming 11 columns, and its shape survives the source adding a method. Neither
subsumes the other, which is why both are kept — the same reasoning as
`amenity_list` alongside the `has_*` flags.

### Why not just string-match the raw column

`contains(host_verifications, 'government_id')` cannot distinguish
`offline_government_id`, and `'email'` cannot distinguish `'work_email'`.

On this snapshot both shortcuts return the **correct** answer, because the
narrower method is a strict subset of the broader one in both cases — all 10
offline_government_id hosts also hold government_id, and all 4 work_email hosts
also hold email. Nothing enforces that. A latent bug that passes review is worse
than one that fails, so the raw string stops at staging and nothing downstream
carries it.

## int_hosts

One row per host. Hosts arrive denormalized onto the listings table rather than
as their own source, so this reconstructs the grain by grouping on `host_id`:
**36 hosts across 49 listings** — 29 with one listing, 7 with several, up to 5.

Sourced from `int_listings` and `int_listing_daily` rather than `dim_listings`,
to keep the intermediate layer free of mart dependencies. Orphan listing 276450
is excluded with `where not is_orphan_listing`, which is correct — with no
listings row it has no `host_id` and cannot belong to any host.

That exclusion is a stated filter rather than a side effect. Reading
`stg_listings`, the orphan was absent because that model does not have it: the
right outcome for a reason unrelated to hosts, and invisible in this model.
`int_listings` carries all 50, so the filter has to be written down — and if it
were ever dropped, the `not_null` test on `host_id` fails rather than a 37th host
appearing.

### Host attributes are picked with min(), and that premise is tested

Because attributes repeat on every listing row, any aggregate returns the same
value; `min()` picks one deterministically rather than relying on `any_value`,
which Snowflake does not guarantee is stable.
[../tests/assert_host_attributes_consistent.sql](../tests/assert_host_attributes_consistent.sql)
fails if a host's listings ever disagree — the signal that hosts need their own
source or SCD treatment, instead of one value silently winning.

### Rates are portfolio-weighted, not averaged

`occupancy_rate` sums booked nights and calendar days across the host's listings
before dividing, and `avg_nights_per_stay` weights by reservation count.
Averaging per-listing rates would let a listing with 30 calendar days count as
much as one with 365.

Compare hosts on `revenue_per_listing`, not `total_revenue` — the latter scales
with portfolio size by construction.

### The verification flags are generated, and there is no coverage floor

`verification_count`, `verification_list`, and one `is_verified_<method>` boolean
per method, joined from `int_host_verifications` by the same Jinja codegen pattern
as the amenity flags. `dbt run-operation generate_verification_flag_yml` emits the
yml for any flag not yet declared and reports declared flags the data no longer
produces.

Unlike the amenities, **every** method gets a flag — including `email` and
`phone`, which all 36 hosts hold and which therefore carry zero predictive signal.
That is deliberate and was the explicit ask: a universally-true flag is the only
thing whose becoming false is visible. Drop it for carrying no signal and you also
drop the ability to notice the first host who arrives without a verified email.

The join is a **left** join, so a host whose array is empty or unparseable keeps
their row with NULL flags rather than vanishing from the host grain.
`verification_count`'s `not_null` test is the tripwire for that happening.

---

# Marts — `core_mart`

The general-purpose mart: four models analysts query directly. Built into the
`core_mart` schema — folder and schema share a name — and this is the only
schema analysts are granted on. See
[../macros/generate_schema_name.sql](../macros/generate_schema_name.sql).

`marts/` is a container rather than a layer. Each subfolder is one mart with its
own schema, so a future mart can be granted separately from this one.
Materialization and `+transient` are set once on `marts:` in `dbt_project.yml`
and inherited; each mart declares only its own `+schema:`.

All materialized as tables (`table_insert_overwrite`) — marts are read many
times and the underlying data is a fixed one-year snapshot, so paying the build
cost once is the right trade.

| Model | Grain | Rows | Serves |
|---|---|---|---|
| `dim_listings` | one row per listing | 50 | listing attributes, amenity flags, lifetime rollups |
| `fct_listing_daily` | one row per listing × date | 18,250 | business problems #1 and #2 |
| `fct_reservations` | one row per reservation | 1,565 | reservation counts, length of stay, booking value |
| `dim_hosts` | one row per host | 36 | host portfolios, tenure, operator segmentation |

## dim_listings

Built from `int_listings`, not `stg_listings`. That is where the grain comes
from: all 50 listings the calendar actually references, including orphan 276450
which never appears in `listings`. Its descriptive columns land NULL and
`is_orphan_listing` flags it, rather than the listing vanishing.

This model used to establish that grain itself — `select distinct listing_id` off
the amenities bridge, left joined to `stg_listings` for the attributes, with
`is_orphan_listing` derived from whether that join found anything. `int_listings`
holds all three, so this model no longer decides which listings exist or which
ones lack attributes; it reads both and joins the daily rollup.

`total_revenue` uses `coalesce(sum(revenue), 0)`. Three listings (1454258,
1510876, 743759) are available all 365 days and never booked, so `sum()` over
all-NULL revenue returns NULL. A `not_null` test caught this; zero is the
honest measure for a listing that earned nothing, so the model was fixed rather
than the test relaxed.

`occupancy_rate` uses `div0` so a listing with no calendar rows returns 0
instead of erroring.

`as_of_date` carries the snapshot's last date (2022-07-11) so review recency can
be measured against a fixed anchor rather than `current_date`, which would drift
on every run. It is set by a pre-hook session variable — the mechanism is
described under [dim_hosts](#dim_hosts), which uses the same one. It lives on
this model rather than being reached through `dim_hosts` because the orphan
listing has no `host_id` to reach it by.

## fct_listing_daily

The atomic fact. Deliberately left at daily grain rather than pre-aggregated by
month, so it can serve both revenue-by-month and point-in-time price questions
from one table.

`month_start_date` is precomputed. Every revenue-by-month query needs it, and
`date_trunc` inside a `group by` is easy to get subtly wrong.

Carries denormalized listing attributes and the three amenity flags the
business questions filter on. This is intentional star-schema redundancy —
analysts answering #1 or #2 never need to join to `dim_listings`.

`bedrooms` and `beds` are carried here so price can be normalized against the
date's actual nightly price rather than the listing's advertised rate. Both need
guarding, in opposite ways — `bedrooms` is NULL on 8 of 49 listings, `beds` is 0
on 4 — and both gaps fall entirely on entire homes. See the doc blocks.

## dim_hosts

The second dimension the star schema wanted. Both facts carry `host_id`, so
revenue and reservations can be sliced by host segment without going through
`dim_listings`.

Adds three things `int_hosts` doesn't: `host_tenure_years`,
`is_multi_listing_host`, and `revenue_per_listing`.

`host_tenure_years` is measured against `as_of_date` — the last date in the
calendar snapshot (2022-07-11) — not `current_date`. The data is a fixed year, so
`current_date` would drift on every run and give a different answer each time.
`as_of_date` is carried as a column so a tenure figure stays reproducible.

That date arrives as a `$calendar_as_of_date` session variable set by the model's
pre-hook, not as a one-row CTE cross joined onto every host. A scalar in the
select list cannot change the row count, so the grain is preserved by
construction — which is why the `equal_rowcount` test against `int_hosts` is
gone. Two real costs: the compiled SQL no longer runs standalone (a worksheet
needs the `set` statement first), and the `int_listing_daily` dependency lives
only in the hook, so the DAG edge survives but is invisible when reading the
select. `dim_listings` sets the same variable from the same source, so the two
dimensions cannot disagree about where the snapshot ends.

### Multi-listing hosts earn less per property

`is_multi_listing_host` splits 7 multi-listing hosts from 29 single-listing ones.
The result runs opposite to the intuition that professional operators perform
better:

| Segment | Hosts | Listings | Revenue per listing | Occupancy | Avg stay |
|---|---|---|---|---|---|
| Multi-listing | 7 | 20 | $19,267 | 38.5% | 6.25 nights |
| Single-listing | 29 | 29 | **$39,749** | **60.0%** | 6.11 nights |

Roughly half the revenue per property at two-thirds the occupancy, with stay
length essentially unchanged — so it's an occupancy gap, not a stay-length one.
Worth investigating before treating multi-listing hosts as the more valuable
segment, though 7 hosts is a small base to conclude much from.

### Verification flags are named explicitly here

`int_hosts` passes its generated flags through with `select *`, since naming the 11
there would put a third copy of the seed's list in the project. This mart names all
11 by hand instead, matching how `dim_listings` handles the amenity flags: a mart's
column list should be stated where analysts read it. That means a new method needs
adding in two places, and `generate_verification_flag_yml`'s stale report is what
catches the mart drifting.

11 columns is tractable to name by hand in a way that 81 amenity flags is not.

This mart naming its flags is also why the seed matters more for verifications than
for amenities — see the next section. Under the old `select distinct` loop, a
method disappearing upstream removed the column here and broke this model at run
time.

### The seeds are the column list, not just a test fixture

A codegen loop over `select distinct` is blind in one direction and dangerous in
the other. It emits a column for whatever it finds, so a **removed** value left a
stale column that `generate_amenity_flag_yml` and `generate_verification_flag_yml`
reported on demand — while a **new** value just widened the model on the next run,
documented nowhere and carried by no mart, until somebody happened to run the
codegen. Neither direction went through review, because neither involved a commit.

So the lists moved into seeds, and the loops read the seeds:

| | Where the list lives | Read by |
|---|---|---|
| 81 amenities | `seeds/known_amenity_names.csv` | `get_amenity_names()` → `int_listing_daily` |
| 11 methods | `seeds/known_verification_methods.csv` | `get_verification_methods()` → `int_hosts` |

**The generated column list is now a committed file.** A value appearing or
disappearing in the source cannot add or drop a column — only a diff to the seed
can. That is the guarantee worth having: a schema change on a table five models
deep should be something someone approved, not something that happened overnight.

The direction this really protects is removal. `dim_hosts` names all 11
`is_verified_*` flags explicitly, so under the old scheme a method vanishing
upstream dropped a column from `int_hosts` and broke the mart at run time — no
test, no warning, just a red build one morning. Now the flag survives and goes
universally false, which is queryable. Verified by pulling a value from each seed:
`int_hosts` compiled to 10 flags instead of 11, `int_listing_daily` to 80 instead
of 81, and both warn tests fired.

Each bridge model `relationships`-tests its column against its seed at
`severity: warn`, which is what notices the source moving:

| | Removed value | New value |
|---|---|---|
| Codegen stale report | caught, on demand | invisible |
| The seed relationships test (warn) | harmless now — flag stays, goes false | **caught, every run** |

**`warn`, not `error`, is the whole point.** A new amenity upstream is a source
change, not a defect — erroring would block a build over data that is perfectly
valid, which is why these tests were argued against in the first place and why the
ymls used to say so explicitly. The warning is a **work order**, and its steps are
now ordered by the fact that the seed drives the schema:

1. regenerate the seed — this is the step that adds the column, and its diff is
   the reviewable decision
2. run the codegen macro, paste the flag into the intermediate yml
3. decide whether the mart carries it

All three in one commit. Step 1 alone silences the warning and leaves an
undocumented column behind, which is the same silent widening this design exists
to stop.

`relationships` rather than `accepted_values` for both, because `accepted_values`
takes a **literal list and cannot read a table**. Pointing a relationships test at
the seed is the same assertion — every value must appear in the seed — and it is
what lets one list serve both the test and the loop.

That single-list property is why the verification methods got a seed too, at only
11 values, having previously been argued to be better off inline. Inline was right
while the list only fed a test. Once it also had to feed a Jinja loop it stopped
being an option: **a loop cannot read an `accepted_values` list out of yml**, so
staying inline meant maintaining the same 11 values in two hand-edited files, and
the failure mode of the copies disagreeing is a flag column with no test behind it
or a tested value with no column.

The seeds are not free, and the cost lands on commands people actually run:

> **A seed is a build artifact.** `dbt test` on the bridge models and `dbt run` on
> `int_listing_daily` / `int_hosts` both now need `dbt seed` to have run — which is
> why those two models carry an explicit `-- depends_on:` for their seed, since a
> `ref()` inside a macro is invisible to dbt's parser. A fresh clone running
> `dbt run && dbt test` gets a missing-relation error. `dbt build` orders seeds
> first and is unaffected.

Both tests are named (`warn_new_amenity_name`, `warn_new_verification_method`)
because generic-test naming derives from the arguments, and 81 literal values
produced a 900-character identifier before the seed replaced them.

The seed generators are the one place that still reads the data —
`generate_known_amenity_names_seed` queries `int_listing_amenities` and
`generate_known_verification_methods_seed` flattens `stg_listings`. Neither calls
the `get_*` macros, which would emit each file back to itself and never discover
anything.

### Verification does not predict performance

This records the negative result rather than leaving the intuition standing. With
36 hosts and 11 methods there are more cells than hosts, and the spread is
non-monotonic: `facebook` — a social link, not an identity check — shows the
second-highest occupancy, while the stronger `selfie` check sits below average,
and `kba` has the highest review score alongside the lowest occupancy. `email` and
`phone` cover every host, so their rows are just the overall average by
construction.

Read that table as **adoption**. Do not attach an occupancy claim to a
verification badge on this data.

## fct_reservations

One row per reservation with listing attributes and amenity flags denormalized
on, so "average length of stay by neighborhood" needs no join. Primary key is
`reservation_key`, not `reservation_id` — see
[int_reservations](#int_reservations) for why, along with the censoring and
derived-source caveats that apply to anything reported off this table.

`check_in_month` is precomputed for the same reason `fct_listing_daily`
precomputes `month_start_date`. Keyed on check-in, so a stay crossing a month
boundary counts in the month it started.

---

# PII handling

`host_name` is a real person's name. **It does not exist in plaintext anywhere in
the dbt layers.**

`stg_listings` is the only model permitted to read the raw column, and it emits
`host_name_masked` instead — a salted SHA-256 truncated to 16 hex characters, via
[../macros/mask_pii.sql](../macros/mask_pii.sql). Masking at the staging boundary
rather than in the mart means no downstream model can expose the plaintext even
by accident; there is nothing to leak.

Nothing is lost analytically: `host_id` already identifies a host for every join
and grouping in the project, and the hash still works as a grouping key.

| Layer | State |
|---|---|
| `RENTALS.RAW_DATA.listings` | Plaintext. Flagged `contains_pii: true` in the source yml, with a note that no model may select it. |
| `stg_listings` | `host_name_masked` only. The plaintext is read here and never emitted. |
| `int_host_verifications`, `int_hosts`, `dim_hosts`, `dim_listings` | `host_name_masked` only. |

Three details that make the masking real rather than decorative:

- **The salt is what makes it irreversible.** Host names are first names from a
  space of maybe a few thousand candidates, so an unsalted `sha2('Maria')` is
  recovered instantly by hashing a name list and matching. Without a secret salt
  this would be theatre. It comes from `PII_HASH_SALT`; the committed default is
  deliberately not a secret and exists only so a fresh clone builds.
- **NULL in, NULL out** — not a hash of a coalesced empty string, which would
  make "no name recorded" indistinguishable from a real value and give every
  NULL row one shared hash resembling a single prolific host.
- **The hash is not a host identifier.** 36 hosts hold only 35 distinct names, so
  two hosts share a name and therefore share a hash. Join on `host_id`.

## What this does not cover

The plaintext still sits in `RAW_DATA`, which dbt cannot reach. Restricting it
needs a Snowflake masking policy or a change to what the loader lands. Rotating
`PII_HASH_SALT` also changes every hash, so anything joined on a masked column
breaks by design — that is the price of the salt being rotatable at all.

`host_location` is self-reported free text and is currently passed through
unmasked. It is coarse (city-level in this data) rather than an address, but it is
worth a deliberate decision rather than an assumption.

---

# Orphan listing 276450

Listing 276450 has 365 calendar rows and 2 amenity-changelog rows but no row in
`listings`. It is the single data defect that shapes decisions in every layer:

| Layer | Handling |
|---|---|
| Staging | Orphan rows **kept**, not filtered. `relationships` tests set to `severity: warn`. |
| Intermediate | `int_listings` sets the 50-listing grain and computes `is_orphan_listing` once; downstream models read it rather than each deriving it. Joins stay **left** joins. `int_amenities_current` is sourced from the changelog so the orphan still gets amenity flags. `int_hosts` excludes it explicitly — no `host_id`, so no host. |
| Marts | `dim_listings` and `fct_reservations` are built off `int_listings`, so the orphan is present in both. Descriptive columns land NULL; its revenue is real and is counted. |

Dropping a year of availability data silently is worse than surfacing it, which
is why nothing filters it out and consumers choose explicitly.

This is load-bearing for business problem #1. Listing 276450 contributes $2,200
of booked July 2022 revenue and does have air conditioning, so inner joining it
away strips revenue from the AC segment and pushes the no-AC share from the
correct 21.2% up to 22.1%. So: queries that need complete revenue should **not**
filter on `is_orphan_listing`; queries about neighborhoods or property types
should, since those attributes are NULL for it.

# Test severity

The pattern: **source tests warn, model tests error.** Source tests describe
what arrived; model tests guarantee what staging produced. A red build then
always means a bug in our code, never a known upstream defect — while the
upstream defects stay visible instead of being silently swallowed.

Six tests warn **and currently fire**. All six reflect real defects in the raw
data that staging does not fully repair:

| Test | Rows | Why warn |
|---|---|---|
| `not_null` on `listings.id` (source) | 2 | Documents the defect at the source; `stg_listings` filters it, where the same test errors. |
| `unique_combination_of_columns` on `calendar` (source) | 1 | Source-level duplicate; `stg_calendar` fixes it, where the same test errors. |
| `relationships` on `calendar.listing_id` | 365 | Orphans kept by design. |
| `relationships` on `amenities.listing_id` | 2 | Same. |
| `relationships` on `stg_calendar.listing_id` | 365 | Same defect re-checked post-staging. |
| `relationships` on `stg_amenities.listing_id` | 2 | Same. |

If listing 276450 is ever backfilled, all four relationships warnings clear on
their own and can be promoted to `error`.

Three more tests are set to warn but pass today. They are **tripwires**, not
defect records — each one describes a source change that is nobody's bug but that
somebody has to act on, which is why blocking the build would be the wrong
response:

| Test | On | Fires when |
|---|---|---|
| `warn_new_amenity_name` | `int_listing_amenities` | the source grows an amenity the seed does not list |
| `warn_new_verification_method` | `int_host_verifications` | the source grows a verification method the seed does not list |
| `assert_orphan_listing_count` | `int_listings` | the orphan count leaves exactly one — in **either** direction |

The third is also a regression guard, and that is the direction worth naming: at
zero it means the listing grain has collapsed back to `stg_listings`' 49, which
is our bug and not the source's.

Each model has a paired `.yml` in its own subfolder. Beyond the per-layer tests
described above, the marts assert:

- `unique` and `not_null` on every primary key
- `relationships` from both facts back to `dim_listings`
- `dbt_utils.equal_rowcount` from each fact to its intermediate parent, so a
  mart cannot silently drop rows
- `dbt_utils.unique_combination_of_columns` on
  `fct_listing_daily (listing_id, calendar_date)` — the declared grain, tested
  independently of the surrogate key
- `dbt_utils.accepted_range` on `occupancy_rate` (0–1 inclusive)
- `dbt_utils.expression_is_true` asserting
  `booked_nights + available_nights = calendar_days` on `dim_listings`

# Business questions

The questions live as verified queries on the semantic views, one macro per
question in
[../macros/verified_queries/](../macros/verified_queries/). Each macro's header
records why its query is shaped the way it is and what the plausible wrong answer
would be; the query itself is the executable form. See
[core_context_layer/README.md](marts/core_context_layer/README.md) for how they
are wired and which view carries which question.

Results below were verified against the intermediate models at the date in the
header above.

| Question | Mart used | Verified result |
|---|---|---|
| Amenity revenue by month | `fct_listing_daily` | July 2022 → 21.2% of revenue from listings without AC |
| Neighborhood price increase | `fct_listing_daily` | Back Bay → 1 listing, $44.00 average increase ($106 → $150) |
| Longest stay, lockbox + first aid kit | `fct_listing_daily` + `dim_listings` | listing 1303261 → 159 nights. Groups on `availability_window_seq` — see [Collapsed models](#collapsed-models) |
| Reservation volume and length of stay | `fct_reservations` | 1,565 reservations, 6.49-night average stay, $1,076.59 average booking value |
| Multi-listing vs single-listing hosts | `dim_hosts` | Multi-listing hosts earn $19,267 per listing vs $39,749 — see [dim_hosts](#dim_hosts) |
| Price per bedroom and per bed | `fct_listing_daily` | Entire homes $165.68/bedroom and $128.10/bed vs $85.74 and $84.15 for private rooms |
| Host verification adoption | `int_host_verifications`, `dim_hosts` | email/phone 36 of 36, reviews 34, kba 18, government_id 16 — and **no** relationship to occupancy or revenue, see [dim_hosts](#dim_hosts) |

2 listings carry both a lockbox and a first aid kit; 42 of 50 have air
conditioning.

# Collapsed models

`int_listing_availability_windows` and `fct_listing_availability_windows` were
removed. They held one row per contiguous run of available dates — 204 windows
across 50 listings — built by gap-and-island.

**Why they went.** 2 models, 258 lines, and 25 tests served exactly one
question (#3, the picky-renter query). Before deleting, both dependent questions
were re-derived from `fct_listing_daily` and matched the mart exactly:

| Question | Via the mart | Via `fct_listing_daily` |
|---|---|---|
| #3 longest stay, lockbox + first aid kit | 1303261 → 159 nights | 1303261 → 159 nights |
| #26 unbookable windows | 204 windows, 59 unbookable, 300 nights | 204 / 59 / 300 |

So the models were never load-bearing for correctness — nothing was answerable
only through them. The gap-and-island itself is 8 lines, and the reservations
work established that all 1,565 reservations are contiguous, so the pattern is
not reusable here the way a windows model would imply.

**What it cost.** Three rules moved from tested columns into a query header:
the gap-and-island itself, `longest_possible_stay_nights = least(window,
maximum_nights)`, and window length as `count(*)` rather than `datediff`. All
three produce plausible wrong answers when forgotten, and the cap genuinely binds
in 8 of 204 windows.

[../tests/assert_stay_cap_binds.sql](../tests/assert_stay_cap_binds.sql) is what
remains of the guard: it fails if the cap stops binding anywhere, which would
mean the clamp had become dead code — or that `maximum_nights` stopped arriving.
Nothing can assert that an ad-hoc query *applies* the clamp, and that is the
honest cost of collapsing a model into an analysis.

**One of the three came back, as a column.** `is_window_start` and
`availability_window_seq` on `int_listing_daily`, carried through
`fct_listing_daily`. The semantic layer is what changed the arithmetic: a
semantic view cannot express a window function at all, so questions 3 and 26 as
verified queries would have restated the gap-and-island in a string literal that
nothing validates — on top of the analysis and the cap test that already had it.
Four copies of an 8-line window function is a different trade than one.

The column form is deliberately not the same expression the analysis used.
`calendar_date - row_number()` only works on a rowset already filtered to
available nights, so it can never be a column; a running sum of run-starts
(`is_available and not lag(is_available)`) computes over the whole calendar
instead. Verified equivalent on all 204 windows — same listing, start date,
length, and clamped value. It buys the column at the price of an assumption: the
calendar must be gap-free per listing, which it is at 50 × 365 with no gaps and
no duplicate dates.

What it does **not** buy is a shorter answer to either question. `count(*)` and
`least(window, cap)` still live in the consumer, and "longest window per listing"
is still a two-level aggregation, so questions 3 and 26 remain CTE-wrapped as
verified queries. Only the least dangerous of the three rules was retired.

**The general shape.** A model earns its place by encoding a rule used in more
than one place, not by having been built. One consumer and a reproducible
derivation is the case for collapsing; a rule that is easy to get subtly wrong is
the case against. Here the single consumer won, and the rule was preserved as a
test plus a documented warning rather than lost — and when a fourth consumer
appeared, the cheapest part of the rule was promoted to a column rather than the
models being restored. The count of consumers is the thing that moved, not the
principle.

# Unresolved

- **Listing 276450 is missing** from `listings` but referenced by 367 rows
  across the other two tables. Worth checking whether the source CSV was
  truncated.
- **Verification methods may be nested rather than distinct.**
  `offline_government_id` is a strict subset of `government_id` here, and
  `work_email` of `email`. Whether that is a source guarantee or an accident of
  this snapshot is unknown, and it decides whether the pairs can be summed. The
  `warn_new_verification_method` test on `int_host_verifications` warns if the
  source grows a method, which is the signal to revisit this — it does not answer
  the question.
- **`bathrooms_text` `"60 baths"`** exists in raw but only on a dropped row. It
  will reappear if the NULL-id rows are ever fixed upstream.
