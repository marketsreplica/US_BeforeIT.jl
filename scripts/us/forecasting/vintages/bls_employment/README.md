# BLS Employment Situation provenance boundaries

This directory contains two non-admitting boundaries:

- a fail-closed, present-day import contract for one exact official BLS
  Employment Situation archive PDF; and
- an offline, sealed 40-event route inventory for the quarter-ending
  releases from 2015Q1 through 2024Q4 in
  `quarter_end_metadata_manifest/`.

The byte importer accepts a local file already downloaded through a browser;
it does not implement a network client. The 40-event contract stores
metadata only: it downloads no route, parses no target value, and keeps
economic-vintage state separate from surviving-artifact provenance.

The pinned artifact is:

- URL:
  `https://www.bls.gov/news.release/archives/empsit_01102020.pdf`
- reference period: December 2019
- byte count: `356586`
- SHA-256:
  `e9005e394f25ad62315817fcada7bfff102442290a995a13417f82f027ceb066`

The importer requires the exact URL-bound identity above, exact bytes, a
`%PDF-1.x` header, and a terminal `%%EOF`. It stores the raw PDF and its
receipt in separate content-addressed directories below the caller's ignored
`data/us/raw` root. Existing objects are accepted only when the directory has
the exact expected file set and bytes. Symlinked inputs, roots, internal
directories, object directories, and object files are refused, including
paths that traverse a symlinked ancestor. Callers must supply canonical local
paths (on macOS, for example, use `/private/tmp/...` rather than `/tmp/...`).

This exact PDF is not the historical first state. Page 1 declares that it was
reissued on February 21, 2020 to correct table A-5; its PDF metadata declares
`/CreationDate D:20200106100753-05'00'` and
`/ModDate D:20200220142443-05'00'`. The receipt binds those inspected fields
to the exact raw hash and labels the document
`REISSUED_CORRECTED_NOT_HISTORICAL_FIRST_STATE`.

The PDF's +145 thousand payroll change and 3.5 percent unemployment rate are
retained in the receipt only as manually inspected diagnostic annotations.
They are not parsed observations, transformation inputs, origin values, or
forecast-scoring data.

## Evidence boundary

The receipt records an operator-asserted time at which the browser download
was observed locally and a separate local-import interval. Those retrieval
observations are not the release's embargo time, publication time, or
historical first-state time. This contract deliberately stores:

- `release_stated_embargo_time = "NOT_EXTRACTED_NOT_VERIFIED"`
- `release_stated_public_time = "NOT_EXTRACTED_NOT_VERIFIED"`
- `release_event_timestamp_utc = "UNKNOWN_NOT_INFERRED"`
- `release_time_inferred_from_browser_capture = false`

The receipt self-hash binds every receipt field except the self-hash itself.
The following gates are hard-false in constructors and validators:

- `historical_first_state_verified`
- `historical_availability_verified`
- `origin_admissible`
- `empirical_execution_allowed`
- `inventory_mutation_authorized`
- `ready`

Accordingly, this is only a present-day archive-byte observation. It neither
registers an origin nor writes `current_inventory.toml`.

## Terms boundary

The receipt cites the official
[BLS copyright page](https://www.bls.gov/opub/copyright-information.htm) and
[BLS API terms](https://www.bls.gov/developers/termsOfService.htm). BLS states
that its publications are public domain except for previously copyrighted
photographs and illustrations and asks users to cite BLS. The BLS emblem is a
registered trademark and is not authorized for reuse. The API-specific
retrieval citation rule is recorded as not applicable because this contract
imports a direct archive PDF downloaded with a browser, not an API response.

Capture does not authorize redistribution. A file-specific image review is
still required before redistribution, and the raw PDF must not be represented
as modified BLS content. The CLI requires an explicit terms-review date equal
to the host's local date at import.

The exported importer is sealed to the pinned January 2020 expectation and
uses the live host-local and UTC clocks. Alternate identities and caller-set
clock values are not accepted at the public API boundary; deterministic clock
and synthetic identity injection exists only in the internal test seam.

## Test

Both suites are hermetic. The byte-capture suite uses only explicit synthetic
PDF bytes:

```sh
julia --startup-file=no --check-bounds=yes --project=scripts/us \
  scripts/us/forecasting/vintages/bls_employment/test_bls_employment_archive_capture.jl
julia --startup-file=no --check-bounds=yes --depwarn=error \
  --project=scripts/us \
  scripts/us/forecasting/vintages/bls_employment/quarter_end_metadata_manifest/test_bls_quarter_end_metadata_manifest.jl
```

## Opt-in local import

After reviewing the two terms pages on the same local date:

```sh
julia --startup-file=no --check-bounds=yes --project=scripts/us \
  scripts/us/forecasting/vintages/bls_employment/import_local_browser_capture.jl \
  --input /absolute/path/to/empsit_01102020.pdf \
  --raw-root /absolute/path/to/data/us/raw \
  --terms-reviewed-local-date YYYY-MM-DD \
  --browser-download-observed-at-utc YYYY-MM-DDTHH:MM:SSZ \
  --live
```

The browser observation timestamp is an operator assertion that the local file
was present after browser download. It must not be copied into any release-time
or historical-availability field.
