# Small New Keynesian DSGE mechanics

This isolated component implements the first, deliberately narrow equilibrium
mechanics slice in the U.S. forecasting plan. Its repaired bytes remain a
candidate pending independent re-audit. It is a three-observable
rational-expectations New Keynesian model adapted from the FRBNY v1.3.0
`AnSchorfheide` equations. It is not registered as a benchmark, does not read
the revised U.S. panel, and cannot forecast or score empirical data through the
project runner.

Its maximum status is:

```text
FIXED_PARAMETER_DSGE_MECHANICS_VALIDATED_NO_EMPIRICAL_EVIDENCE
```

## Scope

The canonical state vector is:

```text
y, pi, rate, y_lag, government_spending, technology_growth,
expected_y, expected_pi
```

The model has technology, government-spending/demand, and monetary-policy
innovations plus output and inflation expectational errors. The module builds
the exact eight-equation canonical system

```text
Gamma0*s_t = Gamma1*s_(t-1) + C + Psi*epsilon_t + Pi*eta_t
```

and solves it with a complex generalized-Schur implementation of the Sims
`gensys` subspace tests. Generalized roots are `T_ii/S_ii`; roots within
`1e-6` of the unit circle and coincident Schur zeros are rejected. Only
`eu == (1,1)` is accepted by the default solver.

The aggregate-PCE measurement adaptation is:

```text
annualized real GDP growth = 4*(gamma + y_t - y_(t-1) + z_t)
annualized PCE inflation   = pi_star + 4*pi_t
quarterly-average EFFR     = pi_star + r_annual + 4*gamma + 4*R_t
```

This differs from the source model's real-GDP-per-capita/CPI panel. It is
therefore an adaptation, not a replication. The existing semi-structural
LGSSM remains a separate non-DSGE model, while a full Smets--Wouters and
Poledna-parity comparator remains future work.

## What is tested

The test suite:

- reproduces the official FRBNY `AnSchorfheide()` `G1`, constant, impact, and
  existence/uniqueness reference to an absolute tolerance of `1e-12`, while
  bit-binding all 13 source parameters, the upstream tag/commit/source hashes,
  and the exact `1 + 1e-6` stake;
- checks canonical equation locations and finite uniform generalized-system
  scales from `1e-12` through `1e12` after one explicit whole-system
  normalization; Schur-zero, SVD-rank, and equation-residual tolerances are
  interpreted on that normalized system;
- rejects near-unit roots, coincident Schur zeros, indeterminacy, and
  nonexistence;
- verifies the aggregate-GDP/PCE/EFFR measurement identities and exactly zero
  base measurement error;
- computes stationary moments and a zero-jitter Kalman likelihood, requiring
  full-rank positive-definite innovation covariance at every observation;
- generates deterministic synthetic observations and coherent joint
  predictive paths with SHA-256-domain-separated per-path RNGs, so both the
  horizon prefix and the path-count prefix are invariant across calls;
- rejects malformed types, nonfinite observations, rank-deficient measurement
  maps, zero shock variances, indeterminate or malformed solutions, invalid
  filtered states, swapped correlated/noisy measurement systems, nonfinite
  derived builders, and horizons beyond 12 at every public operational
  boundary; and
- proves the mechanics class and target panel are absent from the benchmark
  registry and that this module exports no empirical `forecast` or `score`
  operation.

Run from the repository root:

```bash
julia --startup-file=no --check-bounds=yes --depwarn=error \
  --project=scripts/us \
  scripts/us/forecasting/benchmarks/small_nk_dsge/test_small_nk_dsge_mechanics.jl
```

## External reference and license

`frbny_gensys_reference.toml` is a reviewable IEEE-754 hexadecimal conversion
of the four datasets in the official 4,464-byte FRBNY v1.3.0
`test/reference/gensys.h5`. It records the upstream tag, commit, URLs, and
SHA-256 identities for the model, equilibrium conditions, measurement,
solver, test, and HDF5 fixture. Conversion preserves Julia's column-major
array order. The module and tests never fetch the network.

The solver follows the publicly documented Sims/FRBNY algorithm. The upstream
FRBNY code is BSD-3-Clause; the required notice is retained in `NOTICE.md`.

The first candidate was independently rejected even though its original
83/83 suite passed: five fixture parameters were not regression-bound, its
unqualified scale-invariance claim used absolute thresholds, downstream calls
accepted swapped invalid evidence, and a one-path test hid a multi-path RNG
prefix failure. The repaired contract addresses those findings directly; a
green authored suite is not an acceptance disposition.

## Claim ceiling and next stage

This component establishes only deterministic matrix construction, solution,
measurement, synthetic filtering, and predictive-path mechanics. It does not
establish parameter identification, posterior convergence, model adequacy,
historical information-set validity, empirical accuracy, superiority, or
forecast suitability.

Before registration, a successor must freeze normalized priors and
Jacobians; re-estimate independently at every origin from origin-only data;
use at least four chains with rank-normalized split-R-hat/ESS/MCSE gates;
generate posterior-predictive paths containing parameter, terminal-state, and
future-shock uncertainty; add panel-bound AR/VAR/BVAR competitors; and pass the
authenticated origin-receipt runner. The unconstrained linear model has no
ELB, shadow-rate, stochastic-volatility, pandemic-outlier, or
unconventional-policy block. All admission, scoring, promotion, production,
Poledna-parity, and suitability claims remain false.
