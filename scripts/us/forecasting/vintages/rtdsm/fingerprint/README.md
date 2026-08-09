# RTDSM quarterly semantic fingerprint

This directory fingerprints five current Philadelphia Fed Real-Time Data Set
for Macroeconomists (RTDSM) quarterly-vintage matrices:

- nominal GNP/GDP (`NOUTPUT`);
- real GNP/GDP (`ROUTPUT`);
- GNP/GDP chain-type price index (`P`);
- constructed PCE deflator (`PCON`); and
- core PCE price index (`PCONX`).

The official XLSX files remain outside Git. The checked-in artifact contains
raw, ZIP-member, relationship, worksheet, shared-string, style, semantic-grid,
and layout hashes; panel dimensions and aggregate cell-status counts; and only
ten selected cells needed for two BEA cross-checks. It contains no full RTDSM
row, vintage column, or extracted matrix.

## Evidence boundary

RTDSM is a curated historical information-set proxy. Its quarterly vintage
labels do not establish intraday availability or first-public bytes. This
artifact is therefore research-diagnostic evidence only. It is not a forecast
origin, truth artifact, model input, score, accuracy result, or authorization
to redistribute or train on RTDSM. All associated gates remain `false`.

Within this artifact, lowercase `used` is a typed provenance relation binding
each semantic cross-check to the exact BEA fingerprint it used. It is not a
status or regime. Bare `Used` and `Other` values are invalid in the provenance
schema; BEA's native `Used` and `Other` accounting commodities remain distinct
source concepts outside this RTDSM provenance namespace. Validation derives
the ordered reference-period-to-BEA-fingerprint mapping from the exact
SHA-pinned source profile; agreement between two mutable artifact fields is
not accepted as independent evidence of the binding.

The exact source profile is
[`../rtdsm_quarterly_profile.json`](../rtdsm_quarterly_profile.json). It binds
the official landing/download routes, source semantics, conservative use
rights, and two mandatory concept mismatches:

- RTDSM `P` is the chain-type GDP price index from the 1996 vintages onward,
  whereas the project target is the GDP implicit price deflator. See the
  [RTDSM `P` notes](https://www.philadelphiafed.org/-/media/FRBP/Assets/Surveys-And-Data/real-time-data/data-files/P/specific_documentation_P.pdf)
  and [BEA's implicit-deflator definition](https://www.bea.gov/help/faq/513).
- RTDSM `PCON` is constructed as `100*NCON/RCON`; it is not BEA's direct
  chain-type PCE price index. See the
  [RTDSM `PCON` notes](https://www.philadelphiafed.org/-/media/FRBP/Assets/Surveys-And-Data/real-time-data/data-files/PCON/specific_documentation_PCON.pdf).

Neither mismatch may be relabeled `SOURCE_CONFLICT`.

## Selected checks

The compact artifact binds the existing exact BEA HMI7 fingerprints for
2019Q4/RTDSM vintage 2020Q1 and 2021Q2/RTDSM vintage 2021Q3.

- Nominal and real GDP match after converting BEA millions to billions and
  rounding to RTDSM's reported one-decimal precision.
- Core PCE matches exactly at the reported decimal precision.
- The HMI7 implicit GDP deflator lies inside the closed interval implied by
  RTDSM's rounded nominal and real GDP levels.
- `PCON` differences are recorded only as noncomparable diagnostics.

There are three directly comparable targets, two forbidden direct concept
mappings, one separate derived-identity pass, and four of five targets
supported by a direct or derived check. All five are not directly comparable.

## Generate

Point `--raw-dir` to an absolute canonical directory containing exactly the
five profiled XLSX filenames:

```sh
python3 \
  scripts/us/forecasting/vintages/rtdsm/fingerprint/fingerprint_rtdsm_ooxml.py \
  --raw-dir /absolute/canonical/path/to/five/raw/workbooks
```

The dependency-free parser pins each input file descriptor, validates the
OOXML ZIP envelope, rejects unsafe or external content and formulas, verifies
the sheet/header/reference/vintage axes, distinguishes structural future
cells from explicit missing markers and unknown interior absences, and emits
a canonical content-addressed JSON artifact.

## Test

Tests are hermetic and make no network requests:

```sh
python3 \
  scripts/us/forecasting/vintages/rtdsm/fingerprint/test_fingerprint_rtdsm_ooxml.py
```

They cover profile drift, quarterly century rollover, missingness states,
unknown/undocumented tokens, formulas, external relationships, unsafe and
duplicate ZIP members, symlink/hardlink inputs, content-addressed publication,
hard-false gates, both concept mismatches, and exact nested provenance
validation. Negative mutations cover every provenance field, including bare
`Used`/`Other`, corrupted cross-check bindings and relations, and any policy
that would coerce an unknown value to zero. Coordinated changes to a
cross-check hash and its matching provenance hash, swapped period hashes, and
reordered `used` records are also rejected.
