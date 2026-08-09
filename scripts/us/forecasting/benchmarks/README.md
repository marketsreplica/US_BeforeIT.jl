# U.S. forecasting benchmark kernel

This directory contains the first hermetic WS-3B benchmark slice. It is
designed to be called by a later origin runner; it does not fetch data, inspect
truth, or choose a vintage.

`OriginData` is the information firewall. A caller must provide:

- an explicit origin identifier and ordered origin key;
- ordered training keys and target observations available at that origin;
- the exact ordered forecast keys;
- optional historical exogenous values and an equally explicit,
  origin-eligible future exogenous path.

There is intentionally no field for future target realizations. VARX fits only
on `x_train`; the adapter joins `x_train` and `x_future` only to satisfy the
repaired BeforeIT forecasting API after estimation.

Implemented reference models:

- random walk/no change;
- random walk with training-only drift;
- historical-average target;
- seasonal naive with a fixed period;
- iterated univariate AR, either fixed lag or target-specific BIC over a frozen
  candidate set on one common training-only comparison window;
- a fixed-hyperparameter natural-conjugate Bayesian VAR with a
  matrix-normal/inverse-Wishart posterior and coherent Minnesota-style
  own-first-lag shrinkage;
- fixed-lag adapters for the repaired BeforeIT VAR and VARX utilities.

Every model returns the same horizon-by-target point matrix and an optional
horizon-by-target-by-draw density cube. Density generation takes an explicit
integer seed and uses a local `MersenneTwister`; repeated runs with identical
inputs are bit-reproducible in the supported Julia environment. Failed
estimation is a structured `BenchmarkRun(status = :failed, ...)`, never a
missing row or an imputed forecast.

Run the focused hermetic suite from the repository root:

```sh
julia --project=scripts/us scripts/us/forecasting/benchmarks/test_benchmarks.jl
```

This kernel does not yet implement direct multi-step ARs, ARX lag/predictor
selection, forecast combinations, mixed-frequency models, non-conjugate BVAR
variants, or the semi-structural challenger. Those remain later WS-3B slices
and must use the same origin-bounded interface.

## Conjugate BVAR scope

`BVARSpec` fits only the target matrix in `OriginData.y_train`. For
`Y = XB + E`, it uses

```text
Sigma ~ IW(S0, nu0)
B | Sigma ~ MatrixNormal(B0, V0, Sigma)

Vn = (inv(V0) + X'X)^-1
Bn = Vn * (inv(V0) * B0 + X'Y)
nun = nu0 + T
Sn = S0 + (Y-XBn)'(Y-XBn) + (Bn-B0)'inv(V0)(Bn-B0)
```

The coefficient prior mean is one on each target's own first lag and zero
elsewhere. Lag-row variances decay with the fixed lag-decay and overall
tightness settings and are scaled using training-only mean squared first
differences. This is a frozen empirical-Bayes scale normalization: it never
uses forecast outcomes, and its rule and floor are model-id encoded. It
preserves natural conjugacy; it is not the
equation-specific, independent-normal Minnesota prior.

The deterministic point forecast recursively iterates `Bn`. Each predictive
path independently draws a full covariance from `IW(Sn, nun)`, then a complete
coefficient matrix conditional on that covariance, and finally correlated
innovations at every horizon. Thus density paths include parameter and joint
innovation uncertainty. All hyperparameters are constructor-fixed and encoded
exactly in the model identifier; there is no in-origin tuning.

Run its standalone analytic, simulation, leakage, and bounds suite with:

```sh
julia --check-bounds=yes --project=scripts/us \
  scripts/us/forecasting/benchmarks/test_bvar.jl
```
