# Revised-data ABM constructor gate v3

## Status and claim boundary

This is a diagnostic, constructor-only qualification for the installed base
`BeforeIT.Model`. It is not a forecast run and it produces no empirical
evidence. The gate constructs 32 stochastic opening states and one declared
same-seed replay, but never calls a model step, run, solve, or simulation
method. It does not read truth, score forecasts, run inference, serialize a
forecast, admit an origin, or promote a registry entry.

In Sargent's terminology, this gate is implementation/model **verification**:
it asks whether the frozen constructor and its checked inputs execute as
specified. It is not empirical **validation**, which asks whether the model
represents the target economic system adequately for its intended use
([Sargent, 2013](https://doi.org/10.1057/jos.2012.20)).

The successful result therefore means only:

- the exact pinned `US_2026Q1_nowcast.jld2` bytes can be requalified by the
  frozen v2 origin-input firewall;
- the installed constructor domain passes the known `randpl` termination and
  worker-assignment bounds preconditions;
- the base constructor can create finite, structurally consistent opening
  states for all 32 frozen construction seeds in the exact local execution
  envelope;
- replaying path 1 in the same process produces the same full-state hash; and
- the 32 opening-state hashes are distinct for this run.

Distinct hashes are not evidence that seed streams are statistically
independent, and a successful constructor is not evidence of forecast
accuracy, calibration quality, economic validity, or equilibrium behavior.
Independent replications require an explicitly justified stream/substream
design; distinct initial states and distinct observed outputs alone do not
establish that property
([L'Ecuyer et al., 2002](https://doi.org/10.1287/opre.50.6.1073.358)).
The Julia manual explicitly treats the exact default-RNG stream as an
implementation detail that may change across versions, so the contract makes
no cross-version or cross-platform bit-reproducibility claim
([Julia 1.10 `Random` manual](https://docs.julialang.org/en/v1.10/stdlib/Random/)).

## Frozen inputs and execution envelope

The gate reads and SHA-256 checks, rather than accepting from a caller, the
installed artifact:

`data/us/baselines/US_2026Q1_nowcast.jld2`

Its byte SHA-256 is:

`eb8d28f6b2aef9b36cf294be8906d2d5481f1c8db66ea3d034b1a96f9194b0de`

The artifact contains no per-series date labels. The gate reconstructs a
contiguous quarterly axis arithmetically from the frozen artifact period
`2026-Q1`, its `T_prime = 117`, and each dynamic array's first dimension. The
artifact hash binds this reconstruction to those exact bytes, but it does not
authenticate the source or release-time meaning of the period label.
`source_period_labels_authenticated` and `input_lineage_verified` therefore
remain false.

Before loading `BeforeIT`, the gate requires:

- active project exactly `scripts/us/Project.toml`;
- environment variable `JULIA_LOAD_PATH` exactly `@:@stdlib`;
- symbolic `Base.LOAD_PATH` exactly `["@", "@stdlib"]`, expanding only to
  the active `scripts/us/Project.toml` and the pinned Julia stdlib;
- Julia 1.10.3 with startup disabled and bounds-check mode `auto`;
- Darwin/aarch64, Apple M1/native, 64-bit;
- one Julia thread and one LBT/BLAS thread;
- default RNG type exactly `Random.TaskLocalRNG`;
- the exact canonical execution table from
  `scripts/us/accounting/USJuliaExecutionEnvelope.jl`;
- all 83 manifest-backed package entrypoints, including the pinned UUIDs for
  JSON, JLD2, and BeforeIT, pre-resolving through `Base.locate_package` to
  entrypoints inside their source-tree-validated manifest locations;
- an immediate repeat of the relevant entrypoint check before each explicit
  `Base.require`; and
- no already-loaded module named `BeforeIT`.

The v3 module itself bootstraps with Julia standard libraries only. Clean
process probes establish that importing it does not load or execute JSON,
JLD2, BeforeIT, or the frozen v2 module. It validates the manifest records,
all installed source trees, the closed load path, and all 83 entrypoints
before lazily including frozen v2. That delayed include is the first operation
that loads JSON. The gate then requires the exact manifest JLD2 UUID once;
artifact decoding receives that checked module explicitly. JLD2's module
identity, package entrypoint, and `jldopen` method origin are checked before
and after decoding and after construction. BeforeIT is required only after
the decoded input has been requalified and the constructor-domain preflight
has passed.

The regression suite uses benign existing-file path substitutions at the
pure-data resolver boundary. Wrong resolved-entrypoint values for the JSON
and JLD2 package IDs raise the typed v3 error before a supplied loader
callback is invoked. It does not construct or execute alternate packages.

The pinned `Project.toml` and `Manifest.toml` identify the dependency graph.
This follows Julia Pkg's use of the manifest to record exact direct and
indirect dependencies
([Pkg manifest documentation](https://pkgdocs.julialang.org/v1/toml-files/)).
The gate additionally recomputes Git tree SHA-1 values for all 82 installed
non-path dependency source trees and checks the repository's complete Julia
source closure through v2. It checks 18 selected constructor/helper method
origins after loading and again after construction.

Matching a manifest Git-tree SHA-1 establishes consistency with this pinned
manifest; it does not authenticate the publisher or the provenance of that
manifest. This is not a complete supply-chain attestation. JLL wrapper source
trees are checked, but downloaded JLL/binary artifact payloads, compiled
caches, the full depot, global preferences, the Julia executable, the
sysimage, and a same-user actor able to race filesystem reads are not
attested. The package-entrypoint checks constrain Julia source selection; they
do not authenticate native payloads or the runtime that interprets those
sources. Effective `BeforeIT.typeFloat === Float64` and
`BeforeIT.typeInt === Int` are checked after the single package load, but
these broader limitations keep `full_runtime_attestation = false`.

The effective `Base.DEPOT_PATH` is enumerated before JLD2 loading, immediately
before BeforeIT loading, and after construction. Every depot path must be
absolute, normalized, unique, and free of symbolic-link components. Every
corresponding `artifacts/Overrides.toml` must be absent, including broken
symlinks. This matters because Julia Pkg layers per-depot override files and
allows them to replace an artifact by another content hash or an absolute
path
([Julia Pkg 1.10 artifact overrides](https://pkgdocs.julialang.org/v1.10/artifacts/#Overriding-artifact-locations)).
Absence of overrides narrows artifact selection; it still does not attest the
selected binary bytes, compiled caches, or other depot contents.

JLD2 decoding necessarily writes the already SHA-256-verified artifact bytes
to an ephemeral `mktemp` file, verifies those temporary bytes immediately
before and after decode, and removes the file in a `finally` block. The gate
therefore does not claim zero filesystem writes. A same-user concurrent race
against this temporary copy or other checked paths remains outside the
attested boundary.

The qualified local run enumerated three depots, with ordered path-list
SHA-256
`cfa3672b94a76ea1482e4000919387280c0f6bc48e5b3120428fb34c2d158ce0`:

1. `/Users/sina/.julia`
2. `/Users/sina/.julia/juliaup/julia-1.10.3+0.aarch64.apple.darwin14/local/share/julia`
3. `/Users/sina/.julia/juliaup/julia-1.10.3+0.aarch64.apple.darwin14/share/julia`

## Qualification and constructor-domain preflight

The runner never accepts a `QualifiedBaseOriginInputs` value. It reads the
artifact snapshot, reconstructs the axes, and calls the frozen v2
`qualify_base_origin_inputs` itself. The installed v2 bindings are:

- v2 protocol:
  `efcdce3fb08e0b7496f9293c299787994eda85f2d7f750603a7f5a8b0856cab4`
- qualified input:
  `bd9ac9c9054ef51289e5dfb51281e9f259684f19230e8c1a34c47f84d8062011`
- parameter partition:
  `2332724a2600198186e584fec04ad5bdf889fefd66818205e19b5d9580ac58f2`
- static partition:
  `feffe564fac157a5ddd0e8d3a112c028f588e697b243e0bd5ef02d62bcd4a808`
- dynamic partition:
  `29a0fcc671e6e067db846ce77ce556cee599c863108b6e56eb0c16ae2911328e`

Every constructor integer is checked as a non-Boolean exact integer, within
`Int` range, and exactly preserved by the `Float64` projection. Aggregates
are first evaluated with `BigInt`, then checked against both `Int` and the
constructor's projected `Float64` sums. The gate requires, for every sector
`g`,

`N_s[g] >= I_s[g]`

because `randpl` assigns at least one worker to every firm. It also requires

`H_act - sum(I_s) - 1 >= sum(N_s)`

so the model finalizer cannot write more firm assignments than the active
worker vector holds. These checks close the known nontermination and bounds
failure domains before any constructor call.

## RNG and state checks

V2 derives the frozen 32-path seed plan using the v3 experiment namespace.
Only each record's construction seed is used. The simulation seeds are never
used. The wrapper checks that the effective default RNG is exactly
`Random.TaskLocalRNG`, as supplied by the pinned Julia 1.10.3 runtime. Within
the no-inline construction wrapper, `Random.seed!(seed)` is immediately
followed by `Base.invokelatest(BeforeIT.Model, parameters,
initial_conditions)`; there is no intervening random operation. Paths run
serially. This implementation binding and the observed distinct states do
not establish statistical independence among paths.

The gate recursively checks every numeric value reachable from each model for
finiteness. It also checks exact counts for sectors, firms, active and
inactive workers, employed and unemployed workers, per-sector firms and
employment, worker-to-firm assignments, government entities, foreign
consumers, history lengths, sector vectors, and the one constructor-created
opening data row. It verifies that constructor input hashes and the v2
qualified-input hashes remain unchanged.

A canonical traversal includes concrete scalar, array, dictionary, reference,
and struct types while hashing the complete reachable opening state without
emitting raw state values. The result contains only hashes, counts, and
booleans. Path 1 is reconstructed once more with the same construction seed
and must match its first full-state hash. All 32 path hashes must be distinct
and their ordered set must match the frozen set digest:

`2f359965fa08785101870a46332cdd66c91e744a664e9803fc198ef53e024a18`

The ODD literature motivates explicit model mechanisms and implementation
details as aids to understanding and reproducibility, while not treating
documentation as model validation
([Grimm et al., 2010](https://doi.org/10.1016/j.ecolmodel.2010.08.019)).
Empirical review of ABM practice likewise emphasizes archiving code,
metadata, and the necessary runtime environment
([Janssen, 2017](https://doi.org/10.18564/jasss.3317)). Those principles
motivate this gate's explicit source, environment, method, seed, and
claim-boundary records.

## Installed canonical result

Two fresh Julia processes, one launched from the repository root and one
launched from `/tmp`, each passed 271/271 assertions and executed all 33
declared constructions. Both were constrained by the same frozen ordered
fingerprint-set digest. A noncanonical local run passed 219/219 portable
assertions by exercising the typed pre-load rejection branch and performed
zero model constructions.

The installed canonical result records:

- protocol SHA-256:
  `9bea1d110879275e33cc58d87a802c5e51e2b2f3d33929d7db073e81bd07166d`
- result SHA-256:
  `68df3185b7159ac4b9fadcdb82ffb2e674ff5fdf6a89aa8d78585b4e4cf3105b`
- execution-envelope SHA-256:
  `47b774b221673e1da61b770f1a06bdd8eaf61b8ea1d5a22ae2f8cd8fad688deb`
- method-origin SHA-256:
  `fd2b58e895288507bc540d72a9b767f39eafb26b14c8377e514fc6f265f28866`
- dependency-source digest:
  `6192d8216ea69f512df51e086a32c589f0677e81c1a7683b118a9b32ceecee0c`
- 82 checked non-path dependency source trees;
- package-entrypoint digest:
  `a98c02ba04a38a3fc1665fa4fb4e68516093c8d8a92cad738b30cf4623dd2146`
  across 83 manifest-backed entrypoints;
- symbolic load-path digest:
  `9fece03877b2dea05316711ae18d40f81f6525649f4fa3be534b216f446605ce`;
- expanded load-path digest:
  `937243767dce2162176cc5ce3f7adb8ea5f4a67c9319a5d04d7d0d43b99495d3`;
- 38,903 recursively checked numeric values per constructed state;
- 68 sectors, 130 firms, 1,695 active workers, 1,005 inactive workers,
  1,627 employed workers, and 68 unemployed workers;
- 33 government entities and 65 foreign consumers;
- ordered 32-path fingerprint-set SHA-256:
  `2f359965fa08785101870a46332cdd66c91e744a664e9803fc198ef53e024a18`;
  and
- path-1/replay full-state SHA-256:
  `ccd76c1d7748db755391674b179382ea3584a3432021e0ffd1332f76f6697601`.

The exact same-seed replay matched, all 32 observed path hashes were distinct,
constructor input hashes were unchanged, all pinned source snapshots remained
unchanged, and artifact overrides were absent. These are engineering
qualification results only. They do not promote the artifact or establish
forecast accuracy.

## Canonical commands

Run from the repository root:

```sh
JULIA_LOAD_PATH='@:@stdlib' OPENBLAS_NUM_THREADS=1 JULIA_NUM_THREADS=1 \
  julia --startup-file=no --depwarn=error --project=scripts/us \
  scripts/us/forecasting/diagnostics/test_revised_data_abm_constructor_gate_v3.jl
```

Run the same test from an unrelated working directory:

```sh
cd /tmp
JULIA_LOAD_PATH='@:@stdlib' OPENBLAS_NUM_THREADS=1 JULIA_NUM_THREADS=1 \
  julia --startup-file=no --depwarn=error \
  --project=/absolute/path/to/repository/scripts/us \
  /absolute/path/to/repository/scripts/us/forecasting/diagnostics/test_revised_data_abm_constructor_gate_v3.jl
```

Do not add `--check-bounds=yes`; the frozen local envelope requires the
default `auto` mode.

The test file is portable as a fail-closed contract test. On a host that does
not match the frozen M1 envelope, it runs the protocol and adversarial tests,
requires a typed execution-envelope rejection, and verifies that JSON, frozen
v2, JLD2, and BeforeIT all remain unloaded. The current portable branch passes
219/219 assertions; it does not treat the expected rejection as an installed
constructor pass. The 33-construction branch runs only on the exact canonical
local envelope.

## Non-results and next gate

Even when this contract passes, all of the following remain false:

- `model_stepped`
- `forecast_emitted`
- `forecast_serialized`
- `truth_accessed`
- `score_computed`
- `inference_run`
- `origin_admissible`
- `promotion_eligible`
- `full_runtime_attestation`

The next ABM gate must be separately authorized and must preserve truth
blindness while defining a no-leakage simulation and observation-operator
contract. Constructor qualification alone cannot support a forecast
suitability or accuracy statement.
