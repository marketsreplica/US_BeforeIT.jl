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

The legacy Economic-outlook exercise is an **engineering-only class-H
correction experiment**, not a structural calibration or a pseudo-real-time
forecast validation. It uses seven current-vintage one-quarter targets from
2024Q2--2025Q4 for fitting and reserves 2026Q1--Q2 as a two-observation
holdout. It evaluates 128 common-seed paths, fits Taylor-rule overrides and
seven damped output corrections, and always retains the uncorrected paths
alongside the corrected product.

Raw structural and nowcast artifacts never contain these overrides or output
corrections. `scripts/us/forecast_calibration.toml` is explicitly class H and
is ineligible for raw calibration. Existing pre-firewall artifacts can be
migrated deterministically from their preserved pre-override metadata:

```sh
julia --project=scripts/us scripts/us/migrate_calibration_firewall.jl
```

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

The proposed evaluation protocol is separate and remains pending independent
validation:

```sh
julia --project=scripts/us scripts/us/forecasting/test_protocol.jl
```

Its machine-readable contract is
`scripts/us/forecasting/protocol.toml`. It governs future vintage-clean
comparisons and does not retroactively validate the engineering exercise.

## Forecast-research contracts

The retained scientific contracts can be run independently; they mirror the
`us-science` CI job:

```sh
julia --project=. scripts/us/forecasting/variants/test_variants.jl
julia --project=scripts/us scripts/us/validation/test_bitemporal.jl
julia --project=scripts/us scripts/us/calibration/runtests.jl
julia --project=scripts/us scripts/us/accounting/test_supply_make.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us scripts/us/accounting/test_after_redefinitions_model_core.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us scripts/us/accounting/test_after_redefinitions_valuation_envelope.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us scripts/us/accounting/test_opening_accounting_candidate.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --startup-file=no --check-bounds=yes --project=scripts/us \
  scripts/us/accounting/test_portable_accounting_semantics.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us scripts/us/accounting/test_accounting_transition_harness.jl
julia --project=scripts/us scripts/us/forecasting/test_protocol.jl
julia --project=scripts/us scripts/us/forecasting/benchmarks/test_benchmarks.jl
julia --check-bounds=yes --project=scripts/us scripts/us/forecasting/benchmarks/test_benchmark_model_registry.jl
julia --check-bounds=yes --project=scripts/us scripts/us/forecasting/scoring/test_forecast_scores.jl
julia --check-bounds=yes --depwarn=error --project=scripts/us scripts/us/forecasting/inference/test_forecast_inference.jl
julia --check-bounds=yes --depwarn=error --project=scripts/us scripts/us/forecasting/inference/regime_adjudication/test_regime_adjudication_ledger.jl
julia --check-bounds=yes --depwarn=error --project=scripts/us scripts/us/forecasting/inference/calibration/test_forecast_inference_calibration.jl
julia --project=scripts/us scripts/us/forecasting/targets/test_target_coverage.jl
julia --check-bounds=yes --depwarn=error --project=scripts/us scripts/us/forecasting/targets/abm_gdp_operator/test_abm_gdp_operator_qualification.jl
```

They cover the paper/code variant crosswalk, exact as-of bitemporal
selection, the parameter/concept registry, source-aware supply/make and
valuation topology, the opening-accounting candidates and transition
semantics, the naive/AR/VAR/BVAR/semi-structural challenger library, the
frozen benchmark-model registry, the hermetic point/density score kernel,
the Diebold--Mariano/bootstrap inference kernel, and exact Tier-1/truth
coverage. Passing these engineering contracts is not a forecast-skill
result.

Further accounting diagnostics (the BEA requirements comparator, inventory
ledgers, `Used`/`Other` closure evidence, constrained Stone/GLS
qualification, and the Census M3 and OECD source-axis diagnostics) remain
in `scripts/us/accounting/` and run the same way; they are exercised on
demand rather than in CI.

The real-time vintage-capture, release-provenance, origin-package,
forecast-registry, and prospective-acquisition apparatus — the stage-3/4
pseudo-real-time machinery — is parked on the `governance-archive` branch
together with its CI wiring and evidence web. Main carries the revised-data
research platform only; resurrect the archive when a stage-2b result is
worth promoting to vintage-clean evidence.
## Quarantined revised-data benchmark diagnostic

The Stage-2 engineering diagnostic exercises the benchmark and scoring stack
on 101 complete-case quarters from 2000Q3 through 2025Q3. Its eight targets
are present-day/revised BEA, BLS, and New York Fed transformations. It is
explicitly a mixed-vintage snapshot, not an as-of-origin data panel. The
missing October 2025 CPS observation is not imputed, so the common panel stops
before 2025Q4.

Run the canonical one-thread diagnostic from the repository root:

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/diagnostics/run_revised_data_benchmark_diagnostic.jl
```

The command writes research-only outputs to
`output/us_forecasting/revised_data_diagnostic`. It compares no-change,
drift, historical-mean, AR(1), AR(4), AR-BIC(1:8), VAR(1)--VAR(3), and a
fixed-prior BVAR(1) at horizons 1, 2, 4, 8, and 12. Scores use cells common to
all models and are reported on both all-available and horizon-12-balanced
samples. The weighted ratios are macro-averages of 40 matched
target-by-horizon score ratios; they are not ratios of pooled losses.

The v2 diagnostic pins the fixture/receipt chain, complete model
specifications and cards, protocol, code, and Julia environment. It records
per-origin AR selections, VAR design conditioning and companion-root
stability, BVAR prior identity, and maximum forecast magnitude. Any model
failure suppresses aggregate ranking. The current deterministic run contains
22,640 forecast cells, 610 model-origin diagnostics, 800 score summaries, and
zero model failures.

This exercise includes neither the ABM nor an equilibrium benchmark. It adds
no forecast origin, cannot support a production accuracy claim, and is
ineligible for model promotion. Its purpose is to expose benchmark behavior
and harden the future vintage-clean evaluation path.

The companion core-four diagnostic adds the registered fixed-parameter
semi-structural state-space model:

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/diagnostics/run_revised_data_semi_structural_comparison.jl
```

It scores eleven models on identical real-GDP-growth, PCE-inflation,
unemployment, and EFFR realization cells. The statistical models retain their
registered eight-target input panel while the semi-structural model retains
its registered core-four input panel, so this is a native-input comparison,
not an identical-regressor experiment. In the deterministic revised-data run,
the semi-structural model ranks first on weighted RMSE: its ratio to VAR(1) is
`0.7488895447345775` on the all-available track and
`0.7445969022111804` on the balanced-horizon-12 track. Its corresponding MAE
ratios are `0.8856658629411573` and `0.8730449475542831`; AR(1), not the
semi-structural model, has the best weighted MAE.

An independent, explicitly unregistered stress calculation excluding
realizations from 2020Q1 through 2021Q4 materially changes that ranking: the
semi-structural RMSE ratio rises to about `0.985`--`0.997` and its RMSE rank
falls to fifth. This is not a formal alternative result; it demonstrates that
the headline advantage is pandemic/regime-sensitive and that a
literature-grounded regime policy must be frozen before inference.

These are point-forecast-only research diagnostics on a current/revised,
mixed-vintage panel. The comparator is equilibrium-oriented but is not a
DSGE model. No ABM forecast, strict historical origin, statistical
model-comparison inference, promotion score, or production accuracy claim is
included.

The separate `forecasting/benchmarks/small_nk_dsge/` component is now
independently accepted only as fixed-parameter equilibrium, measurement,
filter, and predictive-path mechanics. Its frozen module
`2750a95581ba83bdac8578ccdc2cd290a265fa1968d74ddc3d10cfc56e26248a`
and fixture
`ec0a4a891e49e518ab5e08b98fdeda6b828f1b611600a3ddf4e198d0c70bc89e`
reproduce the pinned FRBNY generalized-Schur oracle and the aggregate
real-GDP-growth/PCE-inflation/EFFR measurement system. Root and unrelated-CWD
suites each pass 224/224; independent adversarial checks also reject
indeterminate, malformed, nonfinite, noisy/correlated, invalid-filter, and
derived-overflow evidence. The component remains unregistered, reads no
empirical panel, estimates no origin-wise parameters, exports no empirical
forecast or score, and establishes no accuracy or forecasting suitability.
See `forecasting/benchmarks/small_nk_dsge/README.md`.

The matching `forecasting/benchmarks/core3_autoregressive/` component is
independently accepted only as nonadmitting AR(1), OLS VAR(1), and
fixed-prior MNIW BVAR(1) mechanics on the same aggregate-PCE core-three
contract. Its repaired module
`e8444761c55e199ab475eddca31a06c058b8fb2566ce721b186654190746f1c0`
reloads the pinned revised fixture and bit-binds every training prefix,
quarter key, origin, following forecast label, and source identity before
execution. Authored root and unrelated-CWD suites each pass 287/287; an
independent 977-case audit also rejected every single-bit training-cell
mutation and coordinated sample/forecast rehash. The component remains
unregistered and nonscoring, and establishes neither an authenticated
historical origin nor empirical accuracy or forecasting suitability. See
`forecasting/benchmarks/core3_autoregressive/README.md`.

An independently accepted descriptive comparison now runs those three
autoregressive mechanics and the fixed-parameter small-NK mechanics on the
same final-revised core-three prefixes. It uses 30 balanced origins from
2015Q2 through 2022Q3, one 12-quarter/500-path run per model-origin, and
extracts h=1/2/4/8/12 without restarting. Its bootstrap checks the exact
dependencies, Project, Manifest, active project, and LOAD_PATH before any
dependency include; every prefix and phase-two truth panel is independently
rebound to the pinned source, and complete attempt identities are replayed.
Independent root and unrelated-CWD suites pass 118/118 and reproduce result
`cd0cb535dfa023dd7d75d50783c259c378c88ad3d1b03fa5abbaf192e9a705cd`.
The fixed small-NK h=1 real-GDP RMSE is 59.226 percentage points with zero
50/80/95-percent coverage, versus BVAR RMSE 10.429; its h=1 joint energy score
is 18.753 versus 1.511 for BVAR. This is a severe calibration failure on the
declared revised panel, not an admitted real-time backtest. The whole panel is
materialized in the same process before prefix extraction, the design and
rankings are retrospectively exposed, small-NK parameters are fixed, and no
common ABM origin exists. Accordingly
`mathematical_scores_computed=true` but
`repository_scoring_eligible=false`; every accuracy, suitability,
confirmation, registration, promotion, and production gate remains false.
See `forecasting/diagnostics/core3_equilibrium_comparison/README.md`.

The quarantined ABM engineering qualification (a registry-bound pre-stage-2
gate) is parked on the `governance-archive` branch; the live ABM evidence is
the stage-2 comparison below.

## ABM stage-2 comparison (current entry points)

The stage-2 comparison scores the agent-based model against the ten
statistical benchmarks on the revised-data panel, in two variants: `v1`, the
model as shipped, and `v2`, the model initialised from the commodity-balance
reconciled artifact with random-walk-with-drift growth expectations. Results
and their labels are in [`../../US_ABM_FORECAST_REPORT.md`](../../US_ABM_FORECAST_REPORT.md)
and in `forecasting/diagnostics/abm_revised_comparison/RESULTS_V2.md`.

Build the reconciled calibration artifact (~40 s):

Instantiate the environment once per clone:

```sh
julia --project=scripts/us -e 'using Pkg; Pkg.instantiate()'
```

Rebuilding the reconciled calibration artifact is **optional** — it is committed, and
the shipped copy already matches the sha256 every `_v2` cache identity records
(`57e23f4a…`):

```sh
julia --project=scripts/us \
  scripts/us/calibration/reconcile_commodity_balance.jl \
  --mode=final_demand_scaled --expectations=rw_drift
```

Run an ensemble. The runner appends to `abm_ensemble_summaries.csv` after every
origin, so an interrupted run resumes and a completed run re-scores from cache
in seconds instead of re-simulating:

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/diagnostics/abm_revised_comparison/run_revised_data_abm_comparison.jl \
  <output-directory> [paths] [variant] [max-origins] \
  [--calibration=<path>] [--also-score=<dir>]
```

`variant` is one of `headline`, `burnin`, `burninN`, `outlook`, `headline_v2`
or `outlook_v2`. The `_v2` variants default to the reconciled artifact;
`--calibration` overrides that. `--also-score` takes a completed run's
directory and scores its ABM columns on the same common cells, which is how
the v1-versus-v2 table is produced in a single pass.

Committed outputs, one directory per run:

| directory | variant | contents |
|---|---|---|
| `output/us_forecasting/abm_revised_comparison/` | `headline` | v1 first-pass scores plus `RESULTS.md` |
| `output/us_forecasting/abm_revised_comparison_burnin{,4}/` | `burnin`, `burnin4` | opening-row burn-in sensitivity |
| `output/us_forecasting/abm_revised_comparison_outlook/` | `outlook` | v1 unscored current outlook |
| `output/us_forecasting/abm_v2_comparison/v1_headline/` | `headline` | v1 column of the joint v1/v2 run |
| `output/us_forecasting/abm_v2_comparison/v2_headline/` | `headline_v2` | joint v1/v2 scores and interval coverage |
| `output/us_forecasting/abm_v2_comparison_outlook/` | `outlook_v2` | v2 unscored current outlook |
| `output/us_forecasting/commodity_balance_reconciliation/` | — | RAS report and per-commodity table |

Every `manifest.toml` seals the comparison module's own sha256 in
`comparison_code_sha256`, so editing that module invalidates the seals and the
affected runs must be re-scored.

Render the tables. The third argument is the v1 run directory: it supplies the v1
rows of `abm_v2_interval_coverage.csv`, which are the v1 half of the interval-coverage
comparison. Omitting it silently leaves the coverage table with v2 rows only:

```sh
julia --project=scripts/us \
  scripts/us/forecasting/diagnostics/abm_revised_comparison/report_v2_comparison.jl \
  output/us_forecasting/abm_v2_comparison/v2_headline \
  output/us_forecasting/abm_v2_comparison_outlook \
  output/us_forecasting/abm_v2_comparison/v1_headline
```

`JULIA_NUM_THREADS=1` and `OPENBLAS_NUM_THREADS=1` pin the statistical benchmark
columns. `run_revised_data_benchmark_diagnostic.jl` throws an `ArgumentError` without
them; this ABM comparison runner only warns, so set them on every invocation.

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
