# Out-of-Sample Forecast Performance of an Agent-Based Macroeconomic Model of the United States

### A stage-2 revised-data, mixed-vintage diagnostic: locating a structural defect, repairing it on accounting grounds, and re-scoring

**2026-08-10.** Branch `codex/us-forecasting`, HEAD `107a9ef`.

---

## 1. Executive summary

This report documents a complete cycle: an agent-based model was scored against ten statistical
benchmarks, found to carry a large and systematic real-growth bias, diagnosed to two specific
defects by matched-seed experiment, repaired by restoring an accounting identity and correcting a
mis-specified estimator — neither repair *selected* using forecast errors — and then
re-scored on identical cells with identical seeds. The exercise remains explicitly mixed-vintage:
2024 structure and current-vintage data are used at historical origins, which is information those
origins did not have. **That arc is the result.** The rank improvement
is a consequence of it, not the object of it.

**Verdict.** On a matched grid of 61 quarterly origins (2010Q2–2025Q2), five horizons and 500 paths
per origin, the repaired model (`beforeit_abm_us_v2`) attains the **best weighted RMSE ratio of the
14 scored forecast columns on the headline pair {real GDP growth, GDP-deflator inflation} in all three sample
tracks**: 0.830 all-available, 0.829 balanced-h12, 0.796 pandemic-masked, against a VAR(1) anchor.
The pre-repair model (`v1`) scored 0.905, 0.894 and 1.272 — 5th, 5th and 11th of the 14 columns. On the secondary
pair {nominal GDP growth, effective federal funds rate}, v2 is 1st all-available (0.716) and 1st
balanced-h12 (0.703), and **2nd pandemic-masked (0.739), behind AR(4) at 0.719** — a loss, reported
as such.

**What "14 columns" means.** The field is 14 *forecast columns*, not 14 independent
models: ten benchmark models (VAR, BVAR, AR variants and naive rules) plus four ABM
ensemble columns — mean and median, for each of two runs (v1 and v2). The two ABM
runs share a seed stream and differ only in the calibration artifact, so the four
ABM columns are not independent of one another. Ranks below are positions among
these 14 scored columns.

**The defect that was found.** v1 under-forecast real GDP growth by −1.3 to −2.9 pp at every horizon,
and by −7.3 pp at h=2. The cause was not tuning. The shipped calibration artifact's opening commodity
balance **does not clear sector by sector**: modelled uses differ from supply by −70.6 % to +47.6 %,
with 42 of 68 commodities over-demanded and 34 off by more than 10 %. This collides with a firm
capacity envelope frozen for all time at `K_i·κ_i = Y_i/0.85`, because investment is replacement-only
(`K_end/K_1 = 1.0000`, measured). Over-demanded sectors sit permanently against their ceiling,
under-demanded ones permanently idle, and `min()` is one-sided so the idle capacity never compensates.
Consequence: **12.9–14.4 % of gross output produced under a binding ceiling every quarter (measured range across origins)**, exports
filling only 87 % of demand, and real growth pinned near zero. This mechanism accounts for **76 %** of
the −2.75 pp bias. The remaining **24 %** is a growth expectation estimated by OLS AR(1) on the **log
level** of an I(1)-with-drift series, which delivers only 32–63 % of the in-sample trend — a
closed-form small-sample artifact, reproduced to 0.05 pp by `γ_e ≈ g·[1 − (1−α̂)T/2]`.

**The repair.** Two changes, both in the calibration artifact rather than in behavioural parameters.
(i) Biproportional (RAS) reconciliation of the **use side only**, holding measured BEA industry output
and T262 imports as row controls — `use_explicit_trade` stays `true`, no measured import level is
discarded — and holding all 72 user budgets as column controls; the balance then clears to
`max|uses/supply − 1| = 1.0e-13`. One accounting choice is required and is stated explicitly: the
artifact's 1.0104 % aggregate excess of uses over supply decomposes exactly into its own
production/expenditure statistical discrepancy plus negative net non-dwelling investment, and v2
anchors on the production account by scaling the four final-demand aggregates by
**λ = 0.983460**, a value fixed by the identity alone. (ii) Growth expectations become a random walk
with drift, flag-gated and default-off, so Austria and Italy remain bit-identical.

**What the repair bought, measured.** Real-GDP bias by horizon collapses from
−1.32 / −7.28 / −2.94 / −2.15 / −2.02 pp to **−0.03 / −0.10 / −0.14 / −0.12 / −0.20 pp**. The weighted
MAE ratio moves from 1.137 to **0.814**, resolving v1's loss-function asymmetry rather than trading it
away. Empirical 90 % interval coverage for real GDP moves from 0.654 to **0.929** against a nominal
0.90. And the GDP deflator is **unchanged** — at h=1 the two columns are bit-identical — which is the
signature the diagnosis predicted: this was a real quantity-rationing defect, never a pricing defect.

**Two results that reverse the draft's earlier readings, and are worth stating plainly.** First, v1's
competitive headline rank *depended on the COVID cells*: masking 2020Q1–2021Q4 sent v1 from 5th to
11th. v2 does not have that dependence — it ranks **1st in the masked sample too, and by its widest
margin** (0.796 versus 0.848 for the best statistical model). The regime sensitivity was a symptom of
the defect, not a property of the design. Second, the h=2 bias of −7.3 pp was attributed to the
opening-row measurement basis; it is now clear that the measurement basis explains only a small part
of it. The bulk was the rationing crash, and it disappears when the balance clears
(−7.28 → −0.10 pp) without any change to the opening-row treatment.

**Two open defects, which limit what any v2 number means.** They are measured, not speculative, and
must travel with every quotation.

1. **Capital never accumulates.** All of v2's growth drains the fixed 17.6 % opening capacity
   headroom; utilisation moves 0.856 → 0.943 over six years and `K24/K0 = 1.0000`. Inside the
   12-quarter scoring window this is a genuine improvement. Beyond roughly eight to ten years v2 must
   stall. **v2 is validated at h ≤ 12 only and is not a multi-year growth mechanism.**
2. **Unemployment collapses to about 1 %** once goods rationing stops — the labour block over-heats.
   `unemployment_rate` is excluded from every weighted score, and it got *worse* in v2 (bias −4.73 pp
   at h=12, coverage 0.216). This is reported as a failing gate on the merits, not hidden.

**What this does not establish.** This is a **revised-data, mixed-vintage diagnostic**. Data are
current-vintage throughout, and the 68×68 input–output structure, firm and employee counts, tax rates
and population are frozen at 2024 and carried backwards to every historical origin.
`real_time = false`, `origin_admissible = false`, `promotion_eligible = false`. No DSGE benchmark is
in the field, and no formal inference was performed, so adjacent ranks are not distinguishable.

---

## 2. Scope, labels, and what this exercise does and does not establish

### 2.1 The information track, stated precisely

Every result carries `information_track = revised_mixed_vintage_diagnostic` and the following manifest
flags:

| Flag | Value |
|---|---|
| `real_time` | `false` |
| `origin_admissible` | `false` |
| `promotion_eligible` | `false` |
| `production_accuracy_score` | `false` |
| `paper_parity_claimed` | `false` |
| `mixed_vintage_structural_year` | `2024` |
| `mixed_vintage_annual_structure_is_future_information_at_historical_origins` | `true` |
| `h1_opening_row_transient` | `true` |
| `truth_vintage` | `revised_mixed_vintage_snapshot` |

These are recorded in the result manifests by the runner and are part of each artifact's identity.

### 2.2 Two distinct vintage problems, which must not be conflated

**(a) Revised-data truth and revised-data estimation.** The scoring panel
(`revised_data/fixtures/quarterly_panel.csv`, 101 rows, 2000Q3–2025Q3, sha256 `f7bb26a4…851bbe`) is a
current-vintage snapshot, used for both estimation and truth by all fourteen models. Real GDP growth
for 2010Q2 is the value as revised through 2026, not the value available in 2010. This limitation is
**symmetric across every model** and is the same design Poledna, Miess, Hommes and Rabitsch (EER 2023)
adopt for the bulk of their evaluation. In that respect this exercise is not weaker than the reference
paper; it inherits the same known limitation, and declares it.

**(b) Mixed-vintage structure, which is asymmetric and is ours alone.** The calibration artifact
contains 37 annual arrays of length one, frozen at 2024: the entire `figaro` input–output block, plus
firm counts, employees, population, census unemployed and inactive, fixed assets, dwellings, capital
consumption, all tax and benefit aggregates, and sectoral wages. Out of the box only nine origins are
constructible (2024Q1–2026Q1), overlapping the benchmark grid in ~14 scoreable cells per target — far
too few to rank.

The unlock is a single-array rewrite: shallow-copy the calibration dictionary and set `years_num` to
the origin's year, which makes `T_calibration` resolve to index 1 — the only valid index, since every
annual array has exactly one column. Every quarterly series the dynamic block needs already covers
1996Q4 onwards, so opening levels do scale correctly with the era (`real_gdp[1]` = 5.483e6 at 2019Q4,
3.745e6 at 2010Q2, 3.231e6 at 2005Q2).

The consequence is a clean and declarable split:

* **Flow targets** — real GDP growth, GDP-deflator inflation, nominal GDP growth, the policy rate —
  are initialized from quarterly series with full history. The 2024 structure enters as a fixed
  technology and demand-composition matrix, not as a level. Scoring these is defensible as a
  diagnostic.
* **Stock-initialized targets** — unemployment above all — open at the 2024 level at *every* origin.
  Scoring these is not defensible, and §8.2 documents the failure quantitatively.

### 2.3 What this establishes

1. That the model runs free-running over the full 61-origin grid at a 12-quarter horizon with **zero
   path failures**, on a cell grid matching the statistical models exactly (61/60/58/54/50).
2. That after the repair it attains the **lowest weighted RMSE ratio in the field on the headline pair
   in all three tracks**, on matched cells with matched seeds.
3. That the pre-repair deficiency was a **specific, located, repairable accounting defect** — shown by
   matched-seed A/B with an explicit falsification table (§6.5), and then shown to be the operative
   cause by fixing it and re-scoring (§7).
4. That the repair is **attributable**: the v1 column was re-run rather than copied, reproduced
   bit-identically (gate G4, `max|diff| = 0` over 3 660 cells), and both columns were scored on
   exactly the same common cells in a single run.

### 2.4 What this does not establish

1. **Not pseudo-real-time accuracy.** No vintage-correct information set was reconstructed. A
   Philadelphia Fed RTDSM capture exists on disk and is the correct asset for a stage-3 design; it was
   not used.
2. **Not production skill, and not a promotion claim.**
3. **Not paper parity.** The reference paper calibrates the structural year at or near each origin and
   includes a DSGE benchmark; this exercise does neither.
4. **Not validity beyond h = 12.** See §7.6 and §10.1 — v2's growth is headroom drainage.
5. **Not evidence about unemployment or the labour block**, in either direction (§8.2).
6. **Not a formally inferential ranking.** No Diebold–Mariano test, no HAC adjustment, no bootstrap,
   no multiplicity control (§10.8).

### 2.5 A stage-3 vintage-clean design would require

Year-by-year annual history for the 37 frozen arrays: BEA Input–Output Summary Use/Make after
redefinitions; Census SUSB and BLS QCEW for firms and employees per sector; BLS CPS for population,
unemployed and inactive; BEA NIPA annual tables for the tax and benefit aggregates; BEA Fixed Assets
HMI11 for fixed assets, dwellings and capital consumption. Quarterly series need no fetch — they run
from 1996Q4. This is a data-acquisition programme, not a modelling one.

---

## 3. The model and its United States calibration

### 3.1 Structure

The model is the BeforeIT implementation of the Poledna–Miess–Hommes–Rabitsch agent-based
macroeconomic model. Agents are heterogeneous firms, worker and inactive households, firm owners, a
bank, a government, a central bank following a Taylor rule, and a rest-of-the-world block. Production
is Leontief in intermediates and capital, with a capacity constraint; goods and labour markets clear
through search-and-matching with rationing rather than by price-taking equilibrium; and expectations
are adaptive, estimated by the agents from the model's own realized history.

### 3.2 United States calibration at `scale = 1e-5`

| Quantity | Value |
|---|---|
| Commodities `G` | 68 |
| Industries `S` | 68 |
| Firms `Σ I_s` | 130 |
| Economically active households `H_act` | 1 826 |
| Inactive households `H_inact` | 1 005 |
| Total population represented | ≈ 2 831 |
| Other agent types `J`, `L` | 33, 65 |

The classifications come from the BEA summary-level supply–use system. The source table carries **68
observed commodities and 71 industries**; the four retail industry columns `441`, `445`, `452` and
`4A0` are summed into model sector `4A0`, giving the **68 modelled industries** matched one-to-one
against the 68 commodities (`scripts/us/bea71.toml:16`; `scripts/us/USPipeline.jl:1573` records the
aggregation as *"71 industries aggregated to 68"*). Runtime is **0.085 s per 12-quarter path** after
compilation, so a 61-origin × 500-path grid is a sub-hour job on one thread.

### 3.3 U.S.-specific adaptations

* **Explicit measured trade.** `use_explicit_trade = true` takes imports from measured BEA T262 rather
  than solving them as the supply–use residual. This preserves the measured import level but leaves
  the sector balance unreconciled — the single most consequential U.S.-specific choice in the artifact,
  and the subject of §6.3. **v2 retains it**; the reconciliation works around it rather than
  discarding it.
* **Product-tax netting.** `use_product_tax_netting = true`.
* **Discrepancy-derived opening inventories.** `use_commodity_balance_inventory = true` in the v1
  artifact, deriving `S_s` from the positive part of the negated statistical discrepancy. Note that
  `scripts/us/USPipeline.jl:3441` sets this to `false`; **the artifact and the pipeline disagreed**,
  and the artifact won for every origin the harness built. v2 sets it `false`, removing both the
  accuracy defect and the reproducibility hazard.
* **Policy rate on a quarterly basis.** `r_bar = (euribor_annual + 1)^(1/4) − 1`, so comparison against
  the annualized-percentage-point EFFR target requires `100·((1 + r_bar)^4 − 1)`. At 2024Q4 this gives
  4.571 % against a panel value of 4.65 %.
* **Capacity utilisation.** `ω = 0.85` is hard-coded (`src/utils/calibration.jl:879`). Every firm opens
  at exactly 85 % utilisation with 17.6 % headroom, by construction. §6.3 and §10.1 show why this
  matters.

### 3.4 The raw-dynamics firewall

That behavioural parameters have not been fitted to forecast errors was verified, not assumed. The
stored baseline carries firewall metadata recording `raw_parameters = true`,
`forecast_error_fitted_parameters = false`, `postprocessing_embedded = false`, four restored parameters
and seven removed output corrections; `forecast_calibration` is absent. Numerically, at 2024Q4:

| Parameter | Stored baseline | Fresh derivation | Class-H override in `forecast_calibration.toml` |
|---|---|---|---|
| `rho` | 0.954811254910 | 0.954811254910 | 0.911458333333 |
| `r_star` | −0.001043926436 | −0.001043926436 | −0.002333333333 |
| `xi_pi` | 0.789655283206 | 0.789655283206 | 0.708333333333 |
| `xi_gamma` | 0.532167779487 | 0.532167779487 | 0.258730279487 |

All ~70 parameter keys are identical between the stored baseline and a fresh derivation, and neither
equals the overrides. Decisively, the two produce **bit-identical 12-quarter paths under the same
seed**. All results here derive parameters via `Bit.get_params_and_initial_conditions`, which never
reads `forecast_calibration.toml`.

**The firewall applies with equal force to v2.** Both v2 changes are labelled **[S] structural** —
each restores an accounting identity or corrects an estimator that is wrong on its own terms, on
past-only information. λ = 0.983460 is fixed by the identity, not chosen. Neither change was selected
by reference to any forecast error. Re-estimating `ω`, `ψ`, `θ`, the Taylor-rule coefficients or the
AR(1) parameters against realized GDP paths would be **[T] behavioural tuning** and is named here
explicitly as prohibited; it was not done.

### 3.5 Absence of behavioural look-ahead

The exogenous arrays `C_G`, `C_E` and `Y_I` extend up to 12 quarters past the origin. This is an
artifact-level concern that is behaviourally empty: only element `T_prime` is ever read, once, as a
scalar, at construction; thereafter the series evolve by estimated AR(1). Proof by mutation: three
runs at 2024Q4 under identical seed — untruncated, truncated to `1:T_prime`, and untruncated with
**every post-origin entry overwritten with `−1e99`** — produced bit-identical `real_gdp`,
`nominal_gdp` and `euribor` paths, with the poisoned run finite throughout. Truncation is applied
anyway as past-only hygiene. Separately, every estimation window terminates at `T_calibration_exo`.

---

## 4. Experimental design

### 4.1 Origins, horizons, and the free-running protocol

| Design element | Value |
|---|---|
| Origins | 61, panel indices 40…100, i.e. **2010Q2 … 2025Q2** |
| Minimum training window | 40 quarters |
| Horizons scored | 1, 2, 4, 8, 12 |
| Simulated quarters per path | 12 |
| Paths per origin | **500** (both v1 and v2) |
| Path failures | **0** |
| Simulation mode | free-running, serial (`parallel = false`) |
| Model scale | 1e-5 |
| Julia / threads / BLAS threads | 1.10.3 / 1 / 1 |

"Free-running" means the model is initialized once at the origin and stepped forward 12 quarters with
no re-anchoring, no observed-data injection and no conditioning on realized post-origin values. This
corresponds to the reference paper's unconditional forecast, the harder of its two exercises.

**Seeding.** `Bit.Model` draws initial microstates from the global RNG, so the only correct
reproducible pattern is `Random.seed!(seed)` immediately before `Bit.Model(...)`, with a fresh model
per path:

```julia
for s in 1:n_paths
    Random.seed!(hash((:abm_revised_v1, period, s)) % 2^30)
    m = Bit.Model(params, ic)          # fresh microstate per path
    for h in 1:T
        Bit.step!(m; parallel = false)
        Bit.collect_data!(m)
    end
end
```

`Bit.ensemblerun` was deliberately not used: it `deepcopy`s one already-constructed model, so all paths
share the same initial microstate. **v2 draws the identical seed stream as v1**, which makes the
contrast matched-seed. The expectations patch consumes exactly one Normal variate on either branch
precisely to keep that alignment.

### 4.2 Operators

Applied **pathwise, before any ensemble operation** (row 1 is the origin; horizon `h` is row `h+1`):

```
real_gdp                       400 * (log(rg[h+1]) - log(rg[h]))
gdp_deflator                   400 * ((log(ng[h+1]) - log(rg[h+1])) - (log(ng[h]) - log(rg[h])))
nominal_gdp                    400 * (log(ng[h+1]) - log(ng[h]))
unemployment_rate              100 * count(==(0), w_act.O_h) / H_act        at row h+1
effective_federal_funds_rate   100 * ((1 + euribor[h+1])^4 - 1)
```

The log form of the deflator operator is algebraically identical to the ratio form but finite for all
positive `Float64`. The quarterly/SAAR ÷4 scaling cancels from log differences, so `400 = 4 × 100` is
the complete annualization. Unemployment has no field in `Bit.Data` and is read off agent state inside
the stepping loop, using `H_act` (1 826, the concept closest to the CPS labour force) as denominator.

### 4.3 Ensemble functionals

Two point forecasts per cell, as separate model columns: the **mean of pathwise-transformed** values
(RMSE-consistent) and the **median of pathwise-transformed** values (MAE-consistent). Reporting both is
what allowed the v1 MAE asymmetry to be attributed correctly — see §5.4 and §7.4.

### 4.4 The comparator field

Fourteen models are scored: ten statistical comparators plus two ABM columns each for v1 and v2. The
statistical specifications, from the module's own type definitions:

| # | `model_id` | Specification |
|---|---|---|
| 1 | `naive_no_change` | Random walk; forecast = last training observation. |
| 2 | `naive_drift` | Random walk with drift estimated only from training differences. |
| 3 | `naive_historical_mean` | Constant forecast equal to the training-sample mean. |
| 4 | `univariate_ar_p1_constant` | Univariate AR(1) with intercept, per target. |
| 5 | `univariate_ar_p4_constant` | Univariate AR(4) with intercept. |
| 6 | `univariate_ar_bic_p1-…-8_constant` | Lag order chosen by BIC on a common, training-only window. |
| 7 | `beforeit_var_p1_constant` | Multivariate VAR(1) with intercept over the eight-target panel. **Ratio anchor.** |
| 8 | `beforeit_var_p2_constant` | VAR(2). |
| 9 | `beforeit_var_p3_constant` | VAR(3). |
| 10 | `bvar_mniw_v1_p1_constant_…` | Natural-conjugate Bayesian VAR, matrix-normal/inverse-Wishart prior, Minnesota-style shrinkage: tightness 0.2, lag decay 1.0, own-lag mean 0.0, intercept variance 100, IW dof offset 2, innovation scale 1.0, scale floor 1e-8. All hyperparameters fixed before the origin fit and encoded in the `model_id`; no tuning inside the benchmark. |

**On the semi-structural comparator.** The registered fixed-parameter quarterly semi-structural
state-space model — potential growth, output gap, natural unemployment, neutral real rate, inflation
anchor, inflation, policy rate and lagged output gap, with a fixed transition encoding IS, Phillips,
Okun and Taylor links updated by an exact Kalman filter — is **not in this field**. It scores a
core-four target set (`real_gdp`, `pce_price_index`, `unemployment_rate`,
`effective_federal_funds_rate`) of which the ABM cannot serve `pce_price_index`. Its standing from the
separate 11-model comparison is weighted RMSE ratio **0.749** (1 of 11, all-available) and **0.745**
(1 of 11, balanced) — quoted as context only, on a *different target set and a different model field*.
It is not a like-for-like comparison. Adding it under the ABM's target set is a gap (§10.7).

### 4.5 Truth, scaling, and score construction

**Truth** is the revised panel itself: `actual = panel.values[origin_index + horizon, column]`;
`error = point_forecast − actual`.

**Target transformations**, from the panel manifest — note these are not uniform:

| `target_id` | Transformation | Unit |
|---|---|---|
| `real_gdp`, `nominal_gdp`, `gdp_deflator`, `pce_price_index`, `core_pce_price_index` | `400·ln(level_t/level_{t−1})` | pp, annual rate |
| `unemployment_rate` | quarterly mean of three monthly `LNS14000000` levels, no transform | pp |
| `effective_federal_funds_rate` | equal-weight mean of published Mon–Fri EFFR in the quarter | pp |
| `payroll_employment` | quarterly mean of three monthly `CES0000000001`, then `100·ln(mean_t/mean_{t−1})` | log points, **not** annualized |

**MASE scales** are recomputed at every origin as
`mean(abs.(diff(panel[1:origin_index, :], dims=1)))` per column, using training data only.

**Score aggregation.** Summaries group by (track, model, target, horizon) and emit RMSE, MAE, MASE and
mean error. Relative scores divide by the anchor's and **throw** if observation counts are unequal. The
weighted ratio is a macro-average of matched target-by-horizon cellwise ratios,

```
Σ_targets Σ_horizons  target_weight × horizon_weight × cellwise_score_ratio
```

with `HORIZON_WEIGHTS = {1:0.30, 2:0.25, 4:0.20, 8:0.15, 12:0.10}` and equal target weights. It is
explicitly **not** a ratio of pooled losses. A model is marked
`INCOMPLETE_MATCHED_GRID_NOT_RANKED` with `NaN` ratios unless it has all `n_targets × 5` cells and zero
failures. Every ABM column here is `COMPLETE_MATCHED` at 10/10 cells on all tracks and both target
sets.

**Common cells.** The scoring key is `(origin_index, target_id, horizon)`; only cells where *every*
model in the field is present survive. Because v1 and v2 were scored in a single run via
`--also-score`, the v1-versus-v2 contrast cannot be a sample artifact.

### 4.6 Tracks

| Track | Rule | n per horizon (h=1/2/4/8/12) |
|---|---|---|
| `abm_all_available_common_cells` | every common cell | 61 / 60 / 58 / 54 / 50 |
| `abm_balanced_h12_common_cells` | `origin_index ≤ 89`, so every origin has a complete h=12 | 50 / 50 / 50 / 50 / 50 |
| `abm_pandemic_masked_common_cells` | exclude cells whose **target** period falls in 2020Q1–2021Q4 | 53 / 52 / 50 / 46 / 42 |

The pandemic mask is applied to target dates, not origins, and was pre-registered in the run manifest
rather than selected after seeing results.

### 4.7 Monte-Carlo error

The ABM's point forecast is an ensemble functional over finitely many stochastic paths, so its measured
RMSE is inflated by roughly `sqrt(1 + (mc_se/rmse)^2)`. At 500 paths:

| Target | Mean ensemble s.d. | Mean MC s.e. of the mean | Max MC s.e. |
|---|---|---|---|
| `real_gdp` | 3.036 – 3.269 | 0.136 – 0.146 | 0.255 |
| `gdp_deflator` | 0.860 – 1.077 | 0.038 – 0.048 | 0.100 |
| `nominal_gdp` | 3.211 – 3.440 | 0.144 – 0.154 | 0.264 |
| `unemployment_rate` | 0.414 – 1.079 | 0.019 – 0.048 | 0.070 |
| `effective_federal_funds_rate` | 0.139 – 0.336 | 0.006 – 0.015 | 0.019 |

Against a real-GDP cross-origin RMSE of order 6 pp, an MC standard error of 0.14 pp inflates measured
RMSE by well under **0.1 %**. Monte-Carlo noise is not a material contributor to any result here. (At
the 16-path pilot count it was 1.3 pp and *was* material; 500 paths were used to remove the confound.)

### 4.8 The opening-row measurement basis

`update_data_init!` writes row 1 on a different measurement basis from rows 2 onwards:
`d.real_gdp[1] = d.nominal_gdp[1]`, because prices are normalized to 1 at initialization — so the
deflator is **exactly 1.0** in row 1. `use_opening_macro_controls = false` and
`validated_opening_macro_controls(ic) === nothing` for both the stored baseline and a fresh
derivation, so the opening row is the **model-implied** opening, not an observed control: reassuring
for leakage, unhelpful for h=1 comparability.

Dropping h=1 was rejected outright — it would render the grid incomplete and the model unranked. h=1
is reported and flagged; it carries the largest horizon weight (0.30).

**This effect is real but smaller than v1 suggested.** The v1 draft attributed the −7.3 pp h=2 bias
principally to this basis change. §7.3 shows that the deflator's h=1 cell is indeed *bit-identical*
between v1 and v2 (the price normalization is untouched by the reconciliation), while real GDP's h=2
bias collapses from −7.28 to −0.10 pp. The measurement basis therefore explains the deflator's h=1
behaviour; **the −7.3 pp was overwhelmingly the rationing crash**, not the basis.

---

## 5. Results: v1, the pre-repair baseline

Computed from `output/us_forecasting/abm_v2_comparison/v2_headline/*.csv`, in which both ABM columns
were scored jointly. The v1 column reproduced the standalone v1 run bit-identically (gate G4).

### 5.1 Headline standings, v1

| Track | v1 mean ratio (rank of 14 columns) | v1 median ratio (rank) | Best statistical |
|---|---|---|---|
| all-available | 0.905 (5th) | 0.903 (4th) | `naive_historical_mean` 0.879 |
| balanced-h12 | 0.894 (5th) | 0.893 (4th) | `naive_historical_mean` 0.884 |
| pandemic-masked | 1.272 (11th) | 1.264 (10th) | `univariate_ar_p1` 0.848 |

Competitive on the first two tracks, and **11th of the 14 columns once the COVID cells are removed**.

### 5.2 Per-target, per-horizon detail, v1

| Target | h | n | RMSE | Ratio to VAR(1) | Rank | Bias |
|---|---:|---:|---:|---:|---:|---:|
| `real_gdp` | 1 | 61 | 6.2592 | 0.689 | 4/14 | −1.317 |
| `real_gdp` | 2 | 60 | 9.5104 | 1.294 | 12/14 | **−7.277** |
| `real_gdp` | 4 | 58 | 6.8762 | 1.082 | 8/14 | −2.938 |
| `real_gdp` | 8 | 54 | 6.7381 | 0.858 | 8/14 | −2.146 |
| `real_gdp` | 12 | 50 | 6.9637 | 1.035 | 10/14 | −2.017 |
| `gdp_deflator` | 1 | 61 | 1.4288 | 0.794 | 6/14 | −0.192 |
| `gdp_deflator` | 2 | 60 | 1.6486 | 0.771 | 5/14 | −0.293 |
| `gdp_deflator` | 4 | 58 | 1.9398 | 0.822 | 2/14 | −0.400 |
| `gdp_deflator` | 8 | 54 | 2.0391 | 0.975 | 4/14 | −0.525 |
| `gdp_deflator` | 12 | 50 | 2.1093 | 0.892 | 5/14 | −0.608 |

Two readings. **The deflator was already the strongest headline target** — ratios 0.771–0.975 at every
horizon, and the only target whose MAE ratios were uniformly below one. **The real-GDP bias was
systematic and large**, −1.3 to −2.9 pp excluding the transient. That v1 nonetheless achieved a
competitive RMSE ratio reflects in part the weakness of the VAR(1) anchor, which is itself unstable at
the 2010Q2 origin (spectral radius 1.0342, design condition number 8 747).

### 5.3 The v1 RMSE–MAE asymmetry

v1's headline RMSE ratio of 0.905 sat against an MAE ratio of 1.137. Disaggregated:

| Target | v1 RMSE ratio, h=1/2/4/8/12 | v1 MAE ratio, h=1/2/4/8/12 |
|---|---|---|
| `real_gdp` | 0.689 / 1.294 / 1.082 / 0.858 / 1.035 | 0.842 / **2.376** / 1.454 / 1.087 / 1.283 |
| `gdp_deflator` | 0.794 / 0.771 / 0.822 / 0.975 / 0.892 | 0.919 / 0.780 / 0.807 / 0.861 / 0.842 |
| `nominal_gdp` | 0.674 / 1.168 / 1.051 / 0.882 / 1.028 | 0.819 / **2.071** / 1.272 / 1.008 / 1.155 |
| `effective_federal_funds_rate` | 0.563 / 0.556 / 0.588 / 0.796 / 0.806 | 0.584 / 0.627 / 0.664 / 0.762 / 0.777 |

The asymmetry was never a general property: on the deflator and the policy rate the MAE ratios were
already below one. It was concentrated in real and nominal GDP, and within those, in the h=2 cell.
Switching to the loss-consistent median improved the weighted MAE ratio only from 1.137 to 1.130 — so
it was **not** a functional-choice artifact. §7.4 shows what it actually was.

### 5.4 Burn-in: a v1-era sensitivity, now superseded

Burn-in was tried as the leading candidate fix for the h=2 cell, at 128 paths: `burn_in_quarters = 1`
and `= 4`, building at origin−k and treating row k+1 as the origin.

| Variant | Paths | Headline weighted RMSE | Headline weighted MAE | Secondary weighted RMSE |
|---|---:|---:|---:|---:|
| v1, no burn-in | 500 | 0.905 | 1.137 | 0.782 |
| Burn-in 1 quarter | 128 | 0.954 | 1.258 | 0.912 |
| Burn-in 4 quarters | 128 | 0.916 | **1.012** | 1.095 |

Per-cell, `real_gdp` RMSE / bias / ratio:

| h | v1 (500p) | Burn-in 1 (128p) | Burn-in 4 (128p) |
|---:|---|---|---|
| 1 | 6.2592 / −1.317 / 0.689 | 9.4889 / **−7.290** / 1.044 | 6.6260 / −2.715 / 0.729 |
| 2 | 9.5104 / **−7.277** / 1.294 | 7.5995 / −4.569 / 1.034 | 6.5522 / −2.370 / 0.891 |
| 4 | 6.8762 / −2.938 / 1.082 | 6.7998 / −2.740 / 1.070 | 6.5242 / −2.156 / 1.027 |
| 8 | 6.7381 / −2.146 / 0.858 | 6.7543 / −2.108 / 0.860 | 6.7025 / −2.004 / 0.853 |
| 12 | 6.9637 / −2.017 / 1.035 | 6.9235 / −1.931 / 1.029 | 6.7966 / −1.583 / 1.010 |

One quarter of burn-in **relocates** the transient from h=2 to h=1, where the weight is larger, so the
weighted result worsens. Four quarters disperses it but destroys the level targets: the policy-rate
h=1 ratio degrades from 0.563 to 2.091 and the secondary weighted ratio from 0.782 to 1.095, because
four quarters of free-running drift move the model's policy rate away from the origin's observed level
before scoring begins. Burn-in trades a growth-rate artifact for a level-drift information loss.

**This whole line of attack is moot in v2.** The h=2 real-GDP bias falls to −0.096 pp under the balance
fix alone, with `burn_in_quarters = 0` (§7.3). The transient was a symptom of the rationing crash, and
burn-in was treating the symptom. No burn-in is applied in v2, and the burn-in runs are retained only
as documented negative results. (They used 128 paths against 500, worth well under 1 % of RMSE by
§4.7 — not enough to change the conclusion.)

---

## 6. Diagnosis: the anatomy of the −2.75 pp real-growth bias

This section rests on matched-seed A/B experiments at four to five origins with 48–64 paths per cell,
seeds identical across every variant. The bias measured here is h=3…12 annualized real GDP growth,
ensemble mean minus realized, averaged over the three clean origins 2012Q4 / 2016Q4 / 2022Q4 (2019Q4 is
excluded from every average: its window is the pandemic rebound at +6.2 pp). The baseline is
**−2.750 pp**, consistent with the −2.0 to −2.9 pp per-horizon biases measured independently at 61
origins in §5.2.

### 6.1 Ranked attribution

| # | Mechanism | Share of bias | Confidence |
|---|---|---|---|
| 1 | Non-clearing sector commodity balance under `use_explicit_trade = true`, colliding with a frozen firm capacity envelope | **−2.10 pp (76 %)** | **high** |
| 2 | Growth expectation `γ_e` from an OLS AR(1) on **log levels**, delivering only 32–63 % of the in-sample trend | **−0.70 pp (24 %)** | **high** on the estimator, **medium** on the delivered size |
| 3 | `S_s` opening inventories built from the negative half of a signed statistical discrepancy | −0.23 pp (subset of #1) | high |
| 4 | No capital accumulation (replacement-only investment) | latent — binds only through #1 | high |
| 5 | Exogenous G/X/M log-level AR(1) attractors | ≈ 0 net | high |

The GDP deflator is untouched throughout — 1.8–2.5 % in every variant — which is why inflation was
never biased. **The defect is a real quantity-rationing defect, not a pricing defect.** §7 confirms
this prediction out of sample: the v2 deflator column is essentially unchanged, bit-identical at h=1.

### 6.2 The shortfall is broad-based, not concentrated

Expenditure decomposition, h=3…12 annualized, contribution gap = opening nominal share × (ABM −
realized):

| Origin | C | I fixed | G | X | M (−) | **GDP** |
|---|---:|---:|---:|---:|---:|---:|
| 2012Q4 | **−1.77** | **−0.91** | −0.02 | +0.23 | +0.44 | **−2.03** |
| 2014Q4 | **−1.54** | **−0.64** | −0.17 | +0.10 | +0.46 | **−1.80** |
| 2016Q4 | **−1.54** | **−0.60** | −0.46 | +0.12 | +0.19 | **−2.30** |
| 2022Q4 | **−1.72** | **−0.44** | −0.30 | −0.05 | +0.30 | **−2.20** |

Every domestic component grows at 0.1–0.5 % annualized against realized 2.5–5.4 %. Consumption carries
~70 % of the contribution gap and fixed investment ~25 % **purely because of their weights** — their
growth *rates* are equally flat (0.11–0.36 %). Net trade contributes *positively*; exports are
over-forecast by 1.3–3.0 pp. Trade is not leaking demand at the aggregate level; the trade problem is
compositional.

At the 68-sector level, 31–36 of 68 sectors show positive growth, and **the same sectors lose at every
origin** — the persistent-loser list is identical at 2012Q4, 2016Q4 and 2024Q4. A stable loser set
across twelve years of origins is a calibration signature, not a shock response.

### 6.3 Defect 1: the commodity balance does not clear

**What the artifact encodes:**

```
figaro["use_explicit_trade"]              = true
figaro["use_commodity_balance_inventory"] = true
ic["commodity_balance_closure_applied"]   = false
ic["commodity_supply_g"]                  = Σ 5.2570e7
ic["modeled_commodity_uses_g"]            = Σ 5.3101e7
```

Because imports come from measured BEA T262 rather than being solved as the residual, the residual
survives as a **signed, sector-level gap**:

```
aggregate uses/supply = 1.01010
min −0.706 | p25 −0.058 | median +0.020 | p75 +0.128 | max +0.476
42/68 over-demanded ; 34/68 with |gap| > 10 % ; 8/68 with |gap| > 25 %
```

**Why nothing absorbs it.** Two facts lock the chain.

1. **The capacity envelope is fixed by construction.** `ω = 0.85` is hard-coded,
   `kappa_s = timescale·industry_output/fixed_assets/ω` and `K_i = Y_i/(ω·κ_i)`, so every firm opens at
   exactly 85 % utilisation with 17.6 % headroom and `K_i·κ_i = Y_i/0.85` identically.
2. **Capital never accumulates.** `I_d_i = δ_i/κ_i·min(Q_s_i, K_i·κ_i)` and `K' = K − δ/κ·Y + I` imply
   `K' = K` exactly when firms get desired investment and produce at target. Measured:
   **`K_end/K_1` = 1.0000–1.0009 in every variant**, including under +30 % capacity relief. This
   `min(...)` was already in the upstream CANVAS commit `320a7e2`; the fork only reformatted it. **It
   is not a fork bug.**

So the capacity vector is frozen in proportion to the *opening output* composition while the demand
vector is fixed by `a_sg, b_HH_g, b_CF_g, c_G_g, c_E_g` — and the two differ by exactly the 42/26
signed gap. Over-demanded sectors sit permanently against the ceiling, under-demanded ones permanently
idle, and `min()` is one-sided so idle capacity never compensates.

The signature matches the mechanism exactly:

* mean `(uses−supply)/supply` of the 12 most-truncated sectors = **+0.222**, versus +0.014 for all 68;
* mean gap of the persistent GVA losers = **−0.140**, versus −0.025 for winners;
* 46 of 68 sectors are *never* truncated, while a stable minority is truncated 40–80 % of quarters.

**Downstream, unmet demand appears as persistent rationing**, stable at every horizon and origin:

| Fill rate | h=1 | h=2 | h=4 | h=8 | h=12 |
|---|---:|---:|---:|---:|---:|
| Households | 0.999 | 0.973 | 0.978 | 0.976 | 0.975 |
| Government | 0.999 | 0.961 | 0.961 | 0.960 | 0.958 |
| **Exports** | 0.995 | **0.845** | **0.869** | **0.865** | **0.862** |
| Imports | 0.993 | 0.991 | 0.989 | 0.989 | 0.987 |

Opening capacity relief (`K × 1.30`) lifts the export fill rate to 0.92–0.96, establishing that
**export rationing is a symptom of the capacity/balance collision, not an independent trade defect**.

**The `S_s` sub-defect.** `S_s = timescale · pos(−discrepancy)`, so only the 42 negative-gap sectors
receive an opening inventory buffer; the 26 positive-gap sectors receive exactly zero. `Σ S_s` is 7.4 %
of quarterly gross output with 31 % of it in a single sector. The zero-buffer sectors stock out first
and are the persistent GVA losers.

### 6.4 Defect 2: the growth expectation is biased low by construction

Firms set `Q_s_i = Q_d_i·(1 + γ_e)` where `γ_e = exp(α̂·log Y_last + β̂)/Y_last − 1` and `(α̂, β̂)` come
from **OLS AR(1) with constant on the log level** of the full model history.

| Origin | T′ | α̂ | γ_e (ann %) | In-sample trend (ann %) | γ_e / trend |
|---|---:|---:|---:|---:|---:|
| 2012Q4 | 64 | 0.9713 | +0.745 | +2.331 | 0.32 |
| 2014Q4 | 72 | 0.9791 | +0.914 | +2.385 | 0.38 |
| 2016Q4 | 80 | 0.9834 | +1.035 | +2.359 | 0.44 |
| 2019Q4 | 92 | 0.9906 | +1.469 | +2.415 | 0.61 |
| 2022Q4 | 104 | 0.9900 | +1.240 | +2.366 | 0.52 |
| 2024Q4 | 112 | 0.9930 | +1.523 | +2.401 | 0.63 |

**The arithmetic is closed-form.** For a log-linear trend `x_t = a + g·t`, OLS AR(1) with constant
gives `β̂ = x̄_t − α̂·x̄_{t−1}`, hence

```
γ_e ≈ g · [ 1 − (1 − α̂)·T/2 ]
```

At 2024Q4, `(1 − 0.99305)·112/2 = 0.389`, so `γ_e ≈ 0.611·g = 1.47 %` against a measured 1.52 % — the
formula reproduces the estimator to 0.05 pp. **The shrinkage is unavoidable**: α̂ carries the
Kendall/Dickey–Fuller small-sample downward bias, and the level shocks of 2008–09 and 2020 push it
further down. Shorter windows do not help; they trade smaller `T` against more biased α̂.

**The counterfactual is exact.** Pinning α = 1 (random walk with drift, β = mean in-sample log growth)
gives γ_e = +2.33, +2.39, +2.36, +2.42, +2.37, +2.40 % — the trend, at every origin, using past data
only.

**But this defect is latent, and that is the crucial finding.** Replacing `ic["Y"]` by its own
log-linear trend raises γ_e from ~1.0 % to ~1.9 % but moves delivered GDP growth by **+0.06 pp on
average**. Pushing the expectation to 2× trend still delivers −0.06 to +0.04 pp. The delivered-growth
elasticity to γ_e is ≈ **0** while the imbalance is present, rises to ≈ +0.5 pp once capacity headroom
is opened, and reaches **+0.75 pp** once the balance is closed. Expectations are a real but strictly
**subordinate** defect: fixing them is worth +0.75 pp, *but only after fix #1*. Measured on the real
patched code (64 matched-seed paths, four origins), the rw-drift delta is +0.193 pp on the unreconciled
baseline and **+0.499 pp** on the reconciled one — the monotone pattern the diagnosis predicted.

### 6.5 The falsification table

Each row is a matched-seed experiment run to kill a competing hypothesis.

| Test | Result | Rules out |
|---|---|---|
| **Agent-count sweep** 130 → 294 → 912 → 2 708 firms | truncated share **14 % at every scale**; growth stays ≈ 0 | idiosyncratic small-sample lumpiness |
| **Materials-only relief** `M × 1.30` | −0.06 vs −0.08 baseline: **no effect** | materials as an independent binding constraint |
| **Investment-demand cut** `κ_s × 1.30` (cuts `I_d` by 23 %, leaves `K·κ`) | −0.20 vs −0.08: **−0.12 pp only** | investment demand as a first-order channel |
| **Capacity tightening** `K·κ × 0.77` | −1.14 / −1.22 pp | — confirms sign and convexity of the capacity margin |
| **Un-capped investment emulation** | −0.03 vs −0.08; `K_end/K_1` = 1.0005 | "the fork's `min` broke investment" |
| **V3 + `K × 1.30`** | 1.921 vs 1.879 (2016Q4); 2.505 vs 2.503 (2024Q4): **+0.00 pp** | capacity as an *independent* cause |
| **Drop `S_s` only** | **+0.23 pp** mean, same sign at all four origins | — a genuine but small independent contribution |
| **Labour-supply ceiling** | `bind:labour` = 0.000 at every row and origin | the labour block as the constraint |
| **Post-origin look-ahead in `C_G`/`C_E`/`Y_I`** | bit-identical paths under `−1e99` poisoning | data leakage |

The sixth row is the decisive discriminator: **capacity relief and balance-closure are substitutes, not
complements. The balance is upstream.**

### 6.6 The dose–response that motivated the fix

Reverting to the legacy residual closure (`use_explicit_trade = false`, which *guarantees* clearing but
discards the measured BEA import levels) gives, for h=3…12 annualized real GDP growth:

| Origin | Realized | V0 baseline | **V3 legacy residual trade** | V6 = V3 + trend-Y | Truncated share V0 → V3 |
|---|---:|---:|---:|---:|---|
| 2012Q4 | **2.586** | 0.051 | **2.365** | 3.511 | 0.144 → 0.006 |
| 2016Q4 | **2.922** | −0.079 | **1.879** | 2.633 | 0.139 → 0.002 |
| 2022Q4 | **2.531** | −0.207 | **1.813** | 2.458 | 0.129 → 0.004 |
| 2024Q4 | — | −0.219 | **2.503** | 2.623 | 0.143 → 0.012 |

**Mean bias over the three clean origins: V0 −2.76 pp → V3 −0.66 pp → V6 +0.19 pp**, with the deflator
unchanged throughout. V3 is a **diagnostic instrument**, not the shipped fix: it discards measured
import levels. The shipped fix (§7.1) achieves exact clearing while *retaining* them.

---

## 7. Results: v2, the repaired model

### 7.1 What v2 changes

Two changes, both in the calibration artifact rather than in behavioural parameters.

**(i) The opening commodity balance now clears.**
`scripts/us/calibration/reconcile_commodity_balance.jl` applies a biproportional (RAS /
minimum-I-divergence) adjustment to the **use side only**, at the flow level, then re-derives every
coefficient from the balanced flows and writes them back in the raw pre-valuation-bridge basis so the
*unmodified* library pipeline reproduces the balanced flows exactly.

* Row controls: `industry_output + imports`. **`use_explicit_trade` stays `true`** — no measured BEA
  import level is discarded.
* Column controls: the 68 industry intermediate budgets and the four final-demand budgets.
* Zeros preserved; converged in 623 iterations (correcting an earlier draft figure of 543; the committed reconciliation_report_rho1.txt is authoritative); column budgets move by `< 1e-13`; the artifact
  re-derives to `max |uses_g/supply_g − 1| = 1.0e-13`.
* `use_commodity_balance_inventory` set `false`: with the balance clearing there is no signed
  discrepancy to promote into `S_s`, and the reference specification opens with `S_i(0) = 0`. This also
  removes the artifact ↔ `USPipeline.jl:3441` contradiction.

**The one accounting choice, stated explicitly.** Uses exceed supply by **1.0104 %** in aggregate. That
residual decomposes exactly (to `5.6e-9`) into:

| Term | Value (US$m) | Meaning |
|---|---:|---|
| expenditure GDP − production GDP | 442 933 | the artifact's own statistical discrepancy, 1.57 % of GDP |
| capital consumption − non-dwelling GFCF | 88 223 | net non-dwelling fixed investment is negative in the artifact |
| **total** | **531 156** | = `sum(uses) − sum(supply)` |

RAS requires `sum(rows) == sum(cols)`, so one control must move. v2 anchors on the **production**
account: C, G, I and X — and `capital_consumption` and `gross_capitalformation_dwellings`, which
together set the investment budget — are scaled by

```
lambda = (supply − intermediates) / (C + G + I + X) = 0.983460
```

`lambda` is **fixed by the accounting identity alone and was not chosen with reference to any forecast
error**. It is sealed in every manifest as `reconciliation_lambda` with its semantics. The alternative
closure (hold every measured budget, let a uniform 1.01 % excess-demand wedge survive) was built and
measured too; it overshoots, because a uniform 1 % excess demand is itself a growth impulse.

**(ii) Growth expectations are a random walk with drift.** v2 pins `alpha = 1` and takes the drift as
average past log growth — the correctly specified estimator for the same series, on past data only.
Gated behind a new `expectation_rw_drift` model property, registered only when the artifact carries the
marker. **Default `false`, so Austria and Italy are bit-identical.** Exactly one Normal variate is
consumed on either branch, keeping matched-seed comparisons aligned.

### 7.2 Regression gates

| # | Gate | Threshold | Result |
|---|---|---|---|
| G1 | matched-grid completeness | 61 origins; counts 61/60/58/54/50; no `INCOMPLETE_MATCHED_GRID_NOT_RANKED` | **PASS** — 61/61 origins; `[61,60,58,54,50]` all-available, `[50,50,50,50,50]` balanced, `[53,52,50,46,42]` masked; every ABM column `COMPLETE_MATCHED` |
| G2 | no non-finite output | 0 | **PASS** — 0 non-finite cells in 3 660 + 3 660 + 120 ensemble rows; `paths_used = 500` at every origin; `paths_failed = 0`; `failures.csv` empty |
| G3 | Austria/Italy unchanged with the flag off | bit-identical | **PASS** — `AUSTRIA2010Q1`, 3 seeds × {real_gdp, nominal_gdp, euribor}, SHA-256 of raw `Float64` vectors identical between a pristine `a55d9ed` checkout and the patched worktree |
| G4 | v1 column reproduces the pre-patch v1 run | bit-identical | **PASS** — all **3 660** cached v1 ensemble cells identical (`max |diff| = 0`); weighted scores match to every printed digit (0.9048 / 0.9034) |
| G5 | GDP-deflator inflation stays ~2 % | no regression vs v1 | **PASS** — v2 mean 2.019 pp (p5 1.663, p95 2.687) vs v1 2.024 pp over the same 671 scored cells; per-horizon v2 bias −0.19/−0.29/−0.42/−0.53/−0.62 pp vs v1 −0.19/−0.29/−0.40/−0.53/−0.61 pp. **At h=1 the two columns are bit-identical** — the reconciliation is a quantity intervention and leaves pricing untouched |
| G6 | commodity balance clears in the shipped artifact | `max &#124;uses/supply − 1&#124;` < 1e-6 | **PASS** — 1.0e-13 after re-derivation through the unmodified pipeline; RAS column budgets moved < 1e-13 |
| G7 | package test suite | green | **PARTIAL — pre-existing failure.** 815 pass, 1 fail. The failure is `Format (Runic.jl)`, which walks the whole repository and already failed at `a55d9ed` on ten `scripts/` files untouched by this work. Every file authored or edited here is Runic-clean. Tracked separately |
| G8 | unemployment | report, do not gate | **REPORTED, FAILING ON MERIT** — §8.2. `unemployment_rate` stays out of every weighted score |

G4 was verified independently for this report: the `monte_carlo_errors.csv` of the re-run v1 column is
byte-identical to that of the original standalone v1 run.

### 7.3 Headline standings, v2 — first of fourteen in all three tracks

**{real GDP growth, GDP-deflator inflation}, `all-available`** (n = 61/60/58/54/50):

| Rank | Model | Weighted RMSE ratio | Weighted MAE ratio |
|---:|---|---:|---:|
| **1** | **`beforeit_abm_us_v2_mean`** | **0.830** | **0.814** |
| **2** | **`beforeit_abm_us_v2_median`** | **0.830** | **0.815** |
| 3 | `naive_historical_mean` | 0.879 | 0.838 |
| 4 | *`beforeit_abm_us_v1_median`* | *0.903* | *1.130* |
| 5 | *`beforeit_abm_us_v1_mean`* | *0.905* | *1.137* |
| 6 | `bvar_mniw_v1_p1_constant_…` | 0.908 | 0.896 |
| 7 | `univariate_ar_p1_constant` | 0.918 | 0.888 |
| 8 | `univariate_ar_bic_p1-…-8_constant` | 0.929 | 0.901 |
| 9 | `univariate_ar_p4_constant` | 0.939 | 0.923 |
| 10 | `beforeit_var_p1_constant` (anchor) | 1.000 | 1.000 |
| 11 | `naive_no_change` | 1.075 | 1.121 |
| 12 | `naive_drift` | 1.106 | 1.156 |
| 13 | `beforeit_var_p2_constant` | 2.121 | 1.496 |
| 14 | `beforeit_var_p3_constant` | 5.313 | 2.672 |

**`balanced h=12`** (n = 50 at every horizon): v2 mean **0.829** (1st), v2 median 0.830 (2nd),
`naive_historical_mean` 0.884 (3rd), v1 median 0.893 (4th), v1 mean 0.894 (5th), BVAR 0.909 (6th).

**`pandemic-masked`** (n = 53/52/50/46/42):

| Rank | Model | Weighted RMSE ratio | Weighted MAE ratio |
|---:|---|---:|---:|
| **1** | **`beforeit_abm_us_v2_mean`** | **0.796** | **0.792** |
| **2** | **`beforeit_abm_us_v2_median`** | **0.799** | **0.795** |
| 3 | `univariate_ar_p1_constant` | 0.848 | 0.830 |
| 4 | `bvar_mniw_v1_p1_constant_…` | 0.852 | 0.866 |
| 5 | `univariate_ar_bic_p1-…-8_constant` | 0.870 | 0.852 |
| 6 | `naive_historical_mean` | 0.881 | 0.819 |
| 7 | `univariate_ar_p4_constant` | 0.889 | 0.864 |
| 8 | `beforeit_var_p1_constant` (anchor) | 1.000 | 1.000 |
| 9 | `naive_no_change` | 1.258 | 1.198 |
| 10 | *`beforeit_abm_us_v1_median`* | *1.264* | *1.435* |
| 11 | *`beforeit_abm_us_v1_mean`* | *1.272* | *1.448* |
| 12 | `naive_drift` | 1.325 | 1.255 |
| 13 | `beforeit_var_p2_constant` | 3.722 | 1.841 |
| 14 | `beforeit_var_p3_constant` | 11.806 | 4.017 |

**The regime-sensitivity finding is resolved, and it resolves in v2's favour.** v1's competitive rank
*depended on the COVID cells*: masking 2020Q1–2021Q4 moved it from 5th (0.905) to 11th (1.272). v2
carries no such dependence — it is 1st in the masked sample, and by its **widest** margin
(0.796 against 0.848 for the best statistical model, a 6.1 % gap, versus 5.6 % all-available). The
regime sensitivity was a symptom of the defect: in the calm sample the chronic −2 pp bias dominated the
error, while in the full sample it was partly hidden by cells no model forecasts. Removing the bias
removes the sensitivity.

### 7.4 Per-cell detail and the v1 → v2 delta

*RMSE ratio vs `beforeit_var_p1_constant`, rank among the 14 scored forecast columns, `all-available` track.*

| Target | h | n | v1 RMSE | v2 RMSE | v1 ratio | v2 ratio | v1 rank | v2 rank | v1 bias | **v2 bias** |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `real_gdp` | 1 | 61 | 6.2592 | 6.0879 | 0.689 | **0.670** | 4/14 | **1/14** | −1.317 | **−0.025** |
| `real_gdp` | 2 | 60 | 9.5104 | 6.1001 | 1.294 | **0.830** | 12/14 | **1/14** | −7.277 | **−0.096** |
| `real_gdp` | 4 | 58 | 6.8762 | 6.2235 | 1.082 | 0.980 | 8/14 | 3/14 | −2.938 | **−0.143** |
| `real_gdp` | 8 | 54 | 6.7381 | 6.4418 | 0.858 | 0.820 | 8/14 | 3/14 | −2.146 | **−0.119** |
| `real_gdp` | 12 | 50 | 6.9637 | 6.6510 | 1.035 | 0.988 | 10/14 | 3/14 | −2.017 | **−0.202** |
| `gdp_deflator` | 1 | 61 | 1.4288 | 1.4288 | 0.794 | 0.794 | 6/14 | 5/14 | −0.192 | −0.192 |
| `gdp_deflator` | 2 | 60 | 1.6486 | 1.6544 | 0.771 | 0.774 | 5/14 | 8/14 | −0.293 | −0.292 |
| `gdp_deflator` | 4 | 58 | 1.9398 | 1.9512 | 0.822 | 0.827 | 2/14 | 6/14 | −0.400 | −0.421 |
| `gdp_deflator` | 8 | 54 | 2.0391 | 2.0448 | 0.975 | 0.978 | 4/14 | 5/14 | −0.525 | −0.528 |
| `gdp_deflator` | 12 | 50 | 2.1093 | 2.1080 | 0.892 | 0.891 | 5/14 | 4/14 | −0.608 | −0.615 |
| `nominal_gdp` | 1 | 61 | 7.0266 | 6.8395 | 0.674 | **0.656** | 4/14 | **1/14** | −1.509 | −0.217 |
| `nominal_gdp` | 2 | 60 | 10.1803 | 6.7821 | 1.168 | **0.778** | 12/14 | **1/14** | −7.569 | −0.388 |
| `nominal_gdp` | 4 | 58 | 7.7626 | 7.0431 | 1.051 | 0.954 | 7/14 | 3/14 | −3.338 | −0.563 |
| `nominal_gdp` | 8 | 54 | 7.7071 | 7.3312 | 0.882 | 0.839 | 7/14 | 5/14 | −2.672 | −0.647 |
| `nominal_gdp` | 12 | 50 | 7.9643 | 7.5800 | 1.028 | 0.979 | 10/14 | 4/14 | −2.625 | −0.816 |
| `effective_federal_funds_rate` | 1 | 61 | 0.3734 | 0.3734 | 0.563 | 0.563 | 6/14 | 7/14 | −0.042 | −0.042 |
| `effective_federal_funds_rate` | 2 | 60 | 0.6921 | 0.6921 | 0.556 | 0.556 | 5/14 | 4/14 | −0.087 | −0.088 |
| `effective_federal_funds_rate` | 4 | 58 | 1.2188 | 1.2196 | 0.588 | 0.589 | 3/14 | 4/14 | −0.196 | −0.199 |
| `effective_federal_funds_rate` | 8 | 54 | 1.8935 | 1.8944 | 0.796 | 0.796 | 1/14 | 2/14 | −0.500 | −0.501 |
| `effective_federal_funds_rate` | 12 | 50 | 2.1670 | 2.1646 | 0.806 | 0.805 | 3/14 | 2/14 | −0.787 | −0.784 |

Four readings.

1. **The real-growth bias is essentially eliminated.** −1.32 / −7.28 / −2.94 / −2.15 / −2.02 pp becomes
   **−0.03 / −0.10 / −0.14 / −0.12 / −0.20 pp**. The residual is under a quarter of a percentage point
   at every horizon, and the mild negative drift at h=12 is consistent with the headroom mechanism of
   §7.6.
2. **The h=2 transient is gone**, with `burn_in_quarters = 0`. This retires the §5.4 hypothesis: the
   opening-row measurement basis is real, but it accounted for a small share of the −7.3 pp. The bulk
   was the rationing crash, and it disappears when the balance clears.
3. **The deflator is untouched** — bit-identical at h=1, within 0.006 of the v1 ratio at h=12, and
   slightly *worse* in rank at h=2 and h=4 only because v2 also moved the models around it. This is the
   diagnosis's central prediction confirmed out of sample: a quantity defect, not a pricing defect.
4. **The policy rate is essentially unchanged** (ratios differ in the fourth decimal). The Taylor rule
   is fed by a corrected output path, but the rate itself was never the problem.

MASE, the scale-free view, `real_gdp`: v1 1.259 / 3.361 / 1.819 / 1.629 / 1.656 → v2 **1.043 / 1.099 /
1.137 / 1.221 / 1.259**.

**The MAE asymmetry is resolved, not traded away.** The weighted MAE ratio moves 1.137 → **0.814**,
and per-cell:

| Target | v1 MAE ratio, h=1/2/4/8/12 | v2 MAE ratio, h=1/2/4/8/12 |
|---|---|---|
| `real_gdp` | 0.842 / 2.376 / 1.454 / 1.087 / 1.283 | **0.691 / 0.734 / 0.879 / 0.790 / 0.962** |
| `nominal_gdp` | 0.819 / 2.071 / 1.272 / 1.008 / 1.155 | **0.711 / 0.725 / 0.851 / 0.804 / 0.937** |
| `gdp_deflator` | 0.919 / 0.780 / 0.807 / 0.861 / 0.842 | 0.919 / 0.779 / 0.808 / 0.866 / 0.843 |
| `effective_federal_funds_rate` | 0.584 / 0.627 / 0.664 / 0.762 / 0.777 | 0.584 / 0.627 / 0.663 / 0.762 / 0.775 |

Every real- and nominal-GDP MAE ratio is now below one at every horizon. v1's weak MAE column was
neither a functional-choice artifact nor an intrinsic property of ensemble forecasting: it was the
2 pp bias, which costs MAE proportionally more than it costs RMSE.

### 7.5 Density calibration

Empirical interval coverage, pooled over all five horizons (n = 283 per target), computed from
`abm_v2_interval_coverage.csv` and verified independently for this report by n-weighted aggregation of
the per-horizon rows:

| Target | v1 5–95 % | **v2 5–95 %** | v1 10–90 % | **v2 10–90 %** | v1 25–75 % | **v2 25–75 %** |
|---|---:|---:|---:|---:|---:|---:|
| `real_gdp` | 0.654 | **0.929** | 0.580 | **0.894** | 0.300 | 0.696 |
| `nominal_gdp` | 0.661 | **0.890** | 0.548 | **0.830** | 0.332 | 0.608 |
| `gdp_deflator` | 0.742 | 0.735 | 0.703 | 0.703 | 0.449 | 0.470 |
| `effective_federal_funds_rate` | 0.509 | 0.512 | 0.431 | 0.438 | 0.247 | 0.251 |
| `unemployment_rate` | 0.509 | **0.216** | 0.375 | **0.127** | 0.177 | 0.071 |

Nominal coverage is 0.90 / 0.80 / 0.50.

**v2's real-GDP density is well calibrated at the 90 % and 80 % levels**: 0.929 and 0.894 against
nominal 0.90 and 0.80. v1's 0.654 and 0.580 were not a width problem — the intervals missed because the
point forecast was biased down by ~2 pp. Nominal GDP improves comparably (0.661 → 0.890). The 50 % band
now **over**-covers (0.696 against 0.500), i.e. the centre of the v2 ensemble is too wide.

Three targets remain badly calibrated and are named as open work:

* **`gdp_deflator`** is under-dispersed at every level (0.735 / 0.703 / 0.470) and **unchanged** by this
  work — the ensemble's inflation spread is genuinely too narrow.
* **`effective_federal_funds_rate`** under-covers badly and increasingly with horizon (0.754 at h=1 down
  to 0.200 at h=12) in both versions — the Taylor-rule path is far too tight.
* **`unemployment_rate`** coverage *falls* from 0.509 to 0.216 and reaches exactly 0.000 at h=12, which
  is the §8.2 defect appearing in the density as well as the mean.

This is a coverage assessment only. No PIT histogram, log score or CRPS was computed, so it is not a
full density evaluation (§10.6).

### 7.6 The caveat that must accompany every v2 number

`K_end/K_1 = 1.0000` in every variant: capital never accumulates, so **all of v2's extra growth comes
from draining the fixed 17.6 % opening capacity headroom.** Measured over 24 quarters at 2016Q4 (24
paths, annualised by year):

| Variant | y1 | y2 | y3 | y4 | y5 | y6 | Utilisation y1 → y6 | K24/K0 |
|---|---:|---:|---:|---:|---:|---:|---|---:|
| v1 baseline | −1.62 | −0.04 | 0.59 | 0.45 | 1.19 | 1.36 | 0.845 → 0.865 | 1.0003 |
| reconciled, budgets held (rejected) | 3.33 | 3.60 | 3.53 | 2.71 | 1.39 | **0.33** | 0.867 → **0.986** | 1.0000 |
| **v2 (`lambda` closure)** | 1.17 | 1.06 | 1.56 | 1.47 | 2.86 | 3.33 | 0.856 → **0.943** | 1.0000 |

Inside the 12-quarter scoring window this is a genuine improvement. Beyond roughly **eight to ten
years v2 must stall**, because it has consumed 0.087 of its 0.144 headroom in six. The rejected
budgets-held variant exhausts its headroom in about four years and decays to +0.33 %/yr — which is
exactly why its smaller headline bias was not taken as evidence in its favour. A capacity-expansion
term in desired investment — calibrated against the accounting identity `net I = ΔK`, **never** against
forecast RMSE — is the prerequisite for any multi-year use. **v2 is validated at h ≤ 12 only.**

---

## 8. Secondary targets and the unemployment defect

### 8.1 Nominal GDP and the effective federal funds rate

Nominal GDP growth is the exact sum of real GDP growth and deflator inflation, so it adds no
independent information but costs nothing. The policy-rate operator maps the model's internal
Taylor-rule rate to an annualized percentage point; **this is explicitly not an approved EFFR bridge**,
and the caveat travels with every number below.

| Track | v2 mean (rank of 14 columns) | v2 median | v1 mean (rank) | Best statistical |
|---|---|---|---|---|
| `all-available` | **0.716 (1st)** | 0.716 (2nd) | 0.782 (5th) | `univariate_ar_bic` 0.780 |
| `balanced h=12` | **0.703 (1st)** | 0.704 (2nd) | 0.761 (4th) | `univariate_ar_bic` 0.770 |
| `pandemic-masked` | **0.739 (2nd)** | 0.741 (3rd) | 1.124 (10th) | **`univariate_ar_p4` 0.719 (1st)** |

**The pandemic-masked loss is reported as a loss.** On the secondary pair in the calm sample, AR(4) at
0.719 beats v2 at 0.739 — a 2.8 % margin. v2 wins the other two tracks and the headline pair
everywhere, but it does not sweep the field, and the one cell where a statistical model wins outright
is stated here rather than buried.

Weighted MAE ratios follow the same pattern: v2 0.717 / 0.694 / 0.735 against v1 0.971 / 0.912 / 1.268.

### 8.2 Unemployment: an open defect that got worse

`unemployment_rate` is **excluded from every weighted score** in both versions, recorded in each
manifest with the reason *"initial unemployed stock is a length-one annual array frozen at 2024, so
every historical origin opens at the 2024 labour market"*.

**The v1 defect: a constant forecast.** Across all 61 origins at 500 paths, the h=1 unemployment
forecast ranges from **3.492 % to 3.679 %** — a span of 0.187 pp, cross-origin standard deviation
0.048 pp — against realized values spanning **3.533 % to 13.000 %**:

| Origin | v1 h=1 forecast | Actual | Error |
|---|---:|---:|---:|
| 2010Q2 | 3.664 | 9.467 | −5.803 |
| 2013Q2 | 3.679 | 7.233 | −3.554 |
| 2017Q4 | 3.641 | 4.033 | −0.393 |
| 2020Q2 | 3.636 | 8.800 | −5.164 |
| 2022Q4 | 3.639 | 3.533 | +0.105 |
| 2025Q2 | 3.564 | 4.333 | −0.769 |

Had it been scored, v1 would have ranked 1st or 2nd of the 14 columns at h=8 and h=12. **Those are not wins.** They
are a constant landing near the sample mean — and the giveaway is that `naive_historical_mean`, a
constant by construction, is the best statistical model in exactly those cells.

**The v2 defect: collapse.** Once goods rationing stops, the labour block over-heats:

| Target | h | v1 bias | **v2 bias** | v1 RMSE | **v2 RMSE** | v1 MASE | **v2 MASE** |
|---|---:|---:|---:|---:|---:|---:|---:|
| `unemployment_rate` | 1 | −1.967 | −2.091 | 2.858 | 2.947 | 7.666 | 8.077 |
| `unemployment_rate` | 2 | −0.858 | −2.383 | 2.200 | 3.128 | 5.997 | 9.258 |
| `unemployment_rate` | 4 | −0.063 | −3.118 | 1.970 | 3.693 | 5.903 | 12.177 |
| `unemployment_rate` | 8 | +0.187 | −4.386 | 1.921 | 4.807 | 5.713 | 17.276 |
| `unemployment_rate` | 12 | +0.077 | −4.731 | 1.814 | 5.051 | 5.247 | 18.754 |

End-of-horizon unemployment at four origins, 64 matched-seed paths: the reconciliation alone gives
0.76–1.11 %, and with rw-drift 0.12–0.50 %, against v1's 4.73–5.28 %. **This is not credible**, it is a
direct consequence of the fix, and it is the diagnosis's predicted side effect. `unemployment_rate` is
emitted and diagnosed but excluded from every weighted score in both versions.

**Staged future work, two separable items.** (a) Fetching historical annual CPS series
(`unemployed_census`, `employees`, `population`) via `USPipeline.collect_bls!` would remove the
frozen-stock defect and make the target scoreable at historical origins. (b) The post-reconciliation
collapse is a labour-block behavioural issue requiring its own diagnosis of the kind in §6. **(a) does
not fix (b)**, and they should not be bundled.

---

## 9. Current outlook — unscored

Origins 2025Q4 and 2026Q1, 500 paths, the reconciled artifact, zero path failures. These origins lie
beyond the end of the revised panel, so **there is no realized truth and nothing here is scored**
(`scored = false`, `realized_truth_available = false`). The §7.6 headroom caveat applies with more
force at h=12 than inside the scored window.

**Origin 2025Q4** (annualized pp, except EFFR and unemployment which are levels in pp):

| Target | h | Target period | Mean | Median | s.d. | p05 | p25 | p75 | p95 |
|---|---:|---|---:|---:|---:|---:|---:|---:|---:|
| `real_gdp` | 1 | 2026Q1 | +2.193 | +1.965 | 4.649 | −5.358 | −0.914 | +5.332 | +9.882 |
| `real_gdp` | 2 | 2026Q2 | +2.010 | +1.876 | 4.896 | −6.119 | −1.281 | +5.357 | +10.224 |
| `real_gdp` | 4 | 2026Q4 | +2.229 | +2.426 | 4.726 | −5.716 | −0.747 | +5.243 | +9.400 |
| `real_gdp` | 8 | 2027Q4 | +2.367 | +2.238 | 5.072 | −5.897 | −1.062 | +5.721 | +10.404 |
| `real_gdp` | 12 | 2028Q4 | +2.044 | +2.322 | 4.775 | −5.912 | −1.110 | +5.259 | +9.757 |
| `gdp_deflator` | 1 | 2026Q1 | +3.211 | +3.188 | 1.133 | +1.252 | +2.388 | +3.983 | +5.009 |
| `gdp_deflator` | 4 | 2026Q4 | +2.399 | +2.419 | 1.518 | −0.204 | +1.388 | +3.363 | +4.889 |
| `gdp_deflator` | 8 | 2027Q4 | +2.283 | +2.271 | 1.617 | −0.247 | +1.196 | +3.293 | +4.833 |
| `gdp_deflator` | 12 | 2028Q4 | +2.245 | +2.198 | 1.606 | −0.296 | +1.189 | +3.339 | +4.952 |
| `nominal_gdp` | 1 | 2026Q1 | +5.404 | +5.323 | 4.798 | −2.570 | +2.289 | +8.542 | +13.583 |
| `nominal_gdp` | 4 | 2026Q4 | +4.628 | +4.842 | 4.903 | −3.835 | +1.286 | +7.991 | +12.574 |
| `nominal_gdp` | 8 | 2027Q4 | +4.650 | +4.653 | 5.456 | −4.215 | +0.910 | +8.465 | +13.305 |
| `nominal_gdp` | 12 | 2028Q4 | +4.289 | +4.440 | 5.023 | −4.186 | +0.879 | +7.647 | +12.366 |
| `effective_federal_funds_rate` | 1 | 2026Q1 | 3.862 | 3.861 | 0.128 | 3.658 | 3.775 | 3.941 | 4.077 |
| `effective_federal_funds_rate` | 4 | 2026Q4 | 3.717 | 3.719 | 0.257 | 3.321 | 3.541 | 3.897 | 4.153 |
| `effective_federal_funds_rate` | 8 | 2027Q4 | 3.514 | 3.516 | 0.354 | 2.935 | 3.293 | 3.766 | 4.071 |
| `effective_federal_funds_rate` | 12 | 2028Q4 | 3.322 | 3.322 | 0.425 | 2.587 | 3.062 | 3.594 | 3.980 |
| `unemployment_rate`† | 1 | 2026Q1 | 3.434 | 3.669 | 0.665 | 2.081 | 3.231 | 3.724 | 4.217 |
| `unemployment_rate`† | 12 | 2028Q4 | 0.392 | 0.000 | 0.922 | 0.000 | 0.000 | 0.000 | 2.579 |

†Subject to §8.2 in full; it decays to zero by h=8 and is the defect, not a forecast.

**Origin 2026Q1**, headline targets:

| Target | h | Target period | Mean | Median | s.d. | p05 | p95 |
|---|---:|---|---:|---:|---:|---:|---:|
| `real_gdp` | 1 | 2026Q2 | +2.589 | +2.597 | 4.975 | −5.739 | +10.619 |
| `real_gdp` | 2 | 2026Q3 | +1.863 | +1.815 | 4.685 | −5.506 | +9.877 |
| `real_gdp` | 4 | 2027Q1 | +2.465 | +2.610 | 4.833 | −5.631 | +9.833 |
| `real_gdp` | 8 | 2028Q1 | +1.565 | +1.603 | 4.729 | −5.540 | +9.425 |
| `real_gdp` | 12 | 2029Q1 | +2.129 | +1.937 | 5.084 | −6.376 | +10.498 |
| `gdp_deflator` | 1 | 2026Q2 | +3.134 | +3.126 | 1.036 | +1.482 | +4.906 |
| `gdp_deflator` | 4 | 2027Q1 | +2.618 | +2.675 | 1.494 | +0.082 | +4.938 |
| `gdp_deflator` | 12 | 2029Q1 | +2.289 | +2.264 | 1.600 | −0.386 | +4.953 |
| `effective_federal_funds_rate` | 1 | 2026Q2 | 3.603 | 3.603 | 0.134 | 3.386 | 3.830 |
| `effective_federal_funds_rate` | 4 | 2027Q1 | 3.469 | 3.442 | 0.279 | 3.050 | 3.949 |
| `effective_federal_funds_rate` | 12 | 2029Q1 | 3.157 | 3.161 | 0.432 | 2.420 | 3.835 |

**Summary.** From the 2025Q4 origin, average real growth over h=1…4 is **+2.11 %** with a 5th–95th band
of roughly −5.5 to +10; deflator inflation runs 3.21 % at h=1, easing to 2.40 % by h=4 and ~2.25 % by
h=12; the policy rate declines from 3.86 % to 3.32 %. From 2026Q1, average real growth over h=1…4 is
**+2.31 %**, average deflator inflation **+2.86 %**, and the policy rate declines from 3.60 % to 3.47 %
by h=4 and 3.16 % by h=12.

**Two things to note when reading this.** First, **the v1 outlook's −4.9 % dive at h=2 is gone** — it
was the transient of §5.4, and it does not survive the balance fix. Second, path dispersion is large by
construction (real-GDP ensemble s.d. ≈ 4.6–5.1 pp, a 5th–95th band spanning ~16 pp), while the
Monte-Carlo standard error of the mean is ≈ 0.2 pp: the width is model dispersion, not simulation
noise, and per §7.5 the real-GDP 90 % band is close to nominal coverage in backtest while the deflator
and policy-rate bands are too narrow. The v1 outlook is superseded and retained only in
`output/us_forecasting/abm_revised_comparison_outlook/` as history.

---

## 10. Limitations and gap register

Ranked by inferential risk to the results above.

### 10.1 Capacity-headroom growth ceiling — no capital accumulation

**The most binding limitation on any forward use of v2.** Investment is replacement-only:
`I_d = δ/κ·min(Q_s, K·κ)` and `K' = K − δ/κ·Y + I` give `K' = K` exactly when firms produce at target,
and `K_end/K_1` measures 1.0000–1.0009 in every variant, including under +30 % capacity relief and
un-capped-investment emulation. v2 grows by draining the fixed 17.6 % headroom implied by the
hard-coded `ω = 0.85`; utilisation moves 0.856 → 0.943 over six years. **Within 12 quarters this is a
legitimate improvement; beyond eight to ten years it is not a growth mechanism.** Any multi-year or
scenario use requires a capacity-expansion term calibrated to `net I = ΔK`, never to forecast RMSE. The
hard-coded `ω` deserves the same treatment: sourcing it from the Federal Reserve G.17
capacity-utilisation series would be structural; sweeping it to improve RMSE would not be.

### 10.2 The labour block

Two distinct failures. **(a)** Unemployment is initialized from a frozen 2024 stock and is a constant
across origins — a mixed-vintage artifact. **(b)** Once rationing is removed, unemployment collapses to
about 1 %, and v2's unemployment scores are *worse* than v1's on every horizon. Fixing (a) does not fix
(b). The labour block needs its own diagnosis of the kind in §6 before unemployment is scored for
either version.

### 10.3 Mixed-vintage structure

The 2024 input–output structure, firm and employee counts, tax rates and population are future
information at every origin before 2024. Bounded for flow targets, fatal for stock-initialized targets.
This is the limitation that most sharply separates this exercise from the reference paper and from a
promotable result.

### 10.4 Single structural year

Even setting aside look-ahead, the model has **one** technology matrix for a fifteen-year sample. Real
changes in U.S. production structure over 2010–2025 — the energy mix, the information-sector share,
post-2020 supply-chain reconfiguration — are invisible to it by construction. This limits what the
sector-level diagnostics of §6.2 can be asked to bear, and it is a reason to treat the reconciled 2024
table as a fixed technology rather than a historical one.

### 10.5 Absent bridges: PCE, core PCE, payroll employment

Three of the eight registered targets are unserved. `pce_price_index` and `core_pce_price_index` need a
consumption-basket price bridge the 68-commodity model does not expose, and core additionally needs a
food/energy exclusion the classification does not identify cleanly. `payroll_employment` targets a CES
establishment count on a different universe from `sum(m.firms.N_i)`. None should be scored until a
bridge qualification of the kind done for the GDP operator is complete. The practical cost is that the
model is compared on five of eight targets, and the semi-structural comparator's core-four set cannot
be matched.

### 10.6 Density evaluation is partial; scale ladder not run for the headline

§7.5 reports **interval coverage only**. No PIT histogram, no log score, no CRPS, no calibration test
with a null distribution. The deflator and policy-rate intervals are demonstrably too narrow and the
real-GDP 50 % band too wide; a full density evaluation is open work. Separately, all headline results
are at `scale = 1e-5` (130 firms). The scale sweep established that the *mean* bias is invariant from
130 to 2 708 firms, but **54 of 68 sectors hold exactly one firm at this scale**, making cross-sectional
dispersion and tail behaviour unreliable. A production run at `scale ≥ 1e-4` costs ~8× runtime and
should precede any density claim.

### 10.7 No DSGE benchmark; semi-structural comparator not in the field

The reference paper compares its ABM against a DSGE model; this exercise does not. A small
New-Keynesian design exists in-repo (`scripts/us/forecasting/benchmarks/small_nk_dsge/` with
`USSmallNKDSGEMechanics.jl` and an `frbny_gensys_reference.toml`), and the FRBNY `DSGE.jl` model is the
natural external candidate. Until one is scored on this grid, "best in the field" means **best among
ten time-series benchmarks**. Adding the semi-structural Kalman comparator under the ABM's target set
is the cheaper first step.

### 10.8 Inference

No formal inference was performed: no Diebold–Mariano or HAC-adjusted test, no bootstrap, no
multiple-comparison control across the 14 forecast columns × 5 targets × 5 horizons × 3 tracks grid. The rankings
are descriptive. The v2-versus-v1 contrast is the most defensible comparison in the report because it
is matched-seed on identical cells with one deliberate change; the v2-versus-statistical-model
comparisons are not, and margins of a few per cent — such as v2's 0.830 against
`naive_historical_mean`'s 0.879 — should not be treated as established.

### 10.9 Residual reproducibility notes

`USPipeline.build_baseline!` errors with *"U.S. baseline is missing validated opening macro controls"*
and **cannot regenerate its own baselines**; the checked-in artifacts load and run correctly, so this
does not block the work, but the provenance chain is broken at the regeneration step. The reconciliation
builder is deliberately standalone and is **not** wired into `USPipeline.build_artifacts!` for that
reason. Minor: `monte_carlo_errors.csv` in the v2 output directory carries a stale
`model_family = "beforeit_abm_us_v1"` label on rows that are the v2 ensemble's own MC errors; the values
are correct, only the family string is wrong, and no reported number depends on it.

### 10.10 Pointer to stage 3

The vintage-clean design requires the annual data programme in §2.5 plus a real-time truth layer from
the existing Philadelphia Fed RTDSM capture. That is the only route to a pseudo-real-time result, and
the only route to a promotion claim.

---

## 11. Reproducibility appendix

### 11.1 Commands

```bash
# Run from the repository root. Julia 1.10.3 exactly (see below).
julia --project=scripts/us -e 'using Pkg; Pkg.instantiate()'

# 1. OPTIONAL — rebuild the reconciled calibration artifact (~40 s). The artifact is
#    committed at data/us/calibration/US_2024_calibration_object_reconciled.jld2 and
#    already matches the sha256 every v2 cache identity records (57e23f4a…), so this
#    step only re-derives what is already in the tree.
julia --project=scripts/us scripts/us/calibration/reconcile_commodity_balance.jl \
  --mode=final_demand_scaled --expectations=rw_drift

# 2. v1 and v2 ensembles, 61 origins x 500 paths each
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=scripts/us \
  scripts/us/forecasting/diagnostics/abm_revised_comparison/run_revised_data_abm_comparison.jl \
  output/us_forecasting/abm_v2_comparison/v1_headline 500 headline
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=scripts/us \
  scripts/us/forecasting/diagnostics/abm_revised_comparison/run_revised_data_abm_comparison.jl \
  output/us_forecasting/abm_v2_comparison/v2_headline 500 headline_v2

# 3. joint scoring: both ABM columns on identical common cells
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=scripts/us \
  scripts/us/forecasting/diagnostics/abm_revised_comparison/run_revised_data_abm_comparison.jl \
  output/us_forecasting/abm_v2_comparison/v2_headline 500 headline_v2 \
  --also-score=output/us_forecasting/abm_v2_comparison/v1_headline

# 4. current outlook (unscored)
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=scripts/us \
  scripts/us/forecasting/diagnostics/abm_revised_comparison/run_revised_data_abm_comparison.jl \
  output/us_forecasting/abm_v2_comparison_outlook 500 outlook_v2

# 5. tables. The third argument is the v1 run directory. It supplies the
#    `beforeit_abm_us_v1_mean` rows of `abm_v2_interval_coverage.csv` — the v1 half of
#    the §8.4 coverage comparison. Omit it and the coverage table holds v2 rows only.
julia --project=scripts/us \
  scripts/us/forecasting/diagnostics/abm_revised_comparison/report_v2_comparison.jl \
  output/us_forecasting/abm_v2_comparison/v2_headline \
  output/us_forecasting/abm_v2_comparison_outlook \
  output/us_forecasting/abm_v2_comparison/v1_headline
```

Set both environment variables yourself. `run_revised_data_benchmark_diagnostic.jl`, which produces
the statistical benchmark columns, throws `ArgumentError` unless `Threads.nthreads() == 1` and
`BLAS.get_num_threads() == 1`; the ABM comparison runner used in steps 2–4 only emits a warning, so
nothing stops an unpinned run there. Step 2 resumes from `abm_ensemble_summaries.csv`, so an
interrupted run continues rather than restarting; step 3 is a re-score off the cache (~15 s) rather
than a re-simulation. Because the ensemble caches are committed, a fresh clone reproduces the tables
from steps 3 and 5 alone; steps 2 and 4 re-simulate and are only needed to regenerate the caches
themselves.

The underlying 10-model and 11-model comparisons are reproduced by
`run_revised_data_benchmark_diagnostic.jl` and `run_revised_data_semi_structural_comparison.jl`; the
latter reproduces byte-for-byte in 13.6 s with all eight output SHA-256 digests matching the work-log
seals.

### 11.2 Artifact paths

Under `output/us_forecasting/`:

| Directory | Contents | Used in |
|---|---|---|
| `abm_v2_comparison/v2_headline/` | **the canonical scored result** — both ABM columns, 14 forecast columns, 500 paths; `manifest.toml`, `score_summaries.csv`, `relative_scores.csv`, `weighted_relative_scores.csv`, `monte_carlo_errors.csv`, `abm_v2_interval_coverage.csv`, `abm_ensemble_summaries.csv`, `abm_origin_diagnostics.csv`, `failures.csv` | §5, §7, §8 |
| `abm_v2_comparison/v1_headline/` | v1 ensemble cache, re-run under the patched tree (gate G4) | §7.2 |
| `abm_v2_comparison_outlook/` | 2025Q4 and 2026Q1 origins on the reconciled artifact, unscored | §9 |
| `commodity_balance_reconciliation/` | `reconciliation_report_rho1.txt`, `reconciliation_by_commodity_rho1.csv` | §7.1 |
| `abm_revised_comparison/` | original standalone v1 run (superseded; byte-identical to the `v1_headline` cache) | §5 |
| `abm_revised_comparison_burnin{,4}/` | burn-in sensitivities, 128 paths | §5.4 |
| `abm_revised_comparison_outlook/` | v1 outlook (superseded) | §9 |

Source modules: `scripts/us/forecasting/diagnostics/USRevisedDataBenchmarkDiagnostic.jl` (schema,
scoring, model specs, MASE, tracks); `.../abm_revised_comparison/USRevisedDataABMComparison.jl`,
`run_revised_data_abm_comparison.jl`, `report_v2_comparison.jl`, and **`RESULTS_V2.md`** (the v2 run's
own narrative, from which several tables here are cross-checked);
`scripts/us/calibration/reconcile_commodity_balance.jl`;
`scripts/us/forecasting/benchmarks/{USForecastBenchmarks.jl,bvar.jl,semi_structural.jl}`;
`scripts/us/forecasting/diagnostics/revised_data/fixtures/quarterly_panel.csv`.

### 11.3 Commit hashes and identity seals

| Commit | Content |
|---|---|
| `a55d9ed` | checkpoint before the ABM campaign; the base all gates compare against |
| `9430a4a` | v1 comparison — first-pass ABM vs statistical benchmarks |
| `cd22674` | RW-drift expectations patch (src, flag-gated, default off) |
| `b82680e` | RAS reconciliation of the opening commodity balance + reconciled artifact |
| `aadde2b` | v2 comparison run + `RESULTS_V2.md` |
| `107a9ef` | merge of the v2 line |

v2 calibration artifact and reconciliation parameters, sealed in every v2 manifest:

| Field | Value |
|---|---|
| `calibration_object_path` | `data/us/calibration/US_2024_calibration_object_reconciled.jld2` |
| `calibration_object_sha256` | `57e23f4aea54aa82319f81f1aabb4a11843890b0d20c5037e0162a4c6e514760` |
| `commodity_balance_reconciled` | `true` |
| `reconciliation_mode` | `final_demand_scaled` |
| `reconciliation_rho` | `1.0` |
| `reconciliation_lambda` | `0.9834601934561227` |
| `growth_expectation_specification` | `rw_drift` |
| `monte_carlo_paths` / `burn_in_quarters` / `simulated_quarters` | `500` / `0` / `12` |
| `model_count` | `14` |

v1 artifact (for contrast): `data/us/calibration/US_2024_calibration_object.jld2`, sha256
`4cce5d629e1776cbf67f645703d79a28108562f7f32f78b94b3dd10705e2e136`.

Panel and environment: `panel_sha256`
`f7bb26a467465937060b1e9e734a020b9158a8136db05d2e0df47c3bff851bbe`; `panel_manifest_sha256`
`fc5209e35bb0d04986c2f8c96563f0c21ad511680753ecc7e6d77f0d8435fb3f`; `panel_source_receipts_sha256`
`14bab08bb573265e0affc878cedbbb8d4a0f8f5510fc59990f92d614f109d488`; `julia_version` `1.10.3`;
`blas_threads` `1`; `julia_threads` `1`.

`reconciliation_lambda_semantics`, recorded verbatim in each manifest: *"explicit accounting choice:
the four final-demand aggregates C, G, I and X (and capital_consumption and
gross_capitalformation_dwellings, which set the investment budget) are scaled by lambda so the
artifact's expenditure aggregates match its production account and the opening commodity balance clears
exactly. lambda is fixed by the accounting identity alone and was not chosen with reference to any
forecast error."*

### 11.4 Seeds policy

* Simulation seeds are `hash((:abm_revised_v1, origin_period, path)) % 2^30` — domain-separated by
  origin and path, so no two cells share a stream.
* **v2 draws the identical seed stream as v1**, making the contrast matched-seed. The expectations
  patch consumes exactly one Normal variate on either branch to preserve this.
* `Random.seed!` is called **immediately before** `Bit.Model(...)`, because the initial microstate is
  drawn from the global RNG; seeding after construction yields a random initial state and is a silent
  error.
* A fresh model is constructed per path; `Bit.ensemblerun` is not used.
* Diagnosis and phase-1 A/B experiments use `hash((:ab, year, quarter, path))`, identical across every
  variant.
* Failed paths are counted and left visible, never resampled. `abm_path_failure_count = 0` in every run.

---

## References

Poledna, S., Miess, M. G., Hommes, C., & Rabitsch, K. (2023). Economic forecasting with an agent-based
model. *European Economic Review*, 151, 104306.

Gneiting, T. (2011). Making and evaluating point forecasts. *Journal of the American Statistical
Association*, 106(494), 746–762. — the basis for the mean/median functional split in §4.3.

---

## Reproducibility

The committed ensemble caches **are** the reproducibility artifact. Each run
directory carries `cache_identity.toml` recording the calibration artifact and its
sha256, the comparison and base-diagnostic code hashes, the panel hashes, the
requested path count, the variant, the seed-contract id and the Julia version. The
runner revalidates all of it before reusing a single cached row, and refuses by
field name on any mismatch.

Exact regeneration requires **Julia 1.10.3**. Seeds derive from `Base.hash` and are
drawn through the default global RNG; both are version-bound, so the same seed
produces a different path under a different Julia. A cross-version rerun is a new
experiment, not a reproduction of these numbers — and the identity check will say
so rather than silently reusing the cache. The U.S. scientific validation CI job
pins 1.10.3 for this reason.

Re-scoring a committed cache (seconds, no simulation):

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=scripts/us \
  scripts/us/forecasting/diagnostics/abm_revised_comparison/run_revised_data_abm_comparison.jl \
  output/us_forecasting/abm_v2_comparison/v2_headline 500 headline_v2 \
  --also-score=output/us_forecasting/abm_v2_comparison/v1_headline
```
