# U.S. calibration and forecasting development plan

**Goal:** bridge the gap between the current U.S. port of BeforeIT and a serious,
defensible forecasting tool for the U.S. economy, following the methodology of
Poledna, Miess, Hommes & Rabitsch, *"Economic Forecasting with an Agent-Based
Model"* (the Austrian exercise), including head-to-head benchmarking against
autoregressive (AR/VAR), Bayesian VAR, semi-structural, and equilibrium (DSGE)
models.

**Plan version:** 2026-08-05

**Repository baseline:** `US_BeforeIT.jl` commit `6030f75`

**Scope:** development and validation specification; this document claims no
new U.S. calibration or forecast result.

**Status.** This is the canonical program plan. It is both a replication plan
and a model-risk specification; completing a workstream is not evidence of
forecast skill unless its stated gate passes.

**Evidence base.** This plan is grounded in (a) inspection of the rendered
paper, including its equations and validation appendices, (b) a source and
artifact review of this repository at commit `6030f75`, (c) the existing data
specification in
[README_US_CALIBRATION.md](README_US_CALIBRATION.md), and (d) the verified
behavior of the shipped U.S. baseline and validation scripts. Claims below use
three labels: **verified** (directly observed in code/data or unambiguous in the
paper), **paper–code difference** (the two sources differ, without presuming
which is normative), and **hypothesis** (requires a controlled test). The audit
is intentionally not described as equation-complete until a machine-readable
crosswalk and its evidence are committed.

**Related repository documents.**
[README_US_CALIBRATION.md](README_US_CALIBRATION.md) is the data-acquisition
and storage specification — this plan does not repeat it.
[CHANGES_FROM_UPSTREAM.md](CHANGES_FROM_UPSTREAM.md) records fork provenance.
This document supersedes the former companion calibration/validation plan and
contains the merged development program.

**Executive judgment.** The current port is a credible research starting point
and broadly follows the BeforeIT lineage, but it is not yet a calibrated U.S.
forecasting system. Five gates are non-negotiable before any production claim:

1. reconcile the industry/commodity/valuation basis and opening GDP identities;
2. build historical, bitemporal U.S. data and origin-specific structures with
   automated leakage prevention;
3. validate observation mappings, latent origin states, scale, and predictive
   uncertainty—not only innovation noise;
4. run a frozen pseudo-real-time competition against strong statistical,
   semi-structural, DSGE, sector, and combination challengers;
5. pass independent model-risk review and prospective shadow operations.

The Austrian exercise is a valuable replication and harness diagnostic. It is
not the U.S. promotion sample, and the repository does not currently contain
all historical inputs needed to reproduce it.

---

## Part I — Is the implementation consistent with the paper?

### I.1 Verdict

**Verdict: the repository has a faithful BeforeIT lineage, but it is not a
literal reproduction of every printed equation and the U.S. fork adds
economically material initialization and calibration choices.** Most
agent-action equations are inherited unchanged from upstream
`bancaditalia/BeforeIT.jl`; however, this fork also changes market
instrumentation/logic, initialization, shock timing, U.S. data mappings, and
optional model variants. Accordingly, neither “the paper model” nor “the
upstream MATLAB behavior” should be used as an unqualified label.

The audit found close correspondence for the main sales, expectation,
production, wage, household, government, banking, central-bank, and
rest-of-world mechanisms, subject to the differences below. The shipped
2024Q4 U.S. artifact also satisfies the tested opening balance-sheet
identities for the banking/central-bank state. It does not yet pass a complete
U.S. national-accounting test: a runtime audit found an opening
GDP-versus-expenditure residual of roughly −$138 billion, about −1.85% of
modeled quarterly nominal GDP. Reproduce and decompose that residual, then
close it or assign and govern an explicit tolerance before validation. These
are implementation facts, not forecast validation.

Production runs must therefore carry an immutable **model-variant manifest**
covering at least: code commit, paper-faithful versus upstream-compatible
choices, product-tax treatment, trade closure, opening inventories, external
block, exogenous-process specification, policy-rule specification, agent
scale, calibration vintages, and enabled extensions. When the paper, upstream
MATLAB/Julia, and an economically corrected specification disagree, retain and
score separate variants rather than silently choosing one.

### I.2 Apparent paper typos or internal inconsistencies

These are strong candidates for typographical or sign errors because the
printed expression conflicts with the surrounding prose or accounting
identity. Preserve the code behavior for the replication variant, but record
the adjudication and a unit test rather than relying on an undocumented
assumption.

| Paper eq. | Issue | Code | Status |
|---|---|---|---|
| A.26 | As printed, profitable firms would borrow and loss-makers would not | `max.(0, -DD_e_i - D_i)` represents the financing gap ([firms.jl:86](src/agent_actions/firms.jl:86)) | paper–code difference |
| A.55–A.56 | The printed debt sign appears inconsistent with the stated surplus/deficit convention | Deficits add to debt ([government.jl:100](src/agent_actions/government.jl:100)) | paper–code difference |
| C.4 Π_k(0) | The printed deposit-interest sign appears inconsistent with “income less interest payments” | `mu*sum(L_i) + r_bar*E_k`, consistent with the implemented bank-accounting convention ([agents.jl:396](src/model_init/agents.jl:396)) | paper–code difference |

### I.3 Upstream implementation differences from the printed equations

These change behavior relative to the paper text. They are candidates for an
upstream-compatible replication variant, not automatically the preferred U.S.
production specification. Each must be covered by a regression test and the
variant manifest.

| # | Deviation | Paper | Code | Status |
|---|---|---|---|---|
| 1 | Price weight in buyer search is `exp(-2P)`, not `exp(-P)` | A.1.1, p.18 | [search_and_matching.jl:606](src/markets/search_and_matching.jl:606) changes the matching-price elasticity | verified paper–code difference |
| 2 | Size weight in buyer search uses available supply `Y_i + S_i(t-1)` (and `Y_m` for importers), not production `Y_i` | A.1.1, p.18 | [search_and_matching.jl:288](src/markets/search_and_matching.jl:288) | verified paper–code difference |
| 3 | Sector price index P̄_g is sales-weighted and includes import prices | A.28 describes a domestic, production-weighted index | [estimations.jl:152](src/agent_actions/estimations.jl:152) | verified paper–code difference |
| 4 | Profit accounting uses firm-specific realized input prices; zero-purchase firms record zero current purchase cost | A.27 uses market indices | [firms.jl:221](src/agent_actions/firms.jl:221) | verified paper–code difference; size of effect is a hypothesis |
| 5 | Desired production scale for material demand—and apparently intended for investment and labor—is capacity-capped | A.13/A.17/A.20 are uncapped | [firms.jl:15](src/agent_actions/firms.jl:15) | verified paper–code difference, plus defect in §I.4 |
| 6 | Capital-requirement headroom nets out the θ installment through `(1-θ)L(t-1)` | A.59/A.64 use full `L(t-1)` while A.62 creates an internal ambiguity | [search_and_matching_credit.jl:21](src/markets/search_and_matching_credit.jl:21) | verified paper–code difference |
| 7 | Innovations are added to exogenous processes; GDP/exports/imports use correlated shocks | Several printed transition equations are deterministic | [epsilon.jl](src/utils/epsilon.jl), [government.jl:15](src/agent_actions/government.jl:15) | verified; necessary to explain a Monte Carlo forecast distribution, but its exact correspondence to the authors' run needs replication evidence |
| 8 | A combined retail market imposes an ordering between consumption and housing investment | A.44/A.47 describe separate demands without a priority rule | [search_and_matching.jl:453](src/markets/search_and_matching.jl:453) | verified paper–code difference |
| 9 | Firm buyers are served before retail buyers from each good's inventory | A.1.1 does not specify this ordering | [search_and_matching.jl:71](src/markets/search_and_matching.jl:71) | verified implementation detail |
| 10 | A second “phantom demand” pass records unmet demand against spare capacity | A.1 leaves the allocation detail unspecified | [search_and_matching.jl:373](src/markets/search_and_matching.jl:373) | verified implementation detail |
| 11 | Final-demand basket weights are price-renormalized through time | A.43/A.46 give fixed coefficients; footnote 20 bears on interpretation | [search_and_matching.jl:236](src/markets/search_and_matching.jl:236) | paper–code interpretation difference |
| 12 | The Taylor-rule regression is zero-intercept with `r*` pinned to `π*(ξπ−1)` | A.69 and Table B.5 do not clearly support that restriction together | [estimate.jl:53](src/utils/estimate.jl:53) | verified implementation; original estimation convention unresolved |
| 13 | Sector net product-tax rates are read and then zeroed in the dynamic object | App. B.3/Table B.7 use nonzero rates | [calibration.jl:559](src/utils/calibration.jl:559), [calibration.jl:880](src/utils/calibration.jl:880) | verified, economically material |
| 14 | `b^CFH_g` inherits total GFCF product shares instead of a dwellings-specific product vector | App. B.2 uses dwellings investment | [calibration.jl:752](src/utils/calibration.jl:752) | verified, economically material |
| 15 | `τ^FIRM` and `θ^DIV` use implemented profit concepts rather than the printed national-accounts denominator | App. B.1/B.3 | [calibration.jl:919](src/utils/calibration.jl:919) | verified paper–code difference |
| 16 | `τ^EXPORT` is zero and `τ^CF` uses the implemented investment-tax mapping | App. B.3 describes different mappings | [calibration.jl:710](src/utils/calibration.jl:710), [calibration.jl:948](src/utils/calibration.jl:948) | verified paper–code difference |
| 17 | The code supports scaled agent populations; the paper's calibration is conceptually 1:1 | App. B | [calibration.jl:448](src/utils/calibration.jl:448) | verified implementation extension |
| 18 | Labor matching shuffles vacancies and allocates at most one worker per firm in each round, spreading hires across firms | The paper describes worker-side random visits, which can concentrate scarce hires at one firm | [search_and_matching_labour.jl:45](src/markets/search_and_matching_labour.jl:45) | verified behavioral paper–code difference |
| 19 | Zero labor/capital productivities are floored at `MIN_PRODUCTIVITY = 1e-6` | The paper does not specify this numerical floor | [calibration.jl](src/utils/calibration.jl) | verified numerical safeguard; report binding incidence and sensitivity |

Other implementation conventions requiring crosswalk entries include rounding
semantics, applying θ^UB when benefits are calculated rather than storing it
in remembered wages, and estimating EA inflation in `log(1+π)`. Do not call
two stochastic algorithms distribution-equivalent without a proof or
simulation test.

### I.4 A genuine latent defect (fix before trusting long simulations)

**Undotted `min()` at [firms.jl:18](src/agent_actions/firms.jl:18) and
[firms.jl:24](src/agent_actions/firms.jl:24)** is inherited from upstream.
`min(Q_s_i, K_i .* kappa_i)` without the broadcast dot compares the two vectors
lexicographically and returns one whole vector; it is not an elementwise cap
(line 21 uses the intended `min.` form). Which vector wins depends on the first
differing element, so one firm's ordering can select the formula for all firms.
Fix it, add heterogeneous-capacity regression cases, and score the corrected
and upstream-compatible variants on frozen origins. Do not interpret earlier
results as implementing an elementwise capacity constraint.

Related wiring hazard (audit): with `use_growth_rate_ar1=true` the calibration
stores growth-rate AR(1) coefficients under the same keys the standard `Model`
would plug into *log-level* updates (collapsing C_G to ~e^β), while `ModelGR`
ignores those keys and re-estimates its own. The flag is `false` on every
reviewed default production configuration, but the wiring is incoherent if
enabled—guard it.

### I.5 Fork additions (U.S. adaptations and extensions)

The fork contains both opt-in extensions and changes that affect the default
U.S. calibration or run path:

- **Measured trade** (`use_explicit_trade`): commodity imports from BEA T262
  (closer to the paper's "taken directly from the IOT" than upstream's
  goods-balance residual) — but see the §II.4 flow-consistency problem it
  exposed.
- **Purchasers→basic-price valuation bridge** (`use_product_tax_netting`):
  necessary because BEA tables are not Eurostat basic-price product-by-product
  IOTs; observed product taxes preserved for a future accounting repair.
- **Opening sector inventories** (`use_commodity_balance_inventory`): S_s from
  a negative supply-use discrepancy — **no paper counterpart** (paper sets
  S_i(0)=0). Its economic interpretation and dynamic consequences are not yet
  established; §II.4 makes that a required diagnosis.
- **Negative trade cells clamped** to zero when building c^E_g/c^I_g
  (confirmed): re-export/residual artifacts redistributed across sectors.
- **`ea` block = U.S. data**, so the Taylor rule reacts to exogenous U.S.
  activity and inflation series while no independent foreign-demand block
  remains.
- **ModelGR** growth-rate AR(1) variant and **CANVAS** per-period re-estimation
  variant (both opt-in, both off in production).
- **Scenario shock timing** applies productivity shocks at `t=1` and reverses
  temporary consumption shocks at `final_time+1`; record timing in the variant
  manifest and add boundary-period regression tests.
- Census labor counts, sectoral D.11 wages, transaction/opening-state loggers,
  provenance/validation infrastructure (raw vintages + SHA-256, DuckDB,
  four-status parameter ledger: 40 APPROVED / 17 DUBIOUS in the reviewed
  snapshot).
- **Forecast-calibration layer** ([calibrate_outlook.jl](scripts/us/forecasting/calibrate_outlook.jl)):
  Taylor-rule coefficients *fitted to backtest errors* and damped log-bias
  output corrections applied to published paths — **no paper counterpart**;
  Part III replaces this.

### I.6 What is missing relative to the paper

- **Appendix D conditional-forecast expectations**: the ARX(1) replacement of
  A.6/A.9 (expectations loading on log imports, government consumption,
  exports) is not implemented — `estimate_with_predictors` exists only as
  commented-out code ([estimate.jl:37-51](src/utils/estimate.jl:37)).
  `examples/Conditional_forecasts.jl` substitutes only the exogenous paths.
- **The entire Section 3 validation protocol** (rolling origins, free-running
  multi-horizon forecasts, AR/VAR/DSGE benchmarks, RMSE gain tables, sectoral
  GVA and three-approach GDP-composition figures). The current U.S. backtest
  is h=1, re-anchored, uses seven fitting quarters and two holdout quarters,
  and reports MAPE against a fixed engineering gate without a formal
  challenger. It therefore supports no comparative forecast-skill conclusion
  and should not be cited as Poledna-style validation.

### I.7 Current repository readiness snapshot

The current U.S. configuration is useful for pipeline engineering, not a
forecast-skill claim:

| Item | Reviewed state | Development implication |
|---|---|---|
| Structural coverage | one 2024 annual U.S. structural row; valid calibration quarters currently recent (approximately 2024Q1–2026Q1) | historical structures and release vintages are a major data build |
| Agent resolution | scale `1e-5`; 130 firms; 54/68 single-firm sectors; about 2,831 modeled people | scale ladder is mandatory |
| Forecast fit/evaluation | seven fitting quarters, two held-out quarters, h=1, 128 simulations, reanchored levels, current-vintage truth | engineering smoke test only |
| Forecast fitting | Taylor-rule overrides plus seven target-specific damped corrections | split raw dynamic parameters and publication layer |
| Real-time claim | configuration explicitly says `real_time_vintage_claim=false` | no historical real-time claim is permitted |
| Parameter checklist | 40 `APPROVED`, 17 `DUBIOUS` in the reviewed snapshot | every questionable field needs a terminal registry status |
| Test run | 660 passing assertions before a live Zenodo fixture timed out | create a hermetic suite plus separately scheduled network tests |

The 17 questionable fields include firm interest/debt and consolidation
concepts; sector wages; enterprise/establishment and job/person bridges;
productive assets, dwellings, and consumption of fixed capital;
intermediate-input allocation; product and dwellings-investment taxes;
government/farm proxies; backcasts; and recent labor observations. A finite
number that closes one identity can still be economically misclassified.

Resolve each as:

1. `APPROVED` with empirical validation;
2. `ASSUMPTION` with owner and sensitivity/prior;
3. `UNOBSERVED_LATENT` with estimator and uncertainty;
4. `REJECTED` with replacement or model redesign.

---

## Part II — Calibration guideline: making the parameters reflect the U.S. economy

### II.1 The calibration philosophy and the firewall

The paper's discipline, which this plan retains:

1. **No behavioral parameter is fitted to match time-series dynamics.** Every
   parameter is either (a) read directly from data, (b) computed from a
   national-accounting identity, (c) taken from literature/regulation, or
   (d) an OLS estimate of an *exogenous* AR(1)/Taylor process. The model's
   forecast skill is then an out-of-sample property, not the residue of
   curve-fitting. This is the paper's central methodological claim and the
   reason its validation is credible.
2. **Re-calibration is part of the model.** For forecasting, parameters and
   initial conditions are recomputed every quarter from data through the
   forecast origin (paper §2 p.5, App. C p.40). A single frozen artifact is
   not the paper's model. In the U.S. real-time implementation, this means
   carrying forward the latest eligible annual structure while updating
   eligible quarterly dynamics and origin state—not inventing a new I-O table
   each quarter.
3. **Stock-flow consistency is the acceptance test.** GDP must reconcile under
   production, income, and expenditure approaches at initialization and along
   simulated paths (paper Fig. 4).

To make (1)–(3) operational, adopt a fixed vocabulary and a **calibration
firewall** separating six activities, each with its own permitted information
set and its own immutable artifact:

| Activity | Permitted information | Artifact |
|---|---|---|
| Structural calibration | cross-sections/identities from releases available at the origin | structural parameters |
| Dynamic estimation | training history through the origin (AR processes, Taylor rule, shock covariance) | dynamic parameters |
| State initialization | releases known at the origin (the paper's App.-C reset) | origin state |
| Forecast correction (optional) | *completed prior forecast errors only* | separate correction artifact |
| Forecast evaluation | frozen forecasts + subsequently released truth | scorecard |
| Conditional scenario | explicit conditioning assumptions | scenario paths, never pooled with unconditional forecasts |

No future realization, revision, or structural release crosses back through
the firewall. Two immediate consequences for the current pipeline:

- **Stop writing forecast-fitted Taylor overrides into baseline artifacts.**
  `build_baseline!` currently applies `apply_forecast_parameter_overrides!`
  from [forecast_calibration.toml](scripts/us/forecast_calibration.toml) into
  the calibrated parameter object. Original estimates are retained in metadata
  and can be reconstructed, but the layers are not cleanly immutable or
  independently addressable. Write structural, dynamic, and (if ever used)
  correction layers as separate files.
- **The damped log-bias output corrections are a correction artifact**, not
  part of the ABM. Going forward, retain and score the raw ensemble/path
  artifact as well as any corrected summary; the current outlook output does
  not itself guarantee retention of all raw paths. If a correction creates
  the measured gain, attribute the gain to the correction, not to agent or
  network mechanisms.

The firewall is enforced by the following development principles:

1. **Definitions precede values.** A source is accepted only after its scope,
   unit, timing, valuation basis, and model meaning agree.
2. **Stocks and flows remain distinct.** End-of-period stocks, quarterly
   flows, SAAR flows, annual flows, indexes, rates, people, jobs,
   establishments, and enterprises have typed units and explicit conversions.
3. **Accounting identities are hard constraints.** An optimizer may not buy
   forecast fit by violating stock-flow closure.
4. **Vintages are data.** A value without a release timestamp and revision
   history is not eligible for historical forecast reconstruction.
5. **Aggregation is versioned.** Every NAICS–BEA–model concordance and every
   retail, government, farm, housing, or trade bridge has a version and hash.
6. **Assumptions are visible.** Paper constants and reduced-form bridges are
   not relabeled as U.S. observations.
7. **Weak measurement implies uncertainty.** Proxies and residual allocations
   receive distributions or sensitivity ranges, not false precision.
8. **No evaluation leakage.** Later outcomes, revisions, or structural
   releases cannot affect an origin's calibration, model selection, or state.
9. **Primary comparisons use common information.** Published institutional
   forecasts remain a separate operational track.
10. **Raw results are immutable.** Corrections and combinations create new
    products; they never overwrite raw ABM paths.
11. **Scale is part of the model.** It changes matching and concentration and
    therefore requires convergence evidence.
12. **Purpose controls champion selection.** Aggregate forecasts, sector
    forecasts, nowcasts, densities, and scenarios may have different champion
    models.

### II.2 Parameter taxonomy and U.S. status

The paper's Table 1/B.5 groups every parameter by source. U.S. status after
the audit:

Create `scripts/us/calibration/parameter_registry.toml` before estimating or
changing parameters. Use these classes consistently:

| Class | Meaning | Examples | Update rule |
|---|---|---|---|
| A | Directly observed | firm counts, employment controls, government debt, bank equity | update only on an eligible release |
| B | Identity-derived | productivities, I-O shares, effective tax/propensity ratios | recompute after the relevant reconciled release |
| C | Econometrically estimated | AR/ARX coefficients, covariance, policy rule | re-estimate at the frozen origin cadence |
| D | Latent behavioral | search/adjustment/default parameters not directly observed | estimate from identified training moments; freeze between reviews |
| E | Institutional/policy | tax schedules, transfer rules, capital requirements | update on rule change or evidence release |
| F | Modeling assumption | utilization, synthetic J/L counts, abstraction bridges | replication value plus U.S. sensitivity range; never silently fit |
| G | Numerical resolution | agent scale, ensemble size, matching approximation | change only after numerical validation |
| H | Publication layer | past-error bias correction or combination weight | separate artifact based only on completed forecasts |

Minimum row schema:

```text
parameter_id
model_symbol
description
economic_unit
frequency
sector_dimension
parameter_class
source_series
source_table_and_line
reference_period
release_vintage
transformation
estimator_or_identity
admissible_range
prior_or_uncertainty
update_cadence
allowed_forecast_products
identification_targets
sensitivity_result
owner
independent_validator
review_status
tests
artifact_hash
```

**Block 1 — Agent counts (census / business demography).**

| Param | Paper rule | U.S. status | Action |
|---|---|---|---|
| I_s (firms/sector) | Business demography active enterprises | Primarily SUSB enterprises plus USDA farms and pseudo-producers; mixed proxies remain | Record the current enterprise-based convention, then decide and validate the production-unit ontology rather than assuming all sectors are conceptually homogeneous |
| H^act, H^inact | Census/LFS | BLS CPS counts wired (`unemployed_census`/`inactive_census`) | Keep |
| J (government entities) | Implemented as total firms/4; commented alternative refers to a government-consumption/output mapping | Inherited ratio | Treat as synthetic matching granularity, not an observed government count. Reproduce a precisely defined paper/upstream rule, then select alternatives through scale and matching-variance tests |
| L (foreign consumers) | Implemented as total firms/2; commented alternative refers to exports/value-added | Inherited ratio | Treat as synthetic matching granularity. Test whether changing it affects allocations at fixed export totals before adopting a U.S.-share rule |
| scale | Conceptually 1:1 in the paper | **1e-5**: 130 firms; 54/68 sectors have exactly one firm; approximately 2,831 modeled people including active and inactive households | See §II.6 |

**Block 2 — IOT-derived technology and demand coefficients.**

α_s, β_s, κ_s, δ_s, w̄_s, a_sg, b^CF_g, b^HH_g, c^G_g, c^E_g, c^I_g, τ^Y_s,
τ^K_s are populated from the BEA-based 68-commodity/71-source-industry
calibration with a valuation bridge. “Populated” does not yet mean economically
validated. Open items:

- **b^CFH_g composition** (§I.3 #14): rebuild from a documented BEA
  residential-investment final-demand product vector rather than multiplying
  a scalar dwellings total by total-GFCF product shares. Verify the exact BEA
  table/line mapping and vintages before coding; do not infer the composition
  from the aggregate `F02R` control alone.
- **τ^Y_s zeroing** (§I.3 #13): keep the model-compatible zeroing for now
  as an explicit replication candidate while the accounting design is tested.
  A source comment describes MATLAB compatibility, but the checked-in MATLAB
  calibration calculates nonzero `τ^Y_s`; the upstream convention is therefore
  unresolved. Keep publishing both observed and zeroed views (the observed
  bridge is stored in `figaro["taxes_products"]`), encode the choice as a
  model-variant flag, and never describe zero as an observed calibration.
- **c^E_g/c^I_g clamping**: document the redistributed weight per vintage
  (QA report), since it changes sectoral trade composition; no sign is clipped
  without a residual ledger entry.
- **Sector-dimension contract**: publish one authoritative statement that the
  modeled system is **68 commodities built from 71 BEA source industries**
  (with the retail 4A0 aggregation), and sweep the docs — parts of
  [README_US_CALIBRATION.md](README_US_CALIBRATION.md) still say "71-sector
  calibration".
- **Chain-type quantities:** do not create component identities by adding
  chained-dollar series. Calibrate and score current-dollar identities,
  chain indexes, or official contribution-to-growth measures as appropriate.

**Block 3 — Rates and propensities (government statistics / sector accounts).**
τ^INC, τ^FIRM, τ^VAT→sales-tax analogue, τ^SIF, τ^SIW, τ^CF, τ^G, r^G, μ, ψ,
ψ^H, θ^DIV are mostly identity-derived from NIPA/Z.1 inputs, with the named
profit-denominator, tax-bridge, zero-export-tax, and investment-tax deviations
in §I.3. One Austrian institutional constant survives:

- **θ^UB = 0.55(1−τ^INC)(1−τ^SIW)** embeds a 0.55 gross replacement assumption
  ([calibration.jl:960](src/utils/calibration.jl:960)). U.S. unemployment
  insurance varies by state, wage, duration, and emergency program.
  Opening `w_UB` already uses observed aggregate UI divided by modeled
  unemployed, so θ^UB mainly governs newly unemployed workers and later
  replacement, not the opening aggregate benefit bill. **Action:** define that
  transition concept; estimate an effective origin-vintage replacement mapping
  from Department of Labor/NIPA covered-wage evidence; and sensitivity-test a
  preregistered range. Do not present the Austrian constant as a U.S.
  observation.

Also record as declared abstractions (not observations): rest-of-world opening
deposits D_RoW = 0, and the single-instrument mapping of all credit-market
debt onto bank loans (already flagged in README §1.5/§8).

**Block 4 — Literature/regulatory constants.** θ=0.05 (amortization), ζ=0.03
(capital/leverage constraint), ζ^LTV=0.6, ζ^b=0.5, and the inflation target are
modeling assumptions. The model's ζ ratio is not mechanically the U.S.
supplementary leverage ratio, whose exposure and capital concepts differ.
Map ζ to an explicit reduced-form U.S. bank-balance-sheet concept if possible;
otherwise label it as an assumption. If the inflation target is represented
as a quarterly rate, use `(1.02)^(1/4)-1`, not 0.02 per quarter. θ, ζ^LTV, and
ζ^b also need concept definitions, priors/ranges, and sensitivity analysis.
None may be silently tuned to forecast errors.

**Block 5 — Estimated exogenous processes.** The code estimates AR processes
for C_G, exports, imports, `"EA"` (=U.S.) GDP and inflation, plus a Taylor
rule. These broadly follow the paper's calibration class but include the
implementation differences in Part I and four U.S.-specific issues:

- **Near-unit-root log-level AR(1)s on trending U.S. series** can create
  economically implausible medium-horizon attractors. Compare the
  paper-faithful log-level process with growth-rate, local-trend, and—where
  jointly warranted—cointegrated alternatives at every origin using only
  eligible training data. This is relevant at h=4–12, not only beyond the
  paper's horizon.
- **Taylor rule**: re-check a free-intercept estimation on Fed-funds data
  (the paper's own Table B.5 values imply the authors estimated a constant);
  keep π\* at (1.02)^{1/4}−1. The paper's rule reacts to *exogenous* AR
  proxies of inflation/growth — acceptable for a small open economy in a
  monetary union, structurally wrong for the U.S. (no policy feedback damping
  endogenous fluctuations). The replication variant keeps that structure;
  the production candidate evaluates endogenous arguments separately. CANVAS
  re-estimates coefficients but still uses exogenous `rotw.gamma_EA/pi_EA`, so
  it is not itself the endogenous-rule implementation.
- **Effective lower bound.** U.S. estimation windows and Window-A origins sit
  inside the 2009–2015 ELB era (and 2020–2021). The simulation side is
  mechanically safe — A.69 carries `max(0, ·)` — but OLS on a floored rate
  biases the estimated reaction coefficients. Decide and document one
  treatment: estimate on the pre-ELB sample and hold, use a shadow-rate
  series as the regressand, or censored (Tobit-style) estimation. The current
  rule sees exogenous `rotw.pi_EA`, populated from the U.S. GDP-deflator series;
  it does not see endogenous model inflation. PCE variants are scored targets
  unless and until a separate production-rule variant is defined.
- **σ_G log-normal mean inflation**: report `exp(σ²_G/2)` for every origin; if
  economically or statistically material under a preregistered tolerance,
  center the innovation or change the point-forecast convention explicitly.

**Parameter-specific U.S. development agenda.**

- **Production units and labor:** decide whether an agent represents an
  enterprise, establishment, or production unit; reconcile SUSB employer
  enterprises, QCEW establishments/jobs, CES payroll jobs, CPS employed
  persons, farms, relevant nonemployers, government productive units, and
  owner-occupied housing. `α_s` must control to people-based employment while
  retaining a measured multiple-job-holder bridge.
- **Wages and technology:** reconcile `w_s` to NIPA wages and salaries while
  keeping supplements/employer contributions separate. Preserve raw
  commodity×industry and modeled symmetric matrices for `β_s`/`a_sg`. Define
  productive capital consistently for dwellings, owner-occupied housing, and
  government enterprises; align `κ_s` and `δ_s` denominators with BEA fixed
  assets and consumption of fixed capital.
- **Final demand and trade:** reconcile household, government, investment, and
  housing baskets across purchaser/basic prices, margins, taxes, current
  dollars, and chain indexes. Keep domestic exports, re-exports, imported
  intermediates, and imports for final use distinct and retain excluded/
  noncomparable commodities in the ledger.
- **Households:** test whether single `ψ` and `ψ^H` ratios are stable enough for
  forecasting versus trailing, state-dependent, or
  disposable-income/liquid-wealth formulations. Reconcile Z.1 HH+NPISH liquid
  assets and dwellings with NIPA sector scope. Keep CPS participation and
  demographic entry/exit people-consistent.
- **Firms and credit:** map interest and debt consistently across corporate/
  noncorporate firms and loans, bonds, mortgages, and other credit. Validate
  `θ` against maturity/amortization evidence; treat `ζ`, `ζ^LTV`, and `ζ^b`
  as reduced-form constraints unless directly mapped. Reconcile or explicitly
  abstract from rest-of-world deposits. Add heterogeneous banks only if a
  frozen baseline shows the representative bank is inadequate for a declared
  target.
- **Government:** distinguish purchases from transfers, federal from
  state/local, statutory changes from cyclical effective rates, accrual from
  cash concepts, and market from par value of debt. Interest flows must be
  compatible with opening stocks.
- **Numerical interventions:** report every productivity floor, clamp,
  rounding repair, or synthetic count that binds. Repair source concepts where
  possible and score sensitivity; never present a numerical safeguard as
  observed data.

### II.3 The `ea` block and the small-open-economy problem

Three design facts must be explicit: (1) the legacy `"euribor"` key holds the
federal funds rate; (2) the `ea` block is populated with U.S. GDP/deflator, so
the policy rule responds to an **exogenous U.S. proxy**, not endogenous ABM
output and inflation; and (3) exports/imports are exogenous AR processes while
there is no independent foreign-demand state. U.S. trade shares alone do not
make this harmless: dollar, commodity-price, foreign-demand, and global
financial channels can be material.

Keep the current mapping only as a paper-port replication variant. Before a
production trade or policy claim, build and score a candidate that separates:

- domestic policy arguments, preferably with an endogenous-output/inflation
  rule or an explicitly exogenous policy scenario;
- trade-weighted foreign activity and inflation;
- exchange-rate/import-price and global-financial conditions where supported;
- correlated export/import innovations and scenario paths.

The variant choice is empirical and must be frozen before the scored run; poor
results are not permission to retrofit the external block to the evaluation
sample.

### II.4 Resolve commodity balance and opening inventories before forecast claims

The 2024Q4 artifact contains nonzero signed commodity discrepancies: 26
positive and 42 negative entries, with opening inventory assigned to the
negative side. This is verified. The claim that this alone causes a particular
GDP or export decline is a **hypothesis** until isolated by controlled
counterfactual runs. A discrepancy can represent legitimate changes in
private inventories, omitted/aggregated final uses, valuation and
margin/tax differences, excluded “other/used” commodities, frequency mismatch,
or statistical discrepancy. Explicitly trace the applicable BEA
change-in-private-inventory/related final-use mapping, including F030 where it
enters the source tables. Treating all of it as an opening stock—or balancing
it all away—can both be wrong.

The present pipeline also compares an industry-output control with
commodity-row uses/imports at points in the closure calculation. Resolve the
industry-versus-commodity basis first, using the BEA make/supply mapping and a
single declared valuation basis. Applying RAS directly to a mixed-basis
residual could distort an already balanced published supply-use system.

Required sequence:

1. **Build a valuation-consistent ledger.** At each structural vintage,
   reconcile current-dollar supply and use at the same basic/purchasers-price
   convention. Preserve source identity, sign, structural zeros, release
   timestamp, uncertainty/confidence, and every transformation.
2. **Classify every residual.** Separate measured change in private
   inventories (a flow) from opening stocks, omissions, valuation bridges,
   aggregation, and true statistical discrepancy. Document any conversion of
   an annual inventory flow into a quarterly opening stock.
3. **Compare three declared closures:**
   - explicit inventory/change-in-inventory treatment with a defensible stock
     initialization;
   - constrained RAS/GLS/cross-entropy reconciliation with source-specific
     covariance/confidence weights, preserved zeros/signs, and fixed published
     controls where warranted;
   - the upstream residual-import closure as a replication fallback.
4. **Run controlled dynamics.** Hold seeds and calibrated totals fixed where
   possible; compare initialization residuals, rationing, realized trade,
   inventories, prices, GDP components, defaults, and conservation identities
   over 1, 4, and 12 quarters.
5. **Select before evaluation.** Choose the production closure using
   preregistered accounting and dynamic-transition criteria on training
   origins, then freeze it. Publish all adjusted cells/margins and the implied
   discrepancy.

Tolerances must reflect source uncertainty and economic materiality, not a
universal arbitrary percentage. Hard gates apply to exact identities after the
chosen reconciliation; softer residual gates carry documented statistical
tolerances. No model variant may call an unclassified discrepancy “inventory.”

### II.5 Calibration acceptance gates

A calibration artifact is *accepted* only if it passes the following layered
gates (extending README §6.2):

1. **Schema/provenance:** dimensions, units, transformations, seasonal
   adjustment, reference period, release/vintage, retrieval timestamp, source
   ID, hash, pipeline commit, and model variant are complete.
2. **Accounting:** all hard national-accounting and balance-sheet identities
   pass at declared tolerances; residuals have the §II.4 ledger; chain-type
   quantities are handled consistently; no unexplained sign clamp or residual
   allocation remains. Test each identity in every period; never aggregate
   signed residuals across time where opposite errors can cancel.
3. **Numerics:** deterministic and stochastic 1/4/12-quarter tests contain no
   NaN/Inf, violation of variable-specific admissible domains, unbounded
   explosion, or unexplained discontinuity. Negative net positions and signed
   flows remain allowed where economically meaningful. Units for every rate
   and growth check are explicit.
4. **Initialization stability:** repeated synthetic-agent draws conditional on
   the same aggregate state do not create economically material shifts in
   forecast moments beyond preregistered Monte Carlo tolerance.
5. **Empirical plausibility:** prior-predictive and one-step hindcast checks
   compare means, variances, autocorrelations, cross-correlations, hazards, and
   key ratios with training-sample distributions using a preregistered
   moment-distance dashboard. A wide ensemble containing history is not a
   passing criterion by itself.
6. **Scale convergence:** the production scale passes §II.6.
7. **Parameter registry:** no parameter is missing or silently rejected.
   Every value has a terminal status—observed/identity, estimated, assumption,
   latent, or replaced—and all assumptions/latents have uncertainty treatment.

The machine-readable parameter record must include: symbol and economic
definition, formula, unit/frequency, source series/table, reference period,
release/vintage, transformation, parameter class, update cadence, owner,
uncertainty/prior, bounds, identification targets, sensitivity result, status,
approver, and artifact hash.

### II.6 Agent scale

At 1e-5 the 2024Q4 artifact contains 130 firms and approximately 2,831 modeled
people; 54 of 68 sectors have exactly one firm and the implied unemployed
population is about 68. This is too coarse to assume that firm heterogeneity,
matching, bankruptcy cascades, or labor-market tail risks are scale-invariant.
The paper is conceptually 1:1. **Plan:** run a
scale ladder {1e-5, 2e-5, 5e-5, 1e-4, 2e-4, 1e-3, and the largest
computationally feasible scale} × 12 quarters, beginning with 32-seed batches
and expanding until comparison uncertainty is below a preregistered tolerance,
with matched aggregate controls and aligned RNG substreams. Compare ensemble
means and bands, impulse responses, firm-size tails, matching/rationing rates,
bankruptcy counts, and sector cross-correlations. **Acceptance rule:** freeze
the smallest scale whose forecast-relevant statistics are stable, within
predeclared tolerances, against the *next two larger* scales. If nothing
converges, either raise the production scale, derive scale-adjusted
matching/entry rules, or restrict claims to statistics shown scale-invariant.
At 1e-3 the present scaling rules imply roughly 13,000 firms and 283,000
modeled people, not a full-population representation. The ladder—not a
preselected target—determines production scale. Stamp the scale, aggregation
semantics, and scale-validation version on every forecast.

### II.7 Structural-calibration build procedure

The implementation team should treat structural calibration as an ordered,
testable build, not one monolithic script.

#### Step 1 — Freeze the economic concept dictionary

Deliver:

- one dictionary for every model variable and parameter;
- official source concept, sector scope, unit, stock/flow status, frequency,
  price basis, seasonal adjustment, and conversion;
- explicit household, firm, bank, government, central-bank, and
  rest-of-world boundaries;
- enterprise/establishment/job/person and industry/commodity definitions;
- the approved 71-source/68-modeled concordance plus every alternative
  aggregation used in sensitivity tests.

Gate: two reviewers can independently trace every required field to an
official table, line, release, unit, and transformation. No `DUBIOUS` field
remains unlabeled as evidence, assumption, latent quantity, or rejection.

#### Step 2 — Build a symmetric, valuation-consistent supply/use system

Start from the BEA commodity×industry supply/use system and make/supply
transformation. Choose a commodity or industry model basis; do not compare
industry output directly with commodity uses. Preserve:

- domestic commodity output and supply;
- intermediate row and column controls;
- value added by industry;
- household, government, fixed-investment, inventory, export, and import uses;
- trade/transport margins and taxes less subsidies;
- excluded, noncomparable, used, re-export, and statistical-discrepancy items.

Only after basis and valuation are consistent may a GLS, cross-entropy, or RAS
reconciliation use source-specific measurement covariance. Store raw, bridged,
balanced, and model matrices. Gate: every adjustment is reported in dollars
and relative to its source control; structural zeros/signs are preserved or
explicitly approved; all three GDP approaches reconcile within declared
source-aware tolerances.

#### Step 3 — Resolve tax accounting as two explicit prototypes

1. **Observed-tax prototype:** carry nonzero `τ^Y_s` consistently through
   producer/purchaser prices, consumption, value added, disposable income, and
   government revenue.
2. **Zero-product-tax prototype:** retain the current dynamic abstraction while
   storing observed taxes in the valuation bridge.

Gate: production, income, and expenditure identities agree under the selected
price basis; taxes are neither double-counted nor silently dropped; the
selection is a model-version flag. Prefer the observed-tax specification if it
can be implemented coherently—never because it improves held-out scores.

#### Step 4 — Calibrate productive units and employment

Construct the SUSB–QCEW–CES–CPS–farm–government–housing crosswalk and select
what one firm agent represents. Use constrained integerization or balanced
sampling so aggregate counts survive scaling. Gate: people and job controls
reconcile; the firm-size distribution matches declared micro moments;
alternative count concepts remain reproducible sensitivity variants.

#### Step 5 — Estimate technology and price-basis coefficients

After reconciliation, calculate and document:

```text
alpha_s = quarterly volume-consistent output / employed persons
beta_s  = output / intermediate-input volume
kappa_s = quarterly output / (productive capital × normal utilization)
delta_s = quarterly consumption of fixed capital /
          (productive capital × normal utilization)
w_s     = quarterly wages and salaries / employed persons
```

For current-price I-O coefficients, state exactly how real quantities and price
dynamics are interpreted; test double-deflation or chain-index alternatives
where relevant. Gate: no unexplained floor binds, zero/negative source values
are reviewed, ratios are plausible against historical distributions, and
quarterly time-scale tests are exact.

#### Step 6 — Calibrate household and fiscal flows

Reconcile disposable income, consumption, residential investment, transfers,
property/mixed income, taxes, and social contributions. Compare point-in-time
paper identities with robust trailing or state-dependent ratios using only
training data. Gate: household and government budgets close, bases agree
across sectors, revision sensitivity is measured, and structural versus
cyclical movement is documented.

#### Step 7 — Reconcile financial balance sheets and interest flows

Create an instrument bridge from every Z.1 asset/liability to model deposits,
loans/debt, equity, government debt/cash, central-bank, and rest-of-world
positions. If several market instruments collapse into one bank loan, quantify
effective rate, duration, collateral, and credit-risk consequences. Gate:
every modeled asset has a liability counterpart or named discrepancy; opening
net worth reconciles; interest flows agree with stocks/rates; no residual is
hidden in central-bank equity.

#### Step 8 — Construct micro initial conditions

Generate firm counts, sector assignments, employment, wage bills, production,
productive capital, material/finished inventories, firm cash/debt, household
states/assets/dwellings, and institutional balance sheets subject to exact
aggregate controls. Gate:

- the seed and artifact fully reproduce initialization;
- integerized aggregates close;
- target distributional moments match;
- no agent has an impossible balance sheet;
- adaptive batches of initialization seeds produce stable opening aggregate
  moments under preregistered Monte Carlo tolerances (100 is a useful planning
  batch, not a universal gate);
- the full per-identity/per-period U.S. accounting suite passes.

### II.8 Dynamic and behavioral calibration

**Dynamic-process candidates.** Estimate government consumption, exports,
imports, expectations, foreign variables, and policy processes under a
preregistered training-only comparison:

- paper-compatible log-level AR(1);
- stationary growth-rate AR;
- local-trend/state-space process;
- ARX with foreign activity, exchange rates, fiscal indicators, surveys, or
  import demand;
- cointegrated systems where economically justified.

For expectations, compare paper AR(1), recursively estimated ARX,
vintage-available SPF augmentation, and partial-information state-space
variants. The unconditional product never exposes agents to realized future
trade or fiscal paths.

**Policy rule.** Estimate smoothing, neutral-rate intercept, inflation and
activity responses, target convention, and innovation variance. Compare
pre-ELB linear, shadow-rate/censored, and explicitly unconventional-policy
variants. A time-varying neutral rate or regime switch must earn its complexity
inside nested training validation.

**Innovation law.** Estimate a positive-semidefinite joint covariance for
foreign activity, trade, prices, fiscal, and monetary shocks; use shrinkage
when needed. Test residual autocorrelation, heteroskedasticity, tail shape, and
subperiod stability. Compare Gaussian, Student-t, and empirical-bootstrap
innovations while preserving coherent multivariate paths.

**Behavioral SMM challenger.** The no-behavioral-forecast-fitting model remains
the replication baseline. Only parameters not pinned by observations,
identities, or defensible external evidence enter a separately labeled SMM or
likelihood-free challenger.

Identification moment families are:

- labor: unemployment duration, vacancy/unemployment, hiring/separation, wage
  adjustment;
- firms: size, entry/exit/default, markup/profit share, investment, and
  inventory/sales;
- credit: growth, spreads, lending standards/denials, charge-offs, and bank
  capital;
- households: consumption/income response, residential investment, and liquid
  assets;
- network: input shares, concentration, and propagation of sector shocks;
- macro dynamics: predeclared autocorrelations/cross-correlations of output,
  inflation, unemployment, investment, inventories, and credit.

Each moment has one primary identification block unless overlap is modeled.
For behavioral vector `θ_B`, data moments `m_data`, simulated moments
`m_sim(θ_B)`, and accounting residuals `g(θ_B)`, use:

```text
min over θ_B:
    [m_sim(θ_B) - m_data]' W [m_sim(θ_B) - m_data]
    + λ_prior R(θ_B)
    + λ_stability S(θ_B)

subject to:
    g(θ_B) = 0
    lower_bound <= θ_B <= upper_bound
```

`W` is a regularized inverse moment covariance or transparent block weighting;
`R` anchors external evidence; `S` penalizes explosive/non-ergodic behavior.
Final evaluation RMSE never enters the objective.

Estimation sequence:

1. Morris/Sobol or comparable global sensitivity screening;
2. fix or remove nonidentified parameters;
3. coarse global search with aligned RNG substreams;
4. surrogate-assisted/Bayesian optimization;
5. local refinement;
6. independent-seed verification;
7. profile-objective or simulation-based posterior uncertainty;
8. held-out moment-family validation.

Report parameter ridges/correlations, monotonic moment responses,
leave-one-family-out estimates, subperiod stability, boundary/prior dominance,
and the Pareto frontier when no vector fits all families. Simplify mechanisms
that cannot be identified.

---

## Part III — Forecast contract, validation, and benchmarks

### III.1 What the Austrian exercise establishes

The paper provides the replication reference, not the U.S. promotion rule.
The published text describes:

- an initial estimation history beginning 1997:Q1 and running through
  2010:Q1;
- forecasts covering 2010:Q2–2016:Q4, with parameters recalculated or
  re-estimated at quarterly origins through 2013:Q4;
- horizons h = 1, 2, 4, 8, and 12 quarters;
- 500 stochastic simulations, ensemble means as point forecasts, and 90%
  ensemble bands;
- RMSE and percentage gain/loss relative to AR, VAR, and Bayesian DSGE
  benchmarks, without modern forecast-comparison inference;
- an ex-post conditional exercise using realized government consumption,
  exports, and imports plus Appendix-D expectations;
- sector GVA and the production/income/expenditure views of GDP.

The reference economy contains firms, households, government, a bank, central
bank, and rest of world; decentralized goods/labor/credit matching; Leontief
production; insolvency/replacement; and approximately one modeled entity per
observed Austrian entity. It begins from a 64-category NACE/CPA system and uses
Eurostat national/sector/I-O/fixed-asset accounts, business demography,
government finance, census/labor, financial balance sheets, money-market
rates, and euro-area output/inflation.

Developer reference for the paper's calibration intent:

| Quantity | Reference construction |
|---|---|
| firm/household counts | business demography and census/labor controls |
| `α_s` | output/employment with quarterly conversion |
| `β_s` | output/intermediate consumption |
| `κ_s` | output/(productive capital × normal utilization) |
| `δ_s` | consumption of fixed capital/(productive assets × utilization) |
| `w_s` | sector wages/employment |
| `a_sg` and final-demand shares | normalized I-O/intermediate and use vectors |
| propensities/taxes/dividends/risk premium | observed flows divided by model-consistent bases |
| micro initial conditions | firm employment draw followed by accounting allocation of production, capital, inputs, cash/debt, household and institutional stocks |

The DSGE comparison adapts a two-country Smets–Wouters-type system, uses 13
domestic/euro-area observables, and reports 250,000 MCMC draws with the first
50,000 discarded. These are replication settings, not automatic U.S.
production settings.

The text does not by itself make every origin/target indexing convention
unambiguous. Before claiming numerical replication, recover the exact forecast
origin convention from the authors' runnable code/data or document a
reproducible interpretation. The paper does not document a
release-timestamp real-time-vintage protocol; treat replication as a
revised-data diagnostic of implementation, not evidence that an operational
forecaster could have produced the same result.

The repository does **not** currently ship the rolling Austrian inputs needed
for this exercise. It exposes recent Austrian baselines and a frozen 2010Q1
parameter/initial-condition pair, not a complete origin-by-origin
2010–2013 calibration archive. Reconstructing the historical Austrian inputs,
licensing them, or obtaining the authors' artifacts is therefore a feasibility
gate, not a ready-made harness run.

### III.2 Freeze the forecast products before calibrating them

Four products/experiments have different information sets and must never be
pooled in one ranking:

| Product | Information cutoff | Purpose | Primary comparators |
|---|---|---|---|
| Quarterly unconditional forecast | Fixed release timestamp after the latest eligible quarterly release; recommend the first business day after BEA's advance GDP release, subject to an explicit operations decision | Core h=1,2,4,8,12 forecast | Naive, AR, VAR/BVAR, semi-structural, DSGE, SPF |
| Ragged-edge nowcast | Fixed monthly/weekly cutoffs before and during the reference quarter | h=0 and h=1 state update | Dynamic factor, bridge, MIDAS, BVAR, archived GDPNow/NY Fed nowcasts |
| Ex-ante conditional/scenario forecast | Same origin information plus a versioned assumption path known at issue time | CBO baseline, fiscal, trade, financial, or user scenario | Conditional ARX/BVAR, semi-structural and FRB/US-style scenario responses |
| Ex-post paper conditional exercise | Realized future G/E/M paths | Replicate/decompose the paper only | Paper-matched ARX |

Recommended operating conventions to decide in WS-0A:

- quarterly forecast immediately after the BEA advance GDP release, with
  h=1,2,4,8,12; add h=3 only for a declared user need;
- nowcasts at fixed monthly cutoffs such as the tenth business day after
  month-end plus a final pre-advance-release cutoff, scored separately at h=0
  and h=1;
- scenarios that label every variable hard-conditioned, softly conditioned,
  or endogenous and always show the unconditional baseline beside them.

For each product freeze: forecast timestamp and timezone; publication calendar;
latest-observation convention; target definitions; transformations and
annualization; horizons; conditioning data; truth definition; benchmark set;
loss functions; revision policy; and promotion rule. “Origin 2010Q1” is not
enough—a forecaster cannot use 2010Q1 GDP before its release. If the quarterly
product instead runs before the advance release, the latest quarter is latent
and the state-estimation requirements increase.

### III.3 Four evidence stages

1. **Austrian replication (revised-data diagnostic).** Reconstruct the
   paper's rolling inputs and reproduce its tables/figures as closely as
   source availability permits. Maintain a discrepancy ledger for data
   revisions, software, seeds, origin indexing, and every unresolved result.
2. **U.S. paper analogue (revised-data diagnostic).** Run the same target
   panel, horizons, ensemble convention, and benchmark family on revised U.S.
   data. This tests transfer of the published design but is not a real-time
   forecast claim.
3. **U.S. pseudo-real-time competition (promotion evidence).** Use exact
   forecast timestamps, releases actually available then, origin-specific
   structural networks/counts/balance sheets, vintage-specific seasonal
   adjustments, and at least 40 eligible retrospective origins for the core
   h=1–4 comparison. Start as early as complete, auditable vintages permit;
   2007 onward is the target, not a promise. Include all regimes rather than
   removing the pandemic from headline results; prespecified regime slices
   are supplementary.
4. **Prospective shadow operation.** Freeze code, calibration rules, data
   queries, target definitions, and score rules; register forecasts before
   outcomes. Eight consecutive quarterly origins establish pipeline
   reliability, not statistical superiority. Continue accumulating evidence.

The current U.S. pipeline contains one annual structural row (2024), and its
valid calibration-quarter window is only recent. Historical annual structures
and release vintages must be built before stages 2–3 can run. Do not estimate
the effort as a simple parameterization of the existing object.

Planning target, conditional on the vintage-completeness audit: use
1997Q1–2006Q4 as the initial warm-up, quarterly origins from 2007Q1 onward,
an expanding estimation window as primary, and 40-/60-quarter rolling windows
as robustness checks. These dates are not promises; start at the earliest
origin for which every required block passes. Preserve longer all-available
samples for simpler benchmarks and add common balanced-sample tables.

For stage 2, a structural table with reference year no later than the origin
may be paired with revised quarterly history to mimic the paper; label this
**revised/mixed-vintage** because the release itself may not have been
available then. Stage 3 alone enforces actual structural and quarterly
`release_timestamp <= forecast_timestamp` eligibility.

### III.4 Bitemporal data and origin manifests

Create an immutable vintage warehouse covering FRED/ALFRED or Philadelphia Fed
[RTDSM](https://www.philadelphiafed.org/surveys-and-data/real-time-data-research/real-time-data-set-for-macroeconomists)
series plus archived BEA, BLS, Census, Federal Reserve Z.1, and other detailed
releases that those databases do not contain. Every observation requires:

- series/concept ID, source table/line, unit, frequency, seasonal-adjustment
  status, and transformation;
- reference period;
- release/publication timestamp and, where applicable, valid-from/valid-to
  interval;
- source release ID/version and URL or archival locator;
- retrieval timestamp, raw-file hash, parser version, and lineage to the
  calibrated field.

Minimum machine schema:

```text
series_id
reference_period_start
reference_period_end
value
release_timestamp
realtime_start
realtime_end
source_release_id
source_url_or_file
raw_sha256
retrieved_at
unit
frequency
seasonal_adjustment
annual_rate_flag
stock_flow_index_rate
price_basis
classification
classification_vintage
transformation_version
quality_status
```

Source hierarchy extends [README_US_CALIBRATION.md](README_US_CALIBRATION.md):

- ALFRED and RTDSM for covered real-time macro series and cross-checks;
- immutable BEA GDP/NIPA, input-output/supply-use, fixed-asset, and
  GDP-by-industry releases;
- BLS payroll, price, productivity, QCEW, and other revisable releases;
- Census business, trade, retail, construction, manufacturing, inventory, and
  classification releases;
- versioned Federal Reserve Financial Accounts and rate/financial-condition
  data;
- Treasury, Department of Labor, and other statutory/administrative releases
  needed by registered parameters;
- archived SPF, CBO, FOMC SEP, GDPNow, NY Fed, and licensed consensus forecasts
  with publication timestamps.

ALFRED validity intervals are not a substitute for the exact intraday release
time when the origin occurs on a release date.

The transformation library fails closed:

- quarterly SAAR level → divide by four only for a model-quarter flow;
- annual flow → allocate to quarters only under an explicit rule;
- published growth/rate → never divide merely because its underlying level is
  annualized;
- end-of-period stock → no flow conversion;
- current dollars → do not mix with chained components as if additive;
- chained components → use official contributions or chain indexes;
- people/jobs/establishments/enterprises → require a named bridge;
- percent/percentage points/basis points → distinct types;
- index/level/log/growth → store transformation with every target.

Every origin has a signed manifest listing the exact eligible rows and
structural artifacts. Enforce `release_timestamp <= forecast_timestamp` in
the query layer and tests. Corrections to a historically available release
create a new warehouse version; they never overwrite the record used for a
frozen forecast.

At each origin, use only annual I-O/supply-use, fixed-asset, firm-count, and
financial-account releases then available; carry the last eligible structure
forward, record its age, and test sensitivity to structural age. First audit
whether sufficiently detailed historical releases actually exist—availability
of a modern archive page does not prove every required vintage is complete.
The structural selector must:

1. find the most recent eligible I-O/supply-use release;
2. find eligible fixed-asset, firm-count, QCEW, sector-account, and
   classification releases;
3. build the structure from only those releases;
4. carry it forward only until the next eligible release;
5. record structural age and all mapping versions;
6. expose age/mapping sensitivity in every scorecard.

Score quarterly macro targets against:

- **first release**, representing what users first learned;
- **near-mature release**, defined by a fixed release number such as the third
  GDP estimate;
- **mature truth**, defined by a fixed lag or benchmark-vintage rule chosen in
  advance.

Report forecast error and later data-revision error separately. Revised-data
and mixed-vintage experiments must be labeled as such.

For a consistent sign convention:

```text
forecast - mature truth
  = (forecast - first release)
  + (first release - mature truth)
```

Store error under every truth definition, the subsequent revision,
predictable-revision diagnostics, provisional/final score status, and
sensitivity to annual/comprehensive NIPA revisions. Payroll truth preserves
initial, revised monthly, and annual benchmark-adjusted values; seasonally
adjusted price/labor series preserve vintage-specific seasonal factors.

### III.5 Targets and the observation operator

Before scoring, implement a versioned observation operator from model states
and flows to official concepts. For every target specify: source series,
nominal/real basis, deflator, seasonal adjustment, annualization, aggregation,
release/revision convention, model formula, bridge/residual if not directly
modeled, and unit tests on historical identities.

**Replication panel** (paper comparability):

- real GDP growth and GDP-deflator inflation;
- real household consumption and real fixed investment;
- government consumption, exports, imports, the model's legacy `ea` inputs,
  and the policy rate for the VAR panel.

Use the actual model inputs for a strict paper-port panel. A panel containing
true foreign GDP/inflation belongs to the production external-block variant
and is scored separately.

**Tier 1 U.S. operational panel:**

| Target | Primary score form | Secondary form |
|---|---|---|
| Real GDP | annualized q/q log growth | four-quarter growth |
| PCE price index | annualized q/q inflation | four-quarter inflation |
| Core PCE price index | annualized q/q inflation | four-quarter inflation |
| GDP deflator | annualized q/q inflation | four-quarter inflation |
| Unemployment | percent level | quarterly change |
| Payroll employment | log growth | revision to level |
| Effective federal funds rate | percentage-point level | change |
| Nominal GDP | annualized q/q growth | four-quarter growth |

If the ABM does not natively produce a target, validate the observation bridge
before including it in a model comparison. Keep raw-model and bridge-adjusted
scores separate.

**Tier 2 expenditure/income/financial panel:**

- real household consumption, with durable/nondurable/services detail where
  the observation bridge is defensible;
- residential investment and nonresidential structures, equipment, and
  intellectual property;
- inventories scored as official contribution to GDP growth;
- federal and state/local government purchases;
- exports, imports, and net-trade contributions;
- compensation, wages, corporate profits, nominal income, government balance,
  and interest expense;
- credit growth, spreads, defaults, losses, and lending/rationing indicators.

**Tier 3 structural-value panel:**

- quarterly sector GVA mapped to the official quarterly GDP-by-industry
  aggregation and annual 68-sector output/employment/network stress;
- firm entry/exit/default, concentration, debt, deposits, and investment;
- bank equity, losses, lending, and credit rationing;
- household liquid assets and unemployment transitions;
- fiscal/external balance sheets and joint tail paths;
- event probabilities such as negative GDP growth, a preregistered
  unemployment increase, recession, default/credit-loss stress, and supply
  bottlenecks.

Sector diagnostics include current-dollar-value-added-weighted MAE/RMSE,
cross-sectional rank correlation, sign accuracy, top/bottom-sector recall,
aggregate contribution error, dispersion, and network/no-network attribution.

Sector and event targets require competent baselines—sector AR, shrinkage
panel/factor, reconciled component forecasts, and distribution-derived event
probabilities. Structural detail is a potential advantage, not an exemption
from comparison. Never sum chained-dollar components; use official chain
indexes or contribution-to-growth methods.

### III.6 Origin-state estimation and predictive uncertainty

Appendix-C deterministic resetting is the **replication baseline**, not a
complete U.S. density state estimate. At each forecast origin, observed
aggregates do not reveal firm cash/debt, inventories, expectations, bank
exposures, worker assignments, or network microstates. For a production
quarterly forecast:

1. constrain/rake synthetic microstates to every eligible aggregate identity;
2. draw multiple admissible microstates conditional on those controls;
3. document which latent states are inherited, redrawn, filtered, or assumed;
4. compare this v1 ensemble with EnKF, particle, or simulation-based
   filtering when data and compute permit;
5. test initialization sensitivity with common aggregate controls.

The origin-state vector covers at least aggregate output/expenditure; sector
output, employment, orders, and inventories; household employment and
disposable income; firm cash, debt, investment, and expected demand; bank
balance sheet and credit conditions; fiscal purchases/transfers/revenue/debt;
policy stance; and foreign demand, trade, exchange rates, and import prices.

Compare an assimilation ladder:

- deterministic accounting benchmarking/raking;
- hybrid raking followed by an ensemble Kalman update;
- particle/iterated filtering for nonlinear and non-Gaussian states;
- simulation smoothing or likelihood-free/ABC alternatives where justified.

The first production quarterly forecast may use the hybrid method if it passes
state gates. At a ragged-edge origin, monthly/weekly releases update only the
states they measure; unreleased NIPA quantities remain latent; missing-data
steps preserve the release calendar; revisions create new vintage states
instead of overwriting history.

State gate: assimilated observables match eligible releases within explicit
measurement error; accounting survives the update; residuals are not
pathologically serial/cross-sectionally dependent; uncertainty expands under
missing/contradictory data; and no backcast innovation uses later releases.

A simulation ensemble conditional on one calibration and one origin state is
an **innovation-conditional interval**, not a predictive interval. Production
predictive distributions should progressively integrate:

- aggregate and agent innovations with estimated dependence;
- exogenous/dynamic-parameter uncertainty;
- synthetic microstate and origin-state uncertainty;
- measurement and data-revision uncertainty;
- structural-network-vintage uncertainty;
- model discrepancy, estimated strictly from completed training-origin
  errors or transparent forecast-combination/postprocessing rules.

The implementation order is:

```text
draw model variant / discrepancy
  draw structural calibration
    draw dynamic and optional behavioral parameters
      draw admissible origin state
        draw one coherent joint innovation path
```

Draws must remain coherent across variables and horizons. Raw ABM,
past-only-calibrated postprocessing, and combinations are separately versioned
products. For the paper replication use 500 paths. For production, use
adaptive batching until means, relevant quantiles, and scores meet
preregistered Monte Carlo error tolerances. Specifically monitor the forecast
mean, CRPS/WIS, 5th/10th/50th/90th/95th percentiles, rare-event probability,
and Monte Carlo uncertainty in reported score differences. Several hundred or
1,000–2,000 paths may be needed for some outputs, but path count is an output
of convergence diagnostics, not a ritual. Replace global `rand`/`randn` and
threaded draw-order dependence with
explicit origin × model × path RNG objects and stable substreams for aggregate
shocks, matching, entry/exit, and initialization. Common random numbers are
valid only for mechanisms whose draw alignment is preserved when variants
consume different numbers of random values. Use an unseen frozen seed family
for final scoring.

### III.7 Benchmark contract

Maintain two non-interchangeable tracks:

- **Common-information track:** identical origin manifest and eligible
  observables, with all hyperparameters selected inside each origin.
- **Published-forecast track:** archived SPF, CBO, FRBNY DSGE, and—for the
  nowcast product—GDPNow/NY Fed forecasts at matched publication timestamps.
  These measure operational competitiveness under different information sets.

Each benchmark needs frozen code, observables, transformations, estimation
window, hyperparameter rule, pandemic/ELB treatment, density construction,
fallback behavior, and convergence gate.

| Family | Required specifications |
|---|---|
| Naive | Random walk/no-change, with/without drift; historical-average growth; seasonal naive where relevant |
| Univariate AR | AR(1), AR(4), and AR(p) selected within-origin; direct and iterated multi-step variants; levels/growth specifications decided per target using training data |
| VAR | Paper-matched VAR(1–3) plus a stable production panel; no look-ahead lag selection |
| BVAR | Core and extended Minnesota/hierarchical variants; frozen priors and within-origin hyperparameter rule; posterior predictive distribution |
| Forecast combinations | Equal weight and rolling past-score weights, both with and without the ABM |
| Semi-structural | Compact gap/state-space model linking output gap, inflation, unemployment, and policy; an equilibrium-oriented low-cost challenger |
| DSGE | Canonical Smets–Wouters-style U.S. model and a frozen public implementation; distinguish a re-estimated common-data run from archived institutional forecasts |
| Professional | SPF median/distribution and CBO where timestamps and concepts match |
| Sector/event | Sector AR/shrinkage/factor models, reconciled components, and event probabilities induced by statistical/DSGE densities |
| Nowcast-only | Dynamic factor, bridge, MIDAS, and ragged-edge BVAR; these are mandatory before making a nowcast claim |
| Scenario | Conditional ARX/BVAR, semi-structural model, and [FRB/US](https://www.federalreserve.gov/econres/us-models-about.htm)-style responses where feasible |

Freeze these executable reference specifications:

- **Univariate:** AR(p), `p ∈ 1:8`, selected by BIC inside each origin; AR(1)
  and AR(4) fixed; direct and iterated forecasts; ARX with a frozen,
  origin-eligible predictor set; equal-weight univariate combination.
- **Core BVAR:** real GDP growth, PCE inflation, unemployment, and effective
  federal funds rate.
- **Extended BVAR:** core plus consumption/investment/wage growth, term and
  credit spreads, broad dollar, and trade-weighted foreign activity.
  Compare Minnesota and hierarchical shrinkage, expanding and 40/60-quarter
  rolling windows, and posterior predictive distributions; any direct
  multi-horizon variant is selected only within training data.
- **Short-horizon/mixed-frequency:** dynamic factor with EM/Kalman ragged-edge
  handling, FAVAR/FABVAR, MIDAS, mixed-frequency BVAR if maintainable, and a
  component GDP bridge reconciled to official accounting.
- **Smets–Wouters:** output, consumption, investment, hours, real wages,
  inflation, and short rate with frozen transforms, priors, estimation cadence,
  and ELB/pandemic treatment.
- **Compact semi-structural:** potential/output gap, natural unemployment and
  Okun relation, IS equation, Phillips curve, policy rule, fiscal block, and
  foreign-demand block in a transparent Bayesian/Kalman state-space system.
- **Published hurdle:** SPF mean/median/distributions, CBO, FOMC SEP at
  compatible annual horizons, and matched GDPNow/NY Fed releases. SEP is an
  appropriate-policy projection, and licensed consensus forecasts enter only
  if storage/publication rights permit.

The [New York Fed DSGE resources](https://www.newyorkfed.org/research/policy/dsge)
and [FRBNY DSGE Julia repositories](https://github.com/orgs/FRBNY-DSGE/repositories)
are useful implementation references. Freeze the exact model, observables,
priors, lower-bound/pandemic treatment, and software revision. Treat canonical
SW07, a public FRBNY implementation, and archived FRBNY forecasts as distinct
experiments. A 250,000-draw configuration may be retained for paper parity;
production backtests use warm starts and effective-sample-size/convergence
gates rather than an arbitrary fixed draw count.

### III.8 Validation harness and artifacts

Build `scripts/us/validation/` around a model-independent
`forecast(origin_manifest, horizons) -> forecast_artifact` interface:

1. Materialize and validate the signed exact-as-of origin manifest; reject any
   ineligible release timestamp or hash.
2. Select the latest eligible structural releases and classification maps.
3. Build/load the structural artifact and pass every accounting/provenance
   gate.
4. Estimate dynamic parameters from eligible history only.
5. Estimate the current latent state from eligible aggregate/ragged-edge data.
6. Select model hyperparameters through a nested past-only validation window.
7. Estimate any postprocessing/correction only from completed prior forecasts.
8. Generate calibration-diagnostic paths with their dedicated seed family.
9. Generate the raw ABM evaluation paths with an unseen seed family, freely
   for h=1,2,4,8,12 and without future re-anchoring.
10. Run every common-information benchmark on the identical manifest.
11. Save coherent paths (or sufficient reproducible state), points, quantiles,
    convergence diagnostics, Monte Carlo error, runtime, and failures.
12. Write and lock the append-only forecast registry **before** loading future
    truth.
13. Later append first/near-mature/mature truth and scores under a new
    immutable evaluation version; never rewrite the forecast.
14. Emit the forecast card and paper-style/production dashboards by target,
    horizon, regime, truth vintage, model variant, structural age, and
    balanced sample.

Test conclusions across multiple stored seed schedules. Retrospective bug fixes
create a new model version and scorecard while retaining the original.

Illustrative artifact separation:

```text
data/us/
  raw/<source>/<release_id>/...
  vintages/<series>/<as_of>/...
  curated/<transformation_version>/...
  concordances/<classification_version>/...

scripts/us/calibration/
  parameter_registry.toml
  concept_dictionary.toml
  build_structural.jl
  estimate_dynamic.jl
  estimate_behavioral.jl
  estimate_state.jl

scripts/us/forecasting/
  protocol.toml
  origins.csv
  run_origin.jl
  benchmarks/
  score.jl

data/us/artifacts/
  structural/<structural_vintage>/<commit>.jld2
  dynamic/<origin>/<spec>.jld2
  states/<origin>/<spec>.jld2
  corrections/<origin>/<spec>.jld2

outputs/us/forecast_registry/<forecast_id>/
  forecast_card.json
  raw_abm.parquet
  postprocessed_abm.parquet
  combinations.parquet
  benchmarks.parquet
  scores.parquet
```

Locations may follow repository conventions; immutable separation is
mandatory. Every forecast record contains:

```text
forecast_id
product_id
model_id
model_version
variant
origin_timestamp
origin_manifest_hash
information_vintage
structural_vintage
structural_age
target
target_operator_version
transformation
horizon
reference_period
simulation_or_quantile
value
unit
scale
conditioning_set
code_commit
environment_hash
parameter_artifact_hash
state_artifact_hash
seed_schedule_id
created_at
evaluation_version
truth_vintage
```

The forecast card states product purpose; code/environment; origin and source
hashes; structural date/age; parameter classes updated; posterior/parameter
summary; initialization/accounting results; scale evidence; uncertainty layers;
ensemble convergence; raw/postprocessed/combined products; benchmark versions;
conditioning assumptions; fallbacks; known limitations; approval; and current
score/truth status.

Run controlled ablations on preregistered origins:

1. structural/paper-port raw ABM;
2. production dynamic-estimation ABM;
3. past-only postprocessed/corrected ABM;
4. homogeneous/no-network counterfactual preserving aggregate controls;
5. simplified/fixed-expectations ABM;
6. deterministic mean-shock ABM;
7. full predictive-distribution ABM;
8. forecast combination containing the ABM;
9. otherwise identical combination excluding the ABM;
10. declared commodity-closure, external-block, origin-state, scale, and
    load-bearing-parameter variants.

An ablation must change one declared mechanism while keeping shared aggregates,
seeds, and information fixed. Otherwise it is not causal evidence about that
mechanism.

### III.9 Scores and forecast-comparison inference

**Point scores:** RMSE for paper parity; mean error with confidence interval;
MAE, MASE, median absolute error, relative MAE/RMSE against each champion,
direction/turning-point and event-classification accuracy, economically
weighted losses, and accounting residuals for production. MAPE is restricted
to strictly positive, economically meaningful levels and is never primary for
growth or rates.

**Density scores:** CRPS and weighted interval score as primary univariate
proper scores; 50/80/90/95% coverage plus width/sharpness; PIT/rank histograms,
serial-independence diagnostics, and calibration curves; Brier score and
reliability for events; energy and/or variogram score for the joint
GDP/inflation/unemployment/rate path. Log score requires a preregistered
finite-ensemble density estimator and tail safeguard.

Report all-available-origin and common balanced-origin samples, with the exact
origin count for every target/model/horizon. Do not pool heterogeneous
target–horizon coverage into a single “honesty” percentage.

For paired comparisons:

- report mean/median loss differences, relative skill, and confidence
  intervals—not only p-values;
- use horizon-appropriate HAC or block bootstrap for overlapping h-step
  errors and the Harvey–Leybourne–Newbold small-sample DM adjustment;
- use Giacomini–White conditional predictive-ability tests where sample size
  supports them;
- use Clark–West only for genuinely nested forecasts with the **same**
  information set—not for an oracle realized-path ARX comparison;
- use Mincer–Zarnowitz diagnostics only where origin counts provide adequate
  power;
- control the target × horizon × benchmark family with a preregistered
  model-confidence-set, false-discovery, or familywise procedure.

Sixteen origins can reproduce paper-style tables but do not support strong
formal superiority claims. Use block-bootstrap uncertainty and state
insufficient power plainly.

Forecast-calibration diagnostics also report Mincer–Zarnowitz intercept/slope,
recursive bias, variance ratio, score stability by origin, revision
sensitivity, simulation Monte Carlo error, interval calibration, and event
reliability. Where sample size is inadequate, display the diagnostic without
claiming a precise test.

### III.10 Regime, robustness, and attribution matrix

Predeclare score slices; never choose them after observing favorable results:

- NBER recession versus expansion (ex-post stratification only);
- global financial crisis;
- effective lower bound;
- pandemic;
- high versus normal PCE inflation under a frozen threshold;
- tightening versus easing under a frozen rate-change rule;
- high versus normal financial stress;
- large versus normal data-revision quarters;
- young versus old structural-network vintage.

Required robustness grid:

- expanding versus 40-/60-quarter rolling estimation;
- paper log-level versus growth/local-trend processes;
- observed/source-based versus zero-product-tax abstraction;
- explicit-inventory, balanced, and residual-import closures;
- alternative agent scales and productive-unit/firm-count concepts;
- external/foreign-demand specifications;
- Gaussian versus Student-t/bootstrap innovations;
- raw versus past-only postprocessed ABM;
- network versus controlled no-network;
- innovation-conditional versus full predictive uncertainty;
- first-release, near-mature, and mature truth;
- full sample and preregistered pre-/post-pandemic views.

Report dependence honestly. Robustness analysis does not permit selecting the
winning variant after opening the frozen evaluation sample; a changed variant
gets a new experiment ID.

### III.11 Conditional forecasts and nowcasts

Implement the paper's Appendix-D ARX expectation mode as a **replication
experiment**: reactivate and test
`estimate_with_predictors` ([estimate.jl:37](src/utils/estimate.jl:37)),
switch the relevant expectation equations only under a versioned flag, and
condition G/E/M on realized paths. Label the result “ex-post/oracle
conditional”; it cannot establish unconditional forecast superiority.

For an **ex-ante scenario**, accept only paths published or supplied at the
origin, version every assumption, preserve cross-variable consistency, and
compare with conditional statistical and structural challengers. Scenario
value is assessed through response plausibility, accounting coherence,
historical-event hindcasts, expert review, and decision usefulness—not by
pretending an assumed path was an unconditional forecast.

A **ragged-edge nowcast** is a separate later product. It requires monthly/
weekly release calendars, a mixed-frequency observation layer, state
assimilation, news decomposition, and dynamic-factor/bridge/MIDAS challengers.
The New York Fed describes a dynamic-factor/Kalman approach in its
[Staff Nowcast](https://www.newyorkfed.org/research/policy/nowcast), while the
Atlanta Fed documents factor, bridge, and BVAR components in
[GDPNow](https://www.atlantafed.org/research-and-data/data/gdpnow/explainer).
Do not market a quarterly reset as a nowcast.

### III.12 Preregistered promotion rules

Freeze numeric weights and economically meaningful non-inferiority margins
before the final retrospective run. Promotion requires all of the following:

1. **Scientific integrity:** zero unresolved leakage, identity, variant,
   parameter-status, numerical, or scale-convergence failures.
2. **Evidence volume:** at least 40 vintage-clean retrospective origins for
   the core h=1–4 panel; longer horizons report the maximum balanced sample and
   its power. Otherwise the result is research-only.
3. **Point competitiveness:** a target/horizon-weighted Tier-1 loss index is
   competitive with the strongest frozen common-information benchmark within
   preregistered, economically justified margins and uncertainty intervals;
   no critical target has a materially unexplained degradation hidden by the
   aggregate index.
4. **Density usefulness:** competitive CRPS/WIS and defensible
   target-by-horizon calibration/sharpness, with uncertainty around coverage.
   Innovation-conditional bands cannot satisfy a predictive-density gate.
5. **Robustness:** conclusions survive reasonable truth vintages, expanding
   versus rolling windows, regimes, scale, origin-state draws, and declared
   structural/model variants. Failures are visible, not averaged away.
6. **Incremental ABM value:** network/agent structure improves at least one
   preregistered sector, joint-tail, scenario, or combination objective
   against an appropriate baseline without unacceptable Tier-1 cost.
7. **Prospective reliability:** at least eight frozen quarterly shadow origins
   complete without material data, calibration, convergence, or registry
   failures. Predictive evidence continues accumulating and is reported
   separately.
8. **Governance:** independent validation signs off on the observation
   operator, vintage firewall, benchmark fairness, model-risk limits, and
   rollback procedure.

Matching the Austrian gain profile, beating every naive forecast, landing
within an arbitrary percentage of a DSGE, or achieving pooled nominal coverage
are not promotion rules. Raw ABM and any past-only bias-corrected or combined
forecast are scored and labeled separately.

**Honest-success clause.** If the ABM does not win aggregate point accuracy but
adds reproducible value for densities/tails, sector allocation, balance-sheet
risk, scenario analysis, or forecast combinations, deploy it only in that
specialized/challenger role. Publish paper-style tables and full negative
results regardless; a U.S. port is not validated by its architecture alone.

---

## Part IV — Program workstreams, gates, and sequencing

Effort ranges are planning estimates after scope confirmation, not commitments:
S ≈ 2–5 person-days, M ≈ 1–3 person-weeks, L ≈ 1–3 person-months. Historical
vintage acquisition and licensing can dominate engineering time.

### Phase 0 — Freeze the scientific and operational contract

#### WS-0A — Forecast and evaluation contract

**Effort/owner:** S; research lead with independent-validation sign-off.
**Dependencies:** none.

Tasks:

- decide the quarterly issue timestamp, timezone, release-calendar rule, and
  treatment of the latest latent/advance-estimate quarter;
- freeze unconditional, nowcast, scenario, and ex-post replication products;
- freeze target/operator versions, transformations, horizons, truth vintages,
  score families, balanced-sample rules, benchmark families, origin minimum,
  loss weights, non-inferiority margins, and promotion logic;
- define retrospective score freeze, exploratory-change, and prospective
  maintenance policies.

Deliverables:

- human-readable pre-analysis/forecast protocol;
- machine-readable `protocol.toml`;
- target/observation dictionary;
- origin and score schemas;
- promotion scorecard template.

Gate: model owner and independent validator sign the protocol; any material
post-freeze change creates a new experiment version.

#### WS-0B — Paper/code crosswalk and model-variant baseline

**Effort/owner:** S/M; model engineering lead plus independent replicator.
**Dependencies:** WS-0A for variant naming.

Tasks:

- commit the paper-equation/source crosswalk and supporting tests;
- distinguish printed-paper, author/upstream-compatible, current U.S. port, and
  corrected production candidates;
- resolve or label every Part-I difference, numerical safeguard, and scenario
  timing convention;
- create the model-variant manifest and change-class taxonomy.

Deliverables:

- hash-addressed crosswalk/evidence table;
- variant manifest schema and baseline manifests;
- discrepancy and unresolved-question register;
- regression/property tests for each resolved difference.

Gate: no blanket replication claim remains; every material difference has
evidence, owner, rationale, test, and explicit variant treatment.

#### WS-0C — Calibration firewall and artifact split

**Effort/owner:** M; calibration/platform engineering.
**Dependencies:** WS-0A/B.

Tasks:

- stop `apply_forecast_parameter_overrides!` from mutating raw baseline
  artifacts;
- implement separate structural, dynamic, behavioral, state, postprocessing,
  scenario, forecast, truth, and score artifacts;
- preserve original estimates and raw simulation outputs;
- relabel current h=1/current-vintage outlook outputs as engineering checks.

Deliverables:

- artifact interfaces and migrations;
- immutable hash/provenance tests;
- leakage/firewall test fixture;
- current-results language and deprecation note.

Gate: automated negative tests prove that future outcomes/revisions and prior
forecast errors cannot enter raw calibration or frozen forecasts; only an
explicit class-H artifact may use completed prior forecast errors.

### Phase 1 — Build the evidence-grade data foundation

#### WS-1A — Bitemporal warehouse and release calendar

**Effort/owner:** L; data engineering lead and source-domain owners.
**Dependencies:** WS-0A.

Tasks:

- ingest ALFRED/RTDSM and archive exact BEA, BLS, Census, Federal Reserve,
  Treasury, DOL, and other eligible releases;
- archive annual I-O/supply-use, fixed-assets, GDP-by-industry, SUSB, QCEW,
  Z.1, classifications, and institutional forecasts;
- implement §III.4 timestamps, validity intervals, hashes, typed units,
  transformation versions, and as-of joins;
- build a release calendar and completeness dashboard;
- implement immutable raw storage and automated look-ahead tests.

Deliverables:

- bitemporal observation store;
- source-release registry and archival locator;
- release calendar and vintage-completeness dashboard;
- transformation library;
- origin-manifest builder and leakage test suite.

Gate: sampled GFC, ELB, pandemic, inflation, and current origins are exactly
reconstructible without post-origin releases; every missing block has a signed
substitute, narrowed-scope, or cannot-run decision.

#### WS-1B — Historical structural-input catalog

**Effort/owner:** L; national-accounts/data team.
**Dependencies:** WS-1A; may begin with discovery in parallel.

Tasks:

- acquire/reconstruct origin-eligible I-O/supply-use, fixed-asset, firm-count,
  labor, wage, fiscal, trade, tax, inventory, and financial-account inputs;
- preserve classification and concept changes instead of forcing modern codes
  backward silently;
- generate annual structural source packages and record structural age;
- audit proposed 1997 warm-up/2007-origin coverage before committing dates.

Deliverables:

- historical source/concordance catalog;
- structural-release eligibility matrix;
- classification bridge/version register;
- pilot origin packages and missing-data remediation plan.

Gate: a diverse pilot set passes provenance and concept checks before mass
backfill. The primary sample eventually has at least 40 eligible h=1–4 origins
or remains explicitly non-promotable.

#### WS-1C — Austrian replication feasibility

**Effort/owner:** M/L; replication lead; parallel with WS-1A/B.
**Dependencies:** WS-0A/B.

Tasks:

- locate, license, or reconstruct rolling 2010–2013 Austrian source/calibration
  inputs and exact origin convention;
- distinguish the frozen 2010Q1 object from a rolling-origin dataset;
- establish executable comparison against tables/figures and reference code;
- create a data/software/seed/origin discrepancy ledger.

Deliverables:

- feasibility decision;
- source/data license manifest;
- Austrian origin packages or documented partial-replication scope;
- replication report and discrepancy ledger when feasible.

Gate: numerical claims about reproducing the paper use only a reproducible
rolling dataset. Failure to obtain it limits the replication claim but does
not automatically block an independently valid U.S. evaluation.

### Phase 2 — Correct and validate U.S. calibration

#### WS-2A — Known code correctness and hermetic tests

**Effort/owner:** S/M; core model engineering.
**Dependencies:** WS-0B.

Tasks:

- fix and test the undotted vector `min`;
- guard growth-rate/log-level AR wiring;
- test innovation centering, RNG substreams, scenario shock timing, and
  productivity-floor binding;
- split hermetic and remote-fixture test suites;
- preserve upstream-compatible variants where attribution requires them.

Deliverables:

- code fixes and regression/property fixtures;
- hermetic CI suite plus separately scheduled/cached network integration suite;
- frozen-origin impact report;
- upstream issue/PR candidates where appropriate.

Gate: tests pass, behavioral differences are attributable, and no historical
score is silently rewritten after a defect fix.

#### WS-2B — Parameter registry and concept audit

**Effort/owner:** M; calibration lead plus domain reviewers.
**Dependencies:** WS-0C and source discovery.

Tasks:

- populate all A–H registry fields and assumption register;
- resolve the 17 `DUBIOUS` fields;
- name all hard-coded, numerical, synthetic-count, and bridge assumptions;
- define update cadence, product eligibility, owner/validator, uncertainty,
  tests, and review triggers.

Deliverables:

- `parameter_registry.toml`;
- concept dictionary and assumption register;
- updated data checklist;
- parameter provenance and unresolved-latent report.

Gate: 100% parameter coverage; no anonymous override or value without status,
source/identity, uncertainty treatment, and owner.

#### WS-2C — Commodity/industry accounting and tax variants

**Effort/owner:** L; national-accounts/calibration engineering.
**Dependencies:** WS-1B and WS-2B.

Tasks:

- resolve industry-output/commodity-use basis through the make/supply mapping;
- implement the valuation/residual/inventory ledger;
- build observed-tax and explicit zero-tax variants;
- compare explicit-inventory, confidence-weighted balance, and residual-import
  closures;
- add U.S. per-identity/per-period accounting tests without cancellation.

Deliverables:

- versioned structural builder;
- raw/bridged/balanced matrix archive;
- reconciliation/adjustment report;
- inventory and tax decision records;
- controlled 1/4/12-quarter transition report.

Gate: source-aware identity tolerances, traceability, sign/zero preservation,
tax treatment, and dynamic-transition gates pass.

#### WS-2D — Productive units, demand, fiscal, and balance-sheet repair

**Effort/owner:** L; calibration team with labor/financial-account specialists.
**Dependencies:** WS-2B/C.

Tasks:

- implement productive-unit/labor bridges and constrained integerization;
- rebuild residential final-demand composition;
- validate technology, depreciation, wage, propensity, UI, tax, debt, interest,
  and instrument concepts;
- reconcile counterparties and opening sector net worth;
- document J/L matching granularity and every binding numerical repair.

Deliverables:

- crosswalk package;
- U.S. technology/final-demand/fiscal parameter report;
- Z.1 instrument bridge and balance-sheet reconciliation;
- micro-initialization builder and distributional diagnostics.

Gate: Part-II steps 4–8 pass, including reproducible aggregate controls,
interest/stock compatibility, admissible micro balance sheets, and
initialization stability under adaptive seed testing.

#### WS-2E — External, monetary, trend, and innovation processes

**Effort/owner:** L; macroeconometrics lead.
**Dependencies:** WS-1A, WS-2B/C.

Tasks:

- implement and compare legacy versus separated foreign/domestic blocks;
- define Taylor-rule target/arguments/intercept and ELB/pandemic treatment;
- compare paper log-level, growth, local-trend, ARX, and cointegrated
  candidates with nested training-only selection;
- estimate shrunk PSD joint covariance and Gaussian/heavy-tail alternatives;
- validate residual and regime stability.

Deliverables:

- dynamic-estimation package;
- specification cards and training-validation results;
- innovation-law artifact;
- frozen replication and production dynamic variants.

Gate: interpretations, stability, residuals, leakage, and convergence pass
before the final evaluation sample is opened.

#### WS-2F — Observation operator and origin-state layer

**Effort/owner:** L; state-estimation and data team.
**Dependencies:** WS-1A/B and WS-2C/D/E.

Tasks:

- implement every Tier-1/Tier-2/Tier-3 observation bridge;
- implement accounting-raked synthetic microstate draws;
- prototype hybrid EnKF/particle alternatives;
- support ragged-edge update semantics for the later nowcast product;
- quantify state, measurement, and revision uncertainty.

Deliverables:

- observation-operator library and identity fixtures;
- origin-state builder;
- state/filter diagnostics;
- initialization/state sensitivity report.

Gate: official concepts/units reconcile; no unreleased value enters state;
accounting survives assimilation; uncertainty reacts appropriately; intervals
are labeled innovation-conditional until the production uncertainty stack
passes.

#### WS-2G — Scale convergence and global sensitivity

**Effort/owner:** L; computational modeling lead; parallel after WS-2C/D.
**Dependencies:** stable initialization and accounting.

Tasks:

- run the scale ladder with aligned substreams and aggregate controls;
- measure aggregate, distributional, matching, network, default, credit, tail,
  runtime, and memory statistics;
- screen all assumptions/dynamic parameters and interactions;
- choose scale, weighted-agent correction, or restricted-claim set.

Deliverables:

- scale-convergence report;
- sensitivity/interaction atlas;
- production-scale decision and validation version;
- compute budget and adaptive batching policy.

Gate: §II.6 passes, or each production claim is limited to outputs demonstrated
scale-invariant.

#### WS-2H — Optional behavioral-calibration challenger

**Effort/owner:** L; behavioral calibration lead with independent validator.
**Dependencies:** frozen no-fitting baseline, WS-2G, and identified moment data.

Tasks:

- execute §II.8 sensitivity, identification, SMM/search, held-out-moment, and
  independent-seed protocol;
- estimate parameter/profile/posterior uncertainty;
- preserve the Pareto frontier and report failed identification.

Deliverables:

- behavioral variant package;
- identification/sensitivity report;
- held-out moment scorecard;
- posterior/profile artifacts.

Gate: every fitted parameter is identified by declared training moments and
stable under seeds/subperiods. This challenger remains distinct from the paper
replication and never uses final forecast errors.

### Phase 3 — Build benchmarks and the immutable evaluation system

#### WS-3A — Forecast registry and origin runner

**Effort/owner:** L; forecasting platform lead.
**Dependencies:** WS-0A/C and WS-1A.

Tasks:

- implement the 14-step §III.8 origin algorithm;
- implement append-only forecasts/truth/evaluations, forecast cards, balanced
  samples, coherent path/quantile storage, retries, and compute telemetry;
- implement origin/model/path RNG substreams and multiple seed schedules;
- enforce target/operator, environment, manifest, and artifact hashes.

Deliverables:

- reusable forecast interface and origin runner;
- immutable registry;
- forecast-card generator;
- restart/partial-failure tooling;
- synthetic end-to-end fixtures.

Gate: fixtures demonstrate zero leakage, exact reproducibility, correct
horizons/vintages/revisions, registry lock before truth, and safe recovery.

#### WS-3B — Statistical, factor, sector, and semi-structural benchmarks

**Effort/owner:** L; econometrics/benchmark team; parallel with calibration.
**Dependencies:** WS-0A and WS-1A; interface from WS-3A.

Tasks:

- implement naive, AR/ARX, VAR/BVAR, combinations, sector/event, DFM/FAVAR,
  bridge/MIDAS, and compact semi-structural specifications in §III.7;
- freeze within-origin hyperparameter selection and posterior-predictive rules;
- validate or replace existing helpers.

The current [varx.jl](src/utils/varx.jl),
[dmtest.jl](src/utils/dmtest.jl),
[mztest.jl](src/utils/mztest.jl), and
[bias_ttest.jl](src/utils/bias_ttest.jl) require checks for double sample-size
scaling, missing HAC/Bartlett treatment, iid/inverse-based MZ inference,
off-diagonal VAR innovation covariance, and intercept/exogenous-column
handling.

Deliverables:

- benchmark library and frozen model cards;
- textbook/simulation/reference fixtures;
- posterior-density and combination modules;
- benchmark failure/convergence reporting.

Gate: known cases reproduce; identical origin manifests and target transforms
are enforced; failed estimates remain visible.

#### WS-3C — DSGE and institutional benchmark track

**Effort/owner:** L; structural macroeconomics lead.
**Dependencies:** WS-3A interface; may run in parallel.

Tasks:

- freeze/validate U.S. SW-style and selected public FRBNY implementation,
  priors, transforms, cadence, ELB/pandemic treatment, and convergence;
- integrate archived FRBNY/SPF/CBO/SEP/nowcast forecasts as a separate
  publication-information track;
- implement FRB/US interfaces primarily for standardized scenario comparison.

Deliverables:

- common-data DSGE model card/package;
- posterior/convergence fixtures;
- institutional forecast archive and concept/timestamp mapping;
- scenario-benchmark interface.

Gate: known-sample/posterior checks pass; nonconverged origins are reported;
published and common-information experiments never share a ranking.

#### WS-3D — Scoring, inference, robustness, and reporting

**Effort/owner:** M/L; forecast-evaluation lead independent of model tuning.
**Dependencies:** WS-3A and benchmark interfaces.

Tasks:

- implement §III.9 point/density/joint/event/revision scores and Monte Carlo
  error;
- implement valid HAC/block-bootstrap/HLN-DM/GW/CW/MZ and multiple-comparison
  procedures with power warnings;
- implement §III.10 regime/robustness tables and ablation registry;
- generate paper-style and production/model-risk reports.

Deliverables:

- score database/engine;
- inference and calibration fixtures;
- revision/regime/robustness dashboards;
- report generator with lineage to immutable records.

Gate: simulations recover known ranking/calibration properties; every table and
figure traces to forecast, truth, score, and evaluation-version hashes.

### Phase 4 — Run evidence stages in increasing cost

#### WS-4A — Vintage-clean pilot

**Effort/owner:** M plus compute; integrated team.
**Dependencies:** minimum viable WS-1–3 stack.

Run 4–8 widely separated origins with smoke-size adaptive ensembles. Diagnose
accounting, state, transformations, horizons, registry, runtime, and benchmark
failures before mass backfill. Deliver a go/no-go report and prioritized
remediation backlog. Gate: no systemic leakage/accounting/state/harness defect
remains.

#### WS-4B — Austrian and revised-data U.S. diagnostics

**Effort/owner:** M/L; replication/evaluation leads.
**Dependencies:** WS-1C and stable harness.

Run the Austrian replication to the feasible scope and publish the discrepancy
ledger. Run the U.S. paper-analogue tables on revised/mixed-vintage data,
clearly labeled. Deliver paper-style tables/figures, crosswalk, and
implementation diagnostics. Gate: claims match available evidence; these
experiments never substitute for promotion evidence.

#### WS-4C — Full pseudo-real-time competition

**Effort/owner:** L plus compute; evaluation lead controls score opening.
**Dependencies:** all production gates in WS-1–3.

Freeze code/rules, run all eligible origins and unseen seeds, lock registry
before truth, then score raw/postprocessed/combined variants and benchmarks.
Run preregistered ablations, revisions, regimes, scale, and uncertainty.

Deliverables:

- locked forecast registry and score database;
- reproducible research report;
- independent model-validation report;
- model-risk findings and remediation backlog.

Gate: at least 40 vintage-clean h=1–4 origins or explicit insufficiency; every
promotion rule is reported pass/fail, with no selective omission.

#### WS-4D — Conditional/scenario product

**Effort/owner:** M/L; scenario/modeling lead.
**Dependencies:** stable quarterly baseline and WS-3 benchmark interfaces.

Implement Appendix-D replication, ex-ante versioned scenario conditioning,
consistency checks, CBO/user interfaces, and FRB/US/semi-structural/statistical
scenario challengers. Deliver scenario schema, response validation, and
scenario cards. Gate: conditioning assumptions are explicit and scenario
results cannot enter unconditional scores.

#### WS-4E — Ragged-edge nowcast product

**Effort/owner:** L; nowcast/state/data team.
**Dependencies:** stable quarterly system, WS-1A, WS-2F, and mixed-frequency
benchmarks.

Implement fixed monthly/weekly cutoffs, state/news assimilation, DFM/bridge/
MIDAS/mixed-frequency challengers, matched institutional archives, and h=0/1
scorecards. Deliver nowcast protocol, release-calendar tests, news
decomposition, and registry. Gate: no unreleased quarterly value enters state
and all models receive the declared information set.

### Phase 5 — Production governance

#### WS-5A — Prospective shadow forecasting

**Effort/owner:** at least eight quarters elapsed; operations owner with model
owner and release approver each cycle.
**Dependencies:** WS-4C and frozen protocol.

Tasks: register before outcomes, monitor data/model/compute failures, append
truth without rewriting, allow only preapproved maintenance, and measure
latency/reproducibility. Deliver prospective registry, quarterly cards,
scorecard, incident/change log, and operational metrics. Gate: at least eight
successful origins demonstrate reliability; predictive evidence remains
separate and continues accumulating.

#### WS-5B — Production deployment and model-risk governance

**Effort/owner:** M/L plus ongoing; operations/model-risk leads.
**Dependencies:** retrospective decision and shadow reliability.

Assign named model, data, operations, independent-validation, and release
approval roles. Establish:

- annual structural, quarterly dynamic, and each-origin state cadences;
- environment locks and raw/calibration/forecast/truth retention;
- data lateness/revision, accounting, drift, convergence, scale, and
  performance alarms;
- outage fallbacks and release-suppression rules;
- change classes with mandatory tests/backtest scope;
- champion/challenger promotion/demotion;
- rollback/kill switch, incident log, retrospective-correction policy, and
  notices;
- periodic model-risk review and forecast-card approval.

Deliverables: production runbook, service-level objectives, fallback forecast,
rollback procedure, monitoring dashboard, approval checklist, and user-facing
methodology/uncertainty documentation.

Gate: both scientific promotion and operational reproducibility pass. A
specialized/challenger deployment is allowed only with its narrower role stated.

### First implementation sprint

After WS-0 scope freeze, execute in this order:

1. create the A–H parameter registry and concept dictionary;
2. remove forecast overrides from structural baseline construction;
3. split structural/dynamic/state/postprocessing artifacts;
4. publish the 71-source/68-modeled dimension and price-basis contract;
5. add U.S. per-period accounting tests and reproduce the opening GDP residual;
6. fix the vector minima, RNG discipline, growth-rate guard, and remote test
   separation;
7. create the machine-readable origin/target/score protocol;
8. implement bitemporal as-of joins and leakage fixtures;
9. integrate naive/AR and a validated VAR interface into the registry;
10. build the first BVAR and vintage-clean origin pilot;
11. resolve industry/commodity basis before tax/inventory balancing;
12. build residential-investment product shares;
13. implement the paper's ARX conditional expectations;
14. split domestic policy variables from foreign activity;
15. run an initial scale ladder and compute profile.

### Decision log

The named owner and independent validator sign each item before its dependent
scored work begins:

1. Quarterly forecast timestamp and handling of the latest latent/advance GDP
   quarter.
2. Firm and household scaling semantics; production scale.
3. Industry/commodity basis, valuation bridge, inventory classification, and
   closure variant.
4. Product, export, investment, and final-use tax treatment.
5. J/L interpretation and matching-granularity rule.
6. UI-benefit and banking-constraint concepts/ranges.
7. Domestic-policy versus foreign-block specification; exchange-rate/global
   channels.
8. Trend/exogenous-process family, Taylor-rule inflation/intercept/ELB and
   pandemic treatment.
9. Origin-state method and minimum predictive-uncertainty stack.
10. Tier-1 observation bridges, truth vintages, windows, losses, weights, and
    non-inferiority margins.
11. Permissible postprocessing/forecast combinations and product labels.
12. DSGE/semi-structural implementation and convergence requirements.

Every record includes owner, validator, date, rationale, alternatives,
expected economic/score/compute effect, dependent artifacts, review trigger,
and approval status.

### Critical dependencies and principal risks

The critical path is:

`forecast contract → vintage warehouse → historical structures → accounting/
observation/state gates → pilot → frozen full evaluation → independent
validation → shadow operation`.

Benchmarks, Austrian-data feasibility, and code-level defect fixes can run in
parallel once their interfaces are frozen.

```text
WS-0 contract/variants/firewall
  ├── WS-1A vintage warehouse ──> WS-1B historical structures
  ├── WS-1C Austrian feasibility
  └── WS-2A code correctness

WS-1B + WS-2B registry ──> WS-2C accounting/tax
  ──> WS-2D units/balance sheets ──> WS-2F state
  └──> WS-2E dynamics

WS-2C/D ──> WS-2G scale ──> optional WS-2H behavior
WS-1A + WS-3A interface ──> WS-3B/C benchmarks ──> WS-3D scoring

WS-1–3 gates ──> WS-4 pilot/full evidence ──> WS-5 shadow/governance
```

| Risk | Consequence | Required mitigation |
|---|---|---|
| Historical structural vintages incomplete | short or mixed-vintage sample | audit before dates; transparent carry-forward; withhold promotion if origin gate fails |
| Revised/structural leakage | artificial accuracy | bitemporal store, signed manifests, negative leakage tests |
| Mixed industry/commodity or price basis | false residual and distorted balancing | make/supply transformation first; typed valuation ledger |
| Product-tax/inventory inconsistency | broken GDP/government dynamics | explicit variants, full adjustment/residual ledger |
| People/jobs/firms mismatch | wrong productivity and matching | concept dictionary, bridge tables, uncertainty and alternatives |
| Current-price/chained-dollar confusion | invalid aggregation/growth | typed units, official contributions, observation tests |
| Weak behavioral identification | overfit/unstable mechanisms | sensitivity, held-out moments, priors, simpler variants |
| Scale dependence | mechanisms change with resolution | scale ladder, weighted-agent/rule correction, restricted claims |
| U.S. activity reused as foreign block | wrong trade/policy propagation | split domestic, foreign, dollar, prices, finance variables |
| Postprocessing absorbs model error | gains falsely attributed to agents/network | raw/postprocessed separation and ablations |
| Simulation noise/RNG drift | unstable estimates and comparisons | stable substreams, adaptive batching, independent seeds, MC error |
| Runtime at converged scale | incomplete competition | pilot profiling, distributed origins, adaptive ensembles, compute budget |
| Weak/asymmetric benchmark | ABM flattered | validated model cards, identical manifests, independent benchmark owner |
| Thin/overlapping origin sample | unreliable ranks/tests | balanced counts, block uncertainty, power statements, prospective evidence |
| Pandemic/regime/revision dominance | nonportable average result | preregistered regime/truth/window matrix |
| Remote fixtures fail | CI/reproduction instability | cached/versioned artifacts; hermetic and network suites |
| State/parameter uncertainty expensive | misleading narrow bands | stage and label layers; no density promotion until complete |
| Post-score model changes | researcher degrees of freedom | score freeze; new version/experiment for every material change |

---

## Part V — Promotion, governance, and definition of done

This file is the single canonical development plan. It preserves a
no-behavioral-forecast-fitting replication baseline while allowing separately
labeled SMM, postprocessing, combination, and scenario variants under frozen,
past-only rules.

The project is complete only when the promotion gates—not merely the
implementation checklist—are satisfied. A partial Austrian replication, a
current-vintage U.S. baseline, or visually plausible simulations are research
milestones, not a production forecasting claim.

An independent analyst must be able to:

1. choose any supported historical forecast origin;
2. reconstruct every source release then available;
3. rebuild the structural parameter artifact and all mappings;
4. reproduce dynamic estimates and the origin-state distribution;
5. rerun the raw ABM with recorded environment and seeds;
6. rerun every primary challenger on the same origin manifest;
7. recover the immutable forecast locked before outcomes;
8. score it against first, near-mature, and mature truth;
9. reproduce uncertainty, revision, regime, robustness, and ablation tables;
10. explain every material parameter, assumption, correction, and difference
    from Poledna et al.

Until all supported steps pass, describe the system as a calibrated research
and scenario platform under development, not a validated production forecaster.

---

## Appendix — Audit traceability and current limitations

Evidence reviewed for this revision:

- the rendered Poledna et al. paper, including model equations, calibration,
  initialization, benchmark, and conditional-forecast sections;
- repository source at commit `6030f75`, with file/line evidence recorded in
  Part I;
- the shipped `US_2024Q4_structural.jld2` artifact, including its scale,
  dimensions, agent counts, and signed commodity discrepancies;
- current U.S. and Austrian baseline loaders, historical-quarter feasibility,
  forecast calibration, and validation utilities;
- a repository test run that reached 660 passing assertions but did not
  complete cleanly because a live Zenodo fixture timed out. Split hermetic
  unit/integration tests from network fixture tests before treating the suite
  as a stable software gate. In any case, tests are not economic or forecast
  validation.

Known audit limits:

- no committed machine-readable paper-equation/source crosswalk yet exists;
- the original MATLAB and complete author forecast artifacts were not
  available as authoritative ground truth for every paper–code difference;
- the repository does not contain the full rolling Austrian 2010–2013 or U.S.
  historical structural-vintage calibration set;
- several dynamic-causality statements—especially commodity residuals versus
  forecast decline—remain hypotheses requiring controlled ablations;
- external regulations, data availability, and benchmark software must be
  versioned at implementation time.

The first Phase-0 deliverable converts this narrative audit into a committed,
hash-addressed evidence table with columns for paper location, code location,
classification, test, variant decision, owner, and resolution. Until then,
Part I is a careful source review, not a completeness certificate.

---

## Primary references and implementation sources

- [Poledna et al., *Economic Forecasting with an Agent-Based
  Model*](<../Contents/papers/Poledna et al. - 2020 - Economic Forecasting with an Agent-Based Model.pdf>),
  especially PDF pages 5–10, 33–43, and 55–63.
- [Smets and Wouters (2007), “Shocks and Frictions in US Business
  Cycles”](https://www.aeaweb.org/articles?id=10.1257/aer.97.3.586).
- [ALFRED/FRED real-time periods](https://fred.stlouisfed.org/docs/api/fred/realtime_period.html).
- [Philadelphia Fed Real-Time Data Set for
  Macroeconomists](https://www.philadelphiafed.org/surveys-and-data/real-time-data-research/real-time-data-set-for-macroeconomists).
- [BEA GDP](https://www.bea.gov/data/gdp/gross-domestic-product),
  [Input-Output Accounts](https://www.bea.gov/data/industries/input-output-accounts-data),
  and [GDP by Industry](https://www.bea.gov/data/gdp/gdp-industry).
- [Federal Reserve Financial Accounts
  guide](https://www.federalreserve.gov/apps/fof/About.htm).
- [New York Fed DSGE model and forecast
  archive](https://www.newyorkfed.org/research/policy/dsge) and
  [FRBNY DSGE Julia repositories](https://github.com/orgs/FRBNY-DSGE/repositories).
- [Federal Reserve Board FRB/US
  model](https://www.federalreserve.gov/econres/us-models-about.htm).
- [Atlanta Fed GDPNow
  methodology](https://www.atlantafed.org/research-and-data/data/gdpnow/explainer)
  and [New York Fed Staff
  Nowcast](https://www.newyorkfed.org/research/policy/nowcast).
- [Philadelphia Fed Survey of Professional Forecasters
  data](https://www.philadelphiafed.org/surveys-and-data/data-files).
- [Gneiting and Raftery (2007), proper scoring
  rules](https://doi.org/10.1198/016214506000001437).
