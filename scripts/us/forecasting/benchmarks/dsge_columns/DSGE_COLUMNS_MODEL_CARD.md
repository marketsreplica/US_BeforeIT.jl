# Stage-2b DSGE scored columns — model card

Two equilibrium forecast columns for the Stage-2b revised-data comparison
(workstream 2b-1; frozen protocol
`scripts/us/forecasting/diagnostics/stage2b/STAGE2B_PROTOCOL.md`).

Both are **research diagnostic columns on the revised, mixed-vintage panel**:
`real_time = false`, `origin_admissible = false`, `promotion_eligible = false`.

## `dsge_small_nk`

* **Model.** The sealed An–Schorfheide-type small New Keynesian gensys
  mechanics (`../small_nk_dsge/USSmallNKDSGEMechanics.jl`, SHA-pinned,
  validated bit-tight against the FRBNY DSGE.jl v1.3.0 oracle). Three
  observables, eight states, three structural shocks.
* **Estimation.** Posterior mode (MAP) re-estimated at **every origin** on
  the origin-bounded frozen panel columns
  `[real_gdp, gdp_deflator, effective_federal_funds_rate]` (annualized
  percent). Priors: An–Schorfheide (2007, Table 2) with two documented
  modernizations — `pi_star ~ Gamma(4, 2)` (original `Gamma(7, 2)`; recentred
  for the post-2000 panel, which strengthens the challenger) and inverse-gamma
  hyperparameters `(s, nu) = (mean·√(2/π)·…, 4)` as coded. Optimizer:
  deterministic fixed-budget Nelder–Mead in transformed space, warm-started
  from the previous origin's mode (first origin from the sealed fixed
  calibration). Budgets: 6000 evaluations at the first origin, 3000 after.
* **Inflation observable.** The mechanics module's measurement labels its
  inflation observable "PCE"; this column feeds it **GDP-deflator inflation**
  so the column forecasts the headline pair directly. The mapping is
  semantic relabeling only; no equation changes.
* **Forecasts.** The sealed `draw_joint_predictive_paths` (500 paths,
  h = 1..12, deterministic seed `7_000_000 + origin_index`, SHA-domain-
  separated per-path RNG).

## `dsge_sw07`

* **Model.** Smets–Wouters (AER 2007), full linearized system with the
  flexible-price block (49 states, 7 shocks, 12 expectational errors),
  transcribed from the published replication (`Smets_Wouters_2007.mod`,
  Pfeifer collection) in `sw07_model.jl`. Solved by `generic_gensys` — a
  size-generic, verbatim transcription of the sealed validated solver,
  oracle-tested to reproduce it exactly on the small-NK system.
* **Data.** Seven observables (output/consumption/investment/real-wage
  growth per capita, demeaned log hours per capita, GDP-deflator inflation,
  federal funds rate), built by `build_sw07_panel.jl` from a fixed FRED
  retrieval (2026-08-17, SHA-pinned in `sw07_panel_provenance.toml`),
  **spliced to the frozen panel** for `dy`, `pinfobs`, `robs` from 2000Q3
  so estimation agrees with the scored truth wherever the panel covers the
  series. Estimation sample starts 1966Q1 (SW07 convention) and expands
  recursively through each origin. This uses pre-panel history and four
  observables the statistical family does not see — an information
  advantage **for the DSGE challenger**, disclosed wherever quoted.
* **Estimation.** Posterior mode at every origin; the 36 SW07 priors and
  bounds exactly as printed in the replication `estimated_params` block
  ("inverse gamma, mean 0.1, 2 df" coded as Sims inverse-gamma-1 with
  `s = 0.056419, nu = 2`). Warm-started Nelder–Mead, 8000 evaluations at
  the first origin, 2000 after. Convergence status is recorded per origin;
  `budget_exhausted` means the simplex spread had not reached 1e-7 —
  the mode is still the best point found and the warm-start chain keeps
  improving it across origins (observed: −952.1 at 2010Q2 vs −1091.0 at
  the published-mode start).
* **Forecasts.** Simulation from the filtered terminal state (terminal
  covariance + future structural shocks at the mode), 500 paths,
  h = 1..12, seed `8_000_000 + origin_index`. Per-capita growth is mapped
  to the aggregate target by adding the trailing-8-quarter mean of observed
  population growth (`CNP16OV`), held constant over the horizon.

## Shared conventions

* **Nominal GDP** per path: exact compounding
  `400·((1+r/400)(1+d/400) − 1)` of the real-growth and deflator draws.
* **EFFR** point/paths floored at 0 (naive ZLB truncation; favors the
  challenger in ELB-era cells).
* **Unemployment** cells come from a labeled **auxiliary Okun bridge**:
  per-origin OLS of the quarterly change in the unemployment rate on
  annualized real GDP growth, iterated over the simulated growth paths with
  Gaussian residual noise, floored at 0. This is outside both DSGE cores;
  it exists so the equilibrium columns cover the same five-target cell grid
  as the ABM and statistical columns. Every table quoting DSGE unemployment
  must carry this label.
* **Densities** carry filtered-state and future-shock uncertainty at the
  posterior mode; **no parameter uncertainty** (unlike the reference
  paper's full-Bayesian DSGE bands). Disclosed limitation.
* **No origin is silently dropped:** estimation failure falls back to the
  previous origin's mode (recorded `carried_forward`) or the fixed start
  (`fixed_fallback`); the realized statuses for both columns in the frozen
  run are 61/61 `converged` (small-NK) and 61/61 `budget_exhausted`
  (SW07), with zero fallbacks.
* **Registry note.** The frozen statistical benchmark registry
  (`benchmark_model_registry.toml`, `registry_status =
  "frozen_implementation_only"`) is intentionally unchanged; the DSGE
  columns are registered in the Stage-2b scorecard manifest with their own
  SHA-pinned provenance (`run_dsge_columns.jl` output `provenance.toml`).
