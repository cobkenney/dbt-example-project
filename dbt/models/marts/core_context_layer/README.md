# core_context_layer

Snowflake semantic views over `core_mart`. This is the layer a natural-language
client — Cortex Analyst, or anything else that turns English into SQL — reads to
learn what the tables mean.

It stores no rows and transforms nothing. It names the tables, their join paths,
and the metrics, so that "what was occupancy last quarter" resolves to one agreed
definition instead of whatever the asker happened to write.

Built with [Snowflake-Labs/dbt_semantic_view](https://github.com/Snowflake-Labs/dbt_semantic_view),
pinned in `packages.yml`. dbt has no native support for `CREATE SEMANTIC VIEW`, and
that package is Snowflake's own. The model body **is** the DDL from `TABLES(...)`
onward — not a `select` — which has consequences noted under
[Conventions](#conventions).

## Four views, and why not one

There are exactly four tables in `core_mart` that own additive measures, and
there is one view per such table. That is not a stylistic choice; it is forced by
fan-out.

A semantic view will aggregate across a join, and Snowflake raises **no error**
when the join fans out. Put `fct_listing_daily` and `dim_listings` in one view and
`sum(total_revenue)` grouped by `calendar_date` multiplies every listing by its
365 calendar rows. The query succeeds and returns a plausible, badly wrong number.

So: **one view per grain of additive measure.** Every other table joins in as a
dimension-only logical table — its attributes are exposed, its measures are not.

| View | Measure table (grain) | Dimension-only | Questions |
|---|---|---|---|
| `sem_listing_daily` | `fct_listing_daily` — listing × date | `dim_listings`, `dim_hosts` | 1, 2, 3, 6, 10, 15, 16, 22, 26, 27 |
| `sem_reservations` | `fct_reservations` — listing × reservation | `dim_listings`, `dim_hosts` | 17, 23, 24 |
| `sem_listing_performance` | `dim_listings` — listing, lifetime | `dim_hosts` | 4, 5, 7, 8, 9, 11, 12, 13, 14, 25 |
| `sem_host_performance` | `dim_hosts` — host, lifetime | — | 18, 19, 20, 21 |

That covers 27 of the 28 questions in
[BUSINESS_QUESTIONS.md](../../../../BUSINESS_QUESTIONS.md). Only #28 (repeat
bookings) is out, for lack of a guest key in the source.

**The split is verified, not just asserted.** Asking `sem_listing_daily` for
`listing.total_revenue` by month fails to compile, because that metric does not
exist in that view. The double-count is unwritable rather than merely
discouraged.

### Why `sem_host_performance` is not derived from listings

Host revenue *can* be had by aggregating `dim_listings` grouped by `host_id`, so a
fourth view looks like duplication. It is not, because the two weightings give
different numbers and both are legitimate:

- **host-weighted** — every host counts once, whatever the portfolio size. This
  view. It is what `analyses/05` reports.
- **listing-weighted** — every listing counts once, so a 5-listing host pulls the
  average five times as hard. That is `sem_listing_performance`.

Overall occupancy is **55.9%** host-weighted against **54.2%** night-weighted.
Aggregating listings to answer a host question silently returns the second when
the question wanted the first. Two views, each weighting one way with comments
saying which, beats one view where the choice is invisible.

`sem_host_performance` is also the only view with **no `RELATIONSHIPS` clause** —
one logical table, nothing to join. Adding `dim_listings` is exactly the bug it
exists to prevent: 7 of 36 hosts hold more than one listing, so summing host
revenue across the listing join double-counts every one of them.

## Revenue reconciliation

Verified across all four views:

| View | Revenue |
|---|---|
| `sem_listing_daily` | $1,684,864 |
| `sem_reservations` | $1,684,864 |
| `sem_listing_performance` | $1,684,864 |
| `sem_host_performance` | **$1,608,344** |

The host view is short by exactly **$76,520** — orphan listing 276450, which has
no `listings` row and therefore no host to attribute its revenue to. This is
stated in that view's `COMMENT` and in its `AI_SQL_GENERATION` instructions, so a
client reports the gap rather than presenting a false reconciliation.

## Conventions

**`COMMENT` is the real documentation.** `persist_docs` is explicitly unsupported
for semantic views, so the `.yml` descriptions reach `dbt docs` and nothing else.
The `COMMENT` clauses inside the DDL are what Snowflake stores and what Cortex
Analyst reads to choose between metrics. That is why they carry the caveats
verbatim rather than pointing elsewhere.

**`AI_SQL_GENERATION` carries the rules that make a reasonable query wrong.** One
per view. Every one of them forbids `current_date`: the snapshot is a fixed year
ending 2022-07-11, so any recency measured against the clock drifts on every run.
The four caveats from `BUSINESS_QUESTIONS.md` are encoded here — the snapshot
edges, the non-unique `reservation_id`, the orphan listing, and the
`bedrooms`/`beds` gaps.

**Both occupancy definitions are named metrics.** `avg_occupancy_rate` and
`occupancy_rate_weighted`, everywhere both are meaningful, each with a `COMMENT`
saying which question wants it. They happen to be *identical* in
`sem_listing_performance`, because `calendar_days` is 365 for all 50 listings —
noted in the comments there, and kept as a pair anyway so the names mean the same
thing in every view.

**No apostrophes in comment text.** Each `COMMENT` is a single-quoted SQL string;
an apostrophe inside one needs doubling, and that is a trap for whoever edits
next. The prose is written around it.

**No column docs and no `data_tests`.** A semantic view exposes metrics and
dimensions, not columns, so `dbt test` has nothing to attach to — a generic test
cannot reach a metric. Grain, uniqueness and reconciliation tests all live on the
underlying marts, which is the right place: if `fct_listing_daily` is sound, a
view over it cannot invent a wrong number, only expose it under a wrong name.
Pinning names to figures is the job of the verified queries, still to be added.

**`sqlfluff` excludes this folder.** Semantic-view DDL is not a `select` and the
snowflake dialect cannot parse it, so every file here fails with "unparsable
section" regardless of formatting. Snowflake is the parser that matters — `dbt
run` fails outright on a malformed clause, which is stricter than the linter was.

## What semantic views cannot express

- **Window functions.** So questions 3 and 26 (gap-and-island over availability
  runs) cannot be a plain `SEMANTIC_VIEW(...)` query. They work wrapped in a CTE,
  which is allowed — verified reproducing `analyses/03` exactly: listing 1303261 →
  159 nights, 182613 → 112.

  **This limitation moved a column upstream.** The gap-and-island now lives on
  `fct_listing_daily` as `availability_window_seq`, so `sem_listing_daily` exposes
  it as an ordinary dimension and both questions group on it instead of restating
  the window function. They stay CTE-wrapped — the aggregation is two-level and
  question 3's `least(window, cap)` is arithmetic across two aggregates — but what
  the view could not express is now precomputed rather than absent. See
  [models/README.md](../../README.md), "Collapsed models".
- **Ranking.** So question 7 (share of revenue from the top 5 listings) has **no
  metric** in `sem_listing_performance`. A metric that quietly returned something
  adjacent would be reported as the answer; better absent, with the comment
  saying to rank outside the view.
- **`LABELS = (FILTER)`.** Documented by Snowflake, rejected as a syntax error by
  the version this account runs. The intent — "this column is for the `WHERE`
  clause, not a grouping key" — lives in the `COMMENT` and
  `AI_SQL_GENERATION` instead.
- **A metric and a fact sharing a name.** They share one namespace, so the host
  view's roll-ups are prefixed `portfolio_*` where they would otherwise collide.

## Verified against `analyses/`

Every figure below was reproduced through the semantic views and matches the
existing verified analysis exactly.

| Question | Figure | Source |
|---|---|---|
| 1 — revenue without AC | 21.2% of July 2022 revenue | `analyses/01` |
| 3 — longest picky-renter stay | 1303261 → 159 nights; 182613 → 112 | `analyses/03` |
| 17 — reservation summary | 1,565 bookings, 10,059 nights, 6.49 vs 6.43 nights, $1,076.59 | `analyses/04` |
| 19 — multi vs single-listing hosts | $19,267 / 38.5% / 6.25 vs $39,749 / 60.0% / 6.11 | `analyses/05` |
| 22 — price per bedroom and bed | entire home $216.84 / $165.68 / $128.10; private room $89.11 / $85.74 / $84.15 | `analyses/06` |

## `AI_VERIFIED_QUERIES`

A question-and-SQL pair per business question: what teaches Cortex Analyst the
shape of a correct answer, and what pins each metric to a figure already verified
in `analyses/`. All four views carry them.

| View | Questions | Entries |
|---|---|---|
| `sem_listing_daily` | 1, 2, 3, 6, 10, 15, 16, 22, 26 | 46 |
| `sem_listing_performance` | 4, 5, 7, 8, 9, 11, 12, 13, 14, 25, 27 | 47 |
| `sem_reservations` | 17, 23, 24 | 14 |
| `sem_host_performance` | 18, 19, 20 | 13 |

Entries outnumber queries, because several phrasings share one query — `QUESTION`
is what a client matches against, so the spend goes where a plausible-but-wrong
answer is easiest to get.

**Question 21 has no entries**, alone among the 27. Trust-signal adoption means a
row per verification method, and the methods are only enumerable from
`stg_listings` — a `ref()` out of `core_mart`, which this layer does not take. The
question also has no finding to pin: 36 hosts against 11 methods is too few to
conclude from. That view's `COMMENT` and `AI_SQL_GENERATION` say so instead.

**One macro per question** in [macros/verified_queries/](../../../macros/verified_queries/),
each returning `{name, question, sql}` entries; `ai_verified_queries()` dispatches
by name and emits the whole clause, so each view file carries one line. Entry
names stay `q17_a`, `q17_b` so they trace back to `BUSINESS_QUESTIONS.md`. Each
macro's header records why its query is shaped the way it is — which is where the
CTE wraps and the orphan-filter decisions are argued.

**Apostrophes are escaped here, unlike in `COMMENT` text.** The dispatcher doubles
them in both fields. Writing prose around them works for a comment; it does not
work for query SQL, where a string literal like `'entire home/apt'` is legitimate
and unavoidable.

**Not yet validated.** Item 14 below.

Four properties of the feature were established by probing this account rather
than read off the documentation, because they change how the queries have to be
written:

- **The SQL goes against these views' own metrics and dimensions**, in the
  `SEMANTIC_VIEW(... METRICS ... DIMENSIONS ...)` form — not against `core_mart`
  directly. Per Snowflake: "Verified SQL queries must use the names of the
  logical tables and columns defined in the semantic model, not those in the
  underlying dataset." A verified query exists to teach a client which metric
  answers which question, and base-table SQL teaches it nothing about choosing
  `avg_length_of_stay` over `avg_length_of_stay_all`. So `analyses/` are the
  source of the verified *figures* here, not of the query text.
- **Snowflake does not validate the SQL when the view is created.** A verified
  query selecting a nonexistent column from a nonexistent table was accepted and
  the `CREATE` succeeded. A query that has silently rotted still builds green and
  surfaces only when a client serves it as a correct answer, which is why the
  validator in item 14 is part of the work rather than a nicety.
- **`QUESTION` is required and is the matching surface.** Omitting it fails with
  `Property '[QUESTION]' must be specified` — Snowflake enforces the grammar
  while ignoring whether the SQL is true. Because a client matches the asked
  question against this text, it should read the way somebody would actually ask.
  Several entries may share one query under different phrasings, which is worth
  spending where a plausible wrong answer is easiest to get.
- **Metrics need the explicit `SEMANTIC_VIEW(...)` form.** Selecting from a view
  by name works for dimensions but fails on a metric with "must be one of the
  following types: (DIMENSION, FACT)".

### Reference values

Figures already reproduced through the views in that form, and the column ranges
a banding query would need:

| Check | Value |
|---|---|
| Q17 reservations | 1,565 bookings / 10,059 nights / 6.4910 vs 6.4275 nights / $1,076.59 / 70 censored |
| Q19 multi vs single host | 7 hosts → $19,267.27 / 38.46% / 6.2516; 29 hosts → $39,748.97 / 60.05% / 6.1098 |
| `review_scores_rating` | 0.00 to 5.00, NULL on 3 listings |
| `list_price` | $25 to $571 |
| `minimum_nights` | 1 to 180, 13 distinct values |
| Q26 unbookable windows | 59 of 204 windows / 300 nights / $64,062 asked, 4.48% of the $1,430,664 in open inventory |
| Availability windows | 204 across 50 listings; `minimum_nights` varies inside 7 of them; the owner cap binds in 8 |
