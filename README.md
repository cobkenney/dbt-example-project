# dbt-example-project

An example dbt project for a rental property marketplace company: three raw CSVs
landed in Snowflake, modeled through staging / intermediate / marts, with a
Snowflake semantic view layer on top for natural-language querying.

This README is the build log — the order things were done in and the decisions
made along the way. The questions the marts answer live in
[BUSINESS_QUESTIONS.md](BUSINESS_QUESTIONS.md).

---

## 1. Set up a free Snowflake account

A Snowflake trial account gives a warehouse, a role, and enough credits to build
this project many times over. Created a `RENTALS` database with a `RAW_DATA`
schema for the landed CSVs.

Credentials go in `.env` and are read by `dbt/profiles.yml` through
`env_var()` — see [.env.example](.env.example). Nothing is committed to the repo.

## 2. Load the CSVs into Snowflake as tables

Three files landed into `RENTALS.RAW_DATA` as-is, with no cleaning:

| Table | Rows | Grain |
|---|---|---|
| `listings` | 51 | one row per listing, host attributes denormalized on |
| `calendar` | 18,252 | one row per listing per date |
| `amenities_changelog` | 100 | one row per listing per change timestamp |

Everything landed as the datatypes outlined in the project prompt.

## 3. Query the raw tables to find out what is actually in them

This was the largest chunk of the work and it drove nearly every modeling
decision that follows. What turned up:

**The calendar is a fixed one-year window** — 2021-07-12 through 2022-07-11, not
a rolling one. Anything measured against `current_date` drifts on every run, so
the marts carry an `as_of_date` set from the snapshot's last date instead.
Reservations touching either edge are truncated, so their length is a floor
rather than a fact.

**Hard deletes.** Listing 276450 has 365 calendar rows and 2 changelog rows but
no row in `listings`. Dropping a year of availability data silently is worse
than surfacing it, so it is kept everywhere and flagged `is_orphan_listing`;
consumers decide. Revenue queries should keep it, attribute comparisons should
filter it out.

**The amenities changelog predates the calendar.** Exactly 2 events per listing:
the first in 2008–2009, the second between 2020-07-17 and 2021-07-06 — six days
before the calendar opens. No event falls inside the fact window, so the
"history" cannot be joined point-in-time to anything. That made a full SCD2
build a provable no-op (verified before collapsing it — see step 7).

**NULL ids.**
- `listings.id` is NULL on 2 rows. Those rows cannot be joined or tested for
  uniqueness, so staging drops them. One of them held the max raw price
  (`$999.99`) and a `60 baths` outlier, which is why staged prices top out lower
  than raw.
- `calendar.reservation_id` holds the literal 4-character string `'NULL'` on
  8,193 unbooked rows, not a true NULL. Before that was fixed,
  `reservation_id is not null` was true for every row — any "is this date
  booked?" filter would have returned the whole table.

**Foreign keys with no parent table.** `calendar.reservation_id` and
`listings.host_id` both reference entities that were never delivered as sources.
Hosts are reconstructed by grouping the listings table on `host_id` (36 hosts
across 49 listings); reservations are derived by grouping the calendar's booked
nights. Both work, and both have costs worth stating: cancellations and
unconfirmed booking requests are invisible, and booking lead time is
unanswerable at any amount of modeling effort.

**`reservation_id` is not unique.** Id 836 appears on two different listings —
753446 and 801680 — both single nights on the same date. Grouping on
`reservation_id` alone would merge them into one impossible two-night
reservation spanning two properties. The grain is `(listing_id,
reservation_id)`, with `reservation_key` as the surrogate key.

**Duplicates.** One calendar row is triplicated, byte-identical across every
column, which breaks the stated grain and inflates any aggregate over that
listing.

**Possible PII.** `host_name` is a real person's name. `host_location` is
self-reported free text — city-level here rather than an address, but that is a
judgment call rather than a fact about the column. Both got a deliberate
decision in step 11.

**JSON hiding in text columns.** `listings.amenities`,
`listings.host_verifications`, and `amenities_changelog.amenities` are all JSON
array strings, not free text. Flattening them (steps 7 and 10) is what makes
them queryable without substring matching — `contains(amenities, '%air%')` also
matches "Hair dryer", and `'government_id'` cannot be distinguished from
`'offline_government_id'`.

## 4. Scaffold the dbt project and connect it to Snowflake

Used AI to generate the project skeleton, then wired up the pieces that carry
real decisions:

**`profiles.yml`** with `dev` and `prod` targets, both reading credentials from
env vars. Kept in the repo rather than `~/.dbt/` so the project is
self-contained.

**A custom `table_insert_overwrite` materialization**
([macros/infrastructure/table_insert_overwrite.sql](dbt/macros/infrastructure/table_insert_overwrite.sql)).
dbt's built-in `table` emits `create or replace`, which creates a *new object* —
and Snowflake Time Travel is scoped to an object, so the pre-build state of a
mart is unreachable. `insert overwrite into ... select` replaces the rows and
keeps the object, so you can still ask what a mart looked like before its last
build. It falls back to `create or replace` when the column signature changes,
since `insert overwrite` binds by position and cannot reshape a table. Marts are
also set `+transient: false`, because Snowflake refuses to let you configure
retention on a transient table. Would suggest setting time travel window on
marts tables to something like 72 hours so we could analyze any unexpected
behaviors effectively (even after weekends). This is not without storage cost,
so would need to weigh that.

**`generate_schema_name`**
([macros/infrastructure/generate_schema_name.sql](dbt/macros/infrastructure/generate_schema_name.sql)).
Each layer gets its own schema so access can be granted per layer —
`analytics_stg`, `analytics_int`, `analytics_seed`, and one schema per mart. In
`prod` the `+schema:` value is used bare, since that is what grants are written
against; anywhere else it is prefixed with the developer's schema so one
person's build cannot clobber another's or the tables analysts query.

**Pre-commit hooks** ([.pre-commit-config.yaml](.pre-commit-config.yaml)):
`sqlfluff` on staged model and analysis SQL with the dbt style guide's
lowercase-everything rules, plus `detect-private-key`,
`check-added-large-files`, and `no-commit-to-branch` for `main`.

**Packages** ([packages.yml](dbt/packages.yml)): `dbt_utils` for surrogate keys,
dedupe and the generic tests, and `Snowflake-Labs/dbt_semantic_view` for step 12
— dbt has no native `CREATE SEMANTIC VIEW`, and that is Snowflake's own package.

**docs.md** ([dbt/models/docs.md](dbt/models/docs.md)): set up scaffolding for
shared column descriptions across models (and then added to as models were built).
This ensures shared columns across layers or models have the same definition.

## 5. Source yml and staging models

One source yml describing all three raw tables and one staging model per table.
Staging casts, renames, and dedupes — nothing else — so it is the single place
cleaning happens.

Everything found in step 3 got fixed here or documented as unfixable:
`try_cast` rather than `cast` throughout, so a future bad value yields NULL
instead of failing the build; `$` and thousands separators stripped from
`listings.price` but not `calendar.price`, which has no symbol; `bathrooms`
parsed out of `"2.5 baths"` while keeping `bathrooms_text`, since the label
carries detail the number loses; `nullif` on the literal `'NULL'` string;
`dbt_utils.deduplicate` on the calendar's grain; surrogate keys for the compound
grains.

## 6. Decide what the marts should be

Worked backward from the first three business questions rather than modeling
everything the source offered:

1. Share of monthly revenue from listings without AC
2. Neighborhood average price increase
3. Longest possible stay for a renter who needs a lockbox and a first aid kit

Questions 1 and 2 are both revenue-and-price by a time grain, which wants the
atomic daily grain — `fct_listing_daily`, deliberately left at listing × date
rather than pre-aggregated by month, so it serves both. Question 3 wants listing
attributes (and windows) and amenity flags — `dim_listings`.

## 7. Intermediate models

The reshaping layer: flatten JSON, join the daily grain, reduce to the host and
reservation grains. No cleaning — that stayed in staging.

**Amenities got flattened rather than string-matched.** `try_parse_json` on the
changelog yields 2,285 listing-amenity pairs across 81 distinct names in
`int_listing_amenities`, pivoted into `has_*` boolean flags downstream in
`int_listing_daily` where they are consumed. Flattening first and comparing
`amenity_name = 'Air conditioning'` removes a class of bug rather than dodging
one instance of it.

**Sourced from the changelog, not `listings`.** The changelog covers all 50
listings the calendar references; `listings` is missing the orphan. So the
orphan gets real amenity flags instead of NULLs. Would prefer if the source
contained the orphan / hard deletes.

**Amenity history was built and then deliberately collapsed.** A full SCD2
version (`valid_from`/`valid_to` via `lead()`, joined to the calendar with
`between`) was built and compared against a latest-wins model: 0 of 18,250
calendar rows resolved to a superseded amenity version, and the July 2022 no-AC
revenue share was identical. A point-in-time join is a no-op on this data, so
the bridge reduces to the latest event per listing. The assumption is enforced
rather than documented —
[assert_amenities_predate_calendar.sql](dbt/tests/assert_amenities_predate_calendar.sql)
fails if a changelog event ever lands inside the calendar window, which is
exactly when latest-wins would start misattributing revenue. If this test
failed, we'd need to utilize the changelog history in fct_listing_daily.

**Left joins are load-bearing.** An inner join against `listings` drops the
orphan's 365 rows and $2,200 of booked July 2022 revenue — enough to move the
no-AC revenue share from 21.2% to 22.1%. `is_orphan_listing` is computed once in
`int_listings` and read downstream, rather than each consumer deriving it from
its own join.

Tests here assert the things the reductions could silently break: reservation
nights and revenue reconciling back to the daily grain, reservation nights being
contiguous, and host attributes agreeing across a host's listings.

## 8. Marts

Tables that analysts query, in `core_mart` — the only schema analysts are
granted on. Listing attributes and amenity flags are denormalized onto both
facts, which is intentional star-schema redundancy: answering question 1 or 2
needs no join.

**Decided against an overfit windows model for question 3.** Could have built
model that deterimined every window for every listing, instead landed on window
functions in fct_listing_daily to determine length of a window.

## 9. Have AI generate more business questions

Asked AI what else a company like this would want to know, which produced
[BUSINESS_QUESTIONS.md](BUSINESS_QUESTIONS.md) — 26 questions, split into
answerable today, needs a new model, and **cannot be answered by this source at
any effort**. That third section is the useful one: booking lead time,
cancellations, host-blocked vs booked dates, and cost/margin are all missing
source data rather than missing models, and writing them down stops somebody
spending a day discovering that, but also helps potentially prioritize
sourcing that data in the future.

## 10. Add the models those questions needed

`fct_reservations` and `dim_hosts` plus their intermediate models, and
`int_host_verifications` — flattening `host_verifications` the same way
amenities were flattened, for the same reason.

**Grouped to the host grain before flattening.** Verifications are a *host*
attribute denormalized onto every *listing* row, so flattening `listings`
directly overcounts the 7 multi-listing hosts — the 5-listing host would
contribute each method five times.

**The flag column lists moved into seeds.** A Jinja loop over `select distinct`
is blind in one direction and dangerous in the other: a removed value leaves a
stale column, and a new value silently widens the model on the next run,
documented nowhere. The lists are also quite long in some cases, so accepted
values tests would have dominated the yml file. So the lists live in
`seeds/known_amenity_names.csv` (81) and `seeds/known_verification_methods.csv`
(11), the loops read the seeds, and a `relationships` test at `severity: warn`
fires when the source grows a value the seed does not have. `warn` rather
than `error` because a new amenity upstream is a source change, not a defect —
the warning is a work order, and the
[wake-up-ae](.claude/skills/wake-up-ae/SKILL.md) skill is that work order's
steps.

## 11. Mask the PII

`host_name` does not exist in plaintext anywhere in the dbt layers and could be
considered PII (but also could not be since presumably the website is public.)
Going to assume its PII in analytics database to demonstrate possible ways to
mask the data.
`stg_listings` is the only model permitted to read the raw column and it emits
`host_name_masked` instead — salted SHA-256 truncated to 16 hex characters, via
[macros/infrastructure/mask_pii.sql](dbt/macros/infrastructure/mask_pii.sql).

Masking at the staging boundary rather than in the mart means no downstream model
can leak the plaintext even by accident; there is nothing there to leak. Nothing
is lost analytically, since `host_id` already identifies a host for every join
and grouping in the project.

Three details are what make it real rather than decorative: **the salt** — host
names are first names from a space of a few thousand candidates, so an unsalted
`sha2('Maria')` is recovered by hashing a name list and matching; **NULL in,
NULL out** rather than hashing a coalesced empty string, which would give every
unnamed row one shared hash resembling a single prolific host; and **the hash is
not a host identifier** — 36 hosts hold 35 distinct names, so two of them share
a hash.

What it does not cover: the plaintext still sits in `RAW_DATA`, which dbt cannot
reach — that needs a Snowflake masking policy or a change to what the loader
lands. `host_location` is currently passed through unmasked.

## 12. Semantic views with verified queries

Four Snowflake semantic views in `core_context_layer` — the layer a
natural-language client (Cortex Analyst, or anything else turning English into
SQL) reads to learn what the tables mean. They store no rows; they name the
tables, their join paths and the metrics, so "what was occupancy last quarter"
resolves to one agreed definition instead of whatever the asker wrote.

**Four views, one per grain of additive measure.** A semantic view will aggregate
across a join and Snowflake raises **no error** when that join fans out, so each
view exposes exactly one grain of additive measure and every other table joins in
dimension-only. The split is verified rather than asserted: asking
`sem_listing_daily` for a listing-lifetime revenue metric fails to compile,
because that metric does not exist in that view. The double-count is unwritable
rather than merely discouraged.

Revenue deliberately does not reconcile across all four. Three views report
$1,684,864; `sem_host_performance` reports $1,608,344, short by exactly the
orphan listing's revenue, which has no host to attribute to. Both the `COMMENT`
and `AI_SQL_GENERATION` text say so, so a client reports the gap rather than
presenting a false reconciliation.

**`AI_VERIFIED_QUERIES`** pin each metric to a question-and-SQL pair whose result
was checked against the marts — one macro per business question in
[macros/verified_queries/](dbt/macros/verified_queries/). Four properties of the
feature had to be established by probing, because the documentation omits or
contradicts them:

- The SQL must target **the view's own** metrics and dimensions in the
  `SEMANTIC_VIEW(...)` form, not the underlying mart tables. Base-table SQL
  teaches a client nothing about which metric answers which question.
- **Snowflake does not validate the SQL at create time.** A verified query
  selecting a nonexistent column from a nonexistent table was accepted and the
  `CREATE` succeeded. A rotted query builds green and surfaces only when a client
  serves it as a correct answer.
- **`QUESTION` is required and is the matching surface** — Snowflake enforces the
  grammar while ignoring whether the SQL is true. Since a client matches against
  that text, it should read the way somebody would actually ask.
- Metrics need the explicit `SEMANTIC_VIEW(...)` form; selecting from the view by
  name works for dimensions but fails on a metric.

What the syntax cannot express also changed what is upstream: no window
functions, so the gap-and-island from step 8 became a column
(`availability_window_seq`) on `fct_listing_daily` rather than being restated in
a string literal that nothing validates. No ranking either, so the
revenue-concentration question has **no** metric — a metric quietly returning
something adjacent would be reported as the answer.

## 13. Skills for the two changes that keep recurring

Two changes in this project are predictable, multi-step, and easy to do half of.
Both got written up as Claude Code skills in [.claude/skills/](.claude/skills/),
so the procedure lives in the repo rather than in whoever did it last.

**[wake-up-ae](.claude/skills/wake-up-ae/SKILL.md)** is the work order behind the
two `severity: warn` seed tripwires from step 10. The trap it exists to prevent:
**regenerating a seed is what adds the flag column, and it is also what turns the
warning green.** Do just that step and you have a new column that no yml
documents, no mart decision stands behind, and no warning is left pointing at.
So the skill enforces one commit carrying all of it — regenerate the seed first
(the yml generator reads the seed, so running it earlier emits nothing), generate
the yml block rather than hand-writing the slugified flag name, then decide
whether the mart carries the flag.

That last decision needed a rule, because marts name their flags explicitly and a
new one otherwise stalls there forever. The rule is **5% of listings or hosts** —
measured, not assumed, and at 50 listings that means 3 clears and 2 does not. The
skill also insists the count is reported next to the percentage, since at this
base one listing moves the answer two points.

**[add-fact-or-dim-to-sv](.claude/skills/add-fact-or-dim-to-sv/SKILL.md)** covers
exposing a mart column to the semantic views. It exists because of the one
mistake in that layer that produces no error: **a numeric column from a
dimension-only table must go in `DIMENSIONS`, never `FACTS`.** A fact gets
aggregated across the join, so `sum(dim_listings.total_revenue)` grouped by date
in `sem_listing_daily` returns each listing multiplied by its 365 calendar rows —
and Snowflake returns that number without complaint. The skill carries the
measure-table-vs-dimension-only table from step 12 and checks the field's role
against it before anything gets written.

It also pulls the column description from `target/manifest.json` rather than the
`.yml`, since mart descriptions are `{{ doc() }}` references that only the
manifest resolves, and it stops outright if the mart column has no description —
inventing one here means the two are drifted from the moment they exist.

Both skills end the same way: verify against Snowflake, because `sqlfluff`
excludes the semantic-view folder and passing the linter proves nothing there,
and say plainly when credentials were unavailable rather than implying something
built.

---

## What was heavily AI-assisted

Claude Code used while developing this project and influenced heavily in these
areas:

**Project scaffolding** (step 4). The dbt skeleton, folder layout, and the first
pass at `profiles.yml` and `dbt_project.yml`. Fast and low-risk — it is boilerplate
with a known shape, and anything wrong in it fails immediately and loudly.

**Macro generation** (steps 4, 7, 10). The custom `table_insert_overwrite`
materialization, `generate_schema_name`, `mask_pii`, and the flag codegen family
were all written with AI. The *decisions* behind them were not AI's — that Time
Travel needs `insert overwrite`, that PII should be maskted, that the flag lists
belong in seeds rather than a `select distinct` or accepted values test.

The flag macros were also **refactored** with AI, which is where it earned the
most: two families had grown eight near-duplicate macros, the two copies had
drifted, and one of the two documented run orders could not work at all.

**Some of the bespoke tests** (steps 7, 8). The singular tests in
[dbt/tests/](dbt/tests/) — reconciling reservation nights against the daily grain,
asserting host attributes agree across a host's listings, checking the amenity
changelog stays outside the calendar window. Once the assumption to protect is
named, writing the SQL that fails when it breaks is mechanical. Naming the
assumption is the part that isn't, and that came from step 3.

**Business questions** (step 9). [BUSINESS_QUESTIONS.md](BUSINESS_QUESTIONS.md) is
the clearest case for using AI: the goal was *breadth* — what would a company like
this plausibly want to know — and breadth is where a model beats one person's
first ten ideas. Each question then had to be checked against the marts as built,
which is where several moved from "answerable" to "needs a new model" or into the
cannot-answer list.

**Documentation**, including this file written with AI from the actual code and the
actual query results, not from memory — which matters, because that is the failure
mode.

---

## Repo map

| Path | What is there |
|---|---|
| [BUSINESS_QUESTIONS.md](BUSINESS_QUESTIONS.md) | 26 questions, what they take, and what this source cannot answer |
| [dbt/models/staging/](dbt/models/staging/) | Cast, dedupe, rename — one model per source table, views |
| [dbt/models/intermediate/](dbt/models/intermediate/) | Flatten, join, reduce grain — tables |
| [dbt/models/marts/core_mart/](dbt/models/marts/core_mart/) | What analysts query |
| [dbt/models/marts/core_context_layer/](dbt/models/marts/core_context_layer/) | Semantic views + verified queries |
| [dbt/macros/infrastructure/](dbt/macros/infrastructure/) | Materialization, schema routing, PII masking |
| [dbt/macros/flags/](dbt/macros/flags/) | Generic codegen for the amenity and verification flag families |
| [dbt/tests/](dbt/tests/) | Singular tests asserting the assumptions the models rest on |
| [.claude/skills/](.claude/skills/) | `wake-up-ae` — act on the seed tripwires; `add-fact-or-dim-to-sv` — expose a mart column to the context layer |

## Running it

```bash
cp .env.example .env          # fill in Snowflake credentials + PII salt
set -a; source .env; set +a
cd dbt
dbt deps
dbt build                     # seeds first — dbt run/test alone need dbt seed to have run
```

The seeds are build artifacts that two models loop over, so `dbt build` is the
command that orders things correctly. A fresh clone running `dbt run && dbt test`
gets a missing-relation error.

---

## Next steps

**Orchestration tool** Use something like airflow or dbt Cloud to run these models
at an appropriate cadence. Assuming at least 1x day.

**Maximize the context layer, and test it for real.** The whole layer rests on a
premise that is currently untested: that a natural-language client reads the
`COMMENT` and `AI_SQL_GENERATION` text and picks the right metric. Making it
available to an agent — Cortex Analyst, Claude, or something else pointed at
Snowflake directly — and then asking it the 26 business questions is the only way
to learn which ones it gets wrong. It is also the only way to find out whether the
four-view split reads as intended or just as four places a question might belong.

**Combine or collapse some amenities.** 81 flags is more than the data supports as
distinct signals, and some are plainly close relatives (like has_tv and
has_tv_with_streaming).

**Similarity assessment of the metrics.** The same question one layer up: where do
two metric names describe one measure. Worth doing before the metric list grows,
since a natural-language client picking between two near-identical metrics is
picking arbitrarily.

**Extend `wake-up-ae` to cover semantic view additions.** It currently stops at the
mart decision and names `add-fact-or-dim-to-sv` as the next step. That handoff is a
human one, so a promoted flag can land in the mart and never reach the layer that
makes it askable in English.

**Extend `wake-up-ae` to run as part of agent rather than standalone skill.** It
currently requires someone log on and call it to open any necessary PRs. I would
want to automate that fully.

**Monitor the noise of the skills.** Both are tripwire-driven, and a tripwire that
fires often enough gets ignored. Worth knowing the real rate before treating either
as a control.

**Set up monitoring on the tables.** Something like Monte Carlo for the freshness
and volume anomalies a dbt test does not cover — though some of it may be built in
already, so that is the first thing to check. The layers do not want the same
treatment: the marts analysts query are worth monitoring in a way the staging views
are not, and deciding that per layer is the work.

**Get the other sources.** Hosts and reservations are both reconstructed today —
hosts by grouping the listings table, reservations by grouping the calendar's
booked nights. That is what makes cancellations, unconfirmed requests, booking lead
time, and host-blocked-vs-booked unanswerable, and none of them is a modeling
problem. A real host source would also settle whether hosts need SCD2 treatment,
which [assert_host_attributes_consistent.sql](dbt/tests/assert_host_attributes_consistent.sql)
currently only watches for.

**Get more history.** Get more calendar history (past, present or future) and
relevant amenities changelogs.
