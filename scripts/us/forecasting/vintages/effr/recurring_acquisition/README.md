# EFFR date-parameterized recurring acquisition v3

This directory is the append-only successor to the immutable 2026-08-07
day-zero runner. It handles the remaining frozen 2026Q3 EFFR campaign slots:

- first-state captures from 2026-08-10 through 2026-10-30; and
- same-day revision checks from 2026-08-10 through 2026-10-29.

It derives the publication date, effective date, phase, UTC window,
transaction ID, paths, request queries, and revision predecessor from the
byte- and semantic-hash-pinned campaign schedule. It rejects 2026-08-07
because that slot belongs exclusively to the byte-pinned day-zero runner. It
does not accept overrides for derived fields.

The runner does not sleep, poll, schedule itself, modify source inventories,
complete a profile, admit an origin, evaluate accuracy, score a forecast, or
promote a model. All such gates remain false.

## Dry run and bounded live invocation

Dry run is the default and is both network-free and write-free:

```bash
julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/effr/recurring_acquisition/capture_effr_recurring.jl \
  --publication-date 2026-08-10 \
  --phase first \
  --output-root data/us/raw/forecasting/effr/prospective/2026q3
```

The output prints the schedule-derived slot, effective date, exact six
requests, canonical transaction and journal paths, and zero network/write
counts. It does not create the output root.

The explicit live form is:

```bash
julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/effr/recurring_acquisition/capture_effr_recurring.jl \
  --publication-date 2026-08-10 \
  --phase first \
  --output-root data/us/raw/forecasting/effr/prospective/2026q3 \
  --execute-live
```

For a revision check, change only `--phase`:

```bash
julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/effr/recurring_acquisition/capture_effr_recurring.jl \
  --publication-date 2026-08-10 \
  --phase revision-check \
  --output-root data/us/raw/forecasting/effr/prospective/2026q3 \
  --execute-live
```

`--execute-live` is a separate, bounded operator authorization for the
selected campaign slot. The reviewed built-in code path invokes its downloader
exactly six times, with each invocation configured as a direct GET, and writes
the corresponding local append-only raw bundle. The CLI does not expose an
injected downloader or clock. The authorization is not inferred from campaign
control. The frozen
campaign fields `network_execution_authorized=false` and
`raw_data_write_authorized=false` remain false and are recorded unchanged in
the bundle. The operator flag does not authorize inventory mutation, origin
admission, scoring, accuracy evaluation, promotion, or production use.

The first command must be started inside the schedule-derived closed window
`[13:00:00Z,13:15:00Z]`; the revision command must be started inside
`[18:30:00Z,18:45:00Z]`. Every request start and body completion must also be
inside that window. A revision invocation first loads and fully revalidates
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
non-campaign event identity, and are rejected by the default loader and by
campaign control. Only an explicit test-loader opt-in can inspect them. The
injected callback may execute arbitrary code, so its six callback invocations
are never represented as six network requests.

The same evidence ceiling applies to a persisted bundle created through the
built-in path. The manifest records
`transport_provenance_assertion_status="LOCAL_UNAUTHENTICATED_RUNTIME_ASSERTION"`,
`network_exchange_count="NOT_INDEPENDENTLY_WITNESSED"`, and permanent false
fields for persisted transport authentication, independently witnessed
network-exchange count, and externally authenticated operator authorization.
It also carries permanent blockers for all three limitations. Six downloader
invocations are a reviewed code-path contract, not proof that six network
exchanges occurred or that a particular operator authorized them.

The local hashes are unkeyed integrity checks. A party able to rewrite all
bundle files can coherently remove a synthetic marker, substitute the
built-in-policy labels, and recompute every local hash. The loader cannot
authenticate that historical execution claim from those bytes alone. It may
accept the rewritten bytes as structurally built-in-shaped, but the permanent
false gates and blockers keep that bundle nonadmitting and unusable for
forecast scoring or promotion. External publisher signatures, an independent
network witness or transparency record, authenticated operator identity, and
an out-of-band trusted pin would be separate future controls.

The runner creates a private deterministic
`.journal-<canonical-transaction-id>` before the first request. It writes and
syncs a start event before each downloader call. If the downloader returns a
bytes-or-string body, the runner immediately creates, syncs, and reads back
two complete raw-byte copies before obtaining the completion-clock value or
validating response metadata, HTTP status, redirects, proxy use, encoding,
media type, JSON schema, or receipt eligibility. A returned complete but
invalid response therefore remains in the crash journal. If the downloader
throws or returns no bytes-or-string body, there is no complete returned body
to preserve; the started event and immutable failure record state that case
without claiming raw preservation.

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
the authorized effective date, a revision token in `""|"r"`, and a supported
footnote token. Unknown fields, zero or duplicate EFFR rows, aliases,
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
  `BYTE_IDENTICAL_NO_REVISION_RECEIPT_CREATED`;
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

- frozen campaign, schedule, receipt-contract, and prospective-contract
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
- campaign status/phase/current-state rules; and
- canonical predecessor bytes, receipts, manifest, and transition semantics.

The local copies and self-generated hashes detect accidental corruption but
are not independent authentication, durable external storage, or an external
timestamp. The runner does not establish retention through 2031, an
independently attested host clock or transport, official holiday parsing,
approval of the draft prospective contract, or a complete campaign origin.
The output root is caller-selected and is not authenticated: a complete first
bundle can be copied under another root with the same canonical date/state
suffix and still has the same local integrity identity. Path checks use local
pathname inspection and no-follow/exclusive leaf creation; they are not a
proof against a concurrent same-user filesystem race. A transport exception
that never returns a complete body may also leave libcurl-held partial bytes
outside the journal. No scheduling workflow is installed by this directory.

## Hermetic verification

Run from the repository root:

```bash
julia --startup-file=no --depwarn=error --check-bounds=yes \
  --project=scripts/us \
  scripts/us/forecasting/vintages/effr/recurring_acquisition/test_effr_recurring_acquisition.jl
```

The same test can run from another working directory using absolute paths:

```bash
cd /tmp
julia --startup-file=no --depwarn=error --check-bounds=yes \
  --project=/absolute/path/to/scripts/us \
  /absolute/path/to/scripts/us/forecasting/vintages/effr/recurring_acquisition/test_effr_recurring_acquisition.jl
```

The 402-test hermetic suite uses only explicitly synthetic clocks, synthetic
downloaders, and temporary directories. Synthetic bundles are visibly marked,
rejected by default loading and campaign handoff, and never treated as
empirical captures. The suite covers dry-run/no-write behavior, exact requests,
schedule and clock boundaries, all completed statuses and invalid transitions,
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
provenance blockers, append-only publication, operator/campaign authorization
separation, and CLI argument and exit behavior.
