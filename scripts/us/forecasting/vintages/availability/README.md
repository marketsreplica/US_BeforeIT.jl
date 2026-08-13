# Retrospective release-availability boundary

`USReleaseAvailability.jl` is a standalone, fail-closed temporal policy for
research reconstruction. It answers one narrow question: based on an
officially evidenced *actual* publication instant, date, or date range, is a
candidate origin late enough to pass a conservative temporal gate?

It does not admit an origin, mutate `current_inventory.toml`, alter the
historical backfill plan, authorize empirical forecast execution, or authorize
production use. Every successful result is explicitly
`TEMPORAL_GATE_SATISFIED_NO_ADMISSION`; all four governance flags remain
false.

The sealed policy is
`release_availability_policy.toml`. Its canonical SHA256 is:

```text
6af185c5fa8be4404a064294a0053eec093ca1a59cbc29f1a0566ada3364de11
```

The module pins that digest in code as well as checking the TOML's stored
digest. Rehashing a relaxed policy therefore cannot make it acceptable.

## Accepted and rejected time claims

The only accepted assertion bases are:

- `actual_public_timestamp`: an evidenced actual-public UTC timestamp at
  exact-second precision;
- `official_actual_release_date`: an official actual release date in a named
  source timezone; and
- `official_actual_release_date_range`: an inclusive official actual release
  date range in a named source timezone.

Schedule-only or planned dates, retrieval timestamps, unexplained vintage
dates, route-level descriptions, unknown timezones, and every unrecognized
basis are rejected. A schedule can be operationally useful without proving
when specific bytes became public. For example, the [BLS release
calendar](https://www.bls.gov/schedule/2026/) publishes scheduled Eastern
times, while an actual [BEA release
notice](https://www.bea.gov/news/2026/us-international-trade-goods-and-services-january-2026)
records the release's embargo time. The validator requires the latter class of
actual-event evidence; it never upgrades the former.

The distinction also matters for vintage systems. The [FRED vintage-date API
documentation](https://fred.stlouisfed.org/docs/api/fred/series_vintagedates.html)
defines vintage dates as dates on which data values were revised or newly
released, not as authenticated first-publication bytes or exact intraday
availability. The [Philadelphia Fed Real-Time Data Set for
Macroeconomists](https://www.philadelphiafed.org/surveys-and-data/real-time-data-research/real-time-data-set-for-macroeconomists)
and Croushore and Stark's [real-time-data
research](https://doi.org/10.1016/S0304-4076(01)00072-0) motivate preserving
historical information sets, but their existence does not by itself prove an
event's exact publication time or raw first state.

## Deterministic date bounds

An actual local release date identifies a set of possible publication
instants, not a fabricated midnight timestamp. For an inclusive local range
from `D_start` through `D_end`, with offsets expressed as minutes east of UTC,
the validator derives:

```text
lower_utc     = local_midnight(D_start)   - sealed_start_utc_offset
upper_utc     = local_midnight(D_end + 1) - sealed_end_utc_offset
safe_not_before_utc = upper_utc
```

The interval is half-open: `[lower_utc, upper_utc)`. Every origin before the
exclusive upper bound fails, including every origin on the asserted
source-local release day. An origin exactly at or after the upper bound may
pass only the temporal gate. The upper bound is a conservative admission
threshold; it is not presented as the publication instant.

The [IMF SDDS Guide](https://dsbb.imf.org/content/pdfs/sddsguide.pdf)
recognizes release-calendar dates, date ranges, and "not later than" dates
while encouraging precise release times. The [BIS release
calendar](https://data.bis.org/release-calendar?view=list) similarly uses
no-later-than dates. This policy operationalizes imprecise *actual* dates as
bounded uncertainty and chooses the end of that uncertainty for its safe
not-before rule.

Both boundary offsets are mandatory and are checked against the checked-in,
sealed local-midnight semantics table—not merely against a zone's set of
possible offsets. The source timezone must be in the policy's exact allowlist,
and the supplied start offset must match local midnight on `D_start`, while
the supplied end offset must match local midnight on `D_end + 1`. Thus a
fictitious New York January `-05:00` → `-04:00` daylight-saving transition is
rejected even though both offsets are otherwise valid for that zone.

The artifact is
`timezone_semantics_iana_tzdb_2026c.toml`, whose canonical SHA-256 is:

```text
8ed940e6deb1a1aa0922369eb8b0ad327ecf52def3c37c7317f81b87afe7a174
```

It covers source-local midnights from 1997-01-01 through the 2036-01-01
boundary sentinel, permitting asserted dates through 2035-12-31. This matches
the plan's 1997 warm-up and 2007-onward evaluation design while leaving a
reviewable forward buffer; a later date requires a new, separately sealed
artifact and policy revision. It includes only `UTC`, `America/New_York`, and
`America/Chicago`.

The table was generated from the IANA Time Zone Database's primary
[`tzdata2026c` source archive](https://data.iana.org/time-zones/releases/tzdata2026c.tar.gz),
SHA-256
`e4a178a4477f3d0ea77cc31828ff72aa38feff8d61aa13e7e99e142e9d902be4`.
IANA describes TZDB as machine-readable history of local civil time, UTC
offsets, and daylight-saving rules on its [Time Zone Database page](https://www.iana.org/time-zones).
For reproducibility, `generate_timezone_semantics.py` verifies that archive,
compiles `etcetera` and `northamerica` with `zic`, and scans the three zones at
each source-local midnight. The runtime validator has no TZDB or host-timezone
dependency. Regeneration is a review aid; it does not authorize replacing the
checked-in table or resealing policy.

The generator uses an explicit POSIX- and Windows-path traversal-, link-, and
special-member-rejecting tar extraction path that works without Python's
version-specific extraction-filter API. It also refuses to write output unless
the generated canonical digest is exactly the module-sealed digest above. The
`zic` executable remains an input to the build, but a different toolchain
cannot silently produce a different accepted table. Independent qualification
reproduced byte-identical output with both the system `zic 2022g` and `zic`
built from `tzcode2026c`.

Date evidence must use the exact semantic-artifact locator and hash from the
policy in `timezone_rules_evidence_locator` and
`timezone_rules_evidence_sha256`. A nonzero, arbitrary hash or a different
TZDB artifact is rejected. The validator proves only the pinned table's
arithmetic and identity; it does not independently attest the source archive
or an upstream release's actual-publication claim.

This avoids a runtime timezone dependency while preserving daylight-saving
days:

| New York local date | Start/end offsets | UTC duration |
| --- | --- | ---: |
| Normal day | `-05:00` / `-05:00` | 24 hours |
| 2026-03-08 spring transition | `-05:00` / `-04:00` | 23 hours |
| 2026-11-01 fall transition | `-04:00` / `-05:00` | 25 hours |

For a multi-day range, the same boundary rule applies once to the inclusive
range. A two-day range crossing spring or fall is therefore 47 or 49 hours,
respectively.

## Evidence boundary

Every evidence object has strict, assertion-specific topology and its own
canonical content SHA256. It must bind:

- the availability claim and its nonzero SHA256;
- exact release-byte evidence and its nonzero SHA256;
- separate vintage evidence and its different locator and nonzero SHA256; and
- for date assertions, separate timezone-rule evidence and its nonzero
  SHA256.

Lowercase 64-hex digests are required; missing, malformed, uppercase, or
all-zero placeholders fail. Availability, release-byte, and vintage locators
and hashes must be pairwise distinct; an artifact serving two evidentiary
roles requires a future explicit policy revision rather than a silent alias.
The evidence content digest detects drift but is not a signature. Upstream
review must still establish that the referenced official material says what
the assertion claims. [RFC
3161](https://www.rfc-editor.org/info/rfc3161/) describes independent
timestamp-token evidence, and [RFC
8493](https://www.rfc-editor.org/info/rfc8493/) describes hash-manifest
packaging; those are useful upstream evidence patterns, not authenticity
claims made by this validator.

The mandatory scope is `retrospective_research`. These fields must be false in
both evidence and every result:

```text
empirical_forecast_execution_allowed
production_scoring_allowed
origin_admission_authorized
inventory_mutation_authorized
```

No passing result is sufficient for origin readiness. It remains subject to
the separate source-release registry, completeness, byte authentication,
vintage review, governance, and admission controls.

Run the hermetic focused suite with:

```sh
julia --startup-file=no --check-bounds=yes --project=scripts/us \
  scripts/us/forecasting/vintages/availability/test_release_availability.jl
```
