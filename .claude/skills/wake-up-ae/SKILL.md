---
name: wake-up-ae
description: Act on the severity-warn tripwires that fire when the source grows a new amenity or host verification method — regenerate the seed, document the new flag, and decide whether the mart carries it. Use when dbt test reports warn_new_amenity_name or warn_new_verification_method, when asked to check for new amenities or verification methods, or when picking up the work order those warnings represent.
---

# wake-up-ae

Two `severity: warn` tests exist so the source growing a value announces itself
instead of silently widening a model. Neither is a defect report — both are work
orders, and this skill is the work.

| Test | On | Fires when |
|---|---|---|
| `warn_new_amenity_name` | `int_listing_amenities.amenity_name` | source has an amenity not in `seeds/known_amenity_names.csv` |
| `warn_new_verification_method` | `int_host_verifications.verification_method` | source has a method not in `seeds/known_verification_methods.csv` |

Both are `relationships` tests against a seed rather than `accepted_values` with
values inline, because the seed is also what the pivot models loop over to
generate their flag columns — and a Jinja loop cannot read an `accepted_values`
list out of yml.

## The one thing that must not go wrong

**Regenerating a seed is what adds the column, and it is also what turns the
warning green.** So a seed diff committed on its own leaves a column that no yml
documents and no mart decision stands behind, with the tripwire silenced and
nobody to notice. Every step below lands in **one commit**, or none of it does.

**Regenerate the seed FIRST.** `get_flag_values()` reads the seed and the pivot
models loop over its output, so nothing downstream exists until the seed carries
the value — and the yml generator in step 4 reads the seed too, so running it
before the seed regenerates emits nothing at all. Every family follows this order;
[generate_flag_seed.sql](dbt/macros/flags/generate_flag_seed.sql) documents it.

## 1. Detect

```bash
cd dbt && set -a && source ../.env && set +a
dbt build -s int_listing_amenities int_host_verifications
```

`dbt build` rather than `dbt test`: both tests depend on a seed, so `dbt test`
alone fails on a fresh clone with a missing-relation error rather than telling you
anything about amenities.

Read the warning body for the actual new values — the test returns the rows that
have no match in the seed. If both tests pass, stop and say so; there is no work
order and running the generators anyway would produce an empty diff at best.

If credentials are unavailable, stop here. Every step in this skill reads the
warehouse, so there is nothing to do offline — say that plainly rather than
guessing at what the source might have grown.

## 2. Branch, before touching anything

Everything from here writes to the working tree. Do this first:

```bash
git switch main && git pull
git switch -c "wake-up-ae-$(date +%F)"
```

Compute the date with `date +%F` rather than typing it — a hardcoded date in a
skill is wrong the day after it is written. That yields `wake-up-ae-2026-08-04`.

Off `main`, not off whatever branch happens to be checked out. The change is a
source-driven update with no dependency on unrelated in-flight work, and branching
off a feature branch would drag that work into the PR.

Three things to get right:

- **Check the tree is clean first** (`git status`). Uncommitted work belonging to
  somebody else must not ride along in this commit — if there is any, stop and ask
  rather than stashing it.
- **If the branch already exists**, today's run is a second pass. `git switch` to
  it rather than creating a duplicate, and say so — the amenity list may have
  moved twice in one day.
- **A pre-commit hook blocks committing to `main` directly**, so skipping this step
  does not fail quietly; it fails at the commit, after the generators have already
  rewritten the seeds. Branch first and that never comes up.

## 3. Regenerate the seed (this adds the column)

Amenities:

```bash
dbt --quiet run-operation generate_flag_seed --args '{family: amenity}' > seeds/known_amenity_names.csv
```

Verification methods:

```bash
dbt --quiet run-operation generate_flag_seed --args '{family: verification}' > seeds/known_verification_methods.csv
```

`--quiet` is not optional and goes **before** `run-operation`. dbt writes its own
log lines to stdout, so without it three junk rows land at the top of the CSV and
the seed fails to load.

Then read the diff. It should be exactly the new values, added in sort order. If
it is larger than that — reordered rows, changed spellings, removals you did not
expect — stop and report, because something other than a new value has moved.

Two things the diff protects, both worth checking by eye:

- **Amenity names keep their Unicode apostrophes** (U+2019, in `Children’s books
  and toys` and `Pack ’n Play/travel crib`). A straightened apostrophe is a false
  positive on the join key forever.
- **A value only needs CSV quoting** if it contains a comma, a double quote or a
  newline. The macro handles this; you are checking it did.

## 4. Document the new flag

```bash
dbt run-operation generate_flag_yml --args '{family: amenity}'       # -> int_listing_daily.yml
dbt run-operation generate_flag_yml --args '{family: verification}'  # -> int_hosts.yml
```

Each prints a yml block for flags the seed produces that the model's yml does not
declare, plus a **stale** report naming declared flags the seed no longer produces.
Paste the block into that model's `columns:` block. Do not hand-write the flag
name: it is `flag_name()` slugification, and guessing at how the punctuation
collapses is how a name gets committed wrong.

Note which model each targets — the flags live on the pivot models, not the bridges
the tests fire on:

| New value in | Flag column lands on | Document in |
|---|---|---|
| `int_listing_amenities` | `int_listing_daily` | `int_listing_daily.yml` |
| `int_host_verifications` | `int_hosts` | `int_hosts.yml` |

The generated description is deliberately thin ("Whether the listing offers X").
That is fine for a flag no mart carries. If step 5 promotes it, write a real
description — and if it earns a curated one, it belongs in
[models/docs.md](dbt/models/docs.md) as a `{% docs %}` block so the mart and the
intermediate model share one text rather than two that drift.

If the stale report names anything, raise it separately. A removed value is
harmless now — the flag survives and goes universally false, which stays
queryable — but it is a real signal about the source and should not ride along
inside an "added a new amenity" commit.

## 5. Decide whether the mart carries it — the 5% rule

Marts name their flags **explicitly** rather than passing them through, so a new
flag stops at the intermediate layer until somebody decides otherwise. That
friction is the design: letting all 81 through would let the source change a
mart's shape with no decision behind it.

The threshold for promoting one:

> **Carry the flag in the mart when more than 5% of listings (or hosts) have it
> true.** Below that, it stays in the intermediate layer and is reachable through
> `int_listing_amenities` / `int_host_verifications`.

Measure it, do not assume:

```sql
-- amenities: share of the 50 listings with the new flag true
select
    count_if(has_<flag>) as with_flag,
    count(*) as listings,
    round(100 * count_if(has_<flag>) / count(*), 1) as pct
from <your_schema>.int_listing_daily
where calendar_date = (select max(calendar_date) from <your_schema>.int_listing_daily)
```

Filter to one date. `int_listing_daily` is listing × date, so counting over the
whole table measures listing-nights and not listings — 5% of 17,885 rows is not
5% of 50 listings. For verification methods the grain is already one row per host
in `int_hosts`, so no filter is needed.

At 50 listings the threshold is 2.5, so **3 listings clears it and 2 does not**.
Say the count alongside the percentage in your report — "4 of 50, 8%" is
reviewable in a way that "8%" is not, and at this base a single listing moves the
answer by 2 points.

**If it clears, promote it in the same commit:**

| Layer | Amenity flag | Verification flag |
|---|---|---|
| Fact | `fct_listing_daily.sql` (carries 3 of 81) | — |
| Dimension | `dim_listings.sql`, inside the `boolor_agg` block | `dim_hosts.sql`, in the explicit flag list |
| Docs | the mart's `.yml` | the mart's `.yml` |

For `dim_listings` the flag goes in the `boolor_agg(...)` group — amenity values
are constant across a listing's daily rows, so the aggregate collapses back to
listing grain without a second join to the bridge.

Then ask whether the **semantic views** should expose it. That is a separate
decision with its own trap (a numeric column from a dimension-only join must not
become a `FACT`), and there is a skill for it: `add-fact-or-dim-to-sv`. Do not
inline that work here.

**If it does not clear, say so and stop.** "1 of 50 listings, below the 5% bar, so
it stays in `int_listing_daily`" is a complete and correct outcome — the flag
still exists and is still queryable.

## 6. Verify, then open the PR

```bash
dbt build -s known_amenity_names known_verification_methods \
    int_listing_amenities int_host_verifications int_listing_daily int_hosts \
    dim_listings dim_hosts fct_listing_daily
```

The tests that warned must now pass, and nothing else may have broken. Then:

- **One commit** carrying the seed, the yml, and any mart change together, on the
  `wake-up-ae-<date>` branch from step 2.
- `pre-commit` runs `sqlfluff` on staged model SQL; let it run rather than
  bypassing it.
- The PR body should state, per new value: the value, the generated flag name, the
  share (count and percent), the promote-or-not decision and its reason, and
  whether the semantic views were left alone.

Do not open the PR without confirming — say what the commit contains and ask.

## Reporting

Lead with whether anything actually fired. If both tests passed, that is the whole
report. If something fired, give the count and share for each new value and the
promotion decision, and name anything you deliberately did not do — the semantic
views, a stale flag, the out-of-date ordering comment. A skipped step that goes
unmentioned reads as a step that was not needed.
