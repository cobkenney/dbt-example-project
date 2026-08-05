---
name: add-fact-or-dim-to-sv
description: Add a fact or dimension to one of the Snowflake semantic views in models/marts/core_context_layer, carrying the column description over from the mart table it comes from. Use when exposing a mart column to the context layer, when a business question needs a field the semantic views do not have yet, or when asked to add a fact, dimension, metric or field to a sem_* view.
---

# Add a fact or dimension to a semantic view

Exposing a mart column to the context layer is four decisions, not one edit: which
section it belongs in, which view can safely hold it, what the `COMMENT` says, and
whether a verified query should pin it. Get the second one wrong and Snowflake
raises no error — it returns a plausible number that has been multiplied by a join.

## Ask these five questions first

Ask them together, in one round, before reading any files. Do not guess an answer
that the user can give in a word:

1. **What is the field name?** The mart column to expose.
2. **What table does it come from?** One of `dim_listings`, `dim_hosts`,
   `fct_listing_daily`, `fct_reservations`.
3. **Which semantic view should it be added to?** One of `sem_listing_daily`,
   `sem_listing_performance`, `sem_reservations`, `sem_host_performance`.
4. **What business question is it trying to answer?** This is not paperwork — it
   decides the `COMMENT` text, whether the field needs synonyms, and whether a
   metric has to come with it. If the answer is a question already in
   `BUSINESS_QUESTIONS.md`, use its number.
5. **Do you want a verified query for it?** Default no. Say that adding one means
   a new macro in `macros/verified_queries/` and a figure to pin the result to.

If the user has already answered some in their request, only ask what is missing.

## Then gather the facts

**The description comes from the manifest, not the `.yml`.** Mart descriptions use
`{{ doc('name') }}` references into `models/docs.md`, and the manifest is where
those are resolved. Read `dbt/target/manifest.json`:

```bash
python3 -c "
import json
m = json.load(open('dbt/target/manifest.json'))
col = m['nodes']['model.rentals.<table>']['columns']['<column>']
print(col['description'])
"
```

If the manifest is missing or stale, `dbt parse` refreshes it. Data types are in
`target/catalog.json`, which only `dbt docs generate` refreshes — treat it as a
hint, not proof the column exists.

**If the mart column has no description, stop and write that one first.** Pulling
nothing over is worse than pulling nothing: the semantic view gets a comment
invented here, and the two are drifted from the moment they are created.

Then read the target view's `TABLES(...)` and `METRICS(...)` clauses to establish
the table's **role**, which is the check that matters.

## The fan-out rule

Every view has exactly one **measure table** — the one its metrics aggregate. Every
other table is a **dimension-only join**, exposed for its attributes only.

| View | Measure table | Dimension-only |
|---|---|---|
| `sem_listing_daily` | `fct_listing_daily` | `dim_listings`, `dim_hosts` |
| `sem_reservations` | `fct_reservations` | `dim_listings`, `dim_hosts` |
| `sem_listing_performance` | `dim_listings` | `dim_hosts` |
| `sem_host_performance` | `dim_hosts` | — (no `RELATIONSHIPS` clause at all) |

> **A numeric column from a dimension-only table must go in `DIMENSIONS`, never
> `FACTS`.** A fact can be aggregated across the join, which multiplies it by the
> row count on the other side. `sum(dim_listings.total_revenue)` grouped by
> `calendar_date` in `sem_listing_daily` returns each listing times its 365
> calendar rows. Snowflake raises no error and the number looks plausible.

So `bathrooms` from `dim_listings` is a `DIMENSION` in `sem_listing_daily` even
though it is a `NUMBER`. If the user wants it aggregated, the answer is to add the
measure to the view that owns its grain — `sem_listing_performance` — not to make
it a fact where it does not belong.

Also check before writing: **facts, dimensions and metrics share one namespace**,
so a name already used in any of the three sections will not build. That is why the
host view's roll-ups are prefixed `portfolio_*`.

## Writing the entry

Add it to the matching section, qualified with the logical alias from `TABLES(...)`
(`listing.`, `daily.`, `host.`, `reservation.`), keeping the section's existing
order and comma style:

```sql
    listing.bathrooms AS listing.bathrooms
        WITH SYNONYMS = ('baths', 'bathroom count')
        COMMENT = 'Bathroom count, 1.0 to 2.5. Does NOT indicate whether the bathroom is shared - is_shared_bathroom is the only signal for that.'
```

Four conventions this layer holds to:

- **`COMMENT` is the real documentation.** `persist_docs` is unsupported for
  semantic views, so the `.yml` description reaches `dbt docs` and nothing else.
  The `COMMENT` is what Snowflake stores and what Cortex Analyst reads to choose
  between fields. Carry the mart description's *substance* over — especially any
  NULL behavior, any caveat, and any "see other column" pointer — rather than
  copying its wording verbatim; the mart description explains a column to a
  person reading a table, and this one has to help a client choose between fields.
- **No apostrophes in `COMMENT` text.** Each is a single-quoted SQL string. Write
  the prose around the apostrophe rather than doubling it.
- **Synonyms only where a plain question would use the word,** and never one
  already claimed in that view — a synonym on two objects makes the client's pick
  arbitrary. Check the other entries before adding one.
- **Never anchor recency to `current_date`.** The snapshot is a fixed year ending
  2022-07-11. Anything time-based measures against `as_of_date` or the max
  calendar date, or the answer drifts on every run.

**Does it need a metric too?** A fact with no metric over it is only reachable at
row grain, so if the business question asks for an aggregate, add the metric in the
same change. A dimension needs no metric.

**Does `AI_SQL_GENERATION` need a line?** Add one only if a reasonable query
against the new field would be wrong — a filter that must be applied, or a
neighbouring field it will be confused with.

The `.yml` beside the model needs no change. Semantic views expose metrics and
dimensions rather than columns, so there are no column docs and no `data_tests`
there; tests belong on the underlying mart.

## Verified query, if asked for

One macro per business question in `macros/verified_queries/`, returning
`{name, question, sql}` entries, registered in the view's `ai_verified_queries([...])`
list. Follow `verified_queries_q13.sql` as the model. What matters:

- The SQL goes against **this view's own metrics and dimensions** in
  `SEMANTIC_VIEW(...)` form, not against the mart. Its purpose is to teach a
  client which field answers which question.
- `QUESTION` is required, and is the surface a client matches against — write it
  the way somebody would actually ask. Several entries may share one query under
  different phrasings.
- Banding a FACT needs a CTE wrap: Snowflake rejects FACTS and METRICS in one
  clause.
- Apostrophes are fine here, unlike in `COMMENT` — the dispatcher doubles them.
- **Snowflake does not validate the SQL at create time.** A query against a
  nonexistent column builds green. So run the query against the mart to get the
  figure, record it in the macro header, and tell the user the query is
  unvalidated until it has been run through the view itself.

## Verify before reporting done

`sqlfluff` excludes this folder — the DDL is not a `select`, so the linter cannot
parse it and passing means nothing. Snowflake is the parser that matters:

```bash
cd dbt && dbt run -s <view_name>
```

That needs warehouse credentials (`set -a; source ../.env; set +a`). If they are
not available, say so plainly — the entry is written but unverified — rather than
implying it built.

Then report: which section the field went into and why, the `COMMENT` you wrote,
anything you carried over from the mart description and anything you deliberately
did not, and whether it built.
