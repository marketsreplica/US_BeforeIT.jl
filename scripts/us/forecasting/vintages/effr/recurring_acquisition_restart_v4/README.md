# EFFR restart-bound recurring acquisition v4

This directory is an isolated acquisition successor bound only to the accepted
offline `campaign_restart_v2` schedule. It handles that restart's 115 slots:

- 58 first-state captures from 2026-08-10 through 2026-10-30; and
- 57 same-day revision checks from 2026-08-10 through 2026-10-29.

It derives the publication date, effective date, phase, UTC window,
transaction ID, paths, request queries, and revision predecessor from the
byte- and semantic-hash-pinned restart schedule. The CLI fixes the output root
to `data/us/raw/forecasting/effr/prospective/2026q3_restart_v2` and exposes no
path override. It rejects every date/phase absent from the restart, including
2026-08-07. The withdrawn/incomplete v1 schedule is lineage evidence only: it
cannot authorize this runner, validate its manifests, or contribute a receipt
to the restart denominator.

The manifest schema is
`beforeit-us-effr-recurring-acquisition-restart.v4`, and the campaign identity
is
`frbny_effr_daily_first_state_and_revision_check_restart_20260810`. A v4
bundle cannot validate as an old recurring-v3 bundle. The implementation pins
the recurring-v3 module, CLI, tests, and README as its reviewed source base,
but explicitly records that source reuse is not a behavioral attestation.

The closed source binding is:

- restart module SHA-256
  `5e0873ec7c427c377386bf9bd33c782f39a4735391011cffc7e24a1c67aa7155`;
- restart schedule-file SHA-256
  `670e5b02b740e9195b768d22e002ee3de49f037efb5f0b1228f0c9482e3e0136`;
- restart schedule semantic SHA-256
  `cae7f463b752ff2c60c78751ca0186712a53fb1732c7970e8bb0e4368d9e477b`;
- recurring-v3 module/CLI/tests/README SHA-256 values
  `3685e0c0ca3d440bdf2816d3c3bc229656d4a2339d6009b34f2c754c4a7051de`,
  `e2f293dd77da818c5fd0ee64e8bb520a162f62e805c17fdc6cf6131f6db3800f`,
  `256eac940dace2e749efb98be33e9ba059f21883da5b6d0bf92fdac2beb7e41b`,
  and `052d02b3117037d86830de50783f43f782907ae84824fa7507acd36b70784d02`;
  and
- capture-contract module SHA-256
  `6c4ee3ff95b92daf34899db64dbff7fc920eb33e5bc4bf17a6adf99bf3b3f651`;
- observed-state-v3 module and protocol-file SHA-256 values
  `3b3040245dd04b800bcdb25d1af0f57c211bf29ce3462f7134418f0263f1f4d6`
  and
  `d09e7d378b22a36a364cd4b08e7f0c42d7a3804c473e8332a22fbe4d9fc20716`;
- observed-state-v3 protocol semantic SHA-256
  `33eb8eba8a6399568c0890d86d555cb5177659d62c098522098ca5d6ce21952c`;
  and
- observed-state-v3 tests and README SHA-256 values
  `55bfbf5a4b252804f4e3b2e91100c83b8ff98bffbf10eec5bdd3bd83d96ad66c`
  and
  `4368b69641138bd5701a9fb4d6be382e23d6b02e0e756192fb9c12b124e12e23`.

The observed-state-v3 binding is offline adjudication code, not acquisition
authority. Its internally pinned original schedule is consulted only after a
restart bundle and its exact restart predecessor have passed restart-v4
validation. That legacy schedule neither authorizes a request nor validates a
restart manifest. The restart schedule alone derives and authorizes the
runner's bounded slot.

The runner does not sleep, poll, schedule itself, modify source inventories,
complete a profile, admit an origin, evaluate accuracy, score a forecast, or
promote a model. All such gates remain false.

The accepted schedule bytes predate this successor and therefore retain
`runner_restart_binding_complete=false`. This package does not rewrite that
historical control. Its tests can establish a separate software-binding result
only after independent audit; schedule acceptance alone never authorizes live
execution.

## Dry run and bounded live invocation

Dry run is the default and is both network-free and write-free:

```bash
julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/effr/recurring_acquisition_restart_v4/capture_effr_recurring_restart_v4.jl \
  --publication-date 2026-08-10 \
  --phase first
```

The output prints the schedule-derived slot, effective date, exact six
requests, canonical transaction and journal paths, and zero network/write
counts. It does not create the output root.

The explicit live form is:

```bash
julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/effr/recurring_acquisition_restart_v4/capture_effr_recurring_restart_v4.jl \
  --publication-date 2026-08-10 \
  --phase first \
  --execute-live
```

For a revision check, change only `--phase`:

```bash
julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/effr/recurring_acquisition_restart_v4/capture_effr_recurring_restart_v4.jl \
  --publication-date 2026-08-10 \
  --phase revision-check \
  --execute-live
```

`--execute-live` is a separate, bounded operator authorization for the
selected campaign slot. The reviewed built-in code path invokes its downloader
exactly six times, with each invocation configured as a direct GET, and writes
the corresponding local append-only raw bundle. The CLI does not expose an
injected downloader or clock. The authorization is not inferred from restart
schedule governance. The frozen restart fields
`network_execution_authorized=false` and
`raw_data_write_authorized=false` remain false and are recorded unchanged in
the bundle. The operator flag does not authorize inventory mutation, origin
admission, scoring, accuracy evaluation, promotion, or production use.

The first command must be started inside the schedule-derived closed window
`[13:00:00Z,13:15:00Z]`; the revision command must be started inside
`[18:30:00Z,18:45:00Z]`. Every request start and body completion must also be
inside that window. Immediately before every attempt-journal event and every
downloader invocation, the runner samples the clock again and refuses to call
the downloader if that request would start after the deadline. The initial
preflight and post-body completion checks remain separate. A revision
invocation first loads and fully revalidates
the canonical same-day first-state predecessor, before creating a journal or
calling the downloader.

No live command was executed while implementing or testing this directory,
and no file was written under `data/us/raw/`.

## Exact request boundary

The reviewed built-in live code path makes six downloader invocations,
configured as direct GETs in this order:

1. the Markets API all-rates JSON endpoint with the canonical one-date query
   `endDate=<effective>&startDate=<effective>&type=rate`;
2. the same endpoint with
   `endDate=<effective>&startDate=<effective>&type=volume`;
3. the Markets API documentation HTML;
4. the documentation-linked `markets-api.yml`;
5. the New York Fed Terms of Use; and
6. the New York Fed holiday schedule.

The built-in live transport disables redirects, netrc, cookies, and ambient
proxies, requests identity encoding, bounds response sizes, and requires the
final URL to equal the requested URL. Header names must be valid HTTP field
names before normalization and may not have leading or trailing whitespace;
control characters are forbidden in names and values; and conflicting
duplicate `Content-Type` or `Content-Encoding` fields fail closed.

The module also has an explicitly marked synthetic-test path for hermetic
tests. It requires both an injected downloader and clock plus
`synthetic_test_fixture=true`. Such bundles record transport and network
request counts as unobservable, carry a synthetic-evidence blocker, use a
non-campaign event identity, and cannot target the restart output root. They
are rejected by the default loader and result evaluator. Only an explicit
test-loader/evaluator opt-in can inspect them. The injected callback may
execute arbitrary code, so its six callback invocations are never represented
as six network requests.

The same evidence ceiling applies to a persisted bundle created through the
built-in path. The manifest records
`transport_provenance_assertion_status="LOCAL_UNAUTHENTICATED_RUNTIME_ASSERTION"`,
`network_exchange_count="NOT_INDEPENDENTLY_WITNESSED"`, and permanent false
fields for persisted transport authentication, independently witnessed
network-exchange count, and externally authenticated operator authorization.
It also carries permanent blockers for all three limitations. Six downloader
invocations are a reviewed code-path contract, not proof that six network
exchanges occurred or that a particular operator authorized them.

The local hashes are unkeyed integrity checks. Rewritten synthetic bytes at an
arbitrary test root cannot become a campaign bundle because non-synthetic
loading requires the exact schedule path. A party able to rewrite every file
of an actual canonical-path bundle can nevertheless coherently remove a
synthetic marker, substitute the built-in-policy labels, and recompute every
local hash. The loader cannot authenticate that historical execution claim
from those bytes alone. Permanent false gates and blockers keep even a
structurally built-in-shaped bundle nonadmitting and unusable for forecast
scoring or promotion. External publisher signatures, an independent network
witness or transparency record, authenticated operator identity, and an
out-of-band trusted pin would be separate future controls.

The runner creates a private deterministic
`.journal-<canonical-transaction-id>` before the first request. It writes and
syncs a `prepared` event before each downloader call. That event records only
the pre-journal clock observation and explicitly says request start is still
pending. After the durable event write, readback, file sync, and directory
sync, the runner samples and validates the clock again immediately before
downloader reachability. The second observation—not the earlier preparation
time—is the `request_started_at_utc` used in response objects, manifests,
receipts, and the completed attempt event. If the second observation is after
the deadline, no downloader callback occurs; the prepared and immutable
failure records remain and explicitly say the request was not issued. If the
downloader was invoked but later throws, its second start observation and the
local invocation assertion are retained in the failure record.

If the downloader returns a bytes-or-string body, the runner immediately
creates, syncs, and reads back two complete raw-byte copies before obtaining
the completion-clock value or validating response metadata, HTTP status,
redirects, proxy use, encoding, media type, JSON schema, or receipt
eligibility. A returned complete but invalid response therefore remains in the
crash journal. If the downloader throws or returns no bytes-or-string body,
there is no complete returned body to preserve; the prepared event and
immutable failure record state that case without claiming raw preservation.

There is no automatic retry. A failure journal and a successful final bundle
are both append-only conflicts on later invocation. Recovery requires
operator review and a separately authorized procedure; this runner never
overwrites either path.

## Raw EFFR semantics

The rate and volume bodies are preserved in full before parsing. A lexical
pre-pass rejects duplicate JSON object members before materialization,
including names that become equal only after JSON escape decoding (for
example, `currentState` and `current\u0053tate`). Each body must have the exact
envelope and contain exactly one raw row with `type="EFFR"`.
The selected row must have the exact closed field set for its report type,
the authorized effective date, a revision token in `""|"r"`, and either no
footnote field or the exact raw integer `footnoteId` value `1`, `2`, or `3`.
The legacy `footnote` alias, strings, decimals, exponents, Booleans, and other
integer values are rejected. Rate and volume must have identical footnote
presence and value. Unknown fields, zero or duplicate EFFR rows, aliases,
row-position fallback, non-finite values, mismatched rate/volume tokens, or
mismatched `currentState` presence fail closed.

`currentState` is handled literally:

- raw `false` is recorded as `RAW_FIELD_FALSE` and can satisfy the local
  one-date receipt schema;
- absence is recorded as
  `ABSENT_FROM_RAW_RESPONSE_NOT_DERIVED`, creates no receipt, and carries
  `ONE_DATE_CONTRACT_RAW_CURRENT_STATE_FIELD_ABSENT`; and
- raw `true` is ineligible and fails after all six raw bodies have been
  retained.

The code never derives `false` from absence.

## Closed state-transition matrix

For a first-state slot, both EFFR rows must carry the empty revision token.
Raw `currentState=false` produces
`LOCAL_INTEGRITY_VALIDATED_NONADMITTING_FIRST_STATE_CANDIDATE`; an absent
field produces
`RAW_CAPTURE_COMPLETED_NONADMITTING_ONE_DATE_CONTRACT_INCOMPATIBLE`.

For a revision-check slot:

- empty tokens and byte-identical rate and volume bodies produce
  `RAW_BYTE_IDENTICAL_EMPTY_REVISION_TOKEN_NONADMITTING_CAPTURE_PRESERVED`
  and no receipt;
- changed bytes with empty tokens fail;
- token `r` without any response-byte change fails;
- changed `r` bytes with absent `currentState` produce the nonadmitting
  incompatibility status and no receipt;
- changed `r` bytes with raw `currentState=false` require both validated
  predecessor receipts and produce linked
  `LOCAL_INTEGRITY_VALIDATED_NONADMITTING_REVISION_CANDIDATE` receipts; and
- a receiptless predecessor cannot be used to manufacture a linked revision
  receipt.

The revision manifest binds the canonical predecessor path, predecessor
manifest hash, both predecessor raw hashes, and both predecessor receipt
hashes. The loader reconstructs the path from the schedule-derived root and
rechecks all bindings and raw transition conditions.

Raw acquisition and loading never emit
`NO_MARKED_REVISION_OBSERVED_AS_OF_SECOND_CAPTURE`; a manifest that uses that
observed-state claim as its raw status is rejected even after a coordinated
self-rehash. The legacy `BYTE_IDENTICAL_NO_REVISION_RECEIPT_CREATED` alias is
also rejected.

## Offline observed-state-v3 adjudication

`evaluate_restart_result` accepts only a validated restart revision bundle. It
reloads and validates the exact same-day restart morning predecessor,
reconstructs rate and volume `CapturedReport` values from the independent raw
replicas and manifest metadata, and passes both pairs through the exact pinned
observed-state-v3 endpoint validators. That step replays the v3 full-envelope
schema, duplicate-member rejection, exact integer `footnoteId` rule, literal
`currentState` prohibition, exact numeric-lexeme/rational arithmetic, strict
timestamp ordering, sequential rate/volume rule, and closed one-date URL and
header rules.

The first evaluator call may omit `decision_binding`. It then returns the two
validated observation hashes with
`adjudication_status="DECISION_BINDING_REQUIRED"`,
`endpoint_state_claim="NOT_ADJUDICATED"`, and no selected unchanged claim.
The caller must supply a `RestartDecisionBinding` whose predecessor observation
hash matches the reconstructed morning observation and whose other lineage
fields come from the caller's append-only decision history. The runner does
not invent or authenticate the out-of-band predecessor-decision or superseded
v2-manifest hashes. It records that decision-binding provenance remains
unauthenticated.

Only `ObservedStateContractV3.adjudicate_transition` can then select
`NO_MARKED_REVISION_OBSERVED_AS_OF_SECOND_CAPTURE`. The same adjudicator
quarantines unmarked semantic changes and marked changes of exactly or less
than one basis point, using exact rational arithmetic, and recognizes a marked
revision only above that threshold. Every decision remains offline,
nonadmitting, and blocked from empirical use, scoring, or promotion. The
evaluator permanently records `no_later_same_day_revision_claimed=false` and
`final_state_for_day_claimed=false`; a second-capture observation never proves
the final state of the day.

## Filesystem and validation boundary

Every existing path component must be a real directory. Symbolic-link
components, symbolic-link files, hard-linked files, non-normalized or
escaping relative paths, existing final paths, and existing journals are
rejected. File creation uses exclusive/no-follow flags. Raw objects have two
local copies; manifests, receipts, and the local storage record have three
local copies. All writes are flushed, file-synced, directory-synced, checked
for a single link, and read back.

Before atomic journal-to-final rename, and on every later load, the validator
rechecks:

- frozen restart-module, restart-schedule file and semantic hashes,
  recurring-v3 source-base pins, receipt-contract, observed-state-v3 module,
  protocol, semantic, tests and README pins, and prospective-contract
  bindings;
- the self-hashed manifest and local storage record;
- exact triplicate equality;
- every raw byte count and SHA-256 across both replicas;
- row identity reconstructed from raw bytes;
- receipt self-hashes, exact rate/volume pairing, and complete receipt
  reconstruction from the selected raw row, preserved response metadata,
  OpenAPI and Terms bytes, local storage record, phase, and predecessor;
- exact permanent-false gates, blocker sets, storage limitations, result
  constants, and receipt-authentication wording;
- recursive type-exact closed records, so integer `0`/`1` cannot substitute
  for Boolean fields and Boolean values cannot substitute for counters;
- rate/volume revision-token and `currentState` transition agreement;
- built-in operator-authorization separation and the six-request ceiling, or
  the explicitly non-campaign synthetic-test policy;
- restart status/phase/current-state rules and the prohibition on storing an
  observed-state decision as a raw status; and
- canonical predecessor bytes, receipts, manifest, and transition semantics.

The local copies and self-generated hashes detect accidental corruption but
are not independent authentication, durable external storage, or an external
timestamp. The runner does not establish retention through 2031, an
independently attested host clock or transport, official holiday parsing,
approval of the draft prospective contract, or a complete campaign origin.
The output root is fixed by the schedule and CLI, and a non-synthetic bundle
copied under another root is rejected. This is local pathname enforcement,
not authenticated host identity. Path checks use local pathname inspection
and no-follow/exclusive leaf creation; they are not a proof against a
concurrent same-user filesystem race. A transport exception that never
returns a complete body may also leave libcurl-held partial bytes outside the
journal. No scheduling workflow is installed by this directory.

## Hermetic verification

Run from the repository root:

```bash
julia --startup-file=no --depwarn=error --check-bounds=yes \
  --project=scripts/us \
  scripts/us/forecasting/vintages/effr/recurring_acquisition_restart_v4/test_effr_recurring_acquisition_restart_v4.jl
```

The same test can run from another working directory using absolute paths:

```bash
cd /tmp
julia --startup-file=no --depwarn=error --check-bounds=yes \
  --project=/absolute/path/to/scripts/us \
  /absolute/path/to/scripts/us/forecasting/vintages/effr/recurring_acquisition_restart_v4/test_effr_recurring_acquisition_restart_v4.jl
```

The 2,515-test hermetic suite uses only explicitly synthetic clocks, synthetic
downloaders, and temporary directories. Synthetic bundles are visibly marked,
rejected by default loading and result evaluation, and never treated as
empirical captures. The suite covers dry-run/no-write behavior, exact requests,
all 115 schedule rows and derived fields, restart/v1 authority separation,
restart-manifest and recurring-v3 cross-schema rejection, coordinated binding
mutations, schedule and clock boundaries, all completed statuses and invalid
transitions,
separate pre-journal and post-journal/immediately-pre-downloader deadline gates
for the first and later requests, truthful preparation/issuance timestamps,
strict
integer-only footnotes and unconditional pair symmetry, raw/observed-state
separation, observed-v3 reconstruction and exact-transition adjudication,
required caller decision binding, exact one-basis-point quarantine, marked
greater-than-one-basis-point recognition, and v3 rejection of raw-preservable
`currentState`, unknown-row, and timestamp drift,
predecessor byte/receipt closure, crash retention and no retry, full-body
preservation before transport/schema rejection, redirects, proxies,
encoding/media/status failures, returned-body preservation across completion
clock and metadata failures, truthful no-body handling, raw and persisted
header-name whitespace, header controls and conflicting singleton duplicates,
escaped-equivalent duplicate JSON members, missing and true `currentState`,
strict raw schema/cardinality, symmetric rate/volume transitions,
child-directory symlinks, leaf symlinks, hardlinks, path escape, coordinated
self-rehash mutations of receipt values and metadata, Boolean/integer
substitution, typed malformed-manifest failures, permanent unauthenticated
provenance blockers, append-only publication, operator/restart-schedule
authorization separation, and CLI argument and exit behavior.
