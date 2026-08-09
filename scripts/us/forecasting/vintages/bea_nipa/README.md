# BEA NIPA HMI7 discovery and exact-byte pilot

This directory implements acquisition stage 1's first, deliberately narrow
slice. It discovers official BEA Historical Data HMI7 release directories,
archive directory IDs, and complete main section-workbook catalogs. It also
contains a fail-closed transport, semantic parser, target profile, historical-
availability audit, and immutable receipt contract for one exact 2026Q2
advance workbook pair. A separate metadata-driven boundary can seal one
present-day Section 1/Section 2 pair for any of 40 releases from 2011Q3
through 2021Q2. None of these artifacts installs a source release.

The official archive UI currently follows this metadata route:

1. `Fea_DisplayChildrenC/?HistMainId=7&getFiles=false&getDirs=true`
   lists HMI7 directories.
2. `UrlPath_getID/?UrlPath=...` maps a selected internal release path to a
   archive directory ID. The response body does not repeat the request path.
3. `getPath/<ID>` resolves that ID back to the internal path.
4. `Fea_DisplayChildrenC/?HistMainId=7&thePath=...&getFiles=true&getDirs=false`
   lists files under the selected release directory.

The parser requires the official `National Accounts (NIPA)` identity, HMI7
folder pattern, and a recognized NIPA estimate-label/date grammar. It
distinguishes release directories from year, quarter, custom, `_notes`, and
nested `UND` directories. Dates embedded in release labels are retained only
as `archive_label_date`; they are never treated as release or availability
timestamps. A live discovery session associates an archive directory ID with
a path only after resolving the ID back to the originally requested path.

## Current protocol selectors versus historical workbooks

| Target | Current protocol selector | Protocol-current expected section |
| --- | --- | --- |
| Nominal GDP | `T10105:1` | Section 1 |
| Real GDP | `T10106:1` | Section 1 |
| GDP deflator | `T10109:1` | Section 1 |
| PCE price index | `T20304:1` | Section 2 |
| Core PCE price index | `T20304:25` | Section 2 |

`protocol_to_hmi7_workbook_mapping.toml` versions current protocol selectors
and current expected sections only. Neither the current section nor current
line is a historical selector. An official-workbook audit found a pre-December
2003 layout in which several target concepts reside in Section 7 tables rather
than the later direct Section 1/2 tables. A separate older-release metadata
fixture also demonstrates that a release can expose Section 7 while omitting
Section 2 entirely.

For an arbitrary historical release, every workbook section remains
`UNRESOLVED_REQUIRES_VINTAGE_AWARE_CONTENT_VALIDATION`, and every historical
row remains
`UNVERIFIED_REQUIRES_VINTAGE_AWARE_CONTENT_VALIDATION`. The acquisition layer
must validate sheet, frequency, concept label, series code, units/base year,
line number, and reference-period column from each frozen workbook.

Target discovery records contain no workbook path or locator. The complete
discovered main-workbook catalog is emitted separately, including Section 7
and nonnumeric sections such as Section S when present. Missing protocol-
current Sections 1 or 2 never suppress a target discovery record.

For example, the 2007Q1 advance live path-to-ID and ID-to-path round trip
returned archive directory ID `12921`. Its independently discovered main
workbook catalog includes these Section 1 and Section 2 locators:

- `https://apps.bea.gov/HistData/Files/Releases/GDP_and_PI/2007/Q1/1.%20Advance_April-27-2007/Section1ALL_xls.xls`
- `https://apps.bea.gov/HistData/Files/Releases/GDP_and_PI/2007/Q1/1.%20Advance_April-27-2007/Section2ALL_xls.xls`

These are entries in the release-wide workbook catalog, not target-workbook
assignments, not exact historical observation selectors, not evidence that a
workbook contains a target sheet, not hashes of the release workbooks, and not
evidence of exact availability at any forecast origin. Target records
therefore always emit unresolved historical-section and row statuses,
`NOT_ACQUIRED`/`NOT_VERIFIED`, `origin_admissible = false`, and
`ready = false`.

## Exact 2026Q2 present-day pilot

The first exact-byte pilot is the 2026Q2 advance release. The transport pins
the direct official Section 1 and Section 2 URLs, exact byte counts, exact
SHA-256 values, XLSX media type, no-redirect effective URL, and OOXML
container signature. It validates both workbooks in memory before atomically
installing the pair below the ignored `data/us/raw` tree:

```text
raw bundle SHA-256:
9f4152937f58d777feb0f6562c1b1ca3681b0e51c1aa03b486fd5d29d1e794ff

Section 1:
4,056,562 bytes
ddcd0c5b693cb5d179198e67dda60f817e0e97196e6f1c158152971bbc80b136

Section 2:
4,870,580 bytes
1d5e3c6e177f6ba818bacf6361b3f21b7996e6cfdf55afb4d2a86a41bd2a4011
```

`pilot_2026q2_target_profile.toml` is the production, non-synthetic mapping
profile for those exact hashes. It binds the five targets to exact workbook,
section, sheet, table, published line, physical row, series code, frequency,
seasonal adjustment, unit, and base year. It remains non-admitting.

`fingerprint_2026q2_pilot.py` is a dependency-free, exact-release OOXML
parser. Before reading cells, it verifies both raw hashes, byte counts, ZIP
integrity, workbook structure, and required parts. It then validates the five
target mappings and all 318 quarterly columns from 1947Q1 through 2026Q2.
Raw XML number text and workbook-formatted published text are hashed
separately so binary floating-point lexical noise cannot silently change the
published observable. Content-fingerprint v2 deliberately excludes the
ambient Python version, platform, and repository HEAD from semantic identity;
the same parser and workbook bytes were verified to emit the same artifact
under Python 3.12.1 and 3.12.13. The generated JSON is stored under ignored
raw storage and remains a present-day content observation only.

`pilot_2026q2_availability_audit.toml` records the decisive negative result.
Independent Internet Archive captures prove that the BEA release PDF and
news page existed before the candidate origin, but neither capture includes
or hashes the two workbooks. Searches found no exact workbook capture.
Present-day server `Last-Modified` and `ETag` headers are post-origin
observations and are not independent historical evidence. Therefore exact
workbook-byte availability at `2026-07-31T14:00:00Z` is not proven, and
historical availability, first-state, origin admission, inventory
registration, and `READY` all remain false.

The immutable receipt contract is documented in `receipts/README.md`. A
receipt binds exact locally re-read raw bytes, HTTP metadata, ordered capture
timestamps, target-profile bytes, parsed-content fingerprint bytes, the
mapping audit, and all five target fingerprints. A receipt proves a
present-day observation—not historical availability.

## Forty-release present-day capture boundary

`advance_metadata_manifest/` seals the exact 40-release route inventory, and
`advance_capture/` derives all 80 direct workbook URLs from that compiled-pin
validated artifact. The capture module has no downloader and no bulk entry
point. It accepts one local pair or invokes a caller-supplied fetcher for one
pair after same-day BEA terms review.

The resulting content-addressed bundle preserves supplied headers, timings,
and exact bytes; validates bounded OLE/ZIP structural envelopes; uses an
exclusive atomic install; and rejects writable, symlinked, hard-linked,
colliding, or tampered objects. Its self-hash is an integrity checksum, not
authentication. Fetcher use, actor identity, and terms review are explicitly
`UNAUTHENTICATED_LOCAL_PROCESS_ASSERTION`, while
`network_transport_verified` and every historical/origin/execution/
promotion/production/readiness gate remain false.

This boundary creates reproducible present-day archive observations only.
Spreadsheet semantics, target mappings, historical first-state evidence, and
origin admission require separate governed artifacts.

## Hermetic test

Run:

```sh
julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/bea_nipa/test_bea_nipa_discovery.jl
julia --startup-file=no --depwarn=error --check-bounds=yes \
  --project=scripts/us \
  scripts/us/forecasting/vintages/bea_nipa/advance_metadata_manifest/test_bea_hmi7_advance_metadata_manifest.jl
julia --startup-file=no --depwarn=error --check-bounds=yes \
  --project=scripts/us \
  scripts/us/forecasting/vintages/bea_nipa/advance_capture/test_bea_hmi7_advance_capture.jl
julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/bea_nipa/test_bea_nipa_acquisition.jl
julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/bea_nipa/test_pilot_2026q2_target_profile.jl
julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/bea_nipa/test_pilot_2026q2_availability_audit.jl
python3 \
  scripts/us/forecasting/vintages/bea_nipa/test_fingerprint_2026q2_pilot.py
julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/bea_nipa/receipts/test_bea_workbook_receipts.jl
julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/bea_nipa/test_pilot_2026q2_present_day_receipt.jl
```

The checked-in JSON documents are normalized subsets of official responses,
not byte-identical raw HTTP captures. `fixtures/fixture_manifest.toml` records
that distinction and the SHA-256 of every fixture. No Excel release bytes are
included.

`live_observation_2026-08-05.toml` records the full request locators, effective
response URIs, and SHA-256 of each ephemeral raw metadata response from the
opt-in 2007Q1 probe. Requested and effective URIs must use HTTPS, the exact
`apps.bea.gov` host, and the default HTTPS port, without user information or a
fragment. The response bytes themselves are not checked in, so these hashes
are local audit notes rather than reproducible provenance. The observation is
explicitly non-admitting.

## Optional live metadata probe

Network access is explicit:

```sh
julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/bea_nipa/live_probe.jl \
  --live 2007 Q1 Advance
```

The probe prints response hashes, a complete main-workbook locator catalog,
and separate fail-closed target discovery records. It does not write files,
download the listed Excel workbooks, update
`current_inventory.toml`, establish an exact availability timestamp, admit an
origin, or produce a READY status. It is intentionally excluded from hermetic
CI.

The exact-byte live acquisition is also explicit and requires a same-UTC-day
BEA terms recheck:

```sh
julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/bea_nipa/live_acquire_2026q2_pilot.jl \
  --live --terms-reviewed-on YYYY-MM-DD
```

Raw workbooks and generated receipt bundles are intentionally ignored by Git.
The command is never run by hermetic CI and never mutates
`current_inventory.toml`.
