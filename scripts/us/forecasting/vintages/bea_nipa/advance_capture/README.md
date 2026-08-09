# BEA HMI7 40-release present-day capture boundary

This directory implements the byte-capture step that follows the sealed
40-release metadata contract in `../advance_metadata_manifest/`. It can seal
one exact Section 1/Section 2 pair at a time. It does not bulk-download the 40
releases, modify a source inventory, or claim that bytes retrieved from BEA
today are the workbook bytes seen at a historical forecast origin.

The boundary is deliberately:

- **metadata-driven:** every release identity, case-sensitive archive path,
  filename, and direct URL comes from the compiled-pin validated metadata
  artifact;
- **one release at a time:** there is no bulk acquisition entry point;
- **transport-injected:** the module imports neither `Downloads` nor `HTTP`
  and has no default network implementation;
- **exact-byte preserving:** the raw response bodies and ordered, supplied
  request/response header name-value pairs are sealed;
- **content-addressed:** the two raw objects are named by their SHA-256
  digests and live inside a directory named by the receipt's semantic
  self-hash;
- **write-once:** installation uses an exclusive atomic directory rename,
  refuses overwrite, and makes bundle directories and files read-only;
- **hermetically testable:** the tests use synthetic OLE and OOXML fixtures
  and make no network requests.

## Present-day boundary

An HMI7 archive workbook retrieved now is a current observation of BEA's
retrospective archive. It is not proof of:

- the first state of the workbook at its release event;
- the workbook's historical publication or availability time;
- a strict real-time forecast origin;
- permission to execute an empirical forecast;
- promotion, production scoring, or readiness.

All corresponding receipt gates are permanently false. A present-day capture
also does not infer redistribution rights from a terms review.

The receipt self-hash detects accidental or unresealed modification; it is
not a digital signature, keyed MAC, trusted timestamp, authenticated operator
identity, or proof that an injected function actually used the network.
Capture metadata therefore uses
`source_mode_attested`, `terms_review_attested`, and
`attestation_authentication = UNAUTHENTICATED_LOCAL_PROCESS_ASSERTION`.
`network_transport_verified` is permanently false. Rewriting and rehashing a
local receipt can create only another unauthenticated assertion, never
authenticated transport evidence. False origin/readiness gates remain
schema-enforced even under such a rewrite.

## Exact URL derivation

`capture_plan(sequence)` loads and validates the sealed 40-row manifest, then
derives the two direct URLs from the exact `archive_path` and filenames. The
conversion changes path separators only; it never changes case or rewrites a
component. Consequently the audited 2014Q3 path remains:

```text
https://apps.bea.gov/HistData/Files/Releases/GDP_and_PI/2014/q3/Advance_October-30-2014/Section1all_xls.xls
```

The URL grammar rejects empty components, traversal, queries, fragments,
unknown hosts, and paths outside the official HMI7 release tree.

## Workbook validation

The first 24 release pairs use legacy `.xls`; the remaining 16 use `.xlsx`.
The capture contract requires:

- `application/vnd.ms-excel` plus an OLE Compound File envelope: signature,
  byte order, version/sector pairing, alignment, directory/FAT bounds,
  mini-FAT/DIFAT consistency, and unique header FAT-sector references for
  `.xls`;
- `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet` plus a
  bounded ZIP envelope for `.xlsx`: terminal EOCD, single-disk non-ZIP64
  central directory, safe unique names, matching local headers, bounded
  advertised expansion, and required `[Content_Types].xml`, `_rels/.rels`,
  and `xl/workbook.xml` entries;
- HTTP status 200, exact requested and effective official URLs, zero
  redirects, complete response headers, identity or absent content encoding,
  an exact `Content-Length` when supplied, and ordered millisecond UTC
  timestamps;
- 512 through 25,000,000 bytes per workbook, at most 64 response headers,
  bounded header names/values and URLs, and exactly two distinct raw-object
  digests.

These are structural envelope checks, not semantic spreadsheet parsing or
proof that target worksheets contain the expected concepts. That later step
requires a format-specific parser and content fingerprint.

The request header tuple is also fixed: the format-specific `Accept` value,
`Accept-Encoding: identity`, and the capture-contract user agent. An injected
fetcher must return those exact request headers in its `FetchResponse`.

## APIs

`import_present_day_pair` seals a fully described local pair and performs no
network access:

```julia
result = import_present_day_pair(
    sequence,
    absolute_raw_root,
    responses;
    observed_local_date = Date(2026, 8, 7),
    importer = "operator or import job identity",
)
```

`capture_present_day_with_fetcher` is the only live-oriented entry point. It
requires `live=true`, explicit terms review, a nonempty reviewer, and a review
date equal to the host's current local date before and after the injected
fetch. These checks govern the live function invocation; the persisted
receipt records them only as unauthenticated local-process attestations:

```julia
result = capture_present_day_with_fetcher(
    sequence,
    absolute_raw_root,
    fetcher;
    live = true,
    terms_reviewed = true,
    terms_reviewed_local_date = today(),
    reviewer = "reviewer identity",
)
```

The caller must review the current [BEA data-use
FAQ](https://www.bea.gov/index.php/help/faq/145) on every live-capture day.
The module does not cache or assume the result of a prior review. It also does
not supply a downloader: the injected fetcher is responsible for performing
one identity-encoded HTTPS GET for the immutable target it receives and
returning a `FetchResponse`.

`validate_capture_bundle` reopens a bundle and verifies its physical
inventory, read-only permissions, exact raw bytes, hashes, schema, metadata
pin, URL identity, headers, timings, limits, pair digest, receipt self-hash,
single-link files, and false gates. Its trusted return value contains only
named tuples, tuples, strings, numbers, and Booleans. It never exposes the
mutable parsed TOML dictionary or raw byte vectors under a trusted digest.

## Bundle layout

```text
receipt-sha256-<receipt digest>/
├── objects/
│   ├── sha256-<section 1 raw digest>.<xls|xlsx>
│   └── sha256-<section 2 raw digest>.<xls|xlsx>
└── receipt-self-sha256-<receipt digest>.toml
```

The receipt semantic hash uses sorted TOML serialization with only
`artifact.receipt_sha256` omitted. The physical receipt file has a separate
SHA-256. Array order is significant, preserving both workbook and header
order.

## Hermetic test

Run:

```sh
julia --startup-file=no --check-bounds=yes --depwarn=error \
  --project=scripts/us \
  scripts/us/forecasting/vintages/bea_nipa/advance_capture/test_bea_hmi7_advance_capture.jl
```

The suite covers all 40 derived plans, the lowercase `2014/q3` exception,
both file formats, local import, the injected live seam, same-day terms
review, size/header/redirect/host/path/time constraints, atomic idempotence,
read-only storage, hard-link aliases, byte tampering, fake ZIP/OLE envelopes,
numeric-to-Boolean/integer coercion, a transport-verification flip, and a
malicious gate flip with a recomputed self-hash.
