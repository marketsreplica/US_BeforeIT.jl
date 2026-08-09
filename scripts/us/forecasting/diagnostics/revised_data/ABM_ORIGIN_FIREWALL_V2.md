# Base-model ABM origin firewall v2

This contract closes the whole-object time-axis hole left deliberately open by
the v1 no-output engineering qualification. It validates the complete installed
U.S. source-envelope schema, then projects only the inputs consumed by the base
constructor:

```text
model_variant = base
model_constructor_id = BeforeIT.Model
origin_period = 2026Q1
```

It does not construct or step that model. It does not emit a forecast, open
truth, calculate a score, conduct inference, admit an origin, approve an
observation operator, or promote a model.

The v1 protocol and module remain separate and byte-pinned prerequisites.
Nothing in this v2 contract changes v1 or the synthetic GDP-operator
qualification that pins it.

## Validate, then project

The installed `US_2026Q1_nowcast.jld2` source envelope contains 66 parameter
keys and 34 initial-condition keys. The firewall first requires those exact key
sets. The compiled and TOML member lists must also contain exactly 66 and 34
unique names: a duplicated schema entry fails even when set-based source-key
comparison would otherwise hide it. Unknown and missing keys fail rather than
being inferred from array shape or passed through to model construction.
Runtime dictionaries must likewise have the exact raw entry count and unique
names after conversion to `String`; distinct `String`/`SubString` keys with
the same text are rejected before projection or canonical hashing.

The resulting model-input projection contains exactly:

- 60 model parameters, including `T_prime`;
- 17 static opening-state fields;
- five base-model histories: `C_G`, `C_E`, `Y_I`, `Y`, and `pi`.

The following recognized source parameters are validated and then excluded:

```text
S
T
T_max
use_commodity_balance_inventory
use_growth_rate_ar1
use_product_tax_netting
```

`S` must equal the consumed `G`. `T` and `T_max` must be non-Boolean integers,
`T >= 4`, and `0 <= T_max <= T`. The base source must declare
`use_growth_rate_ar1=false`. The two remaining calibration markers must be
Boolean. None of these six source values is passed to `BeforeIT.Model`, placed
in the qualified-input hash, or placed in the seed namespace.

The future runner length is the external frozen horizon of four quarters. It is
not read from source `T`. `T_max` is likewise not normalized into a replacement
run control. This matters because the installed 2024Q4 and 2026Q1 artifacts have
the same key schema but `T_max=6` and `T_max=1`, respectively, solely because
different amounts of the later exogenous panel were available.

Nine source diagnostics are also validated for finite values and exact
origin-cross-section shapes, then excluded:

```text
basic_price_fixed_capital_control
basic_price_government_control
basic_price_household_control
basic_price_intermediate_controls_s
commodity_balance_modeled_uses_s
commodity_balance_residual_s
commodity_balance_supply_s
inventory_statistical_discrepancy_s
observed_intermediate_product_taxes_s
```

They document the calibration adapter but are not read by the current model
runtime. The base-irrelevant `Y_EA_series`, `pi_EA_series`, and `r_bar_series`
histories are checked as finite `T_prime` vectors and excluded as well.
Mutating any still-valid excluded value leaves the projected partitions, input
hash, and path seeds unchanged. This prevents economically unused diagnostics
from changing the model's random draws.

The source version inspected by this contract does not contain the optional
13-field opening-macro-control group recognized by newer model code. Supplying
that group is an unknown-key failure. It changes opening-row measurement and
therefore requires a later, separately reviewed source schema rather than a
silent v2 extension.

## Common origin-history axis

Every selected history must have an explicit, contiguous quarterly period
vector containing `2026Q1` exactly once. `C_G`, `C_E`, and `Y_I` must be
`n x 1` matrices; `Y` and `pi` must be one-dimensional vectors. The source
array's first dimension must have a one-to-one period mapping. Every raw and
qualified array, including each period vector, must have conventional
one-based axes before any projection, slicing, copying, or canonical hashing.
Offset arrays fail closed so that `1:origin_index` cannot silently select a
shifted history containing a post-origin observation.

The firewall slices each history through the origin before checking its numeric
values. Every retained axis must then be identical, and:

```text
T_prime =
  origin index =
  common retained-history length
```

`T_prime` must be a positive, non-Boolean, in-range integer. Retained
`C_G`, `C_E`, `Y_I`, and `Y` values must be finite and strictly positive;
retained `pi` values must be finite. A missing or nonfinite post-origin tail is
permitted because it is neither copied nor hashed. A retained or origin-period
mutation changes the dynamic and qualified hashes; a post-origin mutation does
not.

The exact static state is:

```text
D_H  D_I  D_RoW  E_CB  E_k  K_H  L_G  L_I
N_s  S_s  Y_EA  omega  pi_EA  r_bar  sb_inact  sb_other  w_UB
```

`N_s` and `S_s` must be one-dimensional `G`-vectors. `N_s` must contain
nonnegative integer-valued entries and `S_s` must be nonnegative. All remaining
static fields are finite real scalars.

`H_act`, `H_inact`, `J`, `L`, every `I_s` entry, and every `N_s` entry must
also convert exactly to the runtime `Int` type without overflow. Validation is
performed on the original value before the existing Float64 projection, and
converting that projected value back to `Int` must reproduce the original
integer exactly. This rejects both out-of-range values and values such as
`2^53 + 1` that Float64 would silently round. It does not add a second
normalization to `Int`; installed values retain the existing v2 Float64
projection representation.

This is schema, type, shape, range, and projection validation—not full
constructor-domain admission. In particular, v2 does not claim that sector
employment can be allocated or that the active-worker population can absorb
the constructor's assignments. A later no-step constructor preflight must
require:

```text
N_s[g] >= I_s[g] for every sector g
H_W = H_act - sum(I_s) - 1 >= sum(N_s)
all constructed state fields required by the audit are finite
the path construction seed is installed before every constructor call
```

Those checks are deliberately deferred because this v2 contract never calls a
constructor. Its protocol therefore declares
`runtime_projection_schema_validated=true` and
`constructor_domain_admissibility_validated=false`.

## Hash and seed boundary

The qualified-input hash covers the frozen protocol identity, base variant and
constructor identity, origin, exact 60/17/5 projections, retained period axes,
and the protocol-declared excluded member names. It does not cover excluded
source values or post-origin values.

Construction and simulation seeds use the existing registry derivation and the
same domain-separated purposes as v1:

```text
abm_engineering_model_construction
abm_engineering_simulation
```

The qualified-input hash is the origin-manifest component of every seed
namespace. Consequently:

- a consumed parameter, static state, retained history, or retained axis
  mutation changes the qualified hash and seed plan;
- a valid excluded-field or post-origin mutation changes neither;
- construction and simulation namespaces remain distinct for all 32 paths.

The seed mapping is frozen to a 64-bit Julia `Int`, matching the registry's
`UInt64` digest-prefix modulo `typemax(Int)` rule. All 64 construction and
simulation namespace hashes must be globally unique, and all 64 resulting
numeric seeds must be globally unique. A 32-bit runtime fails before
qualification.

The qualified-input hash is an unkeyed integrity and value-binding digest. It
is not authentication and does not prove that an arbitrary, publicly
constructible `QualifiedBaseOriginInputs` object came from the raw frozen
66/34 envelope. A downstream constructor qualification must invoke the
qualifier from the pinned raw artifact in the same process, or verify a
separately authenticated upstream receipt. Merely accepting a rehashed struct
is insufficient. The protocol fixes
`qualified_input_authentication_proof=false`.

This is an input and seed qualification, not proof of input lineage. The period
labels are supplied by the caller and are not independently authenticated.
`input_lineage_verified=false` and
`source_period_labels_authenticated=false` therefore remain fixed.

## Constructor-consumer source closure

The protocol byte-pins the v1 boundary and seed registry and the package and
U.S. environment definitions. It additionally binds the sorted path-and-byte
hash map for all 60 Julia files under `src/` and `ext/`, not merely the files
that visibly define the base constructor. This complete repository source
closure matters because later files included into the same `BeforeIT` module
can add or replace constructor methods. A missing, added, mutated,
symlink-substituted, or out-of-repository Julia source fails validation.

These pins bind the projection allowlist to the audited consumer code. They do
not authorize constructor execution in v2. They also do not authenticate
Preferences.jl state outside the repository. Both supported preference
filenames are required absent beside the root and U.S. projects, while v2
still fixes `runtime_numeric_preferences_validated=false` and
`runtime_julia_version_validated=false`. The no-step v3 gate must load the
pinned environment and require:

```text
VERSION == v"1.10.3"
BeforeIT.typeFloat === Float64
BeforeIT.typeInt === Int
```

Those runtime identities must be included in the v3 receipt before any
constructor call.

The pinned Manifest is an environment declaration, not a byte-level
authentication of package sources, binary artifacts, the Julia executable, or
the depot actually loaded at runtime. Accordingly,
`external_dependency_source_artifact_closure_validated=false`. V3 must bind
the installed dependency trees and artifacts and verify the Julia runtime
before it may claim executable-environment provenance.

## Future variants

`BeforeIT.ModelGR` and `BeforeIT.ModelCANVAS` are rejected by v2. Their future
requirements are documented in the protocol so they cannot inherit the base
schema accidentally:

- growth-rate AR(1): the same five retained histories, plus a separately
  qualified growth-rate calibration contract;
- CANVAS: the five base histories plus `Y_EA_series`, `pi_EA_series`, and
  `r_bar_series`.

A caller cannot supply an alternate `dynamic_keys` list. Supporting either
constructor requires a new version.

## Verification

From the repository root:

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --startup-file=no --depwarn=error --check-bounds=yes \
  --project=scripts/us \
  scripts/us/forecasting/diagnostics/test_revised_data_abm_origin_firewall_v2.jl
```

The suite uses a complete synthetic source envelope and performs a read-only
projection of the installed 2026Q1 JLD2 baseline. It never calls
`BeforeIT.Model`, `ModelGR`, `ModelCANVAS`, `step!`, or `run!`.

The installed smoke projection confirms:

```text
raw parameter keys                 66
raw initial-condition keys         34
source T                           12
source T_max                        1
source T_prime                    117
qualified model parameters         60
qualified static fields            17
qualified dynamic histories         5
retained observations/history     117
retained end period            2026Q1
```

Pinned v2 protocol byte SHA-256:
`efcdce3fb08e0b7496f9293c299787994eda85f2d7f750603a7f5a8b0856cab4`.

Passing this suite creates no model, path, forecast, distribution, truth,
score, empirical origin, promotion evidence, or production artifact.
