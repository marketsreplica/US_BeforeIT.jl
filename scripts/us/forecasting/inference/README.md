# Forecast-comparison inference kernel

This directory contains a hermetic statistical kernel for a future,
pre-specified U.S. forecast-comparison experiment. It does not load forecast
data, select models, define regimes, or make an empirical accuracy claim.

## Upstream regime adjudication

[`regime_adjudication/`](regime_adjudication/) provides the bounded,
non-scoring ledger that must resolve or quarantine raw regime assertions
before a future score-blind geometry is sealed. It preserves every admitted
raw token with a parallel evidence reference, rejects surrounding whitespace
rather than normalizing it, keeps literal `Used`, `Other`, unknown,
provenance, and native BEA accounting labels outside the accepted regime
vocabulary, and produces observation-aligned masks separately for the
pandemic, NBER, and policy contrasts.

Its all-true full-sample mask is regime-only and must be conjoined with
separate score-cell eligibility. An unresolved label therefore does not alter
the full-sample primary analysis and excludes an observation only from the
affected regime contrast.

## Synthetic exact-design calibration preparation

[`calibration/`](calibration/) contains the separately sealed, synthetic-only
preparation contract for choosing a future stationary-bootstrap policy. It
freezes the candidate policies, synthetic DGPs, score-blind geometry schema,
domain-separated seeds, exact Clopper--Pearson bounds, missingness rules, and
shard identity. Expensive stages require an independently reviewed external
geometry digest; the internal geometry self-hash is not an acceptance pin.

That package has no full Monte Carlo runner and has selected no policy. Its
unit tests establish software behavior only; they create no size, coverage,
familywise-error, power, empirical-origin, promotion, or accuracy evidence.

## Direction and pairing contract

`loss_differential(challenger_errors, comparator_errors)` constructs

```text
d[t] = loss(challenger_error[t]) - loss(comparator_error[t])
```

for exactly paired forecast origins. Negative values favor the challenger.
The supported loss families are squared error (`:squared`) and absolute error
(`:absolute`). Pairing by origin, target date, truth vintage,
transformation, and availability state must be completed and audited before
calling this kernel.

The primary reference calculation, `hln_dm`, reports:

- the mean paired differential and paired count;
- a Bartlett HAC long-run variance through lag `h - 1`, with weight
  `1 - lag / h`;
- the Harvey--Leybourne--Newbold (HLN) correction;
- the corrected standard error and two-sided Student `t(n - 1)` p-value; and
- a two-sided confidence interval for the mean differential.

The confidence interval uses the standard error implied by the HLN statistic:
the uncorrected HAC standard error divided by the HLN multiplier. The module
implements the Student-t tail and critical value internally and imports only
Julia standard libraries.

## Stationary bootstrap

`studentized_stationary_bootstrap` accepts one matrix whose rows are forecast
origins and whose columns are hypotheses. One stationary-bootstrap index
draw is applied to every column in each replicate. This preserves the
observed same-origin dependence across models, targets, and horizons. Each
column is centered under its own null before resampling and studentized with
its horizon-specific Bartlett HAC/HLN standard error.

The RNG seed, block-length specification, and horizon-floor policy are
mandatory. The primary experiment remains fixed at 9,999 replicates.
Studentized inference refuses fewer than 999 replicates; 999 is only an API
resolution floor for tests or separately approved diagnostics, not a
replacement for the primary 9,999-replicate design. Low-level index
generation may use fewer draws because it does not itself perform inference.

```julia
include("USForecastInference.jl")
using .USForecastInference

bootstrap = studentized_stationary_bootstrap(
    origin_by_hypothesis_differentials,
    hypothesis_horizons;
    block_length = FixedBlockLength(4),
    horizon_floor_policy = :none,
    seed = 0x4d595df4d0f33173,
    replicates = 9_999,
)
```

The returned object retains both the joint origin-index draws and the
studentized bootstrap statistics for audit. Marginal p-values use
`(1 + exceedances) / (B + 1)`. Marginal confidence intervals are
equal-tailed studentized intervals; they are not simultaneous intervals.

The circular stationary bootstrap uses restart probability
`1 / expected_block_length`. `resolve_block_length` requires one of two
explicit policies:

- `horizon_floor_policy = :none` uses the requested expected length
  unchanged; or
- `horizon_floor_policy = :max_horizon` raises it to the largest horizon
  when necessary.

The result records the policy, requested length, optional floor, effective
length, and whether the explicit floor changed the request. An effective
length greater than the sample size is rejected rather than truncated.
There is deliberately no default policy.

Exact-design size calibration must choose and approve this policy before
scores are opened. In an independent synthetic `n = 50` null audit,
automatically imposing the maximum-horizon floor showed anti-conservative
behavior; therefore that floor is not assumed to be universally valid.
`:max_horizon` remains available only as an explicit, recorded design
choice.

### Plug-in block length is intake-only

This kernel deliberately does **not** implement the corrected
Politis--White/Patton--Politis--White automatic block-length estimator.
Implementing a look-alike rule without its full selection, flat-top
autocorrelation, truncation, and correction contract would create false
precision.

`ExternalPluginBlockLength` only accepts a numeric result computed by a
separately validated and sealed implementation. It requires a method ID and
provenance in the exact form `artifact-sha256:` followed by 64 lowercase
hexadecimal characters:

```julia
plugin = ExternalPluginBlockLength(
    5.7,
    "corrected_politis_white_external.v1",
    "artifact-sha256:" * repeat("a", 64),
)
```

The kernel does not verify the external estimator. Until that estimator is
implemented and tested, fixed expected block lengths are the supported
native sensitivity designs. Whether an `h` or `2h` sensitivity, or a joint
family spanning several horizons, receives a horizon floor must be chosen
explicitly and justified by the exact-design calibration.

## Romano--Wolf multiplicity control

`romano_wolf_stepdown` consumes the joint studentized bootstrap result and
applies a stepdown max-t procedure. It returns both unadjusted and
familywise-error-rate-adjusted resampling p-values. It rejects bootstrap
results with fewer than 999 replicates. Supported alternatives are:

- `:two_sided` for any predictive-accuracy difference;
- `:less` for the directional claim that the challenger has lower expected
  loss; and
- `:greater` for the opposite direction.

For the frozen challenger convention, use `:less`. Hypothesis IDs must be
unique and should be manifest-bound before scores are opened. Squared-loss
and absolute-loss hypotheses belong to separate pre-specified families.

```julia
adjusted = romano_wolf_stepdown(
    bootstrap;
    hypothesis_ids = frozen_hypothesis_ids,
    alternative = :less,
    alpha = 0.05,
)
```

The implementation null-centers every hypothesis, uses the same joint
stationary-bootstrap draws at every step, orders hypotheses by observed
evidence, takes the bootstrap maximum over the hypotheses still under
consideration, and monotonizes adjusted p-values along the stepdown path.
It uses the conservative finite-resample correction
`(1 + exceedances) / (B + 1)`.

## Fail-closed behavior and limits

The public functions throw on:

- unequal or empty pairs;
- Bool observations in error vectors, direct differential vectors, or
  differential matrices;
- non-finite errors or differentials;
- overflowed losses, differentials, covariance terms, statistics, or
  intervals;
- a horizon below one or not smaller than the sample size;
- a nonpositive or numerically degenerate HAC long-run variance;
- fewer than 999 inference replicates;
- a missing or invalid explicit horizon-floor policy;
- invalid confidence levels, significance levels, seeds, replicate counts,
  block lengths, plug-in provenance, or hypothesis IDs; and
- any bootstrap replicate/column that cannot be studentized.

These are computational validity checks, not a power guarantee. A
mathematically computable statistic can still be scientifically
uninformative in a short sample. The experiment must separately freeze
minimum sample and interpretation rules, and regime slices with very few
effective non-overlapping horizons must not receive superiority language.

Other boundaries:

- This is point-loss inference. It does not score forecast densities.
- The kernel does not decide whether models are nested and does not implement
  Clark--West, Giacomini--White, model-confidence-set, or
  forecast-breakdown tests.
- The bootstrap is stationary and circular; a moving-block implementation
  would be a separately labeled sensitivity.
- No missing values are dropped. Missingness and eligibility must be
  resolved upstream under the frozen pairing contract.
- `Used`, `Other`, source-conflict, and unknown provenance tokens are not
  statistical regimes and are not interpreted here.
- Reproducibility requires sealing the Julia version, this source hash, the
  seed, replicate count, hypothesis order, horizons, and block-length
  metadata.

## Literature

The implementation and its documented boundaries are based on:

- Diebold and Mariano,
  [Comparing Predictive Accuracy](https://doi.org/10.1080/07350015.1995.10524599);
- Harvey, Leybourne, and Newbold,
  [Testing the equality of prediction mean squared errors](https://doi.org/10.1016/S0169-2070(96)00719-4);
- Newey and West,
  [A Simple, Positive Semi-definite, Heteroskedasticity and Autocorrelation Consistent Covariance Matrix](https://doi.org/10.2307/1913610);
- Politis and Romano,
  [The Stationary Bootstrap](https://doi.org/10.1080/01621459.1994.10476870);
- Politis and White,
  [Automatic Block-Length Selection for the Dependent Bootstrap](https://doi.org/10.1081/ETC-120028836);
- Patton, Politis, and White,
  [Correction to Automatic Block-Length Selection for the Dependent Bootstrap](https://doi.org/10.1080/07474930802459016); and
- Romano and Wolf,
  [Exact and Approximate Stepdown Methods for Multiple Hypothesis Testing](https://doi.org/10.1111/j.1468-0262.2005.00615.x).

## Verification

Run the deterministic test suite from the repository worktree:

```bash
julia --project=scripts/us --check-bounds=yes --depwarn=error \
  scripts/us/forecasting/inference/test_forecast_inference.jl
```

The suite covers independent HLN/Bartlett formula reconstruction, the
Student-t reference, direction conventions, 9,999-replicate execution,
shared joint resampling, scaling invariance, seed determinism, column
permutation invariance, both horizon-floor policies, exact plug-in
provenance, low-resolution rejection, Bool rejection, one-hypothesis
stepdown equivalence, monotone adjusted p-values, and visible
input/degeneracy failures.
