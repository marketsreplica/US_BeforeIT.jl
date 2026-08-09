# Philadelphia Fed RTDSM research diagnostics

This subtree implements a deliberately non-admitting research slice for five
current quarterly-vintage matrices from the Federal Reserve Bank of
Philadelphia Real-Time Data Set for Macroeconomists (RTDSM):
`NOUTPUT`, `ROUTPUT`, `P`, `PCON`, and `PCONX`.

The sealed
[`rtdsm_quarterly_profile.json`](rtdsm_quarterly_profile.json) fixes the exact
official routes, source semantics, rights boundary, mappings, and selected BEA
cross-checks. It is shared by:

- [`acquisition/`](acquisition/), the explicit live, five-file,
  research-only capture contract; and
- [`fingerprint/`](fingerprint/), the dependency-free OOXML parser and compact
  content-addressed semantic artifact.

Raw workbooks are stored only below the ignored local `data/us/raw/` tree.
They are neither committed nor redistributed. The checked-in fingerprint
contains hashes, dimensions, aggregate status counts, and ten selected cells;
it contains no full RTDSM row, vintage column, or matrix.

## Evidence boundary

RTDSM quarterly vintages are useful reconstructed information-set proxies,
but they do not prove intraday availability or the first bytes served at a
historical release. This subtree cannot create a strict forecast origin,
truth vintage, model input, empirical score, inventory mutation, production
artifact, readiness result, or accuracy claim.

Two mappings also fail closed:

- `P` is the modern GDP chain-type price index, not the protocol's GDP
  implicit price deflator; and
- `PCON` is the constructed ratio `100*NCON/RCON`, not BEA's direct
  chain-type PCE price index.

They are classified as `CONCEPT_MISMATCH`, never as unexplained
`SOURCE_CONFLICT`. The permitted result is limited to a research diagnostic;
all admission and execution gates remain false.

## Hermetic verification

From the repository root:

```sh
julia --startup-file=no --check-bounds=yes --project=scripts/us \
  scripts/us/forecasting/vintages/rtdsm/acquisition/test_rtdsm_quarterly_acquisition.jl

python3 \
  scripts/us/forecasting/vintages/rtdsm/fingerprint/test_fingerprint_rtdsm_ooxml.py
```
