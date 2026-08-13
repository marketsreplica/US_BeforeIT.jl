# Immutable BEA NIPA workbook receipt state

This directory defines a narrow receipt-state contract for an atomic pair of
BEA HMI7 NIPA workbooks: published-main Sections 1 and 2 from one exact
release. A valid production receipt proves that exact local bytes were
retrieved together and observed at the recorded present-day acquisition
times. It does not prove when those bytes first became available historically.

Every valid receipt therefore keeps these states false:

- `historical_release_availability_verified`;
- `release_event_timestamp_verified`;
- `first_state_verified`;
- `origin_admissible`;
- `inventory_registered`; and
- `ready`.

Retrieval timestamps are provenance only. They cannot substitute for an
official release timestamp, historical availability evidence, or an origin
cutoff.

## Atomic receipt

A receipt contains exactly two workbook records, sorted as Section 1 then
Section 2. They must share one release ID, reference period, estimate label,
archive label, archive directory ID, and bounded capture transaction.
Validation is all-or-nothing: a missing, duplicated, or cross-release member
invalidates the receipt.

For each workbook, the validator binds:

- adjacent regular-file storage with no symbolic link;
- exact decoded byte count and SHA-256;
- content-addressed filename and XLS/OLE or XLSX/ZIP signature;
- requested and effective official `apps.bea.gov` URL with no redirect;
- URL year, quarter, archive component, filename, section, and extension;
- HTTP status, media type, Content-Length, ETag, Last-Modified, and
  Content-Disposition presence/absence state and observed value; and
- acquisition start, response-header, and completion timestamps at UTC second
  precision.

The builder serializes the pair endpoints to that exact second precision
before computing `observed_pair_span_seconds`. This makes the declared span,
the validator's parsed span, and the interval bounds identical even when a
live fetch API supplies fractional-second `DateTime` values.

The target-profile file is itself exact-byte hashed and canonically
content-hashed. Its release/profile assignment is checked against the pinned
BEA NIPA mapping audit. All five target mappings must match the audit's exact
mapping fingerprints, and production profile raw hashes and URLs must match
the audited workbooks.

The separate parsed-content fingerprint is an adjacent, canonical JSON file
whose exact bytes are SHA-256 bound by the receipt. The receipt also records
and checks the fingerprint schema version and exact parser SHA-256. The
validator requires the fingerprint's two workbook hashes and byte counts to
match the receipt pair, then recomputes all five mapping fingerprints from the
JSON target rows and compares them with the validated target profile. The
fingerprint, workbook, target, and receipt availability/admission/READY flags
must all remain false. This links parsed content to exact bytes and semantics
without turning any present-day observation into historical-availability or
origin-admission evidence.

Content-fingerprint v2 requires
`canonicalization = "utf8_sorted_keys_compact_json_lf"` and limits semantic
identity to raw workbook bytes, release/mapping identity, parsed values, and
parser bytes. The validator pins the exact v2 parser SHA-256, not merely its
version label. Execution-environment and repository-state metadata are
explicitly excluded and their inclusion flags must remain false. This keeps
the exact JSON hash stable across Python patch versions and repository commits
while the parser SHA remains part of the identity.

`receipt_state.schema.toml` records these rules in a compact declarative form.

## Programmatic API

`BEAWorkbookReceipts.jl` exposes:

- `WorkbookFetch`: one in-memory fetched workbook observation;
- `build_receipt`: construct and validate a receipt dictionary from exactly
  two `WorkbookFetch` values, an adjacent target-profile file, and an adjacent
  parsed-content fingerprint file;
- `validate_receipt` and `validate_receipt_file`: validate parsed or persisted
  receipts;
- `verify_local_raw_files`: independently re-read, decode, hash, and
  signature-check both local raw artifacts; and
- `validate_receipt_set`: reject duplicate receipt/transaction IDs, duplicate
  acquisition observations, and conflicting reuse of an exact raw SHA.

`build_receipt` does not write anything. The parent
`BEANIPAPilotReceipt.jl` / `live_acquire_2026q2_pilot.jl` driver persists the
profile, fingerprint, two raw files, and serialized receipt in a staged
directory, revalidates the complete local bundle, and atomically installs it.
No inventory mutation, origin admission, or promotion logic is implemented.

The receipt exact-byte-binds the complete parsed-content JSON and validates
its two raw workbook identities and five mappings. It does not independently
recompute every raw/published value-sequence digest from the observations or
derive the parser's semantic pair-bundle hash. Those are useful future
defense-in-depth checks; their absence cannot promote any state because the
entire fingerprint file is already immutable and every availability,
admission, inventory, and `READY` flag remains false.

Production receipts require `storage_encoding = "identity"`. The base64
storage mode exists only so small deterministic synthetic packages can remain
text fixtures.

## Hermetic fixtures and test

Run:

```sh
julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/bea_nipa/receipts/test_bea_workbook_receipts.jl
```

The two checked-in OOXML packages and compact parsed-content fingerprint
contain explicit synthetic markers. They are not downloaded BEA bytes, not a
live acquisition receipt, and not source evidence. The synthetic receipt,
profile, and fingerprint are rejected unless the caller explicitly passes
`allow_synthetic = true`. `fixtures/fixture_manifest.toml` pins every fixture
file and both decoded-raw hashes.

The tests cover exact-byte and profile validation, URL/HTTP metadata,
timestamp ordering, atomic-pair identity, constructor replay, missing files,
semantic tampering, noncanonical or stale fingerprint JSON, both fingerprint
workbook hashes, each of the five fingerprint mappings, stale manifest hashes,
and receipt-set ambiguity.
