{#
    Shared column descriptions.

    Every block here describes a column that appears in more than one model and
    genuinely means the same thing in each — so the wording lives once and the
    models reference it with `{{ doc('...') }}`. Where a model needs to add
    something specific (a primary-key claim, a note about which test guards a
    premise), it appends a sentence after the doc reference rather than
    restating the shared part.

    These describe columns, not the rows currently in them. Row counts,
    distinct-value counts, ID values, and date ranges are deliberately absent:
    a description that quotes a figure goes wrong silently the next time the
    source loads, and nothing fails. Where a distribution or a boundary matters
    to how the column should be used, the wording states the shape and names the
    test that holds it — a test reports the current number when it fires, which
    is the only place a number stays true.

    Columns that only look shared are deliberately absent. `price` is the
    clearest case: on the calendar it is the nightly rate for one date, while on
    stg_listings it is the host's advertised rate (surfaced as `list_price` in
    dim_listings). Those are different measures that happen to share a name, so
    each is described where it is defined.

    Doc blocks are global to the project, so these are usable from staging and
    intermediate models too despite living under marts/.
#}


{#-- Identifiers ------------------------------------------------------------#}

{% docs listing_id %}
Identifier of the rental listing. Joins every model in the project together.

The calendar and changelog cover more listings than the raw listings table does,
so models that carry descriptive attributes leave them NULL for the missing ones
rather than dropping the rows. See is_orphan_listing.
{% enddocs %}

{% docs calendar_id %}
Surrogate key over (listing_id, calendar_date), generated in stg_calendar and
carried through unchanged. Unique at the daily grain.
{% enddocs %}

{% docs reservation_id %}
Identifier of the booking occupying this date, NULL when the date is available.

The raw calendar stores the literal string `'NULL'` for unbooked dates;
stg_calendar converts those to true NULLs.
{% enddocs %}

{% docs host_id %}
Identifier of the host who owns the listing. NULL where the listing is absent
from the raw listings table.
{% enddocs %}

{% docs host_name_masked %}
Salted SHA-256 of the host's name, truncated to 16 hex characters. **The
plaintext name is PII and does not exist anywhere in the dbt layers** — it is
masked in stg_listings, the first model to touch the source.

Usable as a grouping key (rows sharing a hash share a name) but not reversible:
the salt is what prevents recovering a first name by hashing a name list. Use
host_id for joins — it identifies a host directly and is stable across salt
rotations, which change every hash here.

Note that host names are not unique: distinct hosts can share a name and
therefore share a hash. Never treat this as a host identifier — nothing tests
this column for uniqueness, because it is not expected to hold.

See macros/mask_pii.sql. The plaintext still exists in RAW_DATA, which dbt
cannot reach — that needs a Snowflake masking policy.
{% enddocs %}


{#-- Hosts ------------------------------------------------------------------#}

{% docs host_since %}
Date the host joined the platform.

Tightly clustered in this data — nearly every host joined in the same two-year
window, so tenure has little variance to explain performance with. Check the
spread before using it as an explanatory variable.
{% enddocs %}

{% docs host_location %}
Self-reported host location, free text and not normalized.

Not comparable to `neighborhood`, which describes where the listing is — a host
can live anywhere relative to the property they rent out.
{% enddocs %}

{% docs host_verifications %}
Raw JSON array string of the verification methods the host has completed, e.g.
`'["email", "phone", "reviews", "kba"]'`.

Kept only in staging. Downstream, use int_host_verifications (host × method) or
the generated `is_verified_*` flags on int_hosts — do not string-match this
column. `contains(host_verifications, 'government_id')` also matches
`offline_government_id`, and `'email'` also matches `'work_email'`.

Both of those return the correct answer on today's data only by luck: each
narrower method happens to be a strict subset of the broader one. Nothing
enforces that, so the substring shortcut is a latent bug rather than a live one —
which is a worse thing to leave in a query, because it will pass review.
{% enddocs %}

{% docs verification_method %}
One verification method a host has completed, unflattened from the raw array.

The set of methods in use is enumerated in `seeds/known_verification_methods.csv`,
which this column is relationships-tested against at `severity: warn` — that
warning (`warn_new_verification_method`) is what announces a method the project
has not seen before.

Note that `government_id` and `offline_government_id` are separate values, as are
`email` and `work_email` — so substring matching on the raw array conflates each
pair. It gives the right answer on this snapshot only because the narrower method
is a strict subset of the broader one in both cases; nothing guarantees that.
{% enddocs %}

{% docs verification_count %}
Number of distinct verification methods the host has completed.

The floor on this data comes from every host happening to hold the same couple of
baseline methods, not from a designed minimum — if that changes,
`is_verified_email` and `is_verified_phone` are what make it visible.

NULL, not 0, for a host with no rows in int_host_verifications — an empty or
unparseable array. The left join keeps that distinguishable from a host verified
by nothing.
{% enddocs %}

{% docs verification_list %}
Array of the host's verification methods.

Redundant with the generated `is_verified_*` flags for filtering. Kept because it
survives the source adding a new method without a schema change, and because it
reads better than a row of booleans when you just want to see what a host has.
{% enddocs %}

{% docs is_verified_email %}
Whether the host has a verified email address. Generated flag.

Universally true on this data, so it has no analytical use — it is kept as a
tripwire. A universally-true flag is the only thing that makes its own violation
visible: the day a host lands without a verified email this goes false and is
queryable, which is impossible if the column was dropped for carrying no signal.

Filter on this expecting variance and you may get every host back.
{% enddocs %}

{% docs is_verified_phone %}
Whether the host has a verified phone number. Generated flag.

Universally true on this data. Kept as a tripwire for the same reason as
is_verified_email — see that column's description.
{% enddocs %}

{% docs is_verified_government_id %}
Whether the host completed government ID verification. Generated flag.

Distinct from is_verified_offline_government_id, a separate method. On this data
every offline host also carries this flag, so the two are nested rather than
disjoint — do not add them together expecting a total. The source treats them as
different processes, so that nesting is a property of the snapshot, not a rule.
{% enddocs %}

{% docs is_verified_offline_government_id %}
Whether the host completed government ID verification through the offline
channel. Generated flag.

Every host carrying this also carries is_verified_government_id, so this is a
subset of that flag on this data. Exists separately because the source treats it
as its own method, and because substring-matching `government_id` on the raw
array cannot tell them apart — a shortcut that works only while the nesting
holds.
{% enddocs %}

{% docs listing_count %}
Number of listings the host holds.

Most hosts hold exactly one, with a thin tail above that. Compare hosts on
revenue_per_listing rather than total_revenue, which scales with this by
construction.
{% enddocs %}

{% docs host_total_revenue %}
Total booked revenue across all the host's listings over the calendar year.

Zero, not NULL, for a host whose listings were never booked — the honest measure
for a host who earned nothing.
{% enddocs %}

{% docs host_occupancy_rate %}
Booked nights divided by calendar days, summed across the host's listings before
dividing.

Portfolio-weighted on purpose: averaging per-listing rates would let a listing
with a short calendar window count as much as one covering the full year.
{% enddocs %}

{% docs host_avg_nights_per_stay %}
Average length of stay across the host's reservations, weighted by reservation
count.

Excludes reservations censored at the snapshot edges, whose lengths are truncated
— see is_reservation_censored. NULL where every reservation of the host's is
censored, or where the host has none.
{% enddocs %}


{#-- Dates and the daily grain ---------------------------------------------#}

{% docs calendar_date %}
Date the row describes. The calendar is a fixed one-year snapshot, not a rolling
window — see as_of_date for the reference point every age and tenure measure in
the marts is anchored to.
{% enddocs %}

{% docs is_available %}
True when the listing is bookable on this date, false when it is already
reserved. Revenue accrues only on unavailable (booked) nights.
{% enddocs %}

{% docs as_of_date %}
Last date in the calendar snapshot — the reference point for every age or tenure
measure in the marts. Constant across every row.

Carried as a column rather than left implicit so a figure measured against it can
be reproduced later, and so nobody assumes `current_date` was used. It was not,
deliberately: the data is a fixed year, so `current_date` would give a different
answer on every run.

Supplied by the `$calendar_as_of_date` session variable that each model's
pre-hook sets from int_listing_daily, not by a join — see the model headers. Both
dim_listings and dim_hosts set the same variable from the same source, so the two
dimensions anchor to the same date by construction.
{% enddocs %}


{#-- Nightly economics ------------------------------------------------------#}

{% docs nightly_price %}
Nightly price in dollars for this specific date, from the calendar. Cast from a
plain numeric string in the source.

Distinct from the host's advertised rate on the listing record, which varies by
date where this does not follow it.
{% enddocs %}

{% docs revenue %}
Nightly price on booked nights, NULL on available nights.

NULL rather than zero is deliberate: `sum(revenue)` then gives booked revenue
with no date filtering, and `avg(revenue)` gives the average rate actually
achieved rather than being dragged down by vacant nights.
{% enddocs %}

{% docs minimum_nights %}
Shortest stay the host will accept, as set on the listing's calendar.
{% enddocs %}

{% docs maximum_nights %}
Longest stay the host will accept, as set on the listing's calendar. Caps how
much of an availability window is actually bookable in one stay.
{% enddocs %}

{% docs is_window_start %}
True on the first available night of a contiguous run of available nights, false
everywhere else — including on every booked night.

The building block of the availability-window questions (#3, longest possible
stay; #26, revenue lost to unbookable windows), which need to group consecutive
available dates into runs. Reading a boolean column is what those queries do
instead of writing the gap-and-island window function themselves.

Computed with `lag(is_available)`, coalesced to false so the first row of each
listing counts as a start when it is available. `sum()` of this column is the
number of availability windows a listing has.
{% enddocs %}

{% docs availability_window_seq %}
Sequence number identifying which availability window a date belongs to, counting
from 1 within each listing. Constant across every night of one window, so
`group by listing_id, availability_window_seq` gives one group per contiguous run
of available nights.

**MEANINGFUL ONLY WHERE `is_available` IS TRUE.** It is a running count of
windows *started so far*, so a booked night carries the number of the window that
ended before it — which is why every consumer must filter `is_available` before
grouping on it. Without that filter each group also collects the booked nights
that follow its window, and `count(*)` returns a window longer than the run
actually is.

Two rules this column does NOT encode, both of which produce a plausible wrong
answer and neither of which lives here — see
`macros/verified_queries/verified_queries_q03.sql`:

1. **Window length is `count(*)`, not `datediff(min, max)`**, which is one lower.
   Every available date is a bookable night, so both endpoints count.
2. **Longest bookable stay is `least(window_length, maximum_nights)`.** Both
   constraints bind in this data — the window usually, the owner's cap on a
   minority of windows — so neither column alone answers "longest possible
   stay." `tests/assert_stay_cap_binds.sql` guards that premise, and fails if
   the cap stops binding anywhere.

Depends on the calendar being gap-free per listing, with no duplicate dates. A
missing date would merge the runs on either side of it into one window, where the
older `date - row_number()` form would have split them. The `calendar_id`
uniqueness test plus `calendar_date` being not-null is what keeps that assumption
honest.
{% enddocs %}


{#-- Reservations -----------------------------------------------------------#}

{% docs reservation_key %}
Surrogate key over (listing_id, reservation_id). Unique per reservation.

Needed because reservation_id is **not** unique on its own — the same id can
appear on two different listings, covering two separate stays. Grouping on
reservation_id alone would merge those into one impossible reservation spanning
two properties, so join and count on this column. `unique` on this column is
what asserts the per-reservation grain.
{% enddocs %}

{% docs check_in_date %}
First night of the reservation — the earliest occupied date carrying this
reservation_id.
{% enddocs %}

{% docs last_night_date %}
Last night the guest sleeps in the unit.

Kept alongside check_out_date because "nights sold" and "the date the unit frees
up" are different questions — housekeeping cares about the latter.
{% enddocs %}

{% docs check_out_date %}
Morning the guest departs — `last_night_date + 1`, following the industry
convention that a checkout date is not a night sold.

`nights` is therefore `check_out_date - check_in_date`, and summing `nights`
across reservations reconciles to the count of booked nights in the calendar.
{% enddocs %}

{% docs nights %}
Number of nights the reservation occupies, counted as occupied calendar rows.

A floor rather than an exact length where the reservation touches either edge of
the calendar snapshot — see is_left_censored / is_right_censored.
{% enddocs %}

{% docs reservation_revenue %}
Total revenue for the reservation: the sum of nightly prices across its booked
nights.

Gross of any fee or commission — the raw data carries no cost, cleaning fee, or
platform take, so this is not margin.
{% enddocs %}

{% docs is_contiguous %}
True when the reservation's nights are consecutive, so collapsing them to a
single check-in/check-out span is honest.

False would mean one reservation_id covers two separate stays, making
check_out_date overstate the first. Asserted true, so a load that breaks the
assumption fails the build rather than quietly inflating length of stay.
{% enddocs %}

{% docs is_reservation_censored %}
True when the reservation touches either edge of the calendar snapshot, meaning
nights outside the loaded year are not counted.

`nights` is then a floor on the true stay length, not the stay length. Exclude
censored reservations before reporting average length of stay, or the average is
biased downward — long stays are the ones most likely to cross an edge.
{% enddocs %}


{#--
    Availability windows had five doc blocks here — window_start_date,
    window_end_date, window_length_nights, longest_possible_stay_nights, and
    availability_window_id. All five went when the two windows models were
    collapsed into the query that needed them; no model declares those columns
    now, and a doc block with no consumer is a maintenance trap.

    The two facts worth keeping are in the header of
    macros/verified_queries/verified_queries_q03.sql, where the person
    re-deriving windows will actually see them: window length is count(*) and
    not datediff (off by one), and the longest bookable stay is
    least(window, maximum_nights) because both constraints bind. See also
    tests/assert_stay_cap_binds.sql and "Collapsed models" in README.md.
--#}

{#-- Listing attributes ----------------------------------------------------#}

{% docs listing_name %}
Host-authored title of the listing. NULL where the listing is absent from the
raw listings table.
{% enddocs %}

{% docs neighborhood %}
Neighborhood the listing sits in. NULL where the listing is absent from the raw
listings table.
{% enddocs %}

{% docs property_type %}
Kind of property, e.g. "Entire rental unit" or "Private room in home". NULL
where the listing is absent from the raw listings table.
{% enddocs %}

{% docs room_type %}
What the guest books: "Entire home/apt" or "Private room". NULL where the
listing is absent from the raw listings table.
{% enddocs %}

{% docs accommodates %}
Maximum guests the listing sleeps. NULL where the listing is absent from the raw
listings table.
{% enddocs %}

{% docs bedrooms %}
Number of bedrooms. Never 0 in this data, but **NULL on a meaningful share of
listings** where the host left it unset — and NULL where the listing is absent
from the raw listings table.

Price-per-bedroom is therefore NULL for those rather than wrong. No div0 needed
while 0 never occurs, but expect the denominator to be missing often enough to
matter. The gaps fall on entire homes, so any figure cut that way rests on fewer
listings than the segment's total.
{% enddocs %}

{% docs beds %}
Number of beds, which may exceed `bedrooms` for multi-bed rooms. Never NULL in
the current data, but **0 on some listings** — and NULL where the listing is
absent from the raw listings table.

The opposite failure mode to `bedrooms`: always populated, but dividing by it
needs div0 or nullif, otherwise price-per-bed errors out on the zeros. A listing
can record bedrooms with 0 beds, so the two columns disagree rather than one being
a clean fallback for the other.

Both gaps fall on entire homes; private rooms have complete data for both columns
in this snapshot.
{% enddocs %}


{#-- Amenities -------------------------------------------------------------#}

{% docs amenities_json %}
Raw amenity set as a JSON array string, e.g. `["Wifi", "Kitchen"]`. Flattened
by int_listing_amenities, then pivoted into boolean flags by
int_listing_daily.
{% enddocs %}

{% docs amenity_count %}
Number of distinct amenities the listing currently offers, from the changelog's
most recent event.
{% enddocs %}

{% docs has_air_conditioning %}
Whether the listing offers air conditioning.

Matched exactly against the flattened amenity name rather than by substring —
`'%air%'` would also match "Hair dryer".
{% enddocs %}

{% docs has_lockbox %}
Whether the listing offers a lockbox. Exact match on the "Lockbox" amenity.
{% enddocs %}

{% docs has_first_aid_kit %}
Whether the listing offers a first aid kit. Exact match on the "First aid kit"
amenity.
{% enddocs %}

{% docs has_wifi %}
Whether the listing offers wifi. Exact match on the "Wifi" amenity.
{% enddocs %}

{% docs has_heating %}
Whether the listing offers heating. Exact match on the "Heating" amenity.
{% enddocs %}

{% docs has_kitchen %}
Whether the listing offers a kitchen. Exact match on the "Kitchen" amenity.
{% enddocs %}


{#-- Data-quality flags ----------------------------------------------------#}

{% docs is_orphan_listing %}
True where the listing appears in the calendar and changelog but not in the raw
listings table, so every descriptive column is NULL for it.

Computed once, in `int_listings`, and read by every model that carries it. Joins
are left joins throughout so these rows survive, and they carry real booked
revenue — `tests/assert_orphan_listing_count.sql` pins how many orphans there are
and warns when that changes.

Consumers should include or exclude them explicitly rather than by accident:
excluding them moves revenue-share figures by enough to notice.
{% enddocs %}
