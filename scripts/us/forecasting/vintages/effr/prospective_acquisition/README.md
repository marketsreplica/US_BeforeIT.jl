# EFFR 2026-08-07 day-zero prospective acquisition

This directory contains the minimal, fail-closed acquisition runner for the
first day of the preregistered 2026Q3 EFFR campaign. The fixed publication
date is 2026-08-07 and the fixed effective date is 2026-08-06. It implements
only two bounded operations:

- the first-state request set inside
  `[2026-08-07T13:00:00Z, 2026-08-07T13:15:00Z]`, corresponding to
  `[09:00,09:15]` America/New_York; and
- the revision-check request set inside
  `[2026-08-07T18:30:00Z, 2026-08-07T18:45:00Z]`, corresponding to
  `[14:30,14:45]` America/New_York.

The runner never sleeps, polls, mutates the checked-in source inventory,
updates the prospective contract, admits an origin, scores a forecast, or
promotes a model. It checks the host clock before any live request and refuses
to execute outside the relevant 15-minute window.

## Exact live commands

Run these commands from the repository worktree. The first command must start
at or just after `2026-08-07T13:00:00Z`:

```bash
julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/effr/prospective_acquisition/capture_effr_day_zero.jl \
  --phase first \
  --transaction-id effr-20260807-first-1300z \
  --output-root data/us/raw/forecasting/effr/prospective/day-zero \
  --execute-live
```

If that command reports `Raw capture complete: true` with either
`RAW_CAPTURE_COMPLETED_NONADMITTING_ONE_DATE_CONTRACT_INCOMPATIBLE` (the
expected status for the currently observed raw schema) or
`LOCAL_INTEGRITY_VALIDATED_NONADMITTING_FIRST_STATE_CANDIDATE`, run this
second command at or just after `2026-08-07T18:30:00Z`:

```bash
julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/effr/prospective_acquisition/capture_effr_day_zero.jl \
  --phase revision-check \
  --transaction-id effr-20260807-revision-1830z \
  --output-root data/us/raw/forecasting/effr/prospective/day-zero \
  --predecessor-bundle data/us/raw/forecasting/effr/prospective/day-zero/2026-08-07/FIRST_0900_STATE/effr-20260807-first-1300z \
  --execute-live
```

Omit `--execute-live` to print the exact network-free, write-free plan. For
example:

```bash
julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/effr/prospective_acquisition/capture_effr_day_zero.jl \
  --phase first \
  --transaction-id effr-20260807-first-1300z \
  --output-root data/us/raw/forecasting/effr/prospective/day-zero
```

The output root is under the ignored `data/us/raw/` tree. Each transaction is
append-only: an existing transaction directory or recoverable transaction
journal is never overwritten. Every existing ancestor and path component of
the output root is required to be a real directory rather than a symbolic
link. The date and state directories, private journal, and final candidate are
realpath-checked for containment before the first request and again before
atomic publication.

## Request and parsing boundary

Each phase performs exactly six direct, no-redirect GETs in this order:

1. `https://markets.newyorkfed.org/api/rates/all/search.json?endDate=2026-08-06&startDate=2026-08-06&type=rate`
2. `https://markets.newyorkfed.org/api/rates/all/search.json?endDate=2026-08-06&startDate=2026-08-06&type=volume`
3. `https://markets.newyorkfed.org/static/docs/markets-api.html`
4. `https://markets.newyorkfed.org/static/docs/markets-api.yml`
5. `https://www.newyorkfed.org/privacy/termsofuse`
6. `https://www.newyorkfed.org/aboutthefed/holiday_schedule`

The first two URLs and canonical query order are the exact route required by
the checked-in one-effective-date receipt validator. The runner does not
substitute the more convenient series-specific CSV or JSON route.

Before network access, the runner creates a deterministic private
`.journal-<transaction-id>` directory with mode `0700` below the verified
state directory. It writes an immutable start event before each request. Every
complete response body is copied, hashed, exclusively created, file- and
directory-synced, and read back in both local raw replicas immediately after
the transport returns and before HTTP status, redirect, media type, clock,
header, schema, or receipt validation. A complete invalid response is
therefore retained. The higher-level manifest records the exact requested and
final URL, canonical query, request start, response-metadata observation, body
completion, HTTP status, selected response headers and their hash, content
type/encoding, byte count, raw SHA-256, both ignored byte paths, attempted and
completed request counts, and the exact failed object and attempt index.

`Downloads.request` exposes its response object after the body transfer
returns. The manifest and any conditionally generated one-date receipt
therefore record the conservative post-body response-metadata observation as
the header observation timestamp; they do not pretend to know an earlier
socket-level header-arrival time.

The all-rates endpoint returns multiple reference-rate rows. The importer
preserves the full body, then requires exactly one row whose raw identity field
is `type="EFFR"`. It records the raw identity, exact JSON pointer, array index,
and raw key set in the acquisition manifest. Zero or multiple EFFR rows,
unknown fields, a true `currentState`, an unsupported revision token, an
unexpected envelope, or an alias/row-one fallback causes a typed failure. Raw
bytes are still retained, but no one-date receipt is created.

The live API currently omits `currentState` for this route, and the official
OpenAPI does not define that field. The runner records
`ABSENT_FROM_RAW_RESPONSE_NOT_DERIVED`; it does not fabricate `false`. A
complete, otherwise valid capture is installed once with status
`RAW_CAPTURE_COMPLETED_NONADMITTING_ONE_DATE_CONTRACT_INCOMPATIBLE` and typed
blocker `ONE_DATE_CONTRACT_RAW_CURRENT_STATE_FIELD_ABSENT`. It contains no
one-date receipt or pair. This is a successful raw capture, so it must not be
retried merely because downstream receipt validation is blocked. If the
source supplies `currentState=true`, the importer fails rather than
relabeling a current-state response as historical first-state evidence.

## OpenAPI, terms, and holiday evidence

The runner captures both the official Markets API documentation HTML and the
`markets-api.yml` bytes that page names. It requires the HTML's literal
relative-YAML discovery binding, then records separate hashes for both
objects. This is a same-run source snapshot, not a precommitted or externally
authenticated OpenAPI pin, and the schema is not compiled into the runner.
Those limitations remain explicit blockers.

The New York Fed [Terms of Use](https://www.newyorkfed.org/privacy/termsofuse)
permit automated access that does not interfere with the site and permit
downloading and storing content, subject to attribution, modification
labeling, reference-rate notice, and other conditions. The runner captures
the exact terms bytes used for the project interpretation, retains the
required attribution and reference-rate notice, and restricts the result to
internal research. `APPROVED_FOR_BOUNDED_CAPTURE` is a project decision, not
legal advice or independent legal authorization.

The official
[New York Fed holiday schedule](https://www.newyorkfed.org/aboutthefed/holiday_schedule)
is also captured and hashed. Its bytes are evidence for later review; this
minimal runner does not implement a holiday parser and does not claim that
the publication day has been independently validated.

## First state and revision semantics

The first phase requires the raw empty revision token in both the rate and
volume EFFR rows. Under the currently observed schema, the missing raw
`currentState` field blocks the checked-in one-date receipt contract, so the
runner preserves the exact first-state candidate bytes and emits no receipt.
The synthetic suite separately proves that, if a future response actually
contains raw `currentState=false`, separate rate and volume receipts must pass
the checked-in validator and exact pairing boundary. Any manifest-generated
receipt hashes would still be local integrity pins produced by the same
process, not out-of-band authentication.

The revision-check phase first revalidates the predecessor manifest,
receipt pair, and both raw copies:

- empty tokens plus byte-identical rate and volume responses produce
  `BYTE_IDENTICAL_NO_REVISION_RECEIPT_CREATED`; this is a successful,
  immutable check record and deliberately contains no revision receipt;
- changed bytes with empty or unknown tokens are retained and quarantined,
  with no revision receipt; and
- the closed raw token `r`, at least one byte change, raw
  `currentState=false` in both rows, a validated predecessor receipt, and a
  valid exact pair are required before linked `SAME_DAY_1430_REVISION`
  receipts can be created. With the currently observed absent field, the
  revision bytes are preserved with the same compatibility blocker and no
  revision receipt.

This prevents an unchanged 14:30 lookup from being relabeled as a revision.

## Storage and admission boundary

Each bundle has two local ignored copies, a local storage-integrity receipt,
an immutable request-attempt journal, and a self-hashed manifest. Successful
or handled fail-closed runs are atomically renamed from the private journal to
the final transaction path. If publication itself cannot proceed, the
deterministically named private journal and already synced raw bodies are
retained for recovery; a later invocation refuses to overwrite them. These
are useful against accidental local corruption but do not satisfy the
prospective contract's durable-storage requirements. In particular, the
runner does not establish:

- two externally durable write-once or versioned copies;
- an external timestamp;
- retention through 2031;
- an independently attested host clock or transport;
- a daily-manifest completeness verifier;
- out-of-band receipt authentication;
- approval of the draft prospective contract; or
- activation of the historical-backfill acquisition gate.

Every empirical, inventory-mutation, origin-admission, accuracy-evaluation,
promotion, production-scoring, and readiness gate remains false.

## Scheduling assessment

The capture code is safe to invoke from an automation in the narrow sense
that the date, window, routes, redirects, overwrite policy, and receipt
semantics fail closed. Unattended GitHub Actions scheduling is not yet a safe
substitute for supervised day-zero capture because cron start times are not
exact, runner host clocks and transport are not independently attested, and a
short-lived Actions artifact does not satisfy the external timestamp,
two-durable-copy, or 2031-retention requirements. No production scheduling
workflow is installed by this directory.

For day zero, use the exact supervised commands above and copy the resulting
ignored bundle to approved durable storage without modifying its bytes.

## Verification

The tests are hermetic and make no network request:

```bash
julia --startup-file=no --depwarn=error --check-bounds=yes \
  --project=scripts/us \
  scripts/us/forecasting/vintages/effr/prospective_acquisition/test_effr_day_zero_acquisition.jl
```

They cover the network-free dry run, the pre-network clock guard, exact EFFR
row selection, ancestor/output/date symlink rejection before fetch, realpath
containment, private preflight creation, per-response dual persistence before
the next request, accurate attempted/completed/failed accounting,
absent-field compatibility blocking, conditional local receipt and pair
validation with a synthetic raw field, full-byte preservation,
unknown/current-state/cardinality failures, partial-request journals,
completed invalid HTTP-body preservation, recoverable publication failure,
append-only journal refusal, byte-identical no-revision checks, changed bytes
without a revision token, linked closed-token revisions, and tampered
predecessor bytes.

Before implementation, two stdout-only capability probes (one `rate`, one
`volume`) used the same official all-rates route for the older effective date
2026-08-05. They were explicitly current-state schema discovery, wrote no
artifact, and are not part of the 2026-08-06 prospective receipt chain.
