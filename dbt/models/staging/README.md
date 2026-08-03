# Staging layer — cleaning log

Every transformation applied between `RENTALS.RAW_DATA` and the `stg_*` models,
and the data defect each one addresses. Keep this current when you change a
staging model.

Raw tables are landed from CSV as-is — all cleaning happens here, so this is the
single place to look when a downstream number disagrees with the source.

## Row counts

| Model | Raw rows | Staged rows | Difference |
|---|---|---|---|
| `stg_listings` | 51 | 49 | −2 NULL-id rows dropped |
| `stg_calendar` | 18,252 | 18,250 | −2 duplicate rows collapsed |
| `stg_amenities_changelog` | 100 | 100 | none |

---

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

---

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

### Rows deliberately kept

**365 orphan rows** reference `listing_id` 276450, which has no row in
`listings` — a full year of one listing whose parent record never loaded.

These are **not** filtered. Dropping a year of availability data silently is
worse than surfacing it, so the relationships test is set to `severity: warn`.
Decide explicitly whether to exclude them when building marts; an inner join to
`stg_listings` will exclude them for you.

### Known-good invariant

`available = true` ⟺ `reservation_id is null` holds for all 18,250 rows (8,191
available / 10,059 booked). Asserted with `dbt_utils.expression_is_true` so a
future load that breaks it fails loudly.

---

## stg_amenities_changelog

Grain: one row per listing per change timestamp.

No rows dropped, no casts needed — the raw types are already correct.

| Change | Detail |
|---|---|
| `amenities_change_id` | Surrogate key over `(listing_id, changed_at)`. |
| `change_at` → `changed_at` | Consistent past-tense naming for event timestamps. |

**2 orphan rows** reference the same missing listing 276450. Kept, and warned
on, for the same reason as `stg_calendar`.

---

## Test severity

Six tests warn rather than error. All six reflect real defects in the raw data
that staging does not fully repair:

| Test | Rows | Why warn |
|---|---|---|
| `not_null` on `listings.id` (source) | 2 | Documents the defect at the source; `stg_listings` filters it, where the same test errors. |
| `unique_combination_of_columns` on `calendar` (source) | 1 | Source-level duplicate; `stg_calendar` fixes it, where the same test errors. |
| `relationships` on `calendar.listing_id` | 365 | Orphans kept by design. |
| `relationships` on `amenities.listing_id` | 2 | Same. |
| `relationships` on `stg_calendar.listing_id` | 365 | Same defect re-checked post-staging. |
| `relationships` on `stg_amenities.listing_id` | 2 | Same. |

The pattern: **source tests warn, model tests error.** Source tests describe
what arrived; model tests guarantee what staging produced. A red build then
always means a staging bug, never a known upstream defect — while the upstream
defects stay visible instead of being silently swallowed.

If listing 276450 is ever backfilled, all four relationships warnings clear on
their own and can be promoted to `error`.

## Unresolved

- **Listing 276450 is missing** from `listings` but referenced by 367 rows
  across the other two tables. Worth checking whether the source CSV was
  truncated.
- **`host_verifications` and `amenities`** are still raw strings. Parsing them
  into arrays or a bridge table is a mart-layer concern.
- **`bathrooms_text` `"60 baths"`** exists in raw but only on a dropped row. It
  will reappear if the NULL-id rows are ever fixed upstream.
