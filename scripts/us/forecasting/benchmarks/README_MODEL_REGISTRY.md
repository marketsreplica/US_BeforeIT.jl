# Benchmark model registry

`benchmark_model_registry.toml` is a fail-closed implementation registry, not
forecast evidence. Its execution scope keeps empirical forecasting and
production scoring disabled. The default loader verifies the exact bytes of
the benchmark kernel, separately registered implementation modules, and model
cards before it returns a registry.

The v1 inventory contains fifteen quarterly common-information models:

- no change, drift, historical mean, and seasonal-naive(4);
- fixed AR(1), fixed AR(4), and target-specific BIC AR(1:8);
- direct multi-step fixed AR(1), fixed AR(4), and target-and-horizon-specific
  BIC AR(1:8);
- fixed VAR(1), VAR(2), and VAR(3);
- the fixed-prior natural-conjugate BVAR(1) used by the current diagnostic;
- a fixed-parameter, non-DSGE quarterly semi-structural state-space model.

Every entry is limited to `quarterly_unconditional`. The naïve, AR, VAR, and
BVAR entries use the ordered eight-target Tier-1 panel and its primary
transformations. The semi-structural entry uses a separately registered
core-four panel; it cannot be run on the eight-target panel. Each entry states
its window, lag/hyperparameter rule, pandemic/ELB treatment, density
construction, fallback, and convergence policy. `published_forecast` remains
canonical protocol vocabulary, but no implementation in this registry may
claim that track.

The three direct AR records bind both `USForecastBenchmarks.jl` and
`direct_ar.jl`, plus the distinct `DIRECT_AR_MODEL_CARD.md`. Their
horizon-specific common-window BIC and selected-lag refit rules, origin-only
expanding information window, full aligned horizon-by-target residual
covariance plug-in density, exogenous-input rejection, and visible
rank/degrees-of-freedom gates are frozen in each record. Coefficient,
lag-selection, and covariance-estimation uncertainty are excluded. These
models receive no pandemic or ELB special treatment and make no dominance
claim over the iterated ARs.

`model_manifest_sha256(registry, model_id)` derives a model seal from the
complete model record and the exact artifact records it references. The seal
therefore changes when code, the shared card, or policy changes. Unsupported
and unregistered IDs, including VARX, are rejected rather than assigned a
nearby model's policy. VARX remains unregistered because its future
conditioning path requires a separate product and origin-eligibility contract.

## Semi-structural model card

The registered model is
`SemiStructuralSpec()` with target contract
`quarterly_core4_contract_v1`. The four model columns map exactly as follows:

| Protocol target | Protocol transformation and unit | Model input and unit |
|---|---|---|
| `real_gdp` | `annualized_qoq_log_growth`; percentage points at annual rate | `real_gdp_growth`; annualized quarter-over-quarter percent |
| `pce_price_index` | `annualized_qoq_log_inflation`; percentage points at annual rate | `pce_inflation`; annualized quarter-over-quarter percent |
| `unemployment_rate` | `percent_level`; percentage points | `unemployment_rate`; quarterly-average percent |
| `effective_federal_funds_rate` | `percentage_point_level`; percentage points | `effective_federal_funds_rate`; quarterly-average percent |

Every structural coefficient and the diagonal state, measurement, and initial
covariances are constructor-fixed and bound by the model-ID parameter digest.
There is no parameter selection or parameter fitting at an origin. The exact
Kalman filter updates only the latent-state distribution.

The point forecast propagates the terminal filtered-state mean. The density is
conditional on the fixed hyperparameters: it includes filtered-state,
process-shock, and measurement-shock uncertainty, but excludes parameter
uncertainty. It is not a full parameter-posterior density and is not a DSGE
model. The transition must have spectral radius below one; invalid
covariances, non-positive-definite innovation updates, non-finite outputs, or
target-contract mismatches produce a structured failure.

The current implementation has no ELB mechanism, regimes, stochastic
volatility, future exogenous conditioning, fiscal block, or foreign block. It
uses the observed EFFR column only. These are implementation limitations, not
claims that those mechanisms are economically irrelevant. The registry's
global gates keep empirical execution, production scoring, and origin
admission disabled.

## Resealing after an intentional code or card change

Artifact hashes are centralized under `[[artifacts]]`, so each changed source
or card file requires one SHA-256 update. After updating that hash, calculate the new
registry seal without running a forecast:

```sh
julia --project=scripts/us -e '
include("scripts/us/forecasting/benchmarks/USBenchmarkModelRegistry.jl")
using .USBenchmarkModelRegistry, TOML
path = "scripts/us/forecasting/benchmarks/benchmark_model_registry.toml"
registry = TOML.parsefile(path)
println(registry_content_sha256(registry))
'
```

Replace `registry_content_sha256` with the printed value and run:

```sh
julia --check-bounds=yes --project=scripts/us \
  scripts/us/forecasting/benchmarks/test_benchmark_model_registry.jl
```

This is an explicit review step; the validator intentionally has no function
that silently rewrites or approves its own trust anchors.

The canonical DSGE, factor/bridge/MIDAS, published-forecast, and conditional
scenario families remain absent. Add them only through an independently
reviewed registry update after their exact model IDs, panels, products, source
and card artifacts, density semantics, and convergence gates are frozen. A
placeholder or `DRAFT` model is rejected by the complete-whitelist validator.
