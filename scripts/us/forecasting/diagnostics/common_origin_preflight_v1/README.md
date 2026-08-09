# Common-origin forecast-seal preflight v1

This isolated component answers one question before any empirical U.S. model
comparison is allowed to run: do the exact current repository artifacts define
one admissible origin, target/operator contract, horizon/path contract, and
registered model set that can be sealed without exposing evaluation truth?

On the frozen current bytes the exhaustive answer is:

```text
CANNOT_RUN
```

The deterministic result has semantic SHA-256
`4b0871cdd9c25fadcd266b778ba23b0415f23ce8e8c423f6ee7fc5d936938fd5`,
with 36 exact source bindings, 21 false readiness conditions, 89 source-bound
blocking reasons, and 17 separately classified downstream limitations. The
current v1 manifest allows only `CANNOT_RUN`. A future
`READY_FOR_FORECAST_SEAL_NO_TRUTH_LOADED` disposition requires a new manifest
schema or successor contract with new exact source bindings; changing local
booleans or recomputing self-hashes cannot elevate v1. `READY_TO_SCORE` is
always forbidden here.

## Pure metadata boundary

The preflight imports only the `SHA` and `TOML` standard libraries. It reads
the frozen manifest, metadata TOMLs, and source/documentation bytes needed for
exact fixity checks. It does not include any upstream module. In particular,
it does not:

- construct, step, filter, fit, forecast, or score a model;
- open the revised core-three CSV or any JLD2 artifact;
- access a truth artifact or future target value;
- write a file, registry, inventory, or raw-data object; or
- use the network.

The returned action counts are scoped to work owned by this preflight, not to
unobservable activity that a caller may have performed before invoking it.
The target and protocol TOMLs provide truth-policy metadata, but the Tier-1
contract registers zero truth matrices. Metadata presence is not represented
as a truth artifact.

## Exact current intersections

The compiler rederives these intersections after all physical file hashes and
source identities pass:

| Dimension | Nominal intersection | Eligible intersection |
|---|---|---|
| origin | metadata labels 2016Q2–2021Q2 (21) | none; strict admitted count is zero |
| target | `real_gdp` | none; its official operator is unapproved |
| transform | annualized quarter-over-quarter real-GDP log growth | none approved |
| horizon | 1, 2, 4 | none |
| path | ABM has 32 paths through h=4 | no shared registered path/convergence contract |
| registration | four executable candidate IDs required | none registered |

The ABM origin is 2026Q1. A physically pinned, metadata-only revised-fixture
manifest declares a 101-row panel ending in 2025Q3. The preflight does not
open that manifest's named CSV and therefore does not claim to verify the
declared panel SHA-256 or its values. From the metadata-declared end, checked
against the pinned core-three software contract, the compiler derives the last
feasible origins as 2025Q2 at h=1, 2024Q3 at h=4, and 2022Q3 at h=12. Thus even
h=1 has no common origin. The protocol requires
the exact set `[1, 2, 4, 8, 12]`; the ABM supplies only h=1–4. Its h=1 value
crosses the frozen `model_implied_opening_to_post_step_flow` basis break, and
h=2/h=4 remain raw model paths without an approved official bridge.

The model-source names are never treated as official target IDs by spelling
alone. The manifest binds each source name to its official target, operator,
transformation, and unit. Core-three and small-NK `real_gdp_growth` map to
official `real_gdp`; `pce_inflation` maps to `pce_price_index`, never to the
GDP deflator. EFFR is a quarterly-average percentage-point level under
`us-effr-quarterly-average.v1-draft`, not an annualized log-growth target. The
ABM's separate inflation output maps to official `gdp_deflator`.

## Why the result is blocked

The blocker list is a deterministic, sorted expansion of the 21 false
forecast-seal readiness conditions. Each blocker names one or more exact
source-binding IDs and one or more conditions it blocks. Highlights include:

- zero registered release events, zero admitted origins, and an empty strict
  common-window intersection;
- the current origin's revised/mixed-vintage `cannot_run` record with all 21
  underlying failures retained;
- no registered historical release set or evidence-bound structural as-of
  receipt for any of the six required structural components;
- synthetic-only builder, receipt, and adapter contracts, which cannot be
  relabelled as empirical evidence;
- an open opening-macro mapping (six unresolved and one rejected), zero of 66
  approved parameters, an open variant gate, and failed latent, inventory,
  supply/make/valuation, and full-accounting gates;
- zero approved Tier-1 operator bridges, zero historical vintages for every
  target, and a fail-closed unimplemented evidence verifier;
- a draft, unapproved, unfrozen evaluation protocol;
- no registration for the ABM or repaired AR/VAR/BVAR mechanics, while
  `small_new_keynesian_dsge` is a mechanics class rather than an executable
  registry model ID;
- incompatible origin, target/operator, horizon, h=1 measurement-basis, and
  path contracts; and
- benchmark empirical execution disabled and a forecast seal unable to
  authenticate missing vintage/source evidence by itself.

Downstream facts such as truth non-use, production/scoring prohibition, and
the accepted ABM software gate's claim ceiling are retained as limitations or
false scientific gates rather than mislabelled as forecast-seal prerequisites.
Admission, scoring, accuracy, suitability, promotion, and production gates
are all exactly false.

## Rejection rules

The result explicitly rejects revised/current tracks, synthetic receipts,
repeated hash labels without path-and-role source binding, hindsight
structural selection, unregistered models, mismatched origin/target/transform
semantics, PCE-to-deflator aliasing, and the ABM h=1 opening-to-flow basis
break. Validation recomputes the complete result from the 36 exact source
files; a coordinated result edit plus a new self-hash still fails replay.

The earlier core-three equilibrium comparison remains historical rejected
evidence, not an input file and not a live-candidate classification. Its
closed identities are module `da358120...`, tests `956b7011...`, runner
`8fd455c9...`, documentation `f37b550a...`, and claimed result `7e92f0df...`.
No file from the actively changing comparison directory is a source binding.

## Manifest and reproduction

The self-hashed manifest has semantic SHA-256
`455ae03d775865eba34e1f1fc84ca0ffe790c79508d89b6cc284d19ce37a175a`
and physical SHA-256
`a44f90f1cc809cfcc928e69f0ddc046916554fee9a534ff8d6162a4df6143902`.
The semantic hash is useful for canonical content comparison; the separately
compiled physical hash is what prevents a coordinated local manifest edit and
self-restamp. Neither kind of local hash independently authenticates upstream
provenance.

Run the adversarial suite from the repository root:

```bash
julia --startup-file=no --check-bounds=yes --depwarn=error \
  --project=scripts/us \
  scripts/us/forecasting/diagnostics/common_origin_preflight_v1/test_common_origin_preflight_v1.jl
```

The same command is portable from an unrelated working directory when the
project and test paths are absolute. To obtain the in-memory result without
writing it:

```julia
include("scripts/us/forecasting/diagnostics/common_origin_preflight_v1/USCommonOriginPreflightV1.jl")
result = USCommonOriginPreflightV1.compile_preflight()
USCommonOriginPreflightV1.validate_preflight(result)
```
