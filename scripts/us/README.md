# U.S. calibration pipeline

This application acquires the public BEA, Federal Reserve/FRED, BLS, Census
SUSB, QCEW, and USDA inputs used by the U.S. BeforeIT calibration. It keeps
downloaded responses immutable under `data/us/raw`, materializes curated
Parquet snapshots, stores the queryable ledger in
`data/us/db/us_calibration.duckdb`, and exports compact JLD2 calibration and
baseline artifacts.

The model sector system has 68 sectors. BEA Table 259 supplies 68 observed
commodity rows and 71 industry columns; the four retail industries (`441`,
`445`, `452`, and `4A0`) are aggregated to the observed retail commodity
`4A0`. The raw 68×71 data, the observed 68×68 aggregation, and the
column-controlled model bridge are all retained. No synthetic retail
commodity split is made.

From the repository root:

```sh
julia --project=scripts/us scripts/us/bootstrap.jl
julia --project=scripts/us scripts/us/us_pipeline.jl all
julia --project=scripts/us scripts/us/us_pipeline.jl status
julia --project=scripts/us scripts/us/test/runtests.jl
```

`BEA_API_KEY`, `FRED_API_KEY`, and `BLS_API_KEY` are read from the repository
`.env`. Credentials are never written to the database, logs, raw metadata, or
artifacts. Some BEA responses echo the request credential; the raw archiver
redacts that echoed field before persistence and records the redaction in the
sidecar metadata.

The validation ledger uses four statuses:

- `APPROVED`: the registered source, definition, units, shape, and tests pass.
- `DUBIOUS`: usable only with the stated proxy, allocation, or model bridge.
- `REJECTED`: a source or construction failed a validity gate.
- `MISSING`: no validated construction is available.

The complete per-source and per-parameter results are written to
`data/us/validation/DATA_CHECKLIST.md` and
`data/us/validation/TEST_LOG.md`.

## Economic-outlook calibration and back-test

The legacy Economic-outlook exercise is an **engineering-only class-H
correction experiment**, not a structural calibration or a pseudo-real-time
forecast validation. It uses seven current-vintage one-quarter targets from
2024Q2--2025Q4 for fitting and reserves 2026Q1--Q2 as a two-observation
holdout. It evaluates 128 common-seed paths, fits Taylor-rule overrides and
seven damped output corrections, and always retains the uncorrected paths
alongside the corrected product.

Raw structural and nowcast artifacts never contain these overrides or output
corrections. `scripts/us/forecast_calibration.toml` is explicitly class H and
is ineligible for raw calibration. Existing pre-firewall artifacts can be
migrated deterministically from their preserved pre-override metadata:

```sh
julia --project=scripts/us scripts/us/migrate_calibration_firewall.jl
```

From the repository root:

```sh
julia --project=scripts/us scripts/us/forecasting/test_calibrate_outlook.jl
julia --project=scripts/us scripts/us/forecasting/calibrate_outlook.jl \
  --n-sims 128 --forecast-horizon 15
```

The frozen calibration contract is `scripts/us/forecast_calibration.toml`.
Quarterly scores, before/after metrics, parameters, corrections, forecast
paths, and the machine-readable summary are written to
`output/us_calibration`. The LaTeX source for the methodology report is
`reports/us_calibration/us_economy_calibration_report.tex`; its compiled PDF is
`output/pdf/us_economy_calibration_report.pdf`.

The proposed evaluation protocol is separate and remains pending independent
validation:

```sh
julia --project=scripts/us scripts/us/forecasting/test_protocol.jl
```

Its machine-readable contract is
`scripts/us/forecasting/protocol.toml`. It governs future vintage-clean
comparisons and does not retroactively validate the engineering exercise.

## Forecast-research contracts

The first hermetic validation primitives can be run independently:

```sh
julia --project=. scripts/us/forecasting/variants/test_variants.jl
julia --project=scripts/us scripts/us/validation/test_bitemporal.jl
julia --project=scripts/us scripts/us/calibration/runtests.jl
julia --project=scripts/us scripts/us/accounting/test_supply_make.jl
julia --project=scripts/us scripts/us/accounting/test_requirements.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us scripts/us/accounting/test_after_redefinitions_common_basis.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us scripts/us/accounting/test_after_redefinitions_model_core.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us scripts/us/accounting/test_after_redefinitions_valuation_envelope.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us scripts/us/accounting/test_after_redefinitions_final_use_envelope.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us scripts/us/accounting/test_after_redefinitions_producer_price_adapter_candidate.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us scripts/us/accounting/test_after_redefinitions_generic_industry_transform_diagnostic.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us scripts/us/accounting/test_after_redefinitions_closure_boundary_candidate.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us scripts/us/accounting/test_after_redefinitions_aggregate_first_scrap_adjusted_diagnostic.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us scripts/us/accounting/test_after_redefinitions_2017_special_accounts.jl
julia --project=scripts/us scripts/us/accounting/test_inventory_stock_ledger.jl
julia --project=scripts/us scripts/us/accounting/test_bea_inventory_stock_diagnostic.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us scripts/us/accounting/test_inventory_transition_evidence_ledger.jl
python3 scripts/us/accounting/census_m3_inventory_stage/test_generate_census_m3_inventory_stage_fixture.py
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us scripts/us/accounting/census_m3_inventory_stage/test_census_m3_inventory_stage_evidence.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us scripts/us/accounting/test_used_other_evidence_ledger.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us scripts/us/accounting/test_constrained_stone_reconciliation.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us scripts/us/accounting/test_production_reconciliation_ledger.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us scripts/us/accounting/test_production_reconciliation_readiness.jl
python3 scripts/us/accounting/oecd_valuation/test_generate_oecd_source_axis_fixture.py
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us scripts/us/accounting/oecd_valuation/test_oecd_source_axis_valuation_diagnostic.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --project=scripts/us scripts/us/accounting/test_opening_accounting_candidate.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --startup-file=no --check-bounds=yes --project=scripts/us \
  scripts/us/accounting/test_portable_accounting_semantics.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
julia --project=scripts/us scripts/us/accounting/test_accounting_transition_harness.jl
julia --project=scripts/us scripts/us/forecasting/benchmarks/test_benchmarks.jl
julia --check-bounds=yes --project=scripts/us scripts/us/forecasting/benchmarks/test_benchmark_model_registry.jl
julia --check-bounds=yes --project=scripts/us scripts/us/forecasting/runner/test_origin_data_receipt.jl
julia --check-bounds=yes --project=scripts/us scripts/us/forecasting/origins/builder/test_trusted_origin_builder.jl
julia --check-bounds=yes --project=scripts/us scripts/us/forecasting/runner/test_benchmark_origin_adapter.jl
julia --check-bounds=yes --project=scripts/us scripts/us/forecasting/scoring/test_forecast_scores.jl
julia --check-bounds=yes --depwarn=error --project=scripts/us scripts/us/forecasting/inference/test_forecast_inference.jl
julia --check-bounds=yes --depwarn=error --project=scripts/us scripts/us/forecasting/inference/regime_adjudication/test_regime_adjudication_ledger.jl
julia --check-bounds=yes --depwarn=error --project=scripts/us scripts/us/forecasting/inference/calibration/test_forecast_inference_calibration.jl
julia --project=scripts/us scripts/us/forecasting/registry/test_registry.jl
julia --project=scripts/us scripts/us/forecasting/origins/test_origin_packages.jl
JULIA_LOAD_PATH='@:@stdlib' JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --check-bounds=yes --depwarn=error --startup-file=no --project=scripts/us scripts/us/forecasting/diagnostics/test_revised_data_abm_constructor_gate_v3.jl
julia --project=scripts/us scripts/us/forecasting/vintages/test_source_release_registry.jl
julia --check-bounds=yes --project=scripts/us scripts/us/forecasting/vintages/availability/test_release_availability.jl
python3 scripts/us/forecasting/vintages/availability/test_generate_timezone_semantics.py
julia --project=scripts/us scripts/us/forecasting/vintages/test_historical_backfill_plan.jl
julia --check-bounds=yes --depwarn=error --project=scripts/us scripts/us/forecasting/vintages/common_window/test_common_origin_window_decision.jl
julia --check-bounds=yes --depwarn=error --project=scripts/us scripts/us/forecasting/vintages/effr/capture_contract/test_effr_capture_contract.jl
julia --check-bounds=yes --depwarn=error --project=scripts/us scripts/us/forecasting/vintages/effr/prospective_acquisition/test_effr_day_zero_acquisition.jl
julia --check-bounds=yes --depwarn=error --project=scripts/us scripts/us/forecasting/vintages/effr/campaign/test_effr_campaign_control.jl
julia --check-bounds=yes --depwarn=error --project=scripts/us scripts/us/forecasting/vintages/effr/recurring_acquisition/test_effr_recurring_acquisition.jl
julia --check-bounds=yes --depwarn=error --project=scripts/us scripts/us/forecasting/vintages/effr/recurring_acquisition_restart_v4/test_effr_recurring_acquisition_restart_v4.jl
julia --check-bounds=yes --project=scripts/us scripts/us/forecasting/vintages/bls_employment/test_bls_employment_archive_capture.jl
julia --check-bounds=yes --depwarn=error --project=scripts/us scripts/us/forecasting/vintages/bls_employment/quarter_end_metadata_manifest/test_bls_quarter_end_metadata_manifest.jl
julia --project=scripts/us scripts/us/forecasting/vintages/bea_schedule/test_bea_schedule_monitor.jl
julia --project=scripts/us scripts/us/forecasting/vintages/bea_nipa/test_bea_nipa_discovery.jl
julia --check-bounds=yes --depwarn=error --project=scripts/us scripts/us/forecasting/vintages/bea_nipa/advance_metadata_manifest/test_bea_hmi7_advance_metadata_manifest.jl
julia --check-bounds=yes --depwarn=error --project=scripts/us scripts/us/forecasting/vintages/bea_nipa/advance_capture/test_bea_hmi7_advance_capture.jl
julia --check-bounds=yes --depwarn=error --project=scripts/us scripts/us/forecasting/vintages/bea_nipa/advance_live_fetcher/test_bea_hmi7_advance_live_fetcher.jl
python3 scripts/us/forecasting/vintages/bea_nipa/era_2017_profile/test_fingerprint_2017q3_advance.py
julia --check-bounds=yes --project=scripts/us scripts/us/forecasting/vintages/bea_nipa/historical/test_bea_hmi7_historical_capture.jl
python3 scripts/us/forecasting/vintages/bea_nipa/historical_fingerprints/test_fingerprint_historical_releases.py
python3 scripts/us/forecasting/vintages/bea_nipa/historical_fingerprints/revision_diagnostic/test_revision_diagnostic.py
julia --check-bounds=yes --project=scripts/us scripts/us/forecasting/vintages/rtdsm/acquisition/test_rtdsm_quarterly_acquisition.jl
python3 scripts/us/forecasting/vintages/rtdsm/fingerprint/test_fingerprint_rtdsm_ooxml.py
julia --project=scripts/us scripts/us/forecasting/vintages/bea_nipa/mapping_audit/test_mapping_audit.jl
julia --project=scripts/us scripts/us/forecasting/vintages/bea_nipa/test_bea_nipa_acquisition.jl
julia --project=scripts/us scripts/us/forecasting/vintages/bea_nipa/test_pilot_2026q2_target_profile.jl
julia --project=scripts/us scripts/us/forecasting/vintages/bea_nipa/test_pilot_2026q2_availability_audit.jl
python3 scripts/us/forecasting/vintages/bea_nipa/test_fingerprint_2026q2_pilot.py
julia --project=scripts/us scripts/us/forecasting/vintages/bea_nipa/receipts/test_bea_workbook_receipts.jl
julia --project=scripts/us scripts/us/forecasting/vintages/bea_nipa/test_pilot_2026q2_present_day_receipt.jl
julia --project=scripts/us scripts/us/forecasting/targets/test_target_coverage.jl
julia --check-bounds=yes --depwarn=error --project=scripts/us scripts/us/forecasting/targets/abm_gdp_operator/test_abm_gdp_operator_qualification.jl
julia --compiled-modules=no --pkgimages=no --check-bounds=yes --depwarn=error --project=scripts/us scripts/us/forecasting/targets/pce_price_analogue/test_pce_price_analogue_qualification.jl
julia --project=scripts/us scripts/us/forecasting/evidence/test_evidence_verifier.jl
```

They cover the paper/code variant crosswalk, exact as-of vintage selection,
the parameter/concept registry, source-aware supply/make topology,
naive/AR/VAR/BVAR/semi-structural challengers, the frozen benchmark-model
registry, the synthetic-only benchmark-origin adapter, the hermetic point,
proper-density, and joint-ensemble score kernel, sealed
forecast/truth/score lineage, and fail-closed origin packages, release-event
provenance, conservative actual-release date intervals, and exact
Tier-1/truth coverage. Passing these engineering contracts is not a
forecast-skill result.

The synthetic ABM GDP operator suite qualifies only pathwise arithmetic for
annualized q/q log real-GDP growth and implicit-GDP-deflator inflation. It
accepts no empirical path or truth, approves no official-concept bridge, and
leaves Tier-1 operator coverage at 0/8.

The independently accepted PCE-price analogue likewise qualifies one
synthetic mechanism only. On positive finite caller-supplied raw paths it
computes `D=N/R` separately by path, then `400*log(D_t/D_(t-1))` and, when
five sequential rows exist, `100*log(D_t/D_(t-4))`. The normalized opening
row may not be stitched to the first post-step row. The post-step ratio equals
the model's `agg.P_bar_h` by construction, but it is not the BEA total or core
PCE Fisher index. It loads no truth and approves no official bridge, so
Tier-1 operator coverage remains 0/8. See
`forecasting/targets/pce_price_analogue/README.md`.

The forecast-comparison inference kernel supplies paired squared/absolute
loss differentials, HLN-corrected Diebold--Mariano inference, joint
studentized stationary-bootstrap draws, and Romano--Wolf stepdown
multiplicity control. It requires an explicit block-length floor policy and
sealed external plug-in provenance. Exact-design size calibration and the
pre-specified historical-origin experiment remain mandatory before any
inferential accuracy claim.

The after-redefinitions valuation-envelope diagnostic separately verifies the
aggregate relation between producer-price output, basic-price output, and net
product taxes. Its commodity redistribution has zero signed total but
$1,254,404m L1 magnitude, so it is retained rather than used as a scalar or
proportional allocation. The 324 runtime controls and 503 focused assertions
pass, but the artifact is current-vintage, research-only, and supplies no
use-cell allocation, model-state write, admitted origin, or accuracy score.

The final-use/GDP envelope then partitions every producer-price final-use
column into seven declared categories and retains the 68-sector core and
`Used`/`Other` closure separately. Archived-cell expenditure, income, and
production GDP are $29,298,007m, $29,298,014m, and $29,297,985m; the -$7m
and -$29m gaps are preserved inside source-rounding bounds, while all three
published-control approaches equal $29,298,013m. Its 275 runtime controls and
313 focused assertions pass. `F030` remains a flow, `F050` remains a signed
accounting offset, and the legacy `T013/T016` proportional bridge is
explicitly rejected for scientific application. This is still a
current-vintage diagnostic with no state write, admitted origin, or score.

The producer-price adapter candidate then turns those ledgers into a typed,
source-aware calibration boundary without claiming runtime readiness. It
retains the 68×68 core, the mandatory 2×68 `Used`/`Other` sidecar, direct
`F02R`, signed annual `F030`, signed `F050` plus separate imputed-import
evidence, all three value-added rows, and distinct commodity and industry
axes. Omitting the closure sidecar leaves a $272,697m production-identity
gap; including its $272,726m of inputs leaves only the established -$29m
source-rounding residual. All 92 candidate residuals pass.
The focused adversarial suite passes 581/581 assertions.

BEA methodology bytes and a receipt are pinned with the adapter: the summary
`Used` account combines a make-side scrap byproduct component with signed
used-asset transfers, while `Other` combines noncomparable imports and the
rest-of-world adjustment. Neither composite is silently folded into the 68
model goods. The adapter emits no FIGARO dictionary,
parameter, initial condition, model state, inventory stock, model imports,
reexports, or selected tax representation. Its materialization method fails
closed until closure, trade, tax, industry/commodity, quarterly state, and
measurement boundaries are governed. It remains current-vintage,
origin-ineligible, and unscored.

The next diagnostic explicitly tests and rejects a generic application of
BEA's published market-share matrix. Exact `D×U` and `D×F` arithmetic followed
by 68-industry aggregation passes 83/83 controls and 244/244 focused
assertions, but it does not separate the make-side scrap treatment from the
signed used-asset-transfer ledger and assigns the entire composite `Other`
account to federal nondefense. The artifact also shows that published `D` and
a make-derived matrix differ in 437 cells. It is an arithmetic falsification
witness only: no transform, state, origin, gate, or score is promoted.

The closure-boundary candidate then computes the BEA make-side scrap
`h`, `p=h/g`, `1-p`, and source-only `W=(I-diag(p))\D_core` witness while
retaining used-asset transfers in the composite `Used` sidecar and `Other` as
an unsplit signed composite. Its 30/30 controls and
245/245 focused assertions pass. The maximum scrap share is 0.817591% in
sector `332`; `Other` contributes a separate $6,187m arithmetic output
requirement without identifying an economic producer.

The official cross-archive `D/W` witness is not a 68-sector runtime
technology: aggregate-first ratios, the noncomparable-import/ROW split,
asset-transfer semantics, financial counterparts, and quarterly dynamics
remain unresolved. No 70-sector expansion or runtime write is allowed.

The same-table aggregate-first diagnostic now builds the 68-sector
scrap-adjusted `B`, make-derived `D`, `W`, and `H=B*W` only after aggregating
levels. Its 39 controls and 350 focused assertions pass. The
`q`-composition-weighted source comparison is explicitly conditional on
verified 2024 retail make structure, while transformed intermediate and final
flows still differ by $1,151.303m and $2,562.398m L1 across aggregation
orders. `Used` use/final asset transfers remain outside the core, and the
make-side `Other` arithmetic witness selects no domestic or rest-of-world
boundary. This current-vintage artifact has no runtime, gate, origin, or score
effect.

The 2017 detailed special-account fixture then verifies the official,
byte-pinned component crosswalk
decomposition `Used=S00401+S00402` and `Other=S00300+S00900` without
borrowing those component shares for 2024. All 3,644 selected detail and
summary cells retain their signs and native masks: 708 numeric, 2,748 blank,
and 188 literal ellipsis cells.
Code-keyed final use has only three independent-rounding residuals
(`Used/F010=-$1m`, `Used/F040=-$1m`, and `Other/F050=+$1m`), while the
published aggregate use and make/output controls reconstruct exactly. The
227 focused assertions also enforce that the observed $3,468m `S00900`
government make placement is not a producer-agent or government-behavior
inference. No 402-to-71 cellwise reconstruction is claimed without a pinned
official industry crosswalk. The exact acquisition metadata is a verified
generator input, and separate openpyxl/artifact-tool receipts record the
reader actually used. No current-vintage, runtime, origin, gate, or score
state is emitted.

Forecast-registry v3 requires every success and failure record to carry
nonzero hashes for both the exact canonical `OriginData` sample and its
provenance receipt. The synthetic-only benchmark adapter requires the concrete
authenticated envelope, cross-binds it to origin/model metadata, executes on a
validated deep copy, and revalidates after the runner. This establishes
hermetic byte/provenance integrity, not semantic proof that the named sources
produced the matrices; empirical execution and production scoring remain
false.

Forecast-registry v3 retains the separate prospective and retrospective-replay modes.
Replay records the historical knowledge cutoff and origin separately from
honest current `execution_*` timestamps. A salted commitment quarantines
already-known truth outside the registry until forecasts are sealed; a
second-stage reveal verifies the exact manifest, nonce, header, seal, chain,
and file hashes before truth can be appended. This removes the incentive to
backdate a replay while preserving the prospective rule that truth releases
after the actual seal. Local clock fields are not external timestamp
attestation, so production promotion still needs trusted time and process/IAM
isolation.

The installed legacy U.S. baselines retain their opening expenditure-side GDP
wedge. Separate 2024Q4 and 2026Q1 candidate artifacts now expose exact BEA
T10105 nominal observations, including signed inventory investment, without
overwriting those baselines. The observed identity passes at source rounding,
but the latent model-state residuals remain -$137.675bn and -$147.094bn.
`data/us/validation/ACCOUNTING_GATES.toml` therefore remains `FAIL`: latent
state, supply/use valuation, an origin-eligible and bridge-complete model
inventory vector, full accounting, forecast promotion, and origin admission
are still blocked. The commodity gap is retained as an unclosed diagnostic
and is never added to capital formation.

The standalone accounting-transition harness runs those two candidate
artifacts under two fixed seeds at exact horizons 1, 4, and 12. It emits one
typed row per candidate, seed, requested horizon, realized period, and
identity, preserving the opening observation residual separately from the
latent-state wedge and never aggregating residuals across time. Available
nominal-income/production, nominal/real expenditure, central-bank,
commercial-bank, finite/domain, and endogenous firm inventory stock/flow
checks are evaluated period by period. Independent observed-tax, explicit
inventory, and confidence-weighted variants remain `NOT_RUN_BLOCKED` with
named blockers. Exact same-seed replay and cross-horizon state-prefix checks
are required, and the candidate artifacts, Julia environment, harness code,
and a canonical digest of all runtime `src/**/*.jl` bytes are pinned. This is
an engineering diagnostic only: origin admission, promotion, forecast
accuracy selection, and runtime selection remain false.

Candidate byte rebuilds are now restricted to the exact local Julia
execution envelope that produced them. A `--check-bounds=yes` audit changed
generic SIMD/reduction rounding and therefore thousands of floating leaves,
without changing any economic gate. Off-envelope hosts now validate the
installed raw/schema/semantic artifacts and affirmatively test a typed
rebuild rejection. The project claims no cross-machine byte determinism.

The candidate build contract also pins the executed builder, both source
readers, execution-envelope module, active Julia environment, and all 57
runtime `src/**/*.jl` files. A separate platform-neutral semantic lane
constructs both candidates in memory and runs two seeds through 12 quarters
under forced bounds checks. It asserts typed accounting, bank, inventory,
domain, and finite invariants while explicitly setting
`byte_identity_asserted=false`; CI can therefore exercise real model
semantics off the Darwin/M1 byte envelope without redefining the golden
artifacts.

The inventory transition evidence ledger separately preserves 119 signed
quarterly T10105 CIPI flows, 24 T50805B holder-stock rows, 70 annual
producer-price F030 commodity/closure flows, and five non-evidentiary
synthetic stage rows. Its 19 source checks pass, while all eight stock-flow,
valuation, axis, timing, `Used`/`Other`, origin, and model-state transitions
remain `NOT_RUN_BLOCKED` with structurally missing diagnostics. It emits no
inventory vector or `S_s`. Its cross-source check now compares the separately
published F030 control with the published quarterly aggregate (residual
$0m); the independent 73-cell-to-control residual remains -$1m under its
own rounding envelope.

The pinned Census M3 inventory-stage artifact preserves all 316 adjusted and
unadjusted manufacturing series, 130,824 numeric cells, and 1,896
source-missing cells. Its 19,872 exact total=materials+WIP+finished identities
are published controlled identities: Census ratio-estimates stages and
proportionally allocates discrepancies when companies cannot report stage
detail. M3 is manufacturing-only, current-vintage, end-of-month stock evidence
and supplies no economy-wide allocation, BEA/model crosswalk, stock-flow
transition, state, origin, or score.

The literature-backed `Used`/`Other` ledger proves that the current BEA
archive has 2024 summary rows but no detailed special-account split after
2017. It therefore keeps the vintages separate and blocks 2017-share
projection. The pinned detail distinguishes current-production scrap,
existing-good transfers, noncomparable imports, and residence
reclassification, while all nine component, dealer/transport, producer,
core/model, and state decisions remain `NOT_RUN_BLOCKED`.

The constrained Stone/GLS implementation is qualified only on a signed
six-cell synthetic ledger. It honors exact cells, reliability-weighted
adjustments, correlated covariance classes, and consistent dependent
controls; RMSE falls from `2.2546` to `0.0577` in that frozen synthetic test.
Its control diagnostics now distinguish three adjustable controls, two
fixed-only validation controls, rank two, and one dependent adjustable
control. Ordinary RAS, corrected GRAS, and cross-entropy remain blocked
pending eligible data and verified implementations. This is oracle-fixture
algebra evidence, not a production balance or forecast-accuracy result. The
public solver authenticates a freshly reloaded, hash-pinned contract and
fixture and rejects caller-fabricated values or controls even when they copy
the synthetic metadata and source hash.

The authenticated production candidate ledger materializes 17,422
producer-price and imputed-import cells from 18,826 raw target leaves and 924
controls from 602 separate control leaves. Its 19,428 immutable source
entities carry stable source keys and release/value-sensitive lineage hashes.
All parent sets are disjoint and exhaustive. It records 346 unapproved
accounting-identity candidates (structural rank 346), 578 measured published
margins, 588 value-free F030 and `Used`/`Other` overlays resolving to 568
canonical owners, and 925 zero-weight lineage relations. Selected-zero cells
remain null, all 924 control lineages are persisted, and the complete lineage
tables are bound into the problem hash. Solver inputs, approved identities,
adjustments, model-state writes, origins, and forecast scores remain zero.

The production-reconciliation admission-evidence layer then binds the
candidate ledger to a full, offline-verifiable BEA iTable capture. The request
has no release selector, so archive identity is established by exact token,
value, and semantic agreement at all 11,972 common-basis coordinates:
6,789/6,789 UIMARI cells and 5,183/5,183 MakeAR cells, with zero mismatches.
It materializes 19,428 unit observation loadings, two display-policy
diagnostics for each of 924 controls, and 6,160 zero-extra-likelihood domestic
use differences. Only 2,480 domestic differences are raw-evaluable; 3,680
remain display-only because at least one parent lineage contains a
selected-zero source leaf. A cell-address-pinned literature overlay classifies
16 of 23 formerly unresolved negative cells as signed flows, while seven
remain blockers and the 2024 `Used`/`Other` component bridge stays unresolved.
No reliability weight, covariance parameter, structural-zero approval, solver
input, adjustment, model-state write, origin, gate, or score is created.

```sh
node scripts/us/accounting/test_bea_itable_display_semantics_receipt.mjs
julia --project=scripts/us scripts/us/accounting/test_production_reconciliation_admission_evidence.jl
julia --project=scripts/us scripts/us/accounting/run_production_reconciliation_admission_evidence.jl OUTPUT_DIRECTORY
```

The versioned production-reconciliation readiness gate authenticates 11
current direct artifacts and 117 exact semantic fields without admitting them
to a solver. Its eleventh direct artifact is the admission contract; the gate
then rebuilds the admission report in process, authenticating its 12 nested
artifacts and exact `admission1:` evidence identity rather than trusting a
caller-supplied report. It freezes the future target as annual 2024 U.S.
producer-price flows on the 68-sector core plus explicit `Used`/`Other`
closure accounts. Seven of 21 mandatory evidence criteria pass; 14 remain
blocked by the same 23 scientific requirements covering release state,
period/frequency/stock-flow semantics, valuation, imports, special accounts,
inventory, cell states/signs, reliability, covariance, control dependence,
solver admission, independent approval, method recovery, and origin vintage.
The resulting counts remain zero solver families, solver-input cells and
controls, production reliability/covariance classes, reconciliation runs, and
adjustments.

The OECD 2024 source-axis valuation diagnostic archives all 25 exact SDMX
responses over 10,675 CPA08×ISIC4 cells. It evaluates 4,226 valuation and
1,257 tax identities only where every component is observed; 6,449 and 9,418
respective rows remain explicitly not evaluable rather than receiving
missing-as-zero substitutions. Evaluated identities close to $0.01m. The
combined-margin cross-source residual is +$0.96m, outside its derived
$0.505m half-unit bound, and joins the $150.330bn purchasers-price and
$150.329bn basic-price gaps as `DUBIOUS`. No CPA/ISIC mapping, recipient
allocation, margin split, state, origin, or score is inferred.

The installed archive contains only retrieval-day current-data snapshots
dated 2026-08-02 and 2026-08-04. It contains zero reconstructible historical
origins under the protocol's exact release-timestamp rule. The tracked
`data/us/origins/current_vintage_2026q1` package is therefore labeled
`revised_mixed_vintage_diagnostic` and resolves to a hash-addressed
`cannot_run` record with 21 explicit blockers. It is not entered into a
forecast comparison.

The tracked source-release inventory contains zero registered release events
and zero admissible origins. Its validator requires exact evidenced UTC
availability, distinct retrieval-event provenance for identical refetches,
append-only latest-release supersession without stale fallback, stable
past-origin evidence hashes, exact-as-of source/target/structural
completeness, and source-bound validation of any derived `cannot_run` record.
The independently accepted pure-data structural as-of selector in
`forecasting/origins/structural_asof/` now closes the selection rule for six
structural components: observation-period end, official release, and evidenced
availability must all precede the origin; the unique latest release is chosen
before its quality is required to be `APPROVED`, with no fallback. This is
nonadmitting mechanics only. No historical structural release catalog has yet
been authenticated or bound to it, so it does not change either zero count.
A separate evidence-bundle verifier now checks strict truth-value bytes,
operator/validation bytes, internal identities, and receipts. Its scope is
local bundle integrity only: it does not resolve upstream origin bytes, verify
horizon/truth-vintage semantics, or externally authenticate signatories.
Requirements approval and those cross-registry checks remain fail-closed, so
syntactic source coverage or a locally intact bundle cannot emit `READY`.
The Tier-1 coverage inventory likewise remains `NOT_READY`: 0/8 exact targets,
0 historical bitemporal panels, 0 truth matrices, and 0 approved observation
bridges. It now pins exact machine selectors and also cannot emit readiness
until truth/operator artifact manifests and a common set of at least 40
vintage-clean origins pass both local integrity and the still-missing external
evidence checks. Monthly `FEDFUNDS` is explicitly rejected as a substitute for
daily FRBNY EFFR.

The plan-only historical backfill contract records zero certified
retrospective origins. `2026-07-31T14:00:00Z` is reconstruction-only and
`CANNOT_RUN`; `2026-10-30T14:00:00Z` is the first planned prospective cutoff
but is still uncaptured, unadmitted, and not `READY`. Official BEA NIPA and
BLS target archives are the first acquisition stages. Structural QCEW, SUSB,
CPS, fixed-assets, industry/I-O, Z.1, and USDA inputs retain source-specific
timestamp or first-state-byte blockers. FRED/ALFRED warehouse use is excluded
pending written clearance. The plan does not modify the zero-event release
inventory.

The offline EFFR campaign control froze 59 first-state and 58 same-day
revision-check slots from 2026-08-07 through the 2026-10-30 origin. The
2026-08-07 first-state slot is preserved, but its revision window was missed
with no request issued, so that campaign can reach at most 116/117. The
planned 2026-08-10 pair is fresh append-only evidence only and cannot repair
the missed slot. A separate 115-slot restart-v2 schedule and a separately
versioned restart-v4 capture/evaluator binding are now independently accepted
for their narrow, permanently nonadmitting roles. The schedule's embedded
`runner_restart_binding_complete=false` remains truthful historical metadata
for the schedule-only artifact; the successor runner pins those exact schedule
bytes rather than restamping them. The original control
reconstructs the weekday/holiday calendar, binds every effective date and UTC
window to the prospective-v2 contract, rejects duplicate or mislinked
manifests, and preserves an absent raw `currentState` as a typed blocker. It
contains no downloader or writer and keeps network execution, inventory
mutation, origin admission, scoring, and promotion false even under complete
synthetic coverage. The preserved August 7 first-state runner remains
separately byte-pinned and is not authority for a late revision request.
After two independently rejected candidates, recurring collector v3 is
byte-level accepted for the production CLI's bounded, append-only,
permanently nonadmitting capture role. Its 402-test hermetic suite passed from
the repository root and `/tmp`; the pinned 178-test receipt contract and
127-test campaign control also passed. Dry run is network-free and write-free,
and explicit `--execute-live` is only a local, one-slot operator assertion.
Persisted local records cannot externally authenticate transport, network
exchange count, operator authorization, host clock, or publisher identity.
The exported module is not claimed as a universally typed or fully
pre-callback-validated API, and execution provenance assumes the exact
reviewed project invocation. The collector cannot mutate the source
inventory, admit an origin, score a forecast, or promote a model. See
`forecasting/vintages/effr/recurring_acquisition/README.md`.

The accepted additive restart-v2 schedule freezes only its own 115-slot
denominator: 58 morning states from 2026-08-10 through 2026-10-30 and 57
same-day revision checks through 2026-10-29. It excludes the September 7 and
October 12 holidays, reconstructs the Madrid daylight-saving transition, and
binds all dates, effective dates, windows, transaction IDs, output paths,
queries, and same-day predecessors. Its unchanged outcome vocabulary is
exactly `NO_MARKED_REVISION_OBSERVED_AS_OF_SECOND_CAPTURE`.

The withdrawn v1 facts remain separate: 117 planned slots, one incompatible
August 7 first state, one missed revision, and a theoretical v1-only
noncoverage ceiling of 116/117. Neither campaign contributes to the other's
completion. Restart coverage can be only 115/115, and all origin, scoring,
promotion, network, write, and readiness gates remain false. In particular,
`runner_restart_binding_complete=false`: the schedule contains no downloader,
writer, result evaluator, or automation. See
`forecasting/vintages/effr/campaign_restart_v2/README.md`.

The accepted restart-v4 successor binds only that exact 115-slot schedule,
uses the fixed ignored root
`data/us/raw/forecasting/effr/prospective/2026q3_restart_v2`, and keeps dry run
network- and write-free. Each request has two fail-closed clock gates: one
before its durable attempt event and another after fsync/readback immediately
before downloader reachability. The second sample is the recorded request
start. First- and later-request regressions prove a journal stall crossing the
deadline invokes no downloader. Raw capture uses an internal nonadmitting
preservation status and cannot borrow observed-state vocabulary. Only the
pinned observed-state-v3 adjudicator, supplied with a caller-owned
`RestartDecisionBinding`, may return
`NO_MARKED_REVISION_OBSERVED_AS_OF_SECOND_CAPTURE`; strict integer
`footnoteId` symmetry, raw schema, exact rational revision policy, and paired
timestamp rules are replayed there. Independent root, `/private/tmp`, and
README-exact suites each passed 2,515/2,515, with no network or raw write. The
binding still cannot authenticate publisher, transport, host time, operator,
external durability, or first-public state, and every origin, score,
promotion, production, and readiness gate remains false. See
`forecasting/vintages/effr/recurring_acquisition_restart_v4/README.md`.

The incompatible EFFR observed-state contract v3 is independently accepted
only as an offline, locally integrity-checked adjudicator for paired morning
and post-revision-window endpoint observations:

```sh
julia --startup-file=no --depwarn=error --check-bounds=yes \
  --project=scripts/us \
  scripts/us/forecasting/vintages/effr/observed_state_contract/test_effr_observed_state_contract_v3.jl
```

Independent repository-root and unrelated-`/tmp` executions each passed
253/253 assertions. The contract rejects duplicate decoded JSON members,
preserves bounded exact numeric lexemes, uses reduced `Rational{BigInt}` for
the strict greater-than-one-basis-point policy, accepts only absent or exact
integer `footnoteId` 1/2/3, and replays transition decisions against raw
lexemes, equality facts, capture windows, and an out-of-band expected pin. It
does not synthesize absent `currentState`; the field remains absent in the
pinned schema/wire evidence and `EVER_OFFICIAL` remains not established.
Acceptance does not authenticate publisher, transport, time, request count,
storage, first-public bytes, atomic pairing, final daily state, campaign
completion, origin eligibility, scoring, or production. Unchanged later bytes
support only `NO_MARKED_REVISION_OBSERVED_AS_OF_SECOND_CAPTURE`. See
`forecasting/vintages/effr/observed_state_contract/README.md`.

Independent acceptance here is a software-review disposition only. The
byte-frozen protocol deliberately retains
`artifact.status = CANDIDATE_OFFLINE_NONADMITTING` as its trust and admission
disposition. That embedded value does not denote origin, estimand, promotion,
or production acceptance, and changing it would require a new contract
version and full requalification.

The first BEA archive-discovery slice resolves HMI7 release directories,
reverse-checks directory IDs, and catalogs all discovered section workbooks
without downloading workbook bytes or changing the source inventory. Current
protocol selectors are retained only as protocol metadata: historical table
rows, series codes, units, base years, and quarter columns must be verified
inside each acquired and hashed workbook. NIPA table composition changes
across vintages, so discovery remains non-admitting and cannot emit `READY`.
The acquisition plan pins BEA's qualified public-domain reuse policy, requires
source/release attribution and a policy recheck before acquisition, and still
requires exact raw bytes, hashes, and availability evidence.

A separate hermetic contract now seals the exact 40-release
2011Q3--2021Q2 advance/initial metadata inventory:

```sh
julia --startup-file=no --depwarn=error --check-bounds=yes \
  --project=scripts/us \
  scripts/us/forecasting/vintages/bea_nipa/advance_metadata_manifest/test_bea_hmi7_advance_metadata_manifest.jl
```

It binds all directory IDs and case-sensitive paths, official event
timestamps/pages/PDF locators, Section 1/2 filenames, the 24-pair
`.xls`--16-pair `.xlsx` transition, update classifications, shutdown
exceptions, and 15 folder-date/event-date mismatches. It is metadata only:
no workbook or PDF bytes are acquired, every strict-origin/execution/
promotion/production gate is false, and the 40 rows are not forecast origins.

An independently reviewed opt-in binding now supplies the capture boundary's
built-in `Downloads` transport for exactly one release and its two sealed
Section 1/Section 2 workbooks. The default CLI path is a network- and
write-free dry run; live use requires a separately explicit `--execute-live`,
an existing canonical raw root, same-host-date review of BEA's reuse FAQ, and
a nonempty local reviewer identity. The public live API exposes no downloader,
clock, URL, header, output-name, loop, or retry injection. Its hermetic suite
passes 170/170 from both the repository and an unrelated working directory.
The returned headers are the final parsed ordered fields exposed by Julia's
`Downloads` API, not raw wire bytes, and their timestamp is conservatively the
body-completion observation. Transport, reviewer, host clock, and request-count
labels remain unauthenticated local assertions. Present-day retrieval proves
neither historical availability nor first-public bytes, and all origin,
empirical, scoring, promotion, production, and readiness gates remain false.
See `forecasting/vintages/bea_nipa/advance_live_fetcher/README.md`.

The separately accepted 2017-era HMI7 profile parses only the exact preserved
2017Q3 sequence-25 pair. It does not weaken the later numeric-cell parser:
all five target histories must be shared-string cells under the exact
`General` styles; GDP levels use strict ASCII comma grouping; price indexes
use exactly three decimal places; and core PCE has exactly 48 literal
`.....` source-missing cells through 1958Q4 before a gap-free numeric history.
An independent parser-free audit matched both raw workbooks, every package
manifest, all five 283-quarter histories, and the displayed Q2-to-Q3 rates.
Section 2 was created and last-modified after the release event, so this
profile remains `PRESENT_DAY_ARCHIVE_BYTES_PARSED_NONADMITTING_2017_ERA_PROFILE`
and supplies neither historical first-state nor origin evidence. Its 20-test
suite requires the exact ignored local raw bundle; it is listed as a local
verification command but deliberately not placed in clean-runner CI. See
`forecasting/vintages/bea_nipa/era_2017_profile/README.md`.

The independently accepted January-2014 HMI8 profile is narrower still: it
fingerprints the exact present-day BEA archive bytes and parses the 1997--2012
summary plus 2007 benchmark-detail make/use tables without admitting them as
historical origin evidence. It independently reconciles the native residual
concepts `Used = S00401 + S00402` and `Other = S00300 + S00900`. The detailed
source contains only combined real estate `531000` and supports the federal
`S00500 + S00600 = GFG` witness, so it cannot identify the later `HS/ORE` or
`GFGD/GFGN` splits; no later-era share is imputed. Its sole formula exception
is the exact eight-cell, out-of-table `OP337:OP344` broken-reference defect,
which is required, excluded from evidence, and otherwise fail-closed. Date-only
release evidence, February 2014 edits, later ZIP timestamps, and 2015 HTTP
labels keep the status `PRESENT_DAY_ARCHIVE_RETRIEVAL_NONADMITTING_PROFILE` and
all model-input, scoring, accuracy, and promotion gates false. See
`forecasting/vintages/bea_industry/hmi8_2014_profile/README.md`.

The first exact HMI7 byte pilot now preserves the official 2026Q2 advance
Section 1/2 pair under ignored content-addressed raw storage. A deterministic
OOXML semantic fingerprint and immutable receipt bind those bytes to all five
target mappings and present-day HTTP/capture metadata. Independent archived
release-page/PDF evidence does not bind the exact workbook hashes, so the
2026Q2 retrospective origin remains `CANNOT_RUN`; the receipt cannot change
historical availability, admission, inventory, or `READY`.

Two historical HMI7 diagnostics preserve exact present-day Section 1/2 pairs
for the 2019Q4 advance and 2021Q2 advance/annual-update archive directories.
Receipt-specific bundles below stable raw-pair hashes retain repeated
acquisition evidence without overwriting it. The semantic fingerprints verify
the five vintage-specific mappings and complete numeric histories from 1997Q1
through each archive endpoint. These are next-day monthly-table snapshots:
neither present-day bytes nor current HTTP headers prove the first state
served at the historical release event. The 2021 pair also contains an annual
update and revised history. Every historical-availability, origin-admission,
execution, inventory, production, and readiness gate therefore remains
`false`. A sealed cross-archive revision diagnostic compares the common
1997Q1--2019Q4 level histories and protocol transformations, while retaining
that annual-update caveat. It is revision-sensitivity evidence only—not a
standard within-definition revision, truth, origin, score, or accuracy
artifact.

The first Philadelphia Fed RTDSM slice captures exactly five current
quarterly-vintage matrices into ignored, immutable, receipt-specific storage
after an explicit same-day terms review and research-only attestation. A
dependency-free OOXML fingerprint binds their complete panel layout and
semantic hashes while checking only ten selected cells against the two BEA
HMI7 fingerprints. The checked-in artifact contains no full row, column, or
matrix. RTDSM is a curated information-set proxy rather than intraday
first-byte evidence; `P` and `PCON` are mandatory concept mismatches for the
GDP implicit deflator and direct PCE price-index targets. Consequently the
capture permits research diagnostics only and leaves training, truth,
model-input, origin-admission, execution, inventory, production, and
readiness gates `false`.

The prospective-capture deadline workflow runs on weekdays around the planned
GDP trigger and origin boundaries. It revalidates the mutable official
schedule and uploads a short-retention, hash-addressed schedule snapshot, but
it remains an alarm rather than a release/origin evidence collector.
Beginning at the trigger it fails until an immutable receipt is installed
through a superseding plan version.

The supply/make diagnostic retains the full 2024 Table 262
commodity-by-industry make matrix, independently typed commodity and industry
output vectors, and explicit `Other`/`Used` rows. It proves that equal-length
industry and commodity arrays cannot be substituted positionally and performs
no balancing or residual allocation. A separate industry-technology operator
now transforms the 70×68 intermediate-use system into a code-keyed 70×70
commodity diagnostic using `Z = U*diag(g)^(-1)*V'`. It retains both published
output denominators and an exact-make-sum rounding normalization. The latter
preserves every intermediate-use row total and exposes 420 passing
transformation controls, while retaining 9 negative make cells, 5 negative
use cells, 19 negative derived cells, and the `Other`/`Used` closure accounts.
Because use, make, and output remain on purchasers', producer, and basic price
bases respectively, the operator is explicitly non-promoted: no complete
valuation bridge, clipping, balancing, or closure allocation is claimed.
A separately published current-vintage comparator now uses BEA's official
after-redefinitions commodity-by-industry direct-requirements matrix `B` and
industry-by-commodity market-share matrix `D`; `A = B*D` is the primary
73×73 direct matrix. Table 59 inversion remains only a published-rounding
round trip. The legacy official-direct, basic-price-T007-scaled 70×70
transaction total is $21,012,023.990184m, versus $21,438,541m for the
purchasers-price symmetric-use diagnostic. Its $426,517.009816m difference is
now explicitly a mixed-basis regression check, not a balancing target.

The after-redefinitions common-basis diagnostic instead retains BEA's 2024
producer-price 73×71 intermediate-use matrix `U`, 71×73 make matrix `V`, 20
final-use columns, three value-added rows, separate import allocation, and
matching `q`/`g` controls. It constructs `Z=U*diag(g)^(-1)*V` and compares it
with `B*D*diag(q)` from the published coefficient workbooks. Their totals are
$21,438,566.625123m and $21,438,542.743527m: a signed $23.881596m
difference and $944.840395m L1 cell gap, with all source and coefficient
rounding retained. The 32,443-cell, 19-projection fixture distinguishes 16,016
BEA ellipsis zeroes from 819 explicit numeric zeroes and preserves all 321
negative source cells. Its CSV and manifest SHA-256 identities are
`6c0c44ca0ac3f70c5d51d6b3a58fca2a02283e9e6f50a254ae663d12f187f0ac`
and
`ff555043829e5d12ba787ba9ad7d58ef4f0d2ee306740d6847bdfec800935030`.

The projected 2024 bottom controls are $21,438,542m for intermediate use
`T001`, $53,546m for `F030`, $29,298,013m for value added `V004`,
$50,736,555m for use-table output, and $50,736,556m for make-table output.
The `F030` cells sum to $53,545m; the one-million difference and its 40
ellipsis flags are retained. The common report has 1,260 passing source
residuals. The same-system comparator checks all 5,183 `B` and 5,183 `D`
cells against whole-million/seven-decimal interval bounds, with zero failures
and maximum ratios 0.9884042149 and 0.9736681278. Its propagated transaction
maximum ratio is 0.9373110641, and all 10,521 comparison controls pass.
Same-column adversarial swaps are rejected, and source status and provenance
remain attached to the result.

The import artifact is a signed allocation ledger, not a nonnegative matrix
to subtract mechanically. Allocations excluding `F050` total +$3,795,870m,
the 48 negative `F050` offset cells total -$3,795,914m, and 10 other negative
allocation cells remain for review. Their -$44m net is rounding; no domestic-
use subtraction is applied.

A separate 2017 producer/purchaser benchmark records $8,169,470m of
commodity-level valuation redistribution while recipient-column totals agree
within $5m. The producer and purchaser cell sums are $34,468,125m and
$34,468,139m, but both published grand totals are $34,468,130m; the apparent
$14m cell-sum difference is rounding, not aggregate valuation change. The 94
benchmark controls pass, but the benchmark is not a 2024 margin/tax allocator.
All of these artifacts are diagnostic-only, origin-ineligible, and cannot
affect accounting gates or model state. Because the products share BEA's
input-output system after redefinitions, the common-basis result is a
rounding/transformation comparator rather than independent statistical
evidence. Product-tax allocation, the domestic/import boundary, final-use
and value-added reconciliation, `Other`/`Used`, signed allocation policy,
inventory allocation, latent-state reconciliation, and an externally bound
multi-archive release identity remain blocked. The checkpoint adds zero
forecast origins and zero accuracy scores.

The next WS-2C checkpoint maps that pinned producer-price system to the model
dimension. The mapping TOML
(`546b3dc15cbb194210ce564a44626b146551b161ca0ce5ffb90a8a5261b4553c`)
and the 68-sector contract
(`2e0fb0a6d8190e4488810653a2638edeff9ceae2a1ea463f28730106752b183f`)
sum source retail codes `441`, `445`, `452`, and `4A0` to model `4A0`,
identity-map the other core codes, and retain `Used` and `Other` in a
separate closure ledger. Every projected source cell is conserved exactly
between the 68×68 core and closure blocks.

Core producer intermediate use, final use, make, and commodity output total
$21,165,843m, $29,550,990m, $50,716,812m, and $50,716,816m. Their
corresponding closure totals are $272,726m, -$252,983m, $19,740m, and
$19,740m. Core/closure import intermediate totals are
$1,776,783m/$181,714m and final-use totals are
-$1,776,831m/-$181,710m. Value added remains $29,298,014m and industry
output $50,736,554m on the 68 producing sectors. Negative-cell counts for
core versus closure are 0/5 in intermediate use, 1/0 in make, 0/6 in
symmetric transactions, and 56/2 in the import allocation.

The typed import ledger retains the role `separate BEA imputed allocation`,
the sign convention positive allocated uses plus signed `F050` offset, and
`domestic_use_subtraction_applied=false`. Core allocation excluding `F050`,
the `F050` offset, and the net are +$3,409,217m, -$3,409,265m, and -$48m;
the closure values are +$386,653m, -$386,649m, and +$4m. Recombined, they
recover the source +$3,795,870m, -$3,795,914m, and -$44m. The core has 46
negative `F050` cells and 10 other negative allocation cells; the closure has
two and zero, recovering the source categories of 48 and 10.

Aggregating the source symmetric system and recomputing after joint retail
aggregation agree up to Float64 order: L1
`4.2105847996611045e-10`, Frobenius
`6.421245119608913e-11`, maximum cell
`2.9103830456733704e-11`, and correlation `1.0`. This is not a technology
effect: all four retail make rows are diagonal one-output rows mapped to the
same aggregate output. All 494 runtime controls and the 227/227 focused tests
pass. The public `model_core_controls_pass` requires the report, fixture, and
mapping contract and performs the fresh pinned-fixture comparison; it has no
report-only overload. The explicitly named
`model_core_internal_controls_pass(report)` checks only internal algebra and
policy. The source-aware gate rejects balanced in-memory cycles that preserve
row and column totals.

This aggregation performs no closure allocation, valuation/tax conversion,
domestic/import choice, balancing, clipping, state write, accounting-gate
change, origin admission, promotion, or accuracy scoring. WS-2C remains in
progress; the next step is a complete valuation/tax/import/final-use ledger.
Applicable common-basis blockers are inherited monotonically. They still
include import-is-imputed evidence, review of signed allocations outside
`F050`, and incomplete final-use/value-added reconciliation.

The standalone inventory-stock ledger contract now fixes end-of-period stock
timing, unit conversion, M3 stage additivity, and missing-not-zero semantics.
Its fixture is intentionally synthetic, carries no source bytes, and cannot
emit model inventory. Holder-to-commodity, valuation, stage-to-model-stock,
coverage, and state-reconciliation bridges remain explicit blockers.

Separately, the 122-test BEA T50805B diagnostic hash-pins a redacted
current-vintage response and receipt for all 29 published 2026Q1 rows. It
verifies $4,223,030m of end-of-quarter private inventories and the published
holder identities and ratios without annual-rate division. This is source
evidence, but it is not an origin-time first-release receipt and remains
origin-ineligible. Holder-to-model-sector and holder-to-commodity mappings,
valuation, inventory-stage and model-stock-scope bridges, latent-state
reconciliation, and origin-time receipt evidence are still missing; the
diagnostic emits no `S_s` and cannot affect an accounting gate or model state.

Clean in-memory calibration builds route Table 262 T007 commodity output only
to a signed diagnostic and retain Table 259 T018 industry output for
production. They do not create opening inventories from that gap. The
installed artifacts remain the protected legacy audited baselines. The two
separately named opening candidates are current-vintage diagnostics only;
their byte/semantic hashes are rebuilt and checked under a single-thread
Julia/BLAS contract. They cannot be registered as forecast origins until the
valuation, latent state, inventory-flow/stock, and full-accounting bridges are
governed.

## Quarantined revised-data benchmark diagnostic

The Stage-2 engineering diagnostic exercises the benchmark and scoring stack
on 101 complete-case quarters from 2000Q3 through 2025Q3. Its eight targets
are present-day/revised BEA, BLS, and New York Fed transformations. It is
explicitly a mixed-vintage snapshot, not an as-of-origin data panel. The
missing October 2025 CPS observation is not imputed, so the common panel stops
before 2025Q4.

Run the canonical one-thread diagnostic from the repository root:

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/diagnostics/run_revised_data_benchmark_diagnostic.jl
```

The command writes research-only outputs to
`output/us_forecasting/revised_data_diagnostic`. It compares no-change,
drift, historical-mean, AR(1), AR(4), AR-BIC(1:8), VAR(1)--VAR(3), and a
fixed-prior BVAR(1) at horizons 1, 2, 4, 8, and 12. Scores use cells common to
all models and are reported on both all-available and horizon-12-balanced
samples. The weighted ratios are macro-averages of 40 matched
target-by-horizon score ratios; they are not ratios of pooled losses.

The v2 diagnostic pins the fixture/receipt chain, complete model
specifications and cards, protocol, code, and Julia environment. It records
per-origin AR selections, VAR design conditioning and companion-root
stability, BVAR prior identity, and maximum forecast magnitude. Any model
failure suppresses aggregate ranking. The current deterministic run contains
22,640 forecast cells, 610 model-origin diagnostics, 800 score summaries, and
zero model failures.

This exercise includes neither the ABM nor an equilibrium benchmark. It adds
no forecast origin, cannot support a production accuracy claim, and is
ineligible for model promotion. Its purpose is to expose benchmark behavior
and harden the future vintage-clean evaluation path.

The companion core-four diagnostic adds the registered fixed-parameter
semi-structural state-space model:

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/diagnostics/run_revised_data_semi_structural_comparison.jl
```

It scores eleven models on identical real-GDP-growth, PCE-inflation,
unemployment, and EFFR realization cells. The statistical models retain their
registered eight-target input panel while the semi-structural model retains
its registered core-four input panel, so this is a native-input comparison,
not an identical-regressor experiment. In the deterministic revised-data run,
the semi-structural model ranks first on weighted RMSE: its ratio to VAR(1) is
`0.7488895447345775` on the all-available track and
`0.7445969022111804` on the balanced-horizon-12 track. Its corresponding MAE
ratios are `0.8856658629411573` and `0.8730449475542831`; AR(1), not the
semi-structural model, has the best weighted MAE.

An independent, explicitly unregistered stress calculation excluding
realizations from 2020Q1 through 2021Q4 materially changes that ranking: the
semi-structural RMSE ratio rises to about `0.985`--`0.997` and its RMSE rank
falls to fifth. This is not a formal alternative result; it demonstrates that
the headline advantage is pandemic/regime-sensitive and that a
literature-grounded regime policy must be frozen before inference.

These are point-forecast-only research diagnostics on a current/revised,
mixed-vintage panel. The comparator is equilibrium-oriented but is not a
DSGE model. No ABM forecast, strict historical origin, statistical
model-comparison inference, promotion score, or production accuracy claim is
included.

The separate `forecasting/benchmarks/small_nk_dsge/` component is now
independently accepted only as fixed-parameter equilibrium, measurement,
filter, and predictive-path mechanics. Its frozen module
`2750a95581ba83bdac8578ccdc2cd290a265fa1968d74ddc3d10cfc56e26248a`
and fixture
`ec0a4a891e49e518ab5e08b98fdeda6b828f1b611600a3ddf4e198d0c70bc89e`
reproduce the pinned FRBNY generalized-Schur oracle and the aggregate
real-GDP-growth/PCE-inflation/EFFR measurement system. Root and unrelated-CWD
suites each pass 224/224; independent adversarial checks also reject
indeterminate, malformed, nonfinite, noisy/correlated, invalid-filter, and
derived-overflow evidence. The component remains unregistered, reads no
empirical panel, estimates no origin-wise parameters, exports no empirical
forecast or score, and establishes no accuracy or forecasting suitability.
See `forecasting/benchmarks/small_nk_dsge/README.md`.

The matching `forecasting/benchmarks/core3_autoregressive/` component is
independently accepted only as nonadmitting AR(1), OLS VAR(1), and
fixed-prior MNIW BVAR(1) mechanics on the same aggregate-PCE core-three
contract. Its repaired module
`e8444761c55e199ab475eddca31a06c058b8fb2566ce721b186654190746f1c0`
reloads the pinned revised fixture and bit-binds every training prefix,
quarter key, origin, following forecast label, and source identity before
execution. Authored root and unrelated-CWD suites each pass 287/287; an
independent 977-case audit also rejected every single-bit training-cell
mutation and coordinated sample/forecast rehash. The component remains
unregistered and nonscoring, and establishes neither an authenticated
historical origin nor empirical accuracy or forecasting suitability. See
`forecasting/benchmarks/core3_autoregressive/README.md`.

An independently accepted descriptive comparison now runs those three
autoregressive mechanics and the fixed-parameter small-NK mechanics on the
same final-revised core-three prefixes. It uses 30 balanced origins from
2015Q2 through 2022Q3, one 12-quarter/500-path run per model-origin, and
extracts h=1/2/4/8/12 without restarting. Its bootstrap checks the exact
dependencies, Project, Manifest, active project, and LOAD_PATH before any
dependency include; every prefix and phase-two truth panel is independently
rebound to the pinned source, and complete attempt identities are replayed.
Independent root and unrelated-CWD suites pass 118/118 and reproduce result
`cd0cb535dfa023dd7d75d50783c259c378c88ad3d1b03fa5abbaf192e9a705cd`.
The fixed small-NK h=1 real-GDP RMSE is 59.226 percentage points with zero
50/80/95-percent coverage, versus BVAR RMSE 10.429; its h=1 joint energy score
is 18.753 versus 1.511 for BVAR. This is a severe calibration failure on the
declared revised panel, not an admitted real-time backtest. The whole panel is
materialized in the same process before prefix extraction, the design and
rankings are retrospectively exposed, small-NK parameters are fixed, and no
common ABM origin exists. Accordingly
`mathematical_scores_computed=true` but
`repository_scoring_eligible=false`; every accuracy, suitability,
confirmation, registration, promotion, and production gate remains false.
See `forecasting/diagnostics/core3_equilibrium_comparison/README.md`.

The model-free common-origin preflight at
`forecasting/diagnostics/common_origin_preflight_v1/` is independently
accepted only as deterministic `CANNOT_RUN` evidence. Its 36 exact metadata
bindings rederive 21 false readiness conditions, 89 blockers, 17 limitations,
zero admitted common origins, no eligible target--horizon cell, and no
registered required model set; root and unrelated-CWD suites each pass
131/131 and reproduce result
`4b0871cdd9c25fadcd266b778ba23b0415f23ce8e8c423f6ee7fc5d936938fd5`.
It includes no model, opens neither the revised panel CSV nor truth, performs
no forecast or score, and writes nothing. Its current schema cannot emit a
ready status: a successor must bind newly admitted origins, approved
operators, registered models, and a common path/horizon design before an
empirical ABM--equilibrium--autoregressive comparison is permitted.

The quarantined ABM engineering qualification is narrower still:

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --startup-file=no --depwarn=error --check-bounds=yes \
  --project=scripts/us \
  scripts/us/forecasting/diagnostics/test_revised_data_abm_engineering_diagnostic.jl
```

It verifies an origin-bounded `C_G`/`C_E`/`Y_I` sanitizer, disjoint
structural/dynamic/state partitions, domain-separated construction/simulation
substreams for 32 paths, runtime-checked serial/global-RNG guards, and
failure-only manifests. It does not construct or run the ABM and emits no
input values, forecast, score, inference, origin, or promotion artifact. Input
truth isolation and lineage remain explicitly unverified, alongside the
mandatory accounting, scale, target-operator, and historical-origin blockers.
See
`forecasting/diagnostics/revised_data/ABM_ENGINEERING_QUALIFICATION.md`.

The separate base-model origin-firewall v2 validates the complete installed
source-envelope schema and projects only the 60 parameters, 17 static fields,
and five origin-ending histories consumed by `BeforeIT.Model`:

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --startup-file=no --depwarn=error --check-bounds=yes \
  --project=scripts/us \
  scripts/us/forecasting/diagnostics/test_revised_data_abm_origin_firewall_v2.jl
```

It removes `T`, `T_max`, `S`, unused calibration markers, non-runtime
diagnostics, and post-origin history before qualified hashing and seed
derivation. It binds the complete 60-file repository `src/`/`ext/` Julia
closure, rejects normalized duplicate text keys and non-one-based arrays, and
requires repository preference files to be absent. It is still a
revised/mixed-vintage, lineage-unverified, constructor-free engineering gate.
Constructor gate v3 attempted the effective-runtime, dependency/artifact,
constructor-domain, and loaded-method boundary, but its acceptance was later
revoked. The cache-free one-step boundary is now independently closed only for
the narrow v4 software diagnostic described below. Firewall v2 emits no path,
forecast, truth, score, admitted origin, or promotion evidence. See
`forecasting/diagnostics/revised_data/ABM_ORIGIN_FIREWALL_V2.md`.

The now-rejected constructor gate v3 mechanically closed much of that
narrower deferred runtime boundary for exact bytes in a fresh canonical
process. It kept bootstrap standard-library-only, required
`JULIA_LOAD_PATH='@:@stdlib'`, validated 82 manifest dependency source trees,
pre-resolved 83 package entrypoints before any third-party import, and
constructed 32 seeded states plus one deterministic replay without stepping:

```sh
JULIA_LOAD_PATH='@:@stdlib' JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --startup-file=no --depwarn=error --check-bounds=yes \
  --project=scripts/us \
  scripts/us/forecasting/diagnostics/test_revised_data_abm_constructor_gate_v3.jl
```

The command above is the portable fail-closed branch; it passed 219/219 while
leaving JSON, JLD2, BeforeIT, and frozen v2 unloaded on a noncanonical
envelope. On the exact documented Julia 1.10.3 M1/native envelope, omit
`--check-bounds=yes`; canonical repository-root and `/tmp` runs each passed
271/271 and completed all 33 constructions. Those runs establish only
constructor/runtime mechanics. The initial independent acceptance was
revoked and the candidate rejected because BeforeIT import eagerly deserializes
package-side data that v3 does not pin and its cache-generation precompile
workload can itself construct and step. The portable pre-load boundary remains
useful, but the canonical result is retained only as cache-contingent
engineering evidence. Binary/JLL payloads, compiled caches, depot contents,
global preferences, Julia
executable/sysimage bytes, same-user filesystem races, empirical validity,
RNG-stream independence, origin admission, forecast accuracy, and promotion
remain unattested or false. See
`forecasting/diagnostics/revised_data/ABM_CONSTRUCTOR_GATE_V3.md`.

The no-cache, side-data-pinned ABM one-step gate v4 is independently accepted
for its exact, revised/mixed-vintage, permanently nonadmitting software
diagnostic. It selectively loads only the U.S. `parameters` and
`initial_conditions`, pins the ten package-import side-data files, disables
compiled modules and package images, verifies that the guarded precompile
workload cannot run, and executes exactly one native serial step per fresh
model. Across primary, reverse, and replay phases it records 65 constructions,
65 steps, 65 implicit opening collections, 65 explicit post-step collections,
and 130 collection events:

```sh
JULIA_LOAD_PATH='@:@stdlib' JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
  julia --startup-file=no --compiled-modules=no --pkgimages=no \
  --depwarn=error --check-bounds=yes --project=scripts/us \
  scripts/us/forecasting/diagnostics/test_revised_data_abm_one_step_gate_v4.jl
```

Independent execution passed 214/214 portable assertions. An unrelated-cwd
canonical Julia 1.10.3 M1/native replay, using the same command without the
altered `--check-bounds=yes` envelope, passed 276/276 and reproduced result
`1ac4efc78236d0dfafb11d78b35597b1106cd374488b4f0c9ddf8fd70b1782a2`.
This verifies the frozen initial transition and pathwise GDP formulas, not an
official observation bridge or forecast. Its opening row is model-implied,
the post-step measurement basis differs, independent RNG streams are not
established, raw truth-bearing bytes are read but evaluation values are not
deserialized or scored, and no origin, Tier-1 operator, accuracy, registry,
promotion, production, or suitability claim follows. See
`forecasting/diagnostics/revised_data/ABM_ONE_STEP_GATE_V4.md`.

The four-quarter ABM path gate v5 is independently accepted only as
`SOFTWARE_FOUR_QUARTER_PATH_VERIFIED_NONADMITTING`. It extends the same
source-only, side-data-pinned envelope through four continuous native serial
steps without resetting the simulation RNG by horizon. Across 32 primary,
32 reverse-order, and one replay path it reproduces 65 constructions, 260
steps, 65 implicit opening collections, 260 explicit collections, and 325
total collection events. An unrelated-CWD canonical audit passed 338/338 in
24m34.4s and reproduced result
`736ac1683df46f1ef856375ef8036b6ab6b8e858fbfd84fc7a366e879855d9b4`;
its h=1 prefixes also reproduce the accepted v4 path identities exactly.
Rows span the model-implied 2026Q1 opening through 2027Q1, but the opening and
flow rows use different measurement constructions. V5 therefore emits only
pathwise q/q operators and no opening-to-year-end statistic. It still has no
authenticated origin, official target bridge, independent RNG-stream proof,
score, empirical accuracy, registry, promotion, production, or forecasting-
suitability status. See `forecasting/models/abm_multistep_gate_v5/README.md`.

## Simulation Lab and Economy Explorer

The web application loads the structural and nowcast artifacts directly
through `BeforeIT.load_us_baseline`. From the repository root:

```sh
julia --project=apps/web -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=apps/web apps/web/src/server.jl
```

Open `http://127.0.0.1:8080`, select the U.S. 2026 Q1 nowcast, and run an
unconditional ensemble. The opening state is 2026 Q1 and the first forecast
quarter is 2026 Q2. A 23-quarter horizon ends in 2031 Q4.

The results workspace shows ensemble means and standard deviations. Standard
trace runs also persist one explicitly identified realization and link to the
Economy Complexity Explorer at `/explorer/?run=<run-id>`. U.S. charts and
traces use the 68-sector BEA Summary I-O classification and millions of U.S.
dollars.

The calibrated U.S. household consumption and housing propensities preserve
the official-data dissaving state even when their sum exceeds one. The web API
applies its combined-value constraint only when a user edits either propensity.
