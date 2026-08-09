# Core-three autoregressive benchmark candidate

This isolated component supplies transparent autoregressive comparators for the
three-observable small New Keynesian (NK) contract. Every model receives an
identical copied training matrix, identical ordered quarter keys, and identical
forecast-period labels. It cannot receive future target values or exogenous
inputs.

The candidate's maximum status is:

```text
CORE3_AUTOREGRESSIVE_MECHANICS_VALIDATED_NONADMITTING
```

It is not in the shared benchmark registry. It has no scoring operation, no
authenticated historical-origin binding, and no route to an accuracy,
suitability, promotion, production, or Poledna-parity claim. Its authored test
suite is mechanics evidence only; independent audit is still required.

## Closed target contract

The target panel is `quarterly_nk3_aggregate_pce_contract_v1`, in this exact
order:

| Candidate target | Pinned revised-fixture column | Unit |
|---|---|---|
| `real_gdp_growth` | `real_gdp` | annualized quarter-over-quarter percent |
| `pce_inflation` | `pce_price_index` | annualized quarter-over-quarter percent |
| `effective_federal_funds_rate` | `effective_federal_funds_rate` | quarterly-average percent |

The first two revised-fixture columns are already transformed rates; this
component does not log, difference, or annualize them a second time. The
renaming is explicit because the source fixture uses level-like column labels
for transformed values. The mapping matches the small-NK measurement contract;
it deliberately does not reuse the existing eight-variable VAR labels.

The optional diagnostic loader accepts only the exact quarantined 101-quarter
fixture from 2000Q3 through 2025Q3. It validates regular-file and no-hard-link
conditions, rejects any symbolic-link path component, reads bytes once across
stable file metadata, validates the manifest's false gates and exact schema,
and checks these identities:

```text
manifest SHA-256:        fc5209e35bb0d04986c2f8c96563f0c21ad511680753ecc7e6d77f0d8435fb3f
panel SHA-256:           f7bb26a467465937060b1e9e734a020b9158a8136db05d2e0df47c3bff851bbe
source receipts SHA-256: 14bab08bb573265e0affc878cedbbb8d4a0f8f5510fc59990f92d614f109d488
derived core-three hash: 905875dbbf7dea22850776d94ee9a1c4ec7d92fc96c6ba3608d00d83a1e9a477
```

`revised_core3_sample` copies only rows through the chosen origin index. It
uses later quarters solely as dimension labels and never copies their target
values into the sample. Before hashing, running, or validating any revised-track
sample, the component independently reloads the exact pinned files and requires
the training keys and observations to be the exact panel prefix, the origin ID
and key to identify that prefix's last row, and the forecast keys to be the
exact following labels. Observation comparison is bit-for-bit over the
`Float64` representation, and every embedded source identity must equal the
freshly loaded panel identity. Directly constructing a `Core3Sample`, altering
one cell, substituting an unrelated time span, or coordinating a new local
payload hash therefore cannot borrow the pinned source claims. Synthetic
samples remain a separate mechanics-only track with all source hashes absent.
All three models are then refit to that one sample.

This is not an honest real-time backtest: the source is a revised,
mixed-vintage current-release fixture whose historical release availability is
unverified. Consequently `origin_bound`, `origin_admissible`,
`scoring_eligible`, `empirical_accuracy_evidence`,
`forecast_suitability_evidence`, `promotion_eligible`,
`production_eligible`, and `registered_benchmark` remain false in every
forecast.

## Frozen model family

All models include an intercept, use exactly one lag, require at least 60
training quarters, and produce iterated recursive forecasts for at most 12
quarters. The lag and prior settings are fixed before an origin; there is no
origin-wise model or hyperparameter selection.

### Independent AR(1)

For each target `j`, the model fits

```text
y[t,j] = c[j] + phi[j] * y[t-1,j] + epsilon[t,j]
```

by full-rank OLS. Its plug-in innovation variance is residual sum of squares
divided by the target equation's residual degrees of freedom. Predictive
innovations are Gaussian and independent across targets. Coefficient and
variance uncertainty are omitted. This is the deliberately low-information
baseline.

### OLS VAR(1)

With `X = [1, y[t-1]']`, the model fits

```text
Y = X * B + E
E[t,:] ~ Normal(0, Sigma)
```

jointly by full-rank OLS. `Sigma` is the residual cross-product divided by
`rows(X) - columns(X)`. It must be positive definite under an exact Cholesky
factorization; there is no jitter, diagonal fallback, pseudoinverse, or hidden
regularization. Predictive paths use joint Gaussian innovations but omit
coefficient and covariance uncertainty.

### Fixed-prior MNIW BVAR(1)

The Bayesian VAR uses the proper natural-conjugate prior

```text
Sigma ~ inverse-Wishart(S0, nu0)
B | Sigma ~ matrix-Normal(B0, V0, Sigma)
```

with three variables, `nu0 = 3 + 2 = 5`, a zero coefficient mean (including
zero own-lag means), intercept row variance 100, overall lag tightness 0.2,
lag decay 1, and no hyperparameter tuning. For predictor `i`, its training-only
scale is

```text
s[i] = max(mean(diff(y[:,i]).^2), 1e-8)
V0[lag_i,lag_i] = 0.2^2 / s[i]
S0 = diag(s)
```

so the inverse-Wishart prior mean is `diag(s)`. This is an auditable
MNIW/Minnesota-style shrinkage construction, not the equation-specific
independent-normal Minnesota prior.

The word `stationary` in the model identifier has a narrow meaning: the
transformed observables are centered with a zero own-lag prior mean. The code
does not impose covariance stationarity, truncate unstable coefficient draws,
or silently replace them. It reports the posterior-mean companion spectral
radius; an unstable fitted mean or draw is retained unless it produces a
nonfinite forecast, which fails visibly.

The deterministic point path recursively iterates the posterior coefficient
mean. It is a plug-in path, not the exact multi-step posterior predictive mean.
For every predictive path, the density simulation independently draws one
full innovation covariance from the posterior inverse-Wishart distribution,
one complete coefficient matrix conditional on that covariance, and correlated
future innovations at each horizon. It therefore includes parameter,
covariance, cross-target, and future-shock uncertainty.

The BVAR follows the conjugate VAR framework developed and compared in
[Doan, Litterman, and Sims (1984)](https://doi.org/10.3386/w1202),
[Litterman (1986)](https://doi.org/10.1080/07350015.1986.10509491), and
[Kadiyala and Karlsson (1997)](https://doi.org/10.1002/%28SICI%291099-1255%28199703%2912%3A2%3C99%3A%3AAID-JAE429%3E3.0.CO%3B2-A).
The fixed shrinkage is intentionally much simpler than the large-BVAR
prior-tightness program in
[Bańbura, Giannone, and Reichlin (2010)](https://doi.org/10.1002/jae.1137).

The three model-contract hashes are:

```text
nk3_aggregate_pce_univariate_ar1_ols_v1
  0d33cbebb614794097f31f215fe8dd628a85120c0a198d429216bc37af771842
nk3_aggregate_pce_var1_ols_v1
  2860c9e0fe1e76e72e365cca1a93559d5adfb1b95755d27b3256ef48c987fc5c
nk3_aggregate_pce_bvar1_mniw_stationary_v1
  32c9c0c6409f521ba2e919b7bc2b36bc8a47e5217c5aedc6b0bbe019b6470fd6
```

## Forecast and density semantics

The AR and VAR point forecasts follow the standard reduced-form forecasting
use of autoregressions associated with
[Sims (1980)](https://doi.org/10.2307/1912017). Every density call takes an
explicit nonnegative integer seed. A SHA-256 domain separator derives an
independent local `MersenneTwister` seed for each model and path. No global RNG
is touched. This makes both properties exact for a fixed environment:

- increasing the number of paths preserves every earlier path; and
- increasing the horizon preserves every earlier horizon for every path.

Forecasts are iterated rather than separately estimated at each horizon. The
choice is frozen; the direct-versus-iterated tradeoff discussed by
[Marcellino, Stock, and Watson (2006)](https://doi.org/10.1016/j.jeconom.2005.07.020)
is not tuned on these data.

Each forecast is content-hashed over its sample identity, model-contract
identity, point and density arrays, diagnostics, blockers, and false gates.
`validate_forecast` then reruns the mechanics from the supplied sample, seed,
and draw count. These hashes establish local deterministic fixity only; they do
not authenticate data provenance or admit an origin.

## Tests and failure policy

The focused suite covers:

- exact target names, order, units, model identities, and frozen hashes;
- copied inputs and rejection of future targets and exogenous regressors;
- malformed quarter axes, target/order/unit/schema mismatches, nonfinite or
  Boolean observations, invalid horizon/seed/draw bounds, and inadequate
  training windows;
- strict revised-fixture hashes, mappings, prefixes, and quarantine gates;
- independent revised-sample rebinding that rejects altered cells, unrelated
  quarter axes carrying pinned hashes, and coordinated local rehashes before
  model execution;
- identical sample hashes across AR, VAR, and BVAR runs;
- full-rank design requirements and visible degenerate-variance/covariance
  failures;
- deterministic replay, recursive second-step identities, multi-path horizon
  prefixes, and path-count prefixes;
- coordinated content rehash, changed-training, and gate-elevation attacks;
  and
- unchanged shared registry hashes, absence of the new identifiers from those
  registries, no scoring export, and no filesystem-write or network path.

Run from the repository root:

```bash
julia --startup-file=no --check-bounds=yes --depwarn=error \
  --project=scripts/us \
  scripts/us/forecasting/benchmarks/core3_autoregressive/test_core3_autoregressive_benchmarks.jl
```

Run from an unrelated working directory:

```bash
cd /tmp
julia --startup-file=no --check-bounds=yes --depwarn=error \
  --project=/absolute/path/to/scripts/us \
  /absolute/path/to/scripts/us/forecasting/benchmarks/core3_autoregressive/test_core3_autoregressive_benchmarks.jl
```

## Claim ceiling and remaining origin binding

The current data support an honest revised-data mechanics diagnostic only.
They do not support a real-time empirical comparison. The small-NK component
is itself a fixed-parameter mechanics candidate with no empirical forecast
operation, so this family cannot yet claim a head-to-head NK result.

A successor may register these models only after an independently audited
origin adapter supplies authenticated, availability-bounded core-three samples
to both this family and an estimated small-NK successor. It must refit every
model independently at each origin, retain identical training rows and
horizons, bind first-release or otherwise predeclared truth vintages, and score
point and density forecasts under the common evaluation protocol. The current
models apply no explicit effective-lower-bound, unconventional-policy,
pandemic-outlier, stochastic-volatility, regime-switching, or structural-break
treatment. Those limitations must remain visible in any later interpretation.
