# Revised/mixed-vintage ABM one-step gate v4

Status: **independently accepted for the narrow, permanently nonadmitting
one-step software-diagnostic role**. This gate does not admit an origin,
validate an empirical forecast, establish accuracy, approve a Tier-1 operator,
or authorize production use.

## Purpose

This diagnostic characterizes exactly one native transition of the installed
base `BeforeIT.Model` from the revised/mixed-vintage U.S. 2026Q1 input
artifact. It returns raw, uncorrected model levels and pathwise h=1 GDP
mechanics for software verification. It reads, hashes, and temporarily copies
the truth-bearing artifact bytes, but it does not deserialize, interpret,
consume, or score evaluation-truth values. It does not reanchor the origin,
apply a bridge, use class H, serialize a forecast, or write a registry record.

The v3 constructor gate's canonical disposition is withdrawn. V4 pins its
exact module and protocol bytes only as reviewed scaffolding for low-level
bootstrap, source-tree, entrypoint, depot, environment, constructor-domain,
state-hash, and frozen-v2 helpers. The withdrawn v3 result hash is retained as
a historical reference and is not used as a v4 result expectation.

## Closed input and truth boundary

The U.S. nowcast artifact is byte-pinned at
`eb8d28f6b2aef9b36cf294be8906d2d5481f1c8db66ea3d034b1a96f9194b0de`.
Those raw bytes contain truth-bearing metadata, but v4 never deserializes the
top-level metadata or `output_measurement`. From a temporary exact-byte
snapshot, it uses JLD2's named-dataset interface to request only:

- `parameters`
- `initial_conditions`

The 2026Q1 period axis is reconstructed from the frozen scaffolding protocol
and checked by the unchanged v2 qualified-input hash
`bd9ac9c9054ef51289e5dfb51281e9f259684f19230e8c1a34c47f84d8062011`.
Static tests forbid the prior whole-artifact decoder, whole-artifact
qualification helper, U.S. baseline loaders, and indexing of artifact
`metadata` or `output_measurement`.

Loading BeforeIT from source eagerly deserializes ten non-U.S. standard
package datasets (Austria, Italy, and steady-state inputs plus Italy
calibration/history objects). V4 snapshots and SHA-256 checks all ten before
package loading and after the complete gate-owned execution sequence. Their
closed manifest digest is
`646fd7727a5885fd9514d0ebf9e722a0b63295f785c52f2a42498d757214ec0a`.
They are not selected or passed to the v4 constructor or GDP kernel. This
narrow statement does not claim that the resulting package globals are
semantically irrelevant to every possible BeforeIT method. Same-user
filesystem-race resistance between those checkpoints remains unattested.

JLD2 decoding uses a temporary file and removes it in a `finally` block.
Accordingly, `ephemeral_jld2_snapshot_written=true` and
`zero_filesystem_writes_claimed=false`. V4 creates no result, forecast,
serialization, score, truth, or registry artifact.

## Package-load and precompile boundary

The canonical command must use:

```text
--startup-file=no --compiled-modules=no --pkgimages=no
```

Before the first third-party package load and again at the later load
boundaries, v4 requires:

- `Base.JLOptions().use_compiled_modules == 0`
- `Base.JLOptions().use_pkgimages == 0`
- `ccall(:jl_generating_output, Cint, ()) == 0`
- exact `JULIA_LOAD_PATH='@:@stdlib'`
- one Julia thread and one BLAS thread

PrecompileTools must be absent at the clean bootstrap. The delayed v2/JSON
source-load path then loads its already source-tree/entrypoint-attested
package. V4 verifies the exact loaded package entrypoint,
`PrecompileTools.verbose[] === false`, and stable module identity before JLD2,
before BeforeIT, and after all gate-owned calls. Under those conditions,
BeforeIT's guarded PrecompileTools workload is not executed.

The complete v4 execution-envelope digest includes the withdrawn v3
environment digest, compiled-module and package-image codes,
`jl_generating_output`, symbolic and expanded load-path digests, the ten-file
side-data manifest, and the selective-decode contract. Its frozen candidate
value is
`ee71160c99b187883eb67769d17fa87829b6a58bda6e23102e97c122fe09005d`.

## Exact transition

The v2 seed namespace is deliberately retained as
`us-abm-constructor-gate-v3` because changing it would change the already
qualified construction and simulation seed plan. The protocol labels it
`seed_namespace_experiment_id`; it is not the v4 experiment identity.
Construction and simulation seeds are distinct, but distinct values and
deterministic replay do **not** establish independent random streams.
`independent_streams_established=false` is permanent.

For every execution:

1. V4 revalidates the qualified input and reconstructs fresh parameter and
   initial-condition dictionaries.
2. The construction seed is set immediately before one explicit
   `BeforeIT.Model` call.
3. The constructor's implicit `collect_data!` creates one opening row. V4
   requires `agg.t == 1` and `collection_time == [1]`.
4. V4 verifies that opening macro controls are disabled. Row 1 is therefore
   model-implied and unanchored, not official U.S. truth.
5. V4 preconstructs `NoShock()` and
   `(:business_goods, :final_demand)`.
6. In an `@noinline` helper, the simulation seed is set immediately before
   exactly one call to the one-argument CommonSolve `step!` method with
   `parallel=false` and all loggers `nothing`.
7. Before collection, v4 requires `agg.t == 2`,
   `collection_time == [1]`, finite state, and a full-state SHA-256.
8. V4 calls `collect_data!` exactly once, then requires
   `collection_time == [1, 2]`, positive finite native GDP levels, finite
   complete state, unchanged reconstructed inputs, and a final-state hash.

The transition intentionally preserves a measurement-basis discontinuity:
row 1 is model-implied initialization, while row 2 is computed from the
flow-based `update_data_step!` measurement. V4 characterizes that transition;
it does not claim an official-concept bridge.

Method origins are checked initially and after execution for:

- the direct one-argument CommonSolve `step!`;
- `NoShock` construction and call;
- `set_gross_domestic_product!`;
- `set_time!`;
- `collect_data!`; and
- `update_data_step!`.

Their frozen origin digest is
`c01f4283b344992f9f6c3590dbd702a0860cfd6f86647e8af88d2b96ba11fe36`.

## Paths, counts, replay, and ordering

V4 runs 32 primary paths in order, all 32 paths again in reverse order, and a
path-1 same-seed replay. Each execution constructs a fresh model; no caller
can inject a qualified object or preconstructed model.

| Phase | Constructions | Steps | Constructor opening collections | Explicit post-step collections | Total collection events |
|---|---:|---:|---:|---:|---:|
| Primary | 32 | 32 | 32 | 32 | 64 |
| Reverse | 32 | 32 | 32 | 32 | 64 |
| Replay | 1 | 1 | 1 | 1 | 2 |
| **Total gate-owned** | **65** | **65** | **65** | **65** | **130** |

Counts are scoped to gate-owned calls after BeforeIT is loaded. The
no-precompile-workload boundary is attested separately.

Primary and reverse records are compared by `path_id`, including seeds,
Float64 level bits, both operators, input hashes, opening state, pre-collection
post-step state, and final post-collection state. Path 1 is compared in full
against the replay.

Frozen candidate identities:

- opening constructor fingerprint set:
  `2f359965fa08785101870a46332cdd66c91e744a664e9803fc198ef53e024a18`
- one-step path-result set:
  `a9e8e6c9d22e5284d163da21477d8726a663590e2e8e3735e54018daac671199`
- path-1 final post-collection state:
  `ce48b0f392ea3be58f392d8be77c647e5e5738dd841194af9422ca5608d5a525`
- complete candidate result:
  `1ac4efc78236d0dfafb11d78b35597b1106cd374488b4f0c9ddf8fd70b1782a2`

## Raw GDP engineering kernel

Empirical-model levels enter a separately typed
`RawEngineeringGDPLevels` kernel. They are never passed to
`compute_synthetic_operators`. The accepted synthetic qualification is used
only as a pure-fixture formula oracle.

For each path:

```text
real GDP growth =
    400 * (log(real_gdp_row_2) - log(real_gdp_row_1))

GDP-deflator inflation =
    400 * ((log(nominal_gdp_row_2) - log(real_gdp_row_2))
         - (log(nominal_gdp_row_1) - log(real_gdp_row_1)))
```

Transforms are computed path by path before any ensemble summary. A varying
pure fixture tests that mean pathwise log growth differs from the log
transform of the arithmetic mean. At h=1 the fixture deliberately has a
common opening denominator, so the difference is the numerator's Jensen gap,
not a path-specific opening-level artifact. The formula-oracle digest is
`c40857cd961532a3b14f89a9bc2ed4cfbee48ce69a40ada38198207e6a18354f`.

## Reproduction

Portable fail-closed branch:

```bash
JULIA_LOAD_PATH='@:@stdlib' \
OPENBLAS_NUM_THREADS=1 \
JULIA_NUM_THREADS=1 \
julia --startup-file=no \
  --compiled-modules=no \
  --pkgimages=no \
  --check-bounds=yes \
  --depwarn=error \
  --project=scripts/us \
  scripts/us/forecasting/diagnostics/test_revised_data_abm_one_step_gate_v4.jl
```

The altered bounds envelope must fail before JSON, v2, JLD2, BeforeIT,
PrecompileTools, construction, stepping, or collection.

Canonical branch:

```bash
JULIA_LOAD_PATH='@:@stdlib' \
OPENBLAS_NUM_THREADS=1 \
JULIA_NUM_THREADS=1 \
ABM_ONE_STEP_GATE_V4_REPORT=1 \
julia --startup-file=no \
  --compiled-modules=no \
  --pkgimages=no \
  --depwarn=error \
  --project=scripts/us \
  scripts/us/forecasting/diagnostics/test_revised_data_abm_one_step_gate_v4.jl
```

The canonical branch performs the complete 65-execution qualification and
asserts the exact envelope, result, path-set, replay-state, method-origin,
side-data, count, row, formula, immutability, order-invariance, replay, and
fail-closed declarations.

## Independent audit result

Independent review rechecked the frozen module, test, and protocol hashes as
`ab16f7a0fb9abe6fc0d066d2b8649e816155f0c34375a8cab7adb8af80233e5b`,
`dd104d943f23b408d0d223938ec5b7ad8c0169ec07656cff055d97c03116a2a9`,
and `d15fdef2c5fa7142c7658318d2bd726953b9a4569f3f7d50762e14965f9c3ef7`.
The portable altered-bounds branch passed 214/214 assertions and left all
delayed third-party packages unloaded. An unrelated-cwd canonical replay
under the exact no-cache envelope passed 276/276 assertions in 7m41s and
reproduced the result, envelope, path set, replay state, method origins,
ten-file side-data manifest, and all 65/65/65/65/130 gate-owned counts.

The audit also exercised inert fail-closed probes for compiled modules,
package images, output generation, ambient PrecompileTools, scoring, and
origin admission. Acceptance applies only to the exact local software
diagnostic. Binary/JLL payloads, Julia executable and sysimage, depot contents,
global preferences, same-user races, independent RNG streams, official
concept equivalence, origin admission, empirical validity, accuracy, and
production suitability remain unattested or false.

## Permanent interpretation

`software_one_step_verified` and `initial_transition_characterized` are
separate from empirical validation. This accepted diagnostic remains:

- revised/mixed-vintage and `origin_admissible=false`;
- `empirical_forecast_validated=false`;
- `us_evaluation_truth_used=false`;
- `truth_values_used_for_scoring=false`;
- `score_computed=false` and `inference_run=false`;
- `registry_write_allowed=false` and `promotion_eligible=false`;
- `class_h_allowed=false` and `production_allowed=false`; and
- outside any claim of forecast accuracy or suitability.

The raw h=1 diagnostic paths may inform later engineering, but they are not an
admitted forecast and must not enter competition or the final accuracy report
until the historical/prospective origin, official concept, truth-quarantine,
scoring, and inference gates are separately satisfied.
