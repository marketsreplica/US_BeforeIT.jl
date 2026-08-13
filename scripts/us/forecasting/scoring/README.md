# U.S. forecast-score kernel

`USForecastScores.jl` is a hermetic mathematical kernel for the first
WS-3D score layer. It does not load forecasts, truth, origins, registries, or
source data and therefore cannot authorize an empirical evaluation.

Implemented scores:

- point: mean error, RMSE, MAE, median absolute error, and optional MASE;
- scalar probabilistic: quantile score, interval score, WIS, empirical-ensemble
  CRPS, interval coverage/width, empirical-PIT tie intervals, and Brier score;
- coherent multivariate ensembles: energy and variogram scores.

The error convention is `actual - forecast`, so positive mean error denotes
underprediction. Relative skill is `1 - model_loss / reference_loss`; the
percentage form matches the intended Poledna-style table grammar.

The density layer follows the strictly proper scoring-rule framework of
Gneiting and Raftery (2007),
<https://doi.org/10.1198/016214506000001437>. WIS follows Bracher, Ray,
Gneiting, and Reich (2021),
<https://doi.org/10.1371/journal.pcbi.1008618>. The joint scores follow
Gneiting et al. (2008), <https://doi.org/10.1007/s11749-008-0114-x>, and
Scheuerer and Hamill (2015),
<https://doi.org/10.1175/MWR-D-14-00269.1>.

## Fail-closed choices

- Missing and non-finite values are rejected; balanced/all-available sample
  construction belongs to the future score-record layer and must be visible.
- MASE requires a positive denominator derived from origin-eligible training
  data. The kernel cannot authenticate that provenance.
- WIS rejects crossing or nonnested central intervals, including a median
  outside any interval, instead of repairing them after truth is known.
- Energy and variogram scores require explicit component scales because the
  U.S. target panel mixes annualized growth, log points, and percentage-point
  levels. The variogram score additionally requires component centers because
  cross-component differences are not invariant to distinct location shifts.
  Centers and scales must be frozen from origin-eligible training data.
- Variogram weights are explicit, symmetric, nonnegative, and zero-diagonal;
  its positive order and all target/horizon weights must be frozen before
  evaluation. No favorable weighting or order may be selected after results
  are opened.
- Nonfinite score results are rejected explicitly. Point scores, MASE
  denominators, and WIS use fixed 4,608-bit intermediates and apply their
  sample-size denominators before converting to `Float64`. The bound is
  derived from Float64's exact `2^-1074` dyadic grid, the largest Julia vector
  length, squared-error accumulation, and WIS products; it retains low-order
  terms even when opposite-sign inputs span the complete Float64 exponent
  range. These kernels return finite values whenever their mathematical
  results are representable as `Float64`. The other kernels remain
  fail-closed on any nonfinite `Float64` intermediate as well as a nonfinite
  result.
- The empirical PIT exposes a tie interval and deterministic midpoint. A
  randomized PIT requires a separately sealed RNG rule and is not fabricated
  here.
- Ensemble CRPS and energy use the `M^2` empirical-distribution formula: the
  predictive draws define an equal-weight discrete distribution. They are not
  the finite-sample unbiased `U`-statistic variants. Model comparisons must
  freeze equal draw counts and report Monte Carlo uncertainty instead of
  changing that definition after results are visible.
- Log score is deliberately absent until a finite-ensemble density estimator,
  tail safeguard, and failure policy are preregistered.

This module does not yet implement score-record schemas, truth-vintage
authentication, Monte Carlo standard errors, HAC/block-bootstrap comparison
inference, conditional predictive-ability tests, Clark-West tests, a model
confidence set, or multiplicity control.

Run the focused tests with:

```sh
julia --project=. scripts/us/forecasting/scoring/test_forecast_scores.jl
```
