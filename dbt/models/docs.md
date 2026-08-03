{#
    Shared column descriptions.

    Every block here describes a column that appears in more than one model and
    genuinely means the same thing in each — so the wording lives once and the
    models reference it with `{{ doc('...') }}`. Where a model needs to add
    something specific (a primary-key claim, an orphan-row count), it appends a
    sentence after the doc reference rather than restating the shared part.

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

50 distinct listings appear across the calendar and changelog; one of them
(276450) is missing from the raw listings table, so models that carry
descriptive attributes leave them NULL for that listing rather than dropping
the rows.
{% enddocs %}

{% docs calendar_id %}
Surrogate key over (listing_id, calendar_date), generated in stg_calendar and
carried through unchanged. Unique at the daily grain.
{% enddocs %}

{% docs availability_window_id %}
Surrogate key over (listing_id, island_group), where island_group is the
gap-and-island constant that groups consecutive available dates. Unique per
availability window.
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


{#-- Dates and the daily grain ---------------------------------------------#}

{% docs calendar_date %}
Date the row describes. The calendar spans 2021-07-12 to 2022-07-11 — a fixed
one-year snapshot, not a rolling window.
{% enddocs %}

{% docs is_available %}
True when the listing is bookable on this date, false when it is already
reserved. Revenue accrues only on unavailable (booked) nights.
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


{#-- Availability windows ---------------------------------------------------#}

{% docs window_start_date %}
First available date in the contiguous window.
{% enddocs %}

{% docs window_end_date %}
Last available date in the contiguous window.
{% enddocs %}

{% docs window_length_nights %}
Count of available dates in the window.

Counted as rows, not `datediff(window_start_date, window_end_date)`, which
would be one lower — every available calendar date counts as a bookable night.
Listing 1303261's 2022-02-03 to 2022-07-11 window is 159 nights, not 158.
{% enddocs %}

{% docs longest_possible_stay_nights %}
`least(window_length_nights, maximum_nights)` — the longest stay actually
bookable in this window.

Both constraints bind in real data, so neither column alone answers the
question: listing 1303261 has a 159-night window under a 180-night cap (window
binds), while listing 743211 has a 206-night window capped to 90 (cap binds).
The cap binds in 8 of 204 windows.
{% enddocs %}


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


{#-- Amenities -------------------------------------------------------------#}

{% docs amenities_json %}
Raw amenity set as a JSON array string, e.g. `["Wifi", "Kitchen"]`. Flattened
and pivoted into boolean flags by int_amenities_current.
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
listings table — listing 276450, covering 365 calendar rows and $2,200 of booked
revenue.

Joins are left joins throughout so these rows survive. Consumers should include
or exclude them explicitly: excluding them shifts the July 2022 no-AC revenue
share from 21.2% to 22.1%.
{% enddocs %}
