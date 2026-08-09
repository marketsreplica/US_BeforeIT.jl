# Trusted Origin Builder (synthetic-only)

`USTrustedOriginBuilder.jl` is an isolated source-to-`OriginData` seam. It
constructs an owned benchmark sample only when every output matrix cell is
covered exactly once by a deterministic lineage claim. Each claim binds the
output slot/key/column/value to ordered source-observation IDs, and each source
observation binds an artifact SHA-256, source-series identity, period, and
vintage. The receipt also binds an explicit transformation ID/version, operator
ID/version, and ordered operator parameters.

The v1 operator allowlist is deliberately small:

- `identity/v1`: exactly one input and no parameters.
- `weighted_sum/v1`: ordered coefficients followed by an intercept.

The builder rejects nonfinite values, unsupported keys or operators, output
coverage gaps/duplicates, unused source observations, artifact-hash aliases,
artifact/observation binding drift, unknown inputs, look-ahead keys, and any
sample or receipt mutation detected at validation time. All source artifacts,
observations, derivations, output ordering, and IEEE-754 values are included in
a typed length-prefixed self-hash. The output `sample_sha256` uses the existing
`USOriginDataReceipt.origin_data_sha256` canonical sample definition, so a
future `authenticate_origin_data` integration can cross-bind both receipts
without changing sample semantics.

This is a synthetic fixture contract only. Both `empirical_execution_authorized`
and `production_admission_authorized` are permanently false in v1. It performs
no filesystem acquisition, release-availability verification, vintage-byte
verification, target/truth validation, or forecast scoring.

The remaining semantic trust boundary is intentional: v1 independently
executes only its two algebraic operators. A future production builder must pin
and execute audited parsers and target transformations against acquired,
availability-qualified source bytes before this derivation receipt can support
an empirical origin.

Run the focused contract tests with:

```sh
julia --startup-file=no --check-bounds=yes \
  scripts/us/forecasting/origins/builder/test_trusted_origin_builder.jl
```
