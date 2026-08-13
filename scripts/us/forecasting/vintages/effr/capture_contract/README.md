# Hermetic EFFR one-effective-date capture contract

This directory defines a fail-closed, offline receipt boundary for one
effective date of the Federal Reserve Bank of New York effective federal
funds rate (EFFR). It is a schema and pairing contract, not a downloader.
It contains no network client, live request, external response bytes,
filesystem receipt/raw-byte loader, source-inventory mutation, origin,
forecast score, promotion path, or production-readiness claim.

The contract follows the information-set distinction documented in the
project work log:

- the New York Fed normally publishes the prior business day's EFFR around
  09:00 ET and may publish a qualifying same-day revision around 14:30 ET;
- extraordinary later corrections remain possible;
- the current Markets Data API is current/revised evidence and does not
  establish the response bytes or exact state visible at a historical
  intraday cutoff;
- ALFRED can represent a date-level vintage after a separate governance
  decision, but that is not proof of the 09:00 intraday state; and
- the post-March-2016 FR 2420 volume-weighted-median concept is not silently
  spliced to the earlier broker-based mean.

Primary references are the
[New York Fed EFFR description](https://www.newyorkfed.org/markets/reference-rates/effr),
[reference-rate methodology and revision policy](https://www.newyorkfed.org/markets/reference-rates/additional-information-about-reference-rates),
[Markets Data API documentation](https://markets.newyorkfed.org/static/docs/markets-api.html),
[New York Fed terms](https://www.newyorkfed.org/privacy/termsofuse), and the
[Board's March 2016 H.15 notice](https://www.federalreserve.gov/Releases/H15/20160307/default.htm).
The real-time information-set boundary follows Croushore and Stark,
[*A Real-Time Data Set for Macroeconomists*](https://doi.org/10.1016/S0304-4076(01)00072-0),
and Koenig, Dolmas, and Piger,
[*The Use and Abuse of Real-Time Data in Economic Forecasting*](https://doi.org/10.1162/003465303322369768).

## What a receipt binds

Each in-memory receipt uses exact, alias-free keys and binds:

- source authority, route, evidence track, EFFR series, and the clean
  post-2016 concept;
- the one-date endpoint, sorted canonical query, and exact requested/final
  URL;
- `rate` or `volume` report type, effective and publication dates, New York
  UTC offset, closed state class, raw revision token, and an exact pair key;
- request start, response-header time, response completion, and a
  conservative availability upper bound equal to completed receipt of the
  response body;
- status, final host, redirect count/chain, complete-header flag, content
  type/encoding/length;
- response SHA-256, captured OpenAPI SHA-256, content-addressed durable
  storage locator, and durable-storage receipt SHA-256;
- raw rate, percentiles, target bounds, volume, footnote, revision, and
  current-state fields;
- a predecessor/supersession pointer that adds a new state without
  overwriting the old state; and
- the exact terms snapshot/review, attribution, disclaimer, redistribution
  scope, and public-endpoint secret reference.

The request is pinned to:

```text
https://markets.newyorkfed.org/api/rates/all/search.json
?endDate=YYYY-MM-DD&startDate=YYYY-MM-DD&type=rate|volume
```

The module accepts no URL aliases, query reorderings, redirects, alternate
hosts, schema aliases, generic fallback enum values, or implicit coercions.
In particular, `Bool` is rejected wherever a number is required, and
nonfinite numeric values are rejected.

## Publication-time boundary

The publication clock is a validated field, not a descriptive label.
Effective and publication dates must be weekdays, the effective date must
be on or after 2016-03-01, and the declared New York offset must equal the
post-2007 U.S. Eastern rule: UTC-04 from the second Sunday in March through
the first Sunday in November, and UTC-05 otherwise.

All request-start, response-header, and response-completion timestamps must
map to the declared publication date under that offset. The state windows
are:

```text
FIRST_0900_STATE       -> all three timestamps in [09:00, 14:30) New York
SAME_DAY_1430_REVISION -> all three timestamps in [14:30, 24:00) New York
LATER_CORRECTION       -> declared local publication date, unspecified time
CURRENT_STATE          -> declared local capture date, unspecified time
```

Strict first/same-day states require publication one to four calendar days
after the effective date. A later correction requires two to 31 days.
Current-state lookup permits one to 7,305 days, but remains explicitly
current/revised evidence. Consequently, a 2017 value fetched in 2026 cannot
be labeled a first or same-day historical state; it may only be a current
state.

This implementation does not contain a federal-holiday calendar. The
weekday and conservative lag checks prevent unconstrained retrospective
labels but do not prove that a declared date was an actual New York Fed
publication day. A future calendar-aware layer must resolve that limitation
before any origin can be considered, and the admission gates here remain
false.

## Closed states and raw-token handling

The immutable taxonomy contains:

| class | meaning |
|---|---|
| `FIRST_0900_STATE` | prospective candidate for the first intraday state |
| `SAME_DAY_1430_REVISION` | same-day revision linked to its predecessor |
| `LATER_CORRECTION` | extraordinary later correction linked to its predecessor |
| `ALFRED_DATE_STATE` | date-level vintage, not an intraday state |
| `CURRENT_STATE` | current API state, not a historical vintage |

`ALFRED_DATE_STATE` is represented so it cannot be conflated with another
class, but this New York Fed receipt validator does not ingest ALFRED
receipts. `CURRENT_STATE` must carry the literal
`CURRENT_API_DOES_NOT_PROVE_HISTORICAL_VINTAGE`; attempts to reverse that
claim fail validation.

The raw token mappings are:

```text
revision "" -> NOT_REVISED_RAW_EMPTY_TOKEN
revision r  -> DOCUMENTED_REVISED_RAW_TOKEN_WITH_SCHEMA_MISMATCH
footnote 1  -> DOCUMENTED_REDUCED_VOLUME
footnote 2  -> DOCUMENTED_BROKER_CONTINGENCY
footnote 3  -> DOCUMENTED_PRIOR_DAY_REPUBLICATION
rate volume -> NOT_REQUESTED_IN_REPORT_TYPE
blank numeric field -> UNKNOWN_NOT_ZERO and quarantine
currentState=true -> CURRENT_STATE_FLAG_NOT_VINTAGE
schema mismatch -> SCHEMA_MISMATCH_QUARANTINED
pair conflict -> QUARANTINED_PENDING_MATCHED_STATE_REVIEW
```

Bare `Used`, `Other`, `unknown`, schema aliases such as `rate` for
`percentRate`, and default branches are rejected. A mismatch admitted only
for preservation must carry a concrete detail, blocker, evidence locator,
and pending adjudication; it cannot produce a joined rate-volume record.

For complete rate rows, the contract also enforces
`p1 <= p25 <= EFFR <= p75 <= p99` and
`targetRateFrom <= targetRateTo`. A structurally impossible row is rejected
before pairing. A permitted blank remains `UNKNOWN_NOT_ZERO` and
quarantined; it is never substituted with zero.

## Terms decision boundary

The terms snapshot must be dated no later than the publication date and no
more than 31 days old. Approved internal research and approved
public-derived contexts have separate closed attribution, disclaimer, and
redistribution profiles. Pending and rejected decisions have their own
closed fields, require `PROHIBITED` redistribution, carry
`TERMS_REVIEW_PENDING` or `TERMS_REVIEW_REJECTED`, and cannot produce a
joined pair. `NONE_REQUIRED`, an old 1990 snapshot, or a profile inconsistent
with its decision fails validation. No unregistered decision/scope
combination can fall through to a rejected-use profile.

## Pairing and authentication boundary

Rate and volume receipts remain independent. `pair_receipts` joins them only
after both receipts pass validation and their exact `effectiveDate`, raw
`revisionIndicator`, closed state class, publication date/offset, pair key,
OpenAPI SHA-256, terms snapshot hash/date/decision, attribution,
disclaimer, and redistribution scope agree. A date, token, state, schema,
OpenAPI, governance, or input-quarantine conflict returns a typed quarantine
decision with `joined_record = nothing` and preserves the mismatched
governance field names where applicable. Matching pending or rejected
receipts still return `TERMS_REVIEW_NOT_APPROVED`.

The embedded receipt digest is an integrity check, not authentication.
`validate_receipt` therefore requires a second SHA-256 supplied by its caller
from an out-of-band trusted manifest. Changing a receipt and recomputing its
own digest fails against the unchanged external pin. This directory does not
create that manifest or claim that an unauthenticated hash proves source
authenticity.

No filesystem path or raw-byte input is accepted by the module, so symlink
and hard-link handling is deliberately outside its attack surface. A later
artifact importer must reject both before calling this validator and must
independently establish durable storage and the external receipt pin.

All historical-first-byte, origin, empirical-execution, inventory-mutation,
promotion, production-scoring, current-API-as-vintage, and readiness gates
are permanently false. Even an exact rate-volume pair is only a validated
receipt pair.

## Verification

From the repository worktree:

```bash
julia --startup-file=no --project=scripts/us \
  --check-bounds=yes --depwarn=error \
  scripts/us/forecasting/vintages/effr/capture_contract/test_effr_capture_contract.jl
```

Formatting:

```bash
runic --check \
  scripts/us/forecasting/vintages/effr/capture_contract/USEFFRCaptureContract.jl \
  scripts/us/forecasting/vintages/effr/capture_contract/test_effr_capture_contract.jl
```

The 178-test suite uses synthetic dictionaries only. It performs no network
request and reads or writes no external artifact.
