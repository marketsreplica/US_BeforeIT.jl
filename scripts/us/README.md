# U.S. calibration pipeline

This application acquires the public BEA, Federal Reserve/FRED, BLS, Census
SUSB, QCEW, and USDA inputs used by the U.S. BeforeIT calibration. It keeps
downloaded responses immutable under `data/us/raw`, materializes curated
Parquet snapshots, stores the queryable ledger in
`data/us/db/us_calibration.duckdb`, and exports compact JLD2 calibration and
baseline artifacts.

The model sector system has 68 sectors. BEA Table 259 supplies 68 observed
commodity rows and 71 industry columns; the four retail industries (`441`,
`445`, `452`, and `4A0`) are aggregated to the observed retail commodity
`4A0`. The raw 68×71 data, the observed 68×68 aggregation, and the
column-controlled model bridge are all retained. No synthetic retail
commodity split is made.

From the repository root:

```sh
julia --project=scripts/us scripts/us/bootstrap.jl
julia --project=scripts/us scripts/us/us_pipeline.jl all
julia --project=scripts/us scripts/us/us_pipeline.jl status
julia --project=scripts/us scripts/us/test/runtests.jl
```

`BEA_API_KEY`, `FRED_API_KEY`, and `BLS_API_KEY` are read from the repository
`.env`. Credentials are never written to the database, logs, raw metadata, or
artifacts. Some BEA responses echo the request credential; the raw archiver
redacts that echoed field before persistence and records the redaction in the
sidecar metadata.

The validation ledger uses four statuses:

- `APPROVED`: the registered source, definition, units, shape, and tests pass.
- `DUBIOUS`: usable only with the stated proxy, allocation, or model bridge.
- `REJECTED`: a source or construction failed a validity gate.
- `MISSING`: no validated construction is available.

The complete per-source and per-parameter results are written to
`data/us/validation/DATA_CHECKLIST.md` and
`data/us/validation/TEST_LOG.md`.

## Economic-outlook calibration and back-test

The economic-outlook calibration starts from the 2024 Q4 structural artifact,
uses 2025 Q1--Q4 for fitting, and reserves 2026 Q1--Q2 as an untouched
holdout. It evaluates 128 common-seed simulation paths, optimizes the
Taylor-rule coefficients, and fits the explicitly recorded GDP and PCE
publication corrections from training observations only.

From the repository root:

```sh
julia --project=scripts/us scripts/us/forecasting/test_calibrate_outlook.jl
julia --project=scripts/us scripts/us/forecasting/calibrate_outlook.jl \
  --n-sims 128 --forecast-horizon 15
```

The frozen calibration contract is `scripts/us/forecast_calibration.toml`.
Quarterly scores, before/after metrics, parameters, corrections, forecast
paths, and the machine-readable summary are written to
`output/us_calibration`. The LaTeX source for the methodology report is
`reports/us_calibration/us_economy_calibration_report.tex`; its compiled PDF is
`output/pdf/us_economy_calibration_report.pdf`.

## Simulation Lab and Economy Explorer

The web application loads the structural and nowcast artifacts directly
through `BeforeIT.load_us_baseline`. From the repository root:

```sh
julia --project=apps/web -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=apps/web apps/web/src/server.jl
```

Open `http://127.0.0.1:8080`, select the U.S. 2026 Q1 nowcast, and run an
unconditional ensemble. The opening state is 2026 Q1 and the first forecast
quarter is 2026 Q2. A 23-quarter horizon ends in 2031 Q4.

The results workspace shows ensemble means and standard deviations. Standard
trace runs also persist one explicitly identified realization and link to the
Economy Complexity Explorer at `/explorer/?run=<run-id>`. U.S. charts and
traces use the 68-sector BEA Summary I-O classification and millions of U.S.
dollars.

The calibrated U.S. household consumption and housing propensities preserve
the official-data dissaving state even when their sum exceeds one. The web API
applies its combined-value constraint only when a user edits either propensity.
