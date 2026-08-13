# Quarantined revised-data target panel

This directory contains the deterministic eight-target input panel for the
Stage-2 U.S. revised-data benchmark diagnostic. It is a current/revised,
mixed-vintage data product. It is not bitemporal evidence, cannot admit a
forecast origin, is ineligible for promotion, and makes no claim about ABM
forecast accuracy.

The primary panel is `fixtures/quarterly_panel.csv`. It has 101 contiguous
quarters from 2000Q3 through 2025Q3 and the exact column order required by
`../USRevisedDataBenchmarkDiagnostic.jl`.

## Sources and transformations

- The five BEA targets come from the pinned 2026Q2 advance HMI7 content
  fingerprint. Real GDP, PCE prices, core PCE prices, the GDP deflator, and
  nominal GDP are each transformed as `400 * ln(level[t] / level[t-1])`.
- BLS CES series `CES0000000001` and CPS series `LNS14000000` come from three
  pinned Public Data API v2 responses: 2000–2009, 2010–2019, and 2020–2026.
  Payroll is `100 * ln(quarterly_mean[t] / quarterly_mean[t-1])`; unemployment
  is the mean of all three published monthly percent levels.
- EFFR comes from the official New York Fed `search.csv` endpoint. The target
  is the equal-weight mean of published Monday-through-Friday effective-date
  rates in each quarter. No weekends or holidays are invented.

The compact source extracts preserve the published values needed to reproduce
every panel cell offline. The larger raw response bytes remain under
`data/us/raw/forecasting/revised_data`; their hashes, URLs, selected headers,
capture timestamps, and observation counts are pinned in
`fixtures/source_receipts.json`.

## Complete-case boundary

BLS reports `LNS14000000` for October 2025 as unavailable (`-`) under footnote
9 because of the 2025 lapse in appropriations. BLS also states that it could
not produce reliable 2025Q4 quarterly estimates with one-third of the quarter
missing:

<https://www.bls.gov/cps/methods/2025-federal-government-shutdown-impact-cps.htm>

Accordingly, the primary complete-case panel stops at 2025Q3. It does not use
a November–December two-month mean and does not impute October. The source
extracts still retain later observations through 2026Q2 for auditability.

The New York Fed response also contains one Sunday-labelled row
(`2003-07-20`, rate `1.02`) whose fields other than effective date exactly
duplicate the adjacent Monday row (`2003-07-21`, rate `1.02`). Its existence
remains bound by the raw-response hash, but the normalized business-date source
extract excludes it without reassignment. The generator accepts only this
exact pair; another weekend row or any drift in either side fails closed.

## Build and verification

The ordinary build is offline and uses the already captured raw responses:

```sh
python3 scripts/us/forecasting/diagnostics/revised_data/build_fixture.py
```

A deliberate fresh BLS/New York Fed acquisition is:

```sh
python3 scripts/us/forecasting/diagnostics/revised_data/build_fixture.py --acquire
```

Run the fail-closed offline tests with:

```sh
python3 scripts/us/forecasting/diagnostics/revised_data/test_revised_panel.py
```

The test suite pins all tracked hashes, independently recomputes each
transformation class, verifies source boundaries and missing-token handling,
and proves that panel or promotion-flag mutations are rejected.

## Downstream benchmark diagnostic

From the repository root, run the frozen benchmark/scoring exercise with:

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/diagnostics/run_revised_data_benchmark_diagnostic.jl
```

The runner reloads this fixture through its pinned manifest/source-receipt
chain and writes research-only tables under
`output/us_forecasting/revised_data_diagnostic`. The diagnostic compares ten
naive, AR, VAR, and BVAR models, but contains no ABM or equilibrium forecast.
It cannot admit an origin, establish pseudo-real-time accuracy, or promote a
model.

The registered semi-structural comparator is exercised separately:

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --startup-file=no --check-bounds=yes --project=scripts/us \
  scripts/us/forecasting/diagnostics/test_revised_data_semi_structural_comparison.jl

JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/diagnostics/run_revised_data_semi_structural_comparison.jl
```

That diagnostic writes ignored tables below
`output/us_forecasting/revised_data_semi_structural_comparison` and scores all
eleven native-input models on the same four target/horizon/origin cells. See
`SEMI_STRUCTURAL_COMPARISON.md` for the model boundary, exact results, and
limitations. It remains a revised-data point-forecast diagnostic and does not
upgrade this panel to origin evidence.

The separate `ABM_ENGINEERING_QUALIFICATION.md` contract does not score this
panel or run an ABM. It qualifies only a past-sliced `2026Q1` input bundle,
registry-derived construction/simulation substreams for 32 paths,
runtime-checked serial/global-RNG declarations, and a failure-only engineering
manifest. Its strict offline tests are:

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --startup-file=no --depwarn=error --check-bounds=yes \
  --project=scripts/us \
  scripts/us/forecasting/diagnostics/test_revised_data_abm_engineering_diagnostic.jl
```

The contract permanently forbids class-H inputs, truth/forecast/score output,
inference, origin admission, promotion, and production registration.

## New York Fed notice

© 2026 Federal Reserve Bank of New York. Content from the New York Fed subject
to the Terms of Use at newyorkfed.org.

The Effective Federal Funds Rate data is subject to the Terms of Use posted at
newyorkfed.org. The New York Fed is not responsible for publication of the
Effective Federal Funds Rate data by BeforeIT, does not sanction or endorse
any particular republication, and has no liability for your use.

Modified/derived by BeforeIT: published daily EFFR observations are
equal-weight averaged by calendar quarter; no weekend observations are
imputed.

Terms: <https://www.newyorkfed.org/privacy/termsofuse>
