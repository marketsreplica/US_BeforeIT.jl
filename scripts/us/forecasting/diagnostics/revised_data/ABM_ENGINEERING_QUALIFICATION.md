# Quarantined ABM engineering qualification

This contract prepares one origin-bounded input bundle and deterministic path
seed plan for a future U.S. BeforeIT ABM runner. It deliberately does not run
an ensemble, emit a forecast, read a realization, calculate a score, conduct
inference, admit an origin, register a production artifact, or support an
accuracy claim.

The only contracted origin is `2026Q1`; the four engineering horizons would
map to `2026Q2` through `2027Q1`. The source material is current/revised and
mixed-vintage. The permanent information track is therefore
`revised_mixed_vintage_diagnostic`, with all of the following fixed:

```toml
origin_admissible = false
promotion_eligible = false
confirmatory = false
truth_blind = false
class_h_allowed = false
production_registry_allowed = false
```

`truth_blind = false` describes the surrounding revised-data research
environment; it is not permission to use truth in a forecast. The kernel has
no explicit truth argument and emits no input values or forecast values, but
the semantic isolation of truth inside arbitrary calibration dictionaries is
not yet verified. The protocol therefore fixes
`input_truth_isolation_verified = false` and
`input_lineage_verified = false`.

## Leakage firewall

`get_params_and_initial_conditions` currently constructs `C_G`, `C_E`, and
`Y_I` from the estimation start through as many post-origin quarters as are
available. That is convenient for simulation, but a monolithic calibration
artifact can therefore contain values dated after a historical origin.

`USRevisedDataABMEngineeringDiagnostic.sanitize_origin_inputs` requires an
explicit quarterly date vector for every *declared* dynamic series and retains
only the prefix ending at the origin. `C_G`, `C_E`, and `Y_I` are mandatory
dynamic series. The qualified-input hash is computed after this slice, so
changing a post-origin value in a declared dynamic series cannot change the
hash, while changing one of its origin-eligible values does. Parameters,
sliced histories, and remaining opening state occupy the disjoint
`structural`, `dynamic`, and `state` namespaces; the validator requires their
union to be exhaustive and can reassemble only those qualified partitions.

The sanitizer does not infer time semantics from array shape. An array left in
`state` is preserved and hashed, but is not certified past-only. A future
runner must enumerate every time-indexed initial-condition array in
`dynamic_keys` with an explicit date vector or supply a separately reviewed
static-state classification. Consequently, this contract proves the mandatory
`C_G`/`C_E`/`Y_I` truncation and declared-series behavior, not a whole-object
calibration firewall.

Every call must explicitly supply `class_h_used = false`; supplying `true`
fails. This is a required provenance assertion, not automatic detection of an
unlabelled publication correction. A future runner still needs reviewed input
lineage to substantiate the assertion. Input dictionary keys containing
truth, actual, realization, score, or loss semantics are rejected throughout
the nested input bundle, but that lexical guard is not a substitute for the
missing reviewed schema and lineage.

This is an engineering boundary, not proof that every calibration dependency
is vintage-clean. The full runner must additionally establish that the code
which creates the parameters and opening state saw no post-origin bytes.

## RNG and execution boundary

The protocol reserves 32 path IDs and derives two domain-separated registry
substreams for every path through `USForecastRegistry.derive_seed_record`:
`abm_engineering_model_construction` and
`abm_engineering_simulation`. Plans are sorted by path ID, so their identity
is independent of requested order. The present model uses the process global
RNG, so qualification requires:

- one Julia thread and one BLAS thread;
- `parallel = false`;
- reseeding immediately before model construction;
- reseeding again immediately before simulation.

The module compares the declared Julia and BLAS counts with the active runtime,
then requires both to equal one. It cannot observe a future caller's
`Random.seed!` placement. A real runner must make those calls adjacent to
construction and simulation using the respective substream and preserve both
seed-key hashes in its path record. Parallel execution remains forbidden until
the model owns independent RNG state.

## Fail-closed boundary

The protocol permanently retains these blockers:

- `FULL_ACCOUNTING_BRIDGE_UNRESOLVED`;
- `OUTPUT_SCALE_BRIDGE_UNVALIDATED`;
- `TIER1_TARGET_OPERATOR_COVERAGE_ZERO_OF_EIGHT`;
- `HISTORICAL_ORIGIN_COUNT_ZERO`.

The candidate real-GDP-growth and GDP-deflator-inflation formulas and units are
recorded only as `NOT_VALIDATED` declarations. Removing a blocker, changing a
formula/unit/date mapping, introducing class-H inputs, adding unknown manifest
fields, or requesting scoring, inference, promotion, origin admission, or
production registration fails closed.

Failures can be recorded for model construction, simulation, accounting,
scale, target-operator, and nonfinite-output stages. The manifest retains the
stage and typed code, plus SHA-256 digests of the constrained exception type
and bounded diagnostic message, rather than embedding free-form output. A
recorded failure is an engineering observation only; it cannot be silently
converted to a missing forecast cell.

## Verification

From the repository root:

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --startup-file=no --depwarn=error --check-bounds=yes \
  --project=scripts/us \
  scripts/us/forecasting/diagnostics/test_revised_data_abm_engineering_diagnostic.jl
```

No model construction or simulation occurs in that suite.

Pinned protocol byte SHA-256:
`34461f24ff09e1aa1eed7bf9bad5d8b415eab011bd82b8f7e7a114d0e2246743`.
