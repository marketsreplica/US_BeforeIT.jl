# Synthetic inference-calibration contract

This directory is the hermetic, synthetic-only preparation layer for the
exact-design calibration frozen in `US_FORECASTING_PLAN_WORK_LOG.md`. It
tests design primitives; it does not calibrate a block policy, inspect an
empirical score, or evaluate a forecasting model.

## Artifacts

- `calibration_protocol.toml` is the immutable, self-hashed protocol. Its
  semantic SHA-256 excludes only the digest field and is also compiled into
  `USForecastInferenceCalibration.jl`.
- `USForecastInferenceCalibration.jl` validates that protocol and provides
  score-blind geometry, deterministic seed, synthetic DGP, missingness,
  block-policy, exact-binomial, and shard primitives.
- `test_forecast_inference_calibration.jl` is a bounded, hermetic unit suite.
  Its tiny generated samples and low-level bootstrap-index draws are software
  tests, never calibration evidence.

There is deliberately no full calibration runner or result artifact. The
planned screening, final-validation, power, and sensitivity stages require
roughly 1,700–2,000 CPU-hours in aggregate and have not been launched.

## Score-field firewall and external acceptance pin

The package imports only the production
`../USForecastInference.jl` kernel. It does not import the revised-data
diagnostic, inspect a score table, read a forecast or truth artifact, or
create a historical origin.

A future historical geometry must be supplied as a separate TOML artifact.
`validate_score_blind_geometry` recursively rejects any field name containing
`forecast`, `truth`, `error`, `loss`, `score`, `rank`, `pvalue`, `p_value`,
or `effect` before validating the schema. The accepted schema contains only:

- origin identifiers, parsed UTC timestamps, and explicit origin quarters;
- target dates and mature horizons;
- model, target, and estimation-window eligibility;
- closed, externally reviewed regime assertions; and
- a score-blind SESOI registry identifier.

Target dates must be the exact calendar quarter end at each registered
horizon relative to the origin quarter. Origins and origin quarters must be
strictly increasing. Each row needs nonempty, sorted maturity and eligibility
sets. Maturity must be a downward-closed prefix of `(1, 2, 4, 8, 12)`;
eligibility arrays must preserve their registry order. Each row needs exactly
one label from each pandemic, NBER, and policy family.
Case-insensitive exact placeholder IDs—including `Used`, `Other`, and
`Unknown`—are fatal for geometry, model, SESOI, and origin identifiers. The
validated return is reconstructed as immutable named tuples and tuples and
does not expose the parsed TOML.

This field-name/schema firewall does **not** cryptographically prove that the
geometry was derived without looking at scores. Before an expensive stage,
the caller must supply an expected semantic SHA-256 from an independently
accepted registry or review channel. That external pin, not the digest
written inside the geometry file, is the acceptance boundary. Rewriting a
geometry and recomputing its internal digest therefore cannot authorize the
modified artifact under the earlier external pin.

The exact immutable geometry label
`EXTERNALLY_REVIEWED_SCORE_BLIND_ASSERTIONS` describes the regime-assignment
basis. The validator checks only that the pandemic, NBER, and policy labels
belong to closed mutually exclusive families. It does not reconstruct NBER
or FOMC/policy states from origin timestamps; that substantive review remains
upstream and is accepted here only through the externally supplied geometry
pin.

`execution_authorization("SMOKE")` is the only default authorization and is
explicitly non-evidentiary. Any expensive stage requires both
`explicit_expensive_mode = true` and a valid separate geometry file. Even
then, this checkpoint only returns an authorization receipt; it contains no
full simulation engine and creates no evidence. Smoke authorization rejects
both geometry paths and geometry pins.

## Frozen geometry and seed identity

The rehearsal geometry reproduces the score-blind counts from the protocol:

| Horizon | Expanding / rolling 40 | Rolling 60 |
|---:|---:|---:|
| 1 | 61 | 41 |
| 2 | 60 | 40 |
| 4 | 58 | 38 |
| 8 | 54 | 34 |
| 12 | 50 | 30 |

The joint intersections contain 50 and 30 origins, respectively.
`estimation_indices` implements expanding, rolling-40, and rolling-60
windows and guarantees that the final estimation index precedes the origin.

The master seed is `0x55534643414c4942` (`USFCALIB`). SHA-256 derivation is
domain separated:

- DGP seeds depend on stage, DGP, geometry ID, and outer-replication ID, but
  never on block policy. This preserves common random numbers.
- Bootstrap seeds additionally depend on the joint-family policy, but never
  on model, target, horizon, or loss family.

Shard identity depends on immutable replication IDs and a payload digest, not
on scheduling. Merging sorts deterministically and rejects duplicate,
missing, or unexpected replication IDs.

## Synthetic primitives

The package provides:

- a direct `N00_DIFF_IID` design whose standard-Gaussian hypothesis columns
  are fully independent with registered zero cross-hypothesis correlation;
- unit-variance, positive-semidefinite four-target factor covariance with the
  frozen signed loadings, plus the 70% common-factor stress;
- IID Gaussian, normalized AR(0.35), AR(0.75), standardized Student-t5,
  standardized Student-t3, and GARCH(1,1) primitives;
- a mandatory 2,000-observation burn-in for AR and GARCH cases;
- acute ninefold-variance, permanent fourfold-variance, and whole-sample-zero
  mean-reversal stresses;
- an exchangeable 11-model null forecast-error tensor with overlapping
  target innovations and strictly prior estimation windows; and
- squared and absolute differentials constructed exclusively through the
  production `USForecastInference.loss_differential`.

Student-t3 squared loss is hard-labeled an ineligible negative control because
its required fourth moment is undefined. Its absolute-loss case is also
ineligible as primary evidence and is labeled a boundary diagnostic only.

The missingness taxonomy is a Julia enum. No value is imputed:

- complete data, terminal maturity, a common four-origin outage, and a
  score-blind lagged-state mask have explicit behavior;
- target-specific gaps abort unless a global intersection was sealed first;
- model-execution failure aborts the primary family; and
- outcome-dependent masking is always forbidden.

Every missingness call must state a minimum retained-origin count of at least
two. The joint intersection aborts if it falls below that threshold, and
duplicate target-gap pairs are rejected.

The `SINGLE`, `TARGET5`, `MODEL20`, and `DENSE200` false-null masks contain
exactly 1, 5, 20, and 200 hypotheses.

## Block policies and exact binomial intervals

The four frozen joint policies are:

| ID | Requested length | Floor policy | Joint effective length |
|---|---:|---|---:|
| J01 | 1 | none | 1 |
| J02 | 4 | none | 4 |
| J03 | 4 | max horizon | 12 |
| J04 | 24 | none | 24 |

At a common seed, J03 generates exactly the same low-level stationary-
bootstrap indices as fixed length 12 with no floor, while retaining different
policy metadata.

The 200 hypothesis columns use the unambiguous IDs
`comparison1_...` through `comparison10_...`. `comparison1` maps challenger
tensor position 2 against comparator position 1; in general comparison `k`
maps challenger position `k + 1` against comparator position 1. Target then
horizon vary inside each comparison, and the immutable mapping records every
column and tensor position.

`clopper_pearson_interval`, `clopper_pearson_lower`, and
`clopper_pearson_upper` compute exact beta-inversion bounds. Tests bind them
to independent reference values, including zero and all-success boundaries.

## Gates and limitations

Every empirical-data, origin, promotion, production-scoring, readiness,
superiority, primary-policy-selection, and calibration-evidence gate in the
protocol is `false`.

This checkpoint does not:

- run any outer Monte Carlo replication;
- call studentized bootstrap inference or Romano–Wolf stepdown;
- select or validate J01–J04;
- establish size, coverage, strong FWER, or power;
- implement the future score-blind SESOI registry;
- prove that an externally accepted geometry was derived without viewing
  scores—the external review and pinning process remains upstream;
- emit a score, p-value, origin, promotion result, or production claim; or
- make an empirical forecast-accuracy statement.

## Verification

From the repository worktree:

```bash
julia --startup-file=no --project=scripts/us \
  --check-bounds=yes --depwarn=error \
  scripts/us/forecasting/inference/calibration/test_forecast_inference_calibration.jl
```

Formatting is checked with Runic 1.7.0:

```bash
runic --check \
  scripts/us/forecasting/inference/calibration/USForecastInferenceCalibration.jl \
  scripts/us/forecasting/inference/calibration/test_forecast_inference_calibration.jl
```
