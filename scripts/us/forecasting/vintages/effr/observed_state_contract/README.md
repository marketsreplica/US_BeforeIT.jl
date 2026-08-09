# EFFR observed-state contract v3

This directory contains an independently accepted offline validator and
adjudicator for paired New York Fed EFFR endpoint observations. Acceptance is
limited to its permanently nonadmitting, locally integrity-checked role. It is deliberately
incompatible with
`beforeit-us-effr-one-effective-date-capture-receipt.v2`. It does not
download, schedule, retry, or write captures, and it cannot admit an origin,
complete a source profile, score a forecast, or promote a model.

The contract records only what the preserved response bodies support:

- `MORNING_WINDOW_ENDPOINT_OBSERVATION`;
- `POST_REVISION_WINDOW_ENDPOINT_OBSERVATION`; and
- `OBSERVED_EFFR_TRANSITION`.

These names are endpoint-observation claims. They are not aliases for
first-public bytes, an atomic publication transaction, the final state for a
day, or a state that can never be corrected later.

## Why v3 is incompatible

The current pinned `effr-record` OpenAPI schema has zero `currentState`
members, and the pinned API-documentation page also has zero. The exact
August 7 rate and volume bodies omit that member. The schema describes
`percent` while the wire uses `percentRate`, gives `"Y"` as a
`revisionIndicator` example while the official page and captured wire use
empty or `r`, and supplies no response-property `required` list.

The durable disposition is therefore:

```text
current_openapi_definition = ABSENT
captured_wire_presence = ABSENT
authoritative_evidence_ever_official = NOT_ESTABLISHED
raw_false_derivation_allowed = false
synthetic_current_state_allowed = false
```

No authoritative source inspected for this contract establishes that
`currentState` was never official. V3 says only that it is absent from the
current pinned schema and captured responses. A `currentState` member in any
future response is schema drift and is quarantined; it is never accepted or
converted to false.

This major-version change follows [Semantic Versioning
2.0.0](https://semver.org/spec/v2.0.0.html) as an engineering convention.
SemVer does not authenticate the data or approve the scientific use.

## Official publication rule encoded

The [New York Fed EFFR
page](https://www.newyorkfed.org/markets/reference-rates/effr) identifies
raw `r` as the revised marker. The New York Fed's official [publication and
revision policy](https://www.newyorkfed.org/markets/reference-rates/additional-information-about-reference-rates),
reviewed in its April 6, 2026 form, says the rate is normally published
around 09:00 ET and a same-day revision is made around 14:30 ET only when the
published rate changes by **more than one basis point**. Accompanying
percentiles and volume are revised only when that qualifying rate revision
occurs.

The executable rule is consequently:

```text
abs(later percentRate - morning percentRate) > 0.01 percentage point
```

Equality is not enough. The implementation preserves each raw RFC 8259
number token and parses it directly as a `Rational{BigInt}`. It never routes
the policy decision through `Float64` or through a re-rendered number. The
decision self-hash covers both raw `percentRate` lexemes and the reduced,
canonical basis-point numerator and positive denominator. Its validator
reparses the lexemes, recomputes the fraction, and reapplies the strict
threshold and outcome. Both report responses must carry raw `r`. Rounded
`volumeInBillions` is allowed to remain visibly unchanged.

The pinned OpenAPI snapshot contains five `footnoteId` schema members and
zero standalone `footnote` members. V3 consequently permits only an absent
annotation or the exact member `footnoteId` with a raw JSON integer 1, 2, or
3. Decimal (`1.0`), exponent (`1e0`), Boolean, string, and `footnote` alias
forms fail. These identifiers are separate contingency annotations for
reduced volume, broker contingency, and prior-day republication. A
contingency annotation is not required for, and is not evidence of, a marked
revision. V3 applies the conservative local pairing rule
`EXACT_FOOTNOTE_ID_INTEGER_OR_ABSENCE_MATCH_OR_QUARANTINE`; this cross-report
rule is a project validation profile, not a New York Fed claim.

## Closed parsing

The validator copies and hashes each complete response body before parsing.
Its closed lexical parser rejects duplicate names after escape decoding
before building an object. Thus, for example, `type` and `t\u0079pe`
conflict. It also retains every selected numeric lexeme while parsing all
numeric values exactly, and rejects invalid UTF-8 or an unpaired Unicode
surrogate. This implements the interoperability caution in
[RFC 8259](https://www.rfc-editor.org/rfc/rfc8259.html).

The frozen resource ceilings are 1,048,576 body bytes, 64 nested JSON
levels, 96 bytes per numeric token, 40 mantissa digits, and absolute decimal
exponent 20. Token, mantissa, and exponent bounds are checked before the
bounded mantissa is converted to `BigInt`; deeper, larger, or more precise
input requires a successor profile.

The complete envelope must contain only `refRates`. Every row is checked:

- `type` must be an exact string in the frozen
  `EFFR/OBFR/TGCR/BGCR/SOFR/SOFRAI` vocabulary;
- there must be exactly one exact `type="EFFR"` row;
- the date, report-specific key set, numeric types, and raw revision token
  are closed;
- the rate route requires raw `percentRate`; `percent` is not an alias;
- revision is exactly the empty string or lowercase `r`; `"Y"`, missing,
  generic, `Used`, `Other`, and new tokens fail;
- only absent or exact integer `footnoteId` in the closed `1/2/3`
  vocabulary is allowed; `footnote` is unknown schema drift;
- `Bool`, numeric strings, nonfinite numbers, new fields, duplicate EFFR
  rows, and unknown row types fail; and
- EFFR percentiles must order around the rate and the target bounds must not
  be reversed.

Both a whole-body SHA-256 and sorted, typed selected-row/value SHA-256 values
are retained. The semantic hashes canonicalize each selected number to its
reduced exact rational, while `selected_fields` separately retains the raw
numeric lexeme. Thus `3.63` and `3.630` have the same economic-value hash but
different full-body hashes and are treated as a serialization/body change,
not an economic transition. The whole-body hash also detects non-EFFR,
row-order, whitespace, and other serialization changes. No parser branch
silently strips a name, converts a type, supplies a missing value, or chooses
the first row as a fallback.

## Capture envelope and non-atomic pair

V3 accepts `CapturedReport` values supplied in memory by a separate
byte-preserving collector. For each report it requires:

- the pinned one-date query in exact
  `endDate=...&startDate=...&type=rate|volume` order;
- the exact HTTPS request and final URL on
  `markets.newyorkfed.org`, status 200, and zero redirects;
- exact `application/json` or
  `application/json;charset=utf-8`, with identity encoding;
- raw, nonduplicated HTTP header names and values, retained under a separate
  header digest; and
- ordered request-start, body-completion, and metadata-observation times
  inside the pinned 13:00--13:15Z morning or 18:30--18:45Z post-revision
  window.

Publication and effective dates are looked up in the byte-pinned campaign
schedule. Weekends, the pinned September 7 and October 12 holidays, effective
date transitions, and the absence of a pre-origin October 30 revision slot
therefore stay governed by the existing schedule. The v3 validator does not
re-authorize its network or raw-write gates.

Rate and volume requests must be sequential: rate metadata is observed before
the volume request begins. Each retains its own start, completion, metadata,
header, full-body, and selected-row hashes. Their revision tokens must agree;
their contingency representation must both be absent or carry the same exact
integer `footnoteId`. `pair_as_of_utc` is the recorded volume-body
completion, while the record also retains the earlier rate-body completion.
`requests_sequential_not_atomic=true` is permanent.

An HTTP `Date` header is retained in the exact header hash but cannot serve as
a trusted publication timestamp. [RFC 9110
§6.6.1](https://www.rfc-editor.org/rfc/rfc9110.html#name-date) permits an
approximate value and, in some conditions, recipient insertion or
replacement.

## Transition matrix

| Morning and later endpoint evidence | V3 outcome |
|---|---|
| both empty tokens; both selected EFFR rows and full bodies identical | `NO_MARKED_REVISION_OBSERVED_AS_OF_SECOND_CAPTURE` |
| morning empty; coherent later pair `r`; published rate change strictly greater than one basis point | `MARKED_SAME_DAY_REVISION_OBSERVED` |
| morning already `r` | `QUARANTINED_MORNING_ALREADY_MARKED_REVISED` |
| later empty but any selected EFFR semantic field changes | `QUARANTINED_UNMARKED_EFFR_TRANSITION` |
| later `r` but rate change is at most one basis point | `QUARANTINED_MARKED_REVISION_POLICY_INCONSISTENT` |
| rate/volume token, exact `footnoteId` or absence, date, type, role, or timing mismatch | typed pair failure / `QUARANTINED_RATE_VOLUME_PAIR_MISMATCH` profile |
| selected EFFR rows identical but a full body differs | `QUARANTINED_FULL_RESPONSE_CHANGED_WITHOUT_EFFR_TRANSITION` |
| missing/unknown token, alias, new field, duplicate, `currentState`, or unknown category | typed schema error / `QUARANTINED_SUCCESSOR_PROFILE_REQUIRED` profile |

The unchanged outcome deliberately says only what was observed as of the
second capture. It never says “no same-day revision occurred,” “first
publication,” “final state,” or “no later correction.” A change in a
non-EFFR row or only in serialization remains quarantined until a separately
frozen rule exists.

## Append-only adjudication

`adjudicate_morning_observation` and `adjudicate_transition` create new
in-memory decision documents. They require:

- a new decision ID and creation time no earlier than the linked evidence;
- the exact predecessor observation digest;
- an out-of-band predecessor decision digest;
- the exact incompatible v2 schema name;
- the old capture-manifest digest and exact v2 nonreceipt status; and
- `APPEND_ONLY_OFFLINE_READJUDICATION_NO_MUTATION_NO_BACKDATING`.

The copied August 7 rate and volume bytes reproduce
`5977e0...5341` and `13f146...bc61`, respectively. The hermetic suite
re-adjudicates those bytes into a new morning endpoint decision linked to
the old `f801b5...d6d1` manifest and
`NOT_CREATED_RAW_CURRENT_STATE_FIELD_ABSENT`. It does not read, edit,
replace, or backdate the ignored raw bundle or the v2 artifact.

Decision documents carry a self-hash and must also validate against a caller's
out-of-band expected hash. Rewriting a trust gate and recomputing the public
self-hash still fails because compiled code fixes all trust and admission
gates false. Validation also fails against the original external pin.

Transition decisions additionally carry
`morning_percent_rate_lexeme`, `later_percent_rate_lexeme`, and the exact
reduced `rate_change_basis_points_numerator` and positive
`rate_change_basis_points_denominator`. They also self-hash the morning and
later revision tokens and the selected-row/full-body equality facts.
Revalidation recomputes the fraction, complete transition-matrix outcome,
claim, and exact blocker set. It rejects a noncanonical fraction, a leading
zero, inconsistent equality facts, a mismatched exact difference, or a
restamped outcome/blocker set that does not replay from those facts.
Selected-row identity also requires equal revision tokens; full-body identity
requires the same exact rate lexeme; and morning/later observation hashes must
differ. Standalone validation rechecks the recorded pair/latest-evidence times
against the pinned morning and post-revision windows, not merely their order.

An optional caller-asserted RFC 3161 token hash is recorded only as
`CALLER_ASSERTED_RFC3161_TOKEN_NOT_CRYPTOGRAPHICALLY_VERIFIED`. Even a
cryptographically validated [RFC 3161
timestamp](https://www.rfc-editor.org/rfc/rfc3161.html) would establish that
a digest existed before a time; it would not by itself prove that the New
York Fed served the bytes. Publisher and transport provenance therefore
remain false.

## Pinned evidence and source boundary

| Reviewed object | SHA-256 |
|---|---|
| campaign control | `83db9b24f88e7ad48ba21726f7905b2ba7a00638e681ff40d8fdcf0c728edd02` |
| campaign schedule file | `ddbc7a089a636d09f97e68e67da7f534ecca6c88d6b7dbc8bf78080ce7400e25` |
| campaign schedule semantic content | `fb984becfc5608922cd4acffd7e3e3bdf997022935f816acad221ec32dcd0383` |
| prospective v2 contract file | `b24ff0c40172d2a23991fbe75c2fe42c6ba6c6c1f5fd46d079ac6d51429bf98f` |
| prospective v2 semantic content | `5d1e7f34eea0470877c7bed096d8b2fb26590f95bd06febb90813faf6063708a` |
| one-date v2 source | `6c4ee3ff95b92daf34899db64dbff7fc920eb33e5bc4bf17a6adf99bf3b3f651` |
| August 7 old manifest file | `f801b5539a550857a4ca6c69e0f16ad1c7645ab83e3c87407a0c99aeed4db6d1` |
| August 7 old manifest semantic content | `9a865a8b60f06b0da33be4f48e40266d986d633d250715c55c69fb113d130885` |
| August 7 rate body | `5977e0aafae9f34d348ad69166afce47c223b6147312654155855e0450315341` |
| August 7 volume body | `13f146b7f27a724f28a63343fed40c1cdb3c447eec1a5663d5b1b5f192febc61` |
| API documentation snapshot | `c1ab76a0e006e7f16c5ba4660716f2ade0f8a76e58dbbe7124d73a9fbf98cd2c` |
| OpenAPI snapshot | `5dbb331d86b91bfc115be9b5fe9c46735833a4f7280d33e4327e8acf7ad30d2b` |
| terms snapshot | `a2904b4679f340f17330c845f481399398f7aeb1fabae5ca14781f15ed3d776b` |
| holiday snapshot | `2d4c37577b6e439136ef15ccf1d56869133e1342a292310417f190d24e239b17` |
| v3 protocol semantic content | `33eb8eba8a6399568c0890d86d555cb5177659d62c098522098ca5d6ce21952c` |

The first six checked-in source files are rehashed when the protocol loads.
The raw August 7, API, OpenAPI, terms, and holiday hashes are evidence
identities, not a claim that an ignored local raw directory exists in every
checkout. The test embeds exact copied response bytes rather than reading
that directory.

The [OpenAPI 3.0 schema
rules](https://spec.openapis.org/oas/v3.0.0.html#schema) and [JSON Schema
2020-12 `required`
rules](https://json-schema.org/draft/2020-12/json-schema-validation#name-required)
support the interpretation of the reviewed schema. These standards and the
remote New York Fed pages are literature/source assertions. Only the listed
local byte hashes are local integrity facts, and none authenticates the
historical TLS exchange, publisher, operator, or host clock.

The protocol validator freezes the exact contract ID, all eight normative
transition evidence strings, and each citation's ID, direct URL, scope, and
local-authentication status. Rehashing a protocol after relabeling remote
literature as a pinned local snapshot therefore fails closed.

## Estimand remains pending

Every decision retains both candidate estimands:

1. `STRICT_FIRST_PUBLIC_BYTES`; and
2. `PRE_ORIGIN_OBSERVED_ENDPOINT_VINTAGE`.

The selected estimand is `NONE` and status is `PENDING`. Owners and validators
must make that scientific/governance decision before origin admission. V3
cannot select it by default. The second option may better represent the
latest eligible information observed before an origin, but this is a project
choice motivated by real-time-data practice, not a conclusion forced by
[Croushore and Stark
2001](https://doi.org/10.1016/S0304-4076(01)00072-0) or by the receipt
mechanics.

## Verification

Run from the repository root:

```bash
julia --startup-file=no --depwarn=error --check-bounds=yes \
  --project=scripts/us \
  scripts/us/forecasting/vintages/effr/observed_state_contract/test_effr_observed_state_contract_v3.jl
```

The frozen suite passes 253 assertions:

```text
protocol pins and incompatible governance boundary       46 / 46
exact copied August 7 bytes and linked re-adjudication    42 / 42
closed parser and raw-schema quarantine                   36 / 36
query, host, media, redirect, windows, sequential pair    22 / 22
full observed-transition matrix and claim ceiling         31 / 31
exact decimal lexemes and strict revision boundary        42 / 42
bindings, self-rehash, timestamp non-elevation            27 / 27
offline/no capture or raw-write surface                     7 / 7
-----------------------------------------------------------------
total                                                     253 / 253
```

Independent audit reproduced 253/253 from both the repository root and an
unrelated `/tmp` working directory. Valid exact-ceiling and rate-boundary cases
produced their expected outcomes. Duplicate names, over-limit inputs,
noncanonical fractions, inconsistent transition facts, out-of-window times,
frozen-profile or citation changes, and validation under the original pin
after mutation failed with the expected typed errors. A fully coordinated
rewrite can pass only under a newly chosen caller-supplied pin and still fails
under the original pin; internal replay consistency is not publisher
authentication.

## Permanent limitations

Local hashes, copied bodies, parser closure, and linked decisions establish
local integrity only. This contract does not establish authenticated
transport or publisher provenance, an externally witnessed network count,
authenticated operator authorization, an independent trusted time, durable
external storage, campaign completion, other-profile completion, first-public
bytes, atomic rate/volume state, no extraordinary later correction, origin
admission, truth, forecast accuracy, scoring, suitability, promotion, or
production readiness. Every corresponding executable gate is permanently
false.
