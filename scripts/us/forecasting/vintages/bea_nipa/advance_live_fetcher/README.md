# BEA HMI7 one-release-pair live binding

This directory adds a narrow, opt-in `Downloads` binding to the accepted
`../advance_capture/` boundary. It can retrieve exactly one of the 40 sealed
releases and exactly its Section 1/Section 2 workbook pair. It has no bulk
loop, retry, scheduler, source-inventory writer, admission path, empirical
forecast path, scoring path, or promotion path.

The accepted boundary remains authoritative for URL derivation, workbook
envelope validation, ordered request and response headers, exact body bytes,
receipt construction, content addressing, exclusive atomic installation,
read-only storage, revalidation, and permanently false origin/readiness gates.
This binding does not edit or redefine that boundary.

## Frozen inputs

The module checks every identity before it includes the accepted capture
source, then checks them again before every dry run or live request:

| Input | Exact SHA-256 |
|---|---|
| `../advance_capture/BEAHMI7AdvanceCapture.jl` | `6da4ad0bc4a458c05e6594448c23aea5c6ae3f25f743d74ae3507d27a8831339` |
| `../advance_metadata_manifest/BEAHMI7AdvanceMetadataManifest.jl` | `ffa254aca14a2d26b711a1ceb7e7ef2be60e703f0918db4b736e780df30b4039` |
| `../advance_metadata_manifest/bea_hmi7_advance_manifest_2011q3_2021q2.toml` (file) | `b785ee5eea5788f7c38a5de391e4173a376780ce48043e0444c37eb84502c607` |
| same metadata artifact (validated semantic content) | `186903041b649480b34a130f8c7518fb53a875e5b02ce4d6c3ee674080d5b824` |
| `scripts/us/Project.toml` | `72cec6cb6dc64dc71b9e342890b78afbf8fd66cb97dd8603e4fe905ad137dc1c` |
| `scripts/us/Manifest.toml` | `c2e596cf8452c5b890bb0ef66c05bc72a57fa25ab6f8fe790f8db4600b035263` |

Missing, symbolic-linked, hard-linked, noncanonical, or hash-mismatched files
fail closed before a downloader can be constructed. These pins establish a
closed local software configuration. They are not publisher signatures,
remote-code attestations, or independently witnessed provenance.

The reviewed authoring candidate is frozen at these exact local identities:

| Candidate artifact | Exact SHA-256 |
|---|---|
| `BEAHMI7AdvanceLiveFetcher.jl` | `a860c12543c9b8d6a815d82fa0dedb312944d9488169800303f4d248a0db05b6` |
| `capture_bea_hmi7_advance_pair.jl` | `36908b21bea00906ac5f77e018816d38fe6f0843fc7df7ce895731097675469e` |
| `test_bea_hmi7_advance_live_fetcher.jl` | `039a5dc6c84d208ee5270650f6b939e73a895ebbe7e6a1343fba0136bfabc6df` |

These candidate pins are review coordinates, not a self-authenticating
signature. If any candidate file changes, the table and independent review
must be regenerated together.

## Network-free dry run

Only `--sequence` is required. Without `--execute-live`, the CLI validates the
frozen inputs and prints the exact sequence, release identity, two direct URLs,
GET method, and ordered `Accept`, `Accept-Encoding`, and `User-Agent` headers:

```sh
julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/bea_nipa/advance_live_fetcher/capture_bea_hmi7_advance_pair.jl \
  --sequence 25
```

The dry-run path does not construct a downloader, invoke a callback, create a
raw root, or write a file. Its counters are fixed at zero.

## Explicit one-pair live command

Before a live command, review the current BEA data-use FAQ at the accepted
boundary's sealed locator, `https://www.bea.gov/index.php/help/faq/145`. The
review date must exactly equal the host's current local date and the reviewer
must be a nonempty, control-free local identity string:

```sh
julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/bea_nipa/advance_live_fetcher/capture_bea_hmi7_advance_pair.jl \
  --sequence 25 \
  --raw-root /absolute/canonical/existing/data/us/raw/forecasting/bea_hmi7/advance \
  --terms-reviewed-local-date YYYY-MM-DD \
  --reviewer "local reviewer identity" \
  --execute-live
```

`--execute-live` is a separate bounded authorization for this invocation only.
The CLI exposes no downloader, callback, clock, metadata path, URL, header,
output name, loop, or retry override. Sequence must be a canonical integer in
`1..40`; duplicates, unknown arguments, missing values, and noncanonical
integer spellings are rejected. The raw root must already exist and must be an
absolute, normalized, canonical, non-symlink directory. Filesystem roots are
forbidden.

The built-in transport performs one request for each immutable target, in
Section 1 then Section 2 order:

- HTTPS only, exact `apps.bea.gov/HistData/Files/Releases/GDP_and_PI/` path;
- exact `GET`, format-specific sealed `Accept`, `Accept-Encoding: identity`,
  and the accepted boundary's sealed `User-Agent`;
- redirects disabled with a zero-hop limit and exact requested/effective URL
  equality;
- ambient proxy disabled, `NO_PROXY=*`, netrc ignored, and cookies disabled;
- 60-second transfer timeout, a 25,000,000-byte libcurl file-size ceiling,
  an equally bounded streaming `IOBuffer`, and progress-limit checks;
- no request body, retry, redirect recovery, mirror, or fallback.

The complete body returned by `Downloads` is passed unchanged to
`capture_present_day_with_fetcher`. That accepted function structurally
validates and seals exactly one pair. Installation is exclusively
content-addressed: an existing identical final bundle is never overwritten
and is returned with `installed=false`; any conflicting or invalid object at
that content address fails revalidation. There is no coarser "sequence already
seen" rule and no overwrite path.

## Header and timestamp claim ceiling

`Downloads.request` exposes its final parsed response-header name/value vector
only after the body transfer completes. This binding preserves every exposed
final header pair in its returned order; it does not allowlist or sort them.
The API does not expose raw wire-header bytes, original optional whitespace,
or a separately authenticated socket-level header-arrival timestamp. Therefore
the receipt conservatively records the post-body observation time as both
`response_headers_at_utc` and `response_body_completed_at_utc`. The exact
effective URL comes from the returned `Downloads.Response`.

Those response fields, the direct-transport label, request count, reviewer,
host-local date, and UTC clock are unauthenticated local-process assertions.
They are useful reproducibility and integrity evidence, not an independent
network witness, operator authentication, trusted timestamp, or proof of the
historical first state.

Every historical-availability, strict-origin, empirical-execution,
source-inventory-mutation, promotion, production-scoring, and readiness gate
remains false. Present-day archive retrieval cannot establish what workbook
bytes existed at a historical forecast origin.

## Hermetic test

```sh
julia --startup-file=no --check-bounds=yes --depwarn=error \
  --project=scripts/us \
  scripts/us/forecasting/vintages/bea_nipa/advance_live_fetcher/test_bea_hmi7_advance_live_fetcher.jl
```

The suite uses only an internal inert request callback and generated pure-data
OOXML envelopes. It performs no network request and never writes below
`data/us/raw`. It covers all 40 dry-run plans, exact URLs and headers, CLI
types/duplicates/unknown arguments, transport-control inspection, conservative
timestamps, full exposed header order, byte ceilings, response and clock
failures, pre-request terms/root/reviewer checks, source tampering, the exact
two-callback ceiling, content-addressed duplicate non-overwrite, and the
absence of a callback argument from both the public live API and CLI.
