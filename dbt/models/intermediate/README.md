# Intermediate layer

Reshaping between staging and marts: flattening JSON, joining the daily grain,
and collapsing dates into availability windows. No cleaning happens here — see
[../staging/README.md](../staging/README.md) for that.

## Models

| Model | Grain | Materialization | Rows |
|---|---|---|---|
| `int_amenities_current` | listing | table | 50 |
| `int_listing_daily` | listing × date | table | 18,250 |
| `int_listing_availability_windows` | listing × availability window | table | 204 |

All tables, with no per-model exceptions — one rule for the layer. An earlier
version made the availability-windows model a view on the grounds that its
window logic was cheap, but that rationale didn't hold up: building it takes
0.50s against 0.79s and 1.78s for the two tables, so "cheap" didn't distinguish
it, and the inconsistency cost more in explanation than the 0.5s saved.

This departs from dbt's recommended `ephemeral` for intermediate models.
Ephemeral inlines each model as a CTE in every consumer — nothing lands in the
warehouse, but the logic re-runs per consumer. Both `int_amenities_current` and
`int_listing_daily` have two consumers, so tables build that work once instead.
The cost of that choice is these models are queryable, which is why analysts are
pointed at the marts layer rather than this one.

At this data size nothing warrants `incremental` — it would add reload
complexity for no measurable gain.

---

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
[../../tests/assert_amenities_predate_calendar.sql](../../tests/assert_amenities_predate_calendar.sql)
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

The changelog holds 2 events per listing, and the latest is taken via
`qualify row_number() = 1`. This is a point-in-time-safe shape, but note the
data doesn't currently require it: **every changelog event predates the calendar
window** (latest change 2021-07-06, window opens 2021-07-12), so amenities are
static across the whole period and the latest state agrees with
`stg_listings.amenities` for all 49 listings present in both.

---

## int_listing_daily

The daily grain the marts aggregate from: `stg_calendar` joined to listing
attributes and amenity flags, one row per listing per date.

### Left joins are load-bearing

Listing 276450 appears in the calendar but not in `listings`. An inner join
drops its 365 rows and **$2,200** of booked July-2022 revenue — enough to shift
the no-AC revenue share from the correct **21.2%** to **22.1%**.

The `is_orphan_listing` flag makes that choice explicit downstream: marts can
include or exclude those rows deliberately rather than inheriting a silent
join-side effect. Row count is asserted equal to `stg_calendar` via
`dbt_utils.equal_rowcount`, so a future inner join can't quietly drop rows.

### revenue

```sql
case when not is_available then price end as revenue
```

NULL on available nights, so `sum(revenue)` is total booked revenue with no
filtering. A test asserts revenue is non-null exactly when a night is booked.

`neighborhood`, `property_type`, and other listing attributes are NULL on the
365 orphan rows — expected, and the reason Q2-style neighborhood aggregations
naturally exclude them.

---

## int_listing_availability_windows

Gap-and-island over consecutive available dates. Subtracting a row number from
the date yields a constant per contiguous block:

```sql
dateadd(day, -row_number() over (partition by listing_id order by calendar_date),
        calendar_date) as island_group
```

204 windows across 50 listings.

### longest_possible_stay_nights

```sql
least(window_length_nights, maximum_nights)
```

Both constraints bind in real cases, so neither can be dropped:

| Listing | Window length | `maximum_nights` | Longest stay | Binding constraint |
|---|---|---|---|---|
| 1303261 | 159 | 180 | **159** | availability window |
| 182613 | 112 | 1125 | **112** | availability window |
| 743211 | 206 | 90 | **90** | owner's cap |
| 1374466 | 220 | 180 | **180** | owner's cap |

An owner cap can exceed the available window, and a window can exceed the cap —
hence the clamp rather than picking one column. The cap is the binding
constraint in **8 of 204** windows.

### window_length_nights counts dates, not datediff

`count(*)` over available dates, not
`datediff(window_start_date, window_end_date)` — which is one lower. Listing
1303261's longest window runs 2022-02-03 → 2022-07-11: 159 available dates
spanning 158 days. Every available calendar date is treated as a bookable night,
which is what makes the expected answer 159 rather than 158.

---

## Business questions these support

All three verified against the int models:

| Question | Models | Verified result |
|---|---|---|
| Amenity revenue by month | `int_listing_daily` | 21.2% of July 2022 revenue from listings without AC |
| Neighborhood price increase | `int_listing_daily` | Back Bay $44.00 across 1 listing |
| Longest stay, lockbox + first aid kit | `int_listing_availability_windows` + `int_amenities_current` | Listing 1303261 → 159 nights |

2 listings carry both a lockbox and a first aid kit; 42 of 50 have air
conditioning.
