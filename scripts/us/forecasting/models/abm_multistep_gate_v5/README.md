# Revised/mixed-vintage ABM four-quarter gate v5

Status: **frozen candidate pending independent audit**. The only proposed
role is `SOFTWARE_FOUR_QUARTER_PATH_VERIFIED_NONADMITTING`. This directory
does not admit a forecast origin, validate an official observation bridge,
read evaluation truth, compute a score, establish accuracy, or authorize
production use.

## Purpose and inheritance

V5 is the deterministic four-quarter successor to the independently accepted
one-step v4 diagnostic. It pins all four accepted v4 artifacts, the withdrawn
v3 bootstrap scaffolding used by v4, the accepted v2 origin firewall and
synthetic GDP formula oracle, the exact revised/mixed-vintage 2026Q1 U.S.
artifact, the active Project/Manifest, four transition/measurement sources,
and all ten eager BeforeIT import-side datasets.

V5 includes the exact accepted v4 module as a dependency but does **not** call
the v4 runner. It reuses the exact v4 construction and simulation seed vectors
and inherited seed namespace `us-abm-constructor-gate-v3` so each v5 path's
opening and h=1 prefix can be compared byte-for-byte with accepted v4. This is
a regression-continuity choice, not evidence that the construction and
simulation seeds are independent random streams.

## Exact free-running transition

Each execution reconstructs fresh v2-qualified parameter and initial-condition
dictionaries, seeds immediately before one `BeforeIT.Model` construction,
then seeds the simulation RNG exactly once immediately before a four-iteration
loop. Each iteration calls the direct one-argument serial `step!` method with:

```text
parallel = false
shock! = NoShock()
transaction_logger = nothing
transaction_markets = (:business_goods, :final_demand)
opening_state_logger = nothing
```

There is no reseeding, realized-outcome insertion, reanchoring, warm-up
deletion, path resampling, clamping, winsorization, or shortened horizon. A
failure or invalid level at any precommitted path/horizon fails the complete
gate and retains only in-memory partial attempt counts.

The constructor implicitly records row 1 at `agg.t == 1`. For horizons 1--4,
v5 requires the following exact trace:

1. direct step to `agg.t == h + 1` while `collection_time == 1:h`;
2. hash the complete pre-collection state and recheck input immutability;
3. call `collect_data!` exactly once;
4. require `collection_time == 1:(h + 1)`, hash the complete post-collection
   state, and recheck input immutability and finite state.

Every execution ends at `agg.t == 5`, `collection_time == [1,2,3,4,5]`, and
five positive finite native nominal/real GDP rows:

```text
row 1  2026Q1  model-implied unanchored opening
row 2  2026Q2  h=1 post-step flow measurement
row 3  2026Q3  h=2 post-step flow measurement
row 4  2026Q4  h=3 post-step flow measurement
row 5  2027Q1  h=4 post-step flow measurement
```

The measurement basis is horizon-specific. H=1 compares the model-implied
opening with the first flow-based measurement and therefore preserves the
known basis discontinuity. H=2--4 compare successive post-step flow-based
measurements, although they remain raw, unbridged model quantities. V5 emits
only sequential q/q operators; it does not emit a row-1-to-row-5
four-quarter statistic.

## Pathwise GDP mechanics

For each raw path and each `h in 1:4`, before any ensemble summary:

```text
real GDP growth[h] =
    400 * (log(real_gdp[h + 1]) - log(real_gdp[h]))

GDP-deflator inflation[h] =
    400 * ((log(nominal_gdp[h + 1]) - log(real_gdp[h + 1]))
         - (log(nominal_gdp[h]) - log(real_gdp[h])))
```

A five-row pure synthetic fixture is passed to the accepted synthetic-only
operator and compared bitwise at all four horizons. Empirical model rows are
never passed into that synthetic API. The fixture also detects
transform-after-ensemble ordering errors and checks level-rebase invariance.

## Executions and regression continuity

V5 executes 32 paths in primary order, the same 32 in reverse order, and one
same-seed replay of path 1:

| Phase | Model constructions | Direct serial steps | Constructor opening collections | Explicit post-step collections | Total collection events |
|---|---:|---:|---:|---:|---:|
| Primary | 32 | 128 | 32 | 128 | 160 |
| Reverse | 32 | 128 | 32 | 128 | 160 |
| Replay | 1 | 4 | 1 | 4 | 5 |
| **Total** | **65** | **260** | **65** | **260** | **325** |

The counts cover only gate-owned `BeforeIT.Model`, direct step, and collection
calls after BeforeIT loads. The pure formula/method checks and `NoShock`
object construction are outside those counts.

Primary and reverse paths are compared by path ID over seeds, Float64 level
bits, all four operators, all eight transition hashes, input hashes, and all
four numeric cardinalities. Path 1 is compared in full with its replay. V5
also projects every h=1 slice into the exact accepted v4 path-record schema,
without rerunning v4, and requires:

```text
v4 h1 path set       a9e8e6c9d22e5284d163da21477d8726a663590e2e8e3735e54018daac671199
v4 opening set       2f359965fa08785101870a46332cdd66c91e744a664e9803fc198ef53e024a18
v4 path-1 h1 state   ce48b0f392ea3be58f392d8be77c647e5e5738dd841194af9422ca5608d5a525
```

## Truth, package-load, and persistence ceiling

The raw U.S. artifact bytes contain truth-bearing metadata, are hashed, and
are copied into an ephemeral JLD2 snapshot. V5 requests only the named
`parameters` and `initial_conditions` datasets and reconstructs period axes
from the frozen protocol. It does not deserialize `metadata` or
`output_measurement`, invoke a whole-artifact decoder/qualifier or baseline
loader, or call prediction, ensemble, scoring, registry, or production APIs.
The temporary snapshot is removed in `finally`, so
`ephemeral_jld2_snapshot_written=true` and
`zero_filesystem_writes_claimed=false`.

The exact command must use `JULIA_LOAD_PATH='@:@stdlib'`, one Julia and BLAS
thread, `--startup-file=no`, `--compiled-modules=no`, and `--pkgimages=no`.
V5 preserves v4's checks for `jl_generating_output == 0`, clean
PrecompileTools bootstrap and `verbose=false`, dependency source trees,
package entrypoints, depot paths/overrides, method origins, and the ten eager
import-side datasets before and after execution.

## Reproduction

Portable altered-envelope branch, which must reject with zero model calls and
all delayed third-party modules still unloaded:

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
  scripts/us/forecasting/models/abm_multistep_gate_v5/test_revised_data_abm_multi_step_gate_v5.jl
```

Canonical branch:

```bash
JULIA_LOAD_PATH='@:@stdlib' \
OPENBLAS_NUM_THREADS=1 \
JULIA_NUM_THREADS=1 \
ABM_MULTI_STEP_GATE_V5_REPORT=1 \
julia --startup-file=no \
  --compiled-modules=no \
  --pkgimages=no \
  --depwarn=error \
  --project=scripts/us \
  scripts/us/forecasting/models/abm_multistep_gate_v5/test_revised_data_abm_multi_step_gate_v5.jl
```

Run from the repository root and an unrelated working directory. The final
candidate hashes and assertion counts are recorded only after the frozen
canonical output is reproduced.

## Frozen candidate evidence

Two authoring runs first failed closed at the intended unbound-identity
guards. The output guard completed all paths in 24m15.3s and yielded the
multi-step path-set and path-1 h=4 state below. After binding those values,
the result guard completed in 24m17.5s and yielded the complete-result hash.
Neither guard was bypassed or converted into a passing result.

The portable altered-envelope branch passes **269/269** assertions. It
rejects before any gate-owned construction, step, or collection and leaves
JSON, JLD2, BeforeIT, v2, and PrecompileTools unloaded. Exact frozen bytes
then pass **338/338** assertions from both the repository root and unrelated
working directory `/private/tmp`; the canonical runner testset is **82/82**
in each process. Wall times were 1,479.86 seconds from the root and 1,479.57
seconds from `/private/tmp` while the processes ran concurrently.

| Frozen candidate component | SHA-256 |
|---|---|
| module | `853bac0c2b6f167da33fb4da0c4bd9366819900a0819f450227bae969ea3ca4d` |
| adversarial tests | `08e760b6e554e0457d433ba7a8f532bcfc3112159b14133a3bf2f561600b1bdc` |
| protocol | `e3f18b132ac65b2c3f985d17e6b850ae3fef4572047b0893acaca2d0f8132ac8` |
| complete result | `736ac1683df46f1ef856375ef8036b6ab6b8e858fbfd84fc7a366e879855d9b4` |
| execution envelope | `6b52a0fa8d1b0548dd51d9930d34df74290bc33d9d1654ecf9d32d4c1265b0de` |
| 32-path four-quarter result set | `33294f6f1eb3a98b2cfb4184b95adae44673b3de8fb1c64638bcb9af58f9a7b3` |
| path-1 h=4 post-collection state | `85a4ebd2a11c73713b9e43c63db71dd732eb2332d0130b19e0eaf921e833819f` |

Both canonical processes also reproduced the accepted v4 h=1 path set,
opening set, and path-1 state listed above, every primary/reverse/replay
comparison, and the exact 65/260/65/260/325 gate-owned counts. These are
authoring results for a frozen candidate pending independent audit, not an
acceptance decision.

## Permanent non-result

All of the following remain false: input-lineage and source-period
authentication; independent RNG streams; official-concept/Tier-1 bridge
approval; truth use and scoring; forecast serialization; inference; origin
admission; registry write; promotion; production; class H; reanchoring; full
runtime attestation; empirical accuracy; and forecasting suitability.

Binary/JLL payloads, Julia executable/sysimage bytes, depot contents and
caches, global preferences, and same-user filesystem-race resistance remain
unattested. The 2026Q1 input is current revised/mixed-vintage evidence, not an
admitted historical origin. A passing v5 result is software-path evidence
only and must not enter the ABM-versus-benchmark accuracy report.
