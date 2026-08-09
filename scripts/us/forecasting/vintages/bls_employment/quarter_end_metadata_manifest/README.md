# BLS Employment Situation 40-event metadata contract

This directory seals an offline route inventory for the 40 quarter-ending
Employment Situation releases from 2015Q1 through 2024Q4. It is metadata
only. It does not download an archive page, retain HTML or PDF bytes, parse a
table, create a quarterly observation, mutate the source inventory, admit a
forecast origin, or authorize empirical forecast execution.

The official
[BLS Employment Situation archive](https://www.bls.gov/bls/news-release/empsit.htm)
uses paired same-key HTML/PDF routes. The manifest binds the exact 40 keys,
reference months, release dates, and both official locators. Every reviewed
document states an 08:30 ET embargo. Each row preserves that basis as
`DOCUMENT_STATED_EMBARGO`, an RFC 3339 local timestamp under
`America/New_York`, and the offset-normalized UTC timestamp. The embargo is a
document-stated not-before threshold, not proof of the first byte's actual
delivery time.

## Provenance boundary

The contract keeps economic vintage and artifact provenance independent:

- all 40 rows are `UNKNOWN_REVISION_STATE`, because this directory extracts
  no target cell and therefore cannot assign a preliminary, benchmark, annual
  seasonal-adjustment, or population-control state;
- 39 surviving route pairs are
  `OFFICIAL_ARCHIVE_RECONSTRUCTION`, with
  `first_public_bytes_verified = false`; and
- 2019Q4 is `REISSUED_CORRECTED` and
  `TARGET_SCOPE_STATED_UNAFFECTED`, also with first-public verification
  false.

The official [December 2019 HTML](https://www.bls.gov/news.release/archives/empsit_01102020.htm)
and [PDF](https://www.bls.gov/news.release/archives/empsit_01102020.pdf)
state that BLS reissued the release to correct Table A-5 and that the release
text was unaffected. That statement supports the target-scope annotation for
headline unemployment/payroll research, but it does not establish bytewise
equality with the missing original artifact. The row is never normalized to
`FIRST_PUBLIC_BYTES_VERIFIED`.

The HTML route is registered as the future `PRIMARY_VALUE_SOURCE`; the PDF is
the future `PRIMARY_ARTIFACT_EVIDENCE`. Those roles describe the planned
independent extraction workflow and do not claim that either format has
already been captured or parsed.

The closed vocabularies exactly follow the project literature survey:

```text
economic_vintage_state:
  FIRST_PRELIMINARY
  SECOND_PRELIMINARY
  THIRD_SAMPLE_BASED
  ANNUAL_BENCHMARK_REVISED
  ANNUAL_SA_REVISED
  POPULATION_CONTROL_BREAK
  UNKNOWN_REVISION_STATE

artifact_provenance_state:
  FIRST_PUBLIC_BYTES_VERIFIED
  OFFICIAL_ARCHIVE_RECONSTRUCTION
  REISSUED_CORRECTED
  UNKNOWN_FIRST_STATE
  MISSING_ROUTE
  SKIPPED_NOT_PUBLISHED

source_role:
  PRIMARY_VALUE_SOURCE
  PRIMARY_ARTIFACT_EVIDENCE
  CROSSCHECK_ONLY
  NOT_USED
  QUARANTINED
```

Bare `Used` and `Other` are rejected. An unfamiliar revision flag remains
`UNKNOWN_REVISION_STATE`; an inadmissible source is `QUARANTINED`. Neither is
zeroed, guessed, or collapsed into an unscoped catch-all.

## Sealing and immutable API

`bls_employment_quarter_end_manifest_2015q1_2024q4.toml` self-hashes with
sorted, typed, length-aware canonicalization. Only
`artifact.content_sha256` is excluded from its own preimage; event order is
significant. `BLSQuarterEndMetadataManifest.jl` also pins that semantic
digest in compiled code. A caller cannot redefine the inventory by changing a
row and merely recomputing the TOML self-hash.

`validate_manifest`, `load_manifest`, and `manifest_artifact` return only
immutable named tuples, tuples, strings, integers, and Booleans. They never
return the mutable TOML dictionary or raw/canonical byte vectors under a
trusted digest. The module exposes a read-only digest calculation but no
stamping helper.

Every historical-first-state, availability, origin, execution, promotion,
production-scoring, and readiness gate is hard false. Tests reject any
attempt to enable one.

## Hermetic test

Run:

```sh
julia --startup-file=no --check-bounds=yes --depwarn=error \
  --project=scripts/us \
  scripts/us/forecasting/vintages/bls_employment/quarter_end_metadata_manifest/test_bls_quarter_end_metadata_manifest.jl
```

The test reads only local files. It performs no source request and does not
assert that today's route content is unchanged. Live route capture, exact
byte receipts, format-specific parsers, HTML/PDF reconciliation, CES
cross-checking, and quarterly aggregation require separately governed
artifacts.

## Official methods and literature basis

BLS's
[CES vintage-data documentation](https://www.bls.gov/web/empsit/cesvininfo.htm)
describes release-indexed payroll estimates, while its
[CES revision guidance](https://www.bls.gov/web/empsit/cesfaq.htm) explains
the two monthly revisions and annual benchmark process. The
[CPS seasonal-adjustment methodology](https://www.bls.gov/cps/seasonal-adjustment-methodology.htm)
documents annual seasonal-factor revisions and population-control breaks.
Those mechanics are why the contract refuses to infer an economic vintage
state from a route alone.

The design follows Fett,
[*Comparing with the original: a look at Current Employment Statistics
vintage data*](https://doi.org/10.21916/mlr.2015.12), Croushore and Stark's
[real-time dataset](https://doi.org/10.1016/S0304-4076(01)00072-0), Koenig,
Dolmas, and Piger's
[real-time-data analysis](https://doi.org/10.1162/003465303322369768), Stark
and Croushore's
[real-time forecasting study](https://doi.org/10.1016/S0164-0704(02)00062-9),
and Aruoba's evidence that
[data revisions are not well behaved](https://doi.org/10.1111/j.1538-4616.2008.00115.x).
Together they support explicit vintage labels and separate reporting by
truth vintage and artifact provenance rather than mixing reconstructed
archive values with verified first-public bytes.
