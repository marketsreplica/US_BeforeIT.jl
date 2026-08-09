# Benchmark model card — interface 0.1.0

## Purpose and evidence class

These models are common-information statistical challengers for U.S.
pseudo-real-time forecast evaluation. They are infrastructure, not forecast
evidence, until an approved vintage manifest and observation operator feed the
interface at every rolling origin.

## Frozen information contract

Targets are limited to `OriginData.y_train`, indexed no later than
`origin_key`. Forecast rows are aligned exactly to `forecast_keys`. Future
target truth cannot enter the interface. `x_future` is allowed only as an
explicit conditioning path that was eligible at the origin; it is never used
for parameter or lag selection. A realized ex-post path requires a distinct
product label outside this library.

## Specifications

| Model ID | Point rule | Density rule | Hyperparameters |
|---|---|---|---|
| `naive_no_change` | Last observation | Joint Gaussian training differences, recursively accumulated | None |
| `naive_drift` | Last observation plus mean training change | Joint Gaussian residual change, recursively accumulated | None |
| `naive_historical_mean` | Training mean | Joint Gaussian deviations around the mean | None |
| `naive_seasonal_s` | Seasonal random walk | Joint Gaussian seasonal differences, recursive | Fixed period `s` |
| `univariate_ar_bic_p…_{constant,no_constant}` | Iterated target-by-target AR | Independent Gaussian fitted innovations, recursive | BIC by target over the encoded candidates on one common training-only window |
| `bvar_mniw_v1_p…_{constant,no_constant}_tight…_decay…_own…_ivar…_iwoff…_iscale…_floor…_diffmse_scale` | Recursive plug-in path from the coefficient posterior mean | One inverse-Wishart covariance and conditional matrix-normal coefficient draw per path, plus joint Gaussian innovations per horizon | Fixed lag, intercept, tightness, lag decay, own-lag mean, intercept variance, inverse-Wishart degrees-of-freedom offset, innovation scale, and scale floor |
| `beforeit_var_p…_{constant,no_constant}` | Repaired BeforeIT VAR | Repaired joint-covariance stochastic recursion | Fixed encoded lag `p` and intercept choice |
| `beforeit_varx_p…_{constant,no_constant}` | Repaired BeforeIT VARX | Repaired joint-covariance stochastic recursion | Fixed encoded lag `p` and intercept choice, separate eligible future exogenous path |

For a fixed AR(1) or AR(4), construct `ARSpec(candidate_lags = [1])` or
`ARSpec(candidate_lags = [4])`. The current univariate implementation is
iterated. Direct multi-step regressions need a separately frozen selection and
density rule before they can be added.

Every model identifier encodes all implemented specification choices that can
change a forecast, including the complete AR lag grid and intercept choice.
This prevents two economically different estimates from colliding in the
forecast registry.

For `BVARSpec`, every floating-point hyperparameter is represented by its exact
16-digit IEEE-754 hexadecimal payload. The identifier also encodes the prior
version and the training-scale rule, preventing rounded decimal formatting
from creating registry collisions.

### Natural-conjugate BVAR prior

For `Y = XB + E`, with `m` targets and `T` usable training rows:

```text
Sigma ~ IW(S0, nu0)
B | Sigma ~ MatrixNormal(B0, V0, Sigma)

Vn = (inv(V0) + X'X)^-1
Bn = Vn * (inv(V0)B0 + X'Y)
nun = nu0 + T
Sn = S0 + (Y-XBn)'(Y-XBn) + (Bn-B0)'inv(V0)(Bn-B0)
```

The mean matrix `B0` is zero except for the own first lag of each target.
`V0` is diagonal: the intercept row uses the fixed intercept variance and a
lag-`l`, predictor-`j` row uses
`tightness^2 / (l^(2*lag_decay) * scale_variance[j])`.
`scale_variance[j]` is the larger of the training-only mean squared first
difference and the fixed floor.

This scale normalization is a deterministic training-only empirical-Bayes
rule. Its formula and floor are frozen in the model identifier; it is not
estimated against forecast outcomes.

`nu0 = m + iw_dof_offset` and
`S0 = (iw_dof_offset - 1) * innovation_scale * Diagonal(scale_variance)`.
The required offset of at least two makes the inverse-Wishart prior mean exist
and sets it to
`innovation_scale * Diagonal(scale_variance)`.

This is a coherent Minnesota-style restriction within a natural-conjugate
matrix-normal prior. It does not claim to reproduce a non-conjugate
equation-specific Minnesota prior. The point path iterates `Bn`; it is not the
Monte Carlo mean of nonlinear multi-step posterior paths. Density paths draw
both parameters and the full innovation covariance, but do not include
stochastic volatility, pandemic/ELB regimes, exogenous predictors, or tuned
hyperparameters.

The exact inverse-Wishart sampler uses the normal-Wishart construction and
therefore restricts the degrees of freedom and its configured offset to
integers.

## Failure and convergence policy

Constructor failures reject malformed origin boundaries before estimation.
Runtime validation and estimation failures remain visible in
`BenchmarkFailure` with a stable category, exception type, and message.
Downstream registries must retain these rows and must not replace a failure
with a naive forecast under the failed model's identifier.

The BVAR reports prior and posterior matrices, degrees of freedom, likelihood
design rank, and uncertainty rules in diagnostics. A proper positive-definite
prior regularizes a rank-deficient likelihood design; singular prior precision
or inverse-Wishart scale matrices fail visibly.

The VAR/VARX adapter exposes the fitted innovation covariance and residual
count in diagnostics. It relies on the repaired BeforeIT utilities for
coefficient estimation, lag recursion, positive-semidefinite covariance
handling, and stochastic innovation generation. This is an adapter model card,
not an independent reimplementation.

## Reproducibility and limitations

An explicit integer seed initializes a local `MersenneTwister`. Point forecasts
do not depend on that seed. Density draws are deterministic for the same code,
environment, origin sample, specification, draw count, and seed. Cross-version
bitwise reproducibility is not claimed until the environment lock is included
in the forecast registry.

This version does not address transformations, pandemic dummies, ELB handling,
rolling-window selection, direct forecasts, non-conjugate posterior
specifications, or publication-vintage eligibility. Those decisions belong to
the protocol, origin manifest, observation operator, and later frozen
model-card versions.
