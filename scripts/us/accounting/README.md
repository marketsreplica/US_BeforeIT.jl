# U.S. accounting diagnostics and opening candidates

This directory contains the isolated WS-2C supply/make diagnostic and the
separate, non-promoted BEA-anchored opening-accounting candidates. It does not
modify the installed legacy baselines.

Run the hermetic suites from the repository root:

```sh
julia --project=scripts/us --startup-file=no \
  scripts/us/accounting/test_supply_make.jl
julia --project=scripts/us --startup-file=no \
  scripts/us/accounting/test_requirements.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us --startup-file=no \
  scripts/us/accounting/test_after_redefinitions_common_basis.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us --startup-file=no \
  scripts/us/accounting/test_after_redefinitions_model_core.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us --startup-file=no \
  scripts/us/accounting/test_after_redefinitions_valuation_envelope.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us --startup-file=no \
  scripts/us/accounting/test_after_redefinitions_final_use_envelope.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us --startup-file=no \
  scripts/us/accounting/test_after_redefinitions_producer_price_adapter_candidate.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us --startup-file=no \
  scripts/us/accounting/test_after_redefinitions_generic_industry_transform_diagnostic.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us --startup-file=no \
  scripts/us/accounting/test_after_redefinitions_closure_boundary_candidate.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us --startup-file=no \
  scripts/us/accounting/test_after_redefinitions_aggregate_first_scrap_adjusted_diagnostic.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us --startup-file=no \
  scripts/us/accounting/test_after_redefinitions_2017_special_accounts.jl
julia --project=scripts/us --startup-file=no \
  scripts/us/accounting/test_inventory_stock_ledger.jl
julia --project=scripts/us --startup-file=no \
  scripts/us/accounting/test_bea_inventory_stock_diagnostic.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us --startup-file=no \
  scripts/us/accounting/test_inventory_transition_evidence_ledger.jl
python3 \
  scripts/us/accounting/census_m3_inventory_stage/test_generate_census_m3_inventory_stage_fixture.py
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us --startup-file=no \
  scripts/us/accounting/census_m3_inventory_stage/test_census_m3_inventory_stage_evidence.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us --startup-file=no \
  scripts/us/accounting/test_used_other_evidence_ledger.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us --startup-file=no \
  scripts/us/accounting/test_constrained_stone_reconciliation.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us --startup-file=no \
  scripts/us/accounting/test_production_reconciliation_readiness.jl
python3 \
  scripts/us/accounting/oecd_valuation/test_generate_oecd_source_axis_fixture.py
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us --startup-file=no \
  scripts/us/accounting/oecd_valuation/test_oecd_source_axis_valuation_diagnostic.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us --startup-file=no \
  scripts/us/accounting/test_opening_accounting_candidate.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us --startup-file=no --check-bounds=yes \
  scripts/us/accounting/test_portable_accounting_semantics.jl
```

Current focused results:

```text
Supply/make + symmetric use:   167 passed
Official direct requirements: 216 passed
After-redefinitions common basis: 268 passed
After-redefinitions model core: 227 passed
After-redefinitions valuation envelope: 503 passed
After-redefinitions final-use/GDP envelope: 313 passed
After-redefinitions producer-price adapter candidate: 581 passed
Rejected generic industry-transform diagnostic: 244 passed
After-redefinitions closure-boundary candidate: 245 passed
Aggregate-first 68-sector scrap-adjusted diagnostic: 350 passed
2017 detailed special-account reconstruction: 227 passed
Synthetic inventory contract:  94 passed
BEA T50805B diagnostic:        122 passed
Inventory transition evidence: 133 passed
Census M3 stage evidence:       77 passed
Census M3 offline/adversarial:    4 passed
Used/Other evidence ledger:     225 passed
Constrained Stone qualification: 168 passed
Production reconciliation readiness: 160 passed
OECD valuation source axes:     421 passed
OECD offline regeneration:       1 passed
Opening-accounting candidates: 185 passed on the canonical build envelope
Portable opening semantics:     19 passed off the byte build envelope
```

## What is enforced

`USSupplyMakeDiagnostics.jl` keeps economic axes in the type system:

- Table 262 `T007` commodity output is a `CommodityBasis` vector.
- Table 262 `T017` industry output is an `IndustryBasis` vector.
- The domestic make matrix is
  `commodity × industry`, never an unlabeled square array.
- `keyed_difference` aligns equal-basis vectors by code and throws
  `BasisMismatchError` for an industry/commodity comparison. Equal lengths or
  coincident code strings are not accepted as a transformation.

The only transformation in the report is an explicit, code-keyed aggregation:

```text
commodity rows 441 + 445 + 452 + 4A0 -> 4A0
industry columns 441 + 445 + 452 + 4A0 -> 4A0
```

Every source row and column must have exactly one target. `Other` and `Used`
must exist and map to themselves. They remain rows in the aggregated matrix,
purchasers-price supply, total use, and cross-table residual ledger.

The report exposes both source matrices and their audited aggregations:

| Artifact | Archived 2024 shape | Meaning |
|---|---:|---|
| `raw_make` | 73 × 71 | Table 262 commodities, including `Other`/`Used`, by source industries |
| `aggregated_make` | 70 × 68 | Explicit retail aggregation; `Other`/`Used` still present |
| `raw_use` | 70 × 71 | Table 259 intermediate use, including `Other`/`Used`, by source industries |
| `aggregated_use` | 70 × 68 | Explicit retail-industry aggregation; no row is allocated or dropped |

Sparse cells omitted by the BEA API are materialized as structural zeroes.
The matrix retains a separate `explicit` mask, so a downstream reviewer can
distinguish an observed zero cell from an omitted cell.

## Diagnostics, not balancing

`diagnose_supply_make` records the published left side, right side, signed
residual, source-rounding envelope, and pass/fail status for:

- commodity and industry make controls against `T007`/`T017`;
- `T007 + MCIF + MADJ = T013`;
- `Trade + Trans = T014`;
- `TOP + MDTY + SUB = T015`;
- `T013 + T014 + T015 = T016`;
- every Table 262 column control;
- intermediate-use row and column controls;
- `T001 + final uses = T019`;
- Table 259 final-use and grand controls;
- retail-aggregated `T016 = T019` by named commodity;
- the three explicit retail aggregation invariants.

BEA values are whole millions of dollars. A sum of `n` independently rounded
cells is tested against its independently rounded control with the
worst-case envelope `(n + 1) / 2` million dollars. Raw residuals are retained
even when they pass.

There is deliberately no RAS, GLS, cross-entropy, scaling, clipping, residual
allocation, or "balanced" matrix API. Reports are marked:

```text
transformation = code_keyed_retail_aggregation_only
balancing_applied = false
```

A deliberately corrupted fixture proves that failed `T016` and supply/use
values remain failed and unchanged in the returned artifacts.

## Industry-technology symmetric-use diagnostic

`USSymmetricSupplyUse.jl` now performs the first explicit
industry-to-commodity transformation. With `V` denoting the
commodity-by-industry make matrix, `U` the commodity-by-industry
intermediate-use matrix, `g` published industry output, and `q` published
commodity output, it records:

```text
published market shares:  D = V' * diag(q)^(-1)
published product mixes:  P = diag(g)^(-1) * V'
published symmetric use:  Z = U * P
```

The operator is code-keyed and uses the industry-technology assumption. It
returns both the published-control calculation and a separate
rounding-normalized calculation. The latter divides each make row/column by
its observed matrix sum, rather than its independently rounded `q`/`g`
control. This makes market-share columns and product-mix rows sum to one
without changing any source cell. The published version remains available so
the normalization is measurable.

For the archived 2024 fixture:

| Diagnostic | Result |
|---|---:|
| Published-control symmetric-use total | $21,438,537.926745m |
| Rounding-normalized symmetric-use total | $21,438,541m |
| Source intermediate-use total | $21,438,541m |
| L1 difference between the two variants | $20.577411m |
| Largest published `q` versus make-row gap | $4m |
| Largest published `g` versus make-column gap | $4m |
| Negative make / use / derived cells retained | 9 / 5 / 19 |
| Transformation residuals within tolerance | 420 / 420 |

The rounding-normalized 70×70 matrix preserves every source commodity row
total, including `Other` at $172,632m and `Used` at $133,321m. Negative source
cells are preserved: they are neither clipped nor redistributed.

This is not yet the model's production matrix. Table 259 use is at purchasers'
prices, Table 262 make is at producer prices, and `T007` commodity output is
at basic prices. The report therefore explicitly sets
`valuation_bridge_applied=false`, `balancing_applied=false`,
`clipping_applied=false`, and `promotion_ready=false`. `Other` and `Used`
remain 70-axis closure accounts instead of being silently folded into the
68-sector core. BEA documents both industry- and commodity-technology
constructions; the selected assumption is versioned so a later
commodity-technology challenger can be evaluated rather than implied.

## Official direct-requirements comparator

`USRequirementsDiagnostics.jl` now uses BEA's directly published
after-redefinitions matrices as the primary coefficient route. The two
official workbooks provide:

```text
B: 73 commodities × 71 industries, direct requirements
D: 71 industries × 73 commodities, market shares
A: B * D, aligned by commodity code
Z: A * diag(q)
```

Here `q` is the separately published 73-commodity Table 262 `T007` output
vector. The previous `A = I - inv(L)` calculation from the 73×73 Table 59
total-requirements matrix `L` remains in the report, but only as a
published-rounding round trip. It is no longer the primary direct-coefficient
source.

The canonical projection also preserves all three value-added rows, the 71
industry-total controls, five negative `B` cells, the one negative `D` cell,
and the explicit `Used` and `Other` commodities. Nothing is clipped,
balanced, or reordered. Its 221 controls comprise:

- 71 direct-input-plus-value-added industry totals;
- 73 market-share column sums;
- 73 Table 59 total-output controls;
- four direct, total, published-Leontief, and numerical-inverse round trips.

The checked-in current-vintage result is:

| Diagnostic | Result |
|---|---:|
| Published `B` / `D` shapes | 73×71 / 71×73 |
| Source and round-trip controls | 221 / 221 pass |
| Maximum `B*D - (I-inv(L))` cell | `1.051092343e-7` |
| L1 / RMSE direct round-trip gap | `1.453323910e-4` / `3.486409258e-8` |
| Maximum `inv(I-B*D) - L` cell | `1.661504203e-7` |
| Condition number / spectral radius | 2.977312 / 0.476008 |
| Aggregated `Z` shape | 70×70 |
| Transaction-aggregation controls | 3 / 3 pass |
| Cross-system comparison controls | 3 / 3 pass |
| Legacy official-direct, basic-price-T007-scaled transaction total | $21,012,023.990184m |
| Legacy purchasers-price symmetric-use total | $21,438,541m |
| Deliberately mixed-basis total difference | $426,517.009816m |
| Deliberately mixed-basis L1 cell difference | $4,370,627.389108m |
| Cell correlation | 0.966245 |
| Largest absolute cell difference | `42`→`23`, -$142,831.146552m |
| Direct cells below `-1e-6` | 5, all in `Used` |
| Negative source/aggregated transaction total | -$694.185318m / -$694.185318m |

This legacy comparator deliberately combines purchasers-price Table 259 use,
producer-price after-redefinitions coefficients, and basic-price Table 262
commodity output. Its $426,517m difference is therefore a mixed-basis stress
test, not an accounting discrepancy or balancing target. The common-basis
section below supersedes it for the scientific make/use versus direct-
requirements comparison. BEA's
[conversion guidance](https://www.bea.gov/help/faq/34) still matters for the
separate producer-to-basic and purchaser-to-producer bridges; a simple row
ratio cannot reconstruct their cell-specific margin and tax ledgers.

The largest legacy mixed-basis difference remains diagnostic: the official-direct
system places $143,321.681428m of wholesale-trade commodity requirements into
construction, while the purchasers-price symmetric-use diagnostic carries
only $490.534876m in that cell. The wholesale-trade row accounts for a signed
-$1,169,852.332564m of `symmetric - requirements` differences. This is
consistent with margins being embedded in purchasers-price product uses but
reallocated to margin-service commodities in the requirements system. It does
not identify a cell-level valuation bridge.

These BEA products share the input-output system after redefinitions; neither
the legacy nor common-basis comparison is independent statistical evidence.
Their cell correlations are descriptive and dominated by common source
structure, not forecast-accuracy scores.

Both sources are explicitly
`CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE`. The loaders pin the complete
manifests, canonical cells, archived source receipt, and member workbooks; they
reject promotion, origin-admission, accounting-gate, or model-state-write
claims.

Official-direct fixture provenance:

```text
source ZIP SHA-256:
e9b9ac6b45bc0385aeb7c21f38ffbcf3eab2e92c0ecadecc43b11ab6dd104eae
acquisition metadata SHA-256:
f3f57a7209f7c6d9b0f76b041f17ae78e9da1d8644dbd7d6815471e740abfaca
CxI_DR_Summary.xlsx SHA-256:
2e128bc5a51e7a12854e9a58afd5ebaca2e384e80abe113fd4274179628b3439
IxC_MS_Summary.xlsx SHA-256:
57c858ae61fa02d6f5b419d265a695318386ec21078ac24d0622f2001aca89d2
10,650-cell canonical CSV SHA-256:
d4df6c610caaca42a9579a4c868efbee6d5f5842467f392bd6a0e75ac8cd748e
manifest SHA-256:
a225951d7ec03aaaaa97f5cc02e58b862e00918dbd31cc35093d80f9dde8c35d
```

Table 59 round-trip fixture provenance:

```text
source / acquisition metadata:
f38f13ac18365fe4a68ad64fc9a6be6661b62893c3b714ee2d070cb7e0cc434d
1cc83c9eec20698bb5a31aaba81eb98dd176126c187399a4d78910c65cebf787
5,402-cell canonical CSV / manifest:
d7285bc44bd9ee40cf51e1a7c0789fdce40b2764b438dec1c598cae81bc31b0b
2bc6040081f9a888639948fe5e5cbf13732a257ee1f62784b19d0aaea4023084
```

`generate_official_direct_requirements_fixture.mjs` reads the XLSX members
with `@oai/artifact-tool`, validates the exact sheet ranges and source
controls, regenerates the byte-identical fixture, and renders eight focused
QA previews. It accepts the archived ZIP, its metadata receipt, the two
extracted workbook members, and an output directory. Table 59 regeneration
remains:

```sh
julia --project=scripts/us --startup-file=no \
  scripts/us/accounting/generate_requirements_fixture.jl \
  TABLE_59_JSON TABLE_59_METADATA_JSON \
  scripts/us/accounting/fixtures/bea_2024_requirements_approved
```

## After-redefinitions common producer-price basis

`USAfterRedefinitionsCommonBasis.jl` removes the mixed-basis ambiguity from
the make/use versus direct-requirements diagnostic. It uses the 2024 producer-
price use and make tables from BEA's
`MAKE-USE-IMPORTS (AFTER REDEFINITIONS).zip`, with:

```text
U: 73 commodities × 71 industries, producer-price intermediate use
V: 71 industries × 73 commodities, producer-price make
g: 71 industry-output controls from the make table
q: 73 commodity-output controls from the make table
B_implied = U * diag(g)^(-1)
D_implied = V * diag(q)^(-1)
Z_source  = U * diag(g)^(-1) * V
Z_direct  = B_published * D_published * diag(q)
```

Every operation aligns by code before materializing an array. The fixture
also retains all 20 producer-price final-use columns, the three value-added
rows, and BEA's separate 2024 import allocation. Imports are not subtracted
from `U`: BEA describes the import matrix as an imputed use allocation, and
the project has not selected a governed total-versus-domestic production
boundary.

The 32,443-cell, 19-projection canonical artifact distinguishes two source
cases that both have numeric value zero:

- `source_cell_kind=selected_zero_not_shown` for BEA's `...` marker;
- `source_cell_kind=numeric` for a published numeric zero.

There are 16,016 ellipsis zeroes and 819 explicit numeric zeroes. All 321
negative source cells, `F030`, `Other`, and `Used` remain unchanged. Nothing
is clipped, balanced, raked, or written to model state.

The import matrix is retained with its published sign convention rather than
treated as an ordinary nonnegative use table. Allocated imported uses outside
`F050` sum to $3,795,870m; the signed `F050` accounting offset sums to
-$3,795,914m. Their -$44m net is source-cell rounding. Of the 58 negative
import cells, 48 are `F050` offsets and 10 are other signed allocation cells.
No import row is subtracted from domestic use.

The checked 2024 result is:

| Diagnostic | Result |
|---|---:|
| Source producer-price intermediate use | $21,438,569m |
| Source industry-technology `Z` | $21,438,566.625123m |
| Published `B*D*diag(q)` | $21,438,542.743527m |
| Signed source-minus-published total | $23.881596m |
| L1 / Frobenius cell difference | $944.840395m / $17.595971m |
| Maximum cell difference | `335`→`5412OP`, -$0.625244m |
| Cell correlation | 0.999999999904 |
| Maximum / L1 implied-versus-published `B` difference | `2.123307e-5` / `0.003963423` |
| Maximum / L1 implied-versus-published `D` difference | `2.789001e-5` / `0.000856513` |
| Direct / market-share interval failures | 0 / 0 of 5,183 cells each |
| Maximum direct / market-share interval ratio | 0.9884042149 / 0.9736681278 |
| Maximum propagated transaction-bound ratio | 0.9373110641 |
| Common-basis source controls | 1,260 / 1,260 pass |
| 2017 valuation controls | 94 / 94 pass |
| Same-system coefficient/transaction controls | 10,521 / 10,521 pass |

The remaining $23.9m grand-total and $944.8m L1 cell differences are
consistent with independently rounded whole-million source cells and
seven-decimal published coefficients. They are retained; no cell is adjusted.
This conclusion is now gated cell by cell: each source ratio uses the
whole-million numerator and output intervals, and each published coefficient
uses its seven-decimal rounding interval. Row, column, and maximum-cell
transaction differences must also fit the propagated coefficient bounds.
Adversarial swaps within a `B` industry column or `D` commodity column are
rejected even when they preserve a grand total. The comparison report retains
both inputs' provenance and research-only source status.

The earlier $426.5bn result is thus diagnosed as predominantly a mixed-output-
and-use-basis artifact, not an inconsistency in BEA's after-redefinitions
system.

The newly projected workbook bottom controls provide independent aggregate
checks:

| Published 2024 bottom control | $m |
|---|---:|
| Intermediate use `T001` | 21,438,542 |
| `F030` change in private inventories | 53,546 |
| Value added `V004` | 29,298,013 |
| Use-table output `T007` | 50,736,555 |
| Make-table output `T017` | 50,736,556 |

The `F030` commodity cells sum to $53,545m, one million below the published
bottom control and within source rounding. Its 40 ellipsis flags are retained
separately from numeric zeroes rather than lost when the vector is extracted.

The fixture also retains BEA's only purchaser-price summary table in this
archive, the 2017 benchmark. After the explicit
`441 + 445 + 452 + 4A0 -> 4A0` commodity aggregation, its 70×91 purchaser
matrix is compared with the 2017 producer matrix:

| 2017 valuation benchmark | Result |
|---|---:|
| Published producer / purchaser grand total | $34,468,130m / $34,468,130m |
| Producer / purchaser cell sum | $34,468,125m / $34,468,139m |
| L1 purchaser-minus-producer redistribution | $8,169,470m |
| Largest recipient-column total gap | $5m |
| Negative producer / purchaser cells retained | 70 / 68 |

This historical pair demonstrates the scale and topology of commodity
valuation redistribution while conserving user totals within source
rounding. The equal published grand totals show that the -$5m and +$9m cell-
sum deviations are independent table rounding, not a $14m aggregate valuation
change. The benchmark does not identify margin, transport, tax, or subsidy
components and is explicitly blocked from acting as a 2024 allocator.

Provenance is byte-pinned:

```text
source ZIP / acquisition metadata:
c93326b3e4ba3bc2024165448800acb89e9b549090b6b4e0c0c0db27c0eea7da
8be9fbef6e2c18a7388cd61bd14312159fc3984d4dbc2c60158e977ee7f0e878
producer use / make workbooks:
9e3791d657909843ce202161bae00cf8a425d7e1bf866cc8a0462810f0ae00c7
073b87c7e52e76fb78ad7ddafb0c2e60f9188fc5a4e56dc0094f4a7ae3f529c6
import / purchaser-use workbooks:
9246c68288bb593495366288b9d8fd2038cae1ff500855ccd3e5c4377d0d3b25
9d55530ec5cd4688855ef474c779d0dba5f2e1e74d4fcfcdc95cddc64c69262b
canonical CSV / manifest:
6c0c44ca0ac3f70c5d51d6b3a58fca2a02283e9e6f50a254ae663d12f187f0ac
ff555043829e5d12ba787ba9ad7d58ef4f0d2ee306740d6847bdfec800935030
```

`acquire_bea_after_redefinitions.jl` refuses a changed URL response, media
type, byte count, or ZIP hash. The deterministic spreadsheet projection uses
the workspace dependency loader's Node runtime and
`@oai/artifact-tool` 2.8.39:

```sh
BEFOREIT_NODE_MODULES=/path/from/workspace-loader/node_modules \
  /path/from/workspace-loader/node \
  scripts/us/accounting/generate_after_redefinitions_common_basis_fixture.mjs \
  SOURCE_ZIP SOURCE_METADATA_JSON \
  IOUse_After_Redefinitions_PRO_Summary.xlsx \
  IOMake_After_Redefinitions_PRO_Summary.xlsx \
  ImportMatrices_After_Redefinitions_Summary.xlsx \
  IOUse_After_Redefinitions_PUR_Summary.xlsx \
  OUTPUT_DIRECTORY QA_DIRECTORY
```

The generator pins the four member hashes and all 19 exact projections,
reproduces the CSV and manifest byte-for-byte, validates source controls and
sign counts, and renders focused QA previews. This remains current-vintage
research evidence: it was not prospectively captured for a forecast origin,
cannot change an accounting gate, and cannot write a model state.
Producer-to-basic product-tax allocation, the full final-use/value-added
three-approach GDP ledger, the domestic/import boundary, `Other`/`Used`
policy, review of signed allocation cells outside `F050`, inventory
holder/stage mappings, latent-state reconciliation, and an externally bound
multi-archive release identity remain hard blockers.

This is a same-system accounting and rounding diagnostic, not independent
forecast validation. It contributes zero admitted forecast origins and zero
ABM, equilibrium, AR, VAR, or BVAR accuracy scores.

## After-redefinitions 68-sector model-core aggregation

`USAfterRedefinitionsModelCore.jl` applies the declared model dimension only
after the pinned producer-price common-basis system has passed. The mapping
identity-maps every model sector except the four source retail codes
`441`, `445`, `452`, and `4A0`, which are summed to model code `4A0`.
The result has a 68×68 model core plus separate typed `Used` and `Other`
closure accounts; neither closure commodity is dropped or allocated into the
core.

The two mapping identities are:

```text
after_redefinitions_model_core_mapping.toml:
546b3dc15cbb194210ce564a44626b146551b161ca0ce5ffb90a8a5261b4553c
scripts/us/bea71.toml sector contract:
2e0fb0a6d8190e4488810653a2638edeff9ceae2a1ea463f28730106752b183f
```

Every source cell and explicit/ellipsis mask enters exactly one core or
closure aggregate. The checked current-dollar totals, in millions, are:

| Block | Model core | `Used`/`Other` closure | Recombined source |
|---|---:|---:|---:|
| Producer intermediate use | 21,165,843 | 272,726 | 21,438,569 |
| Producer final use | 29,550,990 | -252,983 | 29,298,007 |
| Producer make | 50,716,812 | 19,740 | 50,736,552 |
| Commodity output | 50,716,816 | 19,740 | 50,736,556 |
| Import intermediate use | 1,776,783 | 181,714 | 1,958,497 |
| Import final use | -1,776,831 | -181,710 | -1,958,541 |

All $29,298,014m of producer value added and $50,736,554m of industry
output remain on the 68 producing-industry columns. The closure commodity
output is $13,553m for `Used` and $6,187m for `Other`. The aggregation
conservation checks are exact; published-table rounding controls remain
separate.

Negative cells are also retained by block:

| Matrix | Model core | Closure-associated |
|---|---:|---:|
| Producer intermediate use | 0 | 5 |
| Producer make | 1 | 0 |
| Symmetric intermediate transactions | 0 | 6 |
| Import allocation | 56 | 2 |

Imports remain a typed, separate BEA imputed-allocation ledger. Its declared
sign convention is positive allocated uses plus the signed `F050` accounting
offset; signed non-`F050` exceptions remain visible for review. It is not
subtracted from producer use and `domestic_use_subtraction_applied=false`.

| Import-allocation diagnostic | Model core | Closure | Recombined source |
|---|---:|---:|---:|
| Allocation excluding `F050`, $m | +3,409,217 | +386,653 | +3,795,870 |
| Signed `F050` offset, $m | -3,409,265 | -386,649 | -3,795,914 |
| Net, $m | -48 | +4 | -44 |
| Negative `F050` cells | 46 | 2 | 48 |
| Other negative allocation cells | 10 | 0 | 10 |

The report keeps two 70×70 transaction routes: aggregate the source symmetric
system, or aggregate `U` and `V` first and then recompute it. Their
source-versus-recomputed residual has L1
`4.2105847996611045e-10`, Frobenius
`6.421245119608913e-11`, maximum cell
`2.9103830456733704e-11`, and correlation `1.0`. This is only Float64
summation-order noise. Each of the four retail make rows is a diagonal
one-output row whose output maps to the same aggregate retail commodity, so
the near-zero residual is not a technology effect or an accuracy statistic.

All 494 runtime controls pass. The public
`model_core_controls_pass(report, fixture, mapping_path;
sector_mapping_path=...)` gate requires the source fixture and both mapping
contracts. It reloads the pinned common-basis fixture, rebuilds the full
report, and recursively compares it with the candidate. There is deliberately
no one-argument public overload. The report-only algebra/policy check is
explicitly named `model_core_internal_controls_pass(report)` so it cannot be
mistaken for source attestation. The source-aware gate rejects a balanced
in-memory 2×2 cycle even though that mutation preserves every tested row and
column total. The focused suite passes 227/227 assertions.

This is a research-only dimension bridge. It applies no closure or residual
allocation, producer-to-basic tax bridge, domestic/import boundary choice,
balancing, clipping, model-state write, accounting-gate effect, forecast-
origin admission, promotion, or forecast score. WS-2C therefore remains in
progress. Its next accounting step is the complete
valuation/tax/import/final-use ledger.

Promotion blockers are inherited monotonically from the common-basis report,
with the retail-origin aggregation blocker added rather than any upstream
blocker removed. In particular, imports remain separate imputed evidence,
signed non-`F050` allocations require review, and final use/value added are
not fully reconciled.

## After-redefinitions valuation envelope

`USAfterRedefinitionsValuationEnvelope.jl` joins two separately captured
current-vintage 2024 supply systems without pretending that their commodity
rows are already interchangeable. The byte-pinned contract is:

```text
after_redefinitions_valuation_envelope.toml:
110f82037e45e1de3ce4f5a1df2b7982d064e90a9323f255c7441452fa6d2ede
```

Table 262 supplies 12 before-redefinitions commodity controls: domestic
basic-price output, imports and import adjustments, trade and transportation
margins, product taxes, duties, subsidies, and purchasers-price supply. The
after-redefinitions make workbook supplies producer-price commodity output.
The report retains a 73×12 source matrix, a 68×12 model-core aggregation, and
a 2×12 `Used`/`Other` closure block. Their explicit masks distinguish the 672
published source cells from structural zeroes absent from the sparse source.

At the grand-total level, the two independently rounded routes agree exactly:

```text
after-redefinitions producer output cells      50,736,556
before-redefinitions basic output cells        49,726,234
before-redefinitions net product-tax cells      1,010,322
basic output + net product tax                  50,736,556
```

The corresponding published controls also agree exactly:
`50,736,556 = 49,726,230 + 1,010,326`, all in millions of
current dollars. This is an aggregate valuation identity, not a cell
allocator. By commodity, the retained diagnostic vector

```text
R = after-redefinitions producer output
    - before-redefinitions basic output
    - before-redefinitions net product tax
```

has signed total zero but L1 magnitude $1,254,404m, Frobenius magnitude
$412,844.976905m, 32 negative cells, 31 zero cells, and 10 positive cells.
Its largest absolute entry is wholesale trade (`42`) at +$314,881m, and the
four retail rows sum to +$312,316m. The 68-sector core sums to +$23,351m,
offset by -$23,351m in the `Used` closure account. The cell correlation of
`0.9981283834` is descriptive common-source structure, not accuracy evidence.

Because no external receipt binds the two archives to one release state, the
vector cannot be attributed solely to redefinitions. It is retained as an
impossibility witness for a scalar or ungoverned proportional bridge. No part
is balanced, clipped, or allocated across intermediate or final uses.

The report exposes two model-core product-tax controls:

- observed Table 262 `T015`, totaling $986,971m in the core plus $23,351m in
  closure; and
- an explicit-zero policy counterfactual.

Both are diagnostics only. Neither allocates tax to use cells, changes a model
state, affects an accounting gate, or admits a forecast origin. Margin and
transport use-cell allocation, transition testing of both tax variants,
closure policy, full final-use/value-added reconciliation, and an externally
bound multi-archive identity remain required.

All 324 runtime controls and 503 focused assertions pass. The public
`valuation_envelope_controls_pass(report, contract_path; ...)` gate requires
the contract and source paths, reloads every byte-pinned input, rebuilds the
envelope, and compares every field. There is no one-argument public gate.
Tests prove that compensated optional-component changes and explicit-mask
changes can remain internally self-consistent but are rejected by the
source-aware gate, as are changed fixture, manifest, contract, and mapping
bytes.

This slice advances the valuation evidence envelope but does not complete
WS-2C. It contributes zero admitted origins and zero ABM, equilibrium, AR,
VAR, or BVAR forecast scores.

## After-redefinitions final-use and GDP envelope

`USAfterRedefinitionsFinalUseEnvelope.jl` partitions all 20 producer-price
final-use columns into seven code-keyed categories without changing a source
cell: household consumption, private fixed investment, inventory change,
exports, the signed imports accounting offset, government consumption, and
government gross investment. Its byte-pinned contract is:

```text
after_redefinitions_final_use_envelope.toml:
b4e3969a52618b4e462b8e468ada784dda85cae86550fb27659d2afbb4cbb2be
```

The report retains the 73×20 source block, 68×20 model block, and 2×20
`Used`/`Other` closure block, together with 73×7, 68×7, and 2×7 category
views. Category masks use logical OR, so an explicit source zero remains
distinct from an absent structural zero. The producer-price category totals
are:

| Category | 68-sector core, $m | `Used`/`Other`, $m | Cell total, $m | Published control, $m |
|---|---:|---:|---:|---:|
| Household consumption | 19,853,257 | 42,750 | 19,896,007 | 19,896,009 |
| Private fixed investment | 5,360,603 | -154,828 | 5,205,775 | 5,205,774 |
| Inventory change | 44,095 | 9,450 | 53,545 | 53,546 |
| Exports | 2,528,675 | 254,403 | 2,783,078 | 2,783,078 |
| Imports accounting offset | -3,294,892 | -386,649 | -3,681,541 | -3,681,538 |
| Government consumption | 3,991,840 | 0 | 3,991,840 | 3,991,840 |
| Government gross investment | 1,067,412 | -18,109 | 1,049,303 | 1,049,304 |

The signed `F030` inventory entry remains an annual flow, not a quarter-end
stock. Signed `F050` remains the imports accounting offset in final use, not
a nonnegative model import-demand vector. Closure intermediate use is
$272,726m and closure final use is -$252,983m; neither is allocated to the 68
model sectors.

All three GDP approaches are visible without forcing equality:

```text
archived cell expenditure GDP:  29,298,007
archived cell income GDP:       29,298,014
archived cell production GDP:   29,297,985

published expenditure GDP:      29,298,013
published income GDP:           29,298,013
published production GDP:       29,298,013
```

The cell expenditure–income and production–income gaps are -$7m and -$29m.
They pass conservative whole-million source-rounding envelopes of $836.5m
and $2,733.5m and are retained rather than balanced. Every 68-sector industry
identity includes both model and closure intermediate inputs plus value
added.

The legacy `T013/T016` commodity quotient is now explicitly classified
`REJECTED_NOT_CELL_IDENTIFIED`. The report records the historical
proportional-recipient-rescale method, but does not apply it. Observed and
explicit-zero product-tax variants remain unallocated controls. The legacy
pipeline source also labels the quotient `DUBIOUS` and records that its
research runtime still applies it pending a producer-price adapter; existing
legacy artifacts are not regenerated or promoted by this diagnostic.

All 275 runtime controls and 313 focused assertions pass. The public
`final_use_envelope_controls_pass(report, contract_path; ...)` gate reloads
the pinned final-use, model, sector, valuation-contract, and supply inputs and
recursively compares the rebuilt report. There is no report-only public
overload. The envelope applies no balancing, clipping, closure allocation,
inventory-stock mapping, import-boundary selection, model-state write,
accounting-gate effect, origin admission, or promotion.

## After-redefinitions producer-price adapter candidate

`USAfterRedefinitionsProducerPriceAdapterCandidate.jl` is the first typed
calibration boundary built from the code-keyed producer-price accounts. Its
byte-pinned contract is:

```text
after_redefinitions_producer_price_adapter_candidate.toml:
de524df56ad47fb1f26534019386b27f1fc45ebc927bda5f39c3ad812259cf58
```

The candidate accepts the annual source accounts but deliberately refuses
runtime materialization. It retains:

- the 68×68 producer-price intermediate-use core and its explicit mask;
- the separate 2×68 `Used`/`Other` intermediate-use sidecar;
- the complete 68×20 and 2×20 final-use blocks and seven-category views;
- direct `F02R` residential-investment composition;
- signed annual `F030` inventory-change flows, without an `S_s` stock;
- signed producer-table `F050` offsets and separate imputed-import matrices,
  without selecting a model imports vector or reexports;
- signed `V001`/`V002`/`V003`, the distinct industry×commodity make matrix,
  commodity output, and industry output; and
- observed and explicit-zero tax controls, neither selected nor allocated to
  use cells.

The core-only production identity leaves a $272,697m gap:

```text
industry output - core intermediate use - value added = 272,697
```

Adding the $272,726m closure sidecar changes the gap to -$29m, the archived
cell-rounding residual already established by the GDP envelope. The sidecar
therefore cannot be dropped or hidden inside a normalized 68-sector input
share. `Used` contributes $100,094m and `Other` $172,632m of intermediate
inputs.

The closure policy is grounded in BEA's
[`Concepts and Methods of the U.S. Input-Output Accounts`](fixtures/bea_io_concepts_methods_2006_approved/Concepts_and_Methods_US_IO_Accounts_2006.pdf).
The PDF is locally pinned at
`535627e5e44f8461c0a04410f4a05c55d47f2e325d9473cb2df06e5d3e6b271d`
with a separate receipt at
`b4b210be3c364415473f1ef407ed7ea6e9edc2b299bd1058c1658b0ebb3b91ac`.
BEA treats used/scrap output as a special commodity/byproduct and describes
`Other` as the noncomparable-import/rest-of-world-adjustment composite. The
candidate accordingly represents neither as an ordinary model commodity or
producer industry.

Every one of the candidate's 92 accounting and boundary residuals and all
581 focused assertions pass. The sector-level omission witness has a
$272,703m core-only L1 gap, a $57,333m maximum in sector `81`, and a 9.514%
maximum output-relative wedge in sector `331`; retaining closure reduces the
L1 residual to $127m and the maximum to $6m.
The public
`producer_price_adapter_candidate_controls_pass(report, contract_path; ...)`
gate reopens every pinned source, mapping, upstream contract, methodology
file, and receipt and recursively compares the canonical rebuild. There is
no report-only public overload. The explicit
`materialize_producer_price_adapter_model_state(report)` method always
throws while closure, trade/reexports, tax, industry/commodity, quarterly
opening-state, and producer-price measurement policies remain unresolved.

The report emits no runtime key and explicitly forbids the legacy
`purchasers_to_basic_price`, product-tax netting/allocation, imports,
reexports, `S_s`, merged-government, FIGARO, parameter, initial-condition,
and model-state keys. It performs no raking, balancing, clipping, tax
selection, closure allocation, annual-to-quarter conversion, state write,
accounting-gate change, origin admission, or promotion. This is source
admission into a typed candidate, not calibration or forecast admission.
The report carries 18 adapter-specific and 24 inherited blockers, 42 total.
Its contract explicitly records
`BEA_NONSCRAP_TRANSFORMATION_REQUIRED_NOT_APPLIED` for `Used` and
`OTHER_NONCOMPARABLE_IMPORTS_AND_ROW_ADJUSTMENT_BOUNDARY_UNSELECTED` for
`Other`.

## Rejected generic industry transform

`USAfterRedefinitionsGenericIndustryTransformDiagnostic.jl` tests the
obvious commodity-to-industry shortcut without allowing it into calibration.
It applies BEA's separately published 71×73 market-share matrix exactly:

```text
Z_71 = D_official * U_producer
Y_71 = D_official * F_producer
Z_68 = A * Z_71 * transpose(A)
Y_68 = A * Y_71
```

The transformation is performed on the complete source axes before the four
retail industries are aggregated to the 68-industry model basis. Published
values, signs, and rounding drift are retained. The official matrix sums to
72.9999995, has one negative cell of -0.0000113, and has a maximum column
residual of 0.0000003. It transforms $21,438,569m of intermediate use to
$21,438,568.426m and $29,298,007m of final use to $29,298,006.672m.

The exact calculation rejects its own runtime interpretation:

- generic `D` spreads the `Used` row over 15 industries, generating
  $100,094.010m of transformed intermediate input and -$86,542.009m of final
  use without applying BEA's nonscrap or used-asset-sale treatment;
- the `Other` market-share column is exactly one at `GFGN`, so the shortcut
  assigns all $172,632m of intermediate use and -$166,441m of final use in
  the noncomparable-import/rest-of-world composite to federal nondefense;
- the transformed rows are industries, not the model's one-good-per-sector
  commodity technology; and
- the official published `D` differs from `make / commodity output` in 437
  cells (L1 difference 0.000856513), so the two sources cannot be silently
  substituted.

The artifact is therefore classified
`REJECTED_GENERIC_INDUSTRY_TRANSFORM_DIAGNOSTIC_ONLY`. Its cross-archive
application is arithmetic-only because the separately captured official
matrix and use accounts are not externally bound to one release identity.
All 83 controls and 244 focused assertions pass, including source-byte,
orientation, normalization, clipping, aggregation-order, closure, and
runtime-flag mutations. The source-aware public gate rebuilds the canonical
report and has no report-only overload. No calibration dictionary, parameter,
state, accounting gate, forecast origin, or score is written.

## After-redefinitions closure boundary

`USAfterRedefinitionsClosureBoundaryCandidate.jl` makes the special-account
boundary executable without inventing `Used` or `Other` industries. Its
source-aware contract pins the complete after-redefinitions, official
market-share, adapter, mapping, supply, methodology, and Table 262 provenance
ledger.

The report retains the signed source ledgers:

| Account | Intermediate use, $m | Final use, $m | `F050`, $m | Make/output, $m | Use-output gap, $m |
|---|---:|---:|---:|---:|---:|
| `Used` | 100,094 | -86,542 | -17,449 | 13,553 | -1 |
| `Other` | 172,632 | -166,441 | -369,200 | 6,187 | +4 |

For `Used`, it computes the make-side scrap component
`h = make[:, Used]`, scrap shares `p = h/g`, nonscrap ratios `1-p`, and the
diagnostic BEA witness. This does not reinterpret the composite account's
signed used-asset transfers as scrap:

`W = (I - diag(p)) \ D_core`. The maximum scrap share is 0.817591% in
industry `332`; all shares are in `[0,1)`. `h` has 14 positive industries and
sums to $13,553m. No explicit matrix inverse is formed.

`D_core` and `W` are deliberately source-only, cross-archive witnesses. The
contract records that the rounded official `D` is not interchangeable with
same-table `make / commodity output`, and that the future 68-sector
construction must aggregate make, output, and scrap before forming the
nonlinear ratios and `W`. That aggregate-first transformation is not built
or promoted by this artifact.

The report also exposes why `Other` remains necessary:

```text
D_core * q_core - ((I - P) * g - o)
g - W * q_core - (I - P) \ o
```

where `o = make[:, Other]`. This is a make-side accounting placement, not
evidence that `GFGN` economically produces `Other`. The residual vectors
preserve official-matrix rounding separately from the $6,187m `Other` output
requirement. They do not
fold `Other` into the scrap share, assign it to domestic production, or infer
a rest-of-world financial counterpart.

All 30 controls and 245 focused assertions pass. The suite pins masks, signs,
the five negative `Used` intermediate cells, 14 scrap origins, `F050`,
use/output gaps, every formula and residual vector, adapter reconciliation,
closure disjointness, no-smearing witnesses, all runtime flags, all source
bytes, and a throwing materializer. The public gate checks internal controls
before rebuilding from every pinned source. It writes no `U`, `a`, `beta`,
price, quantity, RoW, FIGARO, parameter, initial-condition, state, gate,
origin, or score.

## Aggregate-first 68-sector scrap-adjusted diagnostic

`USAfterRedefinitionsAggregateFirstScrapAdjustedDiagnostic.jl` performs the
next same-table construction without loading the separately published
market-share matrix. It aggregates the pinned 2024 after-redefinitions
ordinary commodity and industry levels first and only then forms:

```text
U68 = A * U71 * A'
F68 = A * F71
V68 = A * V71 * A'
q68 = A * q71
g68 = A * g71
h68 = A * make[:, Used]
B68 = U68 * diag(g68)^-1
D68 = V68 * diag(q68)^-1
W68 = (I - diag(h68 / g68)) \ D68
H68 = B68 * W68
```

Here `h` is only the make-side scrap component of the composite `Used`
account. The signed `Used` use and final-use rows also contain used and
secondhand asset transfers and remain in the closure sidecar; they are not in
`U68` or final demand. Likewise, `o = A * make[:, Other]` and the derived
`Other` term are make-side arithmetic witnesses, not allocations of the
noncomparable-import or rest-of-world-adjustment use rows.

The same-table totals are $21,165,843m intermediate use, $29,550,990m final
use, $50,716,812m ordinary make, $50,716,816m commodity output,
$50,736,554m industry output, $13,553m scrap make, and $6,187m `Other` make.
The maximum scrap share remains 0.817591% in `332`. The resulting requirements
matrix has spectral radius 0.466094 and `cond(I-H)=2.913215`; these are
numerical stability diagnostics, not runtime validation.

The `q`-composition-weighted source comparisons
`W68 ≈ A*W71*Cq` and `H68 ≈ A*H71*Cq` are explicitly conditional facts about
this pinned table, not general aggregation identities. The report verifies
the necessary merged-retail facts: `441`, `445`, `452`, and `4A0` have zero
`Used` and `Other` make; each source-industry make row contains only its
identically coded commodity; and that cell equals the industry's output. The
unweighted `A*W71*A'` shortcut is rejected.

Coefficient equality does not make transformed flows commute. Aggregate-first
and source-first transformations differ by $1,151.303m L1 for intermediate
flows and $2,562.398m L1 for final use; the largest cells are in the aggregated
retail row. The unadjusted `Other` omission is $1,927.473m L1. Adding its
arithmetic term reduces the fixed-point equation residual to $120.330m L1,
but still selects neither a domestic nor a rest-of-world boundary.

All 39 report controls and 350 focused assertions pass. Exact source explicit
masks are hash-checked, derived mask keys are closed, linear-algebra goldens
use portable tolerances, and an independent review confirmed the aggregation
preconditions. BEA's methodology note that coefficients are calculated at
the aggregation level of the published table is retained as additional local
evidence at physical PDF page 213 (printed page 12-11). The artifact is
current-vintage, research-only, has a throwing materializer, and changes no
runtime state, gate, origin, truth, or score.

## 2017 detailed `Used`/`Other` reconstruction evidence

`USAfterRedefinitions2017SpecialAccounts.jl` loads a byte-pinned 2017
benchmark fixture that preserves the four detailed components `S00401`,
`S00402`, `S00300`, and `S00900` alongside the independently published
summary `Used` and `Other` accounts. The official four-to-two component
crosswalk is separately byte-pinned to BEA's printed page 15. The ten
projections retain all selected
402-industry detail cells, all 71-industry summary cells, 20 final-use
columns, aggregate controls, make placements, signs, explicit numeric zeros,
and all native BEA cell kinds.

The 3,644-cell fixture contains 708 numeric cells, 2,748 native blanks, 188
literal BEA ellipses, 50 explicit numeric zeros, and 36 negative cells. The
derived selected-zero-not-shown mask is exactly blank union ellipsis. Its
accepted reconstruction scope is deliberately narrower than the retained
topology: the component crosswalk is pinned, but no official 402-to-71
**industry** crosswalk bytes are pinned, so no cellwise intermediate or make
aggregation is claimed. Code-keyed final-use reconstruction differs only at
independently rounded cells:

| Summary cell | Observed minus detailed reconstruction, $m |
|---|---:|
| `Used/F010` | -1 |
| `Used/F040` | -1 |
| `Other/F050` | +1 |

Every other final-use cell matches, and `T001`, `T004`, `T007`, plus
composite make/output totals reconstruct exactly. The source make ledgers
retain the $3,468m detailed `S00900 × S00600` and summary
`Other × GFGN` placements as accounting observations only. They do not
identify a producer agent, government behavior, cashlessness, or a
current-vintage component weight.

The 227 focused assertions pin every source and generated byte, projection
axis, address, native mask, residual, placement, component crosswalk, and
false runtime/promotion flag. A committed acquisition receipt is now an
actual generator input. Separate generation receipts truthfully identify the
openpyxl 3.1.5 and artifact-tool 2.8.39 readers; both regenerate
byte-identical CSV and TOML artifacts. The weekly remote-fixture workflow
also regenerates with the independent openpyxl route from the exact official
ZIP. The materializer always throws; the evidence cannot write calibration,
state, gate, origin, truth, or score data.

## Inventory-stock ledger contract

`USInventoryStockLedger.jl` establishes stock semantics independently of any
particular source receipt or holder-to-commodity bridge. Its five-row fixture
is deliberately synthetic and therefore cannot affect an origin, accounting
gate, or model state.

The contract enforces end-of-period timing, no SAAR division, billions-to-
millions conversion by ×1000, exact M3
`total = materials + work_in_process + finished_goods` additivity, common
source/valuation/scope/holder/period/coverage across identity terms, and
`MISSING_NOT_ZERO`. It separately blocks the holder-to-commodity,
cost-to-model-price, and stage-to-model-stock-scope bridges. In particular,
M3 finished goods is not silently equated with the model's sellable `S_s`.

The 94-test suite pins the complete manifest and CSV and proves that mixed
identity semantics, widened tolerances, relabeled coverage, fake source
hashes, origin claims, gate claims, and model-write claims fail closed. This
is a schema and boundary checkpoint, not source evidence. The separate
current-vintage T50805B diagnostic below supplies verified aggregate holder
controls, but a prospective origin still needs origin-time T50805B, M3,
wholesale, retail, and allocation receipts before any inventory vector can be
emitted.

## BEA T50805B current-vintage inventory diagnostic

`USBEAInventoryStockDiagnostic.jl` loads a pinned, redacted BEA NIPA
T50805B response for 2026Q1. The fixture preserves all 29 published rows:
24 end-of-quarter stock rows, two final-sales denominators, and three
published inventory-sales ratios. Duplicate totals remain addressable by line
and are never blindly summed. The diagnostic applies no annual-rate division
and does not reinterpret a difference between these end-of-quarter,
current-price stocks as NIPA change in private inventories.

The 122-test suite verifies the redaction without mutating the captured wire
bytes, the complete typed projection, the 2026Q1 period and units, 11
published stock identities within whole-million rounding, and three published
ratios within their 0.005 rounding tolerance. The checked result records
$4,223,030m of private inventories, including $310,129m farm and $3,912,901m
nonfarm inventories. Manufacturing, wholesale, and retail controls are
$1,226,802m, $1,218,329m, and $985,965m.

The redacted response, metadata receipt, content fingerprint, canonical CSV,
and manifest are hash-pinned:

```text
redacted source SHA-256:
428eb140bc2977b78d65f55da0470e9d1eab2d75b2bba4ef021a4f1014bdefbe
acquisition metadata SHA-256:
8c06cc9ff25b0c13af8bd40cf594b6b6b1073a97ffd4cf344f76365f1cf0bb97
content fingerprint SHA-256:
e141b2edd846e8046af278b33e9fe3951e6416e03c41d953351b1784bc916ab1
29-row canonical CSV SHA-256:
43ee3f1764c3505f1f752b8115206113dc14d145d412d6b232be7d1656b4d7f4
manifest SHA-256:
c1e7c6aa1469557844307478170c9d4820898a49e67c258da49c0c596cbab3f6
```

This is verified current-vintage source evidence, not an origin-time
first-release receipt. It is classified
`CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE` and has no accounting-gate
effect. Holder-to-model-sector and holder-to-commodity mappings,
end-of-quarter-price-to-model valuation, inventory-stage decomposition and
stage-to-model-stock scope, latent-state reconciliation, and origin-time
receipt evidence remain absent. Consequently it emits no `S_s`, authorizes no
model-state write, and cannot promote a forecast origin.

## Inventory transition evidence ledger

`USInventoryTransitionEvidenceLedger.jl` now places the available inventory
evidence in one typed ledger without pretending that the sources identify a
stock transition. It retains 119 signed quarterly NIPA T10105 CIPI
observations, 24 T50805B end-of-quarter holder-stock rows, 70 annual
after-redefinitions producer-price F030 commodity/closure rows, and five
explicitly synthetic stage-contract rows. The synthetic rows remain marked
non-evidentiary.

The source boundaries are deliberately separate:

| Evidence | Time/axis/valuation basis | Checked result |
|---|---|---:|
| T10105 CIPI | quarterly transaction flow, current dollars | 94 positive / 25 negative observations |
| T50805B | one 2026Q1 end-of-quarter holder stock, current cost | $4,223,030m private total |
| After-redefinitions F030 | 2024 annual producer-price commodity flow | $44,095m core + $9,450m closure |
| Synthetic stage fixture | schema-only materials/WIP/finished-goods comparator | non-evidentiary |

The 73-cell F030 sum is $53,545m, or -$1m from its separately published
$53,546m column control under the 73-cell, whole-million rounding envelope.
The independent published F030 control is then compared with the four 2024
T10105 quarters, which also sum to $53,546m: the cross-source residual is
exactly $0m under its separately declared ±$1m bound. The cell-to-control and
published-control-to-published-control checks are deliberately distinct; no
correction is applied. The older Table 259 purchasers-price F030 decomposition
is a different valuation/source boundary and is neither loaded nor mixed into
this ledger.

All eight possible transitions remain `NOT_RUN_BLOCKED`: prior-period stock,
revaluation/timing, holder-to-commodity, annual-to-quarterly, observed stage,
`Used`/`Other`, origin-vintage, and model stock-scope reconciliation evidence
are missing. Their diagnostic values and tolerances are structurally missing,
not numeric zero. The contract also binds the implementation module under a
declared normalized-hash policy and binds the runner by its raw SHA-256. The
133-test suite and deterministic writer confirm 218 observations, 19 source
checks, eight blocked assessments, and zero model vectors, `S_s` fields, state
writes, gates, or origins.

## Census M3 manufacturing inventory-stage evidence

The isolated `census_m3_inventory_stage` artifact pins the exact current
Census M3 historical workbook and projects all 316 series without network
access. It retains 158 seasonally adjusted and 158 unadjusted series: 172
total-inventory series and 48 each for materials and supplies, work in
process, and finished goods. Of 132,720 monthly cells, 130,824 are numeric and
1,896 future workbook cells are source-missing, not zero.

For the 48 same-code adjusted/unadjusted stage sets, 19,872 published
identities close exactly:

```text
total inventory = materials and supplies + work in process + finished goods
```

Another 288 identities are `NOT_RUN_SOURCE_MISSING` for 2026-07 through
2026-12; none is numerically filled. The zero residuals are controlled
accounting identities, not independent validation of the stage estimates.
Census explains that many companies report total inventories but cannot
report stages, so it ratio-estimates the three stages and proportionally
allocates the discrepancy to the total-inventory control; a corresponding
control is applied after seasonal adjustment.

M3 covers domestic manufacturing establishments, reports end-of-month stock
levels in current-cost/current-market terms without price adjustment, and the
current workbook can revise history. It does not cover the rest of the
economy, identify a BEA commodity/holder crosswalk, supply a prior-quarter
stock-flow/revaluation bridge, or show that finished goods equal the model's
sellable stock `S_s`. The artifact is therefore current-vintage,
origin-ineligible evidence and emits no allocation, transition, state, gate,
origin, or score. The 77 Julia assertions and four offline/adversarial Python
tests bind the raw workbook, receipt, source masks, source methodology,
implementation, exact identities, and negative guarantees.

## Used/Other evidence and decision ledger

`USUsedOtherEvidenceLedger.jl` turns the special-account boundary into a
vintage-separated evidence ledger instead of guessing a 2024 allocation. The
exact current BEA after-redefinitions archive has producer-detail sheets only
for 2007, 2012, and 2017, although its summary workbooks extend through 2024.
Consequently there is no post-2017 detailed split of `S00401`, `S00402`,
`S00300`, and `S00900`, and the ledger prohibits projecting 2017 component
shares into the 2024 `Used` and `Other` summary rows.

The pinned 2017 detail supports four narrower conclusions:

- `S00401` is mixed evidence: current-production scrap/byproduct output and
  final-user or existing-asset scrap disposal are separate channels.
- `S00402` is a signed existing-good transfer
  (`+$27,562m/-$27,562m`) with no observed output of the underlying good.
- `S00300` is an import-boundary item, not domestic output.
- `S00900` is a residence/final-use reclassification; its source placement
  does not identify a model producer or rest-of-world behavior.

These decisions follow BEA input-output methods, SNA 2008, ESA 2010, the UN
SUT/IOT handbook, and the 2025 OECD extended-SUT handbook. They also preserve
the national-account rule that transfers of existing goods do not create new
output of the underlying good; only separately observed trade, ownership-
transfer, repair, or transport services may add current output.

The ledger retains 4,162 source observations, four typed components, 35 source
checks, nine decisions, and 13 literature records. All nine decisions remain
`NOT_RUN_BLOCKED`: no 2017-share projection, 2024 component split, dealer or
transport allocation, core/model absorption, government-producer inference,
rest-of-world behavior, state write, gate, origin, or score is emitted. The
225 focused assertions and two byte-identical writer runs enforce those
negative guarantees.

## Constrained Stone/GLS method qualification

`USConstrainedStoneReconciliation.jl` implements the equality-constrained
Stone/generalized least-squares estimator

```text
x̂ = y + ΣA′(AΣA′)⁺(b - Ay)
```

with the corresponding posterior covariance, explicit reliability and
covariance classes, exact fixed cells, confirmed structural zeros, signed
cells, and tolerance-ranked treatment of consistent redundant controls. This
checkpoint is deliberately a six-cell synthetic method qualification, not a
balance of BEA or OECD observations.

The frozen benchmark has four adjustable cells and five exact controls of rank
two. Its low-confidence cell absorbs nine times the adjustment of the paired
high-confidence cell, while truth-recovery RMSE falls from
`2.2546248764` to `0.0577350269`, MAE from `1.0` to
`0.0333333333`, and covariance-weighted RMSE from `0.9501461876` to
`0.0527046277`. The maximum control residual is zero, with no sign, fixed-cell,
or structural-zero violations.

The 159-test suite covers covariance validity, redundant and inconsistent
controls, permutations, provenance, deterministic outputs, and adversarial
contract mutations. Ordinary RAS, corrected GRAS, and cross-entropy are
preregistered as `NOT_RUN_BLOCKED` because this signed general-linear
benchmark does not meet ordinary RAS requirements and verified comparator
implementations and priors have not yet been frozen. No production
reconciliation, accounting closure, state write, gate, origin, or accuracy
score follows from the synthetic improvement.

## OECD 2024 source-axis valuation diagnostic

The isolated `oecd_valuation` diagnostic archives 25 exact public OECD SDMX
2.0 responses for the 2024 U.S. supply-use tables: six data CSVs, three
structures, four hierarchies, and twelve codelists. The default generator is
offline and reads only those checked-in bytes; live refresh is an explicit
separate mode.

The resulting 10,675-cell CPA08 × ISIC4 source-axis ledger evaluates an
identity only when every required component is observed:

```text
purchasers = basic + combined trade/transport margin + net product tax
net product tax = gross product tax - subsidy magnitude
```

Of those cells, 4,226 valuation identities are evaluated and 6,449 are
`NOT_EVALUABLE_SOURCE_MISSING`; 1,257 tax identities are evaluated and 9,418
are not evaluable. Evaluated maximum residuals are $0.01m, the source
precision. Missing observations are never substituted with additive zero,
explicit zeros remain observed zeros, and 245 non-basic T1610 rows are
quarantined rather than relabeled. Published OECD controls are:

| Component | $m |
|---|---:|
| Purchasers-price use | 54,568,422.35 |
| Basic-price use | 53,558,096.81 |
| Combined margin | -0.04 |
| Net product tax | 1,010,325.58 |
| Gross product tax | 1,099,681.66 |
| Subsidy magnitude | 89,356.07 |

The net-tax, gross-tax, and subsidy controls agree with the local BEA fixture
within their component-specific half-unit rounding bounds. The combined
margin residual is +$0.96m against a derived $0.505m bound and is therefore
`DUBIOUS_OUTSIDE_DERIVED_CROSS_SOURCE_ROUNDING_BOUND`, not a rounding pass.
OECD purchasers/basic totals exceed the BEA controls by
$150,330.35m/$150,328.81m; those amounts also remain
`DUBIOUS_CROSS_SOURCE_RELEASE_BOUNDARY_RESIDUAL`, unadjusted. A source-axis
observed-tax record and an explicit zero-dynamic-tax record share the same
immutable observed sidecar. Neither performs recipient allocation.

The 421 Julia assertions and the network-disabled Python regeneration test
cover raw response hashes, axes/hierarchies, missing/zero semantics,
explicit not-evaluable identity rows, aggregate-versus-descendant double
counting, sign and label mutations, compensated swaps, candidate identity,
and `Used`/`Other` absorption. CPA08/ISIC4-to-BEA/model mapping, the
trade-versus-transport margin split, resolution of the cross-source margin
discrepancy, fiscal receipts, and runtime transitions remain blocked. This
current-vintage diagnostic has no state, gate, origin, or score effect.

## Archived 2024 evidence

The hermetic fixture is a deterministic numeric projection of every cell in
the approved archived payloads:

| Table | Source SHA-256 | Cells |
|---|---|---:|
| 259 | `2bdd65f04e1bf31fd66d1e642afd0fb9dda2fd9bb5ba3bacf8db83431be1e918` | 4,640 |
| 262 | `91d6686dce15fe1d96f35f1752382bf1d47d274c067f52febc60ae40014406e8` | 1,728 |

The canonical CSV has pinned SHA-256
`c4461fbe971d8fb70750ff4cce6bb09e582a024d7cc1f6e8ebd8e3685bab69e0`
and is loaded without network access. The regeneration script refuses either
raw source unless its bytes match the approved hash:

```sh
julia --project=scripts/us --startup-file=no \
  scripts/us/accounting/generate_fixture.jl \
  TABLE_259_JSON TABLE_262_JSON \
  scripts/us/accounting/fixtures/bea_2024_approved
```

The exact archived run produces 755 residual records, all within their
published-rounding envelopes. Important unadjusted values are:

| Diagnostic | $m |
|---|---:|
| Published `T017/T007` | 49,726,230 |
| Sum of published commodity `T007` controls | 49,726,234 |
| Sum of published industry `T017` controls | 49,726,225 |
| Sum of raw make cells | 49,726,222 |
| Published `T017/T016` | 54,418,092 |
| Sum of commodity `T016` after retail aggregation | 54,418,090 |
| Published Table 259 `T005/T019` | 54,418,093 |
| Sum of commodity `T019` | 54,418,092 |

The maximum absolute cell/control residuals are $4m for commodity `T007`,
$4m for industry output, $1m for each `T016` identity, and $2m for each
`T019` identity. Cross-table purchaser-price supply/use differs only for
commodities `325` and `487OS`, by -$1m each.

The retail result demonstrates why a positional shortcut is invalid:

| Aggregated retail concept | $m |
|---|---:|
| Commodity output, `sum T007[441,445,452,4A0]` | 2,403,974 |
| Industry output, `sum T017[441,445,452,4A0]` | 2,527,001 |
| Difference | 123,027 |
| Purchasers-price supply, aggregated `T016` | 18,144 |
| Table 259 total use, `T019[4A0]` | 18,144 |

`Other` and `Used` also remain visible:

| Code | `T007` output, $m | `T016` supply, $m | `T019` use, $m |
|---|---:|---:|---:|
| `Other` | 6,187 | 375,387 | 375,387 |
| `Used` | 13,553 | 307,187 | 307,187 |

## T10105 controls and non-promoted candidates

`UST10105Controls.jl` converts the approved BEA T10105 current-dollar
quarterly SAAR payload to quarterly flows by dividing by four exactly once.
The tracked fixture contains 119 ordered quarters from 1996Q4 through 2026Q2
and eight controls from lines 1, 2, 7, 8, 14, 16, 19, and 22. Its CSV SHA-256
is
`c453fbdb52cec412ffe41a4d6b791dd6e7432319d6276ea62fef10421414462f`;
the raw source SHA-256 is
`a80351ce2daeccd5994caea385c6ee9f5201fa46ce0c4cab3e7fa19fc8dec574`.
The full panel closes the GDP identity within $0.5m and the GPDI identity
within $0.25m under the explicit $1m source-rounding tolerance. Inventory
investment remains signed.

Regenerate the fixture only from the exact approved raw bytes:

```sh
julia --project=scripts/us --startup-file=no \
  scripts/us/accounting/generate_t10105_fixture.jl \
  SOURCE_JSON SOURCE_METADATA_JSON \
  scripts/us/accounting/fixtures/bea_t10105_2026-08-04
```

Build the separate candidates under the enforced single-thread contract:

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us --startup-file=no \
  scripts/us/accounting/build_opening_accounting_candidate.jl
```

The builder verifies its contract, fixtures, sector mapping, Julia
environment, protected legacy hashes, exact intentional key changes, actual
Julia/BLAS thread counts, and BLAS vendor. The contract now also binds the
executed builder, execution-envelope module, both included source readers,
active Project/Manifest, and the canonical digest of all 57 runtime
`src/**/*.jl` files. Configuration identity is checked before and after the
build, so copied, unverified, wrong-hash, or post-verification-mutated
configuration bytes are rejected. It writes fixed-order JLD2 artifacts only
under `data/us/accounting/candidates` and a manifest under
`data/us/validation`. Rebuild tests compare both semantic hashes and exact
bytes with the installed candidates.

Exact byte reconstruction is now explicitly scoped to the frozen local
execution envelope that produced the artifacts: Julia 1.10.3 on
Darwin/aarch64 Apple M1, bounds mode `auto`, optimization level 2,
`cpu_target=native`, startup file disabled, and one Julia/BLAS thread.
`--check-bounds=yes` changes SIMD/reduction rounding in Julia and therefore
changes thousands of floating leaves at roughly `1e-16` to `1e-8`, even
though the economic gates do not change. A typed envelope mismatch now blocks
rebuilding while still allowing raw/schema/semantic validation of the
installed artifacts on other hosts. The project makes no cross-machine
byte-determinism claim.

`USPortableAccountingSemantics.jl` supplies a separate platform-neutral
semantic lane. It reconstructs both candidates in memory and runs both seeds
through 12 quarters while enforcing typed model/state axes, nominal and real
expenditure, income/production, central-bank and commercial-bank identities,
inventory stock/flow, finite/domain checks, and all fail-closed gates. The
lane asserts `byte_identity_asserted=false` and compares no candidate or state
hash with a golden artifact. Under forced `--check-bounds=yes`, it records the
typed noncanonical envelope mismatch while all semantic invariants pass. This
gives Linux/macOS/Windows CI a real execution test without redefining the
historical Darwin/M1 golden bytes.

| Candidate | Observed GDP residual, $m | Latent model residual, $m | Largest component gap, $m |
|---|---:|---:|---:|
| 2024Q4 | +0.25 | -137,674.939893 | 192,676.843869 |
| 2026Q1 | -0.50 | -147,094.197894 | 182,460.511453 |

For both candidates, the source observation identity passes while latent
state reconciliation, structural supply/use, an origin-eligible and
bridge-complete model inventory vector, full accounting, forecast promotion,
and origin admission fail. The unreconciled T007 diagnostic is
-$99,596.062522m annually and is neither
balanced nor mapped to inventory. The candidates contain no `S_s` or rejected
inventory-discrepancy alias. They are
`REVISED_CURRENT_VINTAGE_DIAGNOSTIC` and
`RESEARCH_ONLY_NOT_PROMOTED`, not forecasts or accuracy evidence.

## Production reconciliation readiness gate

`USProductionReconciliationReadiness.jl` authenticates nine upstream evidence
families and evaluates 45 exact semantic probes before a future reconciliation
can materialize any solver input. The target tuple is frozen as U.S.
calendar-year 2024 annual accounting flows, in millions of current dollars at
producers' prices, on the 68-sector core plus explicit `Used`/`Other` closure
accounts.

The gate deliberately separates evidence validation from solver admission.
The current report has 20 mandatory criteria: four pass and 16 remain blocked.
All 24 open blockers are emitted with the exact source families, evidence,
literature, resolution requirement, and adversarial test needed to close
them. Current counts remain:

```text
admitted solver families:       0
solver input cells:             0
solver input controls:          0
production reliability classes: 0
production covariance classes:  0
approved exact controls:        0
reconciliation runs:            0
adjustment records:             0
```

This zero-input result is substantive. The annual producer-price core and
2024 `Used`/`Other` summary share the declared year/basis but still lack cell
state, sign, import, exact-control, reliability, covariance, and closure
approval. BEA valuation tables and the OECD challenger are quarantined across
price, classification, and release boundaries. T10105, T50805B, and M3 are
flow/stock/stage evidence on different timing, valuation, and holder axes.
The 2017 special-account detail remains semantic evidence only.

The Stone implementation is also correctly classified as synthetic-only: its
problem type requires benchmark truth and rejects production sources. A
separate production observation/control adapter is required; fabricating
truth fields or bypassing its validator is prohibited. The qualification
report now distinguishes three adjustable controls, two fixed-only validation
controls, rank two, and one genuinely dependent adjustable control instead of
mislabeling all three non-rank rows as redundant.

Generate the deterministic blocked-readiness report with:

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us --startup-file=no \
  scripts/us/accounting/run_production_reconciliation_readiness.jl \
  OUTPUT_DIRECTORY
```

The writer rehashes every bound input before and after its semantic probes and
emits artifact, source-family, blocker, criterion, candidate-status, and
manifest reports. It emits no production cell/control file and cannot change
model state, accounting gates, origins, or forecast scores.

## Limitations and next boundary

This prototype establishes source topology and diagnostics; it does not close
the model's opening accounting gate.

- It covers the archived annual 2024 current-dollar summary tables, not an
  origin-eligible historical vintage panel.
- It validates published supply and valuation controls but does not construct
  a full commodity-by-commodity margin, transport, and product-tax allocation.
- The new 73×73 after-redefinitions source diagnostic is internally on a
  producer-price basis. It is not yet bridged to the model's selected
  producer-versus-basic product-tax specification, and the older 70×70
  purchaser/basic comparator remains only as a mixed-basis regression check.
- `Other` and `Used` are preserved as closure accounts but are intentionally
  not allocated into the 68-sector model core.
- Aggregate quarterly NIPA observations are now available to the candidate
  adapter, but latent state/sector reconciliation, an independently sourced
  and origin-eligible model inventory vector, fixed-capital replacement, and
  the three GDP approaches remain unresolved. The current-vintage T50805B
  holder controls do not satisfy the missing allocation and reconciliation
  bridges.
- Passing source-rounding controls proves internal consistency of the
  archived tables. It is not evidence that a later balancing method,
  calibration, simulation, or forecast is economically valid.

The next integration step is now explicitly bounded by the readiness report:
implement the production observation/control schemas and canonical lineage,
then construct and test the complete commodity-by-use margin, transport, tax,
subsidy, import, re-export, and final-use valuation ledger around the
versioned industry-technology diagnostic. Only after the full semantic tuple,
cell states, signed domains, source-specific uncertainty, covariance,
restriction graph, and independent approval pass may the project materialize
Stone inputs or attempt a governed latent-state reconciliation.
